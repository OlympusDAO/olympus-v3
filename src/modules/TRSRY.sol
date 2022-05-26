// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {ERC1155} from "solmate/tokens/ERC1155.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {TransferHelper} from "../libraries/TransferHelper.sol";
import {IERC20} from "../interfaces/IERC20.sol";

import {Kernel, Module} from "../Kernel.sol";

//import "./OlympusErrors.sol";

/// @title TSY - OlympusTreasury
/// @notice Treasury holds reserves, LP tokens and all other assets under the control
/// of the protocol. Any contracts that need access to treasury assets should
/// be whitelisted by governance.
// TODO should only allow approved amounts for a policy?
contract OlympusTreasury is Module {
    using TransferHelper for IERC20;

    event PolicyApprovedForWithdrawal(
        address indexed policy,
        address indexed token_,
        uint256 amount
    );

    Kernel kernel;

    // TODO approval token mapping
    // TODO debt for address and token mapping

    constructor(Kernel kernel_) Module(kernel_) {
        kernel = kernel_;
    }

    function KEYCODE() public pure override returns (bytes5) {
        return "TRSRY";
    }

    function getReserveBalance(address token_) external view returns (uint256) {
        return IERC20(token_).balanceOf(address(this)); // + debt[token_];
    }

    function loanReserves() external onlyPermitted {
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

    function depositReserves() external onlyPermitted {
        // TODO safeTransferFrom caller to here
        // TODO add to virtual reserves
    }

    function requestApproval(
        address policy_,
        address token_,
        uint256 amount_
    ) external onlyPermitted {
        // TODO account for debt
        //IERC20(token_).approve(policy_, amount_);

        //_approveForWithdrawal(policy_, token_, amount_);
        emit PolicyApprovedForWithdrawal(policy_, token_, amount_);
    }

    function withdrawReserves(
        address token_,
        address to_,
        uint256 amount_
    ) external onlyPermitted {
        // TODO is this all?? does this properly gate functions?
        // TODO check approval and decrement
        IERC20(token_).safeTransfer(to_, amount_);
    }

    function revokeApproval() external {
        // TODO make ungated
        // TODO check in kernel if policy is terminated
        // TODO if terminated, revoke approval
    }

    // TODO make payable function to receive eth and wrap?
    receive() external payable {
        // TODO
    }
}
