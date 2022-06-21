// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {TransferHelper} from "../libraries/TransferHelper.sol";

import {Kernel, Module} from "../Kernel.sol";

interface WETH {
    function deposit() external payable;
}

// ERRORS
error TRSRY_NotReserve();
error TRSRY_NotApproved();
error TRSRY_PolicyStillActive();

// CONST
address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

/// @title TRSRY - OlympusTreasury
/// @notice Treasury holds reserves, LP tokens and all other assets under the control
/// of the protocol. Any contracts that need access to treasury assets should
/// be whitelisted by governance and given proper role.
contract OlympusTreasury is Module {
    using TransferHelper for ERC20;

    // TODO are these correct tense?
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
    event ApprovalRevoked(address indexed policy_, ERC20[] tokens_);
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
    event DebtCleared(
        ERC20 indexed token_,
        address indexed policy_,
        uint256 amount_
    );
    event DebtSet(
        ERC20 indexed token_,
        address indexed policy_,
        uint256 amount_
    );

    Kernel.Role public constant APPROVER = Kernel.Role.wrap("TRSRY_Approver");
    Kernel.Role public constant BANKER = Kernel.Role.wrap("TRSRY_Banker");
    Kernel.Role public constant DEBT_ADMIN =
        Kernel.Role.wrap("TRSRY_DebtAdmin");

    // user -> reserve -> amount
    // infinite approval is max(uint256). Should be reserved monitored subsystems.
    mapping(address => mapping(ERC20 => uint256)) public withdrawApproval;

    // TODO debt for address and token mapping
    mapping(ERC20 => uint256) public totalDebt; // reserve -> totalDebt
    mapping(ERC20 => mapping(address => uint256)) public reserveDebt; // TODO reserve -> debtor -> debt

    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Kernel.Keycode) {
        return Kernel.Keycode.wrap("TRSRY");
    }

    function ROLES() public pure override returns (Kernel.Role[] memory roles) {
        roles = new Kernel.Role[](3);
        roles[0] = APPROVER;
        roles[1] = BANKER;
        roles[2] = DEBT_ADMIN;
    }

    /* 
    TODO breaks getModuleAddress
    TODO TypeError: Explicit type conversion not allowed from non-payable "address"
    TODO to "contract OlympusTreasury", which has a payable fallback function.
    receive() external payable {
        WETH(WETH_ADDRESS).deposit{value: msg.value}();
    }
    */

    function getReserveBalance(ERC20 token_) external view returns (uint256) {
        return token_.balanceOf(address(this)) + totalDebt[token_];
    }

    // Must be carefully managed by governance.
    function requestApprovalFor(
        address withdrawer_,
        ERC20 token_,
        uint256 amount_
    ) external onlyRole(APPROVER) {
        withdrawApproval[withdrawer_][token_] = amount_;

        emit ApprovedForWithdrawal(withdrawer_, token_, amount_);
    }

    function withdrawReserves(
        address to_,
        ERC20 token_,
        uint256 amount_
    ) public {
        // Must be approved
        uint256 approval = withdrawApproval[msg.sender][token_];
        if (approval < amount_) revert TRSRY_NotApproved();

        // Check for infinite approval
        if (approval != type(uint256).max)
            withdrawApproval[msg.sender][token_] = approval - amount_;

        token_.safeTransfer(to_, amount_);

        emit Withdrawal(msg.sender, to_, token_, amount_);
    }

    // Anyone can call to revoke a terminated policy's approvals
    function revokeApprovals(address withdrawer_, ERC20[] memory tokens_)
        external
    {
        if (kernel.approvedPolicies(msg.sender) == true)
            revert TRSRY_PolicyStillActive();

        uint256 len = tokens_.length;
        for (uint256 i; i < len; ) {
            withdrawApproval[withdrawer_][tokens_[i]] = 0;
            unchecked {
                ++i;
            }
        }

        emit ApprovalRevoked(withdrawer_, tokens_);
    }

    /// DEBT FUNCTIONS

    // TODO add withdrawer arguments

    function loanReserves(ERC20 token_, uint256 amount_)
        external
        onlyRole(BANKER)
    {
        uint256 approval = withdrawApproval[msg.sender][token_];
        if (approval < amount_) revert TRSRY_NotApproved();

        // If not inf approval, subtract amount from approval
        if (approval != type(uint256).max) {
            withdrawApproval[msg.sender][token_] -= amount_;
        }

        // Add debt to caller
        reserveDebt[token_][msg.sender] += amount_;
        totalDebt[token_] += amount_;

        // Withdraw to caller
        token_.safeTransfer(msg.sender, amount_);

        emit DebtIncurred(token_, msg.sender, amount_);
    }

    function repayLoan(ERC20 token_, uint256 amount_)
        external
        onlyRole(BANKER)
    {
        // Subtract debt to caller
        reserveDebt[token_][msg.sender] -= amount_;
        totalDebt[token_] -= amount_;

        // Deposit from caller
        token_.safeTransferFrom(msg.sender, address(this), amount_);

        emit DebtRepaid(token_, msg.sender, amount_);
    }

    // TODO for repaying debt in different tokens. Specifically for changing reserve assets
    /*
    function repayDebtEquivalent(
        ERC20 origToken_,
        ERC20 repayToken_,
        uint256 debtAmount_
    ) external onlyPermittedPolicies {
        // TODO reduce debt amount of original token
        reserveDebt[origToken_][msg.sender] -= debtAmount_;
        totalDebt[origToken_] -= debtAmount_;
    }
    */

    // To be used as escape hatch for setting debt in special cases, like swapping reserves to another token
    function setDebt(
        ERC20 token_,
        address debtor_,
        uint256 amount_
    ) external onlyRole(DEBT_ADMIN) {
        uint256 oldDebt = reserveDebt[token_][debtor_];

        // Set debt for debtor
        reserveDebt[token_][debtor_] = amount_;

        if (oldDebt < amount_) totalDebt[token_] += amount_ - oldDebt;
        else totalDebt[token_] -= oldDebt - amount_;

        emit DebtSet(token_, debtor_, amount_);
    }

    function increaseDebt(
        ERC20 token_,
        address debtor_,
        uint256 amount_
    ) external onlyRole(DEBT_ADMIN) {
        // Increase debt for debtor
        reserveDebt[token_][debtor_] += amount_;

        // Increase total debt
        totalDebt[token_] += amount_;

        emit DebtSet(token_, debtor_, reserveDebt[token_][debtor_]);
    }

    function decreaseDebt(
        ERC20 token_,
        address debtor_,
        uint256 amount_
    ) external onlyRole(DEBT_ADMIN) {
        // Decrease debt for debtor
        reserveDebt[token_][debtor_] -= amount_;

        // Decrease total debt
        totalDebt[token_] -= amount_;

        emit DebtSet(token_, debtor_, reserveDebt[token_][debtor_]);
    }

    // TODO Only permitted by governor. Used in case of emergency where loaned amounts cannot be repaid.
    function clearDebt(
        ERC20 token_,
        address debtor_,
        uint256 amount_
    ) external onlyRole(DEBT_ADMIN) {
        // Reduce debt for specific address
        reserveDebt[token_][debtor_] -= amount_;
        totalDebt[token_] -= amount_;

        emit DebtCleared(token_, debtor_, amount_);
    }
}
