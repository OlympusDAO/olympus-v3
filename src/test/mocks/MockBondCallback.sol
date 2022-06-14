// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import {IBondCallback} from "interfaces/IBondCallback.sol";
import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";

/**
 * @notice Mock implementation of IBondCallback to use for testing
 */
contract MockBondCallback is IBondCallback {
    MockERC20 internal token;

    mapping(uint256 => uint256[2]) internal amountsPerMarket;

    constructor(MockERC20 _token) {
        token = _token;
    }

    function callback(
        uint256 id_,
        uint256 inputAmount_,
        uint256 outputAmount_
    ) external {
        // Store amounts in/out
        amountsPerMarket[id_][0] += inputAmount_;
        amountsPerMarket[id_][1] += outputAmount_;

        // Mint new tokens and return to sender
        token.mint(msg.sender, outputAmount_);
    }

    function amountsForMarket(uint256 id_)
        external
        view
        override
        returns (uint256 in_, uint256 out_)
    {
        uint256[2] memory marketAmounts = amountsPerMarket[id_];
        return (marketAmounts[0], marketAmounts[1]);
    }

    function whitelist(address teller_, uint256 id_) external override {}
}
