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

    /// @notice Mapping of committed deposits per token
    mapping(IERC20 => uint256) private _committedDeposits;

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
    function authorizeOperator(address operator_) external onlyAdminRole {
        _authorizedOperators.add(operator_);
        emit OperatorAuthorized(operator_);
    }

    /// @inheritdoc IDepositFacility
    function deauthorizeOperator(address operator_) external onlyEmergencyOrAdminRole {
        _authorizedOperators.remove(operator_);
        emit OperatorDeauthorized(operator_);
    }

    /// @inheritdoc IDepositFacility
    function isAuthorizedOperator(address operator_) external view returns (bool) {
        return _authorizedOperators.contains(operator_);
    }

    // ========== CALLBACKS ========== //

    /// @inheritdoc IDepositFacility
    function handleWithdraw(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address recipient_
    ) external onlyAuthorizedOperator {
        // Validate that we have enough committed deposits
        if (amount_ > _committedDeposits[depositToken_]) {
            revert DepositFacility_InsufficientDeposits(amount_, _committedDeposits[depositToken_]);
        }

        // Process the withdrawal through DepositManager
        DEPOSIT_MANAGER.withdraw(
            IDepositManager.WithdrawParams({
                asset: depositToken_,
                depositPeriod: depositPeriod_,
                depositor: msg.sender,
                recipient: recipient_,
                amount: amount_,
                isWrapped: false
            })
        );

        // Update committed deposits
        _committedDeposits[depositToken_] -= amount_;
    }

    /// @inheritdoc IDepositFacility
    function handleBorrow(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address recipient_
    ) external onlyAuthorizedOperator {
        // Validate that we have enough committed deposits
        if (amount_ > _committedDeposits[depositToken_]) {
            revert DepositFacility_InsufficientDeposits(amount_, _committedDeposits[depositToken_]);
        }

        // Process the borrowing through DepositManager
        DEPOSIT_MANAGER.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: depositToken_,
                operator: address(this),
                recipient: recipient_,
                amount: amount_
            })
        );

        // Update committed deposits
        _committedDeposits[depositToken_] -= amount_;
    }

    /// @inheritdoc IDepositFacility
    function handleRepay(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address payer_
    ) external onlyAuthorizedOperator {
        // Process the repayment through DepositManager
        DEPOSIT_MANAGER.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: depositToken_,
                operator: address(this),
                payer: payer_,
                amount: amount_
            })
        );

        // Update committed deposits (repayment increases available deposits)
        _committedDeposits[depositToken_] += amount_;
    }

    /// @inheritdoc IDepositFacility
    function getDepositBalance(IERC20 depositToken_) external view returns (uint256) {
        // Get the total deposited assets for this facility
        (, uint256 depositedSharesInAssets) = DEPOSIT_MANAGER.getOperatorAssets(
            depositToken_,
            address(this)
        );

        // Get the current liabilities (receipt tokens minted)
        uint256 operatorLiabilities = DEPOSIT_MANAGER.getOperatorLiabilities(
            depositToken_,
            address(this)
        );

        // Get the current borrowed amount
        uint256 borrowedAmount = DEPOSIT_MANAGER.getBorrowedAmount(depositToken_, address(this));

        // Available balance = deposited + borrowed - liabilities - committed
        uint256 totalAvailable = depositedSharesInAssets + borrowedAmount;
        if (totalAvailable <= operatorLiabilities) {
            return 0;
        }

        uint256 availableDeposits = totalAvailable - operatorLiabilities;
        return
            availableDeposits > _committedDeposits[depositToken_]
                ? availableDeposits - _committedDeposits[depositToken_]
                : 0;
    }

    /// @inheritdoc IDepositFacility
    function getCommittedDeposits(IERC20 depositToken_) external view returns (uint256) {
        return _committedDeposits[depositToken_];
    }

    // ========== INTERNAL FUNCTIONS ========== //

    /// @notice Internal function to update committed deposits
    /// @param depositToken_ The deposit token
    /// @param amount_ The amount to add (positive) or subtract (negative)
    function _updateCommittedDeposits(IERC20 depositToken_, int256 amount_) internal {
        if (amount_ > 0) {
            _committedDeposits[depositToken_] += uint256(amount_);
        } else if (amount_ < 0) {
            _committedDeposits[depositToken_] -= uint256(-amount_);
        }
    }

    // ========== ERC165 ========== //

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IDepositFacility).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
