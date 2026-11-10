// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansPayoutSetConfigOperatorTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-CONFIGURATOR-P01, BLCU-CONFIGURATOR-A03.
    function test_whenAdminInstallsController_thenNoReverseReads(
        address caller_,
        bool enabled_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenPendingBuckets {
        vm.assume(caller_ != address(0));
        _grantRoleIfMissing(ADMIN_ROLE, caller_);
        _setState(_payout, true, enabled_);
        _setState(_core, coreActive_, coreEnabled_);
        address next = address(_config);
        vm.mockCallRevert(next, abi.encodeWithSignature("kernel()"), hex"deadbeef");
        vm.mockCallRevert(next, abi.encodeWithSignature("isEnabled()"), hex"deadbeef");
        vm.mockCallRevert(
            next,
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            hex"deadbeef"
        );
        bytes32 state = _ledgerDigest();
        vm.expectEmit(address(_payout));
        emit IConfigOperator.ConfigOperatorSet(next);
        vm.prank(caller_);
        _payout.setConfigOperator(next);
        assertEq(_payout.configOperator(), next, "Store independent local controller");
        assertEq(_ledgerDigest(), state, "Authority repair preserves obligations");
    }

    // Scenarios: BLCU-CONFIGURATOR-A01.
    function test_whenCallerLacksAdmin_reverts(address caller_) public givenPendingBuckets {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        bytes32 state = _ledgerDigest();
        address operator = _payout.configOperator();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _payout.setConfigOperator(_destination);
        assertEq(_payout.configOperator(), operator, "Unauthorized pointer unchanged");
        assertEq(_ledgerDigest(), state, "Unauthorized repair preserves custody");
    }

    // Scenarios: BLCU-CONFIGURATOR-A01.
    function test_givenCoreOrStoredOperator_whenInstallingSuccessor_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenCallerLacksAdmin_reverts(address(_core));
        _restore(checkpoint);
        test_whenCallerLacksAdmin_reverts(_controller);
    }

    // Scenarios: BLCU-CONFIGURATOR-A02.
    function test_whenOperatorUnchanged_reverts() public givenPendingBuckets {
        bytes32 state = _ledgerDigest();
        vm.expectRevert(IConfigOperator.ConfigOperator_Unchanged.selector);
        _payout.setConfigOperator(_controller);
        assertEq(_ledgerDigest(), state, "Same pointer rejection preserves custody");
    }

    // Scenarios: BLCU-CONFIGURATOR-A04.
    function test_givenNonzeroOperator_whenCleared_thenDelegationRevoked()
        public
        givenPendingBuckets
    {
        bytes32 state = _ledgerDigest();
        vm.expectEmit(address(_payout));
        emit IConfigOperator.ConfigOperatorSet(address(0));
        _payout.setConfigOperator(address(0));
        assertEq(_payout.configOperator(), address(0), "Delegation revoked");
        assertEq(_ledgerDigest(), state, "Revocation preserves obligations");
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(_controller);
        _payout.setSendFeesToDistributor(false);
    }

    function test_givenCoreBusy_whenOperatorSet_reverts() public givenPendingBuckets {
        bytes32 state = _ledgerDigest();
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(_core.requireNotReentrant, ()),
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector)
        );
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        _payout.setConfigOperator(_destination);
        assertEq(_payout.configOperator(), _controller, "Busy Core retains authority");
        assertEq(_ledgerDigest(), state, "Busy Core retains custody");
    }

    // Scenarios: BLCU-CONFIGURATOR-P02.
    function test_givenPayoutInactive_whenCalled_reverts(
        address caller_,
        bool enabled_
    ) public givenPendingBuckets {
        _grantRoleIfMissing(ADMIN_ROLE, caller_);
        _setState(_payout, false, enabled_);
        bytes32 state = _ledgerDigest();
        _expectInactivePayout();
        vm.prank(caller_);
        _payout.setConfigOperator(_destination);
        assertEq(_ledgerDigest(), state, "Inactive configuration preserves custody");
    }

    // Scenarios: BLCU-CONFIGURATOR-L01.
    function test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins(
        address caller_,
        bool enabled_
    ) public givenPendingBuckets {
        _deactivatePayoutWithBrokenRoles(caller_, enabled_);
        bytes32 state = _ledgerDigest();
        _expectInactivePayout();
        vm.prank(caller_);
        _payout.setConfigOperator(_controller);
        assertEq(_ledgerDigest(), state, "Inactivity rejects before authority or mutation");
    }

    // Scenarios: BLCU-CONFIGURATOR-P01, BLCU-CONFIGURATOR-A03.
    function test_givenExistingAdmin_whenControllerInstalled_thenNoReverseReads() public {
        test_whenAdminInstallsController_thenNoReverseReads(address(this), true, true, true);
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
