// SPDX-License-Identifier: Unlicensed
// solhint-disable one-contract-per-file
pragma solidity >=0.8.20;

import {Module} from "src/Kernel.sol";
import {DEPOSTest} from "./DEPOSTest.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";

contract MockTokenRenderer {
    function supportsInterface(bytes4) public pure returns (bool) {
        return false;
    }
}

contract SetTokenRendererDEPOSTest is DEPOSTest {
    event TokenRendererSet(address indexed renderer);

    // given the caller is not permissioned
    //  [X] it reverts

    function test_callerNotPermissioned_reverts(address caller_) public {
        vm.assume(caller_ != godmode);

        vm.expectRevert(abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, caller_));

        vm.prank(caller_);
        DEPOS.setTokenRenderer(address(tokenURIRenderer));
    }

    // when the address is zero
    //  [X] it sets the renderer to zero address
    //  [X] it emits a TokenRendererSet event

    function test_whenAddressIsZero() public {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit TokenRendererSet(address(0));

        // Call function
        vm.prank(godmode);
        DEPOS.setTokenRenderer(address(0));

        // Assert
        assertEq(DEPOS.getTokenRenderer(), address(0), "Token renderer should be zero address");
    }

    // given the renderer contract does not support the required interface
    //  [X] it reverts

    function test_givenRendererDoesNotSupportInterface_reverts() public {
        MockTokenRenderer renderer = new MockTokenRenderer();

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositPositionManager.DEPOS_InvalidRenderer.selector,
                address(renderer)
            )
        );

        // Call function
        vm.prank(godmode);
        DEPOS.setTokenRenderer(address(renderer));
    }

    // [X] it sets the renderer to the provided address
    // [X] it emits a TokenRendererSet event

    function test_success() public {
        // Set to zero address
        vm.prank(godmode);
        DEPOS.setTokenRenderer(address(0));

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit TokenRendererSet(address(tokenURIRenderer));

        // Call function
        vm.prank(godmode);
        DEPOS.setTokenRenderer(address(tokenURIRenderer));

        // Assert
        assertEq(
            DEPOS.getTokenRenderer(),
            address(tokenURIRenderer),
            "Token renderer should be set"
        );
    }
}
