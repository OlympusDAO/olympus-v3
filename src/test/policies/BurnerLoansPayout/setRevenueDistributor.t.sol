// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {Kernel, Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";

contract BurnerLoansPayoutSetRevenueDistributorTest is BurnerLoansPayoutTest {
    // Scenarios: BLCRD-A01, BLCRD-L01, BLCRD-L02, BLCRD-P01.
    function test_givenValidDistributor_whenSelected_thenOnlyPointerChanges(
        address caller_,
        bool enabled_,
        bool coreActive_,
        bool coreEnabled_,
        bool fee_,
        bool yield_
    ) public givenPendingBuckets {
        vm.assume(caller_ != address(0));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        _bindDistributor();
        _payout.setSendFeesToDistributor(fee_);
        _payout.setSendYieldToDistributor(yield_);
        RevenueDistributor replacement = _installDistributor();
        _setState(_payout, true, enabled_);
        _setState(_core, coreActive_, coreEnabled_);
        bytes32 state = _ledgerDigest();
        vm.prank(caller_);
        _payout.validateRevenueDistributor(address(replacement));
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.RevenueDistributorSet(address(replacement));
        vm.prank(caller_);
        _payout.setRevenueDistributor(address(replacement));
        assertEq(_payout.revenueDistributor(), address(replacement), "New code destination");
        assertEq(_payout.sendFeesToDistributor(), fee_, "Fee flag retained");
        assertEq(_payout.sendYieldToDistributor(), yield_, "Yield flag retained");
        assertEq(_ledgerDigest(), state, "Pointer repair does not move obligations");
    }

    // Scenarios: BLCRD-P01.
    function test_givenFeeRouting_whenDistributorReplaced(
        address caller_,
        bool enabled_,
        bool coreActive_,
        bool coreEnabled_,
        bool yield_
    ) public {
        test_givenValidDistributor_whenSelected_thenOnlyPointerChanges(
            caller_,
            enabled_,
            coreActive_,
            coreEnabled_,
            true,
            yield_
        );
        address replacement = _payout.revenueDistributor();
        _token.setTransferReverts(replacement, false);
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), replacement),
            10,
            "Pending generic fee follows new distributor"
        );
        assertEq(_token.balanceOf(replacement), 10, "New distributor receives deferred fee once");
    }

    // Scenarios: BLCRD-A03.
    function test_whenCallerLacksAdmin_thenSetterRejectsAndValidatorPermits(
        address caller_
    ) public givenPendingBuckets {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        RevenueDistributor next = _installDistributor();
        bytes32 state = _ledgerDigest();
        vm.prank(caller_);
        _payout.validateRevenueDistributor(address(next));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _payout.setRevenueDistributor(address(next));
        assertEq(_payout.revenueDistributor(), address(0), "Unauthorized pointer unchanged");
        assertEq(_ledgerDigest(), state, "Unauthorized setter preserves balances and claims");
    }

    // Scenarios: BLCRD-A03.
    function test_givenCurrentAndFormerOperators_whenSelectingDistributor_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenCallerLacksAdmin_thenSetterRejectsAndValidatorPermits(_controller);
        _restore(checkpoint);
        address former = _controller;
        _payout.setConfigOperator(_recipient);
        test_whenCallerLacksAdmin_thenSetterRejectsAndValidatorPermits(former);
        _restore(checkpoint);
        test_whenCallerLacksAdmin_thenSetterRejectsAndValidatorPermits(address(_config));
    }

    // Scenarios: BLCRD-I01.
    function test_whenDistributorEoa_reverts(address candidate_) public givenPendingBuckets {
        vm.assume(candidate_ != address(0) && candidate_.code.length == 0);
        _expectInvalidDistributor(candidate_);
    }

    // Scenarios: BLCRD-P02.
    function test_givenCurrentDistributor_whenSelected_revertsBeforeReadiness(
        bool fee_,
        bool yield_
    ) public givenPendingBuckets {
        _bindDistributor();
        _payout.setSendFeesToDistributor(fee_);
        _payout.setSendYieldToDistributor(yield_);
        _payout.validateRevenueDistributor(address(_distributor));
        vm.mockCallRevert(
            address(_distributor),
            abi.encodeWithSignature("kernel()"),
            hex"deadbeef"
        );
        _expectSetterRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_UnchangedAddress.selector,
                address(_distributor)
            ),
            address(_distributor)
        );
    }

    // Scenarios: BLCRD-P03.
    function test_givenBothFlagsFalse_whenDistributorCleared_thenOnlyPointerChanges()
        public
        givenPendingBuckets
    {
        _bindDistributor();
        bytes32 state = _ledgerDigest();
        vm.expectRevert(IBurnerLoansPayout.BurnerLoans_RevenueDistributorRequired.selector);
        _payout.validateRevenueDistributor(address(0));
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.RevenueDistributorSet(address(0));
        _payout.setRevenueDistributor(address(0));
        assertEq(_payout.revenueDistributor(), address(0), "Optional pointer cleared");
        assertEq(_ledgerDigest(), state, "Clearing pointer retains all obligations");
    }

    // Scenarios: BLCRD-I05.
    function test_givenFeeRouting_whenDistributorCleared_reverts() public givenPendingBuckets {
        _useDistributor();
        _expectClearingRequiredDistributor();
    }

    // Scenarios: BLCRD-I06.
    function test_givenYieldRouting_whenDistributorCleared_reverts() public givenPendingBuckets {
        _bindDistributor();
        _payout.setSendYieldToDistributor(true);
        _expectClearingRequiredDistributor();
    }

    // Scenarios: BLCRD-I07.
    function test_givenBothRoutes_whenDistributorCleared_reverts() public givenPendingBuckets {
        _useDistributor();
        _payout.setSendYieldToDistributor(true);
        _expectClearingRequiredDistributor();
    }

    // Scenarios: BLCRD-I08.
    function test_givenUnsetDistributor_whenZeroSelected_revertsAsUnchanged()
        public
        givenPendingBuckets
    {
        vm.expectRevert(IBurnerLoansPayout.BurnerLoans_RevenueDistributorRequired.selector);
        _payout.validateRevenueDistributor(address(0));
        _expectSetterRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_UnchangedAddress.selector,
                address(0)
            ),
            address(0)
        );
    }

    function _expectClearingRequiredDistributor() internal {
        vm.expectRevert(IBurnerLoansPayout.BurnerLoans_RevenueDistributorRequired.selector);
        _payout.validateRevenueDistributor(address(0));
        _expectSetterRejected(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoans_RevenueDistributorRequired.selector
            ),
            address(0)
        );
    }

    function _expectInvalidDistributor(address candidate_) internal {
        bytes memory reason = _invalidDistributorError(candidate_);
        vm.expectRevert(reason);
        _payout.validateRevenueDistributor(candidate_);
        _expectSetterRejected(reason, candidate_);
    }

    function _expectSetterRejected(bytes memory reason_, address candidate_) internal {
        bytes32 state = _ledgerDigest();
        address old = _payout.revenueDistributor();
        bool fee = _payout.sendFeesToDistributor();
        bool yield = _payout.sendYieldToDistributor();
        vm.expectRevert(reason_);
        _payout.setRevenueDistributor(candidate_);
        assertEq(_payout.revenueDistributor(), old, "Rejected distributor preserves pointer");
        assertEq(_payout.sendFeesToDistributor(), fee, "Rejected distributor preserves fee route");
        assertEq(
            _payout.sendYieldToDistributor(),
            yield,
            "Rejected distributor preserves yield route"
        );
        assertEq(_ledgerDigest(), state, "Rejected distributor preserves custody");
    }

    // Scenarios: BLCRD-I02.
    function test_givenMissingInterface_whenValidatedAndSelected_reverts()
        public
        givenPendingBuckets
    {
        _distributor = _installDistributor();
        vm.mockCall(
            address(_distributor),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IRevenueDistributor).interfaceId
            ),
            abi.encode(false)
        );
        _expectInvalidDistributor(address(_distributor));
    }

    // Scenarios: BLCRD-I03.
    function test_givenRevertingInterface_whenValidatedAndSelected_reverts()
        public
        givenPendingBuckets
    {
        _distributor = _installDistributor();
        vm.mockCallRevert(
            address(_distributor),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IRevenueDistributor).interfaceId
            ),
            hex"deadbeef"
        );
        _expectInvalidDistributor(address(_distributor));
    }

    // Scenarios: BLCRD-I04.
    function test_givenMalformedInterface_whenValidatedAndSelected_reverts()
        public
        givenPendingBuckets
    {
        _distributor = _installDistributor();
        vm.mockCall(
            address(_distributor),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IRevenueDistributor).interfaceId
            ),
            hex"01"
        );
        _expectInvalidDistributor(address(_distributor));
    }

    // Scenarios: BLCRD-D01.
    function test_givenWrongKernel_whenValidatedAndSelected_reverts() public givenPendingBuckets {
        _distributor = _installDistributor();
        Kernel next = new Kernel();
        vm.prank(address(_kernel));
        _distributor.changeKernel(next);
        bytes memory reason = abi.encodeWithSelector(
            PolicyDependency.PolicyDependency_KernelMismatch.selector,
            address(_distributor),
            address(_kernel),
            address(next)
        );
        vm.expectRevert(reason);
        _payout.validateRevenueDistributor(address(_distributor));
        _expectSetterRejected(reason, address(_distributor));
    }

    // Scenarios: BLCRD-D02.
    function test_givenInactiveEnabled_whenValidatedAndSelected_reverts()
        public
        givenPendingBuckets
    {
        _distributor = _installDistributor();
        _kernel.executeAction(Actions.DeactivatePolicy, address(_distributor));
        bytes memory reason = abi.encodeWithSelector(
            PolicyDependency.PolicyDependency_NotActive.selector,
            address(_distributor)
        );
        vm.expectRevert(reason);
        _payout.validateRevenueDistributor(address(_distributor));
        _expectSetterRejected(reason, address(_distributor));
    }

    // Scenarios: BLCRD-D03.
    function test_givenActivePaused_whenValidatedAndSelected_reverts() public givenPendingBuckets {
        _distributor = _installDistributor();
        _distributor.disable("");
        bytes memory reason = abi.encodeWithSelector(
            PolicyDependency.PolicyDependency_NotActive.selector,
            address(_distributor)
        );
        vm.expectRevert(reason);
        _payout.validateRevenueDistributor(address(_distributor));
        _expectSetterRejected(reason, address(_distributor));
    }

    // Scenarios: BLCRD-D04.
    function test_givenInactivePaused_whenValidatedAndSelected_reverts()
        public
        givenPendingBuckets
    {
        _distributor = _installDistributor();
        _setState(_distributor, false, false);
        bytes memory reason = abi.encodeWithSelector(
            PolicyDependency.PolicyDependency_NotActive.selector,
            address(_distributor)
        );
        vm.expectRevert(reason);
        _payout.validateRevenueDistributor(address(_distributor));
        _expectSetterRejected(reason, address(_distributor));
    }

    // Scenarios: BLCRD-L03, BLCRD-L04.
    function test_givenPayoutInactive_whenCalled_reverts(
        address caller_,
        bool enabled_
    ) public givenPendingBuckets {
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        _setState(_payout, false, enabled_);
        bytes32 state = _ledgerDigest();
        _expectInactivePayout();
        vm.prank(caller_);
        _payout.setRevenueDistributor(address(0));
        assertEq(_ledgerDigest(), state, "Inactive configuration preserves custody");
    }

    // Scenarios: BLCRD-L05.
    function test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins(
        address caller_,
        bool enabled_
    ) public givenPendingBuckets {
        _deactivatePayoutWithBrokenRoles(caller_, enabled_);
        bytes32 state = _ledgerDigest();
        _expectInactivePayout();
        vm.prank(caller_);
        _payout.setRevenueDistributor(address(0));
        assertEq(_ledgerDigest(), state, "Inactivity rejects before authority or mutation");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
