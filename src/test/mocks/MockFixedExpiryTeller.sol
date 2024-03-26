// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract MockFixedExpiryTeller {
    MockERC20 public bondToken;

    constructor() {
        bondToken = new MockERC20("BT", "BT", 9);
    }

    // ========= DEPOSIT/MINT ========= //

    function create(
        MockERC20 underlying_,
        uint48 expiry_,
        uint256 amount_
    ) external returns (MockERC20, uint256) {
        underlying_.transferFrom(msg.sender, address(this), amount_);
        bondToken.mint(msg.sender, amount_);
        return (bondToken, amount_);
    }

    // ========= TOKENIZATION ========= //

    function deploy(MockERC20 underlying_, uint48 expiry_) external returns (MockERC20) {
        return bondToken;
    }

    // ========= VIEW ========= //

    function getBondTokenForMarket(uint256 id_) external view returns (MockERC20) {
        return bondToken;
    }
}
