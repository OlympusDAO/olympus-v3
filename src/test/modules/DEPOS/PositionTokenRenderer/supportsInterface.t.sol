// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

import {PositionTokenRenderer} from "src/modules/DEPOS/PositionTokenRenderer.sol";
import {IPositionTokenRenderer} from "src/modules/DEPOS/IPositionTokenRenderer.sol";
import {ERC165Helper} from "src/test/lib/ERC165.sol";

contract PositionTokenRendererSupportsInterfaceTest is Test {
    // Contracts
    PositionTokenRenderer public renderer;

    function setUp() public {
        // Deploy contracts
        renderer = new PositionTokenRenderer();
    }

    function test_supportsInterface() public view {
        // Validate ERC165 compliance
        ERC165Helper.validateSupportsInterface(address(renderer));

        // Test IERC165
        assertEq(renderer.supportsInterface(type(IERC165).interfaceId), true, "IERC165 mismatch");

        // Test IPositionTokenRenderer
        assertEq(
            renderer.supportsInterface(type(IPositionTokenRenderer).interfaceId),
            true,
            "IPositionTokenRenderer mismatch"
        );

        // Test non-implemented interfaces (should be false)
        assertEq(
            renderer.supportsInterface(type(IERC20).interfaceId),
            false,
            "Should not support IERC20"
        );
    }
}
