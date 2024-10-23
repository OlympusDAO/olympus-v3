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
    uint256 internal minimumPremium = 25e16; // 25% premium
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
    //        [X] when premium is greater than or equal to the minimum premium
    //           [X] sell amount is calculated as the base emissions rate * (1 + premium) / (1 + minimum premium)
    //           [X] it creates a new bond market with the sell amount
    //        [X] when premium is less than the minimum premium
    //           [X] it does not create a new bond market
    //        [ ] when there is a postitive emissions adjustment
    //           [ ] it adjusts the emissions rate by the adjustment amount before calculating the sell amount
    //        [ ] when there is a negative emissions adjustment
    //           [ ] it adjusts the emissions rate by the adjustment amount before calculating the sell amount
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
    //             [X] it deposits the reserve balance into the wrappedReserve contract with the TRSRY as the recipient
    //
    // [ ] bond market purchase tests
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

        // Approve the emission manager to use a bond callback on the auctioneer
        vm.prank(guardian);
        auctioneer.setCallbackAuthStatus(address(emissionManager), true);

        // Total Reserves = $50M + $50 M = $100M
        // Total Supply = 10,000,000 OHM
        // => Backing = $100M / 10,000,000 OHM = $10 / OHM
        // Price is set at $15 / OHM, so a 50% premium, which is above the 25% minimum premium

        // Emissions Rate is initially set to 0.1% of supply per day at the minimum premium
        // This means the capacity of the initial bond market if premium == minimum premium
        // is 0.1% * 10,000,000 OHM = 10,000 OHM
        // For the case where the premium is 50%, then the capacity is:
        // 10,000 OHM * (1 + 0.5) / (1 + 0.25) = 12,000 OHM
    }

    // internal helper functions
    modifier givenNextBeatIsZero() {
        // Execute twice to get beat counter to 2
        vm.startPrank(heart);
        emissionManager.execute();
        emissionManager.execute();
        vm.stopPrank();
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
        emissionManager.execute();
        vm.stopPrank();
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

    function test_execute_whenNextBeatNotZero_incrementsCounter() public {
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
        assertEq(aggregator.marketCounter(), nextBondMarketId);

        // Confirm that the token balances are still 0
        assertEq(ohm.balanceOf(address(emissionManager)), 0, "OHM balance should be 0");
        assertEq(reserve.balanceOf(address(emissionManager)), 0, "Reserve balance should be 0");

        // Confirm that the beat counter is now 0
        assertEq(emissionManager.beatCounter(), 0, "Beat counter should be 0");
    }

    function test_execute_whenNextBeatIsZero_whenPremiumEqualMinimum_whenNoAdjustment()
        public
        givenNextBeatIsZero
        givenPremiumEqualToMinimum
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
            assertEq(
                callbackAddr,
                address(emissionManager),
                "Callback address should be the emissions manager"
            );
            assertEq(isCapacityInQuote, false, "Capacity should not be in quote token");
            assertEq(
                capacity,
                (((baseEmissionsRate * PRICE.getLastPrice()) /
                    ((backing * (1e18 + minimumPremium)) / 1e18)) *
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
    }

    function test_execute_whenNextBeatIsZero_givenPremiumAboveMinimum_whenNoAdjustment()
        public
        givenNextBeatIsZero
        givenPremiumAboveMinimum
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
            assertEq(
                callbackAddr,
                address(emissionManager),
                "Callback address should be the emissions manager"
            );
            assertEq(isCapacityInQuote, false, "Capacity should not be in quote token");
            assertEq(
                capacity,
                (((baseEmissionsRate * PRICE.getLastPrice()) /
                    ((backing * (1e18 + minimumPremium)) / 1e18)) *
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
    ) public {
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

        // Cache the initial OHM balance of the teller and the wrappedReserve balance of the TRSRY
        uint256 tellerBalance = ohm.balanceOf(address(teller));
        uint256 treasuryBalance = wrappedReserve.balanceOf(address(TRSRY));

        // Cache the current backing value in the emissions manager
        uint256 _backing = emissionManager.backing();

        // Cache the reserves and supply values for the backing update calculation
        uint256 reserves = emissionManager.getReserves();
        uint256 supply = emissionManager.getSupply();

        uint256 expectedBacking = (_backing * ((input * 1e18) / reserves)) /
            ((output * 1e18) / supply);

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
            wrappedReserve.balanceOf(address(TRSRY)),
            treasuryBalance + input, // can use the reserve amount as the wrappedReserve amount since the conversion rate is 1:1
            "TRSRY wrapped reserve balance should be updated"
        );
    }
}
