// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";

// Contracts
import {ERC20Mock} from "@openzeppelin-5.7.0/mocks/token/ERC20Mock.sol";

contract MockRecipientBalanceDecreasingToken is ERC20Mock {
    /// @inheritdoc ERC20
    function transferFrom(address, address to_, uint256) public override returns (bool) {
        _burn(to_, 1);
        return true;
    }
}
