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
    error SPPLY_CategoryAlreadyApproved(Category category_);
    error SPPLY_CategoryNotApproved(Category category_);
    error SPPLY_CategoryInUse(Category category_);
    error SPPLY_InvalidParams();
    error SPPLY_LocationNotCategorized(address location_);
    error SPPLY_LocationAlreadyCategorized(address location_, Category category_);
    error SPPLY_SubmoduleFailed(address submodule_, bytes4 selector_);

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
    IgOHM public gohm;

    /// @notice Configured decimal places
    uint8 public immutable decimals = 9;

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
        /// @notice The selector from `SupplySubmodule` to use for metrics in this category
        bytes4 submoduleMetricSelector;
        /// @notice The selector from `SupplySubmodule` to use for reserves in this category
        /// @dev    Optional
        bytes4 submoduleReservesSelector;
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

    /// @notice     Struct to hold token and balance information
    struct Reserves {
        /// @notice     Source of the reserves
        address source;
        /// @notice     Ordered list of tokens
        address[] tokens;
        /// @notice     Ordered list of balances
        /// @dev        This list should be in the same order as the `tokens`, and in native decimals
        uint256[] balances;
    }

    //============================================================================================//
    //                                       CROSS-CHAIN SUPPLY                                   //
    //============================================================================================//

    function increaseCrossChainSupply(uint256 amount_) external virtual;

    function decreaseCrossChainSupply(uint256 amount_) external virtual;

    //============================================================================================//
    //                                      SUPPLY CATEGORIZATION                                 //
    //============================================================================================//

    /// @notice                             Adds a category to the list of approved categories
    /// @dev                                This function will revert if:
    ///                                     - The caller is not permissioned
    ///                                     - The category is already approved
    ///                                     - The category name is empty
    ///
    ///                                      This function will emit the `CategoryAdded` event if successful
    ///
    /// @param category_                    The category to add
    /// @param useSubmodules_               Whether or not to use submodules for this category
    /// @param submoduleMetricSelector_           The selector from `SupplySubmodule` to use for the metrics of this category
    /// @param submoduleReservesSelector_   The selector from `SupplySubmodule` to use for the reserves of this category
    function addCategory(
        Category category_,
        bool useSubmodules_,
        bytes4 submoduleMetricSelector_,
        bytes4 submoduleReservesSelector_
    ) external virtual;

    /// @notice                     Removes a category from the list of approved categories
    /// @dev                        This function will revert if:
    ///                             - The caller is not permissioned
    ///                             - The category is not approved
    ///                             - The category has locations assigned to it
    ///
    ///                             This function will emit the `CategoryRemoved` event if successful
    ///
    /// @param category_            The category to remove
    function removeCategory(Category category_) external virtual;

    /// @notice                     Adds or removes a location to a category
    /// @dev                        To add a location to a category, pass in the address and category
    ///
    ///                             To remove a location from all categories, pass in the address and an empty category
    ///
    ///                             This function will revert if:
    ///                             - The caller is not permissioned
    ///                             - The category is not approved
    ///                             - The location is already in the same category
    ///                             - The location is not in the specified category and the category is empty
    ///
    ///                             This function will emit the `LocationCategorized` event if successful
    ///
    /// @param location_            The address to categorize
    /// @param category_            The category to add the location to
    function categorize(address location_, Category category_) external virtual;

    /// @notice Returns the locations that are categorized
    ///
    /// @return An array of addresses
    function getLocations() external view virtual returns (address[] memory);

    /// @notice Returns the identifiers of the configured categories
    ///
    /// @return An array of Category identifiers
    function getCategories() external view virtual returns (Category[] memory);

    /// @notice             Returns the data for a specific category
    /// @dev                Will revert if:
    ///                     - The category is not approved
    ///
    /// @param category_    The category to query
    /// @return             The category data
    function getCategoryData(
        Category category_
    ) external view virtual returns (CategoryData memory);

    /// @notice             Returns the category for a location
    ///
    /// @param location_    The location to query
    /// @return             The category identifier
    function getCategoryByLocation(address location_) external view virtual returns (Category);

    /// @notice             Returns the locations configured for a category
    /// @dev                Will revert if:
    ///                     - The category is not approved
    ///
    /// @param category_    The category to query
    /// @return             An array of addresses
    function getLocationsByCategory(
        Category category_
    ) external view virtual returns (address[] memory);

    /// @notice             Returns the OHM supply for a category
    /// @dev                This function will first attempt to return the cached value for the current
    ///                     timestamp, if available. Otherwise, it will re-calculate the value.
    ///
    ///                     Will revert if:
    ///                     - The category is not approved
    ///
    /// @param category_    The category to query
    /// @return             The OHM supply for the category in the configured decimals
    function getSupplyByCategory(Category category_) external view virtual returns (uint256);

    /// @notice             Returns the OHM supply for a category no older than the provided age
    /// @dev                This function will first check the validity of the last-cached value.
    ///                     Otherwise, it will re-calculate the value.
    ///
    ///                     Will revert if:
    ///                     - The category is not approved
    ///
    /// @param category_    The category to query
    /// @param maxAge_      The maximum age (in seconds) of the cached value
    /// @return             The OHM supply for the category in the configured decimals
    function getSupplyByCategory(
        Category category_,
        uint48 maxAge_
    ) external view virtual returns (uint256);

    /// @notice             Returns OHM supply for a category with the requested variant
    /// @dev                Will revert if:
    ///                     - The category is not approved
    ///
    /// @param category_    The category to query
    /// @param variant_     The variant to query
    /// @return             The OHM supply for the category in the configured decimals and the timestamp at which it was calculated
    function getSupplyByCategory(
        Category category_,
        Variant variant_
    ) external view virtual returns (uint256, uint48);

    /// @notice             Calculates and stores the current value of the category supply
    /// @dev                Will revert if:
    ///                     - The category is not approved
    ///
    /// @param category_    The category to query
    function storeCategorySupply(Category category_) external virtual;

    /// @notice             Returns the underlying reserves for a category
    function getReservesByCategory(
        Category category_
    ) external view virtual returns (Reserves[] memory);

    //============================================================================================//
    //                                       SUPPLY METRICS                                       //
    //============================================================================================//

    /// @notice         Returns the current value of the metric
    /// @dev            Optimistically uses the cached value if it has been updated this block, otherwise calculates value dynamically
    ///
    ///                 Will revert if:
    ///                 - The value for `metric_` is invalid
    ///
    /// @param metric_  The metric to query
    /// @return         The value of the metric in the module's configured decimals
    function getMetric(Metric metric_) external view virtual returns (uint256);

    /// @notice         Returns a metric value no older than the provided age
    /// @dev            If the cached value is older than the provided age, then the value is calculated dynamically
    ///
    ///                 Will revert if:
    ///                 - The value for `metric_` is invalid
    ///
    /// @param metric_  The metric to query
    /// @param maxAge_  The maximum age (in seconds) of the cached value
    /// @return         The value of the metric in the module's configured decimals
    function getMetric(Metric metric_, uint48 maxAge_) external view virtual returns (uint256);

    /// @notice         Returns the requested variant of the metric and the timestamp at which it was calculated
    /// @dev            If the `Variant.LAST` variant is requested and it has not yet been stored, then (0, 0) will be returned.
    ///
    ///                 Will revert if:
    ///                 - The value for `metric_` is invalid
    ///                 - The value for `variant_` is invalid
    ///
    /// @param metric_  The metric to query
    /// @param variant_ The variant to query
    /// @return         The value of the metric in the module's configured decimals and the timestamp at which it was calculated
    function getMetric(
        Metric metric_,
        Variant variant_
    ) external view virtual returns (uint256, uint48);

    /// @notice         Calculates and stores the current value of the metric
    ///
    ///                 Will revert if:
    ///                 - The value for `metric_` is invalid
    ///
    /// @param metric_  The metric to query
    function storeMetric(Metric metric_) external virtual;
}

abstract contract SupplySubmodule is Submodule {
    // ========== SUBMODULE SETUP ========== //

    /// @inheritdoc Submodule
    function PARENT() public pure override returns (Keycode) {
        return toKeycode("SPPLY");
    }

    /// @notice The parent SPPLY module
    function _SPPLY() internal view returns (SPPLYv1) {
        return SPPLYv1(address(parent));
    }

    // ========== DATA FUNCTIONS ========== //

    /// @notice     Quantity of collateralized OHM
    /// @dev        Definition: The quantity of OHM minted against collateral provided by borrowers or liquidity stakers and not backed by treasury assets.
    ///
    /// @return     Quantity in the configured decimals
    function getCollateralizedOhm() external view virtual returns (uint256);

    /// @notice     Quantity for protocol owned borrowable OHM
    /// @dev        Definition: The quantity of OHM minted against treasury assets and not backed by collateral provided by borrowers or liquidity stakers.
    ///
    /// @return     Quantity in the configured decimals
    function getProtocolOwnedBorrowableOhm() external view virtual returns (uint256);

    /// @notice     Quantity for protocol owned liquidity OHM
    /// @dev        Definition: The quantity of OHM minted against treasury assets and present in liquidity pools.
    ///
    /// @return     Quantity in the configured decimals
    function getProtocolOwnedLiquidityOhm() external view virtual returns (uint256);

    /// @notice     Details of Protocol-Owned Liquidity Reserves in the assets monitored by the submodule
    /// @dev        This provides the details of OHM and non-OHM reserves in the submodule,
    ///             and can be used to determine the market and backing value of a category.
    ///
    /// @return     A Reserves struct
    function getProtocolOwnedLiquidityReserves()
        external
        view
        virtual
        returns (SPPLYv1.Reserves[] memory);

    /// @notice     Number of supply sources monitored by the submodule
    /// @dev        Useful for know the number of sources for `getProtocolOwnedLiquidityReserves()` in advance.
    ///
    /// @return     Number of supply sources monitored by the submodule
    function getSourceCount() external view virtual returns (uint256);
}
