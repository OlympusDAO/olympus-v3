// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {DefaultOperatorAuthHarness} from "./DefaultOperatorAuthHarness.sol";
import {OperatorAuthTest} from "./OperatorAuthTest.sol";

contract OperatorAuthConstructorTest is OperatorAuthTest {
    // Scenarios: OACONSTRUCT-I01.
    function test_whenNoSupportedActions_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidActions.selector, 0)
        );
        new DefaultOperatorAuthHarness(0);
    }

    // Scenarios: OACONSTRUCT-N01.
    function test_whenSupportedMaskMaximum() public {
        DefaultOperatorAuthHarness auth = new DefaultOperatorAuthHarness(type(uint8).max);
        assertEq(
            auth.captureAuthorization(_account, _account, 128),
            bytes32(0),
            "Maximum supported mask permits highest individual bit"
        );
        IOperatorAuth.Grant memory g = _grant(true);
        g.actions = 255;
        vm.prank(_account);
        auth.approveGrant(g);
        assertNotEq(
            auth.captureAuthorization(_account, _operator, 128),
            bytes32(0),
            "Grant mask maximum retains all supported actions"
        );
    }
}
