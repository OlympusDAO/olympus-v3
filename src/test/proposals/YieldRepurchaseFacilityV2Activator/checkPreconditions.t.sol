// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IGenericClearinghouse} from "src/policies/interfaces/IGenericClearinghouse.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2View} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2View.sol";
import {IYieldRepurchaseFacilityV2Activator} from "src/proposals/interfaces/IYieldRepurchaseFacilityV2Activator.sol";

// Mocks
import {MockClearinghouse} from "src/test/mocks/MockClearinghouse.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {ModuleWithSubmodules} from "src/Submodules.sol";
import {YieldRepurchaseFacilityV2ActivatorTest} from "./YieldRepurchaseFacilityV2ActivatorTest.sol";

/// @notice `checkPreconditions`: one test per precondition of the launch on the state that
///         leaves exactly that precondition unmet, and the states the check accepts.
contract YieldRepurchaseFacilityV2ActivatorTests_checkPreconditions is
    YieldRepurchaseFacilityV2ActivatorTest
{
    /// @notice The number of policies of the stack.
    uint256 internal constant STACK_POLICY_COUNT = 5;

    /// @notice The number of bindings the check compares: the Kernel of eight policies and
    ///         eight bindings between the bound contracts.
    uint256 internal constant BINDING_COUNT = 16;

    // ========== HELPERS ========== //

    /// @notice Returns the policy of the stack at `index_`, in the order the check walks them.
    function _stackPolicy(uint256 index_) internal view returns (address policy) {
        if (index_ == 0) return address(backingOracle);
        if (index_ == 1) return address(backingOracleConfigTimelock);
        if (index_ == 2) return address(config);
        if (index_ == 3) return address(configTimelock);
        return address(facility);
    }

    /// @notice Returns the binding at `index_` in the order the check compares them: the
    ///         contract that reports it, the call that reads it, the answer that reports
    ///         `other_` in its place, the name of the binding and the bound value.
    function _binding(
        uint256 index_,
        address other_
    )
        internal
        view
        returns (
            address reporter,
            bytes memory call_,
            bytes memory answer,
            string memory binding,
            address bound_
        )
    {
        answer = abi.encode(other_);
        if (index_ < KERNEL_BOUND_COUNT) {
            (reporter, binding) = _kernelBound(index_);
            return (
                reporter,
                abi.encodeWithSignature("kernel()"),
                answer,
                binding,
                address(kernel)
            );
        }
        if (index_ == 8)
            return (
                address(backingOracleConfigTimelock),
                abi.encodeWithSignature("backingOracle()"),
                answer,
                "BackingOracleConfigTimelock backingOracle",
                address(backingOracle)
            );
        if (index_ == 9)
            return (
                address(configTimelock),
                abi.encodeWithSignature("config()"),
                answer,
                "YieldRepurchaseFacilityV2ConfigTimelock config",
                address(config)
            );
        if (index_ == 10)
            return (
                address(facility),
                abi.encodeWithSignature("backingOracle()"),
                answer,
                "YieldRepurchaseFacilityV2 backingOracle",
                address(backingOracle)
            );
        if (index_ == 11)
            return (
                address(facility),
                abi.encodeWithSignature("bondAuctioneer()"),
                answer,
                "YieldRepurchaseFacilityV2 bondAuctioneer",
                address(bondAuctioneer)
            );
        if (index_ == 12) {
            // The facility reports OHM as a member of its context
            IYieldRepurchaseFacilityV2.Context memory context = facility.context();
            context.ohm = other_;
            return (
                address(facility),
                abi.encodeWithSignature("context()"),
                abi.encode(context),
                "YieldRepurchaseFacilityV2 OHM",
                address(ohm)
            );
        }
        if (index_ == 13)
            return (
                address(yieldRepoV1),
                abi.encodeWithSignature("sReserve()"),
                answer,
                "YieldRepurchaseFacility v1.2 sReserve",
                address(sUsds)
            );
        if (index_ == 14)
            return (
                address(sUsds),
                abi.encodeWithSignature("asset()"),
                answer,
                "sUSDS asset",
                address(usds)
            );
        return (
            address(sUsde),
            abi.encodeWithSignature("asset()"),
            answer,
            "sUSDe asset",
            address(usde)
        );
    }

    function _expectRevertUsdeFeedNotReadable(bytes memory reason_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_UsdeFeedNotReadable
                    .selector,
                address(usdeUsdFeed),
                reason_
            )
        );
    }

    function _expectRevertUsdePriceOutOfBounds(uint256 price_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_UsdePriceOutOfBounds
                    .selector,
                price_,
                1e18,
                uint16(100)
            )
        );
    }

    // ========== ERROR CONDITIONS ========== //

    // given the launch has completed
    //   [X] it reverts with AlreadyActivated

    function test_givenActivated_reverts() public {
        _activate(SUSDE_NEXT_YIELD);

        vm.expectRevert(
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_AlreadyActivated
                .selector
        );
        activator.checkPreconditions();
    }

    // given the admin has pointed the facility at another auctioneer since the deployment
    //   [X] it reverts with BindingMismatch naming the auctioneer of the facility

    function test_givenFacilityAuctioneerChanged_reverts() public {
        address otherAuctioneer = address(_deployAuctioneer("otherAuctioneer"));
        vm.prank(ocgTimelock);
        facility.setBondContracts(otherAuctioneer);

        _expectRevertBindingMismatch(
            "YieldRepurchaseFacilityV2 bondAuctioneer",
            otherAuctioneer,
            address(bondAuctioneer)
        );
        activator.checkPreconditions();
    }

    // given a bound contract reports another binding than the one the constructor checked
    //   [X] it reverts with BindingMismatch naming the binding, the reported and the bound value

    function test_givenBindingChanged_reverts() public {
        address other = makeAddr("otherBinding");
        // Every binding the check compares, one at a time
        for (uint256 i = 0; i < BINDING_COUNT; ++i) {
            (
                address reporter,
                bytes memory call_,
                bytes memory answer,
                string memory binding,
                address bound_
            ) = _binding(i, other);
            vm.mockCall(reporter, call_, answer);

            _expectRevertBindingMismatch(binding, other, bound_);
            activator.checkPreconditions();

            vm.clearMockedCalls();
        }
    }

    // given a policy of the stack is not active in the Kernel
    //   [X] it reverts with PolicyNotActive naming the policy

    function test_givenStackPolicyNotActive_reverts() public {
        // Every policy of the stack, each on the state that leaves the others active
        for (uint256 i = 0; i < STACK_POLICY_COUNT; ++i) {
            address policy = _stackPolicy(i);
            uint256 snapshot = vm.snapshotState();
            kernel.executeAction(Actions.DeactivatePolicy, policy);

            _expectRevertPolicyNotActive(policy);
            activator.checkPreconditions();

            assertTrue(vm.revertToState(snapshot), "rig: the state should be restored");
        }
    }

    // given a policy of the stack reports that it is enabled
    //   [X] it reverts with PolicyAlreadyEnabled naming the policy

    function test_givenStackPolicyEnabled_reverts() public {
        // Every policy of the stack, one at a time
        for (uint256 i = 0; i < STACK_POLICY_COUNT; ++i) {
            address policy = _stackPolicy(i);
            vm.mockCall(
                policy,
                abi.encodeWithSelector(IEnabler.isEnabled.selector),
                abi.encode(true)
            );

            _expectRevertPolicyAlreadyEnabled(policy);
            activator.checkPreconditions();

            vm.clearMockedCalls();
        }
    }

    // given a policy of the stack is disabled but reports an earlier transition
    //   [X] it reverts with PolicyAlreadyEnabled naming the policy

    function test_givenStackPolicyHasTransitioned_reverts(uint48 at_) public {
        // Any non-zero transition timestamp: [1, type(uint48).max]
        uint48 transitionAt = uint48(bound(at_, 1, type(uint48).max));
        // Every policy of the stack, one at a time
        for (uint256 i = 0; i < STACK_POLICY_COUNT; ++i) {
            address policy = _stackPolicy(i);
            vm.mockCall(
                policy,
                abi.encodeWithSelector(IEnablerV2.lastTransitionAt.selector),
                abi.encode(transitionAt)
            );

            _expectRevertPolicyAlreadyEnabled(policy);
            activator.checkPreconditions();

            vm.clearMockedCalls();
        }
    }

    // given the admin has enabled the oracle and the Emergency MS has disabled it again
    //   [X] it reverts with PolicyAlreadyEnabled naming the oracle

    function test_givenOracleEnabledAndDisabled_reverts() public {
        vm.prank(ocgTimelock);
        backingOracle.enable(abi.encode(BACKING));
        vm.prank(emergencyMS);
        backingOracle.disable("");
        assertFalse(backingOracle.isEnabled(), "the oracle should be disabled again");

        _expectRevertPolicyAlreadyEnabled(address(backingOracle));
        activator.checkPreconditions();
    }

    // given the configuration policy is bound to the facility
    //   [X] it reverts with AlreadyBound naming the binding and the facility

    function test_givenConfigBoundToFacility_reverts() public {
        vm.prank(ocgTimelock);
        config.setFacility(address(facility));

        _expectRevertAlreadyBound("YieldRepurchaseFacilityV2Config facility", address(facility));
        activator.checkPreconditions();
    }

    // given the facility names a configurator
    //   [X] it reverts with AlreadyBound naming the binding and the configurator

    function test_givenFacilityNamesConfigurator_reverts() public {
        // The facility accepts a configurator only once the configuration policy names the
        // facility, which the check reads first, so the configurator is mocked on its own
        vm.mockCall(
            address(facility),
            abi.encodeWithSelector(IYieldRepurchaseFacilityV2View.configurator.selector),
            abi.encode(address(config))
        );

        _expectRevertAlreadyBound("YieldRepurchaseFacilityV2 configurator", address(config));
        activator.checkPreconditions();
    }

    // given the configuration policy names a config operator
    //   [X] it reverts with AlreadyBound naming the binding and the operator

    function test_givenConfigNamesConfigOperator_reverts() public {
        vm.prank(ocgTimelock);
        config.setConfigOperator(address(configTimelock));

        _expectRevertAlreadyBound(
            "YieldRepurchaseFacilityV2Config configOperator",
            address(configTimelock)
        );
        activator.checkPreconditions();
    }

    // given the oracle names a config operator
    //   [X] it reverts with AlreadyBound naming the binding and the operator

    function test_givenOracleNamesConfigOperator_reverts() public {
        vm.prank(ocgTimelock);
        backingOracle.setConfigOperator(address(backingOracleConfigTimelock));

        _expectRevertAlreadyBound(
            "BackingOracle configOperator",
            address(backingOracleConfigTimelock)
        );
        activator.checkPreconditions();
    }

    // given the facility is not authorized as a market callback
    //   [X] it reverts with CallbackNotAuthorized naming the auctioneer

    function test_givenCallbackNotAuthorized_reverts() public {
        vm.prank(bondGuardian);
        bondAuctioneer.setCallbackAuthStatus(address(facility), false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_CallbackNotAuthorized
                    .selector,
                address(bondAuctioneer)
            )
        );
        activator.checkPreconditions();
    }

    // given the Heart is not active in the Kernel
    //   [X] it reverts with PolicyNotActive naming the Heart

    function test_givenHeartNotActive_reverts() public {
        kernel.executeAction(Actions.DeactivatePolicy, address(heart));

        _expectRevertPolicyNotActive(address(heart));
        activator.checkPreconditions();
    }

    // given the Heart is disabled
    //   [X] it reverts with PolicyNotEnabled naming the Heart

    function test_givenHeartDisabled_reverts() public {
        heart.disable("");

        _expectRevertPolicyNotEnabled(address(heart));
        activator.checkPreconditions();
    }

    // given v1.2 is not a periodic task of the Heart
    //   [X] it reverts with V1NotHeartTask

    function test_givenV1NotHeartTask_reverts() public {
        heart.removePeriodicTask(address(yieldRepoV1));

        vm.expectRevert(
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_V1NotHeartTask
                .selector
        );
        activator.checkPreconditions();
    }

    // given the facility is already a periodic task of the Heart
    //   [X] it reverts with FacilityAlreadyHeartTask

    function test_givenFacilityAlreadyHeartTask_reverts() public {
        heart.addPeriodicTask(address(facility));

        vm.expectRevert(
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_FacilityAlreadyHeartTask
                .selector
        );
        activator.checkPreconditions();
    }

    // given v1.2 is shut down
    //   [X] it reverts with V1ShutDown

    function test_givenV1ShutDown_reverts() public {
        address[] memory tokens = new address[](0);
        // The call takes the address array as the token array of the deployed contract
        (bool ok, ) = _shutdownV1As(daoMS, tokens);
        assertTrue(ok, "the DAO MS should shut v1.2 down");

        vm.expectRevert(
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_V1ShutDown
                .selector
        );
        activator.checkPreconditions();
    }

    // given a holder of loop_daddy has initialized v1.2 again with a zero conversion rate
    //   [X] it reverts with V1ConversionRateUnset

    function test_givenV1ConversionRateSnapshotIsZero_reverts() public {
        uint256 reserveBalance = yieldRepoV1.lastReserveBalance();
        vm.prank(daoMS);
        yieldRepoV1.initialize(reserveBalance, 0, V1_INITIAL_YIELD);

        vm.expectRevert(
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_V1ConversionRateUnset
                .selector
        );
        activator.checkPreconditions();
    }

    // given a Clearinghouse has joined the CHREG registry since the deployment
    //   [X] it reverts with ClearinghouseRegistryMismatch naming both counts

    function test_givenRegistryHasAnotherClearinghouse_reverts() public {
        address added = address(new MockClearinghouse(address(usds), address(sUsds)));
        vm.label(added, "clearinghouseFour");
        vm.prank(chregWriter);
        chreg.activateClearinghouse(added);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_ClearinghouseRegistryMismatch
                    .selector,
                address(0),
                3,
                4
            )
        );
        activator.checkPreconditions();
    }

    // given the activator lists a Clearinghouse in place of a registry entry
    //   [X] it reverts with ClearinghouseRegistryMismatch naming the registry entry that is not listed

    function test_givenRegistryEntryNotListed_reverts() public {
        address unregistered = address(new MockClearinghouse(address(usds), address(sUsds)));
        vm.label(unregistered, "unregisteredClearinghouse");
        IYieldRepurchaseFacilityV2Activator.LaunchParameters
            memory parameters = _launchParameters();
        parameters.clearinghouses[2].clearinghouse = unregistered;
        _replaceActivator(parameters);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_ClearinghouseRegistryMismatch
                    .selector,
                address(clearinghouseThree),
                3,
                3
            )
        );
        activator.checkPreconditions();
    }

    // given the principalReceivables read of an included Clearinghouse reverts
    //   [X] it reverts with ClearinghouseReceivablesNotReadable naming the Clearinghouse

    function test_givenIncludedClearinghouseReceivablesNotReadable_reverts() public {
        vm.mockCallRevert(
            address(clearinghouseOne),
            abi.encodeWithSelector(IGenericClearinghouse.principalReceivables.selector),
            "unreadable"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_ClearinghouseReceivablesNotReadable
                    .selector,
                address(clearinghouseOne)
            )
        );
        activator.checkPreconditions();
    }

    // given the principalReceivables of a Clearinghouse have fallen below its offset
    //   [X] it reverts with ClearinghouseOffsetTooHigh naming the Clearinghouse, the offset and the receivables

    function test_givenOffsetExceedsReceivables_reverts(uint256 receivables_) public {
        // Receivables below the offset: [0, offset - 1]
        uint256 receivables = bound(receivables_, 0, CLEARINGHOUSE_TWO_OFFSET - 1);
        clearinghouseTwo.setPrincipalReceivables(receivables);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_ClearinghouseOffsetTooHigh
                    .selector,
                address(clearinghouseTwo),
                CLEARINGHOUSE_TWO_OFFSET,
                receivables
            )
        );
        activator.checkPreconditions();
    }

    // given a Clearinghouse is offset without being included
    //   given its principalReceivables are below the offset
    //     [X] it reverts with ClearinghouseOffsetTooHigh

    function test_givenOffsetOfExcludedClearinghouseExceedsReceivables_reverts() public {
        IYieldRepurchaseFacilityV2Activator.LaunchParameters
            memory parameters = _launchParameters();
        parameters.clearinghouses[2].offset = CLEARINGHOUSE_THREE_RECEIVABLES + 1;
        _replaceActivator(parameters);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_ClearinghouseOffsetTooHigh
                    .selector,
                address(clearinghouseThree),
                CLEARINGHOUSE_THREE_RECEIVABLES + 1,
                CLEARINGHOUSE_THREE_RECEIVABLES
            )
        );
        activator.checkPreconditions();
    }

    // given the USDS feed is stale
    //   [X] it reverts with ReserveNotPriceable naming USDS

    function test_givenUsdsFeedStale_reverts() public {
        _setFeed(usdsUsdFeed, USDS_FEED_ANSWER, vm.getBlockTimestamp() - FEED_UPDATE_THRESHOLD - 1);

        _expectRevertReserveNotPriceable(address(usds));
        activator.checkPreconditions();
    }

    // given the OHM feed is stale
    //   [X] it reverts with ReserveNotPriceable naming USDS, the first reserve OHM is priced in

    function test_givenOhmFeedStale_reverts() public {
        _setFeed(ohmUsdFeed, OHM_FEED_ANSWER, vm.getBlockTimestamp() - FEED_UPDATE_THRESHOLD - 1);

        _expectRevertReserveNotPriceable(address(usds));
        activator.checkPreconditions();
    }

    // given USDe is registered in the PRICE module
    //   given its feed is stale
    //     [X] it reverts with ReserveNotPriceable naming USDe

    function test_givenUsdeRegistered_givenUsdeFeedStale_reverts() public givenUsdeRegistered {
        _setFeed(usdeUsdFeed, USDE_FEED_ANSWER, vm.getBlockTimestamp() - FEED_UPDATE_THRESHOLD - 1);

        _expectRevertReserveNotPriceable(address(usde));
        activator.checkPreconditions();
    }

    // given USDe is not registered
    //   given PriceConfig is not active in the Kernel
    //     [X] it reverts with PolicyNotActive naming PriceConfig

    function test_givenPriceConfigNotActive_reverts() public {
        kernel.executeAction(Actions.DeactivatePolicy, address(priceConfig));

        _expectRevertPolicyNotActive(address(priceConfig));
        activator.checkPreconditions();
    }

    // given USDe is not registered
    //   given PriceConfig is disabled
    //     [X] it reverts with PolicyNotEnabled naming PriceConfig

    function test_givenPriceConfigDisabled_reverts() public {
        priceConfig.disable("");

        _expectRevertPolicyNotEnabled(address(priceConfig));
        activator.checkPreconditions();
    }

    // given USDe is not registered
    //   given the PRICE module reports no Chainlink submodule
    //     [X] it reverts with UsdeFeedNotReadable without revert data

    function test_givenChainlinkSubmoduleMissing_reverts() public {
        // The getter of the public mapping of the PRICE module, keyed by the submodule keycode
        vm.mockCall(
            address(price),
            abi.encodeWithSelector(
                ModuleWithSubmodules(address(price)).getSubmoduleForKeycode.selector
            ),
            abi.encode(address(0))
        );

        _expectRevertUsdeFeedNotReadable("");
        activator.checkPreconditions();
    }

    // given USDe is not registered
    //   given the answer of the USDe feed is older than the update threshold
    //     [X] it reverts with UsdeFeedNotReadable carrying the stale-round error of the submodule

    function test_givenUsdeFeedStale_reverts(uint256 age_) public {
        // An age above the threshold: [threshold + 1, the whole block timestamp]
        uint256 age = bound(age_, uint256(FEED_UPDATE_THRESHOLD) + 1, vm.getBlockTimestamp());
        _setFeed(usdeUsdFeed, USDE_FEED_ANSWER, vm.getBlockTimestamp() - age);

        _expectRevertUsdeFeedNotReadable(
            abi.encodeWithSelector(
                ChainlinkPriceFeeds.Chainlink_FeedRoundStale.selector,
                address(usdeUsdFeed),
                vm.getBlockTimestamp() - age,
                vm.getBlockTimestamp() - FEED_UPDATE_THRESHOLD
            )
        );
        activator.checkPreconditions();
    }

    // given USDe is not registered
    //   given the USDe feed answers zero
    //     [X] it reverts with UsdeFeedNotReadable carrying the invalid-price error of the submodule

    function test_givenUsdeFeedAnswersZero_reverts() public {
        _setFeed(usdeUsdFeed, 0, vm.getBlockTimestamp());

        _expectRevertUsdeFeedNotReadable(
            abi.encodeWithSelector(
                ChainlinkPriceFeeds.Chainlink_FeedPriceInvalid.selector,
                address(usdeUsdFeed),
                int256(0)
            )
        );
        activator.checkPreconditions();
    }

    // given USDe is not registered
    //   given the USDe price is below the tolerance around 1 USD
    //     [X] it reverts with UsdePriceOutOfBounds naming the price

    function test_givenUsdePriceBelowTolerance_reverts(uint256 answer_) public {
        // Feed answers (8 decimals) below 0.99 USD: [1, 98,999,999]
        uint256 answer = bound(answer_, 1, 98_999_999);
        // casting to 'int256' is safe because the answer is below 1e8
        // forge-lint: disable-next-line(unsafe-typecast)
        _setFeed(usdeUsdFeed, int256(answer), vm.getBlockTimestamp());

        // answer (8 decimals) * 1e10 -> price (18 decimals)
        _expectRevertUsdePriceOutOfBounds(answer * 1e10);
        activator.checkPreconditions();
    }

    // given USDe is not registered
    //   given the USDe price is above the tolerance around 1 USD
    //     [X] it reverts with UsdePriceOutOfBounds naming the price

    function test_givenUsdePriceAboveTolerance_reverts(uint256 answer_) public {
        // Feed answers (8 decimals) above 1.01 USD: [101,000,001, 1e12]
        uint256 answer = bound(answer_, 101_000_001, 1e12);
        // casting to 'int256' is safe because the answer is at most 1e12
        // forge-lint: disable-next-line(unsafe-typecast)
        _setFeed(usdeUsdFeed, int256(answer), vm.getBlockTimestamp());

        // answer (8 decimals) * 1e10 -> price (18 decimals)
        _expectRevertUsdePriceOutOfBounds(answer * 1e10);
        activator.checkPreconditions();
    }

    // ========== SUCCESS CONDITIONS ========== //

    // given the prepared stack
    //   when any account calls
    //     [X] it passes

    function test_givenPreparedStack(address caller_) public {
        vm.prank(caller_);
        activator.checkPreconditions();
    }

    // given the activator holds neither of its two roles
    //   [X] it passes: the roles are granted by the proposal that calls the activator

    function test_givenActivatorHoldsNoRole() public {
        rolesAdmin.revokeRole(ADMIN_ROLE, address(activator));
        rolesAdmin.revokeRole(LOOP_DADDY_ROLE, address(activator));

        activator.checkPreconditions();
    }

    // given a holder of loop_daddy has initialized v1.2 again with a zero reserve balance
    //   [X] it passes: the yield projected from a zero balance is zero

    function test_givenV1ReserveBalanceSnapshotIsZero() public {
        uint256 conversionRate = yieldRepoV1.lastConversionRate();
        vm.prank(daoMS);
        yieldRepoV1.initialize(0, conversionRate, V1_INITIAL_YIELD);

        activator.checkPreconditions();
    }

    // given the principalReceivables of a Clearinghouse equal its offset
    //   [X] it passes

    function test_givenOffsetEqualsReceivables() public {
        clearinghouseTwo.setPrincipalReceivables(CLEARINGHOUSE_TWO_OFFSET);

        activator.checkPreconditions();
    }

    // given the principalReceivables read of a Clearinghouse that is neither included nor offset reverts
    //   [X] it passes: the launch does not read that Clearinghouse

    function test_givenUnusedClearinghouseReceivablesNotReadable() public {
        vm.mockCallRevert(
            address(clearinghouseThree),
            abi.encodeWithSelector(IGenericClearinghouse.principalReceivables.selector),
            "unreadable"
        );

        activator.checkPreconditions();
    }

    // given USDe is not registered
    //   given the answer of the USDe feed is exactly as old as the update threshold
    //     [X] it passes

    function test_givenUsdeFeedAtUpdateThreshold() public {
        _setFeed(usdeUsdFeed, USDE_FEED_ANSWER, vm.getBlockTimestamp() - FEED_UPDATE_THRESHOLD);

        activator.checkPreconditions();
    }

    // given USDe is not registered
    //   given the USDe price lies within the tolerance around 1 USD, bounds included
    //     [X] it passes

    function test_givenUsdePriceWithinTolerance(uint256 answer_) public {
        // Feed answers (8 decimals) from 0.99 USD to 1.01 USD: [99,000,000, 101,000,000].
        // |price - 1e18| * 10,000 / 1e18 is at most 100 bps over the whole interval.
        uint256 answer = bound(answer_, 99_000_000, 101_000_000);
        // casting to 'int256' is safe because the answer is at most 1.01e8
        // forge-lint: disable-next-line(unsafe-typecast)
        _setFeed(usdeUsdFeed, int256(answer), vm.getBlockTimestamp());

        activator.checkPreconditions();
    }

    // given USDe is registered in the PRICE module
    //   given PriceConfig is disabled and the USDe price is outside the tolerance
    //     [X] it passes: a registered USDe is not registered again

    function test_givenUsdeRegistered_givenPriceConfigDisabled() public givenUsdeRegistered {
        priceConfig.disable("");
        // 0.95 USD (8 decimals), outside the tolerance of a registration
        _setFeed(usdeUsdFeed, 95_000_000, vm.getBlockTimestamp());

        activator.checkPreconditions();
    }

    // given a third party has transferred USDS, sUSDS and OHM to v1.2
    //   [X] it passes: the balances of v1.2 are read when the launch runs

    function test_givenTokensTransferredToV1() public {
        usds.mint(address(yieldRepoV1), 1_000e18);
        _depositFor(usds, sUsds, address(yieldRepoV1), 1_000e18);
        ohm.mint(address(yieldRepoV1), 100e9);

        activator.checkPreconditions();
    }

    // ========== INTERNAL ========== //

    /// @notice Calls `shutdown` of v1.2 from `caller_` with the address array encoding.
    function _shutdownV1As(
        address caller_,
        address[] memory tokens_
    ) internal returns (bool ok, bytes memory data) {
        address target = address(yieldRepoV1);
        bytes memory payload = abi.encodeWithSignature("shutdown(address[])", tokens_);
        vm.prank(caller_);
        // The deployed contract declares the parameter as a token array, which shares the ABI
        // encoding of an address array; the success flag is asserted by the caller
        // forge-lint: disable-next-item(low-level-calls)
        // solhint-disable-next-line avoid-low-level-calls
        (ok, data) = target.call(payload);
    }
}
