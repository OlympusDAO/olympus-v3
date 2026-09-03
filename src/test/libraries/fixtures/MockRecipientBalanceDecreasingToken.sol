// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

// Contracts
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

contract MockRecipientBalanceDecreasingToken is MockERC20 {
    constructor() MockERC20("Recipient Balance Decreasing Token", "RBD", 18) {}

    /// @inheritdoc ERC20
    function transferFrom(address, address to_, uint256) public override returns (bool) {
        _burn(to_, 1);
        return true;
    }
}
