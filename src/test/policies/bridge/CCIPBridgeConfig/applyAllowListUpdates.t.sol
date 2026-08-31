// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";

// Contracts
import {Vm} from "@forge-std-1.16.2/Vm.sol";

import {CCIPBridgeConfigTest} from "./CCIPBridgeConfigTest.sol";

contract CCIPBridgeConfigTests_applyAllowListUpdates is CCIPBridgeConfigTest {
    /// @notice Wraps a single address into a one-element array argument.
    function _singleAddress(address entry_) internal pure returns (address[] memory entries) {
        entries = new address[](1);
        entries[0] = entry_;
        return entries;
    }

    /// @notice Asserts the allowlist of the current rig pool matches the expected entries.
    function _assertAllowList(address[] memory expected_, string memory label_) internal view {
        address[] memory current = pool.getAllowList();
        assertEq(current.length, expected_.length, string.concat(label_, ": length"));
        for (uint256 i; i < expected_.length; ++i) {
            assertEq(current[i], expected_[i], string.concat(label_, ": entry"));
        }
    }

    // given the policy is disabled
    //   [X] it reverts with NotEnabled
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.applyAllowListUpdates(new address[](0), _singleAddress(thirdParty));
    }

    // given the policy is disabled
    //   when the caller is not authorized
    //     [X] it reverts with NotEnabled
    function test_givenDisabled_whenCallerIsNotAuthorized_reverts() public {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotEnabled();
        vm.prank(caller);
        config.applyAllowListUpdates(new address[](0), _singleAddress(thirdParty));
    }

    // when the caller is neither the config operator nor an admin
    //   [X] it reverts with NotAuthorised
    // The fuzz excludes the admin, the operator and the zero address
    function test_whenCallerIsNotAuthorized_reverts(
        address caller_
    ) public givenEnabled givenPoolOwnershipAccepted givenConfigOperatorSet {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != operator);
        vm.assume(caller_ != address(0));

        _expectRevertNotAuthorised();
        vm.prank(caller_);
        config.applyAllowListUpdates(new address[](0), _singleAddress(thirdParty));
    }

    // when the caller holds only the bridge admin role
    //   [X] it reverts with NotAuthorised
    function test_whenCallerIsBridgeAdmin_reverts() public givenEnabled givenPoolOwnershipAccepted {
        _expectRevertNotAuthorised();
        vm.prank(bridgeAdmin);
        config.applyAllowListUpdates(new address[](0), _singleAddress(thirdParty));
    }

    // when the caller holds only the bridge rate limiter role
    //   [X] it reverts with NotAuthorised
    function test_whenCallerIsBridgeRateLimiter_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        _expectRevertNotAuthorised();
        vm.prank(bridgeRateLimiter);
        config.applyAllowListUpdates(new address[](0), _singleAddress(thirdParty));
    }

    // when the caller holds only the emergency role
    //   [X] it reverts with NotAuthorised
    function test_whenCallerIsEmergency_reverts() public givenEnabled givenPoolOwnershipAccepted {
        _expectRevertNotAuthorised();
        vm.prank(emergency);
        config.applyAllowListUpdates(new address[](0), _singleAddress(thirdParty));
    }

    // when the caller is not authorized
    //   given the pool has no allowlist
    //     [X] it reverts with NotAuthorised
    // Pins the masking order: authorization answers before the allowlist probe
    function test_whenCallerIsNotAuthorized_givenPoolHasNoAllowList_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address caller = makeAddr("unauthorizedCaller");
        assertFalse(pool.getAllowListEnabled(), "the primary rig pool has no allowlist");

        _expectRevertNotAuthorised();
        vm.prank(caller);
        config.applyAllowListUpdates(new address[](0), _singleAddress(thirdParty));
    }

    // given the pool has no allowlist
    //   [X] it reverts with AllowListNotEnabled
    //   [X] validateApplyAllowListUpdates reverts with the same error
    // The primary rig pool deploys with an empty allowlist, so the immutable flag is false
    // and every call on it lands here.
    function test_givenPoolHasNoAllowList_reverts() public givenEnabled givenPoolOwnershipAccepted {
        address[] memory adds = _singleAddress(thirdParty);
        bytes memory err = abi.encodeWithSelector(ICCIPTokenPoolAdmin.AllowListNotEnabled.selector);

        vm.expectRevert(err);
        vm.prank(admin);
        config.applyAllowListUpdates(new address[](0), adds);

        vm.expectRevert(err);
        config.validateApplyAllowListUpdates(new address[](0), adds);
    }

    // given the pool has no allowlist
    //   when both arrays are empty
    //     [X] it reverts with AllowListNotEnabled
    // Pins the order: the allowlist probe answers before the emptiness check
    function test_givenPoolHasNoAllowList_whenUpdatesAreEmpty_reverts()
        public
        givenEnabled
        givenPoolOwnershipAccepted
    {
        vm.expectRevert(abi.encodeWithSelector(ICCIPTokenPoolAdmin.AllowListNotEnabled.selector));
        vm.prank(admin);
        config.applyAllowListUpdates(new address[](0), new address[](0));
    }

    // when both arrays are empty
    //   [X] it reverts with CCIPBridgeConfig_AllowListUpdatesEmpty
    //   [X] validateApplyAllowListUpdates reverts with the same error
    // The pool would accept the empty pair as a no-op; the config-only check rejects it
    function test_whenUpdatesAreEmpty_reverts()
        public
        givenAllowListPoolRig
        givenEnabled
        givenPoolOwnershipAccepted
    {
        assertTrue(pool.getAllowListEnabled(), "the allowlist rig pool has an allowlist");
        bytes memory err = abi.encodeWithSelector(
            ICCIPBridgeConfig.CCIPBridgeConfig_AllowListUpdatesEmpty.selector
        );

        vm.expectRevert(err);
        vm.prank(admin);
        config.applyAllowListUpdates(new address[](0), new address[](0));

        vm.expectRevert(err);
        config.validateApplyAllowListUpdates(new address[](0), new address[](0));
    }

    // given the pool is owned by an unrelated third party
    //   [X] it reverts with OnlyCallableByOwner
    function test_givenPoolOwnedByThirdParty_reverts()
        public
        givenAllowListPoolRig
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        address newEntry = makeAddr("allowListCandidate");

        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.applyAllowListUpdates(new address[](0), _singleAddress(newEntry));

        address[] memory expected = new address[](2);
        expected[0] = allowListedOne;
        expected[1] = allowListedTwo;
        _assertAllowList(expected, "allowlist after the rejected call");
    }

    // when the caller is an admin
    //   [X] getAllowList reflects the removals and the additions
    //   [X] the pool emits AllowListRemove and AllowListAdd per effective change
    //   [X] it emits AllowListUpdated carrying the raw arguments
    //   [X] validateApplyAllowListUpdates returns for the same input before the call
    // The main happy path on the allowlist rig: one effective removal, two effective adds
    function test_whenCallerIsAdmin()
        public
        givenAllowListPoolRig
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address firstNewEntry = makeAddr("allowListCandidateOne");
        address secondNewEntry = makeAddr("allowListCandidateTwo");
        address[] memory removes = _singleAddress(allowListedOne);
        address[] memory adds = new address[](2);
        adds[0] = firstNewEntry;
        adds[1] = secondNewEntry;

        config.validateApplyAllowListUpdates(removes, adds);

        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.AllowListRemove(allowListedOne);
        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.AllowListAdd(firstNewEntry);
        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.AllowListAdd(secondNewEntry);
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPBridgeConfig.AllowListUpdated(removes, adds);
        vm.prank(admin);
        config.applyAllowListUpdates(removes, adds);

        // The pool's set swaps the last entry into the removed slot, so the surviving initial
        // entry comes first and the additions follow in argument order
        address[] memory expected = new address[](3);
        expected[0] = allowListedTwo;
        expected[1] = firstNewEntry;
        expected[2] = secondNewEntry;
        _assertAllowList(expected, "allowlist after the update");
    }

    // when the caller is the config operator
    //   [X] it applies the updates
    function test_whenCallerIsConfigOperator()
        public
        givenAllowListPoolRig
        givenEnabled
        givenPoolOwnershipAccepted
        givenConfigOperatorSet
    {
        address newEntry = makeAddr("allowListCandidate");

        vm.prank(operator);
        config.applyAllowListUpdates(new address[](0), _singleAddress(newEntry));

        address[] memory expected = new address[](3);
        expected[0] = allowListedOne;
        expected[1] = allowListedTwo;
        expected[2] = newEntry;
        _assertAllowList(expected, "allowlist after the operator update");
    }

    // when only removals are supplied
    //   [X] it applies the removals
    // One non-empty side passes the AND-shaped emptiness check
    function test_whenRemovesOnly()
        public
        givenAllowListPoolRig
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address[] memory removes = _singleAddress(allowListedOne);

        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.AllowListRemove(allowListedOne);
        vm.prank(admin);
        config.applyAllowListUpdates(removes, new address[](0));

        address[] memory expected = _singleAddress(allowListedTwo);
        _assertAllowList(expected, "allowlist after the removal");
    }

    // when only additions are supplied
    //   [X] it applies the additions
    function test_whenAddsOnly()
        public
        givenAllowListPoolRig
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address newEntry = makeAddr("allowListCandidate");

        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.AllowListAdd(newEntry);
        vm.prank(admin);
        config.applyAllowListUpdates(new address[](0), _singleAddress(newEntry));

        address[] memory expected = new address[](3);
        expected[0] = allowListedOne;
        expected[1] = allowListedTwo;
        expected[2] = newEntry;
        _assertAllowList(expected, "allowlist after the addition");
    }

    // when an addition is the zero address
    //   [X] it succeeds
    //   [X] the zero address is not added and no AllowListAdd is emitted for it
    // The pool skips zero silently; the absence claim needs vm.recordLogs
    function test_whenAddContainsZeroAddress()
        public
        givenAllowListPoolRig
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address[] memory adds = _singleAddress(address(0));

        vm.recordLogs();
        vm.prank(admin);
        config.applyAllowListUpdates(new address[](0), adds);

        address[] memory expected = new address[](2);
        expected[0] = allowListedOne;
        expected[1] = allowListedTwo;
        _assertAllowList(expected, "allowlist after the zero addition");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(
            _countLogs(logs, address(pool), ICCIPTokenPoolAdmin.AllowListAdd.selector),
            0,
            "the pool should emit no AllowListAdd for the zero address"
        );
        assertEq(
            _countLogs(logs, address(config), ICCIPBridgeConfig.AllowListUpdated.selector),
            1,
            "the config should still emit AllowListUpdated"
        );
    }

    // when an addition is already present
    //   [X] it succeeds without emitting AllowListAdd for the duplicate
    //   [X] the config event still carries the raw arguments
    // Absence claim via vm.recordLogs
    function test_whenAddIsAlreadyPresent()
        public
        givenAllowListPoolRig
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address[] memory adds = _singleAddress(allowListedOne);

        vm.recordLogs();
        vm.expectEmit(true, true, true, true, address(config));
        emit ICCIPBridgeConfig.AllowListUpdated(new address[](0), adds);
        vm.prank(admin);
        config.applyAllowListUpdates(new address[](0), adds);

        address[] memory expected = new address[](2);
        expected[0] = allowListedOne;
        expected[1] = allowListedTwo;
        _assertAllowList(expected, "allowlist after the duplicate addition");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(
            _countLogs(logs, address(pool), ICCIPTokenPoolAdmin.AllowListAdd.selector),
            0,
            "the pool should emit no AllowListAdd for a present entry"
        );
    }

    // when a removal is absent from the allowlist
    //   [X] it succeeds without emitting AllowListRemove for it
    // Absence claim via vm.recordLogs
    function test_whenRemoveIsAbsent()
        public
        givenAllowListPoolRig
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address[] memory removes = _singleAddress(thirdParty);

        vm.recordLogs();
        vm.prank(admin);
        config.applyAllowListUpdates(removes, new address[](0));

        address[] memory expected = new address[](2);
        expected[0] = allowListedOne;
        expected[1] = allowListedTwo;
        _assertAllowList(expected, "allowlist after the absent removal");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(
            _countLogs(logs, address(pool), ICCIPTokenPoolAdmin.AllowListRemove.selector),
            0,
            "the pool should emit no AllowListRemove for an absent entry"
        );
    }

    // when the same address appears in the removals and the additions
    //   [X] the address is a member afterwards
    //   [X] the pool emits AllowListRemove and then AllowListAdd for it
    // The pool runs the removals before the additions
    function test_whenSameAddressInRemovesAndAdds()
        public
        givenAllowListPoolRig
        givenEnabled
        givenPoolOwnershipAccepted
    {
        address[] memory removes = _singleAddress(allowListedOne);
        address[] memory adds = _singleAddress(allowListedOne);

        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.AllowListRemove(allowListedOne);
        vm.expectEmit(true, true, true, true, address(pool));
        emit ICCIPTokenPoolAdmin.AllowListAdd(allowListedOne);
        vm.prank(admin);
        config.applyAllowListUpdates(removes, adds);

        // Removed first and re-added afterwards, so the entry lands at the end of the set
        address[] memory expected = new address[](2);
        expected[0] = allowListedTwo;
        expected[1] = allowListedOne;
        _assertAllowList(expected, "allowlist after the remove-and-add pair");
    }

    // given the policy is disabled
    //   [X] validateApplyAllowListUpdates returns for a valid input
    // On the allowlist rig; on the primary rig the mirror repeats AllowListNotEnabled
    function test_validateApplyAllowListUpdates_givenDisabled()
        public
        givenAllowListPoolRig
        givenEnabled
        givenPoolOwnershipAccepted
        givenDisabled
    {
        assertFalse(config.isEnabled(), "the policy should be disabled");

        config.validateApplyAllowListUpdates(new address[](0), _singleAddress(thirdParty));
    }

    // when the mirror caller is any address
    //   [X] validateApplyAllowListUpdates returns for a valid input
    function test_validateApplyAllowListUpdates_whenCallerIsAnyAddress(
        address caller_
    ) public givenAllowListPoolRig givenEnabled givenPoolOwnershipAccepted {
        address[] memory adds = _singleAddress(thirdParty);

        vm.prank(caller_);
        config.validateApplyAllowListUpdates(new address[](0), adds);
    }

    // given the pool is owned by an unrelated third party
    //   [X] validateApplyAllowListUpdates returns for a valid input
    // The mirror covers validation only; the action would revert with OnlyCallableByOwner
    function test_validateApplyAllowListUpdates_givenPoolOwnedByThirdParty()
        public
        givenAllowListPoolRig
        givenEnabled
        givenPoolOwnershipAccepted
        givenPoolOwnedByThirdParty
    {
        address[] memory adds = _singleAddress(makeAddr("allowListCandidate"));

        config.validateApplyAllowListUpdates(new address[](0), adds);

        _expectRevertOnlyCallableByOwner();
        vm.prank(admin);
        config.applyAllowListUpdates(new address[](0), adds);
    }
}
