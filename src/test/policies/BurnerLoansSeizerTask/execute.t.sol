// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";

// Libraries
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansSeizerTaskTest} from "./BurnerLoansSeizerTaskTest.sol";
import {MockSeizerTaskDependency} from "./fixtures/MockSeizerTaskDependency.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {MockPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockPeriodicTask.sol";
import {MockPeriodicTaskManager} from "src/test/bases/PeriodicTaskManager/MockPeriodicTaskManager.sol";

// Small fixture identities and borrower populations are deliberate test boundaries.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop)
contract BurnerLoansSeizerTaskExecuteTest is BurnerLoansSeizerTaskTest {
    error ScanReadFailed();
    error SettlementFailed();

    // Scenarios: BLSEIZ-EXECUTE-P08.
    function test_givenLensExhaustsGas_whenHeartRunsTasks_thenLaterTaskExecutes() public {
        MockPeriodicTaskManager manager = new MockPeriodicTaskManager(_kernel);
        _kernel.executeAction(Actions.ActivatePolicy, address(manager));
        _rolesAdmin.grantRole(HEART_ROLE, address(manager));
        MockPeriodicTask later = new MockPeriodicTask();
        manager.addPeriodicTask(address(_task));
        manager.addPeriodicTask(address(later));
        _task.setExecutionGasLimit(200_000);
        // INVALID consumes the gas forwarded to Lens after successful task binding.
        vm.etch(address(_lens), hex"fe");
        manager.executeAllTasks{gas: 1_000_000}();
        assertEq(later.count(), 1, "Dependency gas exhaustion leaves later Heart work runnable");
        assertEq(_task.nextAssetIndex(), 1, "Gas exhaustion cannot monopolize the asset iterator");
        assertEq(_task.assetCursor(address(_asset)), 0, "Failed scan preserves borrower progress");
    }

    function setUp() public override {
        super.setUp();
        _task.addAsset(address(_asset));
        _task.addAsset(address(_otherAsset));
    }

    // Scenarios: BLSEIZ-EXECUTE-P03.
    function test_givenWholeTaskExhaustsGas_whenExecuted_thenOtherAssetGetsNextHeartbeat() public {
        _task.setExecutionGasLimit(1);
        vm.expectEmit(false, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ExecutionFailed(bytes4(0));
        _task.execute();
        assertEq(
            _task.nextAssetIndex(),
            1,
            "Outer scheduler preserves rotation after self-call exhaustion"
        );
        assertEq(_task.assetCursor(address(_asset)), 0, "Failed body preserves borrower progress");
        _task.setExecutionGasLimit(10_000_000);
        _task.execute();
        assertEq(_task.nextAssetIndex(), 0, "Next heartbeat visits B before returning to A");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-P04, BLSEIZ-EXECUTE-P02.
    function test_givenScanReverts_whenExecuted_thenOtherAssetGetsNextTurn() public {
        vm.mockCallRevert(
            address(_lens),
            _boundedScan(address(_asset), 0),
            abi.encodeWithSelector(ScanReadFailed.selector)
        );
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ScanFailed(address(_asset), ScanReadFailed.selector);
        _task.execute();
        assertEq(_task.nextAssetIndex(), 1, "Failing scan cannot monopolize visits");
        assertEq(_task.assetCursor(address(_asset)), 0, "Scan failure preserves borrower progress");
    }

    // Scenarios: BLSEIZ-EXECUTE-L01.
    function test_givenDisabled_whenExecuted_thenNoRotation() public {
        _task.disable("");
        vm.expectCall(address(_lens), _boundedScan(address(_asset), 0), uint64(0));
        vm.expectCall(
            address(_liquidation),
            abi.encodeWithSelector(_liquidation.seize.selector),
            uint64(0)
        );
        _task.execute();
        assertEq(_task.nextAssetIndex(), 0, "Paused task preserves progress");
        assertEq(_task.assetCursor(address(_asset)), 0, "Paused task preserves borrower progress");
    }

    // Scenarios: BLSEIZ-EXECUTE-A01.
    function test_whenCallerLacksHeartRole_reverts(address caller_, bool enabled_) public {
        vm.assume(!_roles.hasRole(caller_, HEART_ROLE));
        _setTaskEnabled(enabled_);
        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, HEART_ROLE));
        _task.execute();
        assertEq(_task.nextAssetIndex(), 0, "Unauthorized call preserves progress");
    }

    // Scenarios: BLSEIZ-EXECUTE-P06.
    function test_givenSeizerRoleMissing_whenExecuted_thenAssetStillRotates() public {
        _rolesAdmin.revokeRole(BURNER_LOANS_SEIZER_ROLE, address(_task));
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizerRoleMissing(address(_asset));
        vm.expectCall(address(_lens), _boundedScan(address(_asset), 0), uint64(0));
        vm.expectCall(
            address(_liquidation),
            abi.encodeWithSelector(_liquidation.seize.selector),
            uint64(0)
        );
        _task.execute();
        assertEq(_task.nextAssetIndex(), 1, "Missing authority does not monopolize scheduling");
        _rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, address(_task));
        _task.execute();
        assertEq(_task.nextAssetIndex(), 0, "Granting the role restores ordinary scheduling");
    }

    // Scenarios: BLSEIZ-EXECUTE-P01.
    function test_givenNoAssets_whenExecuted_thenNoWork() public {
        _task.removeAsset(address(_asset));
        _task.removeAsset(address(_otherAsset));
        vm.expectCall(
            address(_lens),
            abi.encodeWithSelector(_lens.getSeizableBorrowersBoundedFor.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_liquidation),
            abi.encodeWithSelector(_liquidation.seize.selector),
            uint64(0)
        );
        _task.execute();
        assertEq(_task.nextAssetIndex(), 0, "Empty registry preserves zero iterator");
    }

    // Scenarios: BLSEIZ-EXECUTE-A02, BLSEIZ-EXECUTE-P05.
    function test_givenHeartRole_whenExecuted_thenAssetRotates(address caller_) public {
        vm.assume(caller_ != address(0));
        if (!_roles.hasRole(caller_, HEART_ROLE)) _rolesAdmin.grantRole(HEART_ROLE, caller_);
        vm.prank(caller_);
        _task.execute();
        assertEq(_task.nextAssetIndex(), 1, "Every permitted Heart caller processes only A");
    }

    // Scenarios: BLSEIZ-EXECUTE-L02, BLSEIZ-EXECUTE-L03.
    function test_givenTaskInactive_whenExecuted_reverts(bool enabled_) public {
        _setTaskEnabled(enabled_);
        _setPolicyActive(address(_task), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_task)
            )
        );
        _task.execute();
        assertEq(_task.nextAssetIndex(), 0, "Inactive task cannot advance asset progress");
    }

    // Scenarios: BLSEIZ-EXECUTE-P09.
    function test_givenSelfCallCustomError_whenExecuted_thenSelectorIsReported() public {
        vm.mockCallRevert(
            address(_task),
            abi.encodeCall(_task.selfExecuteTask, ()),
            abi.encodeWithSelector(SettlementFailed.selector)
        );
        vm.expectEmit(false, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ExecutionFailed(SettlementFailed.selector);
        _task.execute();
        assertEq(_task.nextAssetIndex(), 1, "Custom-error failure rotates assets");
    }

    // Scenarios: BLSEIZ-EXECUTE-P10.
    function test_givenSelfCallShortError_whenExecuted_thenPrefixIsZeroPadded() public {
        vm.mockCallRevert(address(_task), abi.encodeCall(_task.selfExecuteTask, ()), hex"ab");
        vm.expectEmit(false, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ExecutionFailed(bytes4(0xab000000));
        _task.execute();
        assertEq(_task.nextAssetIndex(), 1, "Short-error failure rotates assets");
    }

    // Scenarios: BLSEIZ-EXECUTE-P11.
    function test_givenSelfCallLargeError_whenExecuted_thenOnlySelectorIsCopied() public {
        bytes memory failure = new bytes(100_000);
        failure[0] = 0xab;
        failure[1] = 0xcd;
        failure[2] = 0xef;
        failure[3] = 0x01;
        vm.mockCallRevert(address(_task), abi.encodeCall(_task.selfExecuteTask, ()), failure);
        vm.expectEmit(false, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ExecutionFailed(bytes4(0xabcdef01));
        _task.execute();
        assertEq(_task.nextAssetIndex(), 1, "Large-error failure rotates assets");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-P14.
    function test_givenBorrowerCountReadReverts_whenExecuted_thenCursorPreservedAndAssetsRotate()
        public
    {
        MockSeizerTaskDependency(address(_lens)).setScanResult(
            address(_asset),
            new address[](0),
            1
        );
        _task.execute();
        _task.execute(); // B's turn.
        vm.mockCallRevert(
            address(_lens),
            abi.encodeCall(_lens.getActiveBorrowerCount, (address(_asset))),
            abi.encodeWithSelector(ScanReadFailed.selector)
        );
        vm.expectCall(address(_lens), _boundedScan(address(_asset), 1), uint64(0));
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ScanFailed(address(_asset), ScanReadFailed.selector);
        _task.execute();
        assertEq(_task.assetCursor(address(_asset)), 1, "Count failure preserves the saved cursor");
        assertEq(_task.nextAssetIndex(), 1, "Count failure still gives the next asset its turn");
    }

    function test_whenScanReturnsBorrowers_thenForwardsExactBatchAndRewindsCursor() public {
        address[] memory borrowers = _two(_ALICE, _BOB);
        MockSeizerTaskDependency(address(_lens)).setScanResult(address(_asset), borrowers, 6);
        vm.expectCall(address(_lens), _boundedScan(address(_asset), 0), uint64(1));
        vm.expectCall(
            address(_liquidation),
            abi.encodeCall(_liquidation.seize, (address(_asset), borrowers)),
            uint64(1)
        );
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureExecuted(address(_asset), 0, 4, 2);
        _task.execute();
        assertEq(
            _task.assetCursor(address(_asset)),
            4,
            "Six scanned entries minus two removals rewinds to four"
        );
        assertEq(_task.nextAssetIndex(), 1, "Only one asset is processed per execution");
    }

    function test_whenScanReturnsNoBorrowers_thenStoresCursorWithoutSettlement() public {
        MockSeizerTaskDependency(address(_lens)).setScanResult(
            address(_asset),
            new address[](0),
            4
        );
        vm.expectCall(
            address(_liquidation),
            abi.encodeWithSelector(_liquidation.seize.selector),
            uint64(0)
        );
        _task.execute();
        assertEq(
            _task.assetCursor(address(_asset)),
            4,
            "Healthy scan progress is committed without seizure"
        );
        MockSeizerTaskDependency(address(_lens)).setScanResult(
            address(_asset),
            new address[](0),
            0
        );
        _task.execute(); // Other asset receives its turn.
        _task.execute();
        assertEq(_task.assetCursor(address(_asset)), 0, "Population end wraps the borrower cursor");
    }

    // Scenarios: BLSEIZ-EXECUTE-P04.
    function test_givenOneAsset_whenExecuted_thenTraversalRemainsZero() public {
        _task.removeAsset(address(_otherAsset));
        MockSeizerTaskDependency(address(_lens)).setScanResult(
            address(_asset),
            new address[](0),
            4
        );
        vm.expectCall(address(_lens), _boundedScan(address(_asset), 0), uint64(1));
        vm.expectCall(
            address(_liquidation),
            abi.encodeWithSelector(_liquidation.seize.selector),
            uint64(0)
        );
        _task.execute();
        assertEq(_task.nextAssetIndex(), 0, "Single managed asset wraps to itself");
        assertEq(
            _task.assetCursor(address(_asset)),
            4,
            "Borrower progress follows the scan result"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-L02, BLSEIZ-EXECUTE-L03.
    function test_givenInactive_whenUnauthorizedAndInvalid_reverts(
        address caller_,
        bool enabled_
    ) public {
        vm.assume(!_roles.hasRole(caller_, HEART_ROLE));
        if (!enabled_) _task.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_task));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_task)
            )
        );
        vm.prank(caller_);
        _task.execute();
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop)
