// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

// Contracts
import {YieldRepurchaseFacilityV2TestBase} from "src/test/policies/YieldRepurchaseFacility/YieldRepurchaseFacility/YieldRepurchaseFacilityV2TestBase.sol";

/// @notice Coverage of the facility's own max price premium setter, its validation view,
///         and the premium carried by the `enable` payload.
/// @dev The queue path through the config timelock is covered by
///      `YieldRepurchaseFacilityConfigTimelock_QueueSetMaxPricePremium.t.sol`.
contract YieldRepurchaseFacilityV2Tests_SetMaxPricePremium is YieldRepurchaseFacilityV2TestBase {
    /// @notice The inclusive upper bound of the premium (1,000%, 18 decimals).
    uint256 internal constant MAX_PRICE_PREMIUM_LIMIT = 10e18;

    function setUp() public {
        _deployStack();
    }

    // ========== setMaxPricePremium ========== //

    // setMaxPricePremium
    // given the caller is neither the config timelock nor the admin
    //  when setting the premium
    //   then it reverts with NotAuthorised
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != guardian && caller_ != address(configTimelock));

        vm.prank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        yieldRepo.setMaxPricePremium(1e16);
    }

    // setMaxPricePremium
    // given the caller holds only the yrf_admin role
    //  when setting the premium
    //   then it reverts (yrf_admin must go through the config timelock queue)
    function test_givenYrfAdminCaller_reverts() public {
        vm.prank(yrfAdmin);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        yieldRepo.setMaxPricePremium(1e16);
    }

    // setMaxPricePremium
    // given the caller holds the admin role
    //  when setting a premium at or below the upper bound
    //   then the premium is stored and MaxPricePremiumSet is emitted
    function test_givenAdminCaller_whenPremiumIsValid_setsPremium(uint256 premium_) public {
        premium_ = bound(premium_, 0, MAX_PRICE_PREMIUM_LIMIT);

        vm.expectEmit(false, false, false, true, address(yieldRepo));
        emit IYieldRepurchaseFacilityV2.MaxPricePremiumSet(premium_);
        vm.prank(guardian);
        yieldRepo.setMaxPricePremium(premium_);

        assertEq(yieldRepo.maxPricePremium(), premium_, "premium applied");
    }

    // setMaxPricePremium
    // given the caller is the config timelock
    //  when setting the premium
    //   then the premium is stored
    function test_givenTimelockCaller_setsPremium() public {
        vm.prank(address(configTimelock));
        yieldRepo.setMaxPricePremium(2e16);

        assertEq(yieldRepo.maxPricePremium(), 2e16, "premium applied");
    }

    // setMaxPricePremium
    // given the premium is exactly the upper bound
    //  when setting the premium
    //   then it is accepted (the bound is inclusive)
    function test_whenPremiumAtUpperBound_setsPremium() public {
        vm.prank(guardian);
        yieldRepo.setMaxPricePremium(MAX_PRICE_PREMIUM_LIMIT);

        assertEq(yieldRepo.maxPricePremium(), MAX_PRICE_PREMIUM_LIMIT, "premium applied");
    }

    // setMaxPricePremium
    // given the premium is one above the upper bound
    //  when setting the premium
    //   then it reverts with IYieldRepurchaseFacilityV2_MaxPricePremiumTooHigh
    function test_whenPremiumOneAboveUpperBound_reverts() public {
        vm.prank(guardian);
        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_MaxPricePremiumTooHigh.selector
        );
        yieldRepo.setMaxPricePremium(MAX_PRICE_PREMIUM_LIMIT + 1);
    }

    // setMaxPricePremium
    // given the premium is above the upper bound, up to the uint256 maximum
    //  when setting the premium
    //   then it reverts with IYieldRepurchaseFacilityV2_MaxPricePremiumTooHigh
    function test_whenPremiumAboveUpperBound_reverts(uint256 premium_) public {
        premium_ = bound(premium_, MAX_PRICE_PREMIUM_LIMIT + 1, type(uint256).max);

        vm.prank(guardian);
        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_MaxPricePremiumTooHigh.selector
        );
        yieldRepo.setMaxPricePremium(premium_);
    }

    // setMaxPricePremium
    // given the facility is disabled
    //  when setting the premium
    //   then it is accepted (the setter is intentionally callable while disabled)
    function test_givenFacilityDisabled_setsPremium() public {
        assertFalse(yieldRepo.isEnabled(), "facility starts disabled");

        vm.prank(guardian);
        yieldRepo.setMaxPricePremium(4e16);

        assertEq(yieldRepo.maxPricePremium(), 4e16, "premium applied");
    }

    // setMaxPricePremium
    // given the facility is enabled
    //  when setting the premium
    //   then the premium replaces the value seeded by the enable payload
    function test_givenFacilityEnabled_setsPremium() public {
        _enableFacility();
        assertEq(yieldRepo.maxPricePremium(), maxPricePremium, "seeded premium");

        vm.prank(guardian);
        yieldRepo.setMaxPricePremium(5e16);

        assertEq(yieldRepo.maxPricePremium(), 5e16, "premium applied");
    }

    // ========== validateSetMaxPricePremium ========== //

    // validateSetMaxPricePremium
    // given any premium at or below the upper bound
    //  when validating the premium
    //   then it does not revert, matching the setter
    function test_validate_whenPremiumIsValid_doesNotRevert(uint256 premium_) public {
        premium_ = bound(premium_, 0, MAX_PRICE_PREMIUM_LIMIT);

        yieldRepo.validateSetMaxPricePremium(premium_);

        // The setter agrees with the validation view.
        vm.prank(guardian);
        yieldRepo.setMaxPricePremium(premium_);
        assertEq(yieldRepo.maxPricePremium(), premium_, "premium applied");
    }

    // validateSetMaxPricePremium
    // given any premium above the upper bound
    //  when validating the premium
    //   then it reverts with the same error as the setter
    function test_validate_whenPremiumAboveUpperBound_reverts(uint256 premium_) public {
        premium_ = bound(premium_, MAX_PRICE_PREMIUM_LIMIT + 1, type(uint256).max);

        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_MaxPricePremiumTooHigh.selector
        );
        yieldRepo.validateSetMaxPricePremium(premium_);
    }

    // ========== enable payload ========== //

    // enable
    // given an enable payload carrying a premium at or below the upper bound
    //  when the facility is enabled
    //   then the premium is seeded from the payload
    function test_enable_whenPremiumIsValid_seedsPremium(uint256 premium_) public {
        premium_ = bound(premium_, 0, MAX_PRICE_PREMIUM_LIMIT);

        vm.prank(guardian);
        yieldRepo.enable(
            abi.encode(initialDiscount, premium_, new IYieldRepurchaseFacilityV2.NextYieldSeed[](0))
        );

        assertEq(yieldRepo.maxPricePremium(), premium_, "premium seeded");
    }

    // enable
    // given an enable payload carrying a premium above the upper bound
    //  when the facility is enabled
    //   then it reverts with IYieldRepurchaseFacilityV2_MaxPricePremiumTooHigh
    function test_enable_whenPremiumAboveUpperBound_reverts() public {
        vm.prank(guardian);
        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_MaxPricePremiumTooHigh.selector
        );
        yieldRepo.enable(
            abi.encode(
                initialDiscount,
                MAX_PRICE_PREMIUM_LIMIT + 1,
                new IYieldRepurchaseFacilityV2.NextYieldSeed[](0)
            )
        );
    }

    // enable
    // given a legacy two-parameter payload (`abi.encode(uint256, NextYieldSeed[])`), 96 bytes
    //  when the facility is enabled
    //   then it reverts with IYieldRepurchaseFacilityV2_InvalidEnableDataLength
    function test_enable_whenPayloadIsShorterThanMinimum_reverts() public {
        bytes memory legacyPayload = abi.encode(
            initialDiscount,
            new IYieldRepurchaseFacilityV2.NextYieldSeed[](0)
        );
        assertEq(legacyPayload.length, 96, "legacy payload length");

        vm.prank(guardian);
        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_InvalidEnableDataLength.selector
        );
        yieldRepo.enable(legacyPayload);
    }

    // enable
    // given a payload of exactly the minimum length (128 bytes)
    //  when the facility is enabled
    //   then the discount and the premium are both seeded
    function test_enable_whenPayloadIsExactlyMinimumLength_seedsPremium() public {
        bytes memory payload = abi.encode(
            initialDiscount,
            maxPricePremium,
            new IYieldRepurchaseFacilityV2.NextYieldSeed[](0)
        );
        assertEq(payload.length, 128, "payload length");

        vm.prank(guardian);
        yieldRepo.enable(payload);

        assertEq(yieldRepo.initialDiscount(), initialDiscount, "discount seeded");
        assertEq(yieldRepo.maxPricePremium(), maxPricePremium, "premium seeded");
    }
}
