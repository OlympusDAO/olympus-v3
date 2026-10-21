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

contract BurnerLoansConfigSetSendFeesToDistributorTest is BurnerLoansConfigDistributorFlagTest {
    // Scenarios: CFEES-A01, CFEES-A02
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
        burnerLoansConfig.setSendFeesToDistributor(true);

        assertEq(vm.getRecordedLogs().length, 0, "unauthorized forwarding event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: CFEES-A03, CFEES-A04
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
        burnerLoansConfig.setSendFeesToDistributor(true);

        assertEq(vm.getRecordedLogs().length, 0, "disabled unauthorized event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: CFEES-L01
    function test_givenConfigInactive_whenPermittedCallerSetsFeeFlag_reverts(
        bool useAdmin_,
        bool enabled_
    ) public {
        _deactivatePolicy(address(burnerLoansConfig));
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.recordLogs();
        vm.expectRevert(IBurnerLoansConfig.BurnerLoansConfig_PolicyInactive.selector);
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendFeesToDistributor(enabled_);
        assertEq(vm.getRecordedLogs().length, 0, "inactive config event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: CFEES-L02, CFEES-L03
    function test_givenConfigDisabled_whenPermittedCallerSetsFeeFlag_reverts(
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
        burnerLoansConfig.setSendFeesToDistributor(enabled_);
        assertEq(vm.getRecordedLogs().length, 0, "disabled config event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: CFEES-L04, CFEES-L06
    function test_givenFacilityInactive_whenPermittedCallerSetsFeeFlag_reverts(
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
        burnerLoansConfig.setSendFeesToDistributor(enabled_);
        assertEq(vm.getRecordedLogs().length, 0, "inactive facility event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: CFEES-L05
    function test_givenFacilityDisabled_whenPermittedCallerSetsFeeFlag_reverts(
        bool useAdmin_,
        bool enabled_
    ) public {
        vm.prank(admin);
        burnerLoans.disable("");
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendFeesToDistributor(enabled_);
        assertEq(vm.getRecordedLogs().length, 0, "disabled facility event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: CFEES-P01
    function test_givenValidDistributor_whenPermittedCallerEnablesFeeRouting(
        bool useAdmin_,
        bool assetListed_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, assetListed_);
        _selectRevenueDistributor(distributor);

        vm.expectEmit(false, false, false, true, address(burnerLoans));
        emit IBurnerLoans.SendFeesToDistributorSet(true);
        vm.recordLogs();
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendFeesToDistributor(true);

        assertEq(vm.getRecordedLogs().length, 1, "forwarded fee event count");
        assertTrue(burnerLoans.sendFeesToDistributor(), "fee routing enabled");
        assertFalse(burnerLoans.sendYieldToDistributor(), "yield routing unchanged");
    }

    // Scenarios: CFEES-P02
    function test_givenFeeRoutingEnabled_whenPermittedCallerDisables_withoutRevalidation(
        bool useAdmin_,
        uint8 distributorState_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _setFeeFlag(true);
        _driftRevenueDistributor(distributor, distributorState_);

        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendFeesToDistributor(false);

        assertFalse(burnerLoans.sendFeesToDistributor(), "fee routing disabled");
        vm.clearMockedCalls();
    }

    // Scenarios: CFEES-P03
    function test_givenFeeRoutingDisabled_whenPermittedCallerSetsFalse_isNoOp(
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
        burnerLoansConfig.setSendFeesToDistributor(false);
        assertEq(vm.getRecordedLogs().length, 0, "forwarded no-op event count");
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: CFEES-P04
    function test_givenFeeRoutingEnabled_whenPermittedCallerSetsTrue_isNoOp(
        bool useAdmin_,
        uint8 distributorState_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _setFeeFlag(true);
        _driftRevenueDistributor(distributor, distributorState_);
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.recordLogs();
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendFeesToDistributor(true);
        assertEq(vm.getRecordedLogs().length, 0, "forwarded same-value event count");
        _assertRoutingUnchanged(before_);
        vm.clearMockedCalls();
    }

    // Scenarios: CFEES-I01
    function test_givenDistributorUnset_whenPermittedCallerEnablesFeeRouting_reverts(
        bool useAdmin_
    ) public {
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.expectRevert(IBurnerLoans.BurnerLoans_RevenueDistributorRequired.selector);
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendFeesToDistributor(true);
        _assertRoutingUnchanged(before_);
    }

    // Scenarios: CFEES-I02
    function test_givenDistributorInactive_whenPermittedCallerEnablesFeeRouting_reverts(
        bool useAdmin_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        _deactivatePolicy(address(distributor));
        _checkDownstreamRejection(distributor, useAdmin_);
    }

    // Scenarios: CFEES-I03
    function test_givenDistributorDisabled_whenPermittedCallerEnablesFeeRouting_reverts(
        bool useAdmin_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, false);
        _selectRevenueDistributor(distributor);
        vm.prank(admin);
        distributor.disable("");
        _checkDownstreamRejection(distributor, useAdmin_);
    }

    // Scenarios: CFEES-I04
    function test_givenDistributorKernelReadReverts_whenPermittedCallerEnablesFeeRouting_reverts(
        bool useAdmin_
    ) public {
        _checkDownstreamReadFailure(useAdmin_, 0);
    }

    // Scenarios: CFEES-I05
    function test_givenDistributorKernelReadMalformed_whenPermittedCallerEnablesFeeRouting_reverts(
        bool useAdmin_
    ) public {
        _checkDownstreamReadFailure(useAdmin_, 1);
    }

    // Scenarios: CFEES-I06
    function test_givenDistributorEnabledReadReverts_whenPermittedCallerEnablesFeeRouting_reverts(
        bool useAdmin_
    ) public {
        _checkDownstreamReadFailure(useAdmin_, 2);
    }

    // Scenarios: CFEES-I07
    function test_givenDistributorEnabledReadMalformed_whenPermittedCallerEnablesFeeRouting_reverts(
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

    // Scenarios: CFEES-R01
    function test_givenPendingPayouts_whenPermittedCallerEnablesFeeRouting_reassignsFee(
        bool useAdmin_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, true);
        _selectRevenueDistributor(distributor);
        _seedPendingPayouts(address(trsry));
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendFeesToDistributor(true);
        _assertPendingStatePreserved(before_);
        _assertPendingRecipients(address(distributor));
    }

    // Scenarios: CFEES-R02
    function test_givenPendingPayouts_whenPermittedCallerDisablesFeeRouting_reassignsFee(
        bool useAdmin_
    ) public {
        RevenueDistributor distributor = _deployRevenueDistributor(true, true);
        _selectRevenueDistributor(distributor);
        _setFeeFlag(true);
        _seedPendingPayouts(address(distributor));
        RoutingSnapshot memory before_ = _snapshotRouting();
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendFeesToDistributor(false);
        _assertPendingStatePreserved(before_);
        _assertPendingRecipients(address(trsry));
    }

    function _checkDownstreamRejection(RevenueDistributor distributor_, bool useAdmin_) internal {
        RoutingSnapshot memory before_ = _snapshotRouting();
        _expectInvalidRevenueDistributor(address(distributor_));
        vm.prank(_permittedCaller(useAdmin_));
        burnerLoansConfig.setSendFeesToDistributor(true);
        _assertRoutingUnchanged(before_);
        vm.clearMockedCalls();
    }
}
