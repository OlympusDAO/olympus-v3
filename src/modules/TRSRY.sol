// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC1155} from "solmate/tokens/ERC1155.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

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
// TODO should only allow approved amounts for a policy?
contract OlympusTreasury is Module {
    using TransferHelper for ERC20;

    event ApprovedForWithdrawal(
        address indexed policy_,
        ERC20 indexed token_,
        uint256 amount_
    );
    event Withdrawal(
        address indexed policy_,
        ERC20 indexed token_,
        uint256 amount_
    );
    event ApprovalRevoked(address indexed policy_, ERC20[] tokens_);

    Kernel private kernel;

    // user -> reserve -> amount
    // infinite approval is max(uint256). Should be reserved monitored subsystems.
    mapping(address => mapping(ERC20 => uint256)) public withdrawApproval;

    // TODO approval token mapping
    mapping(ERC20 => bool) public isReserve;
    //mapping(ERC20 => uint256) public totalReserves; // reserve -> reserves

    // TODO debt for address and token mapping
    mapping(ERC20 => uint256) public totalDebt; // reserve -> totalDebt
    mapping(ERC20 => mapping(address => uint256)) public reserveDebt; // TODO reserve -> debtor -> debt

    constructor(Kernel kernel_) Module(kernel_) {
        kernel = kernel_;
    }

    function KEYCODE() public pure override returns (bytes5) {
        return "TRSRY";
    }

    receive() external payable {
        WETH(WETH_ADDRESS).deposit{value: msg.value}();
    }

    // Gov can declare a token to be treated as a reserve
    function declareReserve(ERC20 token_) external onlyPermitted {
        isReserve[token_] = true;
    }

    function getReserveBalance(ERC20 token_) external view returns (uint256) {
        if (!isReserve[token_]) {
            revert TRSRY_NotReserve();
        }

        return token_.balanceOf(address(this)) + totalDebt[token_];
    }

    // TODO is this needed if there's no virtual reserves?
    function depositReserves(ERC20 token_, uint256 amount_)
        external
        onlyPermitted
    {
        if (!isReserve[token_]) {
            revert TRSRY_NotReserve();
        }

        token_.safeTransferFrom(msg.sender, address(this), amount_);
    }

    // Must be carefully managed by governance.
    function requestApprovalFor(
        address policy_,
        ERC20 token_,
        uint256 amount_
    ) external onlyPermitted {
        kernel.onlyExecutor(); // TODO should this only be called by gov?

        // TODO account for debtors
        if (isReserve[token_] == false) {
            revert TRSRY_NotReserve();
        }
        withdrawApproval[policy_][token_] = amount_;

        emit ApprovedForWithdrawal(policy_, token_, amount_);
    }

    function withdrawReserves(ERC20 token_, uint256 amount_)
        public
        onlyPermitted
    {
        if (isReserve[token_] == false) {
            revert TRSRY_NotReserve();
        }

        uint256 approval = withdrawApproval[msg.sender][token_];
        if (approval < amount_) {
            revert TRSRY_NotApproved();
        }

        if (approval != type(uint256).max) {
            withdrawApproval[msg.sender][token_] = approval - amount_;
        }

        token_.safeTransfer(msg.sender, amount_);

        emit Withdrawal(msg.sender, token_, amount_);
    }

    // Anyone can call to revoke a terminated policy's approvals
    function revokeApproval(address policy_, ERC20[] memory tokens_) external {
        if (kernel.approvedPolicies(policy_) == true) {
            revert TRSRY_PolicyStillActive();
        }

        uint256 len = tokens_.length;
        for (uint256 i; i < len; ) {
            withdrawApproval[policy_][tokens_[i]] = 0;
        }

        emit ApprovalRevoked(policy_, tokens_);
    }

    /// TODO DEBT FUNCTIONS

    function loanReserves(ERC20 token_, uint256 amount_)
        external
        onlyPermitted
    {
        uint256 approval = withdrawApproval[msg.sender][token_];
        if (approval < amount_) revert TRSRY_NotApproved();

        // TODO verify this
        if (approval != type(uint256).max) {
            withdrawApproval[msg.sender][token_] = approval - amount_;
        }

        // Add debt to caller
        reserveDebt[token_][msg.sender] += amount_;
        totalDebt[token_] += amount_;

        // Withdraw to caller
        token_.safeTransfer(msg.sender, amount_);
    }

    function repayDebt(ERC20 token_, uint256 amount_) external onlyPermitted {
        // Subtract debt to caller
        reserveDebt[token_][msg.sender] -= amount_;
        totalDebt[token_] -= amount_;

        // Deposit from caller
        token_.safeTransferFrom(msg.sender, address(this), amount_);
    }

    // TODO for repaying debt in different token
    function repayDebtEquivalent(
        ERC20 origToken_,
        ERC20 repayToken_,
        uint256 amount_
    ) external {}

    // TODO Only permitted by governor. Used in case of emergency where loaned amounts cannot be repaid.
    function clearDebt(
        ERC20 token_,
        address debtor_,
        uint256 amount_
    ) external onlyPermitted {
        kernel.onlyExecutor();

        // TODO reduce debt for specific address
        reserveDebt[token_][debtor_] -= amount_;
        totalDebt[token_] -= amount_;

        // TODO reduce approval?
    }

    function setDebt(address token_, uint256 amount_) external onlyPermitted {
        // TODO check if debt is already set
        // TODO set debt
    }
}
