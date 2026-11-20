// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IPriceCacherTask} from "src/policies/interfaces/IPriceCacherTask.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {MockPriceCacherTaskCache} from "./MockPriceCacherTaskCache.sol";
import {PriceCacherTaskTest} from "./PriceCacherTaskTest.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract PriceCacherTaskSetPriceCacheTest is PriceCacherTaskTest {
    // when caller is not admin
    //  then the call reverts
    // Scenarios: PCACHER-SET-CACHE-A01.
    function test_whenCallerIsNotAdmin_reverts(address caller_) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        cacher.setPriceCache(address(priceCache));
    }

    // given PriceCacherTask is enabled
    //  when admin rotates PriceCache
    //   then the cache dependency is rotated
    // Scenarios: PCACHER-SET-CACHE-P01.
    function test_givenEnabled_whenAdminRotatesPriceCache() public {
        MockPriceCacherTaskCache replacement = _deployActiveCache(kernel);

        vm.expectEmit(true, false, false, true, address(cacher));
        emit IPriceCacherTask.PriceCacheSet(address(replacement));
        vm.prank(admin);
        cacher.setPriceCache(address(replacement));

        assertEq(cacher.priceCache(), address(replacement), "price cache");

        vm.prank(heart);
        cacher.execute();

        assertEq(replacement.callCount(), 2, "replacement cache calls");
        assertEq(priceCache.callCount(), 0, "old cache calls");
    }

    // given PriceCacherTask is disabled
    //  when admin rotates PriceCache
    //   then the cache dependency is rotated
    // Scenarios: PCACHER-SET-CACHE-L01.
    function test_givenDisabled_whenAdminRotatesPriceCache() public {
        MockPriceCacherTaskCache replacement = _deployActiveCache(kernel);
        vm.prank(emergency);
        cacher.disable("");

        _rotationSucceeds(replacement, admin);
    }

    // when candidate is zero
    //  then it reverts and preserves the cache
    // Scenarios: PCACHER-SET-CACHE-I01.
    function test_whenCandidateIsZero_revertsAndPreservesCache() public {
        vm.expectRevert(IPriceCacherTask.PriceCacherTask_ZeroAddress.selector);
        vm.prank(admin);
        cacher.setPriceCache(address(0));

        assertEq(cacher.priceCache(), address(priceCache), "price cache");
    }

    // when candidate uses different kernel
    //  then it reverts and preserves the cache
    // Scenarios: PCACHER-SET-CACHE-D02.
    function test_whenCandidateUsesDifferentKernel_revertsAndPreservesCache() public {
        Kernel otherKernel = new Kernel();
        MockPriceCacherTaskCache candidate = new MockPriceCacherTaskCache(otherKernel);

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(candidate),
                address(kernel),
                address(otherKernel)
            )
        );
        vm.prank(admin);
        cacher.setPriceCache(address(candidate));

        assertEq(cacher.priceCache(), address(priceCache), "price cache");
    }

    // when candidate does not support an existing pair
    //  then it reverts and preserves the cache
    // Scenarios: PCACHER-SET-CACHE-D03.
    function test_whenCandidateDoesNotSupportAnExistingPair_revertsAndPreservesCache() public {
        MockPriceCacherTaskCache candidate = new MockPriceCacherTaskCache(kernel);
        candidate.setUnsupportedPair(ohm, usde);

        vm.expectRevert(
            abi.encodeWithSelector(MockPriceCacherTaskCache.PairUnsupported.selector, ohm, usde)
        );
        vm.prank(admin);
        cacher.setPriceCache(address(candidate));

        assertEq(cacher.priceCache(), address(priceCache), "price cache");
    }

    function _deployActiveCache(Kernel kernel_) internal returns (MockPriceCacherTaskCache cache_) {
        cache_ = new MockPriceCacherTaskCache(kernel_);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(cache_));
        cache_.enable("");
    }

    // Scenarios: PCACHER-SET-CACHE-A02, PCACHER-SET-CACHE-N01, PCACHER-SET-CACHE-P01.
    function test_whenAdminAndCollectionVary_thenExactRotation(
        address caller_,
        uint8 count_
    ) public {
        _grantTestRole(ADMIN_ROLE, caller_);
        _seedPairs(bound(count_, 0, 32));
        MockPriceCacherTaskCache replacement = _deployActiveCache(kernel);
        IPriceCacherTask.AssetPair[] memory pairs = cacher.getAssetPairs();
        for (uint256 i; i < pairs.length; ++i)
            vm.expectCall(
                address(replacement),
                abi.encodeCall(replacement.validateAssetPair, (pairs[i].asset, pairs[i].quote)),
                uint64(1)
            );
        _rotationSucceeds(replacement, caller_);
        vm.prank(heart);
        cacher.execute();
        _assertAttempts(replacement, pairs);
        assertEq(priceCache.callCount(), 0, "retired cache never called");
    }

    // Scenarios: PCACHER-SET-CACHE-N01.
    function test_whenNoPairs_whenRotationSucceeds() public {
        test_whenAdminAndCollectionVary_thenExactRotation(admin, 0);
    }

    // Scenarios: PCACHER-SET-CACHE-N01.
    function test_whenSinglePair_whenRotationSucceeds() public {
        test_whenAdminAndCollectionVary_thenExactRotation(admin, 1);
    }

    // Scenarios: PCACHER-SET-CACHE-N01.
    function test_whenLargerSet_whenRotationSucceeds() public {
        test_whenAdminAndCollectionVary_thenExactRotation(admin, 32);
    }

    // Scenarios: PCACHER-SET-CACHE-L02.
    function test_givenInactive_whenCacheSelected_reverts(bool enabled_) public {
        _setTaskEnabled(enabled_);
        MockPriceCacherTaskCache candidate = new MockPriceCacherTaskCache(kernel);
        _setTaskMembership(false);
        _rejectCandidate(
            address(candidate),
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_PolicyInactive.selector,
                address(cacher)
            )
        );
    }

    // Scenarios: PCACHER-SET-CACHE-I02.
    function test_whenUnchangedCacheSelected_revertsBeforeProbes() public {
        vm.expectCall(address(priceCache), abi.encodeWithSignature("kernel()"), uint64(0));
        _rejectCandidate(
            address(priceCache),
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_UnchangedAddress.selector,
                address(priceCache)
            )
        );
    }

    // Scenarios: PCACHER-SET-CACHE-D04.
    function test_whenCandidateHasNoCode_reverts(address candidate_) public {
        vm.assume(candidate_ != address(0) && candidate_.code.length == 0);
        _rejectCandidate(candidate_, _invalidCache(candidate_));
    }

    // Scenarios: PCACHER-SET-CACHE-D06.
    function test_givenUnreadyCandidate_whenSelected_thenActivationRejects(
        bool active_,
        bool enabled_
    ) public {
        vm.assume(!active_ || !enabled_);
        MockPriceCacherTaskCache candidate = new MockPriceCacherTaskCache(kernel);
        _setCacheState(candidate, active_, enabled_);
        _rotationSucceeds(candidate, admin);
        vm.prank(admin);
        cacher.disable("");
        _expectConfigRejected(
            admin,
            abi.encodeCall(cacher.enable, (bytes(""))),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(candidate)
            )
        );
    }

    // Scenarios: PCACHER-SET-CACHE-D07.
    function test_givenCacheInterfaceMissing_whenSelected_reverts() public {
        _rejectMissingInterface(false, true);
    }

    // Scenarios: PCACHER-SET-CACHE-D08.
    function test_givenEnablerInterfaceMissing_whenSelected_reverts() public {
        _rejectMissingInterface(true, false);
    }

    // Scenarios: PCACHER-SET-CACHE-D11.
    function test_givenKernelGetterReverts_whenSelected_reverts() public {
        MockPriceCacherTaskCache candidate = new MockPriceCacherTaskCache(kernel);
        vm.mockCallRevert(address(candidate), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        _rejectCandidate(
            address(candidate),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(candidate)
            )
        );
    }

    // Scenarios: PCACHER-SET-CACHE-D12.
    function test_givenMalformedKernel_whenSelected_reverts(bytes memory data_) public {
        vm.assume(data_.length <= 256 && data_.length != 32);
        _rejectMetadataReturn(abi.encodeWithSignature("kernel()"), data_);
    }

    // Scenarios: PCACHER-SET-CACHE-D12.
    function test_givenNoncanonicalKernel_whenSelected_reverts(uint256 word_) public {
        word_ = bound(word_, uint256(type(uint160).max) + 1, type(uint256).max);
        _rejectMetadataReturn(abi.encodeWithSignature("kernel()"), abi.encode(word_));
    }

    // Scenarios: PCACHER-SET-CACHE-P02.
    function test_whenAnyCallerReadsCache(address caller_, bool active_, bool enabled_) public {
        _setTaskEnabled(enabled_);
        _setTaskMembership(active_);
        vm.record();
        vm.prank(caller_);
        assertEq(
            cacher.priceCache(),
            address(priceCache),
            "selected cache readable in every lifecycle state"
        );
        (, bytes32[] memory writes) = vm.accesses(address(cacher));
        assertEq(writes.length, 0, "cache getter writes nothing");
    }

    function _rotationSucceeds(MockPriceCacherTaskCache candidate_, address caller_) internal {
        IPriceCacherTask.AssetPair[] memory pairs = cacher.getAssetPairs();
        bool enabled = cacher.isEnabled();
        uint48 transition = cacher.lastTransitionAt();
        uint32 grace = cacher.gracePeriod();
        vm.expectEmit(address(cacher));
        emit IPriceCacherTask.PriceCacheSet(address(candidate_));
        vm.prank(caller_);
        cacher.setPriceCache(address(candidate_));
        assertEq(cacher.priceCache(), address(candidate_), "replacement pointer exact");
        assertEq(cacher.isEnabled(), enabled, "rotation preserves pause state");
        assertEq(cacher.lastTransitionAt(), transition, "rotation preserves transition history");
        assertEq(cacher.gracePeriod(), grace, "rotation preserves grace");
        _assertPairs(pairs);
    }

    function _rejectCandidate(address candidate_, bytes memory reason_) internal {
        _expectConfigRejected(admin, abi.encodeCall(cacher.setPriceCache, (candidate_)), reason_);
    }

    function _rejectMissingInterface(bool cache_, bool enabler_) internal {
        MockPriceCacherTaskCache candidate = new MockPriceCacherTaskCache(kernel);
        candidate.setInterfaceSupport(cache_, enabler_, true);
        _rejectCandidate(address(candidate), _invalidCache(address(candidate)));
    }

    function _rejectMetadataReturn(bytes memory call_, bytes memory data_) internal {
        MockPriceCacherTaskCache candidate = new MockPriceCacherTaskCache(kernel);
        vm.mockCall(address(candidate), call_, data_);
        _rejectCandidate(
            address(candidate),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(candidate)
            )
        );
    }

    // Scenarios: PCACHER-SET-CACHE-D13.
    function test_givenInterfaceProbeReverts_whenSelected_reverts() public {
        MockPriceCacherTaskCache candidate = new MockPriceCacherTaskCache(kernel);
        vm.mockCallRevert(
            address(candidate),
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            hex"deadbeef"
        );
        _rejectCandidate(address(candidate), _invalidCache(address(candidate)));
    }

    // Scenarios: PCACHER-SET-CACHE-D14.
    function test_givenInterfaceProbeMalformed_whenSelected_reverts() public {
        MockPriceCacherTaskCache candidate = new MockPriceCacherTaskCache(kernel);
        vm.mockCall(
            address(candidate),
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            hex"01"
        );
        _rejectCandidate(address(candidate), _invalidCache(address(candidate)));
    }

    // Scenarios: PCACHER-SET-CACHE-D03, PCACHER-SET-CACHE-N01.
    function test_givenLaterPairRejected_whenSelected_thenAtomicRollback(
        uint8 count_,
        uint8 index_
    ) public {
        _seedPairs(bound(count_, 2, 32));
        IPriceCacherTask.AssetPair[] memory pairs = cacher.getAssetPairs();
        uint256 index = bound(index_, 1, pairs.length - 1);
        MockPriceCacherTaskCache candidate = new MockPriceCacherTaskCache(kernel);
        candidate.setUnsupportedPair(pairs[index].asset, pairs[index].quote);
        vm.expectCall(
            address(candidate),
            abi.encodeCall(candidate.validateAssetPair, (pairs[0].asset, pairs[0].quote)),
            uint64(1)
        );
        _rejectCandidate(
            address(candidate),
            abi.encodeWithSelector(
                MockPriceCacherTaskCache.PairUnsupported.selector,
                pairs[index].asset,
                pairs[index].quote
            )
        );
    }

    // Scenarios: PCACHER-SET-CACHE-D12.
    function test_whenMetadataBoundarySeedsUsed_reverts() public {
        test_givenMalformedKernel_whenSelected_reverts("");
        test_givenMalformedKernel_whenSelected_reverts(new bytes(31));
        test_givenMalformedKernel_whenSelected_reverts(new bytes(33));
        test_givenMalformedKernel_whenSelected_reverts(new bytes(256));
        test_givenNoncanonicalKernel_whenSelected_reverts(uint256(type(uint160).max) + 1);
        test_givenNoncanonicalKernel_whenSelected_reverts(type(uint256).max);
    }

    // Scenarios: PCACHER-SET-CACHE-D09.
    function test_givenNoVersionInterface_whenSelected_thenAccepted() public {
        MockPriceCacherTaskCache candidate = new MockPriceCacherTaskCache(kernel);
        candidate.setInterfaceSupport(true, true, false);
        _forbidCacheVersionReads(candidate);
        _rotationSucceeds(candidate, admin);
    }

    // Scenarios: PCACHER-SET-CACHE-D05.
    function test_givenVersionGetterReverts_whenSelected_thenIgnored() public {
        MockPriceCacherTaskCache candidate = new MockPriceCacherTaskCache(kernel);
        _forbidCacheVersionReads(candidate);
        _rotationSucceeds(candidate, admin);
    }

    // Scenarios: PCACHER-SET-CACHE-L03.
    function test_givenInactiveAndDisabled_whenUnauthorizedCaller_revertsActivityFirst(
        address caller_
    ) public {
        _setTaskEnabled(false);
        _setTaskMembership(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_PolicyInactive.selector,
                address(cacher)
            )
        );
        vm.prank(caller_);
        cacher.setPriceCache(address(0));
    }
}
