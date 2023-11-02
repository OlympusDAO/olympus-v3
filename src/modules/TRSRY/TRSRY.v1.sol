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

    function getAssets() external view virtual returns (address[] memory);

    function getAssetData(address asset_) external view virtual returns (Asset memory);

    function getAssetsByCategory(Category category_) public view virtual returns (address[] memory);

    /// @notice Returns the requested variant of the protocol balance of the asset and the timestamp at which it was calculated
    function getAssetBalance(
        address asset_,
        Variant variant_
    ) public view virtual returns (uint256, uint48);

    /// @notice Calculates and stores the current balance of an asset
    function storeBalance(address asset_) external virtual returns (uint256);

    function getCategoryBalance(
        Category category_,
        Variant variant_
    ) external view virtual returns (uint256, uint48);

    // ========== DATA MANAGEMENT ========== //
    function addAsset(address asset_, address[] calldata locations_) external virtual;

    function addAssetLocation(address asset_, address location_) external virtual;

    function removeAssetLocation(address asset_, address location_) external virtual;

    function addCategoryGroup(CategoryGroup categoryGroup_) external virtual;

    function addCategory(Category category_, CategoryGroup categoryGroup_) external virtual;

    /// @notice Mark an asset as a member of specific categories
    /// @dev    This categorization is done within a category group. So for example if an asset is categorized
    ///         as 'liquid' which is part of the 'liquidity-preference' group, but then is changed to 'illiquid'
    ///         which falls under the same 'liquidity-preference' group, the asset will lose its 'liquid' categorization
    ///         and gain the 'illiquid' categorization (all under the 'liquidity-preference' group).
    function categorize(address asset_, Category category_) external virtual;
}
