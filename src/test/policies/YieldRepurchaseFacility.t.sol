// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "src/test/lib/UserFactory.sol";

import {BondFixedTermSDA} from "src/test/lib/bonds/BondFixedTermSDA.sol";
import {BondAggregator} from "src/test/lib/bonds/BondAggregator.sol";
import {BondFixedTermTeller} from "src/test/lib/bonds/BondFixedTermTeller.sol";
import {RolesAuthority, Authority as SolmateAuthority} from "solmate/auth/authorities/RolesAuthority.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {MockPrice} from "src/test/mocks/MockPrice.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockClearinghouse} from "src/test/mocks/MockClearinghouse.sol";
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";

import {FullMath} from "libraries/FullMath.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {OlympusClearinghouseRegistry} from "modules/CHREG/OlympusClearinghouseRegistry.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {YieldRepurchaseFacility} from "policies/YieldRepurchaseFacility.sol";
import {IYieldRepo} from "policies/interfaces/IYieldRepo.sol";

// solhint-disable-next-line max-states-count
contract YieldRepurchaseFacilityTest is Test {
    using ModuleTestFixtureGenerator for OlympusClearinghouseRegistry;

    using FullMath for uint256;

    UserFactory public userCreator;
    address internal alice;
    address internal bob;
    address internal guardian;
    address internal policy;
    address internal heart;

    RolesAuthority internal auth;
    BondAggregator internal aggregator;
    BondFixedTermTeller internal teller;
    BondFixedTermSDA internal auctioneer;
    MockOhm internal ohm;
    MockERC20 internal reserve;
    MockERC4626 internal sReserve;
    MockERC20 internal oldReserve;

    Kernel internal kernel;
    MockPrice internal PRICE;
    OlympusTreasury internal TRSRY;
    OlympusMinter internal MINTR;
    OlympusRoles internal ROLES;
    OlympusClearinghouseRegistry internal CHREG;
    address internal godmode;

    MockClearinghouse internal clearinghouse;
    YieldRepurchaseFacility internal yieldRepo;
    RolesAdmin internal rolesAdmin;

    uint256 internal initialReserves = 105_000_000e18;
    uint256 internal initialConversionRate = 1_05e16;
    uint256 internal initialPrincipalReceivables = 100_000_000e18;
    uint256 internal initialYield = 50_000e18 + ((initialPrincipalReceivables * 5) / 1000) / 52;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            /// Deploy bond system to test against
            address[] memory users = userCreator.create(5);
            alice = users[0];
            bob = users[1];
            guardian = users[2];
            policy = users[3];
            heart = users[4];
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
            reserve = new MockERC20("Reserve", "RSV", 18);
            oldReserve = new MockERC20("Old Reserve", "oRSV", 18);
            sReserve = new MockERC4626(reserve, "sReserve", "sRSV");
        }

        {
            /// Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            /// Deploy modules (some mocks)
            PRICE = new MockPrice(kernel, uint48(8 hours), 10 * 1e18);
            TRSRY = new OlympusTreasury(kernel);
            MINTR = new OlympusMinter(kernel, address(ohm));
            ROLES = new OlympusRoles(kernel);

            // Deploy mock clearinghouse and registry
            clearinghouse = new MockClearinghouse(address(reserve), address(sReserve));
            CHREG = new OlympusClearinghouseRegistry(
                kernel,
                address(clearinghouse),
                new address[](0)
            );

            /// Configure mocks
            PRICE.setMovingAverage(10 * 1e18);
            PRICE.setLastPrice(10 * 1e18);
            PRICE.setDecimals(18);
            PRICE.setLastTime(uint48(block.timestamp));
        }

        {
            /// Deploy protocol loop
            yieldRepo = new YieldRepurchaseFacility(
                kernel,
                address(ohm),
                address(sReserve),
                address(teller),
                address(auctioneer)
            );

            /// Deploy ROLES administrator
            rolesAdmin = new RolesAdmin(kernel);
        }

        {
            /// Initialize system and kernel

            /// Install modules
            kernel.executeAction(Actions.InstallModule, address(PRICE));
            kernel.executeAction(Actions.InstallModule, address(TRSRY));
            kernel.executeAction(Actions.InstallModule, address(MINTR));
            kernel.executeAction(Actions.InstallModule, address(ROLES));
            kernel.executeAction(Actions.InstallModule, address(CHREG));

            /// Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(yieldRepo));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }
        {
            /// Configure access control

            /// YieldRepurchaseFacility ROLES
            rolesAdmin.grantRole("heart", address(heart));
            rolesAdmin.grantRole("admin", guardian);
        }

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

        // Initialize the yield repo facility
        vm.prank(guardian);
        yieldRepo.enable(
            abi.encode(
                IYieldRepo.EnableParams({
                    initialReserveBalance: initialReserves,
                    initialConversionRate: initialConversionRate,
                    initialYield: initialYield
                })
            )
        );
    }

    function _mintYield() internal {
        // Get the balance of reserves in the sReserve contract
        uint256 sReserveBalance = sReserve.totalAssets();

        // Calculate the yield to mint (0.01%)
        uint256 yield = sReserveBalance / 10000;

        // Mint the yield
        reserve.mint(address(sReserve), yield);
    }

    // test cases
    // [X] setup (contructor + configureDependencies)
    //   [X] addresses are set correctly
    //   [X] initial reserve balance is set correctly
    //   [X] initial conversion rate is set correctly
    //   [X] initial yield is set correctly
    //   [X] epoch is set correctly
    // [X] endEpoch
    //   [X] when contract is shutdown
    //     [X] nothing happens
    //   [X] when contract is not shutdown
    //     [X] when epoch is not divisible by 3
    //       [X] nothing happens
    //     [X] when epoch is divisible by 3
    //       [X] when epoch == epochLength
    //         [X] The yield earned on the wrapped reserves over the past 21 epochs is withdrawn from the TRSRY (affecting the balanceInDai and bidAmount)
    //         [X] OHM in the contract is burned and reserves are added at the backing rate
    //         [X] given current price is less than upper wall
    //           [ ] a new bond market is created with correct bid amount
    //         [X] given current price is greater than or equal to upper wall
    //       [X] when epoch != epochLength
    //         [X] OHM in the contract is burned and reserves are added at the backing rate
    //         [X] a new bond market is created with correct bid amount
    // [X] adjustNextYield
    // [X] shutdown
    // [X] getNextYield
    // [X] getReserveBalance
    //  [ ] includes yield in the ConvertibleDepositFacility

    function test_setup() public view {
        // addresses are set correctly
        assertEq(address(yieldRepo.ohm()), address(ohm));
        assertEq(address(yieldRepo.reserve()), address(reserve));
        assertEq(address(yieldRepo.sReserve()), address(sReserve));
        assertEq(address(yieldRepo.teller()), address(teller));
        assertEq(address(yieldRepo.auctioneer()), address(auctioneer));

        // initial reserve balance is set correctly
        assertEq(yieldRepo.lastReserveBalance(), initialReserves);
        assertEq(yieldRepo.getReserveBalance(), initialReserves);

        // initial conversion rate is set correctly
        assertEq(yieldRepo.lastConversionRate(), initialConversionRate);
        assertEq((sReserve.totalAssets() * 1e18) / sReserve.totalSupply(), 1_05e16);

        // initial yield is set correctly
        assertEq(yieldRepo.nextYield(), initialYield);

        // epoch is set correctly
        assertEq(yieldRepo.epoch(), 20);
    }

    function test_endEpoch_firstCall_currentLessThanWall() public {
        // Mint yield to the sReserve
        _mintYield();

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Cache the TRSRY sDAI balance
        uint256 trsryBalance = sReserve.balanceOf(address(TRSRY));

        vm.prank(heart);
        yieldRepo.endEpoch();

        // Check that the initial yield was withdrawn from the TRSRY
        assertEq(
            sReserve.balanceOf(address(TRSRY)),
            trsryBalance - sReserve.previewWithdraw(initialYield)
        );

        // Check that the yieldRepo contract has the correct reserve balance
        assertEq(reserve.balanceOf(address(yieldRepo)), initialYield / 7);
        assertEq(
            sReserve.balanceOf(address(yieldRepo)),
            sReserve.previewDeposit(initialYield - initialYield / 7)
        );

        // Check that the bond market was created
        assertEq(aggregator.marketCounter(), nextBondMarketId + 1);

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

            assertEq(owner, address(yieldRepo));
            assertEq(address(payoutToken), address(reserve));
            assertEq(address(quoteToken), address(ohm));
            assertEq(callbackAddr, address(0));
            assertEq(isCapacityInQuote, false);
            assertEq(capacity, uint256(initialYield) / 7);
            assertEq(maxPayout, capacity / 6);

            assertEq(scale, 10 ** uint8(36 + 18 - 9 + 0));
            assertEq(
                marketPrice,
                ((uint256(1e36) / ((10e18 * 97) / 100)) * 10 ** uint8(36 + 1)) / 10 ** uint8(18 + 1)
            );
            assertEq(minPrice, 0);
        }

        // Check that the epoch has been incremented
        assertEq(yieldRepo.epoch(), 0);
    }

    function test_endEpoch_firstCall_currentGreaterThanWall() public {
        // Change the current price to be greater than the wall
        PRICE.setLastPrice(15 * 1e18);

        // Mint yield to the sReserve
        _mintYield();

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Cache the TRSRY sDAI balance
        uint256 trsryBalance = sReserve.balanceOf(address(TRSRY));

        vm.prank(heart);
        yieldRepo.endEpoch();

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

        // Check that a bond market was created
        // This is because the current price is greater than the wall, and the wall no longer prevents a new bond market from being created
        assertEq(aggregator.marketCounter(), nextBondMarketId + 1, "marketCount");
    }

    function test_endEpoch_isShutdown() public {
        // Shutdown the yieldRepo contract
        vm.prank(guardian);
        yieldRepo.disable(abi.encode(new address[](0)));

        // Mint yield to the sReserve
        _mintYield();

        // Get the ID of the next bond market from the aggregator
        uint256 nextBondMarketId = aggregator.marketCounter();

        // Cache the TRSRY sDAI balance
        uint256 trsryBalance = sReserve.balanceOf(address(TRSRY));

        vm.prank(heart);
        yieldRepo.endEpoch();

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
        yieldRepo.endEpoch();

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
        yieldRepo.endEpoch();

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
        // Mint yield to the sReserve
        _mintYield();

        // Make the initial call to get the epoch counter to reset
        vm.prank(heart);
        yieldRepo.endEpoch();

        // Call end epoch twice to setup our test
        vm.prank(heart);
        yieldRepo.endEpoch();
        vm.prank(heart);
        yieldRepo.endEpoch();

        // Confirm that the epoch is 2
        assertEq(yieldRepo.epoch(), 2);

        // Cache the yieldRepo contract reserve balance before any bonds are issued
        uint256 yieldRepoReserveBalance = reserve.balanceOf(address(yieldRepo));
        uint256 yieldRepoWrappedReserveBalance = sReserve.balanceOf(address(yieldRepo));

        // Purchase a bond from the existing bond market
        // So that there is some OHM in the contract to burn
        vm.prank(alice);
        (uint256 bondPayout, ) = teller.purchase(alice, address(0), 0, 100e9, 0);

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
        assertEq(yieldRepoOhmBalance, 100e9);

        // Call end epoch again
        vm.prank(heart);
        yieldRepo.endEpoch();

        // Check that a new bond market was created
        assertEq(
            aggregator.marketCounter(),
            nextBondMarketId + 1,
            "bond market id should be incremented"
        );

        // Check that the yieldRepo contract burned the OHM
        assertEq(ohm.balanceOf(address(yieldRepo)), 0, "OHM should be burned");

        // Check that the treasury balance has changed by the amount of backing withdrawn for the burnt OHM
        uint256 reserveFromBurnedOhm = 100e9 * yieldRepo.backingPerToken();
        assertEq(
            sReserve.balanceOf(address(TRSRY)),
            trsryBalance - sReserve.previewWithdraw(reserveFromBurnedOhm),
            "treasury balance should decrease by the amount of backing withdrawn for the burnt OHM"
        );

        // Check that the balance of the yieldRepo contract has changed correctly
        uint256 expectedBidAmount = (yieldRepoReserveBalance +
            sReserve.previewRedeem(yieldRepoWrappedReserveBalance) +
            reserveFromBurnedOhm) / 6;

        // Check that the yieldRepo contract reserve balances have changed correctly
        assertEq(
            reserve.balanceOf(address(yieldRepo)),
            expectedBidAmount,
            "reserve balance should increase by the  bid amount"
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

            assertEq(scale, 10 ** uint8(36 + 18 - 9 + 0), "scale");
            assertEq(
                marketPrice,
                ((uint256(1e36) / ((10e18 * 97) / 100)) * 10 ** uint8(36 + 1)) /
                    10 ** uint8(18 + 1),
                "marketPrice"
            );
            assertEq(minPrice, 0, "minPrice");
        }
    }

    // error ROLES_RequireRole(bytes32 role_);

    function test_adjustNextYield() public {
        // Mint yield to the sReserve
        _mintYield();

        // Call endEpoch to set the next yield
        vm.prank(heart);
        yieldRepo.endEpoch();

        // Get the next yield value
        uint256 nextYield = yieldRepo.nextYield();

        // Try to call adjustNextYield with an invalid caller
        // Expect it to fail
        vm.expectRevert(abi.encodeWithSignature("ROLES_RequireRole(bytes32)", bytes32("admin")));
        vm.prank(alice);
        yieldRepo.adjustNextYield(nextYield);

        // Call adjustNextYield with a value that is too high
        // Expect it to fail
        uint256 newNextYield = (nextYield * 12) / 10;

        vm.expectRevert(abi.encodeWithSignature("TooMuchIncrease()"));
        vm.prank(guardian);
        yieldRepo.adjustNextYield(newNextYield);

        // Call adjustNextYield with a value greater than the current yield but only by 10%
        // Expect it to succeed
        newNextYield = (nextYield * 11) / 10;
        vm.prank(guardian);
        yieldRepo.adjustNextYield(newNextYield);

        // Check that the next yield has been adjusted
        assertEq(yieldRepo.nextYield(), newNextYield);

        // Call adjustNextYield with a value that is lower than the current yield
        // Expect it to succeed
        newNextYield = (newNextYield * 9) / 10;
        vm.prank(guardian);
        yieldRepo.adjustNextYield(newNextYield);

        // Check that the next yield has been adjusted
        assertEq(yieldRepo.nextYield(), newNextYield);

        // Call adjustNextYield with a value of zero next yield
        // Expect it to succeed
        vm.prank(guardian);
        yieldRepo.adjustNextYield(0);

        // Check that the next yield has been adjusted
        assertEq(yieldRepo.nextYield(), 0);
    }

    function test_shutdown() public {
        // Try to call shutdown as an invalid caller
        // Expect it to fail
        vm.expectRevert(abi.encodeWithSignature("NotAuthorised()"));
        vm.prank(alice);
        yieldRepo.disable(abi.encode(new address[](0)));

        // Mint yield
        _mintYield();

        // Call endEpoch initially to get tokens into the contract
        vm.prank(heart);
        yieldRepo.endEpoch();

        // Cache the yieldRepo contract reserve balances
        uint256 yieldRepoReserveBalance = reserve.balanceOf(address(yieldRepo));
        uint256 yieldRepoWrappedReserveBalance = sReserve.balanceOf(address(yieldRepo));

        // Cache the treasury balances of the reserve tokens
        uint256 trsryReserveBalance = reserve.balanceOf(address(TRSRY));
        uint256 trsryWrappedReserveBalance = sReserve.balanceOf(address(TRSRY));

        // Setup array of tokens to extract
        ERC20[] memory tokens = new ERC20[](2);
        tokens[0] = reserve;
        tokens[1] = sReserve;

        // Call shutdown with an invalid caller
        // Expect it to fail
        vm.expectRevert(abi.encodeWithSignature("NotAuthorised()"));
        vm.prank(bob);
        yieldRepo.disable(abi.encode(tokens));

        // Call shutdown with a valid caller
        // Expect it to succeed
        vm.prank(guardian);
        yieldRepo.disable(abi.encode(tokens));

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
        yieldRepo.endEpoch();

        // Cache yield earning balances in the clearinghouse and treasury
        uint256 clearinghouseWrappedReserveBalance = sReserve.balanceOf(address(clearinghouse));
        uint256 trsryWrappedReserveBalance = sReserve.balanceOf(address(TRSRY));

        // Calculate the expected yield earning reserve balance, in reserves
        uint256 expectedYieldEarningReserveBalance = sReserve.previewRedeem(
            clearinghouseWrappedReserveBalance + trsryWrappedReserveBalance
        );

        // Confirm the view function matches
        assertEq(yieldRepo.getReserveBalance(), expectedYieldEarningReserveBalance);

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
        assertEq(yieldRepo.getReserveBalance(), expectedYieldEarningReserveBalance);
    }

    function test_getNextYield() public {
        // Mint yield
        _mintYield();

        // Call endEpoch initially to get tokens into the contract
        vm.prank(heart);
        yieldRepo.endEpoch();

        // Get the "last values" from the yieldRepo contract
        uint256 lastReserveBalance = yieldRepo.lastReserveBalance();

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
        assertEq(yieldRepo.getNextYield(), expectedNextYield);

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
        assertEq(yieldRepo.getNextYield(), expectedNextYield);

        // Deactivate the old clearinghouse, ensure its receivables are still included
        vm.prank(godmode);
        CHREG.deactivateClearinghouse(address(clearinghouse));

        // Confirm the view function matches
        assertEq(yieldRepo.getNextYield(), expectedNextYield);
    }
}
