// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Submodules.sol";
import {OlympusERC20Token as OHM} from "src/external/OlympusERC20.sol";
import {IgOHM} from "src/interfaces/IgOHM.sol";

type Category is bytes32;

// solhint-disable-next-line func-visibility
function toCategory(bytes32 category_) pure returns (Category) {
    return Category.wrap(category_);
}

// solhint-disable-next-line func-visibility
function fromCategory(Category category_) pure returns (bytes32) {
    return Category.unwrap(category_);
}

abstract contract SPPLYv1 is ModuleWithSubmodules {
    //============================================================================================//
    //                                          ERRORS                                            //
    //============================================================================================//
    error SPPLY_InvalidParams();
    error SPPLY_CategoryAlreadyApproved(Category category_);
    error SPPLY_CategoryNotApproved(Category category_);
    error SPPLY_CategoryInUse(Category category_);
    error SPPLY_CategorySubmoduleFailed(
        Category category_,
        uint256 submoduleIndex_,
        bytes4 selector_
    );

    //============================================================================================//
    //                                          EVENTS                                            //
    //============================================================================================//
    event CrossChainSupplyUpdated(uint256 supply_);
    event CategoryAdded(Category category_);
    event CategoryRemoved(Category category_);
    event LocationCategorized(address location_, Category category_);

    //============================================================================================//
    //                                          STATE                                             //
    //============================================================================================//

    /// @notice OHM Token
    OHM public ohm;

    /// @notice gOHM Token
    IgOHM public gOhm;

    // Cross-chain Supply

    /// @notice Total supply of OHM on other chains
    uint256 public totalCrossChainSupply;

    // Supply Categorization
    /// @notice List of addresses holding OHM that are categorized
    address[] public locations;

    /// @notice Categories
    Category[] public categories;

    struct CategoryData {
        bool approved;
        bool useSubmodules;
        bytes4 submoduleSelector; // The selector from `SupplySubmodule` to use for this category
        Cache crossChain;
        Cache total;
    }
    mapping(Category => CategoryData) public categoryData;

    /// @notice Categorization of locations
    /// @dev if a location is categorized, then it is in the locations array
    mapping(address => Category) public categorization;

    // Supply Metrics
    enum Variant {
        CURRENT,
        LAST
    }

    enum Metric {
        TOTAL_SUPPLY,
        CIRCULATING_SUPPLY,
        FLOATING_SUPPLY,
        COLLATERALIZED_SUPPLY,
        BACKED_SUPPLY
    }

    struct Cache {
        uint256 value;
        uint48 timestamp;
    }

    mapping(Metric => Cache) public metricCache;

    //============================================================================================//
    //                                       CROSS-CHAIN SUPPLY                                   //
    //============================================================================================//

    function increaseCrossChainSupply(uint256 amount_) external virtual;

    function decreaseCrossChainSupply(uint256 amount_) external virtual;

    //============================================================================================//
    //                                      SUPPLY CATEGORIZATION                                 //
    //============================================================================================//

    function addCategory(
        Category category_,
        bool useSubmodules_,
        bytes4 submoduleSelector_
    ) external virtual;

    function removeCategory(Category category_) external virtual;

    function categorize(address location_, Category category_) external virtual;

    function getLocations() external view virtual returns (address[] memory);

    function getCategories() external view virtual returns (Category[] memory);

    function getLocationsByCategory(
        Category category_
    ) external view virtual returns (address[] memory);

    function getSupplyByCategory(Category category_) external view virtual returns (uint256);

    function getSupplyByCategory(
        Category category_,
        uint48 maxAge_
    ) external view virtual returns (uint256);

    function getSupplyByCategory(
        Category category_,
        Variant variant_
    ) external view virtual returns (uint256, uint48);

    /// @notice Calculates and stores the current value of the category supply
    function storeCategorySupply(Category category_) external virtual;

    //============================================================================================//
    //                                       SUPPLY METRICS                                       //
    //============================================================================================//

    /// @notice Returns the current value of the metric
    /// @dev Optimistically uses the cached value if it has been updated this block, otherwise calculates value dynamically
    function getMetric(Metric metric_) external view virtual returns (uint256);

    /// @notice Returns a value no older than the provided age
    function getMetric(Metric metric_, uint48 maxAge_) external view virtual returns (uint256);

    /// @notice Returns the requested variant of the metric and the timestamp at which it was calculated
    function getMetric(
        Metric metric_,
        Variant variant_
    ) external view virtual returns (uint256, uint48);

    /// @notice Calculates and stores the current value of the metric
    function storeMetric(Metric metric_) external virtual;
}

abstract contract SupplySubmodule is Submodule {
    // ========== SUBMODULE SETUP ========== //
    function PARENT() public pure override returns (Keycode) {
        return toKeycode("SPPLY");
    }

    function SPPLY() internal view returns (SPPLYv1) {
        return SPPLYv1(address(parent));
    }

    // ========== DATA FUNCTIONS ========== //
    function getCollateralizedOhm() external view virtual returns (uint256);

    function getProtocolOwnedBorrowableOhm() external view virtual returns (uint256);

    function getProtocolOwnedLiquidityOhm() external view virtual returns (uint256);
}
