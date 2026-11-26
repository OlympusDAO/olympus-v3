// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";

// Contracts
import {BurnerLoansSeizerTaskTest} from "./BurnerLoansSeizerTaskTest.sol";
import {MockSeizerTaskDependency} from "./fixtures/MockSeizerTaskDependency.sol";

contract BurnerLoansSeizerTaskSelfExecuteTaskTest is BurnerLoansSeizerTaskTest {
    // Scenarios: BLSEIZ-SELF-EXECUTE-A01.
    function test_whenCallerIsNotSelf_reverts(address caller_) public {
        vm.assume(caller_ != address(_task));
        vm.expectRevert(IBurnerLoansSeizerTask.BurnerLoansSeizer_OnlySelf.selector);
        vm.prank(caller_);
        _task.selfExecuteTask();
        assertEq(_task.nextAssetIndex(), 0, "Rejected self-call preserves progress");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-L01.
    function test_givenTaskInactive_whenSelfCalls_reverts(bool disabled_) public {
        _setTaskEnabled(!disabled_);
        _setPolicyActive(address(_task), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_task)
            )
        );
        vm.prank(address(_task));
        _task.selfExecuteTask();
        assertEq(_task.nextAssetIndex(), 0, "Inactive self-call cannot mutate progress");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-L02.
    function test_givenDisabled_whenSelfCalls_thenBodyStillRuns() public {
        vm.prank(_seizerAdmin);
        _task.addAsset(address(_asset));
        vm.prank(_seizerAdmin);
        _task.addAsset(address(_otherAsset));
        vm.prank(_seizerAdmin);
        _task.disable("");
        vm.expectCall(
            address(_lens),
            abi.encodeCall(
                IBurnerLoansLens.getExpiredBorrowersBoundedFor,
                (address(_task), address(_asset), uint256(0), uint256(500), uint256(25))
            ),
            uint64(1)
        );
        vm.prank(address(_task));
        _task.selfExecuteTask();
        assertEq(_task.nextAssetIndex(), 1, "Self-only body does not enforce local pause");
        assertFalse(_task.isEnabled(), "Body does not enable the task");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-A02.
    function test_givenInactive_givenRolesBroken_whenCallerIsNotSelf_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != address(_task));
        _setPolicyActive(address(_task), false);
        vm.etch(address(_roles), hex"fe");
        vm.expectRevert(IBurnerLoansSeizerTask.BurnerLoansSeizer_OnlySelf.selector);
        vm.prank(caller_);
        _task.selfExecuteTask();
        assertEq(_task.nextAssetIndex(), 0, "Self-only check precedes lifecycle and role reads");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-N01.
    function test_givenEmptyRegistry_whenSelfCalls_thenNoWork() public {
        vm.prank(address(_task));
        _task.selfExecuteTask();
        assertEq(_task.nextAssetIndex(), 0, "Empty registry remains at zero");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-N01.
    function test_givenSingleAsset_whenSelfCalls_thenCursorWraps() public {
        vm.prank(_seizerAdmin);
        _task.addAsset(address(_asset));
        vm.prank(address(_task));
        _task.selfExecuteTask();
        assertEq(_task.nextAssetIndex(), 0, "One managed asset wraps to itself");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-N01.
    function test_givenTwoAssets_whenPendingIndexSelected(uint256 pending_) public {
        uint256 pending = bound(pending_, 0, 1);
        vm.prank(_seizerAdmin);
        _task.addAsset(address(_asset));
        vm.prank(_seizerAdmin);
        _task.addAsset(address(_otherAsset));
        vm.prank(_seizerAdmin);
        _task.setNextAssetIndex(pending);
        address selected = pending == 0 ? address(_asset) : address(_otherAsset);
        vm.expectCall(
            address(_lens),
            abi.encodeCall(
                IBurnerLoansLens.getExpiredBorrowersBoundedFor,
                (address(_task), selected, uint256(0), uint256(500), uint256(25))
            ),
            uint64(1)
        );
        vm.prank(address(_task));
        _task.selfExecuteTask();
        assertEq(
            _task.nextAssetIndex(),
            1 - pending,
            "Two-asset body advances or wraps exactly once"
        );
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-N01.
    function test_givenAssetRemoved_whenSelfCalls_thenSurvivorIsVisited(bool removeFirst_) public {
        vm.prank(_seizerAdmin);
        _task.addAsset(address(_asset));
        vm.prank(_seizerAdmin);
        _task.addAsset(address(_otherAsset));
        vm.prank(_seizerAdmin);
        _task.setNextAssetIndex(1);
        address removed = removeFirst_ ? address(_asset) : address(_otherAsset);
        address survivor = removeFirst_ ? address(_otherAsset) : address(_asset);
        MockSeizerTaskDependency(address(_lens)).setPopulation(removed, 3);
        vm.prank(_seizerAdmin);
        _task.setExpiredAssetCursor(removed, 1);
        vm.prank(_seizerAdmin);
        _task.setUnhealthyAssetCursor(removed, 2);
        vm.prank(_seizerAdmin);
        _task.removeAsset(removed);
        vm.expectCall(
            address(_lens),
            abi.encodeCall(
                IBurnerLoansLens.getExpiredBorrowersBoundedFor,
                (address(_task), survivor, uint256(0), uint256(500), uint256(25))
            ),
            uint64(1)
        );
        vm.prank(address(_task));
        _task.selfExecuteTask();
        assertEq(_task.nextAssetIndex(), 0, "Registry shrink leaves a valid pending asset");
        assertEq(
            _task.expiredAssetCursor(removed),
            0,
            "Removed asset borrower cursor remains clear"
        );
        assertEq(
            _task.unhealthyAssetCursor(removed),
            0,
            "Removed asset borrower cursor remains clear"
        );
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-N02.
    function test_givenMaximumDefensiveAssetIndex_whenSelfCalls_thenIndexNormalizes() public {
        vm.prank(_seizerAdmin);
        _task.addAsset(address(_asset));
        vm.prank(_seizerAdmin);
        _task.addAsset(address(_otherAsset));
        // Public setters reject this unreachable state. Discover only this getter's slot for injection.
        vm.record();
        _task.nextAssetIndex();
        (bytes32[] memory reads, ) = vm.accesses(address(_task));
        vm.store(address(_task), reads[0], bytes32(type(uint256).max));
        vm.expectCall(
            address(_lens),
            abi.encodeCall(
                IBurnerLoansLens.getExpiredBorrowersBoundedFor,
                (address(_task), address(_otherAsset), uint256(0), uint256(500), uint256(25))
            ),
            uint64(1)
        );
        vm.prank(address(_task));
        _task.selfExecuteTask();
        assertEq(_task.nextAssetIndex(), 0, "MAX256 modulo two selects the last asset then wraps");
    }
}
