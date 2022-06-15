// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import {ITreasury} from "../../interfaces/ITreasury.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {TransferHelper} from "../../lib/TransferHelper.sol";

/**
 * @notice Mock implementation of ITreasury to use for testing
 */
contract MockTreasury is ITreasury {
    using TransferHelper for ERC20;

    function withdraw(
        ERC20 token_,
        address to_,
        uint256 amount_
    ) public override {
        token_.safeTransfer(to_, amount_);
    }
}
