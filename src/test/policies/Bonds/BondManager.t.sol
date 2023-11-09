// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {larping} from "test/lib/larping.sol";
import {console2} from "forge-std/console2.sol";

import {OlympusERC20Token, IOlympusAuthority} from "src/external/OlympusERC20.sol";
import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626, ERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {MockLegacyAuthority} from "test/modules/MINTR.t.sol";

import "src/Kernel.sol";

import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";

import {BondCallback} from "policies/Bonds/BondCallback.sol";
import {BondManager} from "policies/Bonds/BondManager.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

import {RolesAuthority, Authority as SolmateAuthority} from "solmate/auth/authorities/RolesAuthority.sol";
import {MockAggregator} from "test/mocks/MockAggregator.sol";
import {MockFixedExpirySDA} from "test/mocks/MockFixedExpirySDA.sol";
import {MockFixedExpiryTeller} from "test/mocks/MockFixedExpiryTeller.sol";
import {MockEasyAuction} from "test/mocks/MockEasyAuction.sol";

import {IBondAggregator} from "interfaces/IBondAggregator.sol";

// solhint-disable-next-line max-states-count
contract BondManagerTest is Test {
    using larping for *;

    UserFactory public userCreator;
    address internal alice;
    address internal guardian;
    address internal policy;

    IOlympusAuthority internal legacyAuth;
    OlympusERC20Token internal ohm;
    MockERC20 internal reserve;
    MockERC4626 internal wrappedReserve;

    Kernel internal kernel;
    OlympusMinter internal MINTR;
    OlympusTreasury internal TRSRY;
    OlympusRoles internal ROLES;

    RolesAdmin internal rolesAdmin;
    BondCallback internal bondCallback;
    BondManager internal bondManager;

    RolesAuthority internal auth;
    MockAggregator internal aggregator;
    MockFixedExpirySDA internal fixedExpirySDA;
    MockFixedExpiryTeller internal fixedExpiryTeller;
    MockEasyAuction internal easyAuction;

    // Bond Protocol Parameters
    uint256 internal INITIAL_PRICE = 1000000000000000000000000000000000000;
    uint256 internal MIN_PRICE = 500000000000000000000000000000000000;
    uint48 internal AUCTION_TIME = 7 * 24 * 60 * 60;
    uint32 internal DEBT_BUFFER = 100000;
    uint32 internal DEPOSIT_INTERVAL = 6 * 60 * 60;

    // Gnosis Parameters
    uint48 internal AUCTION_CANCEL_TIME = 6 * 24 * 60 * 60;
    uint96 internal MIN_PCT_SOLD = 50;
    uint256 internal MIN_BUY_AMOUNT = 1000000000;
    uint256 internal MIN_FUNDING_THRESHOLD = 1000000000000;

    function setUp() public {
        userCreator = new UserFactory();

        // Initialize users
        {
            address[] memory users = userCreator.create(3);
            alice = users[0];
            guardian = users[1];
            policy = users[2];
            auth = new RolesAuthority(guardian, SolmateAuthority(address(0)));
            legacyAuth = new MockLegacyAuthority(address(0x0));
        }

        // Deploy bond system
        {
            fixedExpiryTeller = new MockFixedExpiryTeller();
            fixedExpirySDA = new MockFixedExpirySDA();
            aggregator = new MockAggregator(address(fixedExpirySDA), address(fixedExpiryTeller));
            easyAuction = new MockEasyAuction();
        }

        // Deploy tokens
        {
            ohm = new OlympusERC20Token(address(legacyAuth));
            reserve = new MockERC20("Reserve", "RSV", 18);
            wrappedReserve = new MockERC4626(reserve, "wrappedReserve", "sRSV");
        }

        // Deploy kernel and modules
        {
            kernel = new Kernel();

            MINTR = new OlympusMinter(kernel, address(ohm));
            TRSRY = new OlympusTreasury(kernel);
            ROLES = new OlympusRoles(kernel);
        }

        // Deploy policies
        {
            rolesAdmin = new RolesAdmin(kernel);
            bondCallback = new BondCallback(
                kernel,
                IBondAggregator(address(aggregator)),
                ERC20(address(ohm))
            );
            bondManager = new BondManager(
                kernel,
                address(fixedExpirySDA),
                address(fixedExpiryTeller),
                address(easyAuction),
                address(ohm)
            );
        }

        // Initialize modules and policies
        {
            // Install modules
            kernel.executeAction(Actions.InstallModule, address(MINTR));
            kernel.executeAction(Actions.InstallModule, address(TRSRY));
            kernel.executeAction(Actions.InstallModule, address(ROLES));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
            kernel.executeAction(Actions.ActivatePolicy, address(bondCallback));
            kernel.executeAction(Actions.ActivatePolicy, address(bondManager));
        }

        // Configuration
        {
            // Bond Manager ROLES
            rolesAdmin.grantRole("bondmanager_admin", policy);

            // Bond Callback ROLES
            rolesAdmin.grantRole("callback_whitelist", policy);
            rolesAdmin.grantRole("callback_whitelist", address(bondManager));
            rolesAdmin.grantRole("callback_admin", guardian);

            // OHM Authority Vault
            legacyAuth.vault.larp(address(MINTR));

            // Mint OHM to this contract
            vm.prank(address(MINTR));
            ohm.mint(address(this), 100_000_000_000_000);

            // Approve teller to spend OHM
            ohm.increaseAllowance(address(fixedExpiryTeller), 100_000_000_000_000);
        }
    }

    // ======== SETUP DEPENDENCIES ======= //

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](3);
        expectedDeps[0] = toKeycode("MINTR");
        expectedDeps[1] = toKeycode("TRSRY");
        expectedDeps[2] = toKeycode("ROLES");

        Keycode[] memory deps = bondManager.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
        assertEq(fromKeycode(deps[2]), fromKeycode(expectedDeps[2]));
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](4);
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        expectedPerms[0] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        expectedPerms[1] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        expectedPerms[2] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
        expectedPerms[3] = Permissions(MINTR_KEYCODE, MINTR.decreaseMintApproval.selector);

        Permissions[] memory perms = bondManager.requestPermissions();
        // Check: permission storage
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    //============================================================================================//
    //                                      ADMIN FUNCTIONS                                       //
    //============================================================================================//

    /// [X]  setFixedExpiryParameters()
    ///     [X]  Can only be accessed by an address with bondmanager_admin role
    ///     [X]  Correctly sets parameters

    function testCorrectness_setFixedExpiryParametersRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        bondManager.setFixedExpiryParameters(
            INITIAL_PRICE,
            MIN_PRICE,
            AUCTION_TIME,
            DEBT_BUFFER,
            DEPOSIT_INTERVAL,
            false
        );
    }

    function testCorrectness_correctlySetsFixedExpiryParameters() public {
        // Verify initial state
        (
            uint256 initialPrice,
            uint256 minPrice,
            uint48 auctionTime,
            uint32 debtBuffer,
            uint32 depositInterval,
            bool capacityInQuote
        ) = bondManager.fixedExpiryParameters();
        assertEq(initialPrice, 0);
        assertEq(minPrice, 0);
        assertEq(auctionTime, 0);
        assertEq(debtBuffer, 0);
        assertEq(depositInterval, 0);
        assertEq(capacityInQuote, false);

        // Set parameters
        vm.prank(policy);
        bondManager.setFixedExpiryParameters(
            INITIAL_PRICE,
            MIN_PRICE,
            AUCTION_TIME,
            DEBT_BUFFER,
            DEPOSIT_INTERVAL,
            true
        );

        // Verify end state
        (
            initialPrice,
            minPrice,
            auctionTime,
            debtBuffer,
            depositInterval,
            capacityInQuote
        ) = bondManager.fixedExpiryParameters();
        assertEq(initialPrice, INITIAL_PRICE);
        assertEq(minPrice, MIN_PRICE);
        assertEq(auctionTime, AUCTION_TIME);
        assertEq(debtBuffer, DEBT_BUFFER);
        assertEq(depositInterval, DEPOSIT_INTERVAL);
        assertEq(capacityInQuote, true);
    }

    /// [X]  setBatchAuctionParameters()
    ///     [X]  Can only be accessed by an address with bondmanager_admin role
    ///     [X]  Correctly sets parameters

    function testCorrectness_setBatchParametersRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        bondManager.setBatchAuctionParameters(
            AUCTION_CANCEL_TIME,
            AUCTION_TIME,
            MIN_PCT_SOLD,
            MIN_BUY_AMOUNT,
            MIN_FUNDING_THRESHOLD
        );
    }

    function testCorrectness_correctlySetsBatchParameters() public {
        // Verify initial state
        (
            uint256 auctionCancelTime,
            uint256 auctionTime,
            uint96 minPctSold,
            uint256 minBuyAmount,
            uint256 minFundingThreshold
        ) = bondManager.batchAuctionParameters();
        assertEq(auctionCancelTime, 0);
        assertEq(auctionTime, 0);
        assertEq(minPctSold, 0);
        assertEq(minBuyAmount, 0);
        assertEq(minFundingThreshold, 0);

        // Set parameters
        vm.prank(policy);
        bondManager.setBatchAuctionParameters(
            AUCTION_CANCEL_TIME,
            AUCTION_TIME,
            MIN_PCT_SOLD,
            MIN_BUY_AMOUNT,
            MIN_FUNDING_THRESHOLD
        );

        // Verify end state
        (
            auctionCancelTime,
            auctionTime,
            minPctSold,
            minBuyAmount,
            minFundingThreshold
        ) = bondManager.batchAuctionParameters();
        assertEq(auctionCancelTime, AUCTION_CANCEL_TIME);
        assertEq(auctionTime, AUCTION_TIME);
        assertEq(minPctSold, MIN_PCT_SOLD);
        assertEq(minBuyAmount, MIN_BUY_AMOUNT);
        assertEq(minFundingThreshold, MIN_FUNDING_THRESHOLD);
    }

    /// [X]  setCallback()
    ///     [X]  Can only be accessed by an address with bondmanager_admin role
    ///     [X]  Correctly sets callback address

    function testCorrectness_setCallbackRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        bondManager.setCallback(bondCallback);
    }

    function testCorrectness_correctlySetsCallbackAddress() public {
        // Verify initial state
        assertEq(address(bondManager.bondCallback()), address(0));

        // Set callback
        vm.prank(policy);
        bondManager.setCallback(bondCallback);

        // Verify end state
        assertEq(address(bondManager.bondCallback()), address(bondCallback));
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// [X]  createFixedExpiryBondMarket()
    ///     [X]  Can only be accessed by an address with bondmanager_admin role
    ///     [X]  Correctly launches a fixed expiry market

    function _createBondSetup() internal {
        vm.startPrank(policy);
        bondManager.setFixedExpiryParameters(
            INITIAL_PRICE,
            MIN_PRICE,
            AUCTION_TIME,
            DEBT_BUFFER,
            DEPOSIT_INTERVAL,
            false
        );
        bondManager.setCallback(bondCallback);
        vm.stopPrank();
    }

    function testCorrectness_createFixedExpiryRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        bondManager.createFixedExpiryBondMarket(10_000_000_000_000, 2 weeks);
    }

    function testCorrectness_createFixedExpiryLaunchesMarket() public {
        _createBondSetup();

        // Launch market
        vm.prank(policy);
        uint256 marketId = bondManager.createFixedExpiryBondMarket(10_000_000_000_000, 2 weeks);

        // Verify market state
        (
            address owner,
            ERC20 payoutToken,
            ERC20 quoteToken,
            address callbackAddr,
            bool capacityInQuote,
            uint256 capacity,
            ,
            ,
            ,
            uint256 sold,
            ,

        ) = fixedExpirySDA.markets(marketId);
        assertEq(owner, address(bondManager));
        assertEq(address(payoutToken), address(ohm));
        assertEq(address(quoteToken), address(ohm));
        assertEq(callbackAddr, address(bondCallback));
        assertEq(capacityInQuote, false);
        assertEq(capacity, 10_000_000_000_000);
        assertEq(sold, 0);
    }

    /// [X]  closeFixedExpiryBondMarket()
    ///     [X]  Can only be accessed by an address with bondmanager_admin role
    ///     [X]  Correcly shuts down market

    function _closeMarketSetup() internal {
        vm.startPrank(policy);
        bondManager.setFixedExpiryParameters(
            INITIAL_PRICE,
            MIN_PRICE,
            AUCTION_TIME,
            DEBT_BUFFER,
            DEPOSIT_INTERVAL,
            false
        );
        bondManager.setCallback(bondCallback);
        bondManager.createFixedExpiryBondMarket(10_000_000_000_000, 2 weeks);
        vm.stopPrank();
    }

    function testCorrectness_closeFixedExpiryRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        // This attempts to close a non-existent market but it doesn't matter since the
        // user check happens first. Thus, this is still valid.
        vm.prank(user_);
        bondManager.closeFixedExpiryBondMarket(0);
    }

    function testCorrectness_closeFixedExpiryClosesMarket() public {
        _closeMarketSetup();

        vm.prank(policy);
        bondManager.closeFixedExpiryBondMarket(0);

        // Verify market state
        (, , , , , uint256 capacity, , , , , , ) = fixedExpirySDA.markets(0);
        assertEq(capacity, 0);
    }

    /// [X]  createBatchAuction()
    ///     [X]  Can only be accessed by an address with bondmanager_admin role
    ///     [X]  Correctly launches a batch auction

    function _createGnosisSetup() internal {
        vm.prank(policy);
        bondManager.setBatchAuctionParameters(
            AUCTION_CANCEL_TIME,
            AUCTION_TIME,
            MIN_PCT_SOLD,
            MIN_BUY_AMOUNT,
            MIN_FUNDING_THRESHOLD
        );
    }

    function testCorrectness_createBatchAuctionRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        // This attempts to create a market without any of the base parameters set,
        // but it doesn't matter since the user checks first. Thus, this is still valid.
        vm.prank(user_);
        bondManager.createBatchAuction(10_000_000_000_000, 1 weeks);
    }

    function testCorrectness_correctlyLaunchesBatchAuction() public {
        _createGnosisSetup();

        vm.prank(policy);
        uint256 auctionId = bondManager.createBatchAuction(10_000_000_000_000, 1 weeks);

        // Verify end state
        (
            ERC20 auctioningToken,
            ERC20 biddingToken,
            uint256 orderCancellationEndDate,
            uint256 auctionEndDate,
            ,
            ,
            ,

        ) = easyAuction.auctionData(auctionId);

        // assertEq(auctioningToken, bondToken);
        assertEq(address(biddingToken), address(ohm));
        assertEq(orderCancellationEndDate, block.timestamp + 6 days);
        assertEq(auctionEndDate, block.timestamp + 1 weeks);
    }

    /// [X]  settleBatchAuction()
    ///     [X]  Can only be accessed by an address with bondmanager_admin role
    ///     [X]  Correctly settles auction

    function _settleGnosisSetup() internal {
        vm.startPrank(policy);
        bondManager.setBatchAuctionParameters(
            AUCTION_CANCEL_TIME,
            AUCTION_TIME,
            MIN_PCT_SOLD,
            MIN_BUY_AMOUNT,
            MIN_FUNDING_THRESHOLD
        );
        bondManager.createBatchAuction(10_000_000_000_000, 1 weeks);
        vm.stopPrank();
    }

    function testCorrectness_settleBatchAuctionRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        // This attempts to settle an auction without one existing in the first place,
        // but it doesn't matter since the user checks first. Thus, this is still valid.
        vm.prank(user_);
        bondManager.settleBatchAuction(0);
    }

    // Not really much to test here
    function testCorrectness_settlesGnosisAuction() public {
        _settleGnosisSetup();
        uint256 auctionId = easyAuction.auctionCounter();

        // Settle auction
        vm.prank(policy);
        bondManager.settleBatchAuction(auctionId);
    }

    //============================================================================================//
    //                                   EMERGENCY FUNCTIONS                                      //
    //============================================================================================//

    /// [X]  emergencyShutdownFixedExpiryMarket()
    ///     [X]  Can only be accessed by an address with bondmanager_admin role
    ///     [X]  Closes market on auctioneer
    ///     [X]  Blacklists market on callback to stop minting OHM

    function testCorrectness_emergencyShutdownFixedExpiryMarketRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        // This attempts to shutdown an auction without one existing in the first place,
        // but it doesn't matter since the user checks first. Thus, this is still valid.
        vm.prank(user_);
        bondManager.emergencyShutdownFixedExpiryMarket(0);
    }

    function testCorrectness_closesMarketOnAuctioneer() public {
        // Create market
        vm.startPrank(policy);
        bondManager.setFixedExpiryParameters(
            INITIAL_PRICE,
            MIN_PRICE,
            AUCTION_TIME,
            DEBT_BUFFER,
            DEPOSIT_INTERVAL,
            false
        );
        bondManager.setCallback(bondCallback);
        uint256 marketId = bondManager.createFixedExpiryBondMarket(10_000_000_000_000, 2 weeks);

        // Verify market
        assertTrue(fixedExpirySDA.isLive(marketId));

        // Shutdown market
        bondManager.emergencyShutdownFixedExpiryMarket(marketId);

        // Verify shutdown
        assertFalse(fixedExpirySDA.isLive(marketId));
        vm.stopPrank();
    }

    function testCorrectness_blacklistsMarketOnCallback() public {
        // Create market
        vm.startPrank(policy);
        bondManager.setFixedExpiryParameters(
            INITIAL_PRICE,
            MIN_PRICE,
            AUCTION_TIME,
            DEBT_BUFFER,
            DEPOSIT_INTERVAL,
            false
        );
        bondManager.setCallback(bondCallback);
        uint256 marketId = bondManager.createFixedExpiryBondMarket(10_000_000_000_000, 2 weeks);

        // Verify on callback
        assertTrue(bondCallback.approvedMarkets(address(fixedExpiryTeller), marketId));

        // Blacklist
        bondManager.emergencyShutdownFixedExpiryMarket(marketId);

        // Verify shutdown
        assertFalse(bondCallback.approvedMarkets(address(fixedExpiryTeller), marketId));
        vm.stopPrank();
    }

    /// [X]  emergencySetApproval()
    ///     [X]  Can only be accessed by an address with bondmanager_admin role
    ///     [X]  Sets OHM approval correctly

    function testCorrectness_emergencySetApprovalRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        bondManager.emergencySetApproval(address(fixedExpiryTeller), 10000);
    }

    function testCorrectness_setsCorrectOhmApproval(uint256 amount_) public {
        // Verify initial state
        assertEq(ohm.allowance(address(bondManager), address(fixedExpiryTeller)), 0);

        // Set emergency approval
        vm.prank(policy);
        bondManager.emergencySetApproval(address(fixedExpiryTeller), amount_);

        // Verify end state
        assertEq(ohm.allowance(address(bondManager), address(fixedExpiryTeller)), amount_);
    }

    /// [X]  emergencyWithdraw()
    ///     [X]  Can only be accessed by an address with bondmanager_admin role
    ///     [X]  Sends OHM to the treasury

    function testCorrectness_emergencyWithdrawRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        bondManager.emergencyWithdraw(10000);
    }

    function testCorrectness_emergencyWithdrawSendsOhmToTreasury(uint256 amount_) public {
        vm.assume(amount_ <= type(uint256).max - 100_000_000_000_000);

        // Setup
        vm.prank(address(MINTR));
        ohm.mint(address(bondManager), amount_);

        // Verify initial state
        assertEq(ohm.balanceOf(address(bondManager)), amount_);
        assertEq(ohm.balanceOf(address(TRSRY)), 0);

        // Emergency withdrawal
        vm.prank(policy);
        bondManager.emergencyWithdraw(amount_);

        // Verify end state
        assertEq(ohm.balanceOf(address(bondManager)), 0);
        assertEq(ohm.balanceOf(address(TRSRY)), amount_);
    }

    // ========= USER PATH TESTS ========= //

    function _userPathSetup() internal {
        vm.startPrank(policy);
        bondManager.setFixedExpiryParameters(
            INITIAL_PRICE,
            MIN_PRICE,
            AUCTION_TIME,
            DEBT_BUFFER,
            DEPOSIT_INTERVAL,
            false
        );
        bondManager.setBatchAuctionParameters(
            AUCTION_CANCEL_TIME,
            AUCTION_TIME,
            MIN_PCT_SOLD,
            MIN_BUY_AMOUNT,
            MIN_FUNDING_THRESHOLD
        );
        bondManager.setCallback(bondCallback);
        vm.stopPrank();
    }

    /// [X]  Can create fixed expiry and then batch auction
    function testCorrectness_createsMultipleMarkets1() public {
        // Setup
        _userPathSetup();
        vm.startPrank(policy);

        // Verify initial state
        assertEq(ohm.balanceOf(address(bondManager)), 0);
        assertEq(ohm.balanceOf(address(easyAuction)), 0);
        assertEq(ohm.balanceOf(address(fixedExpiryTeller)), 0);

        // Create Bond Protocol market
        uint256 marketId = bondManager.createFixedExpiryBondMarket(10_000_000_000_000, 2 weeks);

        // Create Gnosis market
        bondManager.createBatchAuction(10_000_000_000_000, 1 weeks);
        MockERC20 bondToken = fixedExpiryTeller.bondToken();

        vm.stopPrank();

        // Verify post-launch state
        assertEq(ohm.allowance(address(bondManager), address(fixedExpiryTeller)), 0);
        assertEq(ohm.balanceOf(address(bondManager)), 0);
        assertEq(ohm.balanceOf(address(fixedExpiryTeller)), 10_000_000_000_000);
        assertEq(bondToken.balanceOf(address(easyAuction)), 10_000_000_000_000);
    }

    /// [X]  Can create batch then fixed expiry then batch
    function testCorrectness_createsMultipleMarkets2() public {
        // Setup
        _userPathSetup();
        vm.startPrank(policy);

        // Verify initial state
        assertEq(ohm.balanceOf(address(bondManager)), 0);
        assertEq(ohm.balanceOf(address(easyAuction)), 0);
        assertEq(ohm.balanceOf(address(fixedExpiryTeller)), 0);

        // Create Gnosis market 1
        bondManager.createBatchAuction(10_000_000_000_000, 1 weeks);
        MockERC20 bondToken = fixedExpiryTeller.bondToken();

        // Create Bond Protocol market
        uint256 marketId = bondManager.createFixedExpiryBondMarket(10_000_000_000_000, 2 weeks);

        // Create Gnosis market 2
        bondManager.createBatchAuction(10_000_000_000_000, 2 weeks);

        vm.stopPrank();

        // Verify post-launch state
        assertEq(ohm.allowance(address(bondManager), address(fixedExpiryTeller)), 0);
        assertEq(ohm.balanceOf(address(bondManager)), 0);
        assertEq(ohm.balanceOf(address(fixedExpiryTeller)), 20_000_000_000_000);
        assertEq(bondToken.balanceOf(address(easyAuction)), 20_000_000_000_000);
    }
}
