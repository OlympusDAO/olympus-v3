// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";

// Contracts
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockCCIPRouter} from "src/test/policies/bridge/mocks/MockCCIPRouter.sol";
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
    // Fuzzed over every address: the lifecycle error answers before any caller check
    function test_givenDisabled_whenCallerIsNotAdmin_reverts(address caller_) public {
        address candidate = address(
            _newRouterCandidate(MockRouterCandidate.ReturnMode.ValidVersion)
        );

        _expectRevertNotEnabled();
        vm.prank(caller_);
        config.setRouter(candidate);
    }

    // when the caller does not hold the admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // The fuzz excludes the admin account
    function test_whenCallerIsNotAdmin_reverts(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted {
        vm.assume(caller_ != admin);

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
    // The fuzz excludes the admin account
    function test_whenCallerIsNotAdmin_whenRouterIsZero_reverts(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted {
        vm.assume(caller_ != admin);

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller_);
        config.setRouter(address(0));
    }

    // when the caller does not hold the admin role
    //   when the router equals the current router
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Pins the masking order: the role check answers before the unchanged check. The rig's
    // router is the current one, so no candidate needs installing first.
    // The fuzz excludes the admin account
    function test_whenCallerIsNotAdmin_whenValueEqualsCurrentRouter_reverts(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted {
        vm.assume(caller_ != admin);

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller_);
        config.setRouter(address(ccipRouter));
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
    // The probe call rejects the unknown selector; MockCCIPRouter itself is such a candidate.
    // A fresh instance rather than the rig's router, which the unchanged check would reject
    // first as the pool's current router.
    function test_whenRouterDoesNotImplementTypeAndVersion_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        // The mock router declares no typeAndVersion and no fallback, so the probe call itself
        // fails
        address candidate = address(new MockCCIPRouter());
        vm.label(candidate, "routerWithoutTypeAndVersion");

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

    // given the candidate's typeAndVersion does not fit the probe budget
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidRouter
    // The candidate answers with 256 KiB, which costs it 262144 / 32 = 8192 words of memory:
    // 3 * 8192 + 8192^2 / 512 = 24,576 + 131,072 = 155,648 gas, five times the 30,000 the probe
    // forwards. The candidate therefore runs out of gas inside its own frame, this call keeps the
    // rest of its own gas, and the rejection is the ordinary error rather than an out-of-gas of
    // the whole transaction: without the budget the candidate would consume 63/64 of what the
    // caller holds before failing.
    function test_givenTypeAndVersionExceedsProbeBudget_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address candidate = address(
            _newRouterCandidate(MockRouterCandidate.ReturnMode.OversizedReturn)
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

    // when the value equals the current router
    //   [X] it reverts with CCIPTokenPoolConfig_AddressUnchanged("router")
    // The valid candidate is installed first and then re-set
    function test_whenValueEqualsCurrentRouter_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address candidate = address(
            _newRouterCandidate(MockRouterCandidate.ReturnMode.ValidVersion)
        );

        vm.prank(admin);
        config.setRouter(candidate);
        assertEq(pool.getRouter(), candidate, "the pool router should be the candidate");

        _expectRevertAddressUnchanged("router");
        vm.prank(admin);
        config.setRouter(candidate);

        assertEq(pool.getRouter(), candidate, "the pool router should still be the candidate");
    }

    // when the value equals the current router
    //   given the current router no longer answers the probe
    //     [X] it reverts with CCIPTokenPoolConfig_AddressUnchanged("router")
    // Pins the order: the unchanged check answers before the probe, so the installed router's
    // answer has no bearing on the rejection. The candidate is installed while valid and then
    // switched to a reverting answer; the rig's initial MockCCIPRouter cannot serve this case
    // because it never answered the probe.
    function test_whenValueEqualsCurrentRouter_givenRouterNoLongerAnswersProbe_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        MockRouterCandidate candidate = _newRouterCandidate(
            MockRouterCandidate.ReturnMode.ValidVersion
        );
        address candidateAddress = address(candidate);

        vm.prank(admin);
        config.setRouter(candidateAddress);
        candidate.setMode(MockRouterCandidate.ReturnMode.Reverting);

        _expectRevertAddressUnchanged("router");
        vm.prank(admin);
        config.setRouter(candidateAddress);

        assertEq(
            pool.getRouter(),
            candidateAddress,
            "the pool router should still be the candidate"
        );
    }
}
