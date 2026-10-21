// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test bounds prove casts fit; reverted-call return values are intentionally unused.
// forge-lint: disable-start(unsafe-typecast,unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {BurnerLoansDistributorConfigTest} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansDistributorConfigTest.sol";
import {MockBurnerLoansPolicy} from "src/test/policies/BurnerLoansConfig/fixtures/MockBurnerLoansPolicy.sol";

contract BurnerLoansSetRevenueDistributorTest is BurnerLoansDistributorConfigTest {
    // Listed/unlisted USDS fixtures for fee and yield routing are exercised by the dedicated
    // setSendFeesToDistributor.t.sol and setSendYieldToDistributor.t.sol suites.

    // Scenarios: DISTPTR-A01, DISTPTR-A02, DISTPTR-A03, DISTPTR-A04
    function test_givenLifecycleState_whenCallerIsNotAdmin_reverts(
        address caller_,
        bool policyActive_,
        bool locallyEnabled_
    ) public {
        vm.assume(caller_ != admin);
        RevenueDistributor candidate = _deployRevenueDistributor(true, false);
        _disableBurnerLoansIf(!locallyEnabled_);
        if (!policyActive_) _deactivatePolicy(address(burnerLoans));
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        burnerLoans.setRevenueDistributor(address(candidate));

        assertEq(vm.getRecordedLogs().length, 0, "rejected call event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: DISTPTR-P01
    function test_givenPointerUnset_whenAdminSetsValidDistributor(bool listUsds_) public {
        RevenueDistributor candidate = _deployRevenueDistributor(true, listUsds_);
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit IBurnerLoans.RevenueDistributorSet(address(candidate));
        vm.recordLogs();
        vm.prank(admin);
        burnerLoans.setRevenueDistributor(address(candidate));

        assertEq(vm.getRecordedLogs().length, 1, "pointer update event count");
        assertEq(
            burnerLoans.revenueDistributor(),
            address(candidate),
            "selected distributor pointer"
        );
        assertEq(burnerLoans.sendFeesToDistributor(), before_.sendFees, "fee flag unchanged");
        assertEq(burnerLoans.sendYieldToDistributor(), before_.sendYield, "yield flag unchanged");
        assertEq(
            usds.balanceOf(address(burnerLoans)),
            before_.facilityBalance,
            "facility balance unchanged"
        );
    }

    // Scenarios: DISTPTR-P02
    function test_givenPointerSelected_whenAdminSetsSameDistributor_isNoOp(
        bool feeFlag_,
        bool yieldFlag_,
        uint8 distributorState_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        if (feeFlag_) _setFeeFlag(true);
        if (yieldFlag_) _setYieldFlag(true);
        distributorState_ = uint8(bound(distributorState_, 0, 2));
        if (distributorState_ == 1) _deactivatePolicy(address(distributor));
        if (distributorState_ == 2) {
            vm.prank(admin);
            distributor.disable("");
        }
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        vm.prank(admin);
        burnerLoans.setRevenueDistributor(address(distributor));

        assertEq(vm.getRecordedLogs().length, 0, "same-pointer event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: DISTPTR-P03
    function test_givenPointerSelected_whenAdminClearsPointer() public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);

        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit IBurnerLoans.RevenueDistributorSet(address(0));
        vm.recordLogs();
        vm.prank(admin);
        burnerLoans.setRevenueDistributor(address(0));

        assertEq(vm.getRecordedLogs().length, 1, "pointer clear event count");
        assertEq(burnerLoans.revenueDistributor(), address(0), "pointer cleared");
        assertFalse(burnerLoans.sendFeesToDistributor(), "fee flag remains false");
        assertFalse(burnerLoans.sendYieldToDistributor(), "yield flag remains false");
    }

    // Scenarios: DISTPTR-P04
    function test_givenPointerSelected_whenAdminChangesDistributor(
        bool feeFlag_,
        bool yieldFlag_,
        bool listUsds_
    ) public {
        RevenueDistributor current = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(current);
        if (feeFlag_) _setFeeFlag(true);
        if (yieldFlag_) _setYieldFlag(true);
        RevenueDistributor replacement = _deployRevenueDistributor(true, listUsds_);
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit IBurnerLoans.RevenueDistributorSet(address(replacement));
        vm.recordLogs();
        vm.prank(admin);
        burnerLoans.setRevenueDistributor(address(replacement));

        assertEq(vm.getRecordedLogs().length, 1, "pointer rotation event count");
        assertEq(
            burnerLoans.revenueDistributor(),
            address(replacement),
            "replacement distributor pointer"
        );
        assertEq(burnerLoans.sendFeesToDistributor(), before_.sendFees, "fee flag unchanged");
        assertEq(burnerLoans.sendYieldToDistributor(), before_.sendYield, "yield flag unchanged");
        assertEq(
            usds.balanceOf(address(burnerLoans)),
            before_.facilityBalance,
            "facility balance unchanged"
        );
    }

    // Scenarios: DISTPTR-P05
    function test_givenPointerUnset_whenAdminSetsZero_isNoOp() public {
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        vm.prank(admin);
        burnerLoans.setRevenueDistributor(address(0));

        assertEq(vm.getRecordedLogs().length, 0, "zero-pointer no-op event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: DISTPTR-L01, DISTPTR-L03
    function test_givenPolicyInactive_whenAdminSetsDistributor_reverts(
        bool locallyEnabled_
    ) public {
        RevenueDistributor candidate = _deployRevenueDistributor(true, false);
        _disableBurnerLoansIf(!locallyEnabled_);
        _deactivatePolicy(address(burnerLoans));
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        vm.expectRevert(IBurnerLoans.BurnerLoans_PolicyInactive.selector);
        vm.prank(admin);
        burnerLoans.setRevenueDistributor(address(candidate));

        assertEq(vm.getRecordedLogs().length, 0, "inactive call event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: DISTPTR-L02
    function test_givenLocallyDisabled_whenAdminSetsDistributor_reverts() public {
        RevenueDistributor candidate = _deployRevenueDistributor(true, false);
        _disableBurnerLoans(admin);
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(admin);
        burnerLoans.setRevenueDistributor(address(candidate));

        assertEq(vm.getRecordedLogs().length, 0, "disabled call event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: DISTPTR-I01
    function test_givenFeeFlagEnabled_whenAdminClearsPointer_reverts() public {
        _checkClearWithFlagsRejected(true, false);
    }

    // Scenarios: DISTPTR-I03
    function test_givenYieldFlagEnabled_whenAdminClearsPointer_reverts() public {
        _checkClearWithFlagsRejected(false, true);
    }

    // Scenarios: DISTPTR-I04
    function test_givenBothFlagsEnabled_whenAdminClearsPointer_reverts() public {
        _checkClearWithFlagsRejected(true, true);
    }

    // Scenarios: DISTPTR-I02
    function test_givenPointerSelected_whenAdminSetsEoa_reverts(address candidate_) public {
        vm.assume(candidate_ != address(0));
        vm.assume(candidate_.code.length == 0);
        _installExistingPointer();
        _checkInvalidCandidate(candidate_);
    }

    // Scenarios: DISTPTR-I05
    function test_givenPointerSelected_whenCandidateLacksRevenueDistributor_reverts() public {
        _installExistingPointer();
        MockBurnerLoansPolicy candidate = new MockBurnerLoansPolicy(kernel, address(ohm));
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(candidate));
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: DISTPTR-I09
    function test_givenPointerSelected_whenCandidateLacksEnabler_reverts() public {
        _installExistingPointer();
        RevenueDistributor candidate = _deployRevenueDistributor(true, false);
        _mockEnablerInterface(address(candidate), false);
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: DISTPTR-I06
    function test_givenPointerSelected_whenCandidateUsesAnotherKernel_reverts() public {
        _installExistingPointer();
        Kernel otherKernel = new Kernel();
        RevenueDistributor candidate = new RevenueDistributor(otherKernel);
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: DISTPTR-I07
    function test_givenPointerSelected_whenCandidateIsKernelInactive_reverts() public {
        _installExistingPointer();
        RevenueDistributor candidate = new RevenueDistributor(kernel);
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: DISTPTR-I08
    function test_givenPointerSelected_whenCandidateIsLocallyDisabled_reverts() public {
        _installExistingPointer();
        RevenueDistributor candidate = _deployRevenueDistributor(false, false);
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: DISTPTR-I10
    function test_givenPointerSelected_whenCandidateKernelReadReverts_reverts() public {
        _installExistingPointer();
        RevenueDistributor candidate = _deployRevenueDistributor(true, false);
        _mockKernelRevert(address(candidate));
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: DISTPTR-I11
    function test_givenPointerSelected_whenCandidateKernelReadIsMalformed_reverts() public {
        _installExistingPointer();
        RevenueDistributor candidate = _deployRevenueDistributor(true, false);
        _mockKernelMalformed(address(candidate));
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: DISTPTR-I12
    function test_givenPointerSelected_whenCandidateEnabledReadReverts_reverts() public {
        _installExistingPointer();
        RevenueDistributor candidate = _deployRevenueDistributor(true, false);
        _mockEnabledRevert(address(candidate));
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: DISTPTR-I13
    function test_givenPointerSelected_whenCandidateEnabledReadIsMalformed_reverts() public {
        _installExistingPointer();
        RevenueDistributor candidate = _deployRevenueDistributor(true, false);
        _mockEnabledMalformed(address(candidate));
        _checkInvalidCandidate(address(candidate));
    }

    // Scenarios: DISTPTR-R01
    function test_givenPendingFee_whenDistributorChanges_reassignsFee() public {
        RevenueDistributor former = _deployRevenueDistributor(true, true);
        _selectRevenueDistributor(former);
        _setFeeFlag(true);
        _seedPendingPayouts(address(former));
        RoutingSnapshot memory before_ = _snapshotRouting();
        RevenueDistributor replacement = _deployRevenueDistributor(true, true);

        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit IBurnerLoans.RevenueDistributorSet(address(replacement));
        vm.prank(admin);
        burnerLoans.setRevenueDistributor(address(replacement));

        _assertPendingStatePreserved(before_);
        _assertPendingRecipients(address(replacement));
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(former)),
            0,
            "former distributor has no entitlement"
        );
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(replacement)),
            PENDING_FEE,
            "replacement distributor receives fee entitlement"
        );
    }

    // Scenarios: DISTPTR-R02
    function test_givenYieldRouting_whenDistributorChanges_updatesOnlyYieldRecipient() public {
        RevenueDistributor former = _deployRevenueDistributor(true, true);
        _selectRevenueDistributor(former);
        _setYieldFlag(true);
        _seedPendingPayouts(address(trsry));
        RoutingSnapshot memory before_ = _snapshotRouting();
        RevenueDistributor replacement = _deployRevenueDistributor(true, true);

        vm.prank(admin);
        burnerLoans.setRevenueDistributor(address(replacement));

        _assertPendingStatePreserved(before_);
        _assertPendingRecipients(address(trsry));
        assertEq(_yieldRecipient(), address(replacement), "replacement yield recipient");
    }

    // Scenarios: DISTPTR-R03
    function test_givenBothRoutesAndPendingPayouts_whenDistributorChanges_preservesBuckets()
        public
    {
        RevenueDistributor former = _deployRevenueDistributor(true, true);
        _selectRevenueDistributor(former);
        _setFeeFlag(true);
        _setYieldFlag(true);
        _seedPendingPayouts(address(former));
        RoutingSnapshot memory before_ = _snapshotRouting();
        RevenueDistributor replacement = _deployRevenueDistributor(true, true);

        vm.prank(admin);
        burnerLoans.setRevenueDistributor(address(replacement));

        _assertPendingStatePreserved(before_);
        _assertPendingRecipients(address(replacement));
        assertEq(_yieldRecipient(), address(replacement), "replacement yield recipient");
        assertEq(
            burnerLoans.pendingPayout(address(usds), keeper),
            PENDING_REWARD,
            "keeper entitlement remains fixed"
        );
    }

    // Scenarios: DISTPTR-R04
    function test_givenBothRoutesAndPendingPayouts_whenRoutesDisabledThenPointerCleared() public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, true);
        _selectRevenueDistributor(distributor);
        _setFeeFlag(true);
        _setYieldFlag(true);
        _seedPendingPayouts(address(distributor));

        _setFeeFlag(false);
        _setYieldFlag(false);
        vm.prank(admin);
        burnerLoans.setRevenueDistributor(address(0));

        _assertPendingRecipients(address(trsry));
        assertEq(_yieldRecipient(), address(trsry), "Treasury yield recipient");
        assertEq(burnerLoans.revenueDistributor(), address(0), "pointer cleared");
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(distributor)),
            0,
            "former distributor entitlement cleared"
        );

        uint256 treasuryBefore = usds.balanceOf(address(trsry));
        burnerLoans.transferPendingPayout(address(usds), address(trsry));
        assertEq(
            usds.balanceOf(address(trsry)) - treasuryBefore,
            PENDING_FEE + PENDING_SEIZURE,
            "Treasury receives fee and seizure"
        );
        assertEq(
            burnerLoans.pendingPayout(address(usds), keeper),
            PENDING_REWARD,
            "keeper reward remains pending"
        );
        assertEq(
            burnerLoans.totalPendingForTest(address(usds)),
            PENDING_REWARD,
            "aggregate retains keeper reward"
        );
    }

    function _checkClearWithFlagsRejected(bool feeFlag_, bool yieldFlag_) internal {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        if (feeFlag_) _setFeeFlag(true);
        if (yieldFlag_) _setYieldFlag(true);
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        vm.expectRevert(IBurnerLoans.BurnerLoans_RevenueDistributorRequired.selector);
        vm.prank(admin);
        burnerLoans.setRevenueDistributor(address(0));

        assertEq(vm.getRecordedLogs().length, 0, "rejected clear event count");
        _assertRoutingUnchanged(before_);
    }

    function _installExistingPointer() internal returns (RevenueDistributor distributor) {
        distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
    }

    function _checkInvalidCandidate(address candidate_) internal {
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.recordLogs();
        _expectInvalidRevenueDistributor(candidate_);
        vm.prank(admin);
        burnerLoans.setRevenueDistributor(candidate_);
        assertEq(vm.getRecordedLogs().length, 0, "invalid candidate event count");
        _assertRoutingUnchanged(before_);
        vm.clearMockedCalls();
    }
}
