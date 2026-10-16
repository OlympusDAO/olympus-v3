// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {ERC20Mock} from "@openzeppelin-5.7.0/mocks/token/ERC20Mock.sol";

contract MockERC20Overcredit is ERC20Mock {
    function transferFrom(
        address sender_,
        address recipient_,
        uint256 amount_
    ) public override returns (bool) {
        _spendAllowance(sender_, msg.sender, amount_);
        _transfer(sender_, recipient_, amount_ + 1);
        return true;
    }
}
