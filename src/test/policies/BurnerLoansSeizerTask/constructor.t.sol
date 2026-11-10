// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IBurnerLoansSeize} from "src/policies/interfaces/burnerloans/IBurnerLoansSeize.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansSeizerTaskTest} from "./BurnerLoansSeizerTaskTest.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansSeizerTask} from "src/policies/burnerloans/BurnerLoansSeizerTask.sol";

// Boundary literals are independent constructor inputs.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast)
contract BurnerLoansSeizerTaskConstructorTest is BurnerLoansSeizerTaskTest {
    error BindingReadFailed();

    // Scenarios: BLSZC-P01, BLSZC-P03, BLSZC-P05, BLSZC-N01.
    function test_whenBindingsMatch_thenCoreIsDerived(
        address caller_,
        uint16 checks_,
        uint8 seize_,
        uint32 gas_
    ) public {
        checks_ = uint16(bound(checks_, 1, type(uint16).max));
        seize_ = uint8(bound(seize_, 1, checks_ < type(uint8).max ? checks_ : type(uint8).max));
        gas_ = uint32(bound(gas_, 1, type(uint32).max));
        vm.prank(caller_);
        BurnerLoansSeizerTask task = new BurnerLoansSeizerTask(
            _kernel,
            _liquidation,
            _lens,
            checks_,
            seize_,
            gas_
        );
        assertEq(
            IBurnerLoansCoreBound(address(task.seize())).core(),
            address(_core),
            "Core is derived from Seize"
        );
        assertEq(task.lens(), address(_lens), "Lens bound directly");
        assertEq(
            address(task.seize()),
            address(_liquidation),
            "Task interface exposes its direct Seize dependency"
        );
        assertEq(task.maxBorrowersToCheck(), checks_, "Full scan width accepted");
        assertEq(task.maxBorrowersToSeize(), seize_, "Full seizure width accepted");
        assertEq(task.executionGasLimit(), gas_, "Full gas width accepted");
        assertFalse(task.isEnabled(), "Deployment starts disabled");
        assertFalse(_kernel.isPolicyActive(task), "Deployment does not activate policy");
        assertEq(task.getAssets().length, 0, "Initial managed asset set is empty");
        assertEq(task.nextAssetIndex(), 0, "Initial asset iterator is zero");
        assertEq(task.assetCursor(address(_asset)), 0, "Initial borrower cursor is zero");
        assertEq(task.lastTransitionAt(), 0, "Deployment has no prior local transition");
        assertEq(task.gracePeriod(), 7 days, "Initial re-enable grace is seven days");
    }

    // Scenarios: BLSZC-I04.
    function test_whenSeizeZero_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_InvalidSeize.selector,
                address(0)
            )
        );
        vm.prank(caller_);
        new BurnerLoansSeizerTask(_kernel, IBurnerLoansSeize(address(0)), _lens, 1, 1, 1);
    }

    // Scenarios: BLSZC-I05.
    function test_whenSeizeHasNoCode_reverts(address seize_) public {
        vm.assume(seize_ != address(0) && seize_.code.length == 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_InvalidSeize.selector,
                seize_
            )
        );
        new BurnerLoansSeizerTask(_kernel, IBurnerLoansSeize(seize_), _lens, 1, 1, 1);
    }

    // Scenarios: BLSZC-I01, BLSZC-I02.
    function test_whenLensHasNoCode_reverts(address lens_) public {
        vm.assume(lens_.code.length == 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_InvalidLens.selector,
                lens_
            )
        );
        new BurnerLoansSeizerTask(_kernel, _liquidation, IBurnerLoansLens(lens_), 1, 1, 1);
    }

    // Scenarios: BLSZC-I03, BLSZC-D05.
    function test_whenLensReportsDifferentCore_reverts(address otherCore_) public {
        vm.assume(otherCore_ != address(_core));
        vm.mockCall(
            address(_lens),
            abi.encodeCall(IBurnerLoansCoreBound.core, ()),
            abi.encode(otherCore_)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_InvalidLens.selector,
                address(_lens)
            )
        );
        new BurnerLoansSeizerTask(_kernel, _liquidation, _lens, 1, 1, 1);
    }

    // Scenarios: BLSZC-D06.
    function test_whenSeizeReportsDifferentKernel_reverts(address otherKernel_) public {
        vm.assume(otherKernel_ != address(_kernel));
        vm.mockCall(
            address(_liquidation),
            abi.encodeCall(_liquidation.kernel, ()),
            abi.encode(otherKernel_)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_liquidation),
                address(_kernel),
                otherKernel_
            )
        );
        new BurnerLoansSeizerTask(_kernel, _liquidation, _lens, 1, 1, 1);
    }

    // Scenarios: BLSZC-P03.
    function test_whenCoreLifecycleUnreadable_thenDeploymentUsesSeizeBinding(
        address caller_
    ) public {
        bytes memory kernelRead = abi.encodeCall(_core.kernel, ());
        bytes memory enabledRead = abi.encodeCall(_core.isEnabled, ());
        vm.mockCallRevert(address(_core), kernelRead, hex"aabbccdd");
        vm.mockCallRevert(address(_core), enabledRead, hex"aabbccdd");
        vm.expectCall(address(_core), kernelRead, uint64(0));
        vm.expectCall(address(_core), enabledRead, uint64(0));
        vm.expectCall(
            address(_kernel),
            abi.encodeWithSignature("isPolicyActive(address)", address(_core)),
            uint64(0)
        );
        vm.prank(caller_);
        BurnerLoansSeizerTask task = _newTask();
        assertEq(address(task.seize()), address(_liquidation), "Direct Seize binding");
        assertEq(
            IBurnerLoansCoreBound(address(task.seize())).core(),
            address(_core),
            "Derived Core binding"
        );
        assertFalse(task.isEnabled(), "Starts disabled");
    }

    // Scenarios: BLSZC-L01, BLSZC-L02, BLSZC-L03.
    function test_givenSeizeLifecycleState_whenDeployed_thenBindingStillSucceeds(
        address caller_,
        bool seizeActive_,
        bool seizeEnabled_
    ) public {
        if (!seizeEnabled_) _liquidation.disable("");
        if (!seizeActive_) _kernel.executeAction(Actions.DeactivatePolicy, address(_liquidation));
        vm.prank(caller_);
        BurnerLoansSeizerTask task = new BurnerLoansSeizerTask(
            _kernel,
            _liquidation,
            _lens,
            1,
            1,
            1
        );
        assertEq(
            IBurnerLoansCoreBound(address(task.seize())).core(),
            address(_core),
            "Construction checks identity without operational readiness"
        );
    }

    // Scenarios: BLSZC-D01, BLSZC-D02, BLSZC-D03.
    function test_whenSeizeInterfaceInvalid_reverts(address caller_, uint8 failure_) public {
        failure_ = uint8(bound(failure_, 0, 2));
        bytes memory query = abi.encodeWithSignature(
            "supportsInterface(bytes4)",
            type(IBurnerLoansSeize).interfaceId
        );
        if (failure_ == 0) vm.mockCall(address(_liquidation), query, abi.encode(false));
        else if (failure_ == 1) vm.mockCallRevert(address(_liquidation), query, hex"aabbccdd");
        else vm.mockCall(address(_liquidation), query, hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_InvalidSeize.selector,
                address(_liquidation)
            )
        );
        vm.prank(caller_);
        new BurnerLoansSeizerTask(_kernel, _liquidation, _lens, 1, 1, 1);
    }

    // Scenarios: BLSZC-I06.
    function test_whenScanLimitZero_reverts(uint8 seize_) public {
        seize_ = uint8(bound(seize_, 1, type(uint8).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_InvalidScanLimits.selector,
                uint16(0),
                seize_
            )
        );
        new BurnerLoansSeizerTask(_kernel, _liquidation, _lens, 0, seize_, 1);
    }

    // Scenarios: BLSZC-I07.
    function test_whenSeizeLimitZero_reverts(uint16 checks_) public {
        checks_ = uint16(bound(checks_, 1, type(uint16).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_InvalidScanLimits.selector,
                checks_,
                uint8(0)
            )
        );
        new BurnerLoansSeizerTask(_kernel, _liquidation, _lens, checks_, 0, 1);
    }

    // Scenarios: BLSZC-I08.
    function test_whenSeizeLimitExceedsScanLimit_reverts(uint16 checks_, uint8 seize_) public {
        checks_ = uint16(bound(checks_, 1, type(uint8).max - 1));
        seize_ = uint8(bound(seize_, checks_ + 1, type(uint8).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_InvalidScanLimits.selector,
                checks_,
                seize_
            )
        );
        new BurnerLoansSeizerTask(_kernel, _liquidation, _lens, checks_, seize_, 1);
    }

    // Scenarios: BLSZC-P04.
    function test_whenConstructorGasLimitZero_reverts() public {
        vm.expectRevert(IBurnerLoansSeizerTask.BurnerLoansSeizer_InvalidExecutionGasLimit.selector);
        new BurnerLoansSeizerTask(_kernel, _liquidation, _lens, 1, 1, 0);
    }

    // Scenarios: BLSZC-P01, BLSZC-P03, BLSZC-P05, BLSZC-N01.
    function test_whenConstructorBoundariesSeeded_thenAccepted() public {
        test_whenBindingsMatch_thenCoreIsDerived(_ALICE, 1, 1, 1);
        test_whenBindingsMatch_thenCoreIsDerived(
            _ALICE,
            type(uint16).max,
            type(uint8).max,
            type(uint32).max
        );
        test_whenBindingsMatch_thenCoreIsDerived(_ALICE, 501, 51, 1);
    }

    // Scenarios: BLSZC-I01.
    function test_whenLensZero_reverts() public {
        test_whenLensHasNoCode_reverts(address(0));
    }

    // Scenarios: BLSZC-P02.
    function test_whenSeizeCoreGetterReverts_thenErrorPropagates() public {
        vm.mockCallRevert(
            address(_liquidation),
            abi.encodeCall(IBurnerLoansCoreBound.core, ()),
            abi.encodeWithSelector(BindingReadFailed.selector)
        );
        vm.expectRevert(BindingReadFailed.selector);
        new BurnerLoansSeizerTask(_kernel, _liquidation, _lens, 1, 1, 1);
    }

    // Scenarios: BLSZC-T01.
    function test_whenLensCoreGetterReverts_thenErrorPropagates() public {
        vm.mockCallRevert(
            address(_lens),
            abi.encodeCall(IBurnerLoansCoreBound.core, ()),
            abi.encodeWithSelector(BindingReadFailed.selector)
        );
        vm.expectRevert(BindingReadFailed.selector);
        new BurnerLoansSeizerTask(_kernel, _liquidation, _lens, 1, 1, 1);
    }

    function _newTask() private returns (BurnerLoansSeizerTask) {
        return new BurnerLoansSeizerTask(_kernel, _liquidation, _lens, 1, 1, 1);
    }

    function _expectInvalidCore(address core_) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizerTask_InvalidCore.selector,
                core_
            )
        );
    }

    function _mockCoreBinding(address core_) private {
        vm.mockCall(
            address(_liquidation),
            abi.encodeCall(IBurnerLoansCoreBound.core, ()),
            abi.encode(core_)
        );
        vm.mockCall(
            address(_lens),
            abi.encodeCall(IBurnerLoansCoreBound.core, ()),
            abi.encode(core_)
        );
    }

    // Scenarios: BLSZC-D07.
    function test_givenZeroCore_whenConstructed_reverts(address caller_) public {
        _mockCoreBinding(address(0));
        _expectInvalidCore(address(0));
        vm.prank(caller_);
        _newTask();
    }

    // Scenarios: BLSZC-D08.
    function test_givenEoaCore_whenConstructed_reverts(address caller_, address core_) public {
        vm.assume(core_ != address(0) && core_.code.length == 0);
        _mockCoreBinding(core_);
        _expectInvalidCore(core_);
        vm.prank(caller_);
        _newTask();
    }

    // Scenarios: BLSZC-D09.
    function test_givenMissingCoreInterface_whenConstructed_reverts(address caller_) public {
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCall(address(_core), probe, abi.encode(false));
        _expectInvalidCore(address(_core));
        vm.prank(caller_);
        _newTask();
    }

    // Scenarios: BLSZC-D10.
    function test_givenRevertingCoreInterface_whenConstructed_reverts(address caller_) public {
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCallRevert(address(_core), probe, hex"deadbeef");
        _expectInvalidCore(address(_core));
        vm.prank(caller_);
        _newTask();
    }

    // Scenarios: BLSZC-D11.
    function test_givenMalformedCoreInterface_whenConstructed_reverts(address caller_) public {
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCall(address(_core), probe, hex"01");
        _expectInvalidCore(address(_core));
        vm.prank(caller_);
        _newTask();
    }

    // Scenarios: BLSZC-P06.
    function test_givenCoreLifecycle_whenConstructed(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setCoreLifecycle(active_, enabled_);
        test_whenBindingsMatch_thenCoreIsDerived(caller_, 1, 1, 1);
    }

    // Scenarios: BLSZC-P06.
    function test_whenCoreLifecycleStatesSeeded_thenAccepted() public {
        uint256 snapshot = vm.snapshotState();
        test_givenCoreLifecycle_whenConstructed(_ALICE, false, false);
        assertTrue(vm.revertToState(snapshot), "Restore disabled inactive Core");
        test_givenCoreLifecycle_whenConstructed(_ALICE, false, true);
        assertTrue(vm.revertToState(snapshot), "Restore enabled inactive Core");
        test_givenCoreLifecycle_whenConstructed(_ALICE, true, false);
        assertTrue(vm.revertToState(snapshot), "Restore disabled active Core");
        test_givenCoreLifecycle_whenConstructed(_ALICE, true, true);
        assertTrue(vm.revertToStateAndDelete(snapshot), "Restore enabled active Core");
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast)
