// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.27;

// Contracts
import {MockERC20} from "src/test/mocks/MockERC20.sol";

/// @notice Token that consumes its forwarded gas during transfer for task isolation tests.
contract GasBurningRevenueToken is MockERC20 {
    constructor() MockERC20("Gas Burning Revenue", "BURN", 18) {}

    function transfer(address, uint256) public pure override returns (bool) {
        // Invalid opcode deliberately exhausts the gas forwarded to this mock.
        // forge-lint: disable-next-line(inline-assembly)
        assembly {
            invalid()
        }
    }
}
