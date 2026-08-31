// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";

// Contracts
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockRouterCandidate} from "src/test/policies/bridge/mocks/MockRouterCandidate.sol";

import {CCIPTokenPoolConfigTest} from "./CCIPTokenPoolConfigTest.sol";

contract CCIPTokenPoolConfigTests_setRouter is CCIPTokenPoolConfigTest {
    /// @notice Deploys a router candidate answering the probe in the requested mode.
    function _newRouterCandidate(
        MockRouterCandidate.ReturnMode mode_
    ) internal returns (MockRouterCandidate candidate) {
        candidate = new MockRouterCandidate();
        vm.label(address(candidate), "routerCandidate");
        candidate.setMode(mode_);
        return candidate;
    }

    // given the policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenDisabled_reverts() public {
        address candidate = address(
            _newRouterCandidate(MockRouterCandidate.ReturnMode.ValidVersion)
        );

        _expectRevertNotEnabled();
        vm.prank(admin);
        config.setRouter(candidate);
    }

    // given the policy is disabled
    //   when the caller does not hold the admin role
    //     [X] it reverts with NotEnabled
    function test_givenDisabled_whenCallerIsNotAdmin_reverts() public {
        address caller = makeAddr("unauthorizedCaller");
        address candidate = address(
            _newRouterCandidate(MockRouterCandidate.ReturnMode.ValidVersion)
        );

        _expectRevertNotEnabled();
        vm.prank(caller);
        config.setRouter(candidate);
    }

    // when the caller does not hold the admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // The fuzz excludes the admin account and the zero address
    function test_whenCallerIsNotAdmin_reverts(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(0));
        address candidate = address(
            _newRouterCandidate(MockRouterCandidate.ReturnMode.ValidVersion)
        );

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller_);
        config.setRouter(candidate);
    }

    // given the config operator is set
    //   when the caller is the config operator
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Role asymmetry: the infrastructure pointer is admin-only
    function test_whenCallerIsConfigOperator_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenConfigOperatorSet
    {
        address candidate = address(
            _newRouterCandidate(MockRouterCandidate.ReturnMode.ValidVersion)
        );

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(operator);
        config.setRouter(candidate);
    }

    // when the caller holds only the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsBridgeAdmin_reverts() public givenEnabled givenPoolOwnershipAccepted {
        address candidate = address(
            _newRouterCandidate(MockRouterCandidate.ReturnMode.ValidVersion)
        );

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(bridgeAdmin);
        config.setRouter(candidate);
    }

    // when the caller holds only the emergency role
    //   [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsEmergency_reverts() public givenEnabled givenPoolOwnershipAccepted {
        address candidate = address(
            _newRouterCandidate(MockRouterCandidate.ReturnMode.ValidVersion)
        );

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(emergency);
        config.setRouter(candidate);
    }

    // when the caller does not hold the admin role
    //   when the router is the zero address
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Pins the masking order: the role check answers before the candidate checks
    function test_whenCallerIsNotAdmin_whenRouterIsZero_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller);
        config.setRouter(address(0));
    }

    // when the router is the zero address
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidAddress("router")
    // Pins the error identity: the dedicated zero check answers before the code probe, which
    // would report InvalidRouter for the same address.
    function test_whenRouterIsZero_reverts() public givenEnabled givenPoolOwnershipAccepted {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_InvalidAddress.selector,
                "router"
            )
        );
        vm.prank(admin);
        config.setRouter(address(0));

        assertEq(pool.getRouter(), address(ccipRouter), "the pool router should be unchanged");
    }

    // when the router candidate holds no code
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidRouter
    // The load-bearing code check: a staticcall to an EOA would succeed with empty return
    // data, so without it the EOA would only fail at the length check.
    function test_whenRouterHasNoCode_reverts() public givenEnabled givenPoolOwnershipAccepted {
        address candidate = makeAddr("codelessRouter");
        assertEq(candidate.code.length, 0, "the candidate should hold no code");

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_InvalidRouter.selector,
                candidate
            )
        );
        vm.prank(admin);
        config.setRouter(candidate);

        assertEq(pool.getRouter(), address(ccipRouter), "the pool router should be unchanged");
    }

    // when the router candidate does not implement typeAndVersion
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidRouter
    // The probe call rejects the unknown selector; MockCCIPRouter itself is such a candidate
    function test_whenRouterDoesNotImplementTypeAndVersion_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        // The mock router of the rig declares no typeAndVersion and no fallback, so the probe
        // call itself fails
        address candidate = address(ccipRouter);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_InvalidRouter.selector,
                candidate
            )
        );
        vm.prank(admin);
        config.setRouter(candidate);
    }

    // given the candidate's typeAndVersion reverts
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidRouter
    // The explicit-revert candidate from the MockRouterCandidate family
    function test_givenTypeAndVersionReverts_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address candidate = address(_newRouterCandidate(MockRouterCandidate.ReturnMode.Reverting));

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_InvalidRouter.selector,
                candidate
            )
        );
        vm.prank(admin);
        config.setRouter(candidate);

        assertEq(pool.getRouter(), address(ccipRouter), "the pool router should be unchanged");
    }

    // given the candidate's typeAndVersion returns short data
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidRouter
    // The failing side of the length boundary: 32 returned bytes, below the 64-byte minimum
    function test_givenTypeAndVersionReturnsShortData_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address candidate = address(
            _newRouterCandidate(MockRouterCandidate.ReturnMode.ShortReturn)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_InvalidRouter.selector,
                candidate
            )
        );
        vm.prank(admin);
        config.setRouter(candidate);

        assertEq(pool.getRouter(), address(ccipRouter), "the pool router should be unchanged");
    }

    // when the router candidate is invalid
    //   given the pool is owned by an unrelated third party
    //     [X] it reverts with CCIPTokenPoolConfig_InvalidRouter
    // Pins the order: the candidate validation answers before the pool's owner check
    function test_whenRouterIsInvalid_givenPoolOwnedByThirdParty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        address candidate = address(_newRouterCandidate(MockRouterCandidate.ReturnMode.Reverting));

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_InvalidRouter.selector,
                candidate
            )
        );
        vm.prank(admin);
        config.setRouter(candidate);
    }

    // given the pool is owned by an unrelated third party
    //   [X] it reverts with OnlyCallableByOwner
    // The candidate is valid, so the failure is the pool call itself
    function test_givenPoolOwnedByThirdParty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        address candidate = address(
            _newRouterCandidate(MockRouterCandidate.ReturnMode.ValidVersion)
        );

        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.setRouter(candidate);

        assertEq(pool.getRouter(), address(ccipRouter), "the pool router should be unchanged");
    }

    // when the caller holds the admin role
    //   [X] the pool reports the new router through getRouter
    //   [X] the pool emits RouterUpdated with the old and the new value
    //   [X] it emits PoolRouterSet with the new value
    // The candidate answers typeAndVersion but serves none of the configured routes: whether
    // it serves them is deliberately not checked, as the function NatSpec states.
    function test_whenCallerIsAdmin() public givenEnabled givenPoolOwnershipAccepted {
        address candidate = address(
            _newRouterCandidate(MockRouterCandidate.ReturnMode.ValidVersion)
        );
        address previousRouter = pool.getRouter();
        assertEq(
            previousRouter,
            address(ccipRouter),
            "the pool router should start at the rig one"
        );

        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.RouterUpdated(previousRouter, candidate);
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolRouterSet(candidate);
        vm.prank(admin);
        config.setRouter(candidate);

        assertEq(pool.getRouter(), candidate, "the pool router should be the candidate");
    }

    // given the candidate's typeAndVersion returns the empty string
    //   [X] it sets the router
    // The passing side of the length boundary: the ABI encoding of an empty string is
    // exactly 64 bytes.
    function test_givenTypeAndVersionReturnsEmptyString()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address candidate = address(
            _newRouterCandidate(MockRouterCandidate.ReturnMode.EmptyString)
        );

        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolRouterSet(candidate);
        vm.prank(admin);
        config.setRouter(candidate);

        assertEq(pool.getRouter(), candidate, "the pool router should be the candidate");
    }

    // given the candidate's typeAndVersion returns garbage of 64 or more bytes
    //   [X] it sets the router
    // The probe checks the length only and never decodes the string
    function test_givenTypeAndVersionReturnsGarbage()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address candidate = address(
            _newRouterCandidate(MockRouterCandidate.ReturnMode.LongGarbage)
        );

        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolRouterSet(candidate);
        vm.prank(admin);
        config.setRouter(candidate);

        assertEq(pool.getRouter(), candidate, "the pool router should be the candidate");
    }

    // when the value equals the current router
    //   [X] it writes and emits both events again
    // The valid candidate is installed first and then re-set; the rig's initial
    // MockCCIPRouter cannot be re-set because it does not answer the probe.
    function test_whenValueEqualsCurrentRouter() public givenEnabled givenPoolOwnershipAccepted {
        address candidate = address(
            _newRouterCandidate(MockRouterCandidate.ReturnMode.ValidVersion)
        );

        vm.prank(admin);
        config.setRouter(candidate);
        assertEq(pool.getRouter(), candidate, "the pool router should be the candidate");

        // The old and the new value of the pool event are the same address on the re-set
        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.RouterUpdated(candidate, candidate);
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPTokenPoolConfig.PoolRouterSet(candidate);
        vm.prank(admin);
        config.setRouter(candidate);

        assertEq(pool.getRouter(), candidate, "the pool router should still be the candidate");
    }
}
