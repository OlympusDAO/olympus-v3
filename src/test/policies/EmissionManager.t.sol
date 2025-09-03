// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "src/test/lib/UserFactory.sol";

import {BondFixedTermSDA} from "src/test/lib/bonds/BondFixedTermSDA.sol";
import {BondAggregator} from "src/test/lib/bonds/BondAggregator.sol";
import {BondFixedTermTeller} from "src/test/lib/bonds/BondFixedTermTeller.sol";
import {RolesAuthority, Authority as SolmateAuthority} from "@solmate-6.2.0/auth/authorities/RolesAuthority.sol";

import {MockERC20, ERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";
import {MockPrice} from "src/test/mocks/MockPrice.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockGohm} from "src/test/mocks/MockGohm.sol";
import {MockClearinghouse} from "src/test/mocks/MockClearinghouse.sol";
import {MockConvertibleDepositAuctioneer} from "src/test/mocks/MockConvertibleDepositAuctioneer.sol";

import {FullMath} from "libraries/FullMath.sol";

import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusRange} from "modules/RANGE/OlympusRange.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {OlympusClearinghouseRegistry} from "modules/CHREG/OlympusClearinghouseRegistry.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {EmissionManager} from "policies/EmissionManager.sol";
import {PolicyAdmin} from "policies/utils/PolicyAdmin.sol";
import {IEmissionManager} from "policies/interfaces/IEmissionManager.sol";

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
    BondFixedTermSDA internal bondAuctioneer;
    MockOhm internal ohm;
    MockGohm internal gohm;
    MockERC20 internal reserve;
    MockERC4626 internal sReserve;

    Kernel internal kernel;
    MockPrice internal PRICE;
    OlympusRange internal RANGE;
    OlympusTreasury internal TRSRY;
    OlympusMinter internal MINTR;
    OlympusRoles internal ROLES;
    OlympusClearinghouseRegistry internal CHREG;

    MockClearinghouse internal clearinghouse;
    MockConvertibleDepositAuctioneer internal cdAuctioneer;
    RolesAdmin internal rolesAdmin;
    EmissionManager internal emissionManager;

    // Emission manager values
    uint256 internal baseEmissionRate = 1e6; // 0.1% at minimum premium
    uint256 internal minimumPremium = 25e16; // 25% premium
    uint256 internal backing = 10e18;
    uint48 internal restartTimeframe = 1 days;
    uint256 internal changeBy = 1e5; // 0.01% change per execution
    uint48 internal changeDuration = 2; // 2 executions
    uint256 internal tickSize = 10e9; // 10 OHM fixed tick size
    uint256 internal minPriceScalar = 9e17; // 90%

    uint256 internal DEFICIT = 1000e9;
    uint256 internal SURPLUS = 1001e9;

    uint256 internal expectedMinPrice;

    event BondMarketCreationFailed(uint256 saleAmount);
    event TickSizeChanged(uint256 newTickSize);

    // test cases
    //
    // core functionality
    // [X] execute
    //   [X] when not enabled
    //     [X] it returns without doing anything
    //   [X] when enabled
    //     [X] given the caller does not have the "cd_emissionmanager" role
    //       [X] it reverts
    //     [X] it increments the beat counter modulo 3
    //     [X] when beatCounter is incremented and != 0
    //        [X] it returns without doing anything
    //     [X] when beatCounter is incremented and == 0
    //        [X] when premium is greater than or equal to the minimum premium
    //           [X] auction target is calculated as the base emissions rate * (1 + premium) / (1 + minimum premium)
    //           [X] when the sum of auction results is negative
    //             [X] it creates a new bond market with the deficit as the capacity
    //           [X] when the sum of auction results is positive
    //             [X] it does not create a new bond market
    //        [X] when premium is less than the minimum premium
    //           [X] when the sum of auction results is negative
    //             [X] it creates a new bond market with the deficit as the capacity
    //           [X] when the sum of auction results is positive
    //             [X] it does not create a new bond market
    //        [X] when there is a positive emissions adjustment
    //           [X] it adjusts the emissions rate by the adjustment amount before calculating the sell amount
    //           [X] when the sum of auction results is negative
    //             [X] it creates a new bond market with the deficit as the capacity
    //           [X] when the sum of auction results is positive
    //             [X] it does not create a new bond market
    //        [X] when there is a negative emissions adjustment
    //           [X] it adjusts the emissions rate by the adjustment amount before calculating the sell amount
    //           [X] when the sum of auction results is negative
    //             [X] it creates a new bond market with the deficit as the capacity
    //           [X] when the sum of auction results is positive
    //             [X] it does not create a new bond market
    //
    // [X] callback unit tests
    //    [X] when the sender is not the teller
    //       [X] it reverts
    //    [X] when the sender is the teller
    //       [X] when the id parameter is not equal to the active market id
    //          [X] it reverts
    //       [X] when the id parameter is equal to the active market id
    //          [X] when the reserve balance of the contract is not atleast the input amount
    //             [X] it reverts
    //          [X] when the reserve balance of the contract is atleast the input amount
    //             [X] it updates the backing number, using the input amount as new reserves and the output amount as new supply
    //             [X] it mints the output amount of OHM to the teller
    //             [X] it deposits the reserve balance into the sReserve contract with the TRSRY as the recipient
    //
    // [X] execute -> callback (bond market purchase test)
    //
    // view functions
    // [X] getSupply
    //    [X] returns the supply of gOHM in OHM
    // [X] getReserves
    //    [X] returns the combined balance of the TSRSY and clearinghouses
    // [X] getPremium
    //    [X] when price less than or equal to backing
    //      [X] it returns 0
    //    [X] when price is greater than backing
    //      [X] it returns the (price - backing) / backing
    // [X] getNextEmission
    //    [X] when the premium is less than the minimum premium
    //       [X] it returns the premium, 0, and 0
    //    [X] when the premium is greater than or equal to the minimum premium
    //       [X] it returns the premium, scaled emissions rate, and the emission amount for the sale
    //
    // emergency functions
    // [X] shutdown
    //    [X] when the caller doesn't have emergency_shutdown role
    //       [X] it reverts
    //    [X] when the caller has emergency_shutdown role
    //       [X] it sets locallyActive to false
    //       [X] it sets the shutdown timestamp to the current block timestamp
    //       [X] when the active market id is live
    //           [X] it closes the market
    //
    // [X] restart
    //    [X] when the caller doesn't have emergency_restart role
    //       [X] it reverts
    //    [X] when the caller has emergency_restart role
    //       [X] when the restart timeframe has elapsed since shutdown
    //          [X] it reverts
    //       [X] when the restart timeframe has not elapsed since shutdown
    //          [X] it sets locallyActive to true
    //
    // admin functions
    // [X] initialize
    //    [X] when the caller doesn't have emissions_admin role
    //       [X] it reverts
    //    [X] when the caller has emissions_admin role
    //       [X] when the contract is enabled
    //          [X] it reverts
    //       [X] when the restart timeframe has not passed since the last shutdown
    //          [X] it reverts
    //       [X] when the baseEmissionRate is zero
    //          [X] it reverts
    //       [X] when the minimumPremium is zero
    //          [X] it reverts
    //       [X] when the backing is zero
    //          [X] it reverts
    //       [X] when the restartTimeframe is zero
    //          [X] it reverts
    //       [X] it sets the baseEmissionRate
    //       [X] it sets the minimumPremium
    //       [X] it sets the backing
    //       [X] it sets the restartTimeframe
    //       [X] it sets locallyActive to true
    //
    // [X] changeBaseRate
    //    [X] when the caller doesn't have the emissions_admin role
    //       [X] it reverts
    //    [X] when the caller has the emissions_admin role
    //       [X] when a negative rate adjustment would result in an underflow
    //          [X] it reverts
    //       [X] when a positive rate adjustment would result in an overflow
    //          [X] it reverts
    //       [X] it sets the rateChange to changeBy, forNumBeats, and add parameters
    //
    // [X] setMinimumPremium
    //     [X] when the caller doesn't have the emissions_admin role
    //        [X] it reverts
    //     [X] when the caller has the emissions_admin role
    //        [X] when the new minimum premium is zero
    //           [X] it reverts
    //        [X] it sets the minimum premium
    //
    // [X] setBacking
    //    [X] when the caller doesn't have the emissions_admin role
    //       [X] it reverts
    //    [X] when the caller has the emissions_admin role
    //       [X] when the new backing is more than 10% lower than the current backing
    //          [X] it reverts
    //       [X] it sets the backing
    //
    // [X] setRestartTimeframe
    //    [X] when the caller doesn't have the emissions_admin role
    //       [X] it reverts
    //    [X] when the caller has the emissions_admin role
    //       [X] when the new restart timeframe is zero
    //          [X] it reverts
    //       [X] it sets the restart timeframe
    //
    // [X] setBondContracts
    //    [X] when the caller doesn't have the admin role
    //       [X] it reverts
    //    [X] when the caller has the admin role
    //       [X] when the new bondAuctioneer address is the zero address
    //          [X] it reverts
    //       [X] when the new teller address is the zero address
    //          [X] it reverts
    //       [X] it sets the bondAuctioneer address
    //       [X] it sets the teller address
    //
    // [X] setCDAuctionContract
    //    [X] when the caller doesn't have the admin role
    //       [X] it reverts
    //    [X] when the caller has the admin role
    //       [X] when the new CDAuctioneer address is the zero address
    //          [X] it reverts
    //       [X] when the new CDAuctioneer has a different deposit asset
    //          [X] it reverts
    //       [X] it sets the cdAuctioneer address

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
            bondAuctioneer = new BondFixedTermSDA(teller, aggregator, guardian, auth);

            /// Register bondAuctioneer on the bond system
            vm.prank(guardian);
            aggregator.registerAuctioneer(bondAuctioneer);
        }

        {
            /// Deploy mock tokens
            ohm = new MockOhm("Olympus", "OHM", 9);
            gohm = new MockGohm("Gohm", "gOHM", 18);
            reserve = new MockERC20("Reserve", "RSV", 18);
            sReserve = new MockERC4626(reserve, "sReserve", "sRSV");
        }

        {
            /// Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy mock clearinghouse
            clearinghouse = new MockClearinghouse(address(reserve), address(sReserve));

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

            // Deploy the mock CD auctioneer
            cdAuctioneer = new MockConvertibleDepositAuctioneer(kernel, address(reserve));

            // Deploy the emission manager
            emissionManager = new EmissionManager(
                kernel,
                address(ohm),
                address(gohm),
                address(reserve),
                address(sReserve),
                address(bondAuctioneer),
                address(cdAuctioneer),
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
            kernel.executeAction(Actions.ActivatePolicy, address(cdAuctioneer));
        }
        {
            /// Configure access control

            // Emission manager roles
            rolesAdmin.grantRole("heart", heart);
            rolesAdmin.grantRole("admin", guardian);

            // Emergency roles
            rolesAdmin.grantRole("emergency", guardian);
        }

        // Mint gOHM supply to test against
        // Index is 10,000, therefore a total supply of 1,000 gOHM = 10,000,000 OHM
        gohm.mint(address(this), 1_000 * 1e18);

        // Mint tokens to users, clearinghouse, and TRSRY for testing
        uint256 testReserve = 1_000_000 * 1e18;

        reserve.mint(alice, testReserve);
        reserve.mint(address(TRSRY), testReserve * 50); // $50M of reserves in TRSRY

        // Deposit TRSRY reserves into sReserve
        vm.startPrank(address(TRSRY));
        reserve.approve(address(sReserve), testReserve * 50);
        sReserve.deposit(testReserve * 50, address(TRSRY));
        vm.stopPrank();

        // Approve the bond teller for the tokens to swap
        vm.prank(alice);
        reserve.approve(address(teller), testReserve);

        // Set principal receivables for the clearinghouse to $50M
        clearinghouse.setPrincipalReceivables(uint256(50 * testReserve));

        // Enable the emissions manager
        vm.prank(guardian);
        emissionManager.enable(
            abi.encode(
                IEmissionManager.EnableParams({
                    baseEmissionsRate: baseEmissionRate,
                    minimumPremium: minimumPremium,
                    backing: backing,
                    tickSize: tickSize,
                    minPriceScalar: minPriceScalar,
                    restartTimeframe: restartTimeframe
                })
            )
        );

        // Approve the emission manager to use a bond callback on the bondAuctioneer
        vm.prank(guardian);
        bondAuctioneer.setCallbackAuthStatus(address(emissionManager), true);

        // Total Reserves = $50M + $50 M = $100M
        // Total Supply = 10,000,000 OHM
        // => Backing = $100M / 10,000,000 OHM = $10 / OHM
        // Price is set at $15 / OHM, so a 50% premium, which is above the 25% minimum premium

        // Emissions Rate is initially set to 0.1% of supply per day at the minimum premium
        // This means the capacity of the initial bond market if premium == minimum premium
        // is 0.1% * 10,000,000 OHM = 10,000 OHM
        // For the case where the premium is 50%, then the capacity is:
        // 10,000 OHM * (1 + 0.5) / (1 + 0.25) = 12,000 OHM

        // Set the current price
        // Always returned in 18 decimal scale
        // 22377897966596497241 = 22.37 reserve/OHM
        PRICE.setCurrentPrice(22377897966596497241);

        // 20140108169936847516
        expectedMinPrice = (uint256(22377897966596497241) * 9e17) / 1e18;
    }

    // internal helper functions
    modifier givenNextBeatIsZero() {
        // Execute twice to get beat counter to 2
        vm.startPrank(heart);
        emissionManager.execute();
        emissionManager.execute();
        vm.stopPrank();

        // Warp to the next day
        vm.warp(block.timestamp + 86400);
        _;
    }

    modifier givenCDAuctioneerHasDeficit() {
        int256[] memory results = new int256[](2);
        results[0] = -int256(DEFICIT) * 2;
        results[1] = int256(DEFICIT);
        cdAuctioneer.setAuctionResults(results);
        _;
    }

    modifier givenCDAuctioneerHasSurplus() {
        int256[] memory results = new int256[](2);
        results[0] = int256(SURPLUS) * 2;
        results[1] = -int256(SURPLUS);
        cdAuctioneer.setAuctionResults(results);
        _;
    }

    modifier givenCDAuctioneerHasZero() {
        int256[] memory results = new int256[](2);
        results[0] = 0;
        results[1] = 0;
        cdAuctioneer.setAuctionResults(results);
        _;
    }

    modifier givenPremiumEqualToMinimum() {
        // Set the price to be exactly 25% above the backing
        PRICE.setLastPrice(125 * 1e17);
        _;
    }

    modifier givenPremiumBelowMinimum() {
        // Set the price below the minumum premium (20%) compared to 25% minimum premium
        PRICE.setLastPrice(12 * 1e18);
        _;
    }

    modifier givenPremiumAboveMinimum() {
        // Set the price above the minumum premium (50%) compared to 25% minimum premium
        PRICE.setLastPrice(15 * 1e18);
        _;
    }

    modifier givenThereIsPreviousSale() {
        // Execute three times to complete one cycle and create a market
        triggerFullCycle();
        _;
    }

    function triggerFullCycle() internal {
        vm.startPrank(heart);
        emissionManager.execute();
        emissionManager.execute();

        // Warp to the next day
        vm.warp(block.timestamp + 86400);

        emissionManager.execute();
        vm.stopPrank();
    }

    modifier givenPositiveRateAdjustment() {
        vm.prank(guardian);
        emissionManager.changeBaseRate(changeBy, changeDuration, true);
        _;
    }

    modifier givenNegativeRateAdjustment() {
        vm.prank(guardian);
        emissionManager.changeBaseRate(changeBy, changeDuration, false);
        _;
    }

    modifier givenShutdown() {
        vm.prank(guardian);
        emissionManager.disable("");
        _;
    }

    modifier givenRestartTimeframeElapsed() {
        vm.warp(block.timestamp + restartTimeframe);
        _;
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
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Check that the contract is enabled
        assertTrue(emissionManager.isEnabled(), "Contract should be enabled");

        // Deactivate the emission manager
        vm.prank(guardian);
        emissionManager.disable("");

        // Check that the contract is not enabled
        assertFalse(emissionManager.isEnabled(), "Contract should not be enabled");

        // Execute the emission manager
        vm.startPrank(heart);
        emissionManager.execute();

        // Check that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Check that the beat counter did not increment
        assertEq(emissionManager.beatCounter(), 2, "Beat counter should be 2");
    }

    function test_execute_withoutHeartRole_reverts() public {
        // Call the function with the wrong caller
        bytes memory err = abi.encodeWithSignature("ROLES_RequireRole(bytes32)", bytes32("heart"));
        vm.expectRevert(err);

        // Call the function
        vm.startPrank(guardian);
        emissionManager.execute();
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

    function test_execute_whenNextBeatNotZero_incrementsCounter() public {
        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Check that the beat counter is initially 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");

        // Execute once to get beat counter to 1
        vm.startPrank(heart);
        emissionManager.execute();

        // Check that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Check the beat counter is 1
        assertEq(emissionManager.beatCounter(), 1, "Beat counter should be 1");

        // Execute the emission manager
        vm.startPrank(heart);
        emissionManager.execute();

        // Check that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Check that the beat counter is now 2
        assertEq(emissionManager.beatCounter(), 2, "Beat counter should be 2");
    }

    function test_execute_whenNextBeatIsZero_whenPremiumBelowMinimum_whenNoAdjustment()
        public
        givenNextBeatIsZero
        givenPremiumBelowMinimum
    {
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

        // Check that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");

            assertEq(emission, 0, "target should be zero");
            assertEq(cdAuctioneer.tickSize(), 0, "tick size should be zero");
        }

        // Confirm that the token balances are still 0
        assertEq(ohm.balanceOf(address(emissionManager)), 0, "OHM balance should be 0");
        assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

        // Confirm that the beat counter is now 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");

        // The pending capacity should be 0
        assertEq(emissionManager.bondMarketPendingCapacity(), 0, "pending capacity");
    }

    function test_execute_whenNextBeatIsZero_whenPremiumBelowMinimum_whenNoAdjustment_surplus()
        public
        givenNextBeatIsZero
        givenPremiumBelowMinimum
        givenCDAuctioneerHasSurplus
    {
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

        // Check that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // Confirm that the token balances are still 0
        assertEq(ohm.balanceOf(address(emissionManager)), 0, "OHM balance should be 0");
        assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

        // Confirm that the beat counter is now 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");

        // The pending capacity should be 0
        assertEq(emissionManager.bondMarketPendingCapacity(), 0, "pending capacity");
    }

    function test_execute_whenNextBeatIsZero_whenPremiumBelowMinimum_whenNoAdjustment_noSurplus()
        public
        givenNextBeatIsZero
        givenPremiumBelowMinimum
        givenCDAuctioneerHasZero
    {
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

        // Check that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // Confirm that the token balances are still 0
        assertEq(ohm.balanceOf(address(emissionManager)), 0, "OHM balance should be 0");
        assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

        // Confirm that the beat counter is now 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");

        // The pending capacity should be 0
        assertEq(emissionManager.bondMarketPendingCapacity(), 0, "pending capacity");
    }

    function test_execute_givenDifferentReserveDecimals() public givenPremiumBelowMinimum {
        // Create a reserve asset with different decimal scale
        reserve = new MockERC20("newReserve", "NR", 6);
        sReserve = new MockERC4626(reserve, "sNewReserve", "sNR");

        // Set up a new CDAuctioneer
        cdAuctioneer = new MockConvertibleDepositAuctioneer(kernel, address(reserve));

        // Set up an EmissionManager with a different deposit asset
        emissionManager = new EmissionManager(
            kernel,
            address(ohm),
            address(gohm),
            address(reserve),
            address(sReserve),
            address(bondAuctioneer),
            address(cdAuctioneer),
            address(teller)
        );

        // Initialise system
        {
            kernel.executeAction(Actions.ActivatePolicy, address(emissionManager));
            kernel.executeAction(Actions.ActivatePolicy, address(cdAuctioneer));
        }

        // Configure price
        {
            // 22377897966596497241 = 22.37 reserve/OHM
            PRICE.setCurrentPrice(22377897966596497241);
        }

        // Enable the emissions manager
        vm.prank(guardian);
        emissionManager.enable(
            abi.encode(
                IEmissionManager.EnableParams({
                    baseEmissionsRate: baseEmissionRate,
                    minimumPremium: minimumPremium,
                    backing: backing,
                    tickSize: tickSize,
                    minPriceScalar: minPriceScalar,
                    restartTimeframe: restartTimeframe
                })
            )
        );

        // Beat counter is 2
        {
            // Execute twice to get beat counter to 2
            vm.startPrank(heart);
            emissionManager.execute();
            emissionManager.execute();
            vm.stopPrank();

            // Warp to the next day
            vm.warp(block.timestamp + 86400);
        }

        // Check that the beat counter is 2
        assertEq(emissionManager.beatCounter(), 2, "Beat counter should be 2");

        // Call execute
        vm.prank(heart);
        emissionManager.execute();

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            // Adjusted to the decimals of the deposit/reserve asset
            // price = 22377897966596497241 (18 dp)
            // price (adjusted) = 22377897 (6 dp)
            // minPrice = price * 9e17/1e18
            // minPrice = 20140107

            assertEq(cdAuctioneer.minPrice(), 20140107, "Min price");
        }

        // The pending capacity should be 0
        assertEq(emissionManager.bondMarketPendingCapacity(), 0, "pending capacity");
    }

    function test_execute_whenNextBeatIsZero_whenPremiumEqualMinimum_whenNoAdjustment()
        public
        givenNextBeatIsZero
        givenPremiumEqualToMinimum
        givenCDAuctioneerHasDeficit
    {
        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Confirm that there are no tokens in the contract yet
        assertEq(ohm.balanceOf(address(emissionManager)), 0, "OHM balance should be 0");
        assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

        // Confirm that mint approval is originally zero
        assertEq(MINTR.mintApproval(address(emissionManager)), 0, "Mint approval should be 0");

        // Check that the beat counter is 2
        assertEq(emissionManager.beatCounter(), 2, "Beat counter should be 2");

        // Warp to the next day
        vm.warp(block.timestamp + 86400);

        // Call execute
        vm.prank(heart);
        emissionManager.execute();

        // Check that a bond market was created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId + 1,
            "Market counter should increment"
        );

        // Confirm that the beat counter is now 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");

        // Verify the bond market parameters
        // Check that the market params are correct
        {
            uint256 marketPrice = bondAuctioneer.marketPrice(nextBondMarketId);
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
            ) = bondAuctioneer.markets(nextBondMarketId);

            assertEq(owner, address(emissionManager), "Owner");
            assertEq(address(payoutToken), address(ohm), "Payout token");
            assertEq(address(quoteToken), address(reserve), "Quote token");
            assertEq(
                callbackAddr,
                address(emissionManager),
                "Callback address should be the emissions manager"
            );
            assertEq(isCapacityInQuote, false, "Capacity should not be in quote token");
            assertEq(capacity, DEFICIT, "Capacity");
            assertEq(maxPayout, capacity / 6, "Max payout");

            assertEq(scale, 10 ** uint8(36 + 9 - 18 + 0), "Scale");
            assertEq(
                marketPrice,
                (PRICE.getLastPrice() * 10 ** uint8(36 - 1)) / 10 ** uint8(18 - 1),
                "Market price"
            );
            assertEq(
                minPrice,
                (((backing * (1e18 + minimumPremium)) / 1e18) * 10 ** uint8(36 - 1)) /
                    10 ** uint8(18 - 1),
                "Min price"
            );

            // Confirm token balances are still zero since the callback will minting and receiving tokens
            assertEq(ohm.balanceOf(address(emissionManager)), 0, "OHM balance should be 0");
            assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

            // Confirm that the emissions manager has mint approval for the capacity
            assertEq(
                MINTR.mintApproval(address(emissionManager)),
                capacity,
                "Mint approval should be the capacity"
            );
        }

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // The pending capacity should be 0
        assertEq(emissionManager.bondMarketPendingCapacity(), 0, "pending capacity");
    }

    function test_execute_whenNextBeatIsZero_whenPremiumEqualMinimum_whenNoAdjustment_surplus()
        public
        givenNextBeatIsZero
        givenPremiumEqualToMinimum
        givenCDAuctioneerHasSurplus
    {
        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Confirm that there are no tokens in the contract yet
        assertEq(ohm.balanceOf(address(emissionManager)), 0, "OHM balance should be 0");
        assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

        // Confirm that mint approval is originally zero
        assertEq(MINTR.mintApproval(address(emissionManager)), 0, "Mint approval should be 0");

        // Check that the beat counter is 2
        assertEq(emissionManager.beatCounter(), 2, "Beat counter should be 2");

        // Warp to the next day
        vm.warp(block.timestamp + 86400);

        // Call execute
        vm.prank(heart);
        emissionManager.execute();

        // Check that a bond market was NOT created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Confirm that the beat counter is now 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // The pending capacity should be 0
        assertEq(emissionManager.bondMarketPendingCapacity(), 0, "pending capacity");
    }

    function test_execute_whenNextBeatIsZero_whenPremiumEqualMinimum_whenNoAdjustment_noSurplus()
        public
        givenNextBeatIsZero
        givenPremiumEqualToMinimum
        givenCDAuctioneerHasZero
    {
        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Confirm that there are no tokens in the contract yet
        assertEq(ohm.balanceOf(address(emissionManager)), 0, "OHM balance should be 0");
        assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

        // Confirm that mint approval is originally zero
        assertEq(MINTR.mintApproval(address(emissionManager)), 0, "Mint approval should be 0");

        // Check that the beat counter is 2
        assertEq(emissionManager.beatCounter(), 2, "Beat counter should be 2");

        // Warp to the next day
        vm.warp(block.timestamp + 86400);

        // Call execute
        vm.prank(heart);
        emissionManager.execute();

        // Check that a bond market was NOT created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Confirm that the beat counter is now 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // The pending capacity should be 0
        assertEq(emissionManager.bondMarketPendingCapacity(), 0, "pending capacity");
    }

    function test_execute_whenNextBeatIsZero_givenPremiumAboveMinimum_whenNoAdjustment()
        public
        givenNextBeatIsZero
        givenPremiumAboveMinimum
        givenCDAuctioneerHasDeficit
    {
        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Confirm that there are no tokens in the contract yet
        assertEq(ohm.balanceOf(address(emissionManager)), 0, "OHM balance should be 0");
        assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

        // Confirm that mint approval is originally zero
        assertEq(MINTR.mintApproval(address(emissionManager)), 0, "Mint approval should be 0");

        // Check that the beat counter is 2
        assertEq(emissionManager.beatCounter(), 2, "Beat counter should be 2");

        // Warp to the next day
        vm.warp(block.timestamp + 86400);

        // Call execute
        vm.prank(heart);
        emissionManager.execute();

        // Check that a bond market was created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId + 1,
            "Market counter should increment"
        );

        // Confirm that the beat counter is now 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // Verify the bond market parameters
        // Check that the market params are correct
        {
            uint256 marketPrice = bondAuctioneer.marketPrice(nextBondMarketId);
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
            ) = bondAuctioneer.markets(nextBondMarketId);

            assertEq(owner, address(emissionManager), "Owner");
            assertEq(address(payoutToken), address(ohm), "Payout token");
            assertEq(address(quoteToken), address(reserve), "Quote token");
            assertEq(
                callbackAddr,
                address(emissionManager),
                "Callback address should be the emissions manager"
            );
            assertEq(isCapacityInQuote, false, "Capacity should not be in quote token");
            assertEq(capacity, DEFICIT, "Capacity");
            assertEq(maxPayout, capacity / 6, "Max payout");

            assertEq(scale, 10 ** uint8(36 + 9 - 18 + 0), "Scale");
            assertEq(
                marketPrice,
                (PRICE.getLastPrice() * 10 ** uint8(36 - 1)) / 10 ** uint8(18 - 1),
                "Market price"
            );
            assertEq(
                minPrice,
                (((backing * (1e18 + minimumPremium)) / 1e18) * 10 ** uint8(36 - 1)) /
                    10 ** uint8(18 - 1),
                "Min price"
            );

            // Confirm token balances are still zero since the callback will minting and receiving tokens
            assertEq(ohm.balanceOf(address(emissionManager)), 0, "OHM balance should be 0");
            assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

            // Confirm that the emissions manager has mint approval for the capacity
            assertEq(
                MINTR.mintApproval(address(emissionManager)),
                capacity,
                "Mint approval should be the capacity"
            );
        }

        // The pending capacity should be 0
        assertEq(emissionManager.bondMarketPendingCapacity(), 0, "pending capacity");
    }

    function test_execute_whenNextBeatIsZero_givenPremiumAboveMinimum_whenNoAdjustment_bondMarketsDisabled()
        public
        givenNextBeatIsZero
        givenPremiumAboveMinimum
        givenCDAuctioneerHasDeficit
    {
        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Disable new bond markets
        vm.prank(guardian);
        bondAuctioneer.setAllowNewMarkets(false);

        // Warp to the next day
        vm.warp(block.timestamp + 86400);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit BondMarketCreationFailed(DEFICIT);

        // Call execute
        vm.prank(heart);
        emissionManager.execute();

        // Check that a bond market was NOT created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should NOT increment"
        );

        // Confirm that the beat counter is now 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // The pending capacity should be set
        assertEq(emissionManager.bondMarketPendingCapacity(), DEFICIT, "pending capacity");
    }

    function test_execute_whenNextBeatIsZero_givenPremiumAboveMinimum_whenNoAdjustment_surplus()
        public
        givenNextBeatIsZero
        givenPremiumAboveMinimum
        givenCDAuctioneerHasSurplus
    {
        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Confirm that there are no tokens in the contract yet
        assertEq(ohm.balanceOf(address(emissionManager)), 0, "OHM balance should be 0");
        assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

        // Confirm that mint approval is originally zero
        assertEq(MINTR.mintApproval(address(emissionManager)), 0, "Mint approval should be 0");

        // Check that the beat counter is 2
        assertEq(emissionManager.beatCounter(), 2, "Beat counter should be 2");

        // Warp to the next day
        vm.warp(block.timestamp + 86400);

        // Call execute
        vm.prank(heart);
        emissionManager.execute();

        // Check that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Confirm that the beat counter is now 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // The pending capacity should be 0
        assertEq(emissionManager.bondMarketPendingCapacity(), 0, "pending capacity");
    }

    function test_execute_whenNextBeatIsZero_givenPremiumAboveMinimum_whenNoAdjustment_noSurplus()
        public
        givenNextBeatIsZero
        givenPremiumAboveMinimum
        givenCDAuctioneerHasZero
    {
        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Confirm that there are no tokens in the contract yet
        assertEq(ohm.balanceOf(address(emissionManager)), 0, "OHM balance should be 0");
        assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

        // Confirm that mint approval is originally zero
        assertEq(MINTR.mintApproval(address(emissionManager)), 0, "Mint approval should be 0");

        // Check that the beat counter is 2
        assertEq(emissionManager.beatCounter(), 2, "Beat counter should be 2");

        // Warp to the next day
        vm.warp(block.timestamp + 86400);

        // Call execute
        vm.prank(heart);
        emissionManager.execute();

        // Check that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Confirm that the beat counter is now 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // The pending capacity should be 0
        assertEq(emissionManager.bondMarketPendingCapacity(), 0, "pending capacity");
    }

    function test_execute_whenNextBeatIsZero_whenPositiveRateAdjustment()
        public
        givenNextBeatIsZero
        givenPositiveRateAdjustment
        givenCDAuctioneerHasDeficit
    {
        // Cache the current base rate
        uint256 baseRate = emissionManager.baseEmissionRate();

        // Calculate the expected base rate after the adjustment
        uint256 expectedBaseRate = baseRate + changeBy;

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Warp to the next day
        vm.warp(block.timestamp + 86400);

        // Execute to trigger the rate adjustment
        vm.prank(heart);
        emissionManager.execute();

        // Confirm the base rate has been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should be updated"
        );

        // Confirm that the capacity of the bond market uses the new base rate
        assertEq(
            bondAuctioneer.currentCapacity(nextBondMarketId),
            DEFICIT,
            "Capacity should be updated"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // Calculate the expected base rate after the next adjustment
        expectedBaseRate += changeBy;

        // Trigger a full cycle to make the next adjustment
        triggerFullCycle();

        // Confirm that the base rate has been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should be updated"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // Trigger a full cycle again. There should be no adjustment this time since it uses a duration of 2
        triggerFullCycle();

        // Confirm that the base rate has not been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should not be updated"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // The pending capacity should be 0
        assertEq(emissionManager.bondMarketPendingCapacity(), 0, "pending capacity");
    }

    function test_execute_whenNextBeatIsZero_whenPositiveRateAdjustment_surplus()
        public
        givenNextBeatIsZero
        givenPositiveRateAdjustment
        givenCDAuctioneerHasSurplus
    {
        // Cache the current base rate
        uint256 baseRate = emissionManager.baseEmissionRate();

        // Calculate the expected base rate after the adjustment
        uint256 expectedBaseRate = baseRate + changeBy;

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Warp to the next day
        vm.warp(block.timestamp + 86400);

        // Execute to trigger the rate adjustment
        vm.prank(heart);
        emissionManager.execute();

        // Confirm the base rate has been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should be updated"
        );

        // Confirm that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // Calculate the expected base rate after the next adjustment
        expectedBaseRate += changeBy;

        // Trigger a full cycle to make the next adjustment
        triggerFullCycle();

        // Confirm that the base rate has been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should be updated"
        );

        // Confirm that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // Trigger a full cycle again. There should be no adjustment this time since it uses a duration of 2
        triggerFullCycle();

        // Confirm that the base rate has not been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should not be updated"
        );

        // Confirm that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // The pending capacity should be 0
        assertEq(emissionManager.bondMarketPendingCapacity(), 0, "pending capacity");
    }

    function test_execute_whenNextBeatIsZero_whenPositiveRateAdjustment_noSurplus()
        public
        givenNextBeatIsZero
        givenPositiveRateAdjustment
        givenCDAuctioneerHasZero
    {
        // Cache the current base rate
        uint256 baseRate = emissionManager.baseEmissionRate();

        // Calculate the expected base rate after the adjustment
        uint256 expectedBaseRate = baseRate + changeBy;

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Warp to the next day
        vm.warp(block.timestamp + 86400);

        // Execute to trigger the rate adjustment
        vm.prank(heart);
        emissionManager.execute();

        // Confirm the base rate has been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should be updated"
        );

        // Confirm that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // Calculate the expected base rate after the next adjustment
        expectedBaseRate += changeBy;

        // Trigger a full cycle to make the next adjustment
        triggerFullCycle();

        // Confirm that the base rate has been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should be updated"
        );

        // Confirm that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // Trigger a full cycle again. There should be no adjustment this time since it uses a duration of 2
        triggerFullCycle();

        // Confirm that the base rate has not been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should not be updated"
        );

        // Confirm that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // The pending capacity should be 0
        assertEq(emissionManager.bondMarketPendingCapacity(), 0, "pending capacity");
    }

    function test_execute_whenNextBeatIsZero_whenNegativeRateAdjustment()
        public
        givenNextBeatIsZero
        givenNegativeRateAdjustment
        givenCDAuctioneerHasDeficit
    {
        // Cache the current base rate
        uint256 baseRate = emissionManager.baseEmissionRate();

        // Calculate the expected base rate after the adjustment
        uint256 expectedBaseRate = baseRate - changeBy;

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Warp to the next day
        vm.warp(block.timestamp + 86400);

        // Execute to trigger the rate adjustment
        vm.prank(heart);
        emissionManager.execute();

        // Confirm the base rate has been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should be updated"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // Confirm that the capacity of the bond market uses the new base rate
        assertEq(
            bondAuctioneer.currentCapacity(nextBondMarketId),
            DEFICIT,
            "Capacity should be updated"
        );

        // Calculate the expected base rate after the next adjustment
        expectedBaseRate -= changeBy;

        // Trigger a full cycle to make the next adjustment
        triggerFullCycle();

        // Confirm that the base rate has been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should be updated"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // Trigger a full cycle again. There should be no adjustment this time since it uses a duration of 2
        triggerFullCycle();

        // Confirm that the base rate has not been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should not be updated"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // The pending capacity should be 0
        assertEq(emissionManager.bondMarketPendingCapacity(), 0, "pending capacity");
    }

    function test_execute_whenNextBeatIsZero_whenNegativeRateAdjustment_surplus()
        public
        givenNextBeatIsZero
        givenNegativeRateAdjustment
        givenCDAuctioneerHasSurplus
    {
        // Cache the current base rate
        uint256 baseRate = emissionManager.baseEmissionRate();

        // Calculate the expected base rate after the adjustment
        uint256 expectedBaseRate = baseRate - changeBy;

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Warp to the next day
        vm.warp(block.timestamp + 86400);

        // Execute to trigger the rate adjustment
        vm.prank(heart);
        emissionManager.execute();

        // Confirm the base rate has been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should be updated"
        );

        // Confirm that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // Calculate the expected base rate after the next adjustment
        expectedBaseRate -= changeBy;

        // Trigger a full cycle to make the next adjustment
        triggerFullCycle();

        // Confirm that the base rate has been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should be updated"
        );

        // Confirm that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // Trigger a full cycle again. There should be no adjustment this time since it uses a duration of 2
        triggerFullCycle();

        // Confirm that the base rate has not been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should not be updated"
        );

        // Confirm that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // The pending capacity should be 0
        assertEq(emissionManager.bondMarketPendingCapacity(), 0, "pending capacity");
    }

    function test_execute_whenNextBeatIsZero_whenNegativeRateAdjustment_noSurplus()
        public
        givenNextBeatIsZero
        givenNegativeRateAdjustment
        givenCDAuctioneerHasZero
    {
        // Cache the current base rate
        uint256 baseRate = emissionManager.baseEmissionRate();

        // Calculate the expected base rate after the adjustment
        uint256 expectedBaseRate = baseRate - changeBy;

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Warp to the next day
        vm.warp(block.timestamp + 86400);

        // Execute to trigger the rate adjustment
        vm.prank(heart);
        emissionManager.execute();

        // Confirm the base rate has been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should be updated"
        );

        // Confirm that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // Calculate the expected base rate after the next adjustment
        expectedBaseRate -= changeBy;

        // Trigger a full cycle to make the next adjustment
        triggerFullCycle();

        // Confirm that the base rate has been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should be updated"
        );

        // Confirm that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // Trigger a full cycle again. There should be no adjustment this time since it uses a duration of 2
        triggerFullCycle();

        // Confirm that the base rate has not been updated
        assertEq(
            emissionManager.baseEmissionRate(),
            expectedBaseRate,
            "Base rate should not be updated"
        );

        // Confirm that a bond market was not created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId,
            "Market counter should not increment"
        );

        // Verify the auctioneer parameters
        {
            // Target == getNextEmission().emission
            (, , uint256 emission) = emissionManager.getNextEmission();

            assertEq(cdAuctioneer.target(), emission, "Target should be the emission");

            // Tick size == getSizeFor(emission)
            assertEq(
                cdAuctioneer.tickSize(),
                emissionManager.getSizeFor(emission),
                "Tick size should be the emission"
            );

            // Min price == getMinPriceFor(emission)
            assertEq(cdAuctioneer.minPrice(), expectedMinPrice, "Min price");
        }

        // The pending capacity should be 0
        assertEq(emissionManager.bondMarketPendingCapacity(), 0, "pending capacity");
    }

    // callback test cases

    function test_callback_whenSenderNotTeller_reverts() public {
        // Call the callback function with the wrong sender
        bytes memory err = abi.encodeWithSignature("OnlyTeller()");
        vm.prank(alice);
        vm.expectRevert(err);
        emissionManager.callback(0, 0, 0);
    }

    function test_callback_whenIdNotActiveMarket_reverts(uint256 id_) public {
        // Active market ID is originally 0
        assertEq(emissionManager.activeMarketId(), 0, "Active market ID should be 0");

        vm.assume(id_ != 0);

        // Call the callback function with the wrong ID
        bytes memory err = abi.encodeWithSignature("InvalidMarket()");
        vm.expectRevert(err);
        vm.prank(address(teller));
        emissionManager.callback(id_, 0, 0);
    }

    function test_callback_whenActiveMarketIdNotZero_whenIdNotActiveMarket_reverts(
        uint256 id_
    ) public givenCDAuctioneerHasDeficit {
        // Trigger two sales so that the active market ID is 1
        triggerFullCycle();
        triggerFullCycle();

        // Active market ID is 1
        assertEq(emissionManager.activeMarketId(), 1, "Active market ID should be 0");

        vm.assume(id_ != 1);

        // Call the callback function with the wrong ID
        bytes memory err = abi.encodeWithSignature("InvalidMarket()");
        vm.expectRevert(err);
        vm.prank(address(teller));
        emissionManager.callback(id_, 0, 0);
    }

    function test_callback_whenReserveBalanceLessThanInput_reverts(
        uint128 balance_,
        uint128 input_
    ) public {
        // Active market ID is originally 0
        assertEq(emissionManager.activeMarketId(), 0, "Active market ID should be 0");

        // Assume that the balance is less than the input amount
        // We cap these values to 2^128 - 1 to avoid overflow for practical purposes and to avoid random overflows with minting
        vm.assume(balance_ < input_);
        uint256 balance = uint256(balance_);
        uint256 input = uint256(input_);

        // Mint the balance to the emissions manager
        reserve.mint(address(emissionManager), balance);

        // Call the callback function with the wrong ID
        bytes memory err = abi.encodeWithSignature("InvalidCallback()");
        vm.expectRevert(err);
        vm.prank(address(teller));
        emissionManager.callback(0, input, 0);
    }

    function test_callback_success(uint128 input_, uint128 output_) public {
        // Active market ID is originally 0
        assertEq(emissionManager.activeMarketId(), 0, "Active market ID should be 0");

        // We cap these values to 2^128 - 1 to avoid overflow for practical purposes and to avoid random overflows with minting
        uint256 input = uint256(input_);
        uint256 output = uint256(output_);

        vm.assume(input != 0 && output != 0);

        // Give the emissions manager mint approval for the output
        // We will test that it functions within its mint limit granted in `execute` later
        // This is strictly for the unit testing of the callback function
        vm.prank(address(emissionManager));
        MINTR.increaseMintApproval(address(emissionManager), output);

        // Mint the input amount to the emissions manager
        reserve.mint(address(emissionManager), input);

        // Cache the initial OHM balance of the teller and the sReserve balance of the TRSRY
        uint256 tellerBalance = ohm.balanceOf(address(teller));
        uint256 treasuryBalance = sReserve.balanceOf(address(TRSRY));

        // Cache the current backing value in the emissions manager
        uint256 _backing = emissionManager.backing();

        // Cache the reserves and supply values for the backing update calculation
        uint256 reserves = emissionManager.getReserves();
        uint256 supply = emissionManager.getSupply();

        uint256 expectedBacking = (_backing * (((input + reserves) * 1e18) / reserves)) /
            (((output + supply) * 1e18) / supply);

        // Call the callback function
        vm.prank(address(teller));
        emissionManager.callback(0, input, output);

        // Check that the backing has been updated
        assertEq(emissionManager.backing(), expectedBacking, "Backing should be updated");

        // Check that the output amount of OHM has been minted to the teller
        assertEq(
            ohm.balanceOf(address(teller)),
            tellerBalance + output,
            "Teller OHM balance should be updated"
        );

        // Check that the input amount of reserves have been wrapped and deposited into the treasury
        assertEq(
            sReserve.balanceOf(address(TRSRY)),
            treasuryBalance + input, // can use the reserve amount as the sReserve amount since the conversion rate is 1:1
            "TRSRY wrapped reserve balance should be updated"
        );
    }

    function test_execute_whenCalculatedTickSizeBelowMinimum_setsTargetToZero()
        public
        givenNextBeatIsZero
        givenPremiumAboveMinimum
    {
        // Set tick size to a value higher than the expected emission
        // This will cause getSizeFor to return 0 when target < tickSize
        uint256 newTickSize = 15_000e9; // 15,000 OHM (higher than expected ~12,000 OHM)
        vm.prank(guardian);
        emissionManager.setTickSize(newTickSize);

        // Get the expected emission (should be > 0 due to premium above minimum)
        (, , uint256 originalEmission) = emissionManager.getNextEmission();
        assertGt(originalEmission, 0, "Original emission should be > 0");

        // Verify that calculated tick size would be less than the minimum
        uint256 calculatedTickSize = emissionManager.getSizeFor(originalEmission);
        assertEq(calculatedTickSize, 0, "Calculated tick size should be 0 when below minimum");
        assertLt(originalEmission, newTickSize, "Original emission should be less than tick size");

        // Call execute
        vm.prank(heart);
        emissionManager.execute();

        // Verify that both target and tick size were set to 0 in the auctioneer
        assertEq(
            cdAuctioneer.target(),
            0,
            "Target should be set to 0 when tick size is below minimum"
        );
        assertEq(cdAuctioneer.tickSize(), 0, "Tick size should be 0");
        assertEq(cdAuctioneer.isAuctionActive(), false, "Auction should be inactive");
    }

    // execute -> callback (full cycle bond purchase) tests

    function test_executeCallback_success() public givenNextBeatIsZero givenCDAuctioneerHasDeficit {
        // Change the price to 20 reserve per OHM for easier math
        PRICE.setLastPrice(20 * 1e18);

        // Cache the next bond market id
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Warp to the next day
        vm.warp(block.timestamp + 86400);

        // Call execute to create the bond market
        vm.prank(heart);
        emissionManager.execute();

        // Store initial balances
        uint256 aliceOhmBalance = ohm.balanceOf(alice);
        uint256 aliceReserveBalance = reserve.balanceOf(alice);
        uint256 treasuryWrappedReserveBalance = sReserve.balanceOf(address(TRSRY));
        uint256 ohmSupply = ohm.totalSupply();

        // Store initial backing value
        uint256 bidAmount = 1000e18;
        uint256 expectedPayout = bondAuctioneer.payoutFor(bidAmount, nextBondMarketId, address(0));
        uint256 expectedBacking;
        {
            uint256 reserves = emissionManager.getReserves();
            uint256 supply = emissionManager.getSupply();
            expectedBacking =
                (emissionManager.backing() * (((reserves + bidAmount) * 1e18) / reserves)) /
                (((supply + expectedPayout) * 1e18) / supply);
        }

        // Purchase a bond from the market

        vm.prank(alice);
        teller.purchase(alice, address(0), nextBondMarketId, bidAmount, expectedPayout);

        // Confirm the balance changes
        assertEq(
            ohm.balanceOf(alice),
            aliceOhmBalance + expectedPayout,
            "OHM balance should be updated"
        );
        assertEq(
            reserve.balanceOf(alice),
            aliceReserveBalance - bidAmount,
            "Reserve balance should be updated"
        );
        assertEq(
            sReserve.balanceOf(address(TRSRY)),
            treasuryWrappedReserveBalance + bidAmount,
            "TRSRY wrapped reserve balance should be updated"
        );
        assertEq(
            ohm.totalSupply(),
            ohmSupply + expectedPayout,
            "OHM total supply should be updated"
        );

        // Confirm the backing has been updated
        assertEq(emissionManager.backing(), expectedBacking, "Backing should be updated");
    }

    // shutdown tests

    function test_shutdown_whenCallerNotEmergencyShutdownRole_reverts(address rando_) public {
        vm.assume(rando_ != guardian);

        // Call the shutdown function with the wrong caller
        vm.expectRevert(abi.encodeWithSelector(PolicyAdmin.NotAuthorised.selector));

        vm.prank(rando_);
        emissionManager.disable("");
    }

    function test_shutdown_success() public {
        // Check that the contract is enabled
        assertTrue(emissionManager.isEnabled(), "Contract should be enabled");

        // Check that the shutdown timestamp is 0
        assertEq(emissionManager.shutdownTimestamp(), 0, "Shutdown timestamp should be 0");

        // Confirm that the block timestamp is not 0
        assertGt(block.timestamp, 0, "Block timestamp should not be 0");

        // Call the shutdown function as guardian (which has the emergency_shutdown role)
        vm.prank(guardian);
        emissionManager.disable("");

        // Check that the contract is not enabled
        assertFalse(emissionManager.isEnabled(), "Contract should not be enabled");

        // Check that the shutdown timestamp is set to the current block timestamp
        assertEq(
            emissionManager.shutdownTimestamp(),
            block.timestamp,
            "Shutdown timestamp should be set"
        );
    }

    function test_shutdown_whenMarketIsActive_closesMarket()
        public
        givenPremiumEqualToMinimum
        givenCDAuctioneerHasDeficit
        givenThereIsPreviousSale
    {
        // We created a market, confirm it is active
        uint256 id = emissionManager.activeMarketId();
        assertTrue(bondAuctioneer.isLive(id), "Market should be active");

        // Check that the contract is enabled
        assertTrue(emissionManager.isEnabled(), "Contract should be enabled");

        // Check that the shutdown timestamp is 0
        assertEq(emissionManager.shutdownTimestamp(), 0, "Shutdown timestamp should be 0");

        // Confirm that the block timestamp is not 0
        assertGt(block.timestamp, 0, "Block timestamp should not be 0");

        // Call the shutdown function as guardian (which has the emergency_shutdown role)
        vm.prank(guardian);
        emissionManager.disable("");

        // Check that the contract is not enabled
        assertFalse(emissionManager.isEnabled(), "Contract should not be enabled");

        // Check that the shutdown timestamp is set to the current block timestamp
        assertEq(
            emissionManager.shutdownTimestamp(),
            block.timestamp,
            "Shutdown timestamp should be set"
        );

        // Check that the market is no longer active
        assertFalse(bondAuctioneer.isLive(id), "Market should be closed");
    }

    // restart tests

    function test_restart_whenCallerNotEmergencyRestartRole_reverts(address rando_) public {
        vm.assume(rando_ != guardian);

        // Emissions Manager is currently enabled
        // Call the restart function with the wrong caller
        bytes memory err = abi.encodeWithSignature("ROLES_RequireRole(bytes32)", bytes32("admin"));
        vm.expectRevert(err);
        vm.prank(rando_);
        emissionManager.restart();

        // Shutdown the emissions manager with the guardian
        vm.prank(guardian);
        emissionManager.disable("");

        // Emissions Manager is currently locally inactive
        // Try to call restart again with the wrong caller
        vm.expectRevert(err);
        vm.prank(rando_);
        emissionManager.restart();
    }

    function test_restart_whenRestartTimeElapsed_reverts(uint48 elapsed_) public givenShutdown {
        assertFalse(emissionManager.isEnabled(), "Contract should not be enabled");

        // Get the restart timeframe and the last shutdown timestamp
        uint48 shutdownTimestamp = emissionManager.shutdownTimestamp();
        uint48 restartTimeframe_ = emissionManager.restartTimeframe();

        vm.assume(elapsed_ <= type(uint48).max - shutdownTimestamp - restartTimeframe_);

        // Warp time to the restart timeframe plus some elapsed time (potentially 0)
        vm.warp(shutdownTimestamp + restartTimeframe_ + elapsed_);

        // Try to restart the emissions manager with guardian, expect revert
        bytes memory err = abi.encodeWithSignature("RestartTimeframePassed()");
        vm.expectRevert(err);
        vm.prank(guardian);
        emissionManager.restart();
    }

    function test_restart_whenRestartTimeFrameNotElapsed_success(
        uint48 elapsed_
    ) public givenShutdown {
        assertFalse(emissionManager.isEnabled(), "Contract should not be enabled");

        // Get the restart timeframe and the last shutdown timestamp
        uint48 shutdownTimestamp = emissionManager.shutdownTimestamp();
        uint48 restartTimeframe_ = emissionManager.restartTimeframe();

        // Set the elapsed time to be less than the restart timeframe
        uint48 elapsed = elapsed_ % restartTimeframe_;

        // Warp forward the elapsed time
        vm.warp(shutdownTimestamp + elapsed);

        // Restart the emissions manager with guardian
        vm.prank(guardian);
        emissionManager.restart();

        assertTrue(emissionManager.isEnabled(), "Contract should be enabled");
    }

    // initialize tests

    function test_initialize_whenCallerNotEmissionsAdmin_reverts(address rando_) public {
        vm.assume(rando_ != guardian);

        // Call the initialize function with the wrong caller
        bytes memory err = abi.encodeWithSignature("ROLES_RequireRole(bytes32)", bytes32("admin"));
        vm.expectRevert(err);
        vm.prank(rando_);
        emissionManager.enable(
            abi.encode(
                IEmissionManager.EnableParams({
                    baseEmissionsRate: baseEmissionRate,
                    minimumPremium: minimumPremium,
                    backing: backing,
                    tickSize: tickSize,
                    minPriceScalar: minPriceScalar,
                    restartTimeframe: restartTimeframe
                })
            )
        );
    }

    function test_initialize_whenAlreadyActive_reverts() public {
        // Call the initialize function with the wrong caller
        bytes memory err = abi.encodeWithSignature("NotDisabled()");
        vm.expectRevert(err);
        vm.prank(guardian);
        emissionManager.enable(
            abi.encode(
                IEmissionManager.EnableParams({
                    baseEmissionsRate: baseEmissionRate,
                    minimumPremium: minimumPremium,
                    backing: backing,
                    tickSize: tickSize,
                    minPriceScalar: minPriceScalar,
                    restartTimeframe: restartTimeframe
                })
            )
        );
    }

    function test_initialize_whenRestartTimeframeNotElapsed_reverts(
        uint48 elapsed_
    ) public givenShutdown {
        assertFalse(emissionManager.isEnabled(), "Contract should not be enabled");

        // Get the restart timeframe and the last shutdown timestamp
        uint48 shutdownTimestamp = emissionManager.shutdownTimestamp();
        uint48 restartTimeframe_ = emissionManager.restartTimeframe();

        // Set the elapsed time to be less than the restart timeframe
        uint48 elapsed = elapsed_ % restartTimeframe_;

        // Warp forward the elapsed time
        vm.warp(shutdownTimestamp + elapsed);

        // Try to initialize the emissions manager with guardian, expect revert
        bytes memory err = abi.encodeWithSignature(
            "CannotRestartYet(uint48)",
            shutdownTimestamp + restartTimeframe_
        );
        vm.expectRevert(err);
        vm.prank(guardian);
        emissionManager.enable(
            abi.encode(
                IEmissionManager.EnableParams({
                    baseEmissionsRate: baseEmissionRate,
                    minimumPremium: minimumPremium,
                    backing: backing,
                    tickSize: tickSize,
                    minPriceScalar: minPriceScalar,
                    restartTimeframe: restartTimeframe
                })
            )
        );
    }

    function test_initialize_whenParamsLengthInvalid_reverts()
        public
        givenShutdown
        givenRestartTimeframeElapsed
    {
        // Try to initialize the emissions manager with guardian, expect revert
        bytes memory err = abi.encodeWithSignature("InvalidParam(string)", "params length");
        vm.expectRevert(err);

        vm.prank(guardian);
        emissionManager.enable(abi.encode(uint256(20)));
    }

    function test_initialize_whenBaseEmissionRateZero_reverts()
        public
        givenShutdown
        givenRestartTimeframeElapsed
    {
        assertFalse(emissionManager.isEnabled(), "Contract should not be enabled");

        // Try to initialize the emissions manager with guardian, expect revert
        bytes memory err = abi.encodeWithSignature("InvalidParam(string)", "baseEmissionRate");
        vm.expectRevert(err);
        vm.prank(guardian);
        emissionManager.enable(
            abi.encode(
                IEmissionManager.EnableParams({
                    baseEmissionsRate: 0,
                    minimumPremium: minimumPremium,
                    backing: backing,
                    tickSize: tickSize,
                    minPriceScalar: minPriceScalar,
                    restartTimeframe: restartTimeframe
                })
            )
        );
    }

    function test_initialize_whenMinimumPremiumZero_reverts()
        public
        givenShutdown
        givenRestartTimeframeElapsed
    {
        assertFalse(emissionManager.isEnabled(), "Contract should not be enabled");

        // Try to initialize the emissions manager with guardian, expect revert
        bytes memory err = abi.encodeWithSignature("InvalidParam(string)", "minimumPremium");
        vm.expectRevert(err);
        vm.prank(guardian);
        emissionManager.enable(
            abi.encode(
                IEmissionManager.EnableParams({
                    baseEmissionsRate: baseEmissionRate,
                    minimumPremium: 0,
                    backing: backing,
                    tickSize: tickSize,
                    minPriceScalar: minPriceScalar,
                    restartTimeframe: restartTimeframe
                })
            )
        );
    }

    function test_initialize_whenBackingZero_reverts()
        public
        givenShutdown
        givenRestartTimeframeElapsed
    {
        assertFalse(emissionManager.isEnabled(), "Contract should not be enabled");

        // Try to initialize the emissions manager with guardian, expect revert
        bytes memory err = abi.encodeWithSignature("InvalidParam(string)", "backing");
        vm.expectRevert(err);
        vm.prank(guardian);
        emissionManager.enable(
            abi.encode(
                IEmissionManager.EnableParams({
                    baseEmissionsRate: baseEmissionRate,
                    minimumPremium: minimumPremium,
                    backing: 0,
                    tickSize: tickSize,
                    minPriceScalar: minPriceScalar,
                    restartTimeframe: restartTimeframe
                })
            )
        );
    }

    function test_initialize_whenRestartTimeframeZero_reverts()
        public
        givenShutdown
        givenRestartTimeframeElapsed
    {
        assertFalse(emissionManager.isEnabled(), "Contract should not be enabled");

        // Try to initialize the emissions manager with guardian, expect revert
        bytes memory err = abi.encodeWithSignature("InvalidParam(string)", "restartTimeframe");
        vm.expectRevert(err);
        vm.prank(guardian);
        emissionManager.enable(
            abi.encode(
                IEmissionManager.EnableParams({
                    baseEmissionsRate: baseEmissionRate,
                    minimumPremium: minimumPremium,
                    backing: backing,
                    tickSize: tickSize,
                    minPriceScalar: minPriceScalar,
                    restartTimeframe: 0
                })
            )
        );
    }

    function test_initialize_success() public givenShutdown givenRestartTimeframeElapsed {
        assertFalse(emissionManager.isEnabled(), "Contract should not be enabled");

        // Values are currently as setup

        // Initialize the emissions manager with guardian using new values
        vm.prank(guardian);
        emissionManager.enable(
            abi.encode(
                IEmissionManager.EnableParams({
                    baseEmissionsRate: baseEmissionRate + 1,
                    minimumPremium: minimumPremium + 1,
                    backing: backing + 1,
                    tickSize: tickSize,
                    minPriceScalar: minPriceScalar,
                    restartTimeframe: restartTimeframe + 1
                })
            )
        );

        // Check that the contract is enabled
        assertTrue(emissionManager.isEnabled(), "Contract should be enabled");
        assertEq(
            emissionManager.baseEmissionRate(),
            baseEmissionRate + 1,
            "Base emission rate should be updated"
        );
        assertEq(
            emissionManager.minimumPremium(),
            minimumPremium + 1,
            "Minimum premium should be updated"
        );
        assertEq(emissionManager.backing(), backing + 1, "Backing should be updated");
        assertEq(
            emissionManager.restartTimeframe(),
            restartTimeframe + 1,
            "Restart timeframe should be updated"
        );
        assertEq(emissionManager.tickSize(), tickSize, "TickSize should be updated");
    }

    function test_initialize_setsTickSizeAndEmitsEvent()
        public
        givenShutdown
        givenRestartTimeframeElapsed
    {
        uint256 testTickSize = 5e9; // 5 OHM

        // Expect TickSizeChanged event to be emitted
        vm.expectEmit(address(emissionManager));
        emit TickSizeChanged(testTickSize);

        // Initialize the emissions manager with a specific tickSize
        vm.prank(guardian);
        emissionManager.enable(
            abi.encode(
                IEmissionManager.EnableParams({
                    baseEmissionsRate: baseEmissionRate,
                    minimumPremium: minimumPremium,
                    backing: backing,
                    tickSize: testTickSize,
                    minPriceScalar: minPriceScalar,
                    restartTimeframe: restartTimeframe
                })
            )
        );

        // Check that tickSize was set correctly
        assertEq(
            emissionManager.tickSize(),
            testTickSize,
            "TickSize should be set during initialization"
        );
    }

    function test_initialize_withZeroMinTickSize_reverts()
        public
        givenShutdown
        givenRestartTimeframeElapsed
    {
        uint256 testTickSize = 0;

        // Expect revert
        bytes memory err = abi.encodeWithSignature("InvalidParam(string)", "Tick Size");
        vm.expectRevert(err);

        // Initialize the emissions manager with minTickSize = 0
        vm.prank(guardian);
        emissionManager.enable(
            abi.encode(
                IEmissionManager.EnableParams({
                    baseEmissionsRate: baseEmissionRate,
                    minimumPremium: minimumPremium,
                    backing: backing,
                    tickSize: testTickSize,
                    minPriceScalar: minPriceScalar,
                    restartTimeframe: restartTimeframe
                })
            )
        );
    }

    // changeBaseRate tests

    function test_changeBaseRate_whenCallerNotEmissionsAdmin_reverts(address rando_) public {
        vm.assume(rando_ != guardian);

        // Call the changeBaseRate function with the wrong caller
        bytes memory err = abi.encodeWithSignature("ROLES_RequireRole(bytes32)", bytes32("admin"));
        vm.expectRevert(err);
        vm.prank(rando_);
        emissionManager.changeBaseRate(1e18, 1, true);
    }

    function test_changeBaseRate_whenNegativeAdjustmentUnderflows_reverts() public {
        uint256 changeBy_ = baseEmissionRate + 1;
        uint48 forNumBeats = 1;

        // Try to change base rate, expect revert
        bytes memory err = abi.encodeWithSignature(
            "InvalidParam(string)",
            "changeBy * forNumBeats"
        );
        vm.expectRevert(err);
        vm.prank(guardian);
        emissionManager.changeBaseRate(changeBy_, forNumBeats, false);
    }

    function test_changeBaseRate_whenPositiveAdjustmentOverflows_reverts() public {
        uint256 changeBy_ = type(uint256).max - baseEmissionRate + 1;
        uint48 forNumBeats = 1;

        // Try to change base rate, expect revert
        bytes memory err = abi.encodeWithSignature(
            "InvalidParam(string)",
            "changeBy * forNumBeats"
        );
        vm.expectRevert(err);
        vm.prank(guardian);
        emissionManager.changeBaseRate(changeBy_, forNumBeats, true);
    }

    function test_changeBaseRate_positive_success() public {
        // Confirm there is no current rate change
        (uint256 currentChangeBy, uint48 currentBeatsLeft, bool addition) = emissionManager
            .rateChange();
        assertEq(currentChangeBy, 0, "Change by should be 0");
        assertEq(currentBeatsLeft, 0, "Beats left should be 0");
        assertEq(addition, false, "Addition should be false");

        uint256 changeBy_ = 1e3;
        uint48 forNumBeats = 5;

        vm.prank(guardian);
        emissionManager.changeBaseRate(changeBy_, forNumBeats, true);

        // Confirm the rate change has been set
        (currentChangeBy, currentBeatsLeft, addition) = emissionManager.rateChange();
        assertEq(currentChangeBy, changeBy_, "Change by should be updated");
        assertEq(currentBeatsLeft, forNumBeats, "Beats left should be updated");
        assertEq(addition, true, "Addition should be true");
    }

    function test_changeBaseRate_negative_success() public {
        // Confirm there is no current rate change
        (uint256 currentChangeBy, uint48 currentBeatsLeft, bool addition) = emissionManager
            .rateChange();
        assertEq(currentChangeBy, 0, "Change by should be 0");
        assertEq(currentBeatsLeft, 0, "Beats left should be 0");
        assertEq(addition, false, "Addition should be false");

        uint256 changeBy_ = 1e3;
        uint48 forNumBeats = 5;

        vm.prank(guardian);
        emissionManager.changeBaseRate(changeBy_, forNumBeats, false);

        // Confirm the rate change has been set
        (currentChangeBy, currentBeatsLeft, addition) = emissionManager.rateChange();
        assertEq(currentChangeBy, changeBy_, "Change by should be updated");
        assertEq(currentBeatsLeft, forNumBeats, "Beats left should be updated");
        assertEq(addition, false, "Addition should be false");
    }

    // setMinimumPremium tests

    function test_setMinimumPremium_whenCallerNotEmissionsAdmin_reverts(address rando_) public {
        vm.assume(rando_ != guardian);

        // Call the setMinimumPremium function with the wrong caller
        bytes memory err = abi.encodeWithSignature("ROLES_RequireRole(bytes32)", bytes32("admin"));
        vm.expectRevert(err);
        vm.prank(rando_);
        emissionManager.setMinimumPremium(1e18);
    }

    function test_setMinimumPremium_whenMinimumPremiumZero_reverts() public {
        // Try to set minimum premium to 0, expect revert
        bytes memory err = abi.encodeWithSignature("InvalidParam(string)", "newMinimumPremium");
        vm.expectRevert(err);
        vm.prank(guardian);
        emissionManager.setMinimumPremium(0);
    }

    function test_setMinimumPremium_success() public {
        uint256 newMinimumPremium = 1e18;

        // Confirm the current minimum premium
        assertEq(emissionManager.minimumPremium(), minimumPremium, "Minimum premium should be 0");

        // Set the new minimum premium
        vm.prank(guardian);
        emissionManager.setMinimumPremium(newMinimumPremium);

        // Confirm the new minimum premium
        assertEq(
            emissionManager.minimumPremium(),
            newMinimumPremium,
            "Minimum premium should be updated"
        );
    }

    // setBacking tests

    function test_setBacking_whenCallerNotEmissionsAdmin_reverts(address rando_) public {
        vm.assume(rando_ != guardian);

        // Call the setBacking function with the wrong caller
        bytes memory err = abi.encodeWithSignature("ROLES_RequireRole(bytes32)", bytes32("admin"));
        vm.expectRevert(err);
        vm.prank(rando_);
        emissionManager.setBacking(11e18);
    }

    function test_setBacking_whenNewBackingTenPercentLessThanCurrent_reverts(
        uint256 newBacking_
    ) public {
        uint256 newBacking = newBacking_ % ((backing * 9) / 10);

        // Try to set backing to more than 10% less than current, expect revert
        bytes memory err = abi.encodeWithSignature("InvalidParam(string)", "newBacking");
        vm.expectRevert(err);
        vm.prank(guardian);
        emissionManager.setBacking(newBacking);
    }

    function test_setBacking_success(uint256 newBacking_) public {
        vm.assume(newBacking_ >= ((backing * 9) / 10));

        // Set new backing
        vm.prank(guardian);
        emissionManager.setBacking(newBacking_);

        // Confirm new backing
        assertEq(emissionManager.backing(), newBacking_, "Backing should be updated");
    }

    // setRestartTimeframe tests

    function test_setRestartTimeframe_whenCallerNotEmissionsAdmin_reverts(address rando_) public {
        vm.assume(rando_ != guardian);

        // Call the setRestartTimeframe function with the wrong caller
        bytes memory err = abi.encodeWithSignature("ROLES_RequireRole(bytes32)", bytes32("admin"));
        vm.expectRevert(err);
        vm.prank(rando_);
        emissionManager.setRestartTimeframe(1);
    }

    function test_setRestartTimeframe_whenRestartTimeframeIsZero_reverts() public {
        // Try to set restart timeframe to 0, expect revert
        bytes memory err = abi.encodeWithSignature("InvalidParam(string)", "newRestartTimeframe");
        vm.expectRevert(err);
        vm.prank(guardian);
        emissionManager.setRestartTimeframe(0);
    }

    function test_setRestartTimeframe_success(uint48 restartTimeframe_) public {
        vm.assume(restartTimeframe_ != 0);

        // Set new restart timeframe
        vm.prank(guardian);
        emissionManager.setRestartTimeframe(restartTimeframe_);

        // Confirm new restart timeframe
        assertEq(
            emissionManager.restartTimeframe(),
            restartTimeframe_,
            "Restart timeframe should be updated"
        );
    }

    // setBondContracts tests

    function test_setBondContracts_whenCallerNotEmissionsAdmin_reverts(address rando_) public {
        vm.assume(rando_ != guardian);

        // Call the setBondContracts function with the wrong caller
        bytes memory err = abi.encodeWithSignature("ROLES_RequireRole(bytes32)", bytes32("admin"));
        vm.expectRevert(err);
        vm.prank(rando_);
        emissionManager.setBondContracts(address(1), address(1));
    }

    function test_setBondContracts_whenBondAuctioneerZero_reverts() public {
        // Try to set bondAuctioneer to 0, expect revert
        bytes memory err = abi.encodeWithSignature("InvalidParam(string)", "bondAuctioneer");
        vm.expectRevert(err);
        vm.prank(guardian);
        emissionManager.setBondContracts(address(0), address(1));
    }

    function test_setBondContracts_whenBondTellerZero_reverts() public {
        // Try to set bond teller to 0, expect revert
        bytes memory err = abi.encodeWithSignature("InvalidParam(string)", "teller");
        vm.expectRevert(err);
        vm.prank(guardian);
        emissionManager.setBondContracts(address(1), address(0));
    }

    function test_setBondContracts_success() public {
        // Set new bond contracts
        vm.prank(guardian);
        emissionManager.setBondContracts(address(1), address(1));

        // Confirm new bond contracts
        assertEq(
            address(emissionManager.bondAuctioneer()),
            address(1),
            "BondAuctioneer should be updated"
        );
        assertEq(emissionManager.teller(), address(1), "Bond teller should be updated");
    }

    // setCDAuctionContract tests

    function test_setCDAuctionContract_whenCallerNotEmissionsAdmin_reverts(address rando_) public {
        vm.assume(rando_ != guardian);

        // Call the setCDAuctionContract function with the wrong caller
        bytes memory err = abi.encodeWithSignature("ROLES_RequireRole(bytes32)", bytes32("admin"));
        vm.expectRevert(err);
        vm.prank(rando_);
        emissionManager.setCDAuctionContract(address(1));
    }

    function test_setCDAuctionContract_whenZero_reverts() public {
        // Try to set cdAuctioneer to 0, expect revert
        bytes memory err = abi.encodeWithSignature("InvalidParam(string)", "zero address");
        vm.expectRevert(err);
        vm.prank(guardian);
        emissionManager.setCDAuctionContract(address(0));
    }

    function test_setCDAuctionContract_differentAsset_reverts() public {
        MockConvertibleDepositAuctioneer newCDAuctioneer = new MockConvertibleDepositAuctioneer(
            kernel,
            address(sReserve)
        );

        // Try to set cdAuctioneer to 0, expect revert
        bytes memory err = abi.encodeWithSignature("InvalidParam(string)", "different asset");
        vm.expectRevert(err);

        vm.prank(guardian);
        emissionManager.setCDAuctionContract(address(newCDAuctioneer));
    }

    function test_setCDAuctionContract_success() public {
        // Set new CD Auctioneer contract
        vm.prank(guardian);
        emissionManager.setCDAuctionContract(address(cdAuctioneer));

        // Confirm new contract
        assertEq(
            address(emissionManager.cdAuctioneer()),
            address(cdAuctioneer),
            "CDuctioneer should be updated"
        );
    }

    // setTickSize tests

    function test_setTickSize_whenCallerNotEmissionsAdmin_reverts(address rando_) public {
        vm.assume(rando_ != guardian);

        // Call the setTickSize function with the wrong caller
        bytes memory err = abi.encodeWithSignature("ROLES_RequireRole(bytes32)", bytes32("admin"));
        vm.expectRevert(err);

        vm.prank(rando_);
        emissionManager.setTickSize(1e9);
    }

    function test_setTickSize_success() public {
        uint256 newTickSize = 5e9; // 5 OHM

        // Expect event to be emitted
        vm.expectEmit(address(emissionManager));
        emit TickSizeChanged(newTickSize);

        // Set new tick size
        vm.prank(guardian);
        emissionManager.setTickSize(newTickSize);

        // Confirm new value
        assertEq(emissionManager.tickSize(), newTickSize, "TickSize should be updated");
    }

    function test_setTickSize_zeroValue_reverts() public {
        uint256 newTickSize = 0;

        // Should revert when trying to set tick size to 0
        vm.expectRevert(
            abi.encodeWithSelector(IEmissionManager.InvalidParam.selector, "Tick Size")
        );
        vm.prank(guardian);
        emissionManager.setTickSize(newTickSize);
    }

    function test_execute_passesCorrectTickSizeToAuctioneer()
        public
        givenNextBeatIsZero
        givenPremiumAboveMinimum
    {
        // Set a specific tick size
        uint256 testTickSize = 15e9; // 15 OHM
        vm.prank(guardian);
        emissionManager.setTickSize(testTickSize);

        // Get the expected emission
        (, , uint256 emission) = emissionManager.getNextEmission();
        assertGt(emission, testTickSize, "Emission should be greater than tick size for this test");

        // Execute
        vm.prank(heart);
        emissionManager.execute();

        // Verify that the correct tick size was passed to the auctioneer
        assertEq(
            cdAuctioneer.tickSize(),
            testTickSize,
            "Auctioneer should receive the fixed tick size"
        );
        assertEq(
            cdAuctioneer.target(),
            emission,
            "Auctioneer should receive the emission as target"
        );
    }

    // getSupply tests

    function test_getSupply_success() public {
        // Confirm the supply is the total supply of OHM
        assertEq(
            emissionManager.getSupply(),
            (gohm.totalSupply() * gohm.index()) / 1e18,
            "Supply should be gOHM supply times index"
        );

        // Mint some more gOHM
        uint256 mintAmount = 1000e18;
        gohm.mint(address(1), mintAmount);

        // Confirm the supply is the total supply of OHM
        assertEq(
            emissionManager.getSupply(),
            (gohm.totalSupply() * gohm.index()) / 10 ** gohm.decimals(),
            "Supply should be gOHM supply times index"
        );
    }

    // getReserves test

    function test_getReserves_success() public {
        uint256 expectedBalance = sReserve.balanceOf(address(TRSRY));
        expectedBalance += sReserve.balanceOf(address(clearinghouse));
        expectedBalance += clearinghouse.principalReceivables();

        // Confirm the reserves are the wrapped reserve balance of the treasury and clearinghouse
        assertEq(
            emissionManager.getReserves(),
            expectedBalance,
            "Reserves should be wrapped reserve balance of treasury and clearinghouse"
        );

        // Mint some more wrapped reserve to the treasury
        uint256 mintAmount = 1000e18;
        reserve.mint(address(this), 2 * mintAmount);
        reserve.approve(address(sReserve), 2 * mintAmount);
        sReserve.mint(mintAmount, address(TRSRY));
        expectedBalance += mintAmount;

        // Confirm the reserves are the wrapped reserve balance of the treasury and clearinghouse
        assertEq(
            emissionManager.getReserves(),
            expectedBalance,
            "Reserves should be wrapped reserve balance of treasury and clearinghouse"
        );

        // Mint some wrapped reserves to the clearinghouse
        sReserve.mint(mintAmount, address(clearinghouse));
        expectedBalance += mintAmount;

        // Confirm the reserves are the wrapped reserve balance of the treasury and clearinghouse
        assertEq(
            emissionManager.getReserves(),
            expectedBalance,
            "Reserves should be wrapped reserve balance of treasury and clearinghouse"
        );

        // Increase the principal receivables of the clearinghouse
        uint256 principalReceivables = clearinghouse.principalReceivables();
        clearinghouse.setPrincipalReceivables(principalReceivables + mintAmount);
        expectedBalance += mintAmount;

        // Confirm the reserves are the wrapped reserve balance of the treasury and clearinghouse
        assertEq(
            emissionManager.getReserves(),
            expectedBalance,
            "Reserves should be wrapped reserve balance of treasury and clearinghouse"
        );
    }

    // getNextEmission tests

    function test_getNextSale_whenPremiumBelowMinimum() public givenPremiumBelowMinimum {
        // Get the next sale data
        (uint256 premium, uint256 emissionRate, uint256 emission) = emissionManager
            .getNextEmission();

        // Expect that the premium is as set in the setup
        // and the other two values are zero
        assertEq(premium, 20e16, "Premium should be 20%");
        assertEq(emissionRate, 0, "Emission rate should be 0");
        assertEq(emission, 0, "Emission should be 0");
    }

    function test_getNextSale_whenPremiumEqualToMinimum() public givenPremiumEqualToMinimum {
        // Get the next sale data
        (uint256 premium, uint256 emissionRate, uint256 emission) = emissionManager
            .getNextEmission();

        uint256 expectedEmission = 10_000e9; // 10,000 OHM (as described in setup)

        // Expect that the premium is as set in the setup
        // and the other two values are zero
        assertEq(premium, 25e16, "Premium should be 20%");
        assertEq(emissionRate, baseEmissionRate, "Emission rate should be the baseEmissionRate");
        assertEq(emission, expectedEmission, "Emission should be 10,000 OHM");
    }

    function test_getNextSale_whenPremiumAboveMinimum() public givenPremiumAboveMinimum {
        // Get the next sale data
        (uint256 premium, uint256 emissionRate, uint256 emission) = emissionManager
            .getNextEmission();

        uint256 expectedEmission = 12_000e9; // 12,000 OHM (as described in setup)

        // Expect that the premium is as set in the setup
        // and the other two values are zero
        assertEq(premium, 50e16, "Premium should be 50%");
        assertEq(
            emissionRate,
            (baseEmissionRate * 150e16) / 125e16,
            "Emission rate should be the baseEmissionRate"
        );
        assertEq(emission, expectedEmission, "Emission should be 10,000 OHM");
    }

    // getPremium tests

    function test_getPremium_whenPriceBelowBacking() public {
        // Set the price to be below the backing ($10/OHM)
        PRICE.setLastPrice(9e18);

        // Get the premium
        uint256 premium = emissionManager.getPremium();

        // Expect the premium to be 0
        assertEq(premium, 0, "Premium should be 0");
    }

    function test_getPremium_whenPriceEqualsBacking() public {
        // Set the price to be equal to the backing ($10/OHM)
        PRICE.setLastPrice(10e18);

        // Get the premium
        uint256 premium = emissionManager.getPremium();

        // Expect the premium to be 0
        assertEq(premium, 0, "Premium should be 0");
    }

    function test_getPremium_whenPriceAboveBacking() public {
        // Set the price to be above the backing ($10/OHM)
        PRICE.setLastPrice(11e18);

        // Get the premium
        uint256 premium = emissionManager.getPremium();

        // Expect the premium to be 10%
        assertEq(premium, 10e16, "Premium should be 10%");

        // Set price again
        PRICE.setLastPrice(15e18);

        // Get the premium
        premium = emissionManager.getPremium();

        // Expect the premium to be 50%
        assertEq(premium, 50e16, "Premium should be 50%");

        // Set price again
        PRICE.setLastPrice(30e18);

        // Get the premium
        premium = emissionManager.getPremium();

        // Expect the premium to be 200%
        assertEq(premium, 200e16, "Premium should be 200%");
    }

    // getSizeFor tests

    function test_getSizeFor_zero() public view {
        assertEq(emissionManager.getSizeFor(0), 0, "getSizeFor should return 0 when target is 0");
    }

    function test_getSizeFor(uint256 target_) public view {
        target_ = bound(target_, tickSize, 1000e9); // Only test targets >= tickSize

        // For fixed tick size: return tickSize if target >= tickSize, otherwise 0
        uint256 expectedSize = tickSize;

        assertEq(emissionManager.getSizeFor(target_), expectedSize, "getSizeFor");
    }

    function test_getSizeFor_whenTargetEqualsTickSize_returnsTickSize() public view {
        uint256 target = tickSize; // Target exactly equals tick size

        assertEq(
            emissionManager.getSizeFor(target),
            tickSize,
            "Should return tick size when target equals tick size"
        );
    }

    function test_getSizeFor_whenTargetBelowTickSize_returnsZero() public view {
        // Use a target that is below the fixed tick size
        uint256 target = tickSize - 1; // Just below tick size

        assertEq(
            emissionManager.getSizeFor(target),
            0,
            "Should return 0 when target is below tick size"
        );
    }

    function test_getSizeFor_whenTargetAboveTickSize_returnsTickSize() public view {
        // Use a target that is well above the fixed tick size
        uint256 target = tickSize * 10; // 10x the tick size

        assertEq(
            emissionManager.getSizeFor(target),
            tickSize,
            "Should return tick size when target is above tick size"
        );
    }

    function test_execute_whenCalculatedTickSizeIsZero_setsTargetToZero()
        public
        givenNextBeatIsZero
        givenPremiumAboveMinimum
    {
        // Get the expected emission first, then set tick size higher
        (, , uint256 originalEmission) = emissionManager.getNextEmission();
        assertGt(originalEmission, 0, "Original emission should be > 0");

        // Set tick size higher than the emission so that getSizeFor returns 0
        vm.prank(guardian);
        emissionManager.setTickSize(originalEmission + 1); // Just above the emission

        // Verify that calculated tick size would be 0
        uint256 calculatedTickSize = emissionManager.getSizeFor(originalEmission);
        assertEq(calculatedTickSize, 0, "Calculated tick size should be 0");

        // Call execute
        vm.prank(heart);
        emissionManager.execute();

        // Verify that both target and tick size were set to 0 in the auctioneer
        assertEq(cdAuctioneer.target(), 0, "Target should be set to 0 when tick size is 0");
        assertEq(cdAuctioneer.tickSize(), 0, "Tick size should be 0");
        assertEq(cdAuctioneer.isAuctionActive(), false, "Auction should be inactive");
    }

    function test_disable_disablesAuction() public {
        // First enable the emission manager with some auction parameters
        vm.prank(heart);
        emissionManager.execute();

        // Disable the emission manager
        vm.prank(guardian);
        emissionManager.disable("");

        // Verify that the auction is disabled (target = 0, tickSize = 0)
        assertEq(cdAuctioneer.target(), 0, "Target should be 0 when EmissionManager is disabled");
        assertEq(
            cdAuctioneer.tickSize(),
            0,
            "Tick size should be 0 when EmissionManager is disabled"
        );
        assertEq(cdAuctioneer.isAuctionActive(), false, "Auction should be inactive");
        assertFalse(emissionManager.isEnabled(), "EmissionManager should be disabled");
    }
}
