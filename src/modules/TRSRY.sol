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

    event PolicyApprovedForWithdrawal(
        address indexed policy_,
        address indexed token_,
        uint256 amount_
    );

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
    function makeReserve(ERC20 token_) external onlyPermitted {
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
    function requestApproval(
        address policy_,
        ERC20 token_,
        uint256 amount_
    ) external onlyPermitted {
        // TODO account for debtors
        withdrawApproval[policy_][token_] = amount_;
        emit PolicyApprovedForWithdrawal(policy_, address(token_), amount_);
    }

    function withdrawReserves(
        ERC20 token_,
        address to_,
        uint256 amount_
    ) external onlyPermitted {
        // TODO check approval and decrement
        uint256 approval = withdrawApproval[msg.sender][token_];
        if (approval < amount_) {
            revert TRSRY_NotApproved();
        }
        if (approval != type(uint256).max) {
            withdrawApproval[msg.sender][token_] = approval - amount_;
        }

        token_.safeTransfer(to_, amount_);
    }

    // Anyone can call to revoke a terminated policy's approvals
    function revokeApproval(address policy_, ERC20[] calldata tokens_)
        external
    {
        if (kernel.approvedPolicies(policy_) == true) {
            revert TRSRY_PolicyStillActive();
        }

        uint256 len = tokens_.length;
        for (uint256 i; i < len; ) {
            withdrawApproval[policy_][tokens_[i]] = 0;
        }
    }

    /// TODO DEBT FUNCTIONS

    function loanReserves(
        address recipient_,
        address token_,
        uint256 amount_
    ) external onlyPermitted {
        /*
          1. update debt 
          2. send tokens
        */
        // TODO check approval
        // TODO add debt to caller
        // TODO Withdraw to caller
        // -> virtual reserves stay the same
    }

    function repayReserves() external onlyPermitted {
        // TODO check approval
        // TODO subtract debt to caller
        // TODO Deposit from caller
    }

    // TODO Only permitted by governor. Used in case of emergency where loaned amounts cannot be repaid.
    function clearDebt() external onlyPermitted {
        // TODO reduce debt for specific address
        // TODO reduce approval?
    }

    function setDebt(address token_, uint256 amount_) external onlyPermitted {
        // TODO check if debt is already set
        // TODO set debt
    }
}
