// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import "src/Kernel.sol";

/// @notice Treasury holds reserves, LP tokens and all other assets under the control
///         of the protocol.
contract OlympusTreasury is TRSRYv1, ReentrancyGuard {
    using TransferHelper for ERC20;

    /*//////////////////////////////////////////////////////////////
                            MODULE INTERFACE
    //////////////////////////////////////////////////////////////*/

    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("TRSRY");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    /*//////////////////////////////////////////////////////////////
                               CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Get total balance of assets inside the treasury + any debt taken out against those assets.
    function getReserveBalance(ERC20 token_) external view override returns (uint256) {
        return token_.balanceOf(address(this)) + totalDebt[token_];
    }

    /// @notice Increase approval for specific withdrawer addresses
    function increaseWithdrawerApproval(
        address withdrawer_,
        ERC20 token_,
        uint256 amount_
    ) external override permissioned {
        uint256 newAmount = withdrawApproval[withdrawer_][token_] + amount_;
        withdrawApproval[withdrawer_][token_] = newAmount;
        emit IncreaseWithdrawerApproval(withdrawer_, token_, newAmount);
    }

    /// @notice Decrease approval for specific withdrawer addresses
    function decreaseWithdrawerApproval(
        address withdrawer_,
        ERC20 token_,
        uint256 amount_
    ) external override permissioned {
        uint256 newAmount = withdrawApproval[withdrawer_][token_] - amount_;
        withdrawApproval[withdrawer_][token_] = newAmount;
        emit DecreaseWithdrawerApproval(withdrawer_, token_, newAmount);
    }

    /// @notice Allow withdrawal of reserve funds from pre-approved addresses.
    function withdrawReserves(
        address to_,
        ERC20 token_,
        uint256 amount_
    ) public override {
        uint256 approval = withdrawApproval[msg.sender][token_];
        if (approval < amount_) revert TRSRY_NotApproved();

        // If not infinite approval, decrement approval by amount
        if (approval != type(uint256).max) {
            unchecked {
                withdrawApproval[msg.sender][token_] = approval - amount_;
            }
        }

        token_.safeTransfer(to_, amount_);

        emit Withdrawal(msg.sender, to_, token_, amount_);
    }

    /*//////////////////////////////////////////////////////////////
                             DEBT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Increase approval for someone to accrue debt in order to withdraw reserves.
    /// @dev    Debt will generally be taken by contracts to allocate treasury funds in yield sources.
    function increaseDebtorApproval(
        address debtor_,
        ERC20 token_,
        uint256 amount_
    ) external override permissioned {
        uint256 newAmount = debtApproval[debtor_][token_] + amount_;
        debtApproval[debtor_][token_] = newAmount;
        emit IncreaseDebtorApproval(debtor_, token_, newAmount);
    }

    /// @notice Decrease approval for someone to withdraw reserves as debt.
    function decreaseDebtorApproval(
        address debtor_,
        ERC20 token_,
        uint256 amount_
    ) external override permissioned {
        uint256 newAmount = debtApproval[debtor_][token_] - amount_;
        debtApproval[debtor_][token_] = newAmount;
        emit DecreaseDebtorApproval(debtor_, token_, newAmount);
    }

    /// @notice Pre-approved policies can get a loan to perform operations with treasury assets.
    function incurDebt(ERC20 token_, uint256 amount_) external override permissioned {
        uint256 approval = debtApproval[msg.sender][token_];
        if (approval < amount_) revert TRSRY_NotApproved();

        // If not infinite approval, decrement approval by amount
        if (approval != type(uint256).max) {
            unchecked {
                debtApproval[msg.sender][token_] = approval - amount_;
            }
        }

        // Add debt to caller
        reserveDebt[token_][msg.sender] += amount_;
        totalDebt[token_] += amount_;

        token_.safeTransfer(msg.sender, amount_);

        emit DebtIncurred(token_, msg.sender, amount_);
    }

    /// @notice Repay a debtor debt.
    /// @dev    Only confirmed to safely handle standard and non-standard ERC20s.
    /// @dev    Can have unforeseen consequences with ERC777. Be careful with ERC777 as reserve.
    function repayDebt(
        address debtor_,
        ERC20 token_,
        uint256 amount_
    ) external override nonReentrant {
        if (reserveDebt[token_][debtor_] == 0) revert TRSRY_NoDebtOutstanding();

        // Deposit from caller first (to handle nonstandard token transfers)
        uint256 prevBalance = token_.balanceOf(address(this));
        token_.safeTransferFrom(msg.sender, address(this), amount_);

        uint256 received = token_.balanceOf(address(this)) - prevBalance;

        // Choose minimum between passed-in amount and received amount
        if (received > amount_) received = amount_;

        // Subtract debt from debtor
        reserveDebt[token_][debtor_] -= received;
        totalDebt[token_] -= received;

        emit DebtRepaid(token_, debtor_, received);
    }

    /// @notice An escape hatch for setting debt in special cases, like swapping reserves to another token.
    function setDebt(
        address debtor_,
        ERC20 token_,
        uint256 amount_
    ) external override permissioned {
        uint256 oldDebt = reserveDebt[token_][debtor_];

        reserveDebt[token_][debtor_] = amount_;

        if (oldDebt < amount_) totalDebt[token_] += amount_ - oldDebt;
        else totalDebt[token_] -= oldDebt - amount_;

        emit DebtSet(token_, debtor_, amount_);
    }
}
