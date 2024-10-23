// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {BondFixedTermSDA} from "test/lib/bonds/BondFixedTermSDA.sol";
import {BondAggregator} from "test/lib/bonds/BondAggregator.sol";
import {BondFixedTermTeller} from "test/lib/bonds/BondFixedTermTeller.sol";
import {RolesAuthority, Authority as SolmateAuthority} from "solmate/auth/authorities/RolesAuthority.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626, ERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {MockPrice} from "test/mocks/MockPrice.sol";
import {MockOhm} from "test/mocks/MockOhm.sol";
import {MockGohm} from "test/mocks/MockGohm.sol";
import {MockClearinghouse} from "test/mocks/MockClearinghouse.sol";

import {IBondSDA} from "interfaces/IBondSDA.sol";
import {IBondAggregator} from "interfaces/IBondAggregator.sol";

import {FullMath} from "libraries/FullMath.sol";

import "src/Kernel.sol";
import {OlympusRange} from "modules/RANGE/OlympusRange.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {OlympusClearinghouseRegistry} from "modules/CHREG/OlympusClearinghouseRegistry.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {EmissionManager} from "policies/EmissionManager.sol";

// solhint-disable-next-line max-states-count
contract EmissionManagerTest is Test {
    using FullMath for uint256;

    UserFactory public userCreator;
    address internal alice;
    address internal bob;
    address internal heart;
    address internal guardian;

    RolesAuthority internal auth;
    BondAggregator internal aggregator;
    BondFixedTermTeller internal teller;
    BondFixedTermSDA internal auctioneer;
    MockOhm internal ohm;
    MockGohm internal gohm;
    MockERC20 internal reserve;
    MockERC4626 internal wrappedReserve;

    Kernel internal kernel;
    MockPrice internal PRICE;
    OlympusRange internal RANGE;
    OlympusTreasury internal TRSRY;
    OlympusMinter internal MINTR;
    OlympusRoles internal ROLES;
    OlympusClearinghouseRegistry internal CHREG;

    MockClearinghouse internal clearinghouse;
    RolesAdmin internal rolesAdmin;
    EmissionManager internal emissionManager;

    // Emission manager values
    uint256 internal baseEmissionsRate = 1e6; // 0.1% at minimum premium
    uint256 internal minimumPremium = 125e16; // 125% -> 25% premium
    uint256 internal backing = 10e18;
    uint48 internal restartTimeframe = 1 days;

    // test cases
    //
    // core functionality
    // [ ] execute
    //   [X] when not locally active
    //     [X] it returns without doing anything
    //   [ ] when locally active
    //     [X] it increments the beat counter modulo 3
    //     [X] when beatCounter is incremented and != 0
    //        [X] it returns without doing anything
    //     [ ] when beatCounter is incremented and == 0
    //        [ ] when current OHM balance is not zero
    //           [ ] it reduces supply added from the last sale
    //        [ ] when current DAI balance is not zero
    //           [ ] it increments the reserves added from the last sale
    //           [ ] it deposits the DAI into sDAI and sends it to the treasury
    //           [ ] it updates the backing price value based on the reserves added and supply added values from the last sale
    //        [ ] when sell amount is greater than current OHM balance
    //           [ ] it mints the difference between the sell amount and the current OHM balance to the contract
    //        [ ] when sell amount is less than current OHM balance
    //           [ ] it burns the difference between the current OHM balance and the sell amount from the contract
    //        [ ] when the current balance equals the sell amount
    //           [ ] it does not mint or burn OHM
    //        [ ] when sell amount is not zero
    //           [ ] it creates a new bond market with the sell amount
    //        [ ] when sell amount is zero
    //           [ ] it does not create a new bond market
    //        [ ] when there is a postitive emissions adjustment
    //           [ ] it adjusts the emissions rate by the adjustment amount before calculating the sell amount
    //        [ ] when there is a negative emissions adjustment
    //           [ ] it adjusts the emissions rate by the adjustment amount before calculating the sell amount
    //        [ ] when the num of previous sales is greater than zero
    //           [ ] it updates the supply added from the last sale based by subtracting any remaining OHM
    //
    //
    // view functions
    // [ ] getSupply
    // [ ] getReseves
    //
    // emergency functions
    // [ ] shutdown
    // [ ] restart
    //
    // admin functions
    // [ ] initialize
    // [ ] setBaseRate
    // [ ] setMinimumPremium
    // [ ] adjustBacking
    // [ ] adjustRestartTimeframe
    // [ ] updateBondContracts

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            /// Deploy bond system to test against
            address[] memory users = userCreator.create(4);
            alice = users[0];
            bob = users[1];
            guardian = users[2];
            heart = users[3];
            auth = new RolesAuthority(guardian, SolmateAuthority(address(0)));

            /// Deploy the bond system
            aggregator = new BondAggregator(guardian, auth);
            teller = new BondFixedTermTeller(guardian, aggregator, guardian, auth);
            auctioneer = new BondFixedTermSDA(teller, aggregator, guardian, auth);

            /// Register auctioneer on the bond system
            vm.prank(guardian);
            aggregator.registerAuctioneer(auctioneer);
        }

        {
            /// Deploy mock tokens
            ohm = new MockOhm("Olympus", "OHM", 9);
            gohm = new MockGohm("Gohm", "gOHM", 18);
            reserve = new MockERC20("Reserve", "RSV", 18);
            wrappedReserve = new MockERC4626(reserve, "wrappedReserve", "sRSV");
        }

        {
            /// Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy mock clearinghouse
            clearinghouse = new MockClearinghouse(address(reserve), address(wrappedReserve));

            /// Deploy modules (some mocks)
            PRICE = new MockPrice(kernel, uint48(8 hours), 10 * 1e18);
            CHREG = new OlympusClearinghouseRegistry(
                kernel,
                address(clearinghouse),
                new address[](0)
            );
            TRSRY = new OlympusTreasury(kernel);
            MINTR = new OlympusMinter(kernel, address(ohm));
            ROLES = new OlympusRoles(kernel);

            /// Configure mocks
            PRICE.setMovingAverage(13 * 1e18);
            PRICE.setLastPrice(15 * 1e18); //
            PRICE.setDecimals(18);
            PRICE.setLastTime(uint48(block.timestamp));

            /// Deploy ROLES administrator
            rolesAdmin = new RolesAdmin(kernel);

            // Deploy the emission manager
            emissionManager = new EmissionManager(
                kernel,
                address(ohm),
                address(gohm),
                address(reserve),
                address(wrappedReserve),
                address(auctioneer),
                address(teller)
            );
        }

        {
            /// Initialize system and kernel

            /// Install modules
            kernel.executeAction(Actions.InstallModule, address(PRICE));
            kernel.executeAction(Actions.InstallModule, address(CHREG));
            kernel.executeAction(Actions.InstallModule, address(TRSRY));
            kernel.executeAction(Actions.InstallModule, address(MINTR));
            kernel.executeAction(Actions.InstallModule, address(ROLES));

            /// Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(emissionManager));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }
        {
            /// Configure access control

            // Emission manager roles
            rolesAdmin.grantRole("heart", heart);
            rolesAdmin.grantRole("emissions_admin", guardian);

            // Emergency roles
            rolesAdmin.grantRole("emergency_shutdown", guardian);
            rolesAdmin.grantRole("emergency_restart", guardian);
        }

        // Mint gOHM supply to test against
        // Index is 10,000, therefore a total supply of 10,000 gOHM = 10,000,000 OHM
        gohm.mint(address(this), 10_000 * 1e18);

        // Mint tokens to users, clearinghouse, and TRSRY for testing
        uint256 testReserve = 1_000_000 * 1e18;

        reserve.mint(alice, testReserve);
        reserve.mint(address(TRSRY), testReserve * 50); // $50M of reserves in TRSRY

        // Deposit TRSRY reserves into wrappedReserve
        vm.startPrank(address(TRSRY));
        reserve.approve(address(wrappedReserve), testReserve * 50);
        wrappedReserve.deposit(testReserve * 50, address(TRSRY));
        vm.stopPrank();

        // Approve the bond teller for the tokens to swap
        vm.prank(alice);
        reserve.approve(address(teller), testReserve);

        // Set principal receivables for the clearinghouse to $50M
        clearinghouse.setPrincipalReceivables(uint256(50 * testReserve));

        // Initialize the emissions manager
        vm.prank(guardian);
        emissionManager.initialize(baseEmissionsRate, minimumPremium, backing, restartTimeframe);

        // Total Reserves = $50M + $50 M = $100M
        // Total Supply = 10,000,000 OHM
        // => Backing = $100M / 10,000,000 OHM = $10 / OHM
        // Price is set at $15 / OHM, so a 50% premium, which is above the 25% minimum premium

        // Emissions Rate is initially set to
    }

    // execute test cases

    function test_execute_whenNotLocallyActive_NothingHappens() public {
        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Execute twice to get beat counter to 2
        vm.startPrank(heart);
        emissionManager.execute();
        emissionManager.execute();
        vm.stopPrank();

        // Check the beat counter is 2
        assertEq(emissionManager.beatCounter(), 2, "Beat counter should be 2");

        // Check that a bond market was not created
        assertEq(aggregator.marketCounter(), nextBondMarketId);

        // Check that the contract is locally active
        assertTrue(emissionManager.locallyActive(), "Contract should be locally active");

        // Deactivate the emission manager
        vm.prank(guardian);
        emissionManager.shutdown();

        // Check that the contract is not locally active
        assertFalse(emissionManager.locallyActive(), "Contract should not be locally active");

        // Execute the emission manager
        vm.startPrank(heart);
        emissionManager.execute();

        // Check that a bond market was not created
        assertEq(aggregator.marketCounter(), nextBondMarketId);

        // Check that the beat counter did not increment
        assertEq(emissionManager.beatCounter(), 2, "Beat counter should be 2");
    }

    function test_execute_incrementsBeatCounterModulo3() public {
        // Beat counter should be 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");

        // Execute once to get beat counter to 1
        vm.startPrank(heart);
        emissionManager.execute();

        // Check that the beat counter is 1
        assertEq(emissionManager.beatCounter(), 1, "Beat counter should be 1");

        // Execute again to get beat counter to 2
        vm.startPrank(heart);
        emissionManager.execute();

        // Check that the beat counter is 2
        assertEq(emissionManager.beatCounter(), 2, "Beat counter should be 2");

        // Execute again to get beat counter to 0 (wraps around)
        vm.startPrank(heart);
        emissionManager.execute();

        // Check that the beat counter is 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");
    }

    function test_execute_whenBeatCounterNot0_incrementsCounter() public {
        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Check that the beat counter is initially 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");

        // Execute once to get beat counter to 1
        vm.startPrank(heart);
        emissionManager.execute();

        // Check that a bond market was not created
        assertEq(aggregator.marketCounter(), nextBondMarketId);

        // Check the beat counter is 1
        assertEq(emissionManager.beatCounter(), 1, "Beat counter should be 1");

        // Execute the emission manager
        vm.startPrank(heart);
        emissionManager.execute();

        // Check that a bond market was not created
        assertEq(aggregator.marketCounter(), nextBondMarketId);

        // Check that the beat counter is now 2
        assertEq(emissionManager.beatCounter(), 2, "Beat counter should be 2");
    }

    function test_execute_whenBeatCounterIs0_whenSellAmountZero_noAdjustment_noBalances_noSales()
        public
    {
        // Call execute twice to get beat counter to 2
        vm.startPrank(heart);
        emissionManager.execute();
        emissionManager.execute();
        vm.stopPrank();

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Set the price below the minumum premium
        PRICE.setLastPrice(12 * 1e18);

        // Confirm that there are no tokens in the contract yet
        assertEq(ohm.balanceOf(address(emissionManager)), 0, "OHM balance should be 0");
        assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

        // Check that the beat counter is 2
        assertEq(emissionManager.beatCounter(), 2, "Beat counter should be 2");

        // Call execute
        vm.prank(heart);
        emissionManager.execute();

        // Check that a bond market was not created
        assertEq(aggregator.marketCounter(), nextBondMarketId);

        // Confirm that the token balances are still 0
        assertEq(ohm.balanceOf(address(emissionManager)), 0, "OHM balance should be 0");
        assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

        // Confirm that the beat counter is now 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");
    }

    function test_execute_whenBeatCounterIs0_whenSellAmountZero_noAdjustment_ohmBalance_noSales()
        public
    {
        // Call execute twice to get beat counter to 2
        vm.startPrank(heart);
        emissionManager.execute();
        emissionManager.execute();
        vm.stopPrank();

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Set the price below the minumum premium
        PRICE.setLastPrice(12 * 1e18);

        // Mint a small amount of OHM to the emissions manager
        ohm.mint(address(emissionManager), 100e9);
        uint256 ohmSupply = ohm.balanceOf(address(emissionManager));

        // Confirm that there are no tokens in the contract yet
        assertEq(ohm.balanceOf(address(emissionManager)), 100e9, "OHM balance should be 100e9");
        assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

        // Check that the beat counter is 2
        assertEq(emissionManager.beatCounter(), 2, "Beat counter should be 2");

        // Call execute
        vm.prank(heart);
        emissionManager.execute();

        // Check that a bond market was not created
        assertEq(aggregator.marketCounter(), nextBondMarketId);

        // Confirm that the token balances are now zero.
        assertEq(ohm.balanceOf(address(emissionManager)), 0, "OHM balance should be 0");
        assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

        // Confirm that the ohm was burned
        assertEq(
            ohm.totalSupply(),
            ohmSupply - 100e9,
            "OHM total supply should be reduced by 100e9"
        );

        // Confirm that the beat counter is now 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");
    }

    function test_execute_whenBeatCounterIs0_whenSellAmountNotZero_noAdjustment_noBalances()
        public
    {
        // Call execute twice to get beat counter to 2
        vm.startPrank(heart);
        emissionManager.execute();
        emissionManager.execute();
        vm.stopPrank();

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Confirm that there are no tokens in the contract yet
        assertEq(ohm.balanceOf(address(emissionManager)), 0, "OHM balance should be 0");
        assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

        // Check that the beat counter is 2
        assertEq(emissionManager.beatCounter(), 2, "Beat counter should be 2");

        // Call execute
        vm.prank(heart);
        emissionManager.execute();

        // Check that a bond market was created
        assertEq(aggregator.marketCounter(), nextBondMarketId + 1);

        // Confirm that the beat counter is now 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");

        // Verify the bond market parameters
        // Check that the market params are correct
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

            assertEq(owner, address(emissionManager), "Owner");
            assertEq(address(payoutToken), address(ohm), "Payout token");
            assertEq(address(quoteToken), address(reserve), "Quote token");
            assertEq(callbackAddr, address(0), "Callback address");
            assertEq(isCapacityInQuote, false, "Capacity should not be in quote token");
            assertEq(
                capacity,
                (((baseEmissionsRate * PRICE.getLastPrice()) /
                    ((backing * minimumPremium) / 1e18)) *
                    gohm.totalSupply() *
                    gohm.index()) / 1e18,
                "Capacity"
            );
            assertEq(maxPayout, capacity / 6, "Max payout");

            assertEq(scale, 10 ** uint8(36 + 9 - 18 + 0), "Scale");
            assertEq(
                marketPrice,
                (PRICE.getLastPrice() * 10 ** uint8(36 - 1)) / 10 ** uint8(18 - 1),
                "Market price"
            );
            assertEq(
                minPrice,
                (((backing * minimumPremium) / 1e18) * 10 ** uint8(36 - 1)) / 10 ** uint8(18 - 1),
                "Min price"
            );

            // Confirm token balances are updated correctly
            assertEq(
                ohm.balanceOf(address(emissionManager)),
                capacity,
                "OHM balance should be the capacity"
            );
            assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");
        }
    }
    /*
    function test_execute_whenBeatCounterIs0_withPreviousSale_reducesSupplyAdded() public {
        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Set up scenario where we have a previous sale
        // Execute three times to complete one cycle and create a market
        vm.startPrank(heart);
        emissionManager.execute();
        emissionManager.execute();
        emissionManager.execute();
        vm.stopPrank();

        // Check that a bond market was created
        assertEq(aggregator.marketCounter(), nextBondMarketId + 1);

        // Get information about the first sale
        (, , uint256 originalCapacity, ) = emissionManager.sales(0);
        console2.log(originalCapacity);

        // Get supply at this point
        uint256 originalTotalSupply = ohm.totalSupply();
        console2.log(originalTotalSupply);

        // Buy an amount of token from the bond market
        uint256 bidAmount = 1000e18;
        reserve.mint(alice, bidAmount);

        vm.startPrank(alice);
        reserve.approve(address(teller), bidAmount);
        teller.purchase(alice, address(0), nextBondMarketId, bidAmount, 0);
        vm.stopPrank();

        // Execute three more times to trigger another cycle
        vm.startPrank(heart);
        emissionManager.execute();
        emissionManager.execute();
        emissionManager.execute();
        vm.stopPrank();

        // Get the updated sale information
        (, , uint256 updatedCapacity, ) = emissionManager.sales(1);
        console2.log(updatedCapacity);

        // Get the new total supply
        uint256 updatedTotalSupply = ohm.totalSupply();
        console2.log(updatedTotalSupply);

        // Verify that the supply added was reduced by the leftover amount
        // In other words, only the difference from market 1 to market 2 capacity was minted
        assertEq(
            updatedTotalSupply - originalTotalSupply,
            updatedCapacity - originalCapacity,
            "Supply minted should be difference in capacities"
        );
    }
*/
    function test_execute_whenBeatCounterIs0_depositsDaiToTreasuryAsSDai() public {
        // Call execute twice to get beat counter to 2
        vm.startPrank(heart);
        emissionManager.execute();
        emissionManager.execute();
        vm.stopPrank();

        // Set the price above the minumum premium
        PRICE.setLastPrice(120 * 1e18);

        // Get initial treasury sDAI balance
        uint256 initialTreasurySdaiBalance = wrappedReserve.balanceOf(address(TRSRY));

        // Send some DAI to the emissions manager
        uint256 daiAmount = 1000e18;
        reserve.mint(address(emissionManager), daiAmount);

        // Confirm initial balances
        assertEq(
            reserve.balanceOf(address(emissionManager)),
            daiAmount,
            "Initial DAI balance should be correct"
        );
        assertEq(
            wrappedReserve.balanceOf(address(TRSRY)),
            initialTreasurySdaiBalance,
            "Initial treasury sDAI balance should be unchanged"
        );

        uint256 sdaiAmount = wrappedReserve.previewDeposit(daiAmount);

        // Execute
        vm.prank(heart);
        emissionManager.execute();

        // Verify DAI was converted to sDAI and sent to treasury
        assertEq(
            reserve.balanceOf(address(emissionManager)),
            0,
            "Emissions manager should have no DAI left"
        );
        assertEq(
            wrappedReserve.balanceOf(address(TRSRY)),
            initialTreasurySdaiBalance + sdaiAmount,
            "Treasury should have received the sDAI"
        );
    }
}
