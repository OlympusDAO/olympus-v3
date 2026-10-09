// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

// Contracts
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {BurnerLoansDistributorConfigTest} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansDistributorConfigTest.sol";

contract BurnerLoansSetSendFeesToDistributorTest is BurnerLoansDistributorConfigTest {
    // Scenarios: FEES-A01, FEES-A02, FEES-A03, FEES-A04
    function test_givenLifecycleState_whenCallerIsNotConfigurator_reverts(
        address caller_,
        bool policyActive_,
        bool locallyEnabled_
    ) public {
        vm.assume(caller_ != address(burnerLoansConfig));
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _disableBurnerLoansIf(!locallyEnabled_);
        if (!policyActive_) _deactivatePolicy(address(burnerLoans));
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_OnlyConfigurator.selector, caller_)
        );
        vm.prank(caller_);
        burnerLoans.setSendFeesToDistributor(true);

        assertEq(vm.getRecordedLogs().length, 0, "unauthorized event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: FEES-L01, FEES-L03
    function test_givenPolicyInactive_whenConfiguratorSetsFeeFlag_reverts(
        bool locallyEnabled_,
        bool enabled_
    ) public {
        _disableBurnerLoansIf(!locallyEnabled_);
        _deactivatePolicy(address(burnerLoans));
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        vm.expectRevert(IBurnerLoans.BurnerLoans_PolicyInactive.selector);
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setSendFeesToDistributor(enabled_);

        assertEq(vm.getRecordedLogs().length, 0, "inactive event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: FEES-L02
    function test_givenLocallyDisabled_whenConfiguratorSetsFeeFlag_reverts(bool enabled_) public {
        _disableBurnerLoans(admin);
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setSendFeesToDistributor(enabled_);

        assertEq(vm.getRecordedLogs().length, 0, "disabled event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: FEES-P01
    function test_givenValidDistributor_whenConfiguratorEnablesFeeRouting(
        bool assetListed_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, assetListed_);
        _selectRevenueDistributor(distributor);
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.expectEmit(false, false, false, true, address(burnerLoans));
        emit IBurnerLoans.SendFeesToDistributorSet(true);
        vm.recordLogs();
        _setFeeFlag(true);

        assertEq(vm.getRecordedLogs().length, 1, "fee-enable event count");
        assertTrue(burnerLoans.sendFeesToDistributor(), "fee routing enabled");
        assertFalse(burnerLoans.sendYieldToDistributor(), "yield routing unchanged");
        assertEq(
            burnerLoans.revenueDistributor(),
            before_.distributor,
            "distributor pointer unchanged"
        );
        assertEq(usds.balanceOf(address(burnerLoans)), before_.facilityBalance, "no tokens move");
    }

    // Scenarios: FEES-P02
    function test_givenFeeRoutingEnabled_whenConfiguratorDisables_withoutRevalidation(
        uint8 distributorState_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _setFeeFlag(true);
        _driftRevenueDistributor(distributor, distributorState_);

        vm.expectEmit(false, false, false, true, address(burnerLoans));
        emit IBurnerLoans.SendFeesToDistributorSet(false);
        vm.recordLogs();
        _setFeeFlag(false);

        assertEq(vm.getRecordedLogs().length, 1, "fee-disable event count");
        assertFalse(burnerLoans.sendFeesToDistributor(), "fee routing disabled");
        assertEq(
            burnerLoans.revenueDistributor(),
            address(distributor),
            "distributor pointer unchanged"
        );
        vm.clearMockedCalls();
    }

    // Scenarios: FEES-P03
    function test_givenFeeRoutingDisabled_whenConfiguratorSetsFalse_isNoOp(
        bool pointerSelected_
    ) public {
        if (pointerSelected_) {
            RevenueDistributor distributor = _deployRevenueDistributor(true, false);
            _selectRevenueDistributor(distributor);
        }
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        _setFeeFlag(false);

        assertEq(vm.getRecordedLogs().length, 0, "same-false event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: FEES-P04
    function test_givenFeeRoutingEnabled_whenConfiguratorSetsTrue_isNoOp(
        uint8 distributorState_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _setFeeFlag(true);
        _driftRevenueDistributor(distributor, distributorState_);
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        _setFeeFlag(true);

        assertEq(vm.getRecordedLogs().length, 0, "same-true event count");
        _assertRoutingUnchanged(before_);
        vm.clearMockedCalls();
    }

    // Scenarios: FEES-I01
    function test_givenDistributorUnset_whenConfiguratorEnablesFeeRouting_reverts() public {
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.recordLogs();
        vm.expectRevert(IBurnerLoans.BurnerLoans_RevenueDistributorRequired.selector);
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setSendFeesToDistributor(true);
        assertEq(vm.getRecordedLogs().length, 0, "unset distributor event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: FEES-I05
    function test_givenDistributorKernelInactive_whenConfiguratorEnablesFeeRouting_reverts()
        public
    {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _deactivatePolicy(address(distributor));
        _checkEnableRejected(distributor);
    }

    // Scenarios: FEES-I06
    function test_givenDistributorLocallyDisabled_whenConfiguratorEnablesFeeRouting_reverts()
        public
    {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        vm.prank(admin);
        distributor.disable("");
        _checkEnableRejected(distributor);
    }

    // Scenarios: FEES-I07
    function test_givenDistributorKernelReadReverts_whenConfiguratorEnablesFeeRouting_reverts()
        public
    {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _mockKernelRevert(address(distributor));
        _checkEnableRejected(distributor);
    }

    // Scenarios: FEES-I08
    function test_givenDistributorKernelReadMalformed_whenConfiguratorEnablesFeeRouting_reverts()
        public
    {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _mockKernelMalformed(address(distributor));
        _checkEnableRejected(distributor);
    }

    // Scenarios: FEES-I09
    function test_givenDistributorEnabledReadReverts_whenConfiguratorEnablesFeeRouting_reverts()
        public
    {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _mockEnabledRevert(address(distributor));
        _checkEnableRejected(distributor);
    }

    // Scenarios: FEES-I10
    function test_givenDistributorEnabledReadMalformed_whenConfiguratorEnablesFeeRouting_reverts()
        public
    {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _mockEnabledMalformed(address(distributor));
        _checkEnableRejected(distributor);
    }

    // Scenarios: FEES-R01
    function test_givenPendingPayouts_whenConfiguratorEnablesFeeRouting_reassignsFee() public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, true);
        _selectRevenueDistributor(distributor);
        _seedPendingPayouts(address(trsry));
        RoutingSnapshot memory before_ = _snapshotRouting();

        _setFeeFlag(true);

        _assertPendingStatePreserved(before_);
        _assertPendingRecipients(address(distributor));
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(distributor)),
            PENDING_FEE,
            "distributor receives fee entitlement"
        );
    }

    // Scenarios: FEES-R02
    function test_givenPendingPayouts_whenConfiguratorDisablesFeeRouting_reassignsFee() public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, true);
        _selectRevenueDistributor(distributor);
        _setFeeFlag(true);
        _seedPendingPayouts(address(distributor));
        RoutingSnapshot memory before_ = _snapshotRouting();

        _setFeeFlag(false);

        _assertPendingStatePreserved(before_);
        _assertPendingRecipients(address(trsry));
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(distributor)),
            0,
            "distributor fee entitlement removed"
        );
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(trsry)),
            PENDING_FEE + PENDING_SEIZURE,
            "Treasury resolves fee and seizure"
        );
    }

    function _checkEnableRejected(RevenueDistributor distributor_) internal {
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.recordLogs();
        _expectInvalidRevenueDistributor(address(distributor_));
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setSendFeesToDistributor(true);
        assertEq(vm.getRecordedLogs().length, 0, "invalid distributor event count");
        _assertRoutingUnchanged(before_);
        vm.clearMockedCalls();
    }
}
