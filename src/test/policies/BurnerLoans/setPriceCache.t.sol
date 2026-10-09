// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {Kernel} from "src/Kernel.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansSetPriceCacheTest is BurnerLoansTest {
    event PriceCacheSet(address indexed priceCache);

    // when caller is not admin
    //  then the call reverts
    function test_whenCallerIsNotAdmin_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        MockPriceCache candidate = new MockPriceCache(address(kernel));

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        burnerLoans.setPriceCache(address(candidate));

        assertEq(burnerLoans.priceCache(), address(0), "price cache should remain unchanged");
    }

    // given the Burner Loans policy is disabled
    //  when caller is not admin
    //   then the call reverts
    function test_givenPolicyIsDisabled_whenCallerIsNotAdmin_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        MockPriceCache candidate = new MockPriceCache(address(kernel));
        vm.prank(admin);
        burnerLoans.disable("");

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        burnerLoans.setPriceCache(address(candidate));

        assertEq(burnerLoans.priceCache(), address(0), "price cache should remain unchanged");
    }

    // given the Burner Loans policy is enabled
    //  when admin sets valid cache
    //   then it updates the dependency
    function test_givenPolicyIsEnabled_whenAdminSetsValidCache_updatesDependency() public {
        MockPriceCache candidate = new MockPriceCache(address(kernel));

        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit PriceCacheSet(address(candidate));
        vm.prank(admin);
        burnerLoans.setPriceCache(address(candidate));

        assertEq(burnerLoans.priceCache(), address(candidate), "price cache getter");
        assertEq(
            address(burnerLoans.context().priceCache),
            address(candidate),
            "context price cache"
        );
    }

    // given the Burner Loans policy is disabled
    //  when admin sets valid cache
    //   then it updates the dependency
    function test_givenPolicyIsDisabled_whenAdminSetsValidCache_updatesDependency() public {
        MockPriceCache candidate = new MockPriceCache(address(kernel));
        vm.startPrank(admin);
        burnerLoans.disable("");

        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit PriceCacheSet(address(candidate));
        burnerLoans.setPriceCache(address(candidate));
        vm.stopPrank();

        assertFalse(burnerLoans.isEnabled(), "Burner Loans should remain disabled");
        assertEq(burnerLoans.priceCache(), address(candidate), "price cache getter");
    }

    // given a cache dependency is configured
    //  when admin rotates cache
    //   then it updates the dependency
    function test_givenCacheConfigured_whenAdminRotatesCache_updatesDependency() public {
        MockPriceCache initial = new MockPriceCache(address(kernel));
        MockPriceCache replacement = new MockPriceCache(address(kernel));
        vm.startPrank(admin);
        burnerLoans.setPriceCache(address(initial));
        burnerLoans.setPriceCache(address(replacement));
        vm.stopPrank();

        assertEq(burnerLoans.priceCache(), address(replacement), "rotated price cache");
    }

    // given the Burner Loans policy is disabled
    //  given a cache dependency is configured
    //   when admin rotates cache
    //    then it updates the dependency
    function test_givenPolicyIsDisabled_givenCacheConfigured_whenAdminRotatesCache_updatesDependency()
        public
    {
        MockPriceCache initial = new MockPriceCache(address(kernel));
        MockPriceCache replacement = new MockPriceCache(address(kernel));
        vm.startPrank(admin);
        burnerLoans.setPriceCache(address(initial));
        burnerLoans.disable("");
        burnerLoans.setPriceCache(address(replacement));
        vm.stopPrank();

        assertFalse(burnerLoans.isEnabled(), "Burner Loans should remain disabled");
        assertEq(burnerLoans.priceCache(), address(replacement), "rotated price cache");
    }

    // given a cache dependency is configured
    //  when admin clears cache
    //   then it selects direct PRICE mode
    function test_givenCacheConfigured_whenAdminClearsCache_selectsDirectPriceMode() public {
        MockPriceCache candidate = new MockPriceCache(address(kernel));
        vm.startPrank(admin);
        burnerLoans.setPriceCache(address(candidate));

        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit PriceCacheSet(address(0));
        burnerLoans.setPriceCache(address(0));
        vm.stopPrank();

        assertEq(burnerLoans.priceCache(), address(0), "price cache should be cleared");
        assertEq(
            address(burnerLoans.context().priceCache),
            address(0),
            "context price cache should be cleared"
        );
    }

    // given the Burner Loans policy is disabled
    //  given a cache dependency is configured
    //   when admin clears cache
    //    then it selects direct PRICE mode
    function test_givenPolicyIsDisabled_givenCacheConfigured_whenAdminClearsCache_selectsDirectPriceMode()
        public
    {
        MockPriceCache candidate = new MockPriceCache(address(kernel));
        vm.startPrank(admin);
        burnerLoans.setPriceCache(address(candidate));
        burnerLoans.disable("");
        burnerLoans.setPriceCache(address(0));
        vm.stopPrank();

        assertFalse(burnerLoans.isEnabled(), "Burner Loans should remain disabled");
        assertEq(burnerLoans.priceCache(), address(0), "price cache should be cleared");
    }

    // when candidate is not a contract
    //  then it reverts and preserves the dependency
    function test_whenCandidateIsNotAContract_revertsAndPreservesDependency() public {
        address candidate = makeAddr("priceCache");

        _expectInvalidCandidatePreservesDependency(
            candidate,
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidPriceCache.selector, candidate)
        );
    }

    // when candidate does not support PriceCache
    //  then it reverts and preserves the dependency
    function test_whenCandidateDoesNotSupportPriceCache_revertsAndPreservesDependency() public {
        MockPriceCache candidate = new MockPriceCache(address(kernel));
        candidate.setInterfaceSupport(type(IPriceCache).interfaceId, false);

        _expectInvalidCandidatePreservesDependency(
            address(candidate),
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidPriceCache.selector,
                address(candidate)
            )
        );
    }

    // when candidate does not support versioned
    //  then it reverts and preserves the dependency
    function test_whenCandidateDoesNotSupportVersioned_revertsAndPreservesDependency() public {
        MockPriceCache candidate = new MockPriceCache(address(kernel));
        candidate.setInterfaceSupport(type(IVersioned).interfaceId, false);

        _expectInvalidCandidatePreservesDependency(
            address(candidate),
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidPriceCache.selector,
                address(candidate)
            )
        );
    }

    // when candidate does not support enabler
    //  then it reverts and preserves the dependency
    function test_whenCandidateDoesNotSupportEnabler_revertsAndPreservesDependency() public {
        MockPriceCache candidate = new MockPriceCache(address(kernel));
        candidate.setInterfaceSupport(type(IEnabler).interfaceId, false);

        _expectInvalidCandidatePreservesDependency(
            address(candidate),
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidPriceCache.selector,
                address(candidate)
            )
        );
    }

    // when candidate belongs to another kernel
    //  then it reverts and preserves the dependency
    function test_whenCandidateBelongsToAnotherKernel_revertsAndPreservesDependency() public {
        Kernel otherKernel = new Kernel();
        MockPriceCache candidate = new MockPriceCache(address(otherKernel));

        _expectInvalidCandidatePreservesDependency(
            address(candidate),
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_PriceCacheKernelMismatch.selector,
                address(kernel),
                address(otherKernel)
            )
        );
    }

    // when candidate major version is unsupported
    //  then it reverts and preserves the dependency
    function test_whenCandidateMajorVersionIsUnsupported_revertsAndPreservesDependency() public {
        MockPriceCache candidate = new MockPriceCache(address(kernel));
        candidate.setVersion(0, type(uint8).max);

        _expectInvalidCandidatePreservesDependency(
            address(candidate),
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_UnsupportedPriceCacheVersion.selector,
                address(candidate),
                0,
                type(uint8).max
            )
        );
    }

    // when candidate major version is too high
    //  then it reverts and preserves the dependency
    function test_whenCandidateMajorVersionIsTooHigh_revertsAndPreservesDependency() public {
        MockPriceCache candidate = new MockPriceCache(address(kernel));
        candidate.setVersion(2, type(uint8).max);

        _expectInvalidCandidatePreservesDependency(
            address(candidate),
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_UnsupportedPriceCacheVersion.selector,
                address(candidate),
                2,
                type(uint8).max
            )
        );
    }

    // when candidate version is 1.x maximum minor
    //  then it accepts the candidate
    function test_whenCandidateVersionIsOneMaximumMinor_acceptsCandidate() public {
        MockPriceCache candidate = new MockPriceCache(address(kernel));
        candidate.setVersion(1, type(uint8).max);

        vm.prank(admin);
        burnerLoans.setPriceCache(address(candidate));

        assertEq(burnerLoans.priceCache(), address(candidate), "price cache getter");
    }

    // when candidate is inactive
    //  then it accepts the candidate
    function test_whenCandidateIsInactive_acceptsCandidate() public {
        vm.prank(admin);
        PriceCache candidate = _deployPriceCache(false, false);

        vm.prank(admin);
        burnerLoans.setPriceCache(address(candidate));

        assertEq(burnerLoans.priceCache(), address(candidate), "inactive price cache");
    }

    // when candidate is active and disabled
    //  then it accepts the candidate
    function test_whenCandidateIsActiveAndDisabled_acceptsCandidate() public {
        vm.startPrank(admin);
        PriceCache candidate = _deployPriceCache(true, false);
        burnerLoans.setPriceCache(address(candidate));
        vm.stopPrank();

        assertTrue(kernel.isPolicyActive(candidate), "price cache should be active");
        assertFalse(candidate.isEnabled(), "price cache should be disabled");
        assertEq(burnerLoans.priceCache(), address(candidate), "disabled price cache");
    }

    // when candidate is active and enabled
    //  then it accepts the candidate
    function test_whenCandidateIsActiveAndEnabled_acceptsCandidate() public {
        vm.startPrank(admin);
        PriceCache candidate = _deployPriceCache(true, true);
        burnerLoans.setPriceCache(address(candidate));
        vm.stopPrank();

        assertTrue(kernel.isPolicyActive(candidate), "price cache should be active");
        assertTrue(candidate.isEnabled(), "price cache should be enabled");
        assertEq(burnerLoans.priceCache(), address(candidate), "enabled price cache");
    }

    function _expectInvalidCandidatePreservesDependency(
        address candidate_,
        bytes memory revertData_
    ) internal {
        MockPriceCache initial = new MockPriceCache(address(kernel));
        vm.startPrank(admin);
        burnerLoans.setPriceCache(address(initial));

        vm.expectRevert(revertData_);
        burnerLoans.setPriceCache(candidate_);
        vm.stopPrank();

        assertEq(burnerLoans.priceCache(), address(initial), "price cache should be preserved");
    }
}
