// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import "src/Kernel.sol";

/// @notice Treasury holds all other assets under the control of the protocol.
abstract contract TRSRYv1 is Module {
    // =========  EVENTS ========= //

    event IncreaseWithdrawApproval(
        address indexed withdrawer_,
        ERC20 indexed token_,
        uint256 newAmount_
    );
    event DecreaseWithdrawApproval(
        address indexed withdrawer_,
        ERC20 indexed token_,
        uint256 newAmount_
    );
    event Withdrawal(
        address indexed policy_,
        address indexed withdrawer_,
        ERC20 indexed token_,
        uint256 amount_
    );
    event IncreaseDebtorApproval(address indexed debtor_, ERC20 indexed token_, uint256 newAmount_);
    event DecreaseDebtorApproval(address indexed debtor_, ERC20 indexed token_, uint256 newAmount_);
    event DebtIncurred(ERC20 indexed token_, address indexed policy_, uint256 amount_);
    event DebtRepaid(ERC20 indexed token_, address indexed policy_, uint256 amount_);
    event DebtSet(ERC20 indexed token_, address indexed policy_, uint256 amount_);

    // =========  ERRORS ========= //

    error TRSRY_NoDebtOutstanding();
    error TRSRY_NotActive();

    // =========  STATE ========= //

    /// @notice Status of the treasury. If false, no withdrawals or debt can be incurred.
    bool public active;

    /// @notice Mapping of who is approved for withdrawal.
    /// @dev    withdrawer -> token -> amount. Infinite approval is max(uint256).
    mapping(address => mapping(ERC20 => uint256)) public withdrawApproval;

    /// @notice Mapping of who is approved to incur debt.
    /// @dev    debtor -> token -> amount. Infinite approval is max(uint256).
    mapping(address => mapping(ERC20 => uint256)) public debtApproval;

    /// @notice Total debt for token across all withdrawals.
    mapping(ERC20 => uint256) public totalDebt;

    /// @notice Debt for particular token and debtor address
    mapping(ERC20 => mapping(address => uint256)) public reserveDebt;

    // =========  FUNCTIONS ========= //

    modifier onlyWhileActive() {
        if (!active) revert TRSRY_NotActive();
        _;
    }

    /// @notice Increase approval for specific withdrawer addresses
    function increaseWithdrawApproval(
        address withdrawer_,
        ERC20 token_,
        uint256 amount_
    ) external virtual;

    /// @notice Decrease approval for specific withdrawer addresses
    function decreaseWithdrawApproval(
        address withdrawer_,
        ERC20 token_,
        uint256 amount_
    ) external virtual;

    /// @notice Allow withdrawal of reserve funds from pre-approved addresses.
    function withdrawReserves(address to_, ERC20 token_, uint256 amount_) external virtual;

    /// @notice Increase approval for someone to accrue debt in order to withdraw reserves.
    /// @dev    Debt will generally be taken by contracts to allocate treasury funds in yield sources.
    function increaseDebtorApproval(
        address debtor_,
        ERC20 token_,
        uint256 amount_
    ) external virtual;

    /// @notice Decrease approval for someone to withdraw reserves as debt.
    function decreaseDebtorApproval(
        address debtor_,
        ERC20 token_,
        uint256 amount_
    ) external virtual;

    /// @notice Pre-approved policies can get a loan to perform operations with treasury assets.
    function incurDebt(ERC20 token_, uint256 amount_) external virtual;

    /// @notice Repay a debtor debt.
    /// @dev    Only confirmed to safely handle standard and non-standard ERC20s.
    /// @dev    Can have unforeseen consequences with ERC777. Be careful with ERC777 as reserve.
    function repayDebt(address debtor_, ERC20 token_, uint256 amount_) external virtual;

    /// @notice An escape hatch for setting debt in special cases, like swapping reserves to another token.
    function setDebt(address debtor_, ERC20 token_, uint256 amount_) external virtual;

    /// @notice Get total balance of assets inside the treasury + any debt taken out against those assets.
    function getReserveBalance(ERC20 token_) external view virtual returns (uint256);

    /// @notice Emergency shutdown of withdrawals.
    function deactivate() external virtual;

    /// @notice Re-activate withdrawals after shutdown.
    function activate() external virtual;
}

type Category is bytes32;

// solhint-disable-next-line func-visibility
function toCategory(bytes32 category_) pure returns (Category) {
    return Category.wrap(category_);
}

// solhint-disable-next-line func-visibility
function fromCategory(Category category_) pure returns (bytes32) {
    return Category.unwrap(category_);
}

type CategoryGroup is bytes32;

// solhint-disable-next-line func-visibility
function toCategoryGroup(bytes32 categoryGroup_) pure returns (CategoryGroup) {
    return CategoryGroup.wrap(categoryGroup_);
}

// solhint-disable-next-line func-visibility
function fromCategoryGroup(CategoryGroup categoryGroup_) pure returns (bytes32) {
    return CategoryGroup.unwrap(categoryGroup_);
}

abstract contract TRSRYv1_1 is TRSRYv1 {
    // ========== EVENTS ========== //
    event BalanceStored(address asset_, uint256 balance_, uint48 timestamp_);

    // ========== ERRORS ========== //
    error TRSRY_AssetNotApproved(address asset_);
    error TRSRY_AssetNotContract(address asset_);
    error TRSRY_AssetAlreadyApproved(address asset_);
    error TRSRY_BalanceCallFailed(address asset_);
    error TRSRY_InvalidParams(uint256 index, bytes params);
    error TRSRY_CategoryGroupDoesNotExist(CategoryGroup categoryGroup_);
    error TRSRY_CategoryGroupExists(CategoryGroup categoryGroup_);
    error TRSRY_CategoryExists(Category category_);
    error TRSRY_CategoryDoesNotExist(Category category_);
    error TRSRY_InvalidCalculation(address asset_, Variant variant_);
    error TRSRY_AssetNotInCategory(address asset_, Category category_);

    // ========== STATE ========== //
    enum Variant {
        CURRENT,
        LAST
    }

    struct Asset {
        bool approved;
        uint48 updatedAt;
        uint256 lastBalance;
        address[] locations;
    }

    address[] public assets;
    CategoryGroup[] public categoryGroups;
    mapping(Category => CategoryGroup) public categoryToGroup;
    mapping(CategoryGroup => Category[]) public groupToCategories;
    mapping(address => mapping(CategoryGroup => Category)) public categorization;
    mapping(address => Asset) public assetData;

    ////////////////////////////////////////////////////////////////
    //                      DATA FUNCTIONS                        //
    ////////////////////////////////////////////////////////////////

    // ========== ASSET INFORMATION ========== //

    /// @notice             Gets all the assets tracked by the treasury
    /// @return address[]   Array of all the assets
    function getAssets() external view virtual returns (address[] memory);

    /// @notice         Gets the data for a specific asset
    /// @param  asset_  Address of the asset to get the data of
    /// @return Asset   Struct of the asset's data
    function getAssetData(address asset_) external view virtual returns (Asset memory);

    /// @notice             Gets all the assets in a specific category
    /// @param  category_   Category to get the assets of
    /// @return address[]   Array of assets in the category
    function getAssetsByCategory(Category category_) public view virtual returns (address[] memory);

    /// @notice                     Returns the requested variant of the protocol balance of the asset and the timestamp at which it was calculated
    /// @param  asset_              Address of the asset to get the balance of
    /// @param  variant_            Variant of the balance to get (current or last)
    /// @return uint256             Balance of the asset
    /// @return uint48              Timestamp at which the balance was calculated
    function getAssetBalance(
        address asset_,
        Variant variant_
    ) public view virtual returns (uint256, uint48);

    /// @notice         Calculates and stores the current balance of an asset
    /// @param  asset_  Address of the asset to store the balance of
    /// @return uint256 Current balance of the asset
    function storeBalance(address asset_) external virtual returns (uint256);

    /// @notice             Gets the balance for a category by summing the balance of each asset in the category
    /// @param  category_   Category to get the balance of
    /// @param  variant_    Variant of the balance to get (current or last)
    /// @return uint256     Balance of the category
    /// @return uint48      Timestamp at which the balance was calculated
    function getCategoryBalance(
        Category category_,
        Variant variant_
    ) external view virtual returns (uint256, uint48);

    // ========== DATA MANAGEMENT ========== //

    /// @notice             Adds an asset for tracking by the treasury
    /// @dev                Asset must be a contract and must not already be approved
    /// @param  asset_      Address of the asset to add
    /// @param  locations_  Addresses of external addresses outside of the treasury that hold the asset, but should
    ///                     be considered part of the treasury balance
    function addAsset(address asset_, address[] calldata locations_) external virtual;

    /// @notice             Removes an asset from tracking by the treasury
    /// @dev                Asset must be approved
    /// @param  asset_      Address of the asset to remove
    function removeAsset(address asset_) external virtual;

    /// @notice             Adds an additional external address that holds an asset and should be considered part of
    ///                     the treasury balance
    /// @dev                Asset must already be approved and the location cannot be the zero address
    /// @param  asset_      Address of the asset to add an additional location for
    /// @param  location_   Address of the external address that holds the asset
    function addAssetLocation(address asset_, address location_) external virtual;

    /// @notice             Removes an external address that holds an asset and should no longer be considered part of the
    ///                     treasury balance
    /// @dev                Asset must already be approved
    /// @param  asset_      Address of the asset to remove a location for
    /// @param  location_   External address that holds the asset to remove tracking of
    function removeAssetLocation(address asset_, address location_) external virtual;

    /// @notice                 Adds an additional category group
    /// @dev                    Category group must not already exist
    /// @param  categoryGroup_  Category group to add
    function addCategoryGroup(CategoryGroup categoryGroup_) external virtual;

    /// @notice                 Removes a category group
    /// @dev                    Category group must exist
    /// @param  categoryGroup_  Category group to remove
    function removeCategoryGroup(CategoryGroup categoryGroup_) external virtual;

    /// @notice                 Adds an additional category
    /// @dev                    The cateogory group must exist and the category must not already exist
    /// @param  category_       Category to add
    /// @param  categoryGroup_  Category group to add the category to
    function addCategory(Category category_, CategoryGroup categoryGroup_) external virtual;

    /// @notice                 Removes a category
    /// @dev                    The category must exist
    /// @param  category_       Category to remove
    function removeCategory(Category category_) external virtual;

    /// @notice             Mark an asset as a member of specific categories
    /// @dev                This categorization is done within a category group. So for example if an asset is categorized
    ///                     as 'liquid' which is part of the 'liquidity-preference' group, but then is changed to 'illiquid'
    ///                     which falls under the same 'liquidity-preference' group, the asset will lose its 'liquid' categorization
    ///                     and gain the 'illiquid' categorization (all under the 'liquidity-preference' group).
    /// @param  asset_      Address of the asset to categorize
    /// @param  category_   Category to add the asset to
    function categorize(address asset_, Category category_) external virtual;

    /// @notice             Removes an asset from a category
    /// @dev                Asset must be approved, category must exist, and asset must be a member of the category
    /// @param  asset_      Address of the asset to remove from the category
    /// @param  category_   Category to remove the asset from
    function uncategorize(address asset_, Category category_) external virtual;
}
