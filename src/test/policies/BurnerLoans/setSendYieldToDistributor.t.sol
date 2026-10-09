// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

// Contracts
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {BurnerLoansDistributorConfigTest} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansDistributorConfigTest.sol";

contract BurnerLoansSetSendYieldToDistributorTest is BurnerLoansDistributorConfigTest {
    // Scenarios: YIELD-A01, YIELD-A02, YIELD-A03, YIELD-A04
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
        burnerLoans.setSendYieldToDistributor(true);

        assertEq(vm.getRecordedLogs().length, 0, "unauthorized event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: YIELD-L01, YIELD-L03
    function test_givenPolicyInactive_whenConfiguratorSetsYieldFlag_reverts(
        bool locallyEnabled_,
        bool enabled_
    ) public {
        _disableBurnerLoansIf(!locallyEnabled_);
        _deactivatePolicy(address(burnerLoans));
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        vm.expectRevert(IBurnerLoans.BurnerLoans_PolicyInactive.selector);
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setSendYieldToDistributor(enabled_);

        assertEq(vm.getRecordedLogs().length, 0, "inactive event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: YIELD-L02
    function test_givenLocallyDisabled_whenConfiguratorSetsYieldFlag_reverts(bool enabled_) public {
        _disableBurnerLoans(admin);
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setSendYieldToDistributor(enabled_);

        assertEq(vm.getRecordedLogs().length, 0, "disabled event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: YIELD-P01
    function test_givenValidDistributor_whenConfiguratorEnablesYieldRouting(
        bool assetListed_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, assetListed_);
        _selectRevenueDistributor(distributor);
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.expectEmit(false, false, false, true, address(burnerLoans));
        emit IBurnerLoans.SendYieldToDistributorSet(true);
        vm.recordLogs();
        _setYieldFlag(true);

        assertEq(vm.getRecordedLogs().length, 1, "yield-enable event count");
        assertTrue(burnerLoans.sendYieldToDistributor(), "yield routing enabled");
        assertFalse(burnerLoans.sendFeesToDistributor(), "fee routing unchanged");
        assertEq(_yieldRecipient(), address(distributor), "distributor is yield recipient");
        assertEq(
            burnerLoans.revenueDistributor(),
            before_.distributor,
            "distributor pointer unchanged"
        );
        assertEq(usds.balanceOf(address(burnerLoans)), before_.facilityBalance, "no tokens move");
    }

    // Scenarios: YIELD-P02
    function test_givenYieldRoutingEnabled_whenConfiguratorDisables_withoutRevalidation(
        uint8 distributorState_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _setYieldFlag(true);
        _driftRevenueDistributor(distributor, distributorState_);

        vm.expectEmit(false, false, false, true, address(burnerLoans));
        emit IBurnerLoans.SendYieldToDistributorSet(false);
        vm.recordLogs();
        _setYieldFlag(false);

        assertEq(vm.getRecordedLogs().length, 1, "yield-disable event count");
        assertFalse(burnerLoans.sendYieldToDistributor(), "yield routing disabled");
        assertEq(_yieldRecipient(), address(trsry), "Treasury is yield recipient");
        assertEq(
            burnerLoans.revenueDistributor(),
            address(distributor),
            "distributor pointer unchanged"
        );
        vm.clearMockedCalls();
    }

    // Scenarios: YIELD-P03
    function test_givenYieldRoutingDisabled_whenConfiguratorSetsFalse_isNoOp(
        bool pointerSelected_
    ) public {
        if (pointerSelected_) {
            RevenueDistributor distributor = _deployRevenueDistributor(true, false);
            _selectRevenueDistributor(distributor);
        }
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        _setYieldFlag(false);

        assertEq(vm.getRecordedLogs().length, 0, "same-false event count");
        _assertRoutingUnchanged(before_);
        assertEq(_yieldRecipient(), address(trsry), "Treasury remains yield recipient");
    }

    // Scenarios: YIELD-P04
    function test_givenYieldRoutingEnabled_whenConfiguratorSetsTrue_isNoOp(
        uint8 distributorState_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _setYieldFlag(true);
        _driftRevenueDistributor(distributor, distributorState_);
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        _setYieldFlag(true);

        assertEq(vm.getRecordedLogs().length, 0, "same-true event count");
        _assertRoutingUnchanged(before_);
        assertEq(_yieldRecipient(), address(distributor), "distributor remains yield recipient");
        vm.clearMockedCalls();
    }

    // Scenarios: YIELD-I01
    function test_givenDistributorUnset_whenConfiguratorEnablesYieldRouting_reverts() public {
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.recordLogs();
        vm.expectRevert(IBurnerLoans.BurnerLoans_RevenueDistributorRequired.selector);
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setSendYieldToDistributor(true);
        assertEq(vm.getRecordedLogs().length, 0, "unset distributor event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: YIELD-I05
    function test_givenDistributorKernelInactive_whenConfiguratorEnablesYieldRouting_reverts()
        public
    {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _deactivatePolicy(address(distributor));
        _checkEnableRejected(distributor);
    }

    // Scenarios: YIELD-I06
    function test_givenDistributorLocallyDisabled_whenConfiguratorEnablesYieldRouting_reverts()
        public
    {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        vm.prank(admin);
        distributor.disable("");
        _checkEnableRejected(distributor);
    }

    // Scenarios: YIELD-I07
    function test_givenDistributorKernelReadReverts_whenConfiguratorEnablesYieldRouting_reverts()
        public
    {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _mockKernelRevert(address(distributor));
        _checkEnableRejected(distributor);
    }

    // Scenarios: YIELD-I08
    function test_givenDistributorKernelReadMalformed_whenConfiguratorEnablesYieldRouting_reverts()
        public
    {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _mockKernelMalformed(address(distributor));
        _checkEnableRejected(distributor);
    }

    // Scenarios: YIELD-I09
    function test_givenDistributorEnabledReadReverts_whenConfiguratorEnablesYieldRouting_reverts()
        public
    {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _mockEnabledRevert(address(distributor));
        _checkEnableRejected(distributor);
    }

    // Scenarios: YIELD-I10
    function test_givenDistributorEnabledReadMalformed_whenConfiguratorEnablesYieldRouting_reverts()
        public
    {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _mockEnabledMalformed(address(distributor));
        _checkEnableRejected(distributor);
    }

    // Scenarios: YIELD-R01
    function test_givenPendingPayouts_whenConfiguratorEnablesYieldRouting_preservesPayouts()
        public
    {
        RevenueDistributor distributor = _deployRevenueDistributor(true, true);
        _selectRevenueDistributor(distributor);
        _seedPendingPayouts(address(trsry));
        RoutingSnapshot memory before_ = _snapshotRouting();

        _setYieldFlag(true);

        _assertPendingStatePreserved(before_);
        _assertPendingRecipients(address(trsry));
        assertEq(_yieldRecipient(), address(distributor), "distributor is yield recipient");
    }

    // Scenarios: YIELD-R02
    function test_givenPendingPayouts_whenConfiguratorDisablesYieldRouting_preservesPayouts()
        public
    {
        RevenueDistributor distributor = _deployRevenueDistributor(true, true);
        _selectRevenueDistributor(distributor);
        _setYieldFlag(true);
        _seedPendingPayouts(address(trsry));
        RoutingSnapshot memory before_ = _snapshotRouting();

        _setYieldFlag(false);

        _assertPendingStatePreserved(before_);
        _assertPendingRecipients(address(trsry));
        assertEq(_yieldRecipient(), address(trsry), "Treasury is yield recipient");
    }

    function _checkEnableRejected(RevenueDistributor distributor_) internal {
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.recordLogs();
        _expectInvalidRevenueDistributor(address(distributor_));
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setSendYieldToDistributor(true);
        assertEq(vm.getRecordedLogs().length, 0, "invalid distributor event count");
        _assertRoutingUnchanged(before_);
        vm.clearMockedCalls();
    }
}
