// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast)

// Interfaces
import {Vm} from "forge-std/Vm.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

// Libraries

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventorySetGracePeriodTest is BurnerLoansInventoryTest {
    uint32 internal constant _ONE_DAY = 1 days;

    function test_givenConstructed_setsDefaultGracePeriod() public view {
        assertEq(inventory.gracePeriod(), 7 days, "default grace period");
    }

    // Scenarios: BLINVGR-A01.
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        _initializeAndEnable();

        _expectAdminRole();
        vm.prank(caller_);
        inventory.setGracePeriod(_ONE_DAY);
    }

    function test_givenBurnerLoansAdminCaller_reverts() public {
        _initializeAndEnable();

        _expectAdminRole();
        vm.prank(burnerLoansAdmin);
        inventory.setGracePeriod(_ONE_DAY);
    }

    // Scenarios: BLINVGR-I01.
    function test_givenZeroPeriod_reverts() public {
        _initializeAndEnable();

        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(admin);
        inventory.setGracePeriod(0);
    }

    function test_givenDisabled_reverts() public {
        _expectNotEnabled();
        vm.prank(admin);
        inventory.setGracePeriod(_ONE_DAY);
    }

    // Scenarios: BLINVGR-N01.
    function test_givenValidPeriod_setsPeriod(uint32 period_) public {
        period_ = uint32(bound(period_, 1, type(uint32).max));
        _initializeAndEnable();

        vm.prank(admin);
        inventory.setGracePeriod(period_);

        assertEq(inventory.gracePeriod(), period_, "grace period should be updated");
    }

    // Scenarios: BLINVGR-N01.
    function test_givenMaximumPeriod_setsPeriod() public {
        _initializeAndEnable();

        vm.prank(admin);
        inventory.setGracePeriod(type(uint32).max);

        assertEq(inventory.gracePeriod(), type(uint32).max, "maximum grace period");
    }

    function _assertGraceUnchanged(
        bytes32 accounting_,
        uint48 transition_,
        uint32 grace_
    ) internal view {
        assertEq(inventory.gracePeriod(), grace_, "Grace unchanged");
        assertEq(inventory.lastTransitionAt(), transition_, "No lifecycle transition");
        assertEq(_accountingState(), accounting_, "No custody or obligation changes");
    }

    // Scenarios: BLINVGR-L01, BLINVGR-L03.
    function test_givenDisabledInventory_whenGraceSet_reverts(
        address caller_,
        uint32 period_
    ) public {
        _setPolicyActive(address(inventory), true);
        bytes32 beforeState = _accountingState();
        _expectNotEnabled();
        vm.prank(caller_);
        inventory.setGracePeriod(period_);
        _assertGraceUnchanged(beforeState, 0, 7 days);
    }

    // Scenarios: BLINVGR-L02, BLINVGR-L04.
    function test_givenInactiveDisabledInventory_whenGraceSet_reverts(
        address caller_,
        uint32 period_
    ) public {
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(caller_);
        inventory.setGracePeriod(period_);
        _assertGraceUnchanged(beforeState, 0, 7 days);
    }

    // Scenarios: BLINVGR-L06, BLINVGR-L08, BLINVGR-L10, BLINVGR-L12.
    function test_givenInactiveEnabledInventory_whenGraceSet_reverts(
        uint32 period_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        _initializeAndEnable();
        _deactivateInventory();
        _setPolicyActive(address(facility), coreActive_);
        _mockFacilityEnabled(coreEnabled_);
        bytes32 beforeState = _accountingState();
        uint48 transitionBefore = inventory.lastTransitionAt();
        _expectInventoryNotActive();
        vm.prank(admin);
        inventory.setGracePeriod(period_);
        _assertGraceUnchanged(beforeState, transitionBefore, 7 days);
    }

    // Scenarios: BLINVGR-L05, BLINVGR-L07, BLINVGR-L09, BLINVGR-L11.
    function test_givenActiveEnabledInventory_whenGraceSet_succeeds(
        uint32 period_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        _initializeAndEnable();
        _setPolicyActive(address(facility), coreActive_);
        _mockFacilityEnabled(coreEnabled_);
        period_ = uint32(bound(period_, 1, type(uint32).max));
        bytes32 beforeState = _accountingState();
        uint48 transitionBefore = inventory.lastTransitionAt();
        vm.expectEmit(address(inventory));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(admin);
        inventory.setGracePeriod(period_);
        assertEq(inventory.gracePeriod(), period_, "Exact configured grace");
        assertEq(inventory.lastTransitionAt(), transitionBefore, "No lifecycle transition");
        assertEq(_accountingState(), beforeState, "No custody or obligation changes");
    }

    // Scenarios: BLINVGR-A02.
    function test_givenUnauthorizedCaller_whenZeroPeriod_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        _initializeAndEnable();
        _expectAdminRole();
        vm.prank(caller_);
        inventory.setGracePeriod(0);
    }

    // Scenarios: BLINVGR-P01.
    function test_givenSamePeriod_whenSet_emitsOnce(address caller_, uint32 period_) public {
        vm.assume(caller_ != address(0));
        _initializeAndEnable();
        _grantAdminRole(caller_);
        period_ = uint32(bound(period_, 1, type(uint32).max));
        vm.prank(caller_);
        inventory.setGracePeriod(period_);
        bytes32 beforeState = _accountingState();
        uint48 transitionBefore = inventory.lastTransitionAt();
        vm.recordLogs();
        vm.prank(caller_);
        inventory.setGracePeriod(period_);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "Exactly one grace event on same value");
        assertEq(logs[0].emitter, address(inventory), "Event emitter");
        assertEq(logs[0].topics[0], keccak256("GracePeriodSet(uint32)"), "Grace event");
        assertEq(logs[0].data, abi.encode(period_), "Exact period event data");
        assertEq(inventory.gracePeriod(), period_, "Same period retained");
        assertEq(inventory.lastTransitionAt(), transitionBefore, "No transition");
        assertEq(_accountingState(), beforeState, "Accounting unchanged");
    }

    // Scenarios: BLINVGR-L01, BLINVGR-L02, BLINVGR-L03, BLINVGR-L04, BLINVGR-L05, BLINVGR-L06, BLINVGR-L07, BLINVGR-L08, BLINVGR-L09, BLINVGR-L10, BLINVGR-L11, BLINVGR-L12, BLINVGR-N01, BLINVGR-P01.
    function test_whenGraceAndLifecycleSeeds() public {
        for (uint8 flags; flags < 4; ++flags) {
            uint256 snapshot = vm.snapshotState();
            test_givenDisabledInventory_whenGraceSet_reverts(outsider, 0);
            test_givenInactiveDisabledInventory_whenGraceSet_reverts(outsider, 0);
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore disabled zero seed");
            snapshot = vm.snapshotState();
            test_givenDisabledInventory_whenGraceSet_reverts(outsider, 1);
            test_givenInactiveDisabledInventory_whenGraceSet_reverts(outsider, 1);
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore disabled positive seed");
            snapshot = vm.snapshotState();
            test_givenInactiveEnabledInventory_whenGraceSet_reverts(
                1,
                flags & 1 != 0,
                flags & 2 != 0
            );
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore inactive seed");
            snapshot = vm.snapshotState();
            test_givenActiveEnabledInventory_whenGraceSet_succeeds(
                1,
                flags & 1 != 0,
                flags & 2 != 0
            );
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore active seed");
        }
        test_givenSamePeriod_whenSet_emitsOnce(outsider, 1);
        test_givenSamePeriod_whenSet_emitsOnce(outsider, type(uint32).max);
        test_givenSamePeriod_whenSet_emitsOnce(outsider, 7 days);
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast)
