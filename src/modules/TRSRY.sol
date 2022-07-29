// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

import {Kernel, Module} from "src/Kernel.sol";

// ERRORS
error TRSRY_NotApproved();

/// @title TRSRY - OlympusTreasury
/// @notice Treasury holds reserves, LP tokens and all other assets under the control
/// of the protocol. Any contracts that need access to treasury assets should
/// be whitelisted by governance and given proper role.
contract OlympusTreasury is Module, ReentrancyGuard {
    using TransferHelper for ERC20;

    event ApprovedForWithdrawal(
        address indexed policy_,
        ERC20 indexed token_,
        uint256 amount_
    );
    event Withdrawal(
        address indexed policy_,
        address indexed withdrawer_,
        ERC20 indexed token_,
        uint256 amount_
    );
    event DebtIncurred(
        ERC20 indexed token_,
        address indexed policy_,
        uint256 amount_
    );
    event DebtRepaid(
        ERC20 indexed token_,
        address indexed policy_,
        uint256 amount_
    );
    event DebtSet(
        ERC20 indexed token_,
        address indexed policy_,
        uint256 amount_
    );

    // user -> reserve -> amount
    // infinite approval is max(uint256). Should be reserved monitored subsystems.
    mapping(address => mapping(ERC20 => uint256)) public withdrawApproval;

    // debt for address and token mapping
    mapping(ERC20 => uint256) public totalDebt; // reserve -> totalDebt
    mapping(ERC20 => mapping(address => uint256)) public reserveDebt; // TODO reserve -> debtor -> debt

    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("TRSRY");
    }

    function VERSION()
        external
        pure
        override
        returns (uint8 major, uint8 minor)
    {
        return (1, 0);
    }

    function getReserveBalance(ERC20 token_) external view returns (uint256) {
        return token_.balanceOf(address(this)) + totalDebt[token_];
    }

    // Set approval for specific addresses
    function setApprovalFor(
        address withdrawer_,
        ERC20 token_,
        uint256 amount_
    ) external permissioned {
        withdrawApproval[withdrawer_][token_] = amount_;

        emit ApprovedForWithdrawal(withdrawer_, token_, amount_);
    }

    // Allow withdrawal of reserve funds from pre-approved addresses
    function withdrawReserves(
        address to_,
        ERC20 token_,
        uint256 amount_
    ) public {
        _checkApproval(msg.sender, token_, amount_);

        token_.safeTransfer(to_, amount_);

        emit Withdrawal(msg.sender, to_, token_, amount_);
    }

    // DEBT FUNCTIONS

    function loanReserves(ERC20 token_, uint256 amount_) external permissioned {
        _checkApproval(msg.sender, token_, amount_);

        // Add debt to caller
        reserveDebt[token_][msg.sender] += amount_;
        totalDebt[token_] += amount_;

        token_.safeTransfer(msg.sender, amount_);

        emit DebtIncurred(token_, msg.sender, amount_);
    }

    function repayLoan(ERC20 token_, uint256 amount_)
        external
        nonReentrant
        permissioned
    {
        // Deposit from caller first (to handle nonstandard token transfers)
        uint256 prevBalance = token_.balanceOf(address(this));
        token_.safeTransferFrom(msg.sender, address(this), amount_);

        uint256 received = token_.balanceOf(address(this)) - prevBalance;

        // Subtract debt to caller
        reserveDebt[token_][msg.sender] -= received;
        totalDebt[token_] -= received;

        emit DebtRepaid(token_, msg.sender, received);
    }

    // To be used as escape hatch for setting debt in special cases, like swapping reserves to another token
    function setDebt(
        ERC20 token_,
        address debtor_,
        uint256 amount_
    ) external permissioned {
        uint256 oldDebt = reserveDebt[token_][debtor_];

        // Set debt for debtor
        reserveDebt[token_][debtor_] = amount_;

        if (oldDebt < amount_) totalDebt[token_] += amount_ - oldDebt;
        else totalDebt[token_] -= oldDebt - amount_;

        emit DebtSet(token_, debtor_, amount_);
    }

    function _checkApproval(
        address withdrawer_,
        ERC20 token_,
        uint256 amount_
    ) internal {
        // Must be approved
        uint256 approval = withdrawApproval[withdrawer_][token_];
        if (approval < amount_) revert TRSRY_NotApproved();

        // Check for infinite approval
        if (approval != type(uint256).max) {
            unchecked {
                withdrawApproval[withdrawer_][token_] = approval - amount_;
            }
        }
    }
}
