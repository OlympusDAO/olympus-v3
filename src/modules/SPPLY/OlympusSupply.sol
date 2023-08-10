// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/SPPLY/SPPLY.v1.sol";

// Requirements
// [X] Track total OHM supply, including other chains
// [X] Group supply into categories to provide standardized supply metrics
// [X] Get correct protocol supply data from lending protocols that OHM is integrated with
// [X] Handle OHM in liquidity pools (POL vs not)
// [X] Allow caching supply metrics

contract OlympusSupply is SPPLYv1 {
    //============================================================================================//
    //                                        MODULE SETUP                                        //
    //============================================================================================//
    constructor(
        Kernel kernel_,
        address[2] memory tokens_, // [ohm, gOHM]
        uint256 initialCrossChainSupply_
    ) Module(kernel_) {
        ohm = OHM(tokens_[0]);
        gOhm = IgOHM(tokens_[1]);
        totalCrossChainSupply = initialCrossChainSupply_;

        // Add categories that are required for the metrics functions
        _addCategory(toCategory("protocol-owned-treasury"), false, 0x00000000);
        _addCategory(toCategory("dao"), false, 0x00000000);
        _addCategory(toCategory("protocol-owned-liquidity"), true, 0x8ebf7278); // getProtocolOwnedLiquidityOhm()
        _addCategory(toCategory("protocol-owned-borrowable"), true, 0x117fb54a); // getProtocolOwnedBorrowableOhm()
    }

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("SPPLY");
    }

    /// @inheritdoc Module
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    //============================================================================================//
    //                                       CROSS-CHAIN SUPPLY                                   //
    //============================================================================================//

    /// @dev all cross-chain supply is circulating supply since it belongs to users or is in LP pools

    /// @inheritdoc SPPLYv1
    function increaseCrossChainSupply(uint256 amount_) external override permissioned {
        totalCrossChainSupply += amount_;
        emit CrossChainSupplyUpdated(totalCrossChainSupply);
    }

    /// @inheritdoc SPPLYv1
    function decreaseCrossChainSupply(uint256 amount_) external override permissioned {
        totalCrossChainSupply -= amount_;
        emit CrossChainSupplyUpdated(totalCrossChainSupply);
    }

    //============================================================================================//
    //                                       SUPPLY CATEGORIZATION                                //
    //============================================================================================//

    /// @inheritdoc SPPLYv1
    function addCategory(
        Category category_,
        bool useSubmodules_,
        bytes4 submoduleSelector_
    ) external override permissioned {
        _addCategory(category_, useSubmodules_, submoduleSelector_);
    }

    function _addCategory(
        Category category_,
        bool useSubmodules_,
        bytes4 submoduleSelector_
    ) internal {
        // Check if category is 0, if so revert
        if (fromCategory(category_) == bytes32(uint256(0))) revert SPPLY_InvalidParams();

        // Check if category is already approved, if so revert
        if (categoryData[category_].approved) revert SPPLY_CategoryAlreadyApproved(category_);

        // Add category to list of approved categories and store category data
        categories.push(category_);
        CategoryData storage data = categoryData[category_];
        data.approved = true;
        data.useSubmodules = useSubmodules_;
        data.submoduleSelector = submoduleSelector_;

        emit CategoryAdded(category_);
    }

    /// @inheritdoc SPPLYv1
    function removeCategory(Category category_) external override permissioned {
        // Check if category is approved, if not revert
        if (!categoryData[category_].approved) revert SPPLY_CategoryNotApproved(category_);

        // Check if any locations still have this category, if so revert
        address[] memory locations_ = getLocationsByCategory(category_);
        if (locations_.length > 0) revert SPPLY_CategoryInUse(category_);

        // Remove category from list of approved categories
        delete categoryData[category_];
        uint256 len = categories.length;
        for (uint256 i; i < len; ) {
            if (fromCategory(categories[i]) == fromCategory(category_)) {
                categories[i] = categories[categories.length - 1];
                categories.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
        emit CategoryRemoved(category_);
    }

    /// @inheritdoc SPPLYv1
    function categorize(address location_, Category category) external override permissioned {
        // Check if the category is approved
        if (!categoryData[category].approved) revert SPPLY_CategoryNotApproved(category);

        // If the location is not categorized yet, add to list of locations
        // If it is already categorized, remove it if the new category is 0
        if (fromCategory(categorization[location_]) == bytes32(uint256(0))) {
            locations.push(location_);
        } else if (fromCategory(category) == bytes32(uint256(0))) {
            uint256 len = locations.length;
            for (uint256 i; i < len; ) {
                if (locations[i] == location_) {
                    locations[i] = locations[locations.length - 1];
                    locations.pop();
                    break;
                }
                unchecked {
                    ++i;
                }
            }
        }

        // Categorize location
        categorization[location_] = category;
        emit LocationCategorized(location_, category);
    }

    /// @inheritdoc SPPLYv1
    function getLocations() external view override returns (address[] memory) {
        return locations;
    }

    /// @inheritdoc SPPLYv1
    function getCategories() external view override returns (Category[] memory) {
        return categories;
    }

    /// @inheritdoc SPPLYv1
    function getLocationsByCategory(
        Category category_
    ) public view override returns (address[] memory) {
        // Check if category is approved, if not revert
        if (!categoryData[category_].approved) revert SPPLY_CategoryNotApproved(category_);

        // Determine the number of locations in the category
        uint256 len = locations.length;
        uint256 count;
        for (uint256 i; i < len; ) {
            if (fromCategory(categorization[locations[i]]) == fromCategory(category_)) {
                unchecked {
                    ++count;
                }
            }
            unchecked {
                ++i;
            }
        }

        // If count is zero, return an empty array
        if (count == 0) return new address[](0);

        // Create array of locations in the category
        address[] memory locations_ = new address[](count);
        count = 0;
        for (uint256 i; i < len; ) {
            if (fromCategory(categorization[locations[i]]) == fromCategory(category_)) {
                locations_[count] = locations[i];
                unchecked {
                    ++count;
                }
            }
            unchecked {
                ++i;
            }
        }

        return locations_;
    }

    /// @inheritdoc SPPLYv1
    function getSupplyByCategory(Category category_) external view override returns (uint256) {
        // Try to use the last value, must be updated on the current timestamp
        // getSupplyByCategory checks if category is approved
        (uint256 supply, uint48 timestamp) = getSupplyByCategory(category_, Variant.LAST);
        if (timestamp == uint48(block.timestamp)) return supply;

        // If last value is stale, calculate the current value
        supply = _getSupplyByCategory(category_);
        return supply;
    }

    /// @inheritdoc SPPLYv1
    function getSupplyByCategory(
        Category category_,
        uint48 maxAge_
    ) external view override returns (uint256) {
        // Try to use the last value, must be updated more recently than maxAge
        // getSupplyByCategory checks if category is approved
        (uint256 supply, uint48 timestamp) = getSupplyByCategory(category_, Variant.LAST);
        if (timestamp >= uint48(block.timestamp) - maxAge_) return supply;

        // If last value is stale, calculate the current value
        supply = _getSupplyByCategory(category_);
        return supply;
    }

    /// @inheritdoc SPPLYv1
    function getSupplyByCategory(
        Category category_,
        Variant variant_
    ) public view override returns (uint256, uint48) {
        // Check if asset is approved
        if (!categoryData[category_].approved) revert SPPLY_CategoryNotApproved(category_);

        // Route to correct price function based on requested variant
        if (variant_ == Variant.CURRENT) {
            return (_getSupplyByCategory(category_), uint48(block.timestamp));
        } else if (variant_ == Variant.LAST) {
            Cache memory cache = categoryData[category_].total;
            return (cache.value, cache.timestamp);
        } else {
            revert SPPLY_InvalidParams();
        }
    }

    /// @notice             Returns the balance of gOHM (in terms of OHM) for the provided location
    /// @param location_    The location to get the gOHM balance for
    /// @return             The balance of gOHM (in terms of OHM) for the provided location
    function _getOhmForGOhmBalance(address location_) internal view returns (uint256) {
        // Get the gOHM balance of the location
        uint256 gOhmBalance = gOhm.balanceOf(location_);

        // Convert gOHM balance to OHM balance
        uint256 ohmBalance = gOhm.balanceFrom(gOhmBalance);

        return ohmBalance;
    }

    function _getSupplyByCategory(Category category_) internal view returns (uint256) {
        // Determine the number of locations in the category
        uint256 len = locations.length;
        uint256 count;
        for (uint256 i; i < len; ) {
            if (fromCategory(categorization[locations[i]]) == fromCategory(category_)) {
                unchecked {
                    ++count;
                }
            }
            unchecked {
                ++i;
            }
        }

        // If count is zero, return zero
        if (count == 0) return 0;

        // Total up the supply of OHM of all locations in the category
        count = 0; // TODO is this needed?
        uint256 supply;
        for (uint256 i; i < len; ) {
            if (fromCategory(categorization[locations[i]]) == fromCategory(category_)) {
                supply += ohm.balanceOf(locations[i]);
                unchecked {
                    ++count;
                }
            }
            unchecked {
                ++i;
            }
        }

        // Total up the supply of gOHM of all locations in the category
        for (uint256 i; i < len; ) {
            if (fromCategory(categorization[locations[i]]) == fromCategory(category_)) {
                supply += _getOhmForGOhmBalance(locations[i]);
            }
            unchecked {
                ++i;
            }
        }

        // Add cross-chain category supply
        CategoryData memory data = categoryData[category_];
        supply += data.crossChain.value;

        // If category requires data from submodules, it must be calculated and added
        if (data.useSubmodules) {
            // Iterate through submodules and add their value to the total
            // Should not include any supply that is retrievable via a simple balance lookup, which is handled by locations above
            len = submodules.length;
            for (uint256 i; i < len; ) {
                address submodule = address(_getSubmoduleIfInstalled(submodules[i]));
                (bool success, bytes memory returnData) = submodule.staticcall(
                    abi.encodeWithSelector(data.submoduleSelector)
                );

                // Ensure call was successful
                if (!success) revert SPPLY_CategorySubmoduleFailed(category_, i, data.submoduleSelector);

                // Decode supply returned by the submodule
                supply += abi.decode(returnData, (uint256));

                unchecked {
                    ++i;
                }
            }
        }

        return supply;
    }

    /// @inheritdoc SPPLYv1
    function storeCategorySupply(Category category_) external override permissioned {
        (uint256 supply, uint48 timestamp) = getSupplyByCategory(category_, Variant.CURRENT);
        categoryData[category_].total = Cache(supply, timestamp);
    }

    //============================================================================================//
    //                                       SUPPLY METRICS                                       //
    //============================================================================================//

    /// @inheritdoc SPPLYv1
    function getMetric(Metric metric_) external view override returns (uint256) {
        // Get the cached value of the metric
        (uint256 value, uint48 timestamp) = getMetric(metric_, Variant.LAST);

        // Try to use the last value, must be updated on the current timestamp
        if (timestamp == uint48(block.timestamp)) return value;

        // If the last value is not on the current timestamp, calculate the current value
        (value, ) = getMetric(metric_, Variant.CURRENT);

        return value;
    }

    /// @inheritdoc SPPLYv1
    function getMetric(Metric metric_, uint48 maxAge_) external view override returns (uint256) {
        // Get the cached value of the metric
        (uint256 value, uint48 timestamp) = getMetric(metric_, Variant.LAST);

        // Try to use the last value, must be no older than maxAge_
        if (timestamp >= uint48(block.timestamp) - maxAge_) return value;

        // If the last value is not on the current timestamp, calculate the current value
        (value, ) = getMetric(metric_, Variant.CURRENT);

        return value;
    }

    /// @inheritdoc SPPLYv1
    function getMetric(
        Metric metric_,
        Variant variant_
    ) public view override returns (uint256, uint48) {
        if (variant_ == Variant.LAST) {
            return (metricCache[metric_].value, metricCache[metric_].timestamp);
        } else if (variant_ == Variant.CURRENT) {
            if (metric_ == Metric.TOTAL_SUPPLY) {
                return (_totalSupply(), uint48(block.timestamp));
            } else if (metric_ == Metric.CIRCULATING_SUPPLY) {
                return (_circulatingSupply(), uint48(block.timestamp));
            } else if (metric_ == Metric.FLOATING_SUPPLY) {
                return (_floatingSupply(), uint48(block.timestamp));
            } else if (metric_ == Metric.COLLATERALIZED_SUPPLY) {
                return (_collateralizedSupply(), uint48(block.timestamp));
            } else if (metric_ == Metric.BACKED_SUPPLY) {
                return (_backedSupply(), uint48(block.timestamp));
            } else {
                revert SPPLY_InvalidParams();
            }
        } else {
            revert SPPLY_InvalidParams();
        }
    }

    function storeMetric(Metric metric_) external override permissioned {
        (uint256 result, uint48 timestamp) = getMetric(metric_, Variant.CURRENT);
        metricCache[metric_] = Cache(result, timestamp);
    }

    function _totalSupply() internal view returns (uint256) {
        return ohm.totalSupply() + totalCrossChainSupply;
    }

    function _circulatingSupply() internal view returns (uint256) {
        uint256 treasuryOhm = _getSupplyByCategory(toCategory("protocol-owned-treasury"));
        uint256 daoOhm = _getSupplyByCategory(toCategory("dao"));

        return _totalSupply() - treasuryOhm - daoOhm;
    }

    function _floatingSupply() internal view returns (uint256) {
        uint256 polOhm = _getSupplyByCategory(toCategory("protocol-owned-liquidity"));
        uint256 borrowableOhm = _getSupplyByCategory(toCategory("protocol-owned-borrowable"));
        return _circulatingSupply() - polOhm - borrowableOhm;
    }

    function _collateralizedSupply() internal view returns (uint256) {
        // There isn't any collateralized supply from simple balance lookups, so we forgo the supply by category call
        // Iterate through the submodules and get the collateralized supply from each lending facility
        // In general, collateralized supply can't be measured by a balance lookup since it would not be in the contract
        uint256 total;
        uint256 len = submodules.length;
        for (uint256 i; i < len; ) {
            total += SupplySubmodule(address(getSubmoduleForKeycode[submodules[i]]))
                .getCollateralizedOhm();
            unchecked {
                ++i;
            }
        }

        return total;
    }

    function _backedSupply() internal view returns (uint256) {
        return _floatingSupply() - _collateralizedSupply();
    }
}
