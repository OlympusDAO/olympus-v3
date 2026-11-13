// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2Activator} from "src/proposals/interfaces/IYieldRepurchaseFacilityV2Activator.sol";

// Libraries
import {fromSubKeycode, toSubKeycode} from "src/Submodules.sol";
import {YieldRepurchaseFacilityV2EnvFixture} from "./YieldRepurchaseFacilityV2Proposal/YieldRepurchaseFacilityV2EnvFixture.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {YieldRepurchaseFacilityV2Activator} from "src/proposals/YieldRepurchaseFacilityV2Activator.sol";
import {YieldRepurchaseFacilityV2ProposalRig} from "./YieldRepurchaseFacilityV2Proposal/YieldRepurchaseFacilityV2ProposalRig.sol";

// The rig loops walk the periodic tasks and the Clearinghouses of the fork
// forge-lint: disable-start(calls-loop)

/// @notice The activator on a mainnet fork, called directly from the OCG timelock with the two
///         roles the proposal grants it: the migration against the live state of the
///         YieldRepurchaseFacility v1.2, the state that moves between the submission and the
///         execution of the proposal, and the first beats of the Heart after the launch.
contract YieldRepurchaseFacilityV2ActivatorForkTest is YieldRepurchaseFacilityV2ProposalRig {
    /// @notice The next yield of the sUSDe vault, as the proposal passes it.
    uint256 internal sUsdeNextYield;

    /// @notice The update threshold the launch registers the USDe/USD feed with, in seconds.
    uint48 internal constant USDE_FEED_UPDATE_THRESHOLD = 1 days;

    /// @notice The weekly epoch count of the facility and of v1.2, and the epochs of a day.
    uint48 internal constant EPOCH_LENGTH = 21;
    uint48 internal constant EPOCHS_PER_DAY = 3;
    uint256 internal constant DAYS_PER_WEEK = 7;

    function setUp() public virtual override {
        super.setUp();

        sUsdeNextYield = proposal.SUSDE_NEXT_YIELD();

        // The two grants the proposal makes before it calls the activator
        _grantRole(ADMIN_ROLE, address(activator));
        _grantRole(_LOOP_DADDY_ROLE, address(activator));
    }

    // ========== HELPERS ========== //

    function _activate() internal {
        YieldRepurchaseFacilityV2Activator target = activator;
        uint256 nextYield = sUsdeNextYield;
        vm.prank(ocgTimelock);
        target.activate(nextYield);
    }

    // ========== MIGRATION ========== //

    // given the live state at the pin
    //   when the timelock activates
    //     [X] the five policies are enabled and bound, with the values of env.json
    //     [X] USDe is registered in the PRICE module with the Chainlink feed and the one-day threshold
    //     [X] the facility continues the weekly cycle of v1.2 with its funds
    //     [X] the Clearinghouses carry the declared inclusions and offsets
    //     [X] the other periodic tasks of the Heart keep their slots

    function test_givenLiveState_whenActivated() public {
        LaunchInputs memory inputs = _launchInputs();
        (address[] memory tasksBefore, bytes4[] memory selectorsBefore) = heart.getPeriodicTasks();
        YieldRepurchaseFacilityV2EnvFixture.State memory desired = _desired();
        assertFalse(price.isAssetApproved(address(usde)), "live: USDe should not be registered");

        vm.expectEmit(address(activator));
        emit IYieldRepurchaseFacilityV2Activator.Activated(
            inputs.epoch,
            inputs.nextYield,
            inputs.poolSeed,
            sUsdeNextYield
        );
        _activate();
        emit log_named_uint("gas of activate()", vm.lastFrameGas().gasTotalUsed);

        _assertMigrated(inputs, sUsdeNextYield);

        // Lifecycle, bindings and parameters
        assertTrue(backingOracle.isEnabled(), "the oracle should be enabled");
        assertTrue(
            backingOracleConfigTimelock.isEnabled(),
            "the oracle timelock should be enabled"
        );
        assertTrue(config.isEnabled(), "the configuration policy should be enabled");
        assertTrue(configTimelock.isEnabled(), "the config timelock should be enabled");
        assertTrue(facility.isEnabled(), "the facility should be enabled");
        assertEq(
            backingOracle.configOperator(),
            address(backingOracleConfigTimelock),
            "oracle config operator"
        );
        assertEq(config.facility(), address(facility), "configuration policy facility");
        assertEq(facility.configurator(), address(config), "facility configurator");
        assertEq(config.configOperator(), address(configTimelock), "config operator");
        assertEq(backingOracle.backing(), desired.backing, "backing of env.json");
        assertEq(
            facility.initialDiscount(),
            desired.config.parameters.initialDiscount,
            "initialDiscount of env.json"
        );
        assertEq(
            facility.maxPricePremium(),
            desired.config.parameters.maxPricePremium,
            "maxPricePremium of env.json"
        );

        // Assets
        assertEq(facility.getVaults().length, 2, "the facility should register two vaults");
        IYieldRepurchaseFacilityV2.ReserveAsset memory sUsdsAsset = facility.getAssetConfig(
            address(sUsds)
        );
        assertEq(sUsdsAsset.reserve, address(usds), "sUSDS: reserve");
        assertFalse(sUsdsAsset.sellShares, "sUSDS: the markets should pay out USDS");
        assertTrue(sUsdsAsset.isAssetEnabled, "sUSDS: enabled");
        assertFalse(sUsdsAsset.asyncRedeem, "sUSDS: synchronous redemption");
        IYieldRepurchaseFacilityV2.ReserveAsset memory sUsdeAsset = facility.getAssetConfig(
            address(sUsde)
        );
        assertEq(sUsdeAsset.reserve, address(usde), "sUSDe: reserve");
        assertTrue(sUsdeAsset.sellShares, "sUSDe: the markets should pay out sUSDe");
        assertTrue(sUsdeAsset.isAssetEnabled, "sUSDe: enabled");
        assertFalse(sUsdeAsset.asyncRedeem, "sUSDe: valued through the previews");

        // USDe in the PRICE module: one Chainlink feed, no moving average
        assertTrue(price.isAssetApproved(address(usde)), "USDe should be registered");
        IPRICEv2.Asset memory usdeData = price.getAssetData(address(usde));
        assertFalse(usdeData.storeMovingAverage, "USDe: no stored moving average");
        assertFalse(usdeData.useMovingAverage, "USDe: no moving average in the price");
        IPRICEv2.Component[] memory feeds = abi.decode(usdeData.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 1, "USDe: one feed");
        assertEq(
            fromSubKeycode(feeds[0].target),
            fromSubKeycode(toSubKeycode("PRICE.CHAINLINK")),
            "USDe: the Chainlink submodule"
        );
        assertEq(feeds[0].selector, ChainlinkPriceFeeds.getOneFeedPrice.selector, "USDe: one feed");
        ChainlinkPriceFeeds.OneFeedParams memory feedParams = abi.decode(
            feeds[0].params,
            (ChainlinkPriceFeeds.OneFeedParams)
        );
        assertEq(address(feedParams.feed), address(usdeUsdFeed), "USDe: the feed of env.json");
        assertEq(feedParams.updateThreshold, USDE_FEED_UPDATE_THRESHOLD, "USDe: one-day threshold");
        assertGt(price.getPriceIn(address(ohm), address(usde)), 0, "OHM should be priced in USDe");

        // Clearinghouses
        for (uint256 i = 0; i < desired.config.clearinghouses.length; ++i) {
            address clearinghouse = desired.config.clearinghouses[i].clearinghouse;
            assertEq(
                facility.isClearinghouseIncluded(clearinghouse),
                desired.config.clearinghouses[i].included,
                string.concat("included: ", vm.toString(clearinghouse))
            );
            assertEq(
                facility.clearinghouseOffset(clearinghouse),
                desired.config.clearinghouses[i].offset,
                string.concat("offset: ", vm.toString(clearinghouse))
            );
        }

        // The other periodic tasks
        (address[] memory tasksAfter, bytes4[] memory selectorsAfter) = heart.getPeriodicTasks();
        for (uint256 i = 0; i < tasksBefore.length; ++i) {
            if (i == inputs.heartTaskIndex) continue;
            assertEq(tasksAfter[i], tasksBefore[i], "the other tasks should keep their slots");
            assertEq(
                selectorsAfter[i],
                selectorsBefore[i],
                "the other selectors should not change"
            );
        }
    }

    // ========== STATE THAT MOVES BEFORE THE EXECUTION ========== //

    // given the Heart beats before the launch, with v1.2 still its task
    //   when the timelock activates
    //     [X] the facility resumes at the epoch v1.2 reached, with the funds v1.2 holds then

    function test_givenHeartBeatsBeforeTheLaunch() public {
        uint48 epochAtPin = yieldRepoV1.epoch();
        _beat();
        LaunchInputs memory inputs = _launchInputs();
        // The epoch counter of v1.2 wraps from 20 to 0
        assertEq(
            inputs.epoch,
            (epochAtPin + 1) % EPOCH_LENGTH,
            "rig: the beat should advance the epoch of v1.2"
        );

        _activate();

        _assertMigrated(inputs, sUsdeNextYield);
    }

    // given a third party transfers USDS and sUSDS to v1.2 before the launch
    //   when the timelock activates
    //     [X] the transferred funds join the buyback pool of the facility

    function test_givenTokensTransferredToV1() public {
        LaunchInputs memory atPin = _launchInputs();
        // 1,000 USDS (18 decimals) and 1,000 sUSDS shares (18 decimals) on top of the balances
        deal(address(usds), address(yieldRepoV1), atPin.v1Usds + 1_000e18);
        deal(address(sUsds), address(yieldRepoV1), atPin.v1SUsdsShares + 1_000e18);
        LaunchInputs memory inputs = _launchInputs();
        assertGt(inputs.poolSeed, atPin.poolSeed, "rig: the transfers should raise the funds");

        _activate();

        _assertMigrated(inputs, sUsdeNextYield);
    }

    // given a holder of price_admin registers USDe before the launch
    //   when the timelock activates
    //     [X] the launch does not register USDe again

    function test_givenUsdeRegisteredBeforeTheLaunch() public {
        _registerUsdeAsDaoMS(USDE_FEED_UPDATE_THRESHOLD);
        LaunchInputs memory inputs = _launchInputs();

        vm.expectCall(priceConfig, abi.encodeWithSelector(IPriceConfigv2.addAsset.selector), 0);
        _activate();

        _assertMigrated(inputs, sUsdeNextYield);
    }

    // given the answer of the USDe/USD feed is older than one day when the proposal executes
    //   when the timelock activates
    //     [X] it reverts with UsdeFeedNotReadable carrying the stale-round error
    //   when the feed is updated and the timelock activates again
    //     [X] the launch completes

    function test_givenUsdeFeedStale_reverts_thenLaunchesAfterTheUpdate() public {
        uint256 staleAt = vm.getBlockTimestamp() - USDE_FEED_UPDATE_THRESHOLD - 1;
        _setUsdeFeed(usdeFeedAnswer, staleAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_UsdeFeedNotReadable
                    .selector,
                address(usdeUsdFeed),
                abi.encodeWithSelector(
                    ChainlinkPriceFeeds.Chainlink_FeedRoundStale.selector,
                    address(usdeUsdFeed),
                    staleAt,
                    vm.getBlockTimestamp() - USDE_FEED_UPDATE_THRESHOLD
                )
            )
        );
        _activate();
        assertFalse(activator.isActivated(), "a reverted launch should leave the flag unset");

        _setUsdeFeed(usdeFeedAnswer, vm.getBlockTimestamp());
        LaunchInputs memory inputs = _launchInputs();
        _activate();

        _assertMigrated(inputs, sUsdeNextYield);
    }

    // given the USDe/USD feed reports a price more than 1% away from 1 USD
    //   when the timelock activates
    //     [X] it reverts with UsdePriceOutOfBounds naming the price

    function test_givenUsdePriceOutOfTolerance_reverts() public {
        uint8 feedDecimals = usdeUsdFeed.decimals();
        // 0.98 USD in the decimals of the feed: 98 * 10^(decimals - 2)
        uint256 answer = 98 * 10 ** (feedDecimals - 2);
        // casting to 'int256' is safe because the answer is below 10^decimals
        // forge-lint: disable-next-line(unsafe-typecast)
        _setUsdeFeed(int256(answer), vm.getBlockTimestamp());

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_UsdePriceOutOfBounds
                    .selector,
                // answer (feed decimals) * 10^(18 - feed decimals) -> 0.98e18 (18 decimals)
                0.98e18,
                1e18,
                uint16(100)
            )
        );
        _activate();
    }

    // given a holder of loop_daddy shuts v1.2 down before the launch
    //   when the timelock activates
    //     [X] it reverts with V1ShutDown

    function test_givenV1ShutDownBeforeTheLaunch_reverts() public {
        _shutdownV1(daoMS);

        vm.expectRevert(
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_V1ShutDown
                .selector
        );
        _activate();
    }

    // given the owner of the bond auctioneer revokes the callback authorization before the launch
    //   when the timelock activates
    //     [X] it reverts with CallbackNotAuthorized naming the auctioneer

    function test_givenCallbackRevokedBeforeTheLaunch_reverts() public {
        _setCallbackAuthStatus(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_CallbackNotAuthorized
                    .selector,
                address(bondAuctioneer)
            )
        );
        _activate();
    }

    // given the DAO MS deactivates the facility in the Kernel before the launch
    //   when the timelock activates
    //     [X] it reverts with PolicyNotActive naming the facility

    function test_givenFacilityDeactivatedBeforeTheLaunch_reverts() public {
        address facilityAddress = address(facility);
        vm.prank(daoMS);
        kernel.executeAction(Actions.DeactivatePolicy, facilityAddress);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_PolicyNotActive
                    .selector,
                facilityAddress
            )
        );
        _activate();
    }

    // ========== THE HEART AFTER THE LAUNCH ========== //

    // given the launch has completed
    //   when the Heart beats through the rest of the week and the weekly reset
    //     [X] v1.2 is not called again
    //     [X] the facility advances its epoch with every beat
    //     [X] each daily beat before the reset opens the sUSDS market from the funds of v1.2
    //     [X] the weekly reset funds both pools with the registered next yields and opens both markets

    function test_givenActivated_whenHeartBeatsThroughTheWeek() public {
        _activate();
        uint48 epoch = facility.epoch();
        uint48 v1Epoch = yieldRepoV1.epoch();
        uint256 sUsdsNextYield = facility.getAssetConfig(address(sUsds)).nextYield;
        assertGt(sUsdsNextYield, 0, "rig: v1.2 should carry a next yield");

        while (true) {
            ++epoch;
            bool weeklyReset = epoch == EPOCH_LENGTH;
            if (weeklyReset) epoch = 0;
            _warpToNextBeat();
            uint256 sUsdsSharesBefore = IERC20(address(sUsds)).balanceOf(address(facility));
            uint256 sUsdeSharesBefore = IERC20(address(sUsde)).balanceOf(address(facility));
            // The sUSDS pool at the time of the beat: the USDS left of the last market plus
            // the value of the shares (USDS, 18 decimals)
            uint256 sUsdsPoolBefore = usds.balanceOf(address(facility)) +
                sUsds.previewRedeem(sUsdsSharesBefore);

            _beatNow();

            assertEq(facility.epoch(), epoch, "the facility should advance its epoch");
            assertEq(yieldRepoV1.epoch(), v1Epoch, "v1.2 should not be called");

            if (weeklyReset) {
                _assertWeeklyReset(sUsdsPoolBefore, sUsdeSharesBefore, sUsdsNextYield);
                break;
            }
            if (epoch % EPOCHS_PER_DAY != 0) {
                assertEq(
                    IERC20(address(sUsds)).balanceOf(address(facility)),
                    sUsdsSharesBefore,
                    "a beat inside a day should leave the pool alone"
                );
                continue;
            }
            _assertDailyBeatBeforeReset(epoch);
        }
    }

    /// @notice Asserts a daily beat of the migrated week: the sUSDS market is open, sized as
    ///         the pool over the days that remain, and the sUSDe pool is still empty.
    function _assertDailyBeatBeforeReset(uint48 epoch_) internal view {
        (bool tracked, uint256 marketId) = facility.trackedMarket(address(sUsds));
        assertTrue(tracked, "the facility should open the sUSDS market of the day");
        uint256 capacity = bondAuctioneer.currentCapacity(marketId);
        // The cycle redeems the bid into USDS, so after it the pool is the USDS held plus the
        // value of the shares held (USDS, 18 decimals), and the bid was that pool over the
        // days that remain: 7 - epoch / 3. The redemption rounds in favour of the vault, so
        // the pool read after the cycle can be a few units below the pool the bid was sized
        // from.
        uint256 daysRemaining = DAYS_PER_WEEK - uint256(epoch_ / EPOCHS_PER_DAY);
        uint256 poolAfter = usds.balanceOf(address(facility)) +
            sUsds.previewRedeem(IERC20(address(sUsds)).balanceOf(address(facility)));
        assertApproxEqAbs(
            capacity,
            poolAfter / daysRemaining,
            10,
            "the market should offer the pool over the days that remain"
        );
        assertEq(
            usds.balanceOf(address(facility)),
            capacity,
            "the facility should hold the USDS of the open market"
        );
        (bool sUsdeTracked, ) = facility.trackedMarket(address(sUsde));
        assertFalse(sUsdeTracked, "the sUSDe pool is empty before the first weekly reset");
    }

    /// @notice Asserts the first weekly reset of the facility: both pools are funded with the
    ///         registered next yields, the snapshots are refreshed and both markets are open.
    function _assertWeeklyReset(
        uint256 sUsdsPoolBefore_,
        uint256 sUsdeSharesBefore_,
        uint256 sUsdsNextYield_
    ) internal view {
        assertEq(sUsdeSharesBefore_, 0, "the sUSDe pool should be empty before the reset");
        // The reset withdraws the shares that cover the next yield, rounded up by the vault.
        // The sUSDe markets pay out shares, so the facility still holds all of them.
        assertEq(
            IERC20(address(sUsde)).balanceOf(address(facility)),
            sUsde.previewWithdraw(sUsdeNextYield),
            "the reset should fund the sUSDe pool with the registered next yield"
        );
        // The sUSDS cycle of the same beat redeems a part of the pool into USDS for its
        // market, so the pool is compared by value: before + next yield (USDS, 18 decimals),
        // within the rounding of two share conversions and one redemption.
        uint256 poolAfter = usds.balanceOf(address(facility)) +
            sUsds.previewRedeem(IERC20(address(sUsds)).balanceOf(address(facility)));
        assertApproxEqAbs(
            poolAfter,
            sUsdsPoolBefore_ + sUsdsNextYield_,
            10,
            "the reset should add the next yield of v1.2 to the sUSDS pool"
        );

        IYieldRepurchaseFacilityV2.ReserveAsset memory sUsdsAsset = facility.getAssetConfig(
            address(sUsds)
        );
        IYieldRepurchaseFacilityV2.ReserveAsset memory sUsdeAsset = facility.getAssetConfig(
            address(sUsde)
        );
        assertEq(sUsdsAsset.unfundedYield, 0, "sUSDS: the treasury should cover the yield");
        assertEq(sUsdeAsset.unfundedYield, 0, "sUSDe: the treasury should cover the yield");
        assertEq(
            sUsdsAsset.lastConversionRate,
            sUsds.previewRedeem(_ONE),
            "sUSDS: the rate snapshot should be refreshed"
        );
        assertEq(
            sUsdeAsset.lastConversionRate,
            sUsde.previewRedeem(_ONE),
            "sUSDe: the rate snapshot should be refreshed"
        );
        assertGt(sUsdsAsset.nextYield, 0, "sUSDS: the reset should project the next yield");

        (bool sUsdsTracked, ) = facility.trackedMarket(address(sUsds));
        (bool sUsdeTracked, ) = facility.trackedMarket(address(sUsde));
        assertTrue(sUsdsTracked, "the reset beat should open the sUSDS market");
        assertTrue(sUsdeTracked, "the reset beat should open the sUSDe market");
    }
}

// forge-lint: disable-end(calls-loop)
