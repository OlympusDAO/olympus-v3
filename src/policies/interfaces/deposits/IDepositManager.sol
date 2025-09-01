// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";

/// @title  Deposit Manager
/// @notice Defines an interface for a policy that manages deposits on behalf of other contracts. It is meant to be used by the facilities, and is not an end-user policy.
///
///         Key terms for the contract:
///         - Asset: an ERC20 asset that can be deposited into the contract
///         - Asset vault: an optional ERC4626 vault that assets are deposited into
///         - Asset period: the combination of an asset and deposit period
interface IDepositManager is IAssetManager {
    // ========== EVENTS ========== //

    event OperatorYieldClaimed(
        address indexed asset,
        address indexed depositor,
        address indexed operator,
        uint256 amount
    );

    // Asset Configuration Events
    event OperatorNameSet(address indexed operator, string name);

    event AssetPeriodConfigured(
        uint256 indexed receiptTokenId,
        address indexed asset,
        address indexed operator,
        uint8 depositPeriod
    );

    event AssetPeriodEnabled(
        uint256 indexed receiptTokenId,
        address indexed asset,
        address indexed operator,
        uint8 depositPeriod
    );

    event AssetPeriodDisabled(
        uint256 indexed receiptTokenId,
        address indexed asset,
        address indexed operator,
        uint8 depositPeriod
    );

    event AssetPeriodReclaimRateSet(
        address indexed asset,
        address indexed operator,
        uint8 depositPeriod,
        uint16 reclaimRate
    );

    // Borrowing Events
    event BorrowingWithdrawal(
        address indexed asset,
        address indexed operator,
        address indexed recipient,
        uint256 amount
    );

    event BorrowingRepayment(
        address indexed asset,
        address indexed operator,
        address indexed payer,
        uint256 amount
    );

    event BorrowingDefault(
        address indexed asset,
        address indexed operator,
        address indexed payer,
        uint256 amount
    );

    // ========== ERRORS ========== //

    error DepositManager_InvalidParams(string reason);

    error DepositManager_Insolvent(
        address asset,
        uint256 requiredAssets,
        uint256 depositedSharesInAssets,
        uint256 borrowedAmount
    );

    error DepositManager_ZeroAddress();

    error DepositManager_OutOfBounds();

    // Asset Configuration Errors
    error DepositManager_OperatorNameNotSet(address operator);

    error DepositManager_OperatorNameSet(address operator);

    error DepositManager_OperatorNameInvalid();

    error DepositManager_OperatorNameInUse(string name);

    error DepositManager_InvalidAssetPeriod(address asset, uint8 depositPeriod, address operator);

    error DepositManager_AssetPeriodExists(address asset, uint8 depositPeriod, address operator);

    error DepositManager_AssetPeriodEnabled(address asset, uint8 depositPeriod, address operator);

    error DepositManager_AssetPeriodDisabled(address asset, uint8 depositPeriod, address operator);

    // Borrowing Errors
    error DepositManager_BorrowingLimitExceeded(
        address asset,
        address operator,
        uint256 requested,
        uint256 available
    );

    error DepositManager_BorrowedAmountExceeded(
        address asset,
        address operator,
        uint256 amount,
        uint256 borrowed
    );

    // ========== STRUCTS ========== //

    /// @notice Parameters for the {deposit} function
    ///
    /// @param asset           The underlying ERC20 asset
    /// @param depositPeriod   The deposit period, in months
    /// @param depositor       The depositor
    /// @param amount          The amount to deposit
    /// @param shouldWrap      Whether the receipt token should be wrapped
    struct DepositParams {
        IERC20 asset;
        uint8 depositPeriod;
        address depositor;
        uint256 amount;
        bool shouldWrap;
    }

    /// @notice Parameters for the {withdraw} function
    ///
    /// @param asset            The underlying ERC20 asset
    /// @param depositPeriod    The deposit period, in months
    /// @param depositor        The depositor that is holding the receipt tokens
    /// @param recipient        The recipient of the withdrawn asset
    /// @param amount           The amount to withdraw
    /// @param isWrapped        Whether the receipt token is wrapped
    struct WithdrawParams {
        IERC20 asset;
        uint8 depositPeriod;
        address depositor;
        address recipient;
        uint256 amount;
        bool isWrapped;
    }

    /// @notice An asset period configuration, representing an asset and period combination
    ///
    /// @param isEnabled       Whether the asset period is enabled for new deposits
    /// @param depositPeriod   The deposit period, in months
    /// @param reclaimRate     The reclaim rate for the asset period (see the implementation contract for scale)
    /// @param asset           The underlying ERC20 asset
    /// @param operator        The operator that can issue this receipt token
    struct AssetPeriod {
        bool isEnabled;
        uint8 depositPeriod;
        uint16 reclaimRate;
        address asset;
        address operator;
    }

    /// @notice Status of an asset period
    ///
    /// @param isConfigured    Whether the asset period is configured
    /// @param isEnabled       Whether the asset period is enabled for new deposits
    struct AssetPeriodStatus {
        bool isConfigured;
        bool isEnabled;
    }

    /// @notice Parameters for borrowing withdrawal operations
    ///
    /// @param asset           The underlying ERC20 asset
    /// @param recipient       The recipient of the borrowed funds
    /// @param amount          The amount to borrow
    struct BorrowingWithdrawParams {
        IERC20 asset;
        address recipient;
        uint256 amount;
    }

    /// @notice Parameters for borrowing repayment operations
    ///
    /// @param asset           The underlying ERC20 asset
    /// @param payer           The address making the repayment
    /// @param amount          The amount to repay
    struct BorrowingRepayParams {
        IERC20 asset;
        address payer;
        uint256 amount;
    }

    /// @notice Parameters for borrowing default operations
    ///
    /// @param asset           The underlying ERC20 asset
    /// @param depositPeriod   The deposit period, in months
    /// @param payer           The address making the default
    /// @param amount          The amount to default
    struct BorrowingDefaultParams {
        IERC20 asset;
        uint8 depositPeriod;
        address payer;
        uint256 amount;
    }

    // ========== BORROWING FUNCTIONS ========== //

    /// @notice Borrows funds from deposits
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Validating borrowing limits and capacity
    ///         - Transferring the underlying asset from the contract to the recipient
    ///         - Updating borrowing state
    ///         - Checking solvency
    ///
    /// @param  params_         The parameters for the borrowing withdrawal
    /// @return actualAmount    The quantity of underlying assets transferred to the recipient
    function borrowingWithdraw(
        BorrowingWithdrawParams calldata params_
    ) external returns (uint256 actualAmount);

    /// @notice Repays borrowed funds
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Transferring the underlying asset from the payer to the contract
    ///         - Updating borrowing state
    ///         - Checking solvency
    ///
    /// @param  params_         The parameters for the borrowing repayment
    /// @return actualAmount    The quantity of underlying assets received from the payer
    function borrowingRepay(
        BorrowingRepayParams calldata params_
    ) external returns (uint256 actualAmount);

    /// @notice Defaults on a borrowed amount
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Burning the receipt tokens from the payer for the default amount
    ///         - Updating borrowing state
    ///         - Updating liabilities
    function borrowingDefault(BorrowingDefaultParams calldata params_) external;

    /// @notice Gets the current borrowed amount for an operator
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  operator_       The address of the operator
    /// @return borrowed        The current borrowed amount for the operator
    function getBorrowedAmount(
        IERC20 asset_,
        address operator_
    ) external view returns (uint256 borrowed);

    /// @notice Gets the available borrowing capacity for an operator
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  operator_       The address of the operator
    /// @return capacity        The available borrowing capacity for the operator
    function getBorrowingCapacity(
        IERC20 asset_,
        address operator_
    ) external view returns (uint256 capacity);

    // ========== DEPOSIT/WITHDRAW FUNCTIONS ========== //

    /// @notice Deposits the given amount of the underlying asset in exchange for a receipt token
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Transferring the underlying asset from the depositor to the contract
    ///         - Minting the receipt token to the depositor
    ///         - Updating the amount of deposited funds
    ///
    /// @param  params_         The parameters for the deposit
    /// @return receiptTokenId  The ID of the receipt token
    /// @return actualAmount    The quantity of receipt tokens minted to the depositor
    function deposit(
        DepositParams calldata params_
    ) external returns (uint256 receiptTokenId, uint256 actualAmount);

    /// @notice Returns the maximum yield that can be claimed for an asset and operator pair
    ///
    /// @param  asset_        The address of the underlying asset
    /// @param  operator_     The address of the operator
    /// @return yieldAssets   The amount of yield that can be claimed
    function maxClaimYield(
        IERC20 asset_,
        address operator_
    ) external view returns (uint256 yieldAssets);

    /// @notice Claims the yield from the underlying asset
    ///         This does not burn receipt tokens, but should reduce the amount of shares the caller has in the vault.
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Transferring the underlying asset from the contract to the recipient
    ///         - Updating the amount of deposited funds
    ///         - Checking solvency
    ///
    /// @param  asset_        The address of the underlying asset
    /// @param  recipient_    The recipient of the claimed yield
    /// @param  amount_       The amount to claim yield for
    /// @return actualAmount  The quantity of underlying assets transferred to the recipient
    function claimYield(
        IERC20 asset_,
        address recipient_,
        uint256 amount_
    ) external returns (uint256 actualAmount);

    /// @notice Withdraws the given amount of the underlying asset
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Burning the receipt token
    ///         - Transferring the underlying asset from the contract to the recipient
    ///         - Updating the amount of deposited funds
    ///
    /// @param  params_         The parameters for the withdrawal
    /// @return actualAmount    The quantity of underlying assets transferred to the recipient
    function withdraw(WithdrawParams calldata params_) external returns (uint256 actualAmount);

    /// @notice Returns the liabilities for an asset and operator pair
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  operator_       The address of the operator
    /// @return liabilities     The quantity of assets that the contract is custodying for the operator's depositors
    function getOperatorLiabilities(
        IERC20 asset_,
        address operator_
    ) external view returns (uint256 liabilities);

    // ========== OPERATOR NAMES ========== //

    /// @notice Sets the name of an operator. This is included in the name and symbol of receipt tokens.
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Setting the operator name
    ///         - Emitting an event
    function setOperatorName(address operator_, string calldata name_) external;

    /// @notice Returns the name of an operator
    ///
    /// @param  operator_   The address of the operator
    /// @return name        The name of the operator or an empty string
    function getOperatorName(address operator_) external view returns (string memory name);

    // ========== DEPOSIT CONFIGURATIONS ========== //

    /// @notice Adds a new asset
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Configuring the asset
    ///         - Emitting an event
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  vault_          The address of the ERC4626 vault to deposit the asset into (or the zero address)
    /// @param  depositCap_     The deposit cap of the asset
    /// @param  minimumDeposit_ The minimum deposit amount for the asset
    function addAsset(
        IERC20 asset_,
        IERC4626 vault_,
        uint256 depositCap_,
        uint256 minimumDeposit_
    ) external;

    /// @notice Sets the deposit cap for an asset
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Setting the deposit cap for the asset
    ///         - Emitting an event
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositCap_     The deposit cap to set for the asset
    function setAssetDepositCap(IERC20 asset_, uint256 depositCap_) external;

    /// @notice Sets the minimum deposit for an asset
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Setting the minimum deposit for the asset
    ///         - Emitting an event
    ///
    /// @param  asset_           The address of the underlying asset
    /// @param  minimumDeposit_  The minimum deposit to set for the asset
    function setAssetMinimumDeposit(IERC20 asset_, uint256 minimumDeposit_) external;

    /// @notice Adds a new asset period
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Creating a new receipt token
    ///         - Emitting an event
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @param  operator_       The address of the operator
    /// @param  reclaimRate_    The reclaim rate to set for the deposit
    /// @return receiptTokenId  The ID of the new receipt token
    function addAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_,
        uint16 reclaimRate_
    ) external returns (uint256 receiptTokenId);

    /// @notice Disables an asset period, which prevents new deposits
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Disabling the asset period
    ///         - Emitting an event
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @param  operator_       The address of the operator
    function disableAssetPeriod(IERC20 asset_, uint8 depositPeriod_, address operator_) external;

    /// @notice Enables an asset period, which allows new deposits
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Enabling the asset period
    ///         - Emitting an event
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @param  operator_       The address of the operator
    function enableAssetPeriod(IERC20 asset_, uint8 depositPeriod_, address operator_) external;

    /// @notice Returns the asset period for an asset, period and operator
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @param  operator_       The address of the operator
    /// @return configuration   The asset period
    function getAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external view returns (AssetPeriod memory configuration);

    /// @notice Returns the asset period from a receipt token ID
    ///
    /// @param  tokenId_        The ID of the receipt token
    /// @return configuration   The asset period
    function getAssetPeriod(
        uint256 tokenId_
    ) external view returns (AssetPeriod memory configuration);

    /// @notice Returns whether a deposit asset, period and operator combination are configured
    /// @dev    A asset period that is disabled will not accept further deposits
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @param  operator_       The address of the operator
    /// @return status          The status of the asset period
    function isAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external view returns (AssetPeriodStatus memory status);

    /// @notice Gets all configured asset periods
    ///
    /// @return assetPeriods    Array of configured asset periods
    function getAssetPeriods() external view returns (AssetPeriod[] memory assetPeriods);

    // ========== RECLAIM RATE ========== //

    /// @notice Sets the reclaim rate for an asset period
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Setting the reclaim rate for the asset period
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @param  operator_       The address of the operator
    /// @param  reclaimRate_    The reclaim rate to set
    function setAssetPeriodReclaimRate(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_,
        uint16 reclaimRate_
    ) external;

    /// @notice Returns the reclaim rate for an asset period
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @param  operator_       The address of the operator
    /// @return reclaimRate     The reclaim rate for the asset period
    function getAssetPeriodReclaimRate(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external view returns (uint16 reclaimRate);

    // ========== RECEIPT TOKEN FUNCTIONS ========== //

    /// @notice Returns the ID of the receipt token for an asset period and operator
    /// @dev    The ID returned is not a guarantee that the asset period is configured or enabled. {isAssetPeriod} should be used for that purpose.
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @param  operator_       The address of the operator
    /// @return receiptTokenId  The ID of the receipt token
    function getReceiptTokenId(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external view returns (uint256 receiptTokenId);

    /// @notice Convenience function that returns both receipt token ID and wrapped token address
    ///
    /// @param  asset_          The asset contract
    /// @param  depositPeriod_  The deposit period in months
    /// @param  operator_       The operator address
    /// @return tokenId         The receipt token ID
    /// @return wrappedToken    The address of the wrapped ERC20 token (0x0 if not created yet)
    function getReceiptToken(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external view returns (uint256 tokenId, address wrappedToken);

    /// @notice Gets the receipt token manager
    ///
    /// @return manager The receipt token manager contract
    function getReceiptTokenManager() external view returns (IReceiptTokenManager manager);
}
