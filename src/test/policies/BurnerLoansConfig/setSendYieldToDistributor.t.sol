// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test bounds prove casts fit; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";

// Contracts
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {BurnerLoansConfigDistributorFlagTest} from "src/test/policies/BurnerLoansConfig/fixtures/BurnerLoansConfigDistributorFlagTest.sol";

contract BurnerLoansConfigSetSendYieldToDistributorTest is BurnerLoansConfigDistributorFlagTest {
    // Scenarios: CYIELD-A01, CYIELD-A02
    function test_givenConfigEnabled_whenCallerIsUnauthorized_reverts(
        address caller_,
        bool policyActive_
    ) public {
        vm.assume(caller_ != admin && caller_ != configOperator);
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        if (!policyActive_) _deactivatePolicy(address(burnerLoansConfig));
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                caller_
            )
        );
        vm.prank(caller_);
        burnerLoansConfig.setSendYieldToDistributor(true);

        assertEq(vm.getRecordedLogs().length, 0, "unauthorized forwarding event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: CYIELD-A03, CYIELD-A04
    function test_givenConfigDisabled_whenCallerIsUnauthorized_reverts(
        address caller_,
        bool policyActive_
    ) public {
        vm.assume(caller_ != admin && caller_ != configOperator);
        vm.prank(admin);
        burnerLoansConfig.disable("");
        if (!policyActive_) _deactivatePolicy(address(burnerLoansConfig));
        RoutingSnapshot memory before_ = _snapshotRouting();

        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        burnerLoansConfig.setSendYieldToDistributor(true);

        assertEq(vm.getRecordedLogs().length, 0, "disabled unauthorized event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: CYIELD-L01
    function test_givenConfigInactive_whenPermittedCallerSetsYieldFlag_reverts(
        bool useAdmin_,
        bool enabled_
    ) public {
        _deactivatePolicy(address(burnerLoansConfig));
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.recordLogs();
        vm.expectRevert(IBurnerLoansConfig.BurnerLoansConfig_PolicyInactive.selector);
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendYieldToDistributor(enabled_);
        assertEq(vm.getRecordedLogs().length, 0, "inactive config event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: CYIELD-L02, CYIELD-L03
    function test_givenConfigDisabled_whenPermittedCallerSetsYieldFlag_reverts(
        bool useAdmin_,
        bool policyActive_,
        bool enabled_
    ) public {
        vm.prank(admin);
        burnerLoansConfig.disable("");
        if (!policyActive_) _deactivatePolicy(address(burnerLoansConfig));
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendYieldToDistributor(enabled_);
        assertEq(vm.getRecordedLogs().length, 0, "disabled config event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: CYIELD-L04, CYIELD-L06
    function test_givenFacilityInactive_whenPermittedCallerSetsYieldFlag_reverts(
        bool useAdmin_,
        bool locallyEnabled_,
        bool enabled_
    ) public {
        if (!locallyEnabled_) {
            vm.prank(admin);
            burnerLoans.disable("");
        }
        _deactivatePolicy(address(burnerLoans));
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.recordLogs();
        vm.expectRevert(IBurnerLoans.BurnerLoans_PolicyInactive.selector);
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendYieldToDistributor(enabled_);
        assertEq(vm.getRecordedLogs().length, 0, "inactive facility event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: CYIELD-L05
    function test_givenFacilityDisabled_whenPermittedCallerSetsYieldFlag_reverts(
        bool useAdmin_,
        bool enabled_
    ) public {
        vm.prank(admin);
        burnerLoans.disable("");
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendYieldToDistributor(enabled_);
        assertEq(vm.getRecordedLogs().length, 0, "disabled facility event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: CYIELD-P01
    function test_givenValidDistributor_whenPermittedCallerEnablesYieldRouting(
        bool useAdmin_,
        bool assetListed_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, assetListed_);
        _selectRevenueDistributor(distributor);

        vm.expectEmit(false, false, false, true, address(burnerLoans));
        emit IBurnerLoans.SendYieldToDistributorSet(true);
        vm.recordLogs();
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendYieldToDistributor(true);

        assertEq(vm.getRecordedLogs().length, 1, "forwarded yield event count");
        assertTrue(burnerLoans.sendYieldToDistributor(), "yield routing enabled");
        assertFalse(burnerLoans.sendFeesToDistributor(), "fee routing unchanged");
    }

    // Scenarios: CYIELD-P02
    function test_givenYieldRoutingEnabled_whenPermittedCallerDisables_withoutRevalidation(
        bool useAdmin_,
        uint8 distributorState_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _setYieldFlag(true);
        _driftRevenueDistributor(distributor, distributorState_);

        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendYieldToDistributor(false);

        assertFalse(burnerLoans.sendYieldToDistributor(), "yield routing disabled");
        vm.clearMockedCalls();
    }

    // Scenarios: CYIELD-P03
    function test_givenYieldRoutingDisabled_whenPermittedCallerSetsFalse_isNoOp(
        bool useAdmin_,
        bool pointerSelected_
    ) public {
        if (pointerSelected_) {
            RevenueDistributor distributor = _deployRevenueDistributor(true, false);
            _selectRevenueDistributor(distributor);
        }
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.recordLogs();
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendYieldToDistributor(false);
        assertEq(vm.getRecordedLogs().length, 0, "forwarded no-op event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: CYIELD-P04
    function test_givenYieldRoutingEnabled_whenPermittedCallerSetsTrue_isNoOp(
        bool useAdmin_,
        uint8 distributorState_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _setYieldFlag(true);
        _driftRevenueDistributor(distributor, distributorState_);
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.recordLogs();
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendYieldToDistributor(true);
        assertEq(vm.getRecordedLogs().length, 0, "forwarded same-value event count");
        _assertRoutingUnchanged(before_);
        vm.clearMockedCalls();
    }

    // Scenarios: CYIELD-I01
    function test_givenDistributorUnset_whenPermittedCallerEnablesYieldRouting_reverts(
        bool useAdmin_
    ) public {
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.expectRevert(IBurnerLoans.BurnerLoans_RevenueDistributorRequired.selector);
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendYieldToDistributor(true);
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: CYIELD-I02
    function test_givenDistributorInactive_whenPermittedCallerEnablesYieldRouting_reverts(
        bool useAdmin_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _deactivatePolicy(address(distributor));
        _checkDownstreamRejection(distributor, useAdmin_);
    }

    // Scenarios: CYIELD-I03
    function test_givenDistributorDisabled_whenPermittedCallerEnablesYieldRouting_reverts(
        bool useAdmin_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        vm.prank(admin);
        distributor.disable("");
        _checkDownstreamRejection(distributor, useAdmin_);
    }

    // Scenarios: CYIELD-I04
    function test_givenDistributorKernelReadReverts_whenPermittedCallerEnablesYieldRouting_reverts(
        bool useAdmin_
    ) public {
        _checkDownstreamReadFailure(useAdmin_, 0);
    }

    // Scenarios: CYIELD-I05
    function test_givenDistributorKernelReadMalformed_whenPermittedCallerEnablesYieldRouting_reverts(
        bool useAdmin_
    ) public {
        _checkDownstreamReadFailure(useAdmin_, 1);
    }

    // Scenarios: CYIELD-I06
    function test_givenDistributorEnabledReadReverts_whenPermittedCallerEnablesYieldRouting_reverts(
        bool useAdmin_
    ) public {
        _checkDownstreamReadFailure(useAdmin_, 2);
    }

    // Scenarios: CYIELD-I07
    function test_givenDistributorEnabledReadMalformed_whenPermittedCallerEnablesYieldRouting_reverts(
        bool useAdmin_
    ) public {
        _checkDownstreamReadFailure(useAdmin_, 3);
    }

    function _checkDownstreamReadFailure(bool useAdmin_, uint8 failure_) internal {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        if (failure_ == 0) _mockKernelRevert(address(distributor));
        if (failure_ == 1) _mockKernelMalformed(address(distributor));
        if (failure_ == 2) _mockEnabledRevert(address(distributor));
        if (failure_ == 3) _mockEnabledMalformed(address(distributor));
        _checkDownstreamRejection(distributor, useAdmin_);
    }

    // Scenarios: CYIELD-R01, CYIELD-R02
    function test_givenPendingPayouts_whenPermittedCallerChangesYieldRouting_preservesThem(
        bool useAdmin_,
        bool enable_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, true);
        _selectRevenueDistributor(distributor);
        if (!enable_) _setYieldFlag(true);
        _seedPendingPayouts(address(trsry));
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendYieldToDistributor(enable_);
        _assertPendingStatePreserved(before_);
        _assertPendingRecipients(address(trsry));
    }

    function _checkDownstreamRejection(RevenueDistributor distributor_, bool useAdmin_) internal {
        RoutingSnapshot memory before_ = _snapshotRouting();
        _expectInvalidRevenueDistributor(address(distributor_));
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendYieldToDistributor(true);
        _assertRoutingUnchanged(before_);
        vm.clearMockedCalls();
    }
}
