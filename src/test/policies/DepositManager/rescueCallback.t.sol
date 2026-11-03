// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.27;

// Interfaces
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Contracts
import {DepositManagerTest} from "./DepositManagerTest.sol";
import {DepositManagerRescueCallbackActor} from "./fixtures/DepositManagerRescueCallbackActor.sol";
import {DepositManagerRescueCallbackToken} from "./fixtures/DepositManagerRescueCallbackToken.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {Actions} from "src/Kernel.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

contract DepositManagerRescueCallbackTest is DepositManagerTest {
    // Scenarios: DM-RESCUE-C02.
    function test_givenAuthorizedRescueCallback_whenCaught_outerSucceedsOnce()
        public
        givenIsEnabled
    {
        ReentrantFeeToken outerToken = new ReentrantFeeToken();
        MockERC20 nestedToken = new MockERC20("Nested token", "NEST", 18);
        vm.prank(ADMIN);
        depositManager.setConfigOperator(address(outerToken));
        outerToken.mint(address(depositManager), 10);
        nestedToken.mint(address(depositManager), 7);
        outerToken.setCallback(
            address(depositManager),
            abi.encodeWithSignature("rescue(address)", address(nestedToken))
        );

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint256 quote = IDepositManagerV1_1(address(depositManager)).previewRescue(
            address(outerToken)
        );
        assertEq(quote, 10, "preview sees independently funded outer balance");
        assertEq(outerToken.transferCallCount(), 0, "preview does not trigger token transfer");
        vm.expectEmit(address(depositManager));
        emit IDepositManager.TokenRescued(address(outerToken), 10);
        vm.recordLogs();
        vm.prank(ADMIN);
        depositManager.rescue(address(outerToken));
        assertEq(
            vm.getRecordedLogs().length,
            2,
            "one outer transfer and rescue event with no nested event"
        );

        assertFalse(outerToken.callbackSucceeded(), "authorized nested rescue must be rejected");
        assertEq(
            outerToken.callbackRevertData(),
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector),
            "nested rescue reaches exact shared guard"
        );
        assertEq(outerToken.transferCallCount(), 1, "outer rescue transfers once");
        assertEq(outerToken.balanceOf(address(trsry)), 10, "outer quote reaches Treasury once");
        assertEq(outerToken.balanceOf(address(depositManager)), 0, "outer stray token fully swept");
        assertEq(
            nestedToken.balanceOf(address(depositManager)),
            7,
            "nested token custody untouched"
        );
        assertEq(nestedToken.balanceOf(address(trsry)), 0, "no nested Treasury transfer");

        // The token is the selected operator; the same nested action succeeds after guard release.
        vm.prank(address(outerToken));
        depositManager.rescue(address(nestedToken));
        assertEq(nestedToken.balanceOf(address(trsry)), 7, "nested action is otherwise executable");
    }

    // Scenarios: DM-RESCUE-C03.
    function test_givenAuthorizedRescueCallback_whenPropagated_outerRollsBack()
        public
        givenIsEnabled
    {
        DepositManagerRescueCallbackToken outerToken = new DepositManagerRescueCallbackToken();
        MockERC20 nestedToken = new MockERC20("Nested token", "NEST", 18);
        vm.prank(ADMIN);
        depositManager.setConfigOperator(address(outerToken));
        outerToken.mint(address(depositManager), 10);
        nestedToken.mint(address(depositManager), 7);
        outerToken.setCallback(
            address(depositManager),
            abi.encodeWithSignature("rescue(address)", address(nestedToken))
        );
        outerToken.setBubbleCallbackFailure(true);

        vm.prank(address(0));
        assertEq(
            IDepositManagerV1_1(address(depositManager)).previewRescue(address(outerToken)),
            10,
            "preview does not predict transfer callbacks"
        );
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vm.prank(ADMIN);
        depositManager.rescue(address(outerToken));

        assertEq(outerToken.balanceOf(address(depositManager)), 10, "outer transfer rolled back");
        assertEq(outerToken.balanceOf(address(trsry)), 0, "Treasury payment rolled back");
        assertEq(outerToken.transferCallCount(), 0, "token-side pre-callback mutation rolled back");
        assertTrue(outerToken.callbackEnabled(), "callback execution state rolled back");
        assertEq(nestedToken.balanceOf(address(depositManager)), 7, "nested custody preserved");
        assertEq(nestedToken.balanceOf(address(trsry)), 0, "nested Treasury balance unchanged");
        vm.prank(address(outerToken));
        depositManager.rescue(address(nestedToken));
        assertEq(
            nestedToken.balanceOf(address(trsry)),
            7,
            "nested authorized action works outside callback"
        );
    }

    // Scenarios: DM-RESCUE-L06.
    function test_givenActivePolicyDuringCallback_whenRescueReenters_guardWins(
        bool enabled_
    ) public givenIsEnabled {
        DepositManagerRescueCallbackActor actor = _rescueThroughActor(true, enabled_);
        assertTrue(actor.previewSucceeded(), "view does not acquire the execution guard");
        assertEq(
            abi.decode(actor.previewResult(), (uint256)),
            7,
            "nested permissionless preview returns live independent token balance"
        );
        assertFalse(
            actor.rescueSucceeded(),
            "nested rescue rejected even for current config operator"
        );
        assertEq(
            actor.rescueResult(),
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector),
            "active nested action fails at shared guard"
        );
    }

    // Scenarios: DM-RESCUE-L06.
    function test_givenInactivePolicyDuringCallback_whenRescueReenters_guardWins(
        bool enabled_
    ) public givenIsEnabled {
        DepositManagerRescueCallbackActor actor = _rescueThroughActor(false, enabled_);
        assertFalse(actor.previewSucceeded(), "preview rejects own inactivity");
        assertEq(
            actor.previewResult(),
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_PolicyInactive.selector),
            "preview has its own active-only validation"
        );
        assertFalse(actor.rescueSucceeded(), "nested rescue rejected");
        assertEq(
            actor.rescueResult(),
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector),
            "execution guard wins over own inactivity"
        );
    }

    // Scenarios: DM-RESCUE-L06.
    function test_givenEachCallbackLifecyclePair_whenRescuing_guardWins() public {
        uint256 snapshot = vm.snapshotState();
        test_givenActivePolicyDuringCallback_whenRescueReenters_guardWins(false);
        assertTrue(vm.revertToState(snapshot), "restore active disabled callback fixture");
        test_givenActivePolicyDuringCallback_whenRescueReenters_guardWins(true);
        assertTrue(vm.revertToState(snapshot), "restore active enabled callback fixture");
        test_givenInactivePolicyDuringCallback_whenRescueReenters_guardWins(false);
        assertTrue(vm.revertToState(snapshot), "restore inactive disabled callback fixture");
        test_givenInactivePolicyDuringCallback_whenRescueReenters_guardWins(true);
    }

    function _rescueThroughActor(
        bool nestedActive_,
        bool enabled_
    ) private returns (DepositManagerRescueCallbackActor actor) {
        ReentrantFeeToken outerToken = new ReentrantFeeToken();
        MockERC20 nestedToken = new MockERC20("Nested token", "NEST", 18);
        actor = new DepositManagerRescueCallbackActor(
            kernel,
            address(depositManager),
            address(nestedToken),
            nestedActive_
        );
        vm.startPrank(ADMIN);
        depositManager.setConfigOperator(address(actor));
        kernel.executeAction(Actions.ChangeExecutor, address(actor));
        vm.stopPrank();
        if (!enabled_) {
            vm.prank(EMERGENCY);
            depositManager.disable("");
        }
        outerToken.mint(address(depositManager), 10);
        nestedToken.mint(address(depositManager), 7);
        outerToken.setCallbackFrom(
            address(depositManager),
            address(actor),
            abi.encodeCall(actor.callback, ())
        );
        vm.prank(ADMIN);
        depositManager.rescue(address(outerToken));
        assertTrue(
            outerToken.callbackSucceeded(),
            "actor catches nested failure so outer transfer succeeds"
        );
        assertEq(outerToken.balanceOf(address(trsry)), 10, "outer rescue succeeds once");
        assertEq(nestedToken.balanceOf(address(depositManager)), 7, "nested token is never swept");
        assertEq(
            depositManager.isEnabled(),
            enabled_,
            "callback preserves requested local enablement"
        );
        vm.prank(address(actor));
        depositManager.rescue(address(nestedToken));
        assertEq(
            nestedToken.balanceOf(address(trsry)),
            7,
            "nested caller is authorized and executable outside guard"
        );
    }
}
