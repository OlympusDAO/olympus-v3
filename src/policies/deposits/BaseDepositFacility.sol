// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";

// Bophades
import {Kernel, Policy} from "src/Kernel.sol";
import {ReentrancyGuard} from "@openzeppelin-5.3.0/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title Base Deposit Facility
/// @notice Abstract base contract for deposit facilities with shared functionality
abstract contract BaseDepositFacility is Policy, PolicyEnabler, IDepositFacility, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    // ========== STATE VARIABLES ========== //

    /// @notice The deposit manager
    IDepositManager public immutable DEPOSIT_MANAGER;

    /// @notice Set of authorized operators
    EnumerableSet.AddressSet private _authorizedOperators;

    mapping(IERC20 asset => uint256 committedDeposits) private _assetCommittedDeposits;

    mapping(bytes32 assetOperatorKey => uint256 committedDeposits)
        private _assetOperatorCommittedDeposits;

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

    // ========== CALLBACKS ========== //

    function _getCommittedDepositsKey(
        IERC20 depositToken_,
        address operator_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(address(depositToken_), operator_));
    }

    /// @inheritdoc IDepositFacility
    function handleCommit(
        IERC20 depositToken_,
        uint256 amount_
    ) external onlyEnabled onlyAuthorizedOperator {
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
    function handleCommitCancel(
        IERC20 depositToken_,
        uint256 amount_
    ) external onlyEnabled onlyAuthorizedOperator {
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
    function handleCommitWithdraw(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address recipient_
    ) external onlyEnabled onlyAuthorizedOperator returns (uint256) {
        // Validate that there are enough committed funds
        uint256 operatorCommitments = getCommittedDeposits(depositToken_, msg.sender);
        if (amount_ > operatorCommitments)
            revert DepositFacility_InsufficientCommitment(msg.sender, amount_, operatorCommitments);

        // Reduce the commitment
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

        // Emit event
        emit AssetCommitWithdrawn(address(depositToken_), msg.sender, actualAmount);

        return actualAmount;
    }

    /// @inheritdoc IDepositFacility
    function handleBorrow(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address recipient_
    ) external onlyEnabled onlyAuthorizedOperator returns (uint256) {
        // Process the borrowing through DepositManager
        // It will revert if more is being borrowed than available
        return
            DEPOSIT_MANAGER.borrowingWithdraw(
                IDepositManager.BorrowingWithdrawParams({
                    asset: depositToken_,
                    recipient: recipient_,
                    amount: amount_
                })
            );
    }

    /// @inheritdoc IDepositFacility
    function handleRepay(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address payer_
    ) external onlyEnabled onlyAuthorizedOperator returns (uint256) {
        // Process the repayment through DepositManager
        // It will revert if more is being repaid than borrowed
        return
            DEPOSIT_MANAGER.borrowingRepay(
                IDepositManager.BorrowingRepayParams({
                    asset: depositToken_,
                    payer: payer_,
                    amount: amount_
                })
            );
    }

    /// @inheritdoc IDepositFacility
    function getAvailableDeposits(IERC20 depositToken_) public view returns (uint256) {
        // Available deposits are the assets - commitments
        (, uint256 sharesInAssets) = DEPOSIT_MANAGER.getOperatorAssets(
            depositToken_,
            address(this)
        );
        uint256 committedDeposits = _assetCommittedDeposits[depositToken_];

        // This should not happen, but prevent a revert anyway
        if (committedDeposits > sharesInAssets) return 0;

        return sharesInAssets - committedDeposits;
    }

    /// @inheritdoc IDepositFacility
    function getCommittedDeposits(
        IERC20 depositToken_,
        address operator_
    ) public view returns (uint256) {
        return _assetOperatorCommittedDeposits[_getCommittedDepositsKey(depositToken_, operator_)];
    }

    /// @inheritdoc IDepositFacility
    function getCommittedDeposits(IERC20 depositToken_) public view returns (uint256) {
        return _assetCommittedDeposits[depositToken_];
    }

    // ========== ERC165 ========== //

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IDepositFacility).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
