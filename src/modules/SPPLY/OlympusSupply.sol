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
    bytes4[3] internal SUPPLY_SUBMODULE_SELECTORS = [
        SupplySubmodule.getCollateralizedOhm.selector,
        SupplySubmodule.getProtocolOwnedBorrowableOhm.selector,
        SupplySubmodule.getProtocolOwnedLiquidityOhm.selector
    ];

    bytes4[1] internal SUPPLY_SUBMODULE_RESERVES_SELECTORS = [
        SupplySubmodule.getProtocolOwnedLiquidityReserves.selector
    ];

    //============================================================================================//
    //                                        MODULE SETUP                                        //
    //============================================================================================//
    constructor(
        Kernel kernel_,
        address[2] memory tokens_, // [ohm, gOHM]
        uint256 initialCrossChainSupply_
    ) Module(kernel_) {
        ohm = OHM(tokens_[0]);
        gohm = IgOHM(tokens_[1]);
        totalCrossChainSupply = initialCrossChainSupply_;

        // Add categories that are required for the metrics functions
        _addCategory(toCategory("protocol-owned-treasury"), false, 0x00000000, 0x00000000);
        _addCategory(toCategory("dao"), false, 0x00000000, 0x00000000);
        _addCategory(toCategory("protocol-owned-liquidity"), true, 0x8ebf7278, 0x55bdad01); // getProtocolOwnedLiquidityOhm(), getProtocolOwnedLiquidityReserves()
        _addCategory(toCategory("protocol-owned-borrowable"), true, 0x117fb54a, 0x00000000); // getProtocolOwnedBorrowableOhm()
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
        bytes4 submoduleMetricSelector_,
        bytes4 submoduleReservesSelector_
    ) external override permissioned {
        _addCategory(
            category_,
            useSubmodules_,
            submoduleMetricSelector_,
            submoduleReservesSelector_
        );
    }

    function _addCategory(
        Category category_,
        bool useSubmodules_,
        bytes4 submoduleMetricSelector_,
        bytes4 submoduleReservesSelector_
    ) internal {
        // Check if category is 0, if so revert
        if (fromCategory(category_) == bytes32(uint256(0))) revert SPPLY_InvalidParams();

        // Check if category is already approved, if so revert
        if (categoryData[category_].approved) revert SPPLY_CategoryAlreadyApproved(category_);

        // If submodules are enabled and the metric selector is empty, revert
        if (useSubmodules_ && submoduleMetricSelector_ == bytes4(0)) revert SPPLY_InvalidParams();

        // If submodules are not enabled and the metric selector is specified, revert
        if (!useSubmodules_ && submoduleMetricSelector_ != bytes4(0)) revert SPPLY_InvalidParams();

        // If submodules are not enabled and the reserves selector is specified, revert
        if (!useSubmodules_ && submoduleReservesSelector_ != bytes4(0))
            revert SPPLY_InvalidParams();

        // If submodules are enabled, check that the selector is valid
        if (useSubmodules_) {
            // Check if the metric selector is valid
            {
                bool validMetricSelector;
                uint256 len = SUPPLY_SUBMODULE_SELECTORS.length;
                for (uint256 i; i < len; ) {
                    if (SUPPLY_SUBMODULE_SELECTORS[i] == submoduleMetricSelector_) {
                        validMetricSelector = true;
                        break;
                    }
                    unchecked {
                        ++i;
                    }
                }
                if (!validMetricSelector) revert SPPLY_InvalidParams();
            }

            // If specified (since it is optional), check if the reserves selector is valid
            if (submoduleReservesSelector_ != bytes4(0)) {
                bool validReservesSelector;
                uint256 len = SUPPLY_SUBMODULE_RESERVES_SELECTORS.length;
                for (uint256 i; i < len; ) {
                    if (SUPPLY_SUBMODULE_RESERVES_SELECTORS[i] == submoduleReservesSelector_) {
                        validReservesSelector = true;
                        break;
                    }
                    unchecked {
                        ++i;
                    }
                }
                if (!validReservesSelector) revert SPPLY_InvalidParams();
            }
        }

        // Add category to list of approved categories and store category data
        categories.push(category_);
        CategoryData storage data = categoryData[category_];
        data.approved = true;
        data.useSubmodules = useSubmodules_;
        data.submoduleMetricSelector = submoduleMetricSelector_;
        data.submoduleReservesSelector = submoduleReservesSelector_;
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

    function _uncategorize(address location_) internal {
        // Check if the location is already in the category, if not revert
        if (fromCategory(categorization[location_]) == bytes32(uint256(0)))
            revert SPPLY_LocationNotCategorized(location_);

        // Remove location from list of locations
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

        // Remove from location-category mapping
        categorization[location_] = toCategory("");

        emit LocationCategorized(location_, toCategory(""));
    }

    /// @inheritdoc SPPLYv1
    function categorize(address location_, Category category) external override permissioned {
        bool toRemove = fromCategory(category) == bytes32(uint256(0));

        // Removing
        if (toRemove) {
            _uncategorize(location_);
            return;
        }

        // Check if category is approved, if not revert
        if (!categoryData[category].approved) revert SPPLY_CategoryNotApproved(category);

        // Check if the location is already in the category, if so revert
        Category existingCategorization = categorization[location_];
        if (fromCategory(existingCategorization) == fromCategory(category))
            revert SPPLY_LocationAlreadyCategorized(location_, existingCategorization);

        // Check if the location is already in a different category, if so revert
        if (fromCategory(existingCategorization) != bytes32(uint256(0)))
            revert SPPLY_LocationAlreadyCategorized(location_, existingCategorization);

        // Add to the list of tracked locations
        locations.push(location_);

        // Add to the location-category mapping
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
    function getCategoryData(
        Category category_
    ) external view virtual override returns (CategoryData memory) {
        // Check if category is approved
        if (!categoryData[category_].approved) revert SPPLY_CategoryNotApproved(category_);

        return categoryData[category_];
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
    function getCategoryByLocation(
        address location_
    ) external view virtual override returns (Category) {
        return categorization[location_];
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
        // Check if category is approved
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
        uint256 gohmBalance = gohm.balanceOf(location_);

        // Convert gOHM balance to OHM balance
        return gohmBalance != 0 ? gohm.balanceFrom(gohmBalance) : 0;
    }

    function _getSupplyByCategory(Category category_) internal view returns (uint256) {
        // Total up the supply of OHM of all locations in the category. Also accounts for gOHM.
        uint256 len = locations.length;
        uint256 supply;
        for (uint256 i; i < len; ) {
            if (fromCategory(categorization[locations[i]]) == fromCategory(category_)) {
                supply += ohm.balanceOf(locations[i]) + _getOhmForGOhmBalance(locations[i]);
            }
            unchecked {
                ++i;
            }
        }

        // Add cross-chain category supply
        CategoryData memory data = categoryData[category_];

        // If category requires data from submodules, it must be calculated and added
        if (data.useSubmodules) {
            // Iterate through submodules and add their value to the total
            // Should not include any supply that is retrievable via a simple balance lookup, which is handled by locations above
            len = submodules.length;
            for (uint256 i; i < len; ) {
                address submodule = address(_getSubmoduleIfInstalled(submodules[i]));
                (bool success, bytes memory returnData) = submodule.staticcall(
                    abi.encodeWithSelector(data.submoduleMetricSelector)
                );

                // Ensure call was successful
                if (!success)
                    revert SPPLY_SubmoduleFailed(address(submodule), data.submoduleMetricSelector);

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
    function getReservesByCategory(
        Category category_
    ) external view override returns (Reserves[] memory) {
        // Check if category is approved
        if (!categoryData[category_].approved) revert SPPLY_CategoryNotApproved(category_);

        uint256 categoryLocations;
        uint256 len = locations.length;
        // Count all locations for given category.
        for (uint256 i; i < len; ) {
            if (fromCategory(categorization[locations[i]]) == fromCategory(category_)) {
                unchecked {
                    ++categoryLocations;
                }
            }
            unchecked {
                ++i;
            }
        }

        CategoryData memory data = categoryData[category_];
        uint256 categorySubmodSources;
        // If category requires data from submodules, count all submodules and their sources.
        len = (data.useSubmodules) ? submodules.length : 0;
        for (uint256 i; i < len; ) {
            address submodule = address(_getSubmoduleIfInstalled(submodules[i]));
            (bool success, bytes memory returnData) = submodule.staticcall(
                abi.encodeWithSelector(SupplySubmodule.getSourceCount.selector)
            );

            // Ensure call was successful
            if (!success)
                revert SPPLY_SubmoduleFailed(
                    address(submodule),
                    SupplySubmodule.getSourceCount.selector
                );

            // Decode number of sources returned by the submodule
            unchecked {
                categorySubmodSources = categorySubmodSources + abi.decode(returnData, (uint256));
            }
            unchecked {
                ++i;
            }
        }

        Reserves[] memory reserves = new Reserves[](categoryLocations + categorySubmodSources);
        // Iterate through submodules and add their reserves to the return array
        // Should not include any supply that is retrievable via a simple balance lookup, which is handled by locations below
        uint256 j;
        for (uint256 i; i < len; ) {
            address submodule = address(_getSubmoduleIfInstalled(submodules[i]));
            (bool success, bytes memory returnData) = submodule.staticcall(
                abi.encodeWithSelector(data.submoduleReservesSelector)
            );

            // Ensure call was successful
            if (!success)
                revert SPPLY_SubmoduleFailed(address(submodule), data.submoduleReservesSelector);

            // Decode supply returned by the submodule
            Reserves[] memory currentReserves = abi.decode(returnData, (Reserves[]));
            uint256 current = currentReserves.length;
            for (uint256 k; k < current; ) {
                reserves[j] = currentReserves[k];
                unchecked {
                    ++j;
                    ++k;
                }
            }
            unchecked {
                ++i;
            }
        }

        address[] memory ohmTokens = new address[](1);
        ohmTokens[0] = address(ohm);
        len = locations.length;
        // Get supply from all locations in the category. Also accounts for gOHM.
        for (uint256 i; i < len; ) {
            if (fromCategory(categorization[locations[i]]) == fromCategory(category_)) {
                uint256[] memory ohmBalances = new uint256[](1);
                ohmBalances[0] = ohm.balanceOf(locations[i]) + _getOhmForGOhmBalance(locations[i]);
                reserves[j] = Reserves(locations[i], ohmTokens, ohmBalances);
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }

        return reserves;
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
        uint256 totalOhm = _totalSupply();

        return totalOhm - treasuryOhm - daoOhm;
    }

    function _floatingSupply() internal view returns (uint256) {
        uint256 polOhm = _getSupplyByCategory(toCategory("protocol-owned-liquidity"));
        uint256 borrowableOhm = _getSupplyByCategory(toCategory("protocol-owned-borrowable"));
        uint256 circulatingSupply = _circulatingSupply();

        return circulatingSupply - polOhm - borrowableOhm;
    }

    function _collateralizedSupply() internal view returns (uint256) {
        // There isn't any collateralized supply from simple balance lookups, so we forgo the supply by category call
        // Iterate through the submodules and get the collateralized supply from each lending facility
        // In general, collateralized supply can't be measured by a balance lookup since it would not be in the contract
        uint256 total;
        uint256 len = submodules.length;
        for (uint256 i; i < len; ) {
            address submodule = address(_getSubmoduleIfInstalled(submodules[i]));

            bytes4 selector = SupplySubmodule.getCollateralizedOhm.selector;
            (bool success, bytes memory returnData) = submodule.staticcall(
                abi.encodeWithSelector(selector)
            );

            // Ensure call was successful
            if (!success) revert SPPLY_SubmoduleFailed(address(submodule), selector);

            total += abi.decode(returnData, (uint256));
            unchecked {
                ++i;
            }
        }

        return total;
    }

    function _backedSupply() internal view returns (uint256) {
        uint256 floatingSupply = _floatingSupply();
        uint256 collateralizedSupply = _collateralizedSupply();

        return floatingSupply - collateralizedSupply;
    }
}
