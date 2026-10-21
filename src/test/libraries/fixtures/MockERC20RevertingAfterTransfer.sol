// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {ERC20Mock} from "@openzeppelin-5.7.0/mocks/token/ERC20Mock.sol";

contract MockERC20RevertingAfterTransfer is ERC20Mock {
    error TransferRejected();

    function transfer(address recipient_, uint256 amount_) public override returns (bool) {
        super.transfer(recipient_, amount_);
        revert TransferRejected();
    }

    function transferFrom(
        address sender_,
        address recipient_,
        uint256 amount_
    ) public override returns (bool) {
        super.transferFrom(sender_, recipient_, amount_);
        revert TransferRejected();
    }
}
