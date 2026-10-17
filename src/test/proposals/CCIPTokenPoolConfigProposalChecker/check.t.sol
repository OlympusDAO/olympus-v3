// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolConfigProposalChecker} from "src/proposals/interfaces/ICCIPTokenPoolConfigProposalChecker.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPTokenPoolConfigProposalCheckerTest} from "./CCIPTokenPoolConfigProposalCheckerTest.sol";

contract CCIPTokenPoolConfigProposalCheckerTests_check is CCIPTokenPoolConfigProposalCheckerTest {
    // ========== STATE MODIFIERS ========== //

    modifier givenHandoverExecuted() {
        _executeHandover();
        _;
    }

    // ========== BINDINGS ========== //

    // given the config policy is not active in the Kernel
    //   [X] it reverts with PolicyNotActive naming the config policy

    function test_givenConfigNotActive_reverts() public {
        Kernel rigKernel = kernel;
        address configAddress = address(config);
        rigKernel.executeAction(Actions.DeactivatePolicy, configAddress);

        _expectRevertPolicyNotActive(address(config));
        checker.check(_phaseBExpectations());
    }

    // given the config timelock is not active in the Kernel
    //   [X] it reverts with PolicyNotActive naming the timelock

    function test_givenTimelockNotActive_reverts() public {
        Kernel rigKernel = kernel;
        address timelockAddress = address(timelock);
        rigKernel.executeAction(Actions.DeactivatePolicy, timelockAddress);

        _expectRevertPolicyNotActive(address(timelock));
        checker.check(_phaseBExpectations());
    }

    // given the registry registers no pool for OHM
    //   [X] it reverts with RegisteredPoolMismatch naming the zero address and the pool

    function test_givenPoolUnregistered_reverts() public {
        _daoSetPool(address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_RegisteredPoolMismatch
                    .selector,
                address(0),
                address(pool)
            )
        );
        checker.check(_phaseBExpectations());
    }

    // given the Kernel has upgraded the ROLES module
    //   [X] it reverts with BindingMismatch naming the new module and the bound one

    function test_givenRolesModuleUpgraded_reverts() public {
        OlympusRoles newRoles = new OlympusRoles(kernel);
        vm.label(address(newRoles), "newRolesModule");
        kernel.executeAction(Actions.UpgradeModule, address(newRoles));

        _expectRevertBindingMismatch("ROLES module", address(newRoles), address(rolesModule));
        checker.check(_phaseBExpectations());
    }

    // given the OCG timelock does not hold admin
    //   [X] it reverts with MissingRole

    function test_givenAdminRoleRevoked_reverts() public {
        rolesAdmin.revokeRole(ADMIN_ROLE, ocgTimelock);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_MissingRole
                    .selector,
                ADMIN_ROLE,
                ocgTimelock
            )
        );
        checker.check(_phaseBExpectations());
    }

    // ========== THE OHM ADMINISTRATOR ========== //

    // given the acceptance is included
    //   given the DAO MS has nominated another administrator
    //     [X] it reverts with OhmAdministratorMismatch naming both live values
    //   given the OCG timelock has already accepted
    //     [X] it reverts with OhmAdministratorMismatch, since nothing is pending
    //   given the nomination stands
    //     [X] it passes

    function test_givenAcceptIncluded_givenAnotherNominee_reverts() public {
        _daoNominateRegistryAdmin(stranger);

        _expectRevertOhmAdministratorMismatch(daoMS, stranger, true);
        checker.check(_phaseBExpectations());
    }

    function test_givenAcceptIncluded_givenAlreadyAccepted_reverts() public {
        _ocgAcceptAdminRole();

        _expectRevertOhmAdministratorMismatch(ocgTimelock, address(0), true);
        checker.check(_phaseBExpectations());
    }

    function test_givenAcceptIncluded_givenNominated() public view {
        checker.check(_phaseBExpectations());
    }

    // given the acceptance is not included
    //   given the DAO MS is still the administrator
    //     [X] it reverts with OhmAdministratorMismatch
    //   given the OCG timelock has accepted
    //     [X] it passes

    function test_givenAcceptNotIncluded_givenNotAccepted_reverts() public {
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.acceptAdminRole = false;

        _expectRevertOhmAdministratorMismatch(daoMS, ocgTimelock, false);
        checker.check(expectations);
    }

    function test_givenAcceptNotIncluded_givenAccepted() public {
        _ocgAcceptAdminRole();
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.acceptAdminRole = false;

        checker.check(expectations);
    }

    // ========== BRIDGE_ADMIN ========== //

    // given the grant is included
    //   given the DAO MS holds bridge_admin
    //     [X] it reverts with BridgeAdminRoleMismatch
    // given the grant is not included
    //   given the DAO MS does not hold bridge_admin
    //     [X] it reverts with BridgeAdminRoleMismatch
    //   given the DAO MS holds bridge_admin
    //     [X] it passes

    function test_givenGrantIncluded_givenRoleHeld_reverts() public {
        rolesAdmin.grantRole(BRIDGE_ADMIN_ROLE, daoMS);

        _expectRevertBridgeAdminRoleMismatch(true, true);
        checker.check(_phaseBExpectations());
    }

    function test_givenGrantNotIncluded_givenRoleNotHeld_reverts() public {
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.grantBridgeAdmin = false;

        _expectRevertBridgeAdminRoleMismatch(false, false);
        checker.check(expectations);
    }

    function test_givenGrantNotIncluded_givenRoleHeld() public {
        rolesAdmin.grantRole(BRIDGE_ADMIN_ROLE, daoMS);
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.grantBridgeAdmin = false;

        checker.check(expectations);
    }

    // ========== THE CONFIG POLICY LIFECYCLE ========== //

    // given the enable of the config policy is included
    //   given the config policy is enabled
    //     [X] it reverts with ConfigEnabledMismatch
    // given the enable is not included
    //   given the config policy is disabled
    //     [X] it reverts with ConfigEnabledMismatch
    //   given the config policy is enabled
    //     [X] it passes

    function test_givenEnableConfigIncluded_givenEnabled_reverts() public {
        _ocgEnableConfig();

        _expectRevertConfigEnabledMismatch(true, true);
        checker.check(_phaseBExpectations());
    }

    function test_givenEnableConfigNotIncluded_givenDisabled_reverts() public {
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.enableConfig = false;

        _expectRevertConfigEnabledMismatch(false, false);
        checker.check(expectations);
    }

    function test_givenEnableConfigNotIncluded_givenEnabled() public {
        _ocgEnableConfig();
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.enableConfig = false;

        checker.check(expectations);
    }

    // ========== THE POOL OWNER ========== //

    // given the ownership acceptance is included
    //   given the config policy has accepted the ownership
    //     [X] it reverts with PoolOwnerMismatch naming the config policy and the DAO MS
    //   given another account has accepted the ownership
    //     [X] it reverts with PoolOwnerMismatch naming that account and the DAO MS
    //   given the DAO MS has proposed another owner, who has not accepted
    //     [X] it passes, since the pool exposes no read of its pending owner

    function test_givenAcceptOwnershipIncluded_givenConfigOwns_reverts() public {
        _ocgEnableConfig();
        _ocgAcceptPoolOwnership();
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.enableConfig = false;

        _expectRevertPoolOwnerMismatch(address(config), daoMS);
        checker.check(expectations);
    }

    function test_givenAcceptOwnershipIncluded_givenAnotherOwner_reverts() public {
        _daoProposePoolOwner(stranger);
        vm.prank(stranger);
        pool.acceptOwnership();

        _expectRevertPoolOwnerMismatch(stranger, daoMS);
        checker.check(_phaseBExpectations());
    }

    function test_givenAcceptOwnershipIncluded_givenPendingOwnerRepointed() public {
        _daoProposePoolOwner(stranger);

        checker.check(_phaseBExpectations());
    }

    // given the ownership acceptance is not included
    //   given the DAO MS still owns the pool
    //     [X] it reverts with PoolOwnerMismatch naming the DAO MS and the config policy
    //   given the config policy owns the pool
    //     [X] it passes

    function test_givenAcceptOwnershipNotIncluded_givenDaoOwns_reverts() public {
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.acceptPoolOwnership = false;

        _expectRevertPoolOwnerMismatch(daoMS, address(config));
        checker.check(expectations);
    }

    function test_givenAcceptOwnershipNotIncluded_givenConfigOwns() public {
        _ocgEnableConfig();
        _ocgAcceptPoolOwnership();
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.enableConfig = false;
        expectations.acceptPoolOwnership = false;

        checker.check(expectations);
    }

    // ========== THE CONFIG OPERATOR ========== //

    // given the rotation is included
    //   given the timelock is already the config operator
    //     [X] it reverts with ConfigOperatorMismatch
    // given the rotation is not included
    //   given the config operator is unset
    //     [X] it reverts with ConfigOperatorMismatch
    //   given the timelock is the config operator
    //     [X] it passes

    function test_givenSetOperatorIncluded_givenAlreadySet_reverts() public {
        _ocgEnableConfig();
        _ocgSetConfigOperator(address(timelock));
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.enableConfig = false;

        _expectRevertConfigOperatorMismatch(address(timelock), address(timelock), true);
        checker.check(expectations);
    }

    function test_givenSetOperatorNotIncluded_givenUnset_reverts() public {
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.setConfigOperator = false;

        _expectRevertConfigOperatorMismatch(address(0), address(timelock), false);
        checker.check(expectations);
    }

    function test_givenSetOperatorNotIncluded_givenSet() public {
        _ocgEnableConfig();
        _ocgSetConfigOperator(address(timelock));
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.enableConfig = false;
        expectations.setConfigOperator = false;

        checker.check(expectations);
    }

    // ========== THE REBALANCER ========== //

    // given the rebalancer setter is included
    //   given the pool rebalancer is already the desired one
    //     [X] it reverts with RebalancerMismatch
    // given the setter is not included
    //   given the pool rebalancer differs from the desired one
    //     [X] it reverts with RebalancerMismatch
    //   given the pool rebalancer is the desired one
    //     [X] it passes

    function test_givenSetRebalancerIncluded_givenAlreadySet_reverts() public {
        _daoSetRebalancer(ocgTimelock);

        _expectRevertRebalancerMismatch(ocgTimelock, ocgTimelock, true);
        checker.check(_phaseBExpectations());
    }

    function test_givenSetRebalancerNotIncluded_givenDiffers_reverts() public {
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.setRebalancer = false;

        _expectRevertRebalancerMismatch(address(0), ocgTimelock, false);
        checker.check(expectations);
    }

    function test_givenSetRebalancerNotIncluded_givenSet() public {
        _daoSetRebalancer(ocgTimelock);
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.setRebalancer = false;

        checker.check(expectations);
    }

    // given the desired rebalancer is another account
    //   [X] the comparison follows the expectations, not the rig

    function test_givenAnotherDesiredRebalancer() public {
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.rebalancer = stranger;
        expectations.setRebalancer = false;
        _daoSetRebalancer(stranger);

        checker.check(expectations);
    }

    // ========== THE RATE LIMIT ADMIN ========== //

    // given the rate limit admin setter is included
    //   given the pool rate limit admin is already the desired one
    //     [X] it reverts with RateLimitAdminMismatch
    //   given the pool rate limit admin differs from the desired one
    //     [X] it passes
    // given the setter is not included
    //   given the pool rate limit admin differs from the desired one
    //     [X] it reverts with RateLimitAdminMismatch

    function test_givenSetRateLimitAdminIncluded_givenAlreadySet_reverts() public {
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.setRateLimitAdmin = true;

        _expectRevertRateLimitAdminMismatch(address(0), address(0), true);
        checker.check(expectations);
    }

    function test_givenSetRateLimitAdminIncluded_givenDiffers() public {
        _daoSetRateLimitAdmin(stranger);
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.setRateLimitAdmin = true;

        checker.check(expectations);
    }

    function test_givenSetRateLimitAdminNotIncluded_givenDiffers_reverts() public {
        _daoSetRateLimitAdmin(stranger);

        _expectRevertRateLimitAdminMismatch(stranger, address(0), false);
        checker.check(_phaseBExpectations());
    }

    // ========== THE CONFIG TIMELOCK LIFECYCLE ========== //

    // given the enable of the timelock is included
    //   given the timelock is enabled
    //     [X] it reverts with TimelockEnabledMismatch
    // given the enable is not included
    //   given the timelock is disabled
    //     [X] it reverts with TimelockEnabledMismatch
    //   given the timelock is enabled
    //     [X] it passes

    function test_givenEnableTimelockIncluded_givenEnabled_reverts() public {
        _ocgEnableTimelock();

        _expectRevertTimelockEnabledMismatch(true, true);
        checker.check(_phaseBExpectations());
    }

    function test_givenEnableTimelockNotIncluded_givenDisabled_reverts() public {
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.enableTimelock = false;

        _expectRevertTimelockEnabledMismatch(false, false);
        checker.check(expectations);
    }

    function test_givenEnableTimelockNotIncluded_givenEnabled() public {
        _ocgEnableTimelock();
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.enableTimelock = false;

        checker.check(expectations);
    }

    // ========== THE ROUTES ========== //

    // given a listed route exists on the pool
    //   [X] it reverts with RouteAlreadyExists naming the first listed one that exists
    // given the list is empty
    //   [X] it passes whatever the pool serves

    function test_givenListedRouteExists_reverts() public {
        _daoAddRoute(CHAIN_SELECTOR_B);

        _expectRevertRouteAlreadyExists(CHAIN_SELECTOR_B);
        checker.check(_phaseBExpectations());
    }

    function test_givenEveryListedRouteExists_revertsOnTheFirst() public {
        _daoAddRoute(CHAIN_SELECTOR_A);
        _daoAddRoute(CHAIN_SELECTOR_B);
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.routesToAdd[0] = CHAIN_SELECTOR_B;
        expectations.routesToAdd[1] = CHAIN_SELECTOR_A;

        _expectRevertRouteAlreadyExists(CHAIN_SELECTOR_B);
        checker.check(expectations);
    }

    function test_givenEmptyList_givenRoutesExist() public {
        _daoAddRoute(CHAIN_SELECTOR_A);
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.routesToAdd = new uint64[](0);

        checker.check(expectations);
    }

    // ========== THE BACKING ========== //

    // given the pool holds less than the minimum
    //   [X] it reverts with BackingTooLow naming the balance and the minimum
    // given the pool holds exactly the minimum
    //   [X] it passes
    // given the minimum is zero
    //   [X] it passes

    function test_givenBackingBelowMinimum_reverts() public {
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.minimumPoolBacking = MIN_BACKING + 1;

        _expectRevertBackingTooLow(MIN_BACKING, MIN_BACKING + 1);
        checker.check(expectations);
    }

    function test_givenBackingAtMinimum() public view {
        checker.check(_phaseBExpectations());
    }

    function test_givenZeroMinimum() public {
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.minimumPoolBacking = 0;

        checker.check(expectations);
    }

    // ========== ORDER ========== //

    // given several expectations fail
    //   [X] the first one in action order is reported

    function test_givenSeveralFailures_reportsTheFirst() public {
        _ocgEnableConfig();
        _daoAddRoute(CHAIN_SELECTOR_A);
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.minimumPoolBacking = MIN_BACKING + 1;

        _expectRevertConfigEnabledMismatch(true, true);
        checker.check(expectations);
    }

    function test_givenBindingAndExpectationFail_reportsTheBinding() public {
        _ocgEnableConfig();
        rolesAdmin.revokeRole(ADMIN_ROLE, ocgTimelock);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_MissingRole
                    .selector,
                ADMIN_ROLE,
                ocgTimelock
            )
        );
        checker.check(_phaseBExpectations());
    }

    // given every expectation fails at once
    //   [X] each repair surfaces the next error, in action order, down to the backing

    function test_givenEveryExpectationFails_reportsInActionOrder() public {
        _executeHandover();
        _ocgAddRoute(CHAIN_SELECTOR_A);
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _phaseBExpectations();
        expectations.setRateLimitAdmin = true;
        expectations.minimumPoolBacking = MIN_BACKING + 1;

        _expectRevertOhmAdministratorMismatch(ocgTimelock, address(0), true);
        checker.check(expectations);
        expectations.acceptAdminRole = false;

        _expectRevertBridgeAdminRoleMismatch(true, true);
        checker.check(expectations);
        expectations.grantBridgeAdmin = false;

        _expectRevertConfigEnabledMismatch(true, true);
        checker.check(expectations);
        expectations.enableConfig = false;

        _expectRevertPoolOwnerMismatch(address(config), daoMS);
        checker.check(expectations);
        expectations.acceptPoolOwnership = false;

        _expectRevertConfigOperatorMismatch(address(timelock), address(timelock), true);
        checker.check(expectations);
        expectations.setConfigOperator = false;

        _expectRevertRebalancerMismatch(ocgTimelock, ocgTimelock, true);
        checker.check(expectations);
        expectations.setRebalancer = false;

        _expectRevertRateLimitAdminMismatch(address(0), address(0), true);
        checker.check(expectations);
        expectations.setRateLimitAdmin = false;

        _expectRevertTimelockEnabledMismatch(true, true);
        checker.check(expectations);
        expectations.enableTimelock = false;

        _expectRevertRouteAlreadyExists(CHAIN_SELECTOR_A);
        checker.check(expectations);
        expectations.routesToAdd = new uint64[](0);

        _expectRevertBackingTooLow(MIN_BACKING, MIN_BACKING + 1);
        checker.check(expectations);
        expectations.minimumPoolBacking = MIN_BACKING;

        checker.check(expectations);
    }

    // ========== THE END STATE ========== //

    // given the whole handover has executed
    //   given nothing is included
    //     [X] it passes
    //   given the routes were added through the config policy
    //     [X] it passes with an empty list
    //   given the build expectations
    //     [X] it reverts at the first handover expectation

    function test_givenHandoverExecuted_givenEndState() public givenHandoverExecuted {
        checker.check(_endStateExpectations());
    }

    function test_givenHandoverExecuted_givenRoutesAdded() public givenHandoverExecuted {
        _ocgAddRoute(CHAIN_SELECTOR_A);
        _ocgAddRoute(CHAIN_SELECTOR_B);

        checker.check(_endStateExpectations());
    }

    function test_givenHandoverExecuted_givenPhaseBExpectations_reverts()
        public
        givenHandoverExecuted
    {
        _expectRevertOhmAdministratorMismatch(ocgTimelock, address(0), true);
        checker.check(_phaseBExpectations());
    }

    // given the handover has executed except the enable of the timelock
    //   given only that enable is included
    //     [X] it passes

    function test_givenPartialHandover_givenOnlyTimelockEnableIncluded() public {
        _ocgAcceptAdminRole();
        rolesAdmin.grantRole(BRIDGE_ADMIN_ROLE, daoMS);
        _ocgEnableConfig();
        _ocgAcceptPoolOwnership();
        _ocgSetConfigOperator(address(timelock));
        _ocgSetRebalancer(ocgTimelock);
        ICCIPTokenPoolConfigProposalChecker.Expectations
            memory expectations = _endStateExpectations();
        expectations.enableTimelock = true;

        checker.check(expectations);
    }

    // ========== CALLER ========== //

    // given any caller
    //   [X] it reads the same state

    function test_givenAnyCaller() public {
        vm.prank(stranger);
        checker.check(_phaseBExpectations());
    }
}
