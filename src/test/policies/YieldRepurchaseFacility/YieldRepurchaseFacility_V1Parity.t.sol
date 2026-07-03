// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {YieldRepurchaseFacilityV2TestBase} from "./YieldRepurchaseFacilityV2TestBase.sol";

import {ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockClearinghouse} from "src/test/mocks/MockClearinghouse.sol";
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";

import {FullMath} from "libraries/FullMath.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusClearinghouseRegistry} from "modules/CHREG/OlympusClearinghouseRegistry.sol";
import {IPolicyAdmin} from "policies/interfaces/utils/IPolicyAdmin.sol";
import {IYieldRepurchaseFacilityV2} from "policies/interfaces/IYieldRepurchaseFacilityV2.sol";

// This file is a copy of the V1 YieldRepurchaseFacility tests, updated to run against
// the multi-asset YieldRepurchaseFacilityV2 with a single sUSDS-like reserve asset.
// Its purpose is to highlight differences in the calculations.
//
// Known V2 design differences are marked with "V2 DIFFERENCE" comments:
// - execute() skips the daily cycle (no bond market) when the oracle price is below the backing.
// - Bond markets are created with a callback (this contract) instead of a teller allowance.
// - Bond markets have a minimum price floor (the undiscounted oracle price) instead of zero.
// - The daily bid amount is based on the weeklyBudgetRemaining counter instead of actual
//   token holdings, so intra-week vault appreciation is excluded until the next weekly reset.
//
// solhint-disable-next-line max-states-count
contract YieldRepurchaseFacilityV1ParityTest is YieldRepurchaseFacilityV2TestBase {
    using ModuleTestFixtureGenerator for OlympusClearinghouseRegistry;
    using FullMath for uint256;

    address internal alice;
    address internal bob;
    address internal godmode;

    uint256 internal initialReserves = 105_000_000e18;
    uint256 internal initialConversionRate = 1_05e16;
    uint256 internal initialPrincipalReceivables = 100_000_000e18;
    uint256 internal initialYield = 50_000e18 + ((initialPrincipalReceivables * 5) / 1000) / 52;

    function setUp() public {
        _deployStack();

        // Extra test accounts used by the V1-parity bond-purchase flows.
        address[] memory users = userCreator.create(2);
        alice = users[0];
        bob = users[1];

        // Mint tokens to users, clearinghouse, and TRSRY for testing
        uint256 testOhm = 1_000_000 * 1e9;
        uint256 testReserve = 1_000_000 * 1e18;

        ohm.mint(alice, testOhm * 20);

        reserve.mint(address(TRSRY), testReserve * 80);
        reserve.mint(address(clearinghouse), testReserve * 20);

        // Deposit TRSRY reserves into sReserve
        vm.startPrank(address(TRSRY));
        reserve.approve(address(sReserve), testReserve * 80);
        sReserve.deposit(testReserve * 80, address(TRSRY));
        vm.stopPrank();

        // Deposit clearinghouse reserves into sReserve
        vm.startPrank(address(clearinghouse));
        reserve.approve(address(sReserve), testReserve * 20);
        sReserve.deposit(testReserve * 20, address(clearinghouse));
        vm.stopPrank();

        // Mint additional reserve to the wrapped reserve to hit the initial conversion rate
        reserve.mint(address(sReserve), 5 * testReserve);

        // Approve the bond teller for the tokens to swap
        vm.prank(alice);
        ohm.approve(address(teller), testOhm * 20);

        // Set principal receivables for the clearinghouse
        clearinghouse.setPrincipalReceivables(uint256(100_000_000e18));

        // Enable the backing oracle and the facility.
        _enableFacility();

        // Register the reserve asset with a 100% yield buyback share, make it
        // the backing vault, and seed the initial yield.
        vm.startPrank(guardian);
        yieldRepo.addAsset(address(sReserve), 1e18, initialReserves, initialConversionRate, false);
        yieldRepo.setBackingVault(address(sReserve));
        yieldRepo.adjustNextYield(address(sReserve), initialYield);
        vm.stopPrank();
    }

    // test cases
    // [X] setup (constructor + configureDependencies + enable + addAsset)
    //   [X] addresses are set correctly
    //   [X] initial reserve balance is set correctly
    //   [X] initial conversion rate is set correctly
    //   [X] initial yield is set correctly
    //   [X] epoch is set correctly
    // [X] execute (formerly endEpoch)
    //   [X] when contract is shutdown
    //     [X] nothing happens
    //   [X] when contract is not shutdown
    //     [X] when epoch is not divisible by 3
    //       [X] nothing happens
    //     [X] when epoch is divisible by 3
    //       [X] when epoch == epochLength
    //         [X] The yield earned on the wrapped reserves over the past 21 epochs is withdrawn from the TRSRY
    //             (affecting the balanceInDai and bidAmount)
    //         [X] OHM in the contract is burned and reserves are added at the backing rate
    //         [X] given current price is less than the backing
    //           [X] V2 DIFFERENCE: no bond market is created (V1 created one)
    //         [X] given current price is greater than or equal to the backing
    //           [X] a new bond market is created with correct bid amount
    //       [X] when epoch != epochLength
    //         [X] OHM in the contract is burned and reserves are added at the backing rate
    //         [X] a new bond market is created with correct bid amount
    // [X] adjustNextYield
    // [X] shutdown
    // [X] getNextYield
    // [X] getReserveBalance

    function test_setup() public view {
        // addresses are set correctly
        assertEq(yieldRepo.teller(), address(teller));
        assertEq(yieldRepo.bondAuctioneer(), address(auctioneer));
        assertEq(yieldRepo.backingOracle(), address(backingOracle));
        assertEq(yieldRepo.backingVault(), address(sReserve));
        assertEq(yieldRepo.initialDiscount(), initialDiscount);
        assertEq(backingOracle.backing(), backingPerToken);

        IYieldRepurchaseFacilityV2.ReserveAsset memory config = yieldRepo.getAssetConfig(
            address(sReserve)
        );
        assertEq(config.vault, address(sReserve));
        assertEq(config.reserve, address(reserve));
        assertTrue(config.isActive);
        assertEq(config.yieldBuybackShare, 1e18);

        // initial reserve balance is set correctly
        assertEq(config.lastReserveBalance, initialReserves);
        assertEq(yieldRepo.getReserveBalance(address(sReserve)), initialReserves);

        // initial conversion rate is set correctly
        assertEq(config.lastConversionRate, initialConversionRate);
        assertEq((sReserve.totalAssets() * 1e18) / sReserve.totalSupply(), 1_05e16);

        // initial yield is set correctly
        assertEq(config.nextYield, initialYield);

        // epoch is set correctly
        assertEq(yieldRepo.epoch(), 20);
    }

    function test_endEpoch_firstCall_currentLessThanBacking() public {
        // The default oracle price (10e18) is below the backing (11.33e18)

        // Mint yield to the sReserve
        _mintYield();

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Cache the TRSRY sDAI balance
        uint256 trsryBalance = sReserve.balanceOf(address(TRSRY));

        vm.prank(heart);
        yieldRepo.execute();

        // Check that the initial yield was withdrawn from the TRSRY
        // Same as V1: the weekly reset withdraws previewWithdraw(initialYield) shares
        assertEq(
            sReserve.balanceOf(address(TRSRY)),
            trsryBalance - sReserve.previewWithdraw(initialYield),
            "TRSRY wrapped reserve balance"
        );

        // V2 DIFFERENCE: execute() skips the daily cycle when the oracle price is below the
        // backing, so no funds are unwrapped and no bond market is created.
        // V1 created a bond market with a capacity of initialYield / 7 here:
        // assertEq(reserve.balanceOf(address(yieldRepo)), initialYield / 7);
        // assertEq(
        //     sReserve.balanceOf(address(yieldRepo)),
        //     sReserve.previewDeposit(initialYield - initialYield / 7)
        // );
        // assertEq(aggregator.marketCounter(), nextBondMarketId + 1);
        assertEq(reserve.balanceOf(address(yieldRepo)), 0, "yieldRepo reserve balance");
        assertEq(
            sReserve.balanceOf(address(yieldRepo)),
            sReserve.previewWithdraw(initialYield),
            "yieldRepo wrapped reserve balance"
        );
        assertEq(aggregator.marketCounter(), nextBondMarketId, "no market created below backing");

        // The weekly budget is still funded with the initial yield
        assertEq(
            yieldRepo.getAssetConfig(address(sReserve)).weeklyBudgetRemaining,
            initialYield,
            "weekly budget"
        );

        // Check that the epoch has been incremented
        assertEq(yieldRepo.epoch(), 0);
    }

    function test_endEpoch_firstCall_currentGreaterThanBacking() public {
        // Change the current price to be greater than the backing
        // (this is also the price used by the V1 "greater than wall" test)
        PRICE.setLastPrice(15 * 1e18);

        // Mint yield to the sReserve
        _mintYield();

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Cache the TRSRY sDAI balance
        uint256 trsryBalance = sReserve.balanceOf(address(TRSRY));

        vm.prank(heart);
        yieldRepo.execute();

        // Check that the initial yield was withdrawn from the TRSRY
        assertEq(
            sReserve.balanceOf(address(TRSRY)),
            trsryBalance - sReserve.previewWithdraw(initialYield),
            "TRSRY wrapped reserve balance"
        );

        // Check that the yieldRepo contract has the correct reserve balance
        assertEq(
            reserve.balanceOf(address(yieldRepo)),
            initialYield / 7,
            "yieldRepo reserve balance"
        );
        assertEq(
            sReserve.balanceOf(address(yieldRepo)),
            sReserve.previewDeposit(initialYield - initialYield / 7),
            "yieldRepo wrapped reserve balance"
        );

        // Check that the bond market was created
        assertEq(aggregator.marketCounter(), nextBondMarketId + 1, "marketCount");

        // Check that the market params are correct
        // (the V1 test asserted these at a price of 10e18, which V2 skips due to the backing
        // check, so the same assertions are reproduced here at a price of 15e18)
        {
            uint256 marketPrice = auctioneer.marketPrice(nextBondMarketId);
            (
                address owner,
                ERC20 payoutToken,
                ERC20 quoteToken,
                address callbackAddr,
                bool isCapacityInQuote,
                uint256 capacity,
                ,
                uint256 minPrice,
                uint256 maxPayout,
                ,
                ,
                uint256 scale
            ) = auctioneer.markets(nextBondMarketId);

            assertEq(owner, address(yieldRepo));
            assertEq(address(payoutToken), address(reserve));
            assertEq(address(quoteToken), address(ohm));
            // V2 DIFFERENCE: V1 created markets without a callback (callbackAddr == address(0))
            assertEq(callbackAddr, address(yieldRepo));
            assertEq(isCapacityInQuote, false);
            assertEq(capacity, uint256(initialYield) / 7);
            assertEq(maxPayout, capacity / 6);

            // initialPrice = 1e36 / ((15e18 * 97) / 100) = 68728522336769759 (17 digits)
            // priceDecimals = 16 - 18 = -2
            // scaleAdjustment = 18 - 9 + (-2 / 2) = 8 -> scale = 10^(36 + 8)
            // bondScale = 10^(36 + 8 + 9 - 18 + 2) = 10^37, oracleScale = 10^(18 + 2) = 10^20
            assertEq(scale, 10 ** uint8(36 + 18 - 9 - 1), "scale");
            assertEq(
                marketPrice,
                ((uint256(1e36) / ((15e18 * 97) / 100)) * 10 ** uint8(36 + 1)) /
                    10 ** uint8(18 + 2),
                "marketPrice"
            );
            // V2 DIFFERENCE: V1 set no price floor (minPrice == 0). V2 sets the floor at the
            // undiscounted oracle price: minPrice = 1e36 / 15e18, formatted with the same scales.
            assertEq(
                minPrice,
                ((uint256(1e36) / uint256(15e18)) * 10 ** uint8(36 + 1)) / 10 ** uint8(18 + 2),
                "minPrice"
            );
        }

        // Check that the epoch has been incremented
        assertEq(yieldRepo.epoch(), 0);
    }

    function test_endEpoch_isShutdown() public {
        // Shutdown the yieldRepo contract
        // V2 DIFFERENCE: the disable payload is unused (V1 expected an abi-encoded token list);
        // all registered vault/reserve balances are transferred to the TRSRY automatically
        vm.prank(guardian);
        yieldRepo.disable("");

        // Mint yield to the sReserve
        _mintYield();

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Cache the TRSRY sDAI balance
        uint256 trsryBalance = sReserve.balanceOf(address(TRSRY));

        vm.prank(heart);
        yieldRepo.execute();

        // Check that the initial yield was not withdrawn from the treasury
        assertEq(sReserve.balanceOf(address(TRSRY)), trsryBalance);

        // Check that the yieldRepo contract has not received any funds
        assertEq(reserve.balanceOf(address(yieldRepo)), 0);
        assertEq(sReserve.balanceOf(address(yieldRepo)), 0);

        // Check that the bond market was not created
        assertEq(aggregator.marketCounter(), nextBondMarketId);
    }

    function test_endEpoch_notDivisBy3() public {
        // Mint yield to the sReserve
        _mintYield();

        // Make the initial call to get the epoch counter to reset
        vm.prank(heart);
        yieldRepo.execute();

        // Mint yield to the sReserve
        _mintYield();

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Cache the TRSRY sDAI balance
        uint256 trsryBalance = sReserve.balanceOf(address(TRSRY));

        // Cache the yieldRepo contract reserve balance
        uint256 yieldRepoReserveBalance = reserve.balanceOf(address(yieldRepo));
        uint256 yieldRepoWrappedReserveBalance = sReserve.balanceOf(address(yieldRepo));

        // Call end epoch again
        vm.prank(heart);
        yieldRepo.execute();

        // Check that a new bond market was not created
        assertEq(aggregator.marketCounter(), nextBondMarketId);

        // Check that the treasury balance has not changed
        assertEq(sReserve.balanceOf(address(TRSRY)), trsryBalance);

        // Check that the yieldRepo contract reserve balance has not changed
        assertEq(reserve.balanceOf(address(yieldRepo)), yieldRepoReserveBalance);
        assertEq(sReserve.balanceOf(address(yieldRepo)), yieldRepoWrappedReserveBalance);

        // Check that the epoch has been incremented
        assertEq(yieldRepo.epoch(), 1);
    }

    function test_endEpoch_divisBy3_notEpochLength() public {
        // V2 DIFFERENCE: the daily cycle only runs when the oracle price is at or above the
        // backing (11.33e18), so the price is raised for this test. V1 ran it at the default
        // price of 10e18.
        PRICE.setLastPrice(15 * 1e18);

        // Mint yield to the sReserve
        _mintYield();

        // Make the initial call to get the epoch counter to reset
        vm.prank(heart);
        yieldRepo.execute();

        // Call end epoch twice to setup our test
        vm.prank(heart);
        yieldRepo.execute();
        vm.prank(heart);
        yieldRepo.execute();

        // Confirm that the epoch is 2
        assertEq(yieldRepo.epoch(), 2);

        // Cache the yieldRepo contract reserve balance before any bonds are issued
        uint256 yieldRepoReserveBalance = reserve.balanceOf(address(yieldRepo));
        uint256 yieldRepoWrappedReserveBalance = sReserve.balanceOf(address(yieldRepo));

        // Purchase a bond from the existing bond market
        // So that there is some OHM in the contract to burn
        // At a price of 15e18 the payout per OHM is higher than in V1 (10e18), so the purchase
        // amount is reduced from 100e9 to 90e9 to stay below the market maxPayout
        uint256 ohmPurchaseAmount = 90e9;
        vm.prank(alice);
        (uint256 bondPayout, ) = teller.purchase(alice, address(0), 0, ohmPurchaseAmount, 0);

        // Confirm that the yieldRepo balance is updated with the bond payout
        assertEq(reserve.balanceOf(address(yieldRepo)), yieldRepoReserveBalance - bondPayout);
        yieldRepoReserveBalance -= bondPayout;

        // Warp forward a day so that the initial bond market ends
        vm.warp(block.timestamp + 1 days);

        // Mint yield to the sReserve
        _mintYield();

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Cache the TRSRY sDAI balance
        uint256 trsryBalance = sReserve.balanceOf(address(TRSRY));

        // Cache the OHM balance in the yieldRepo contract
        uint256 yieldRepoOhmBalance = ohm.balanceOf(address(yieldRepo));
        assertEq(yieldRepoOhmBalance, ohmPurchaseAmount);

        // Call end epoch again
        vm.prank(heart);
        yieldRepo.execute();

        // Check that a new bond market was created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId + 1,
            "bond market id should be incremented"
        );

        // Check that the yieldRepo contract burned the OHM
        assertEq(ohm.balanceOf(address(yieldRepo)), 0, "OHM should be burned");

        // Check that the treasury balance has changed by the amount of backing withdrawn for the burnt OHM
        // V1: 90e9 (9 decimals) * 1133e7 = 1019.7e18
        // V2: 90e9 (9 decimals) * 1133e16 (18 decimals) / 1e9 = 1019.7e18 -- the same value
        uint256 reserveFromBurnedOhm = (ohmPurchaseAmount * backingPerToken) / 1e9;
        assertEq(
            sReserve.balanceOf(address(TRSRY)),
            trsryBalance - sReserve.previewWithdraw(reserveFromBurnedOhm),
            "treasury balance should decrease by the amount of backing withdrawn for the burnt OHM"
        );

        // Check that the balance of the yieldRepo contract has changed correctly
        // V2 DIFFERENCE: the daily bid amount is derived from the weeklyBudgetRemaining counter
        // (initialYield - bond purchases + withdrawn backing), not from the actual token
        // holdings. The intra-week appreciation of the held wrapped reserves (_mintYield above)
        // is therefore NOT included in the bid amount until the next weekly reset.
        // V1 formula (based on actual holdings, includes the appreciation):
        // uint256 expectedBidAmount = (yieldRepoReserveBalance +
        //     sReserve.previewRedeem(yieldRepoWrappedReserveBalance) +
        //     reserveFromBurnedOhm) / 6;
        // Reconciled to the wei: V1 bid = 9888449084249084247654, V2 bid = 9887597435897435896006.
        // The numerator difference of 5109890109890109889 decomposes into:
        // - +5109890109890109890: the held shares' pro rata part of the 0.01% vault yield
        //   minted above (heldShares * mintedYield / totalSupply); V1 re-marks the held shares
        //   at the current conversion rate every day, the V2 counter does not.
        // - -1: previewRedeem floor rounding when V1 values the held shares.
        // The day-0 redeem and the backing previewWithdraw/previewRedeem roundtrips are exact
        // in this scenario and contribute nothing. The appreciation is not lost in V2: it is
        // picked up by the poolValue sync in _weeklyReset() at the start of the next week.
        uint256 backingReceived = sReserve.previewRedeem(
            sReserve.previewWithdraw(reserveFromBurnedOhm)
        );
        uint256 expectedBidAmount = (initialYield - bondPayout + backingReceived) / 6;

        // Check that the yieldRepo contract reserve balances have changed correctly
        assertEq(
            reserve.balanceOf(address(yieldRepo)),
            expectedBidAmount,
            "reserve balance should increase by the bid amount"
        );
        assertGe(
            sReserve.balanceOf(address(yieldRepo)),
            yieldRepoWrappedReserveBalance - sReserve.previewWithdraw(expectedBidAmount),
            "wrapped reserve balance should decrease by the bid amount"
        );

        // Confirm that the bond market has the correct configuration
        {
            uint256 marketPrice = auctioneer.marketPrice(nextBondMarketId);
            (
                ,
                ,
                ,
                ,
                ,
                uint256 capacity,
                ,
                uint256 minPrice,
                uint256 maxPayout,
                ,
                ,
                uint256 scale
            ) = auctioneer.markets(nextBondMarketId);

            assertEq(capacity, expectedBidAmount, "capacity should be the bid amount");
            assertEq(maxPayout, capacity / 6, "max payout should be 1/6th of the capacity");

            // See test_endEpoch_firstCall_currentGreaterThanBacking for the price derivation
            assertEq(scale, 10 ** uint8(36 + 18 - 9 - 1), "scale");
            assertEq(
                marketPrice,
                ((uint256(1e36) / ((15e18 * 97) / 100)) * 10 ** uint8(36 + 1)) /
                    10 ** uint8(18 + 2),
                "marketPrice"
            );
            // V2 DIFFERENCE: V1 set no price floor (minPrice == 0)
            assertEq(
                minPrice,
                ((uint256(1e36) / uint256(15e18)) * 10 ** uint8(36 + 1)) / 10 ** uint8(18 + 2),
                "minPrice"
            );
        }
    }

    function test_adjustNextYield() public {
        // Mint yield to the sReserve
        _mintYield();

        // Call endEpoch to set the next yield
        vm.prank(heart);
        yieldRepo.execute();

        // Get the next yield value
        uint256 nextYield = yieldRepo.getAssetConfig(address(sReserve)).nextYield;

        // Try to call adjustNextYield with an invalid caller
        // Expect it to fail
        // V2 DIFFERENCE: the function is gated by the manager-or-admin modifier, which reverts
        // with NotAuthorised() instead of ROLES_RequireRole("admin")
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(alice);
        yieldRepo.adjustNextYield(address(sReserve), nextYield);

        // Call adjustNextYield with a value that is too high
        // Expect it to fail
        uint256 newNextYield = (nextYield * 12) / 10;

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_TooMuchIncrease.selector
            )
        );
        vm.prank(guardian);
        yieldRepo.adjustNextYield(address(sReserve), newNextYield);

        // Call adjustNextYield with a value greater than the current yield but only by 10%
        // Expect it to succeed
        newNextYield = (nextYield * 11) / 10;
        vm.prank(guardian);
        yieldRepo.adjustNextYield(address(sReserve), newNextYield);

        // Check that the next yield has been adjusted
        assertEq(yieldRepo.getAssetConfig(address(sReserve)).nextYield, newNextYield);

        // Call adjustNextYield with a value that is lower than the current yield
        // Expect it to succeed
        newNextYield = (newNextYield * 9) / 10;
        vm.prank(guardian);
        yieldRepo.adjustNextYield(address(sReserve), newNextYield);

        // Check that the next yield has been adjusted
        assertEq(yieldRepo.getAssetConfig(address(sReserve)).nextYield, newNextYield);

        // Call adjustNextYield with a value of zero next yield
        // Expect it to succeed
        vm.prank(guardian);
        yieldRepo.adjustNextYield(address(sReserve), 0);

        // Check that the next yield has been adjusted
        assertEq(yieldRepo.getAssetConfig(address(sReserve)).nextYield, 0);
    }

    function test_shutdown() public {
        // Try to call shutdown as an invalid caller
        // Expect it to fail
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(alice);
        yieldRepo.disable("");

        // Mint yield
        _mintYield();

        // Call endEpoch initially to get tokens into the contract
        vm.prank(heart);
        yieldRepo.execute();

        // Cache the yieldRepo contract reserve balances
        uint256 yieldRepoReserveBalance = reserve.balanceOf(address(yieldRepo));
        uint256 yieldRepoWrappedReserveBalance = sReserve.balanceOf(address(yieldRepo));

        // Cache the treasury balances of the reserve tokens
        uint256 trsryReserveBalance = reserve.balanceOf(address(TRSRY));
        uint256 trsryWrappedReserveBalance = sReserve.balanceOf(address(TRSRY));

        // Call shutdown with an invalid caller
        // Expect it to fail
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(bob);
        yieldRepo.disable("");

        // Call shutdown with a valid caller
        // Expect it to succeed
        // V2 DIFFERENCE: the registered vault/reserve balances are transferred to the TRSRY
        // automatically, the payload with the token list is no longer used
        vm.prank(guardian);
        yieldRepo.disable("");

        // Check that the contract is shutdown
        assertEq(yieldRepo.isEnabled(), false);

        // Check that the yieldRepo contract reserve balances have been transferred to the TRSRY
        assertEq(reserve.balanceOf(address(yieldRepo)), 0);
        assertEq(sReserve.balanceOf(address(yieldRepo)), 0);
        assertEq(reserve.balanceOf(address(TRSRY)), trsryReserveBalance + yieldRepoReserveBalance);
        assertEq(
            sReserve.balanceOf(address(TRSRY)),
            trsryWrappedReserveBalance + yieldRepoWrappedReserveBalance
        );
    }

    function test_getReserveBalance() public {
        // Mint yield
        _mintYield();

        // Call endEpoch initially to get tokens into the contract
        vm.prank(heart);
        yieldRepo.execute();

        // Cache yield earning balances in the clearinghouse and treasury
        uint256 clearinghouseWrappedReserveBalance = sReserve.balanceOf(address(clearinghouse));
        uint256 trsryWrappedReserveBalance = sReserve.balanceOf(address(TRSRY));

        // Calculate the expected yield earning reserve balance, in reserves
        uint256 expectedYieldEarningReserveBalance = sReserve.previewRedeem(
            clearinghouseWrappedReserveBalance + trsryWrappedReserveBalance
        );

        // Confirm the view function matches
        assertEq(
            yieldRepo.getReserveBalance(address(sReserve)),
            expectedYieldEarningReserveBalance
        );

        // Add new active clearinghouse and mint it some reserves
        MockClearinghouse newClearinghouse = new MockClearinghouse(
            address(reserve),
            address(sReserve)
        );
        reserve.mint(address(newClearinghouse), 1_000_000e18);
        vm.startPrank(address(newClearinghouse));
        reserve.approve(address(sReserve), 1_000_000e18);
        sReserve.deposit(1_000_000e18, address(newClearinghouse));
        vm.stopPrank();

        // Register the new clearinghouse
        godmode = CHREG.generateGodmodeFixture(type(OlympusClearinghouseRegistry).name);
        kernel.executeAction(Actions.ActivatePolicy, godmode);
        vm.prank(godmode);
        CHREG.activateClearinghouse(address(newClearinghouse));

        // Get the total yield earning balance with the new clearinghouse included
        uint256 totalWrappedReserveBalance = clearinghouseWrappedReserveBalance +
            trsryWrappedReserveBalance +
            sReserve.balanceOf(address(newClearinghouse));

        // Calculate the expected yield earning reserve balance, in reserves
        expectedYieldEarningReserveBalance = sReserve.previewRedeem(totalWrappedReserveBalance);

        // Confirm the view function matches
        assertEq(
            yieldRepo.getReserveBalance(address(sReserve)),
            expectedYieldEarningReserveBalance
        );
    }

    function test_getNextYield() public {
        // Mint yield
        _mintYield();

        // Call endEpoch initially to get tokens into the contract
        vm.prank(heart);
        yieldRepo.execute();

        // Get the "last values" from the yieldRepo contract
        uint256 lastReserveBalance = yieldRepo.getAssetConfig(address(sReserve)).lastReserveBalance;

        // Get the principal receivables from the clearinghouse
        uint256 principalReceivables = clearinghouse.principalReceivables();

        // Mint additional yield to the sReserve
        _mintYield();

        // Calculate the expected next yield
        uint256 expectedNextYield = lastReserveBalance /
            10000 +
            (principalReceivables * 5) /
            1000 /
            52;

        // Confirm the view function matches
        assertEq(yieldRepo.getNextYield(address(sReserve)), expectedNextYield);

        // Add new active clearinghouse and mint it some reserves
        MockClearinghouse newClearinghouse = new MockClearinghouse(
            address(reserve),
            address(sReserve)
        );
        newClearinghouse.setPrincipalReceivables(1_000_000e18);

        // Register the new clearinghouse
        godmode = CHREG.generateGodmodeFixture(type(OlympusClearinghouseRegistry).name);
        kernel.executeAction(Actions.ActivatePolicy, godmode);
        vm.prank(godmode);
        CHREG.activateClearinghouse(address(newClearinghouse));

        // Recalculate the expected next yield
        expectedNextYield =
            lastReserveBalance /
            10000 +
            ((clearinghouse.principalReceivables() + newClearinghouse.principalReceivables()) * 5) /
            1000 /
            52;

        // Confirm the view function matches
        assertEq(yieldRepo.getNextYield(address(sReserve)), expectedNextYield);

        // Deactivate the old clearinghouse, ensure its receivables are still included
        vm.prank(godmode);
        CHREG.deactivateClearinghouse(address(clearinghouse));

        // Confirm the view function matches
        assertEq(yieldRepo.getNextYield(address(sReserve)), expectedNextYield);
    }
}
