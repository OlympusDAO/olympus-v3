// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(asm-keccak256)
pragma solidity >=0.8.20;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";

// Bophades
import {Kernel, Policy} from "src/Kernel.sol";
import {ReentrancyGuard} from "@openzeppelin-5.3.0/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {DEPOSv1} from "src/modules/DEPOS/DEPOS.v1.sol";

/// @title Base Deposit Facility
/// @notice Abstract base contract for deposit facilities with shared functionality
abstract contract BaseDepositFacility is Policy, PolicyEnabler, IDepositFacility, ReentrancyGuard {
    using FullMath for uint256;
    using TransferHelper for ERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ========== CONSTANTS ========== //

    /// @notice The number representing 100%
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    // ========== STATE VARIABLES ========== //

    /// @notice The deposit manager
    IDepositManager public immutable DEPOSIT_MANAGER;

    /// @notice Set of authorized operators
    EnumerableSet.AddressSet private _authorizedOperators;

    /// @notice The amount of assets committed, excluding the assets that have been lent out
    mapping(IERC20 asset => uint256 committedDeposits) private _assetCommittedDeposits;

    /// @notice The amount of assets committed per operator, excluding the assets that have been lent out
    mapping(bytes32 assetOperatorKey => uint256 committedDeposits)
        private _assetOperatorCommittedDeposits;

    /// @notice The TRSRY module
    /// @dev    Must be populated by the inheriting contract in `configureDependencies()`
    TRSRYv1 public TRSRY;

    /// @notice The DEPOS module.
    /// @dev    Must be populated by the inheriting contract in `configureDependencies()`
    DEPOSv1 public DEPOS;

    /// @notice Maps asset-period key to reclaim rate
    /// @dev    The key is the keccak256 of the asset address and the deposit period
    mapping(bytes32 key => uint16 reclaimRate) private _assetPeriodReclaimRates;

    // ========== MODIFIERS ========== //

    /// @notice Reverts if the caller is not an authorized operator
    modifier onlyAuthorizedOperator() {
        if (!_authorizedOperators.contains(msg.sender)) {
            revert DepositFacility_UnauthorizedOperator(msg.sender);
        }
        _;
    }

    // ========== CONSTRUCTOR ========== //

    constructor(address kernel_, address depositManager_) Policy(Kernel(kernel_)) {
        DEPOSIT_MANAGER = IDepositManager(depositManager_);
    }

    // ========== AUTHORIZATION ========== //

    /// @inheritdoc IDepositFacility
    function authorizeOperator(address operator_) external onlyEnabled onlyAdminRole {
        // Validate not zero address or existing
        if (operator_ == address(0) || _authorizedOperators.contains(operator_))
            revert DepositFacility_InvalidAddress(operator_);

        _authorizedOperators.add(operator_);
        emit OperatorAuthorized(operator_);
    }

    /// @inheritdoc IDepositFacility
    function deauthorizeOperator(address operator_) external onlyEnabled onlyEmergencyOrAdminRole {
        // Validate authorized
        if (!_authorizedOperators.contains(operator_))
            revert DepositFacility_InvalidAddress(operator_);

        _authorizedOperators.remove(operator_);
        emit OperatorDeauthorized(operator_);
    }

    /// @inheritdoc IDepositFacility
    function isAuthorizedOperator(address operator_) external view returns (bool) {
        return _authorizedOperators.contains(operator_);
    }

    /// @inheritdoc IDepositFacility
    function getOperators() external view returns (address[] memory operators) {
        return _authorizedOperators.values();
    }

    // ========== CALLBACKS ========== //

    function _getCommittedDepositsKey(
        IERC20 depositToken_,
        address operator_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(address(depositToken_), operator_));
    }

    /// @notice Helper function to generate the key for asset period reclaim rates
    /// @param asset_ The asset address
    /// @param depositPeriod_ The deposit period in months
    /// @return The keccak256 hash of the asset and deposit period
    function _getAssetPeriodKey(
        IERC20 asset_,
        uint8 depositPeriod_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(address(asset_), depositPeriod_));
    }

    /// @inheritdoc IDepositFacility
    /// @dev        This function will revert if:
    ///             - This contract is not enabled
    ///             - The caller is not an authorized operator
    ///             - The deposit token or period are not supported for this facility in the DepositManager
    ///             - There are not enough available deposits in the DepositManager
    function handleCommit(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) external nonReentrant onlyEnabled onlyAuthorizedOperator {
        // Validate that the amount is not zero
        if (amount_ == 0) revert DepositFacility_ZeroAmount();

        // Validate that the deposit token and period are supported
        if (
            !DEPOSIT_MANAGER
                .isAssetPeriod(depositToken_, depositPeriod_, address(this))
                .isConfigured
        )
            revert IDepositManager.DepositManager_InvalidAssetPeriod(
                address(depositToken_),
                depositPeriod_,
                address(this)
            );

        // Validate that there are enough uncommitted funds
        uint256 availableDeposits = getAvailableDeposits(depositToken_);
        if (amount_ > availableDeposits)
            revert DepositFacility_InsufficientDeposits(amount_, availableDeposits);

        // Record the commitment
        _assetOperatorCommittedDeposits[
            _getCommittedDepositsKey(depositToken_, msg.sender)
        ] += amount_;
        _assetCommittedDeposits[depositToken_] += amount_;

        // Emit event
        emit AssetCommitted(address(depositToken_), msg.sender, amount_);
    }

    /// @inheritdoc IDepositFacility
    /// @dev        This function will revert if:
    ///             - This contract is not enabled
    ///             - The caller is not an authorized operator
    ///             - The amount is greater than the committed deposits for the operator
    function handleCommitCancel(
        IERC20 depositToken_,
        uint8,
        uint256 amount_
    ) external nonReentrant onlyEnabled onlyAuthorizedOperator {
        // Validate that the amount is not zero
        if (amount_ == 0) revert DepositFacility_ZeroAmount();

        // Validate that there are enough committed funds
        uint256 operatorCommitments = getCommittedDeposits(depositToken_, msg.sender);
        if (amount_ > operatorCommitments)
            revert DepositFacility_InsufficientCommitment(msg.sender, amount_, operatorCommitments);

        // Reduce the commitment
        _assetOperatorCommittedDeposits[
            _getCommittedDepositsKey(depositToken_, msg.sender)
        ] -= amount_;
        _assetCommittedDeposits[depositToken_] -= amount_;

        // Emit event
        emit AssetCommitCancelled(address(depositToken_), msg.sender, amount_);
    }

    /// @inheritdoc IDepositFacility
    /// @dev        This function will revert if:
    ///             - This contract is not enabled
    ///             - The caller is not an authorized operator
    ///             - The amount is greater than the committed deposits for the operator
    function handleCommitWithdraw(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address recipient_
    ) external nonReentrant onlyEnabled onlyAuthorizedOperator returns (uint256) {
        // Validate that there are enough committed funds for the operator
        uint256 operatorCommitments = getCommittedDeposits(depositToken_, msg.sender);
        if (amount_ > operatorCommitments)
            revert DepositFacility_InsufficientCommitment(msg.sender, amount_, operatorCommitments);

        // Validate that the amount is not zero
        if (amount_ == 0) revert DepositFacility_ZeroAmount();

        // Reduce the commitment
        // The input amount is used here, in order to avoid having residual values
        // (which the calling operator has no control over)
        _assetOperatorCommittedDeposits[
            _getCommittedDepositsKey(depositToken_, msg.sender)
        ] -= amount_;
        _assetCommittedDeposits[depositToken_] -= amount_;

        // Process the withdrawal through DepositManager
        uint256 actualAmount = DEPOSIT_MANAGER.withdraw(
            IDepositManager.WithdrawParams({
                asset: depositToken_,
                depositPeriod: depositPeriod_,
                depositor: msg.sender,
                recipient: recipient_,
                amount: amount_,
                isWrapped: false
            })
        );

        // Validate that the amount is not zero
        if (actualAmount == 0) revert DepositFacility_ZeroAmount();

        // Emit event
        emit AssetCommitWithdrawn(address(depositToken_), msg.sender, actualAmount);

        return actualAmount;
    }

    /// @inheritdoc IDepositFacility
    /// @dev        This function will revert if:
    ///             - This contract is not enabled
    ///             - The caller is not an authorized operator
    ///             - The amount is greater than the committed deposits for the operator
    function handleBorrow(
        IERC20 depositToken_,
        uint8,
        uint256 amount_,
        address recipient_
    ) external nonReentrant onlyEnabled onlyAuthorizedOperator returns (uint256) {
        // Validate that there are enough committed funds for the operator
        uint256 operatorCommitments = getCommittedDeposits(depositToken_, msg.sender);
        if (amount_ > operatorCommitments)
            revert DepositFacility_InsufficientCommitment(msg.sender, amount_, operatorCommitments);

        // Process the borrowing through DepositManager
        // It will revert if more is being borrowed than available
        uint256 actualAmount = DEPOSIT_MANAGER.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: depositToken_,
                recipient: recipient_,
                amount: amount_
            })
        );

        // Reduce committed deposits
        // This uses the requested amount, to be consistent with DepositManager
        _assetOperatorCommittedDeposits[
            _getCommittedDepositsKey(depositToken_, msg.sender)
        ] -= amount_;
        _assetCommittedDeposits[depositToken_] -= amount_;

        // Validate that the amount is not zero
        if (actualAmount == 0) revert DepositFacility_ZeroAmount();

        return actualAmount;
    }

    /// @inheritdoc IDepositFacility
    /// @dev        This function performs the following:
    ///             - Updates the committed deposits
    ///
    ///             This function will revert if:
    ///             - This contract is not enabled
    ///             - The caller is not an authorized operator
    function handleLoanRepay(
        IERC20 depositToken_,
        uint8,
        uint256 amount_,
        address payer_
    ) external nonReentrant onlyEnabled onlyAuthorizedOperator returns (uint256) {
        // Process the repayment through DepositManager
        // It will revert if more is being repaid than borrowed
        uint256 repaymentActual = DEPOSIT_MANAGER.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: depositToken_,
                payer: payer_,
                amount: amount_
            })
        );

        // Repayment of a principal amount increases the committed deposits (since it was deducted in `handleBorrow()`
        // This uses the requested amount, to be consistent with DepositManager
        _assetOperatorCommittedDeposits[
            _getCommittedDepositsKey(depositToken_, msg.sender)
        ] += amount_;
        _assetCommittedDeposits[depositToken_] += amount_;

        // Validate that the amount is not zero
        if (repaymentActual == 0) revert DepositFacility_ZeroAmount();

        return repaymentActual;
    }

    /// @inheritdoc IDepositFacility
    /// @dev        This function will revert if:
    ///             - This contract is not enabled
    ///             - The caller is not an authorized operator
    function handleLoanDefault(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address payer_
    ) external nonReentrant onlyEnabled onlyAuthorizedOperator {
        // Validate that the amount is not zero
        if (amount_ == 0) revert DepositFacility_ZeroAmount();

        // Default has no impact on the committed deposits
        // The amount has already been lent out,
        // and committed deposits have been decreased accordingly

        // Process the default through DepositManager
        // It will revert if more is being defaulted than borrowed
        DEPOSIT_MANAGER.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: depositToken_,
                depositPeriod: depositPeriod_,
                payer: payer_,
                amount: amount_
            })
        );
    }

    /// @inheritdoc IDepositFacility
    function handlePositionRedemption(
        uint256 positionId_,
        uint256 amount_
    ) external nonReentrant onlyEnabled onlyAuthorizedOperator {
        // Validate that the amount is not zero
        if (amount_ == 0) revert DepositFacility_ZeroAmount();

        // Get position to validate it exists and get current remainingDeposit
        IDepositPositionManager.Position memory position = DEPOS.getPosition(positionId_);

        // Validate that this facility is the operator of the position
        if (position.operator != address(this))
            revert IDepositPositionManager.DEPOS_InvalidParams("operator");

        // Validate that the amount is not greater than remaining deposit
        if (amount_ > position.remainingDeposit)
            revert IDepositPositionManager.DEPOS_InvalidParams("amount");

        // Update the position's remaining deposit
        DEPOS.setRemainingDeposit(positionId_, position.remainingDeposit - amount_);
    }

    /// @inheritdoc IDepositFacility
    function handlePositionCancelRedemption(
        uint256 positionId_,
        uint256 amount_
    ) external nonReentrant onlyEnabled onlyAuthorizedOperator {
        // Validate that the amount is not zero
        if (amount_ == 0) revert DepositFacility_ZeroAmount();

        // Get position to validate it exists and get current remainingDeposit
        IDepositPositionManager.Position memory position = DEPOS.getPosition(positionId_);

        // Validate that this facility is the operator of the position
        if (position.operator != address(this))
            revert IDepositPositionManager.DEPOS_InvalidParams("operator");

        // Update the position's remaining deposit
        DEPOS.setRemainingDeposit(positionId_, position.remainingDeposit + amount_);
    }

    /// @inheritdoc IDepositFacility
    function getAvailableDeposits(IERC20 depositToken_) public view returns (uint256) {
        // Asset liabilities are used as the excess (sharesInAssets - liabilities) is not accessible anyway
        uint256 assetLiabilities = DEPOSIT_MANAGER.getOperatorLiabilities(
            depositToken_,
            address(this)
        );
        uint256 borrowedAmount = DEPOSIT_MANAGER.getBorrowedAmount(depositToken_, address(this));

        // Committed deposits does not include the assets that have been lent out
        uint256 committedDeposits = _assetCommittedDeposits[depositToken_];

        // This should not happen, but prevent a revert anyway
        if (committedDeposits + borrowedAmount > assetLiabilities) return 0;

        return assetLiabilities - committedDeposits - borrowedAmount;
    }

    /// @inheritdoc IDepositFacility
    /// @dev        The amount is calculated as:
    ///             - The amount of deposits that have been committed (via `handleCommit()`) for the deposit token and operator
    ///             - Minus: the amount of loan principal currently outstanding for the operator
    function getCommittedDeposits(
        IERC20 depositToken_,
        address operator_
    ) public view returns (uint256) {
        return _assetOperatorCommittedDeposits[_getCommittedDepositsKey(depositToken_, operator_)];
    }

    /// @inheritdoc IDepositFacility
    /// @dev        The amount returned is calculated as:
    ///             - The amount of deposits that have been committed (via `handleCommit()`) for the deposit token
    ///             - Minus: the amount of loan principal currently outstanding
    function getCommittedDeposits(IERC20 depositToken_) public view returns (uint256) {
        return _assetCommittedDeposits[depositToken_];
    }

    // ========== RECLAIM ========== //

    function _validateAvailableDeposits(IERC20 depositToken_, uint256 amount_) internal view {
        uint256 availableDeposits = getAvailableDeposits(depositToken_);

        if (amount_ > availableDeposits)
            revert DepositFacility_InsufficientDeposits(amount_, availableDeposits);
    }

    function _previewReclaim(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) internal view returns (uint256 reclaimed) {
        // This is rounded down to keep assets in the vault, otherwise the contract may end up
        // in a state where there are not enough of the assets in the vault to redeem/reclaim
        reclaimed = amount_.mulDiv(
            _assetPeriodReclaimRates[_getAssetPeriodKey(depositToken_, depositPeriod_)],
            ONE_HUNDRED_PERCENT
        );

        // If the reclaimed amount is 0, revert
        if (reclaimed == 0) revert DepositFacility_ZeroAmount();

        return reclaimed;
    }

    /// @inheritdoc IDepositFacility
    function previewReclaim(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) public view onlyEnabled returns (uint256 reclaimed) {
        // Validate that the amount is not 0
        if (amount_ == 0) revert DepositFacility_ZeroAmount();

        // Validate that there are enough available deposits
        _validateAvailableDeposits(depositToken_, amount_);

        return _previewReclaim(depositToken_, depositPeriod_, amount_);
    }

    /// @inheritdoc IDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not active
    ///             - Deposits are not enabled for the asset/period
    ///             - The depositor has not approved the DepositManager to spend the receipt token
    ///             - The depositor has an insufficient balance of the receipt token
    function reclaim(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) external nonReentrant onlyEnabled returns (uint256 reclaimed) {
        // Validate that the amount is not 0
        if (amount_ == 0) revert DepositFacility_ZeroAmount();

        // Validate that there are enough available deposits
        _validateAvailableDeposits(depositToken_, amount_);

        // Withdraw the deposit
        uint256 actualAmount = DEPOSIT_MANAGER.withdraw(
            IDepositManager.WithdrawParams({
                asset: depositToken_,
                depositPeriod: depositPeriod_,
                depositor: msg.sender,
                recipient: address(this),
                amount: amount_,
                isWrapped: false
            })
        );

        // Calculate the quantity of deposit token to withdraw and return
        // This will create a difference between the quantity of deposit tokens and the vault shares, which will be swept as yield
        uint256 discountedAssetsOut = _previewReclaim(depositToken_, depositPeriod_, actualAmount);

        // Transfer discounted amount of the deposit token to the recipient
        ERC20(address(depositToken_)).safeTransfer(msg.sender, discountedAssetsOut);

        // Transfer the remaining deposit tokens to the TRSRY
        ERC20(address(depositToken_)).safeTransfer(
            address(TRSRY),
            actualAmount - discountedAssetsOut
        );

        // Emit event
        emit Reclaimed(
            msg.sender,
            address(depositToken_),
            depositPeriod_,
            discountedAssetsOut,
            actualAmount - discountedAssetsOut
        );

        return discountedAssetsOut;
    }

    // ========== POSITION MANAGEMENT ========== //

    /// @inheritdoc IDepositFacility
    /// @dev        This function reverts if:
    ///             - The position does not exist
    ///             - The position was not created by this facility
    ///             - The caller is not the owner of the position
    function split(
        uint256 positionId_,
        uint256 amount_,
        address to_,
        bool wrap_
    ) external nonReentrant onlyEnabled returns (uint256) {
        // Get the position. This will revert if the position does not exist.
        IDepositPositionManager.Position memory position = DEPOS.getPosition(positionId_);

        // Validate that the position was created by this facility
        if (position.operator != address(this))
            revert IDepositPositionManager.DEPOS_NotOperator(positionId_);

        // Validate that the caller is the owner of the position
        if (position.owner != msg.sender)
            revert IDepositPositionManager.DEPOS_NotOwner(positionId_);

        // Validate that the amount is valid
        if (amount_ == 0 || amount_ > position.remainingDeposit)
            revert IDepositPositionManager.DEPOS_InvalidParams("amount");

        uint256 minimumDeposit = DEPOSIT_MANAGER
            .getAssetConfiguration(IERC20(position.asset))
            .minimumDeposit;
        // Validate minimum deposit if set
        if (minimumDeposit > 0) {
            // Validate that the new position amount is >= the minimum deposit
            if (amount_ < minimumDeposit) {
                revert IAssetManager.AssetManager_MinimumDepositNotMet(
                    position.asset,
                    amount_,
                    minimumDeposit
                );
            }
            // Validate that the remaining position amount is >= the minimum deposit
            // No risk of underflow here, as it has been validated that amount_ < position.remainingDeposit
            if (position.remainingDeposit - amount_ < minimumDeposit) {
                revert IAssetManager.AssetManager_MinimumDepositNotMet(
                    position.asset,
                    position.remainingDeposit - amount_,
                    minimumDeposit
                );
            }
        }

        // Perform the split
        // This will revert if the amount is 0 or greater than the position amount
        uint256 newPositionId = DEPOS.split(positionId_, amount_, to_, wrap_);

        // Allow inheriting contracts to perform custom actions when a position is split
        _split(positionId_, newPositionId, amount_);

        return newPositionId;
    }

    /// @notice     Internal function to handle the splitting of a position
    /// @dev        Inheriting contracts can implement this function to perform custom actions when a position is split. This function is called after the position is split, so beware of reentrancy.
    function _split(
        uint256 oldPositionId_,
        uint256 newPositionId_,
        uint256 amount_
    ) internal virtual {}

    // ========== RECLAIM RATE MANAGEMENT ========== //

    /// @notice Sets the reclaim rate for an asset period
    /// @dev    This function reverts if:
    ///         - The contract is not enabled
    ///         - The caller does not have the manager or admin role
    ///         - The reclaim rate exceeds 100%
    ///
    /// @param asset_         The address of the underlying asset
    /// @param depositPeriod_ The deposit period, in months
    /// @param reclaimRate_   The reclaim rate to set (in basis points, where 100e2 = 100%)
    function setAssetPeriodReclaimRate(
        IERC20 asset_,
        uint8 depositPeriod_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyManagerOrAdminRole {
        // Validate that the asset period exists in DepositManager
        if (!DEPOSIT_MANAGER.isAssetPeriod(asset_, depositPeriod_, address(this)).isConfigured)
            revert IDepositManager.DepositManager_InvalidAssetPeriod(
                address(asset_),
                depositPeriod_,
                address(this)
            );

        // Validate that the reclaim rate does not exceed 100%
        if (reclaimRate_ > ONE_HUNDRED_PERCENT) revert DepositFacility_InvalidAddress(address(0));

        // Set the reclaim rate
        _assetPeriodReclaimRates[_getAssetPeriodKey(asset_, depositPeriod_)] = reclaimRate_;

        // Emit event (we'll add this to IDepositFacility interface next)
        emit AssetPeriodReclaimRateSet(address(asset_), depositPeriod_, reclaimRate_);
    }

    /// @notice Returns the reclaim rate for an asset period
    ///
    /// @param asset_         The address of the underlying asset
    /// @param depositPeriod_ The deposit period, in months
    /// @return reclaimRate   The reclaim rate for the asset period
    function getAssetPeriodReclaimRate(
        IERC20 asset_,
        uint8 depositPeriod_
    ) external view returns (uint16 reclaimRate) {
        return _assetPeriodReclaimRates[_getAssetPeriodKey(asset_, depositPeriod_)];
    }

    // ========== ERC165 ========== //

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IDepositFacility).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
/// forge-lint: disable-end(asm-keccak256)
