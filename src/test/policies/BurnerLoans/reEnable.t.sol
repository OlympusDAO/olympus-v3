// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {Actions} from "src/Kernel.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.
// forge-lint: disable-start(unsafe-typecast)

contract BurnerLoansReEnableTest is BurnerLoansTest {
    uint48 internal constant _DISABLED_AT = 1234;

    event Enabled();
    event Transition(address indexed by, bool indexed enable, bytes data, uint48 at);

    // reEnable
    // given caller has neither admin nor burner_loans_admin role
    //  when reEnable is called within the grace period
    //   then it reverts
    function test_givenNonAdminOrBurnerLoansAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        vm.assume(caller_ != address(burnerLoans));

        vm.prank(emergency);
        burnerLoans.disable("");

        vm.prank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        burnerLoans.reEnable();
    }

    // reEnable
    // given the policy is already enabled
    //  when reEnable is called by burner_loans_admin
    //   then it reverts
    function test_givenAlreadyEnabled_reverts() public {
        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        burnerLoans.reEnable();
    }

    // reEnable
    // given the policy re-enable grace period has elapsed
    //  when reEnable is called by burner_loans_admin
    //   then it reverts
    function test_givenGracePeriodElapsed_reverts(
        uint32 gracePeriod_,
        uint48 elapsedAfterDeadline_
    ) public {
        uint32 gracePeriod = uint32(bound(gracePeriod_, 1, type(uint32).max));
        uint48 elapsedAfterDeadline = uint48(bound(elapsedAfterDeadline_, 1, 365 days));

        vm.prank(admin);
        burnerLoans.setGracePeriod(uint32(gracePeriod));

        vm.warp(_DISABLED_AT);
        vm.prank(emergency);
        burnerLoans.disable("");

        uint48 deadline = uint48(_DISABLED_AT + uint48(gracePeriod));
        vm.warp(uint256(deadline) + elapsedAfterDeadline);

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        burnerLoans.reEnable();
    }

    // reEnable
    // given caller has burner_loans_admin role and the grace period is active
    //  when reEnable is called
    //   then the policy is re-enabled
    function test_givenBurnerLoansAdminCallerWithinGracePeriod_reenablesPolicy() public {
        vm.warp(_DISABLED_AT);
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.warp(_DISABLED_AT + BurnerLoansConstants.REENABLE_GRACE_PERIOD);
        vm.prank(burnerLoansAdmin);
        vm.expectEmit(address(burnerLoans));
        emit Enabled();
        vm.expectEmit(true, true, false, true, address(burnerLoans));
        emit Transition(burnerLoansAdmin, true, "", uint48(block.timestamp));
        burnerLoans.reEnable();

        assertTrue(burnerLoans.isEnabled(), "enabled");
        assertEq(burnerLoans.lastTransitionAt(), uint48(block.timestamp), "last transition");
    }

    // reEnable
    // given caller has burner_loans_admin role and a fuzzed timestamp within the grace period
    //  when reEnable is called
    //   then the policy is re-enabled
    function test_givenBurnerLoansAdminCallerWithinGracePeriod_reenablesPolicy(
        uint48 disabledAt_,
        uint32 elapsed_
    ) public {
        uint48 disabledAt = uint48(
            bound(
                disabledAt_,
                1,
                uint256(type(uint48).max) - BurnerLoansConstants.REENABLE_GRACE_PERIOD
            )
        );
        uint32 elapsed = uint32(bound(elapsed_, 0, BurnerLoansConstants.REENABLE_GRACE_PERIOD));

        vm.warp(disabledAt);
        vm.prank(emergency);
        burnerLoans.disable("");

        assertFalse(burnerLoans.isEnabled(), "disabled");
        assertEq(burnerLoans.lastTransitionAt(), disabledAt, "disabled at");

        vm.warp(uint256(disabledAt) + elapsed);
        vm.prank(burnerLoansAdmin);
        vm.expectEmit(address(burnerLoans));
        emit Enabled();
        vm.expectEmit(true, true, false, true, address(burnerLoans));
        emit Transition(burnerLoansAdmin, true, "", uint48(block.timestamp));
        burnerLoans.reEnable();

        assertTrue(burnerLoans.isEnabled(), "enabled");
        assertEq(burnerLoans.lastTransitionAt(), uint48(block.timestamp), "last transition");
    }

    // reEnable
    // given caller has admin role and the configured grace period is active
    //  when reEnable is called
    //   then the policy is re-enabled
    function test_givenAdminCallerWithinConfiguredGracePeriod_reenablesPolicy() public {
        uint32 gracePeriod = 2 days;
        vm.prank(admin);
        burnerLoans.setGracePeriod(gracePeriod);

        vm.warp(_DISABLED_AT);
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.warp(_DISABLED_AT + gracePeriod);
        vm.prank(admin);
        vm.expectEmit(address(burnerLoans));
        emit Enabled();
        vm.expectEmit(true, true, false, true, address(burnerLoans));
        emit Transition(admin, true, "", uint48(block.timestamp));
        burnerLoans.reEnable();

        assertTrue(burnerLoans.isEnabled(), "enabled");
        assertEq(burnerLoans.lastTransitionAt(), uint48(block.timestamp), "last transition");
    }

    // reEnable
    // given the configured Burner Loans Inventory was deactivated after Burner Loans was disabled
    //  when admin re-enables Burner Loans
    //   then it revalidates the pointer and reverts
    function test_givenInventoryIsNoLongerActive_reverts() public {
        vm.startPrank(admin);
        burnerLoans.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(inventory));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InventoryNotActive.selector,
                address(inventory)
            )
        );
        burnerLoans.reEnable();
        vm.stopPrank();
    }

    function test_givenConfiguratorIsNoLongerActive_reverts() public {
        vm.startPrank(admin);
        burnerLoans.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoansConfig));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility.selector,
                address(burnerLoansConfig)
            )
        );
        burnerLoans.reEnable();
        vm.stopPrank();
    }

    function test_givenDepositManagerIsNoLongerActive_reverts() public {
        vm.startPrank(admin);
        burnerLoans.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoans.reEnable();
        vm.stopPrank();
    }

    // given PriceCache is inactive
    //  when the policy is re-enabled
    //   then the call reverts
    function test_givenPriceCacheIsInactive_reverts() public {
        vm.prank(admin);
        PriceCache candidate = _deployPriceCache(false, false);

        vm.prank(admin);
        burnerLoans.setPriceCache(address(candidate));
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_PriceCacheNotActive.selector,
                address(candidate)
            )
        );
        vm.prank(burnerLoansAdmin);
        burnerLoans.reEnable();

        assertFalse(burnerLoans.isEnabled(), "Burner Loans should remain disabled");
    }

    // given PriceCache is active and disabled
    //  when the policy is re-enabled
    //   then Burner Loans becomes re-enabled
    function test_givenPriceCacheIsActiveAndDisabled_reenables() public {
        vm.startPrank(admin);
        PriceCache candidate = _deployPriceCache(true, false);
        vm.stopPrank();

        _assertReEnableAcceptsPriceCache(candidate);
    }

    // given PriceCache is active and enabled
    //  when the policy is re-enabled
    //   then Burner Loans becomes re-enabled
    function test_givenPriceCacheIsActiveAndEnabled_reenables() public {
        vm.startPrank(admin);
        PriceCache candidate = _deployPriceCache(true, true);
        vm.stopPrank();

        _assertReEnableAcceptsPriceCache(candidate);
    }

    // given the PriceCache Kernel has become incompatible
    //  when the policy is re-enabled
    //   then the call reverts
    function test_givenPriceCacheKernelBecameIncompatible_reverts() public {
        MockPriceCache candidate = new MockPriceCache(address(kernel));
        address otherKernel = makeAddr("otherKernel");
        vm.startPrank(admin);
        burnerLoans.setPriceCache(address(candidate));
        burnerLoans.disable("");
        vm.mockCall(
            address(candidate),
            abi.encodeWithSignature("kernel()"),
            abi.encode(otherKernel)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_PriceCacheKernelMismatch.selector,
                address(kernel),
                otherKernel
            )
        );
        burnerLoans.reEnable();
        vm.stopPrank();

        assertFalse(burnerLoans.isEnabled(), "Burner Loans should remain disabled");
        assertEq(burnerLoans.priceCache(), address(candidate), "price cache should be preserved");
    }

    function _assertReEnableAcceptsPriceCache(PriceCache candidate_) internal {
        vm.prank(admin);
        burnerLoans.setPriceCache(address(candidate_));
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.prank(burnerLoansAdmin);
        burnerLoans.reEnable();

        assertTrue(burnerLoans.isEnabled(), "Burner Loans should be enabled");
        assertEq(burnerLoans.priceCache(), address(candidate_), "price cache getter");
    }
}

// forge-lint: disable-end(unsafe-typecast)
