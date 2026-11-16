// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";
import {IDiscoveryRoles} from "./fixtures/IDiscoveryDependencies.sol";

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

    // Scenarios: BLSEIZ-EXECUTE-P06, BLSEIZ-SELF-EXECUTE-P01.
    function test_givenSeizerRoleMissing_whenExecuted_thenAssetStillRotates() public {
        _rolesAdmin.revokeRole(BURNER_LOANS_SEIZER_ROLE, address(_task));
        vm.mockCallRevert(
            address(_lens),
            abi.encodeWithSelector(_lens.getExpiredBorrowersBoundedFor.selector),
            abi.encodeWithSelector(ScanReadFailed.selector)
        );
        vm.mockCallRevert(
            address(_lens),
            abi.encodeWithSelector(_lens.getSeizableBorrowersBoundedFor.selector),
            abi.encodeWithSelector(ScanReadFailed.selector)
        );
        vm.mockCallRevert(
            address(_lens),
            abi.encodeWithSelector(_lens.getActiveBorrowerCount.selector),
            abi.encodeWithSelector(ScanReadFailed.selector)
        );
        vm.mockCallRevert(
            address(_liquidation),
            abi.encodeWithSelector(_liquidation.seize.selector),
            abi.encodeWithSelector(SettlementFailed.selector)
        );
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizerRoleMissing(address(_asset));
        vm.expectCall(address(_lens), _boundedScan(address(_asset), 0), uint64(0));
        vm.expectCall(address(_lens), _expiryScan(0), uint64(0));
        vm.expectCall(
            address(_liquidation),
            abi.encodeWithSelector(_liquidation.seize.selector),
            uint64(0)
        );
        _task.execute();
        assertEq(_task.nextAssetIndex(), 1, "Missing authority does not monopolize scheduling");
        assertEq(
            _task.assetCursor(address(_asset)),
            0,
            "Missing authority retains borrower progress"
        );
        vm.clearMockedCalls();
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

    // Scenarios: BLSEIZ-EXECUTE-D07, BLSEIZ-SELF-EXECUTE-D07.
    function test_givenExpiredScan_givenHelperExhaustsGas_whenExecuted_thenLaterHeartTaskExecutes()
        public
    {
        MockPeriodicTaskManager manager = new MockPeriodicTaskManager(_kernel);
        _kernel.executeAction(Actions.ActivatePolicy, address(manager));
        _rolesAdmin.grantRole(HEART_ROLE, address(manager));
        MockPeriodicTask later = new MockPeriodicTask();
        manager.addPeriodicTask(address(_task));
        manager.addPeriodicTask(address(later));
        _mockCount(10);
        _task.setNextAssetBorrowerIndex(address(_asset), 9);
        _mockCount(1);
        _task.setExecutionGasLimit(200_000);
        address[] memory borrowers = _one(_ALICE);
        vm.mockCallRevert(
            address(_lens),
            _boundedScan(address(_asset), 0),
            abi.encodeWithSelector(ScanReadFailed.selector)
        );
        bytes memory expiredScan = abi.encodeWithSelector(
            _lens.getExpiredBorrowersBoundedFor.selector,
            address(_task),
            address(_asset)
        );
        vm.mockCall(address(_lens), expiredScan, abi.encode(borrowers, uint256(1), uint256(0)));
        bytes memory settlement = abi.encodeCall(_liquidation.seize, (address(_asset), borrowers));
        // Copying this return data in the helper's catch exceeds the entire metered body budget.
        vm.mockCallRevert(address(_liquidation), settlement, new bytes(1_000_000));
        vm.expectCall(address(_lens), expiredScan, uint64(1));
        vm.expectCall(address(_liquidation), settlement, uint64(1));
        vm.expectEmit(false, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ExecutionFailed(bytes4(0));
        manager.executeAllTasks{gas: 1_000_000}();
        assertEq(
            _task.assetCursor(address(_asset)),
            9,
            "Unexpected helper failure rolls back the stale-cursor repair"
        );
        assertEq(_task.nextAssetIndex(), 1, "Outer failure boundary retains one asset rotation");
        assertEq(later.count(), 1, "Helper exhaustion cannot prevent later Heart tasks");
        vm.clearMockedCalls();
        _task.execute();
        assertEq(
            _task.nextAssetIndex(),
            0,
            "Other asset receives the next heartbeat after helper failure"
        );
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

    // Scenarios: BLSEIZ-SELF-EXECUTE-P15.
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

    // Scenarios: BLSEIZ-SELF-EXECUTE-P18.
    function test_whenScanReturnsNoBorrowers_thenStoresCursorWithoutSettlement() public {
        _mockCount(5);
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
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureExecuted(address(_asset), 0, 4, 0);
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
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureExecuted(address(_asset), 4, 0, 0);
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
        vm.expectCall(address(_lens), _expiryScan(0), uint64(1));
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

    // Scenarios: BLSEIZ-SELF-EXECUTE-D01.
    function test_givenExpiryCandidates_whenExecuted_thenOnlyExpiryBatchSettles() public {
        address[] memory borrowers = _two(_ALICE, _BOB);
        vm.mockCall(address(_lens), _expiryScan(0), abi.encode(borrowers, uint256(6), uint256(0)));
        _expectNoPricedDiscovery();
        vm.expectCall(address(_lens), _expiryScan(0), uint64(1));
        vm.expectCall(
            address(_liquidation),
            abi.encodeCall(_liquidation.seize, (address(_asset), borrowers)),
            uint64(1)
        );
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureExecuted(address(_asset), 0, 4, 2);
        _task.execute();
        assertEq(_task.assetCursor(address(_asset)), 4, "Expiry batch rewinds for two removals");
        assertEq(_task.nextAssetIndex(), 1, "Expiry batch consumes one asset turn");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-P16.
    function test_givenExpiryNextEqualsBatchLength_whenExecuted_thenCursorIsZero() public {
        vm.mockCall(
            address(_lens),
            _expiryScan(0),
            abi.encode(_two(_ALICE, _BOB), uint256(2), uint256(0))
        );
        _expectNoPricedDiscovery();
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureExecuted(address(_asset), 0, 0, 2);
        _task.execute();
        assertEq(_task.assetCursor(address(_asset)), 0, "Exact rewind boundary remains zero");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-D02, BLSEIZ-SELF-EXECUTE-D06.
    function test_givenStaleCursor_givenExpirySettlementFails_whenExecuted_thenRepairPersists()
        public
    {
        _mockCount(10);
        _task.setNextAssetBorrowerIndex(address(_asset), 9);
        _mockCount(1);
        vm.mockCall(
            address(_lens),
            _expiryScan(0),
            abi.encode(_one(_ALICE), uint256(0), uint256(0))
        );
        vm.mockCallRevert(
            address(_liquidation),
            abi.encodeCall(_liquidation.seize, (address(_asset), _one(_ALICE))),
            abi.encodeWithSelector(SettlementFailed.selector)
        );
        _expectNoPricedDiscovery();
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureFailed(address(_asset), SettlementFailed.selector);
        _task.execute();
        assertEq(
            _task.assetCursor(address(_asset)),
            0,
            "Caught settlement failure retains repaired offset"
        );
        assertEq(_task.nextAssetIndex(), 1, "Failed expiry batch rotates exactly once");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-D03, BLSEIZ-SELF-EXECUTE-D05.
    function test_givenValidCursor_givenExpiryScanFails_whenExecuted_thenCursorIsRetained() public {
        _mockCount(10);
        _task.setNextAssetBorrowerIndex(address(_asset), 7);
        vm.mockCallRevert(
            address(_lens),
            _expiryScan(7),
            abi.encodeWithSelector(ScanReadFailed.selector)
        );
        vm.expectCall(address(_lens), _expiryScan(7), uint64(1));
        _expectNoPricedDiscovery();
        vm.expectCall(
            address(_liquidation),
            abi.encodeWithSelector(_liquidation.seize.selector),
            uint64(0)
        );
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ScanFailed(address(_asset), ScanReadFailed.selector);
        _task.execute();
        assertEq(
            _task.assetCursor(address(_asset)),
            7,
            "Failed expiry discovery retains valid retry start"
        );
        assertEq(_task.nextAssetIndex(), 1, "Expiry failure leaves the next asset reachable");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-D04.
    function test_givenEmptyExpiryPage_givenPricedFailure_whenExecuted_thenProvenCursorIsStored(
        uint8 next_
    ) public {
        uint256 next = bound(next_, 0, 4);
        vm.mockCall(address(_lens), _expiryScan(0), abi.encode(new address[](0), next, uint256(0)));
        vm.mockCallRevert(
            address(_lens),
            _boundedScan(address(_asset), 0),
            abi.encodeWithSelector(ScanReadFailed.selector)
        );
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ScanFailed(address(_asset), ScanReadFailed.selector);
        _task.execute();
        assertEq(
            _task.assetCursor(address(_asset)),
            next,
            "Priced failure commits only proven expiry-empty progress"
        );
        assertEq(_task.nextAssetIndex(), 1, "Priced failure consumes one turn");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-D08.
    function test_givenZeroCursor_givenCountReadBroken_whenExecuted_thenDiscoveryStillRuns()
        public
    {
        vm.mockCallRevert(
            address(_lens),
            abi.encodeCall(_lens.getActiveBorrowerCount, (address(_asset))),
            abi.encodeWithSelector(ScanReadFailed.selector)
        );
        vm.expectCall(
            address(_lens),
            abi.encodeCall(_lens.getActiveBorrowerCount, (address(_asset))),
            uint64(0)
        );
        vm.expectCall(address(_lens), _expiryScan(0), uint64(1));
        vm.expectCall(address(_lens), _boundedScan(address(_asset), 0), uint64(1));
        _task.execute();
        assertEq(_task.nextAssetIndex(), 1, "Zero cursor needs no count read");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-N03.
    function test_givenMaximumLimits_whenExecuted_thenBothStagesReceiveFullWidthInputs() public {
        _task.setScanLimits(type(uint16).max, type(uint8).max);
        _mockCount(1);
        vm.expectCall(address(_lens), _expiryScan(0), uint64(1));
        vm.expectCall(address(_lens), _boundedScan(address(_asset), 0), uint64(1));
        _task.execute();
        assertEq(
            _task.assetCursor(address(_asset)),
            0,
            "Small population wraps under full-width caps"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-D20.
    function test_givenMalformedExpiryReturn_whenExecuted_thenOuterBoundaryRotates() public {
        vm.mockCall(address(_lens), _expiryScan(0), hex"00");
        _expectNoPricedDiscovery();
        vm.expectEmit(false, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ExecutionFailed(bytes4(0));
        _task.execute();
        assertEq(
            _task.assetCursor(address(_asset)),
            0,
            "Malformed return rolls back body progress"
        );
        assertEq(_task.nextAssetIndex(), 1, "Outer boundary rotates after ABI decode failure");
    }

    // Scenarios: BLSEIZ-EXECUTE-D20.
    function test_givenMalformedPricedReturn_whenExecuted_thenOuterBoundaryRotates() public {
        vm.mockCall(
            address(_lens),
            _expiryScan(0),
            abi.encode(new address[](0), uint256(4), uint256(0))
        );
        vm.mockCall(address(_lens), _boundedScan(address(_asset), 0), hex"00");
        vm.expectEmit(false, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ExecutionFailed(bytes4(0));
        _task.execute();
        assertEq(
            _task.assetCursor(address(_asset)),
            0,
            "Decode failure does not commit expiry-empty cursor"
        );
        assertEq(_task.nextAssetIndex(), 1, "Outer recovery consumes only one asset turn");
    }

    // Scenarios: BLSEIZ-EXECUTE-D23.
    function test_givenMissingExpirySelector_whenExecuted_thenNoPricedFallback() public {
        // A compatible bound helper can still lack this newer optional selector.
        vm.mockCallRevert(address(_lens), _expiryScan(0), hex"");
        _expectNoPricedDiscovery();
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ScanFailed(address(_asset), bytes4(0));
        _task.execute();
        assertEq(
            _task.assetCursor(address(_asset)),
            0,
            "Missing capability retains retry progress"
        );
        assertEq(_task.nextAssetIndex(), 1, "Missing capability does not monopolize scheduling");
    }

    // Scenarios: BLSEIZ-EXECUTE-P17.
    function test_givenGasBelowReserve_whenExecuted_thenNoBodyAndOneRotation() public {
        vm.expectCall(address(_task), abi.encodeCall(_task.selfExecuteTask, ()), uint64(0));
        vm.expectEmit(false, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ExecutionFailed(bytes4(0));
        _task.execute{gas: 50_000}();
        assertEq(_task.nextAssetIndex(), 1, "Cleanup rotates without entering the task body");
        assertEq(
            _task.assetCursor(address(_asset)),
            0,
            "No-body execution preserves borrower progress"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-P18.
    function test_givenEmptyRegistry_givenGasBelowReserve_whenExecuted_thenNoBody() public {
        _task.removeAsset(address(_asset));
        _task.removeAsset(address(_otherAsset));
        vm.expectCall(address(_task), abi.encodeCall(_task.selfExecuteTask, ()), uint64(0));
        vm.expectEmit(false, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ExecutionFailed(bytes4(0));
        _task.execute{gas: 50_000}();
        assertEq(_task.nextAssetIndex(), 0, "Empty registry cleanup avoids modulo by zero");
    }

    // Scenarios: BLSEIZ-EXECUTE-D21.
    function test_givenEmptyRegistry_givenBodyReverts_whenExecuted_thenFailureIsReported() public {
        _task.removeAsset(address(_asset));
        _task.removeAsset(address(_otherAsset));
        vm.mockCallRevert(
            address(_task),
            abi.encodeCall(_task.selfExecuteTask, ()),
            abi.encodeWithSelector(SettlementFailed.selector)
        );
        vm.expectEmit(false, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ExecutionFailed(SettlementFailed.selector);
        _task.execute();
        assertEq(
            _task.nextAssetIndex(),
            0,
            "Empty registry failure cannot rotate or divide by zero"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-T01.
    function test_givenKernelActivityReadFails_whenExecuted_reverts() public {
        vm.mockCallRevert(
            address(_kernel),
            abi.encodeCall(_kernel.isPolicyActive, (_task)),
            abi.encodeWithSelector(ScanReadFailed.selector)
        );
        vm.expectCall(address(_task), abi.encodeCall(_task.selfExecuteTask, ()), uint64(0));
        vm.expectRevert(ScanReadFailed.selector);
        _task.execute();
        assertEq(_task.nextAssetIndex(), 0, "Admission failure does not consume an asset turn");
    }

    // Scenarios: BLSEIZ-EXECUTE-P22.
    function test_givenTaskHeartOnly_whenExecuted_thenSeizerGrantStillRequired() public {
        _rolesAdmin.grantRole(HEART_ROLE, address(_task));
        _rolesAdmin.revokeRole(BURNER_LOANS_SEIZER_ROLE, address(_task));
        vm.expectCall(address(_lens), _expiryScan(0), uint64(0));
        _expectNoPricedDiscovery();
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizerRoleMissing(address(_asset));
        _task.execute();
        assertEq(_task.nextAssetIndex(), 1, "HEART-only Task still rotates without discovery");
        assertEq(
            _task.assetCursor(address(_asset)),
            0,
            "HEART-only Task retains borrower progress"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-T02.
    function test_givenHeartRoleReadFails_whenExecuted_reverts(bool enabled_) public {
        _setTaskEnabled(enabled_);
        vm.mockCallRevert(
            address(_roles),
            abi.encodeCall(ROLESv1.requireRole, (HEART_ROLE, address(this))),
            abi.encodeWithSelector(ScanReadFailed.selector)
        );
        vm.expectCall(address(_task), abi.encodeCall(_task.selfExecuteTask, ()), uint64(0));
        vm.expectRevert(ScanReadFailed.selector);
        _task.execute();
        assertEq(_task.nextAssetIndex(), 0, "Role lookup failure propagates before disabled no-op");
    }

    // Scenarios: BLSEIZ-EXECUTE-D22.
    function test_givenTaskSeizerRoleReadFails_whenExecuted_thenOuterBoundaryRotates() public {
        vm.mockCallRevert(
            address(_roles),
            abi.encodeCall(IDiscoveryRoles.hasRole, (address(_task), BURNER_LOANS_SEIZER_ROLE)),
            abi.encodeWithSelector(ScanReadFailed.selector)
        );
        vm.expectCall(address(_lens), _expiryScan(0), uint64(0));
        vm.expectEmit(false, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ExecutionFailed(ScanReadFailed.selector);
        _task.execute();
        assertEq(_task.nextAssetIndex(), 1, "Body role lookup failure consumes one asset turn");
        assertEq(
            _task.assetCursor(address(_asset)),
            0,
            "Body role lookup failure preserves borrower progress"
        );
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-P17.
    function test_givenExpiryBatchAtPopulationEnd_whenExecuted_thenCursorRemainsZero() public {
        vm.mockCall(
            address(_lens),
            _expiryScan(0),
            abi.encode(_two(_ALICE, _BOB), uint256(0), uint256(0))
        );
        _expectNoPricedDiscovery();
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureExecuted(address(_asset), 0, 0, 2);
        _task.execute();
        assertEq(
            _task.assetCursor(address(_asset)),
            0,
            "End sentinel is not subtracted below zero"
        );
    }

    function _expiryScan(uint256 start_) private view returns (bytes memory) {
        return
            abi.encodeCall(
                IBurnerLoansLens.getExpiredBorrowersBoundedFor,
                (
                    address(_task),
                    address(_asset),
                    start_,
                    uint256(_task.maxBorrowersToCheck()),
                    uint256(_task.maxBorrowersToSeize())
                )
            );
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-P08.
    function test_givenLensExhaustsGas_givenCatchGasSufficient_whenHeartRunsTasks() public {
        MockPeriodicTaskManager manager = new MockPeriodicTaskManager(_kernel);
        _kernel.executeAction(Actions.ActivatePolicy, address(manager));
        _rolesAdmin.grantRole(HEART_ROLE, address(manager));
        MockPeriodicTask later = new MockPeriodicTask();
        manager.addPeriodicTask(address(_task));
        manager.addPeriodicTask(address(later));
        _task.setExecutionGasLimit(1_000_000);
        vm.etch(address(_lens), hex"fe");
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ScanFailed(address(_asset), bytes4(0));
        manager.executeAllTasks{gas: 2_000_000}();
        assertEq(
            _task.assetCursor(address(_asset)),
            0,
            "Caught dependency exhaustion retains borrower progress"
        );
        assertEq(_task.nextAssetIndex(), 1, "Caught dependency exhaustion rotates assets");
        assertEq(later.count(), 1, "Sufficient catch gas preserves subsequent Heart work");
    }

    function _expectNoPricedDiscovery() private {
        vm.expectCall(
            address(_lens),
            abi.encodeWithSelector(_lens.getSeizableBorrowersBoundedFor.selector),
            uint64(0)
        );
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop)
