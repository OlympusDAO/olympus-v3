// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";

import {OlympusERC20Token, IOlympusAuthority} from "src/external/OlympusERC20.sol";
import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockLegacyAuthority} from "../modules/MINTR.t.sol";

import "src/Kernel.sol";

import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";

import {BondCallback} from "policies/BondCallback.sol";
import {BondManager} from "policies/BondManager.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

import {RolesAuthority, Authority as SolmateAuthority} from "solmate/auth/authorities/RolesAuthority.sol";
import {BondAggregator} from "test/lib/bonds/BondAggregator.sol";
import {BondFixedExpirySDA} from "test/lib/bonds/BondFixedExpirySDA.sol";
import {BondFixedExpiryTeller} from "test/lib/bonds/BondFixedExpiryTeller.sol";
import {MockEasyAuction} from "test/mocks/MockEasyAuction.sol";

import {IBondAggregator} from "interfaces/IBondAggregator.sol";

// solhint-disable-next-line max-states-count
contract BondManagerTest is Test {
    UserFactory public userCreator;
    address internal alice;
    address internal guardian;
    address internal policy;

    MockLegacyAuthority internal legacyAuth;
    OlympusERC20Token internal ohm;

    Kernel internal kernel;
    OlympusMinter internal mintr;
    OlympusTreasury internal trsry;
    OlympusRoles internal roles;

    RolesAdmin internal rolesAdmin;
    BondCallback internal bondCallback;
    BondManager internal bondManager;

    RolesAuthority internal auth;
    BondAggregator internal bondAggregator;
    BondFixedExpirySDA internal fixedExpirySDA;
    BondFixedExpiryTeller internal fixedExpiryTeller;
    MockEasyAuction internal easyAuction;

    // Bond Protocol Parameters
    uint256 INITIAL_PRICE = 1000000000000000000000000000000000000;
    uint256 MIN_PRICE = 500000000000000000000000000000000000;
    uint32 DEBT_BUFFER = 100000;
    uint256 AUCTION_TIME = 7 * 24 * 60 * 60;
    uint32 DEPOSIT_INTERVAL = 6 * 60 * 60;

    // Gnosis Parameters
    uint256 AUCTION_CANCEL_TIME = 6 * 24 * 60 * 60;
    uint96 MIN_RATIO_SOLD = 2;
    uint256 MIN_BUY_AMOUNT = 1000000000;
    uint256 MIN_FUNDING_THRESHOLD = 1000000000000;

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
            bondAggregator = new BondAggregator(guardian, auth);
            fixedExpiryTeller = new BondFixedExpiryTeller(guardian, bondAggregator, guardian, auth);
            fixedExpirySDA = new BondFixedExpirySDA(
                fixedExpiryTeller,
                bondAggregator,
                guardian,
                auth
            );
            easyAuction = new MockEasyAuction();

            // Register auctioneer
            vm.prank(guardian);
            bondAggregator.registerAuctioneer(fixedExpirySDA);
        }

        // Deploy OHM mock
        {
            ohm = new OlympusERC20Token(address(legacyAuth));
        }

        // Deploy kernel and modules
        {
            kernel = new Kernel();

            mintr = new OlympusMinter(kernel, address(ohm));
            trsry = new OlympusTreasury(kernel);
            roles = new OlympusRoles(kernel);
        }

        // Deploy policies
        {
            rolesAdmin = new RolesAdmin(kernel);
            bondCallback = new BondCallback(
                kernel,
                IBondAggregator(address(bondAggregator)),
                ERC20(address(ohm))
            );
            bondManager = new BondManager(
                kernel,
                address(fixedExpirySDA),
                address(fixedExpiryTeller),
                address(easyAuction),
                address(ohm)
            );

            // Register bond manager to create bond markets with a callback
            vm.prank(guardian);
            fixedExpirySDA.setCallbackAuthStatus(address(bondManager), true);
        }

        // Initialize modules and policies
        {
            // Install modules
            kernel.executeAction(Actions.InstallModule, address(mintr));
            kernel.executeAction(Actions.InstallModule, address(trsry));
            kernel.executeAction(Actions.InstallModule, address(roles));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
            kernel.executeAction(Actions.ActivatePolicy, address(bondCallback));
            kernel.executeAction(Actions.ActivatePolicy, address(bondManager));
        }

        // Configure roles
        {
            // Bond Manager roles
            rolesAdmin.grantRole("bondmanager_admin", policy);

            // Bond Callback roles
            rolesAdmin.grantRole("callback_whitelist", policy);
            rolesAdmin.grantRole("callback_whitelist", address(bondManager));
            rolesAdmin.grantRole("callback_blacklist", policy);
            rolesAdmin.grantRole("callback_blacklist", address(bondManager));
            rolesAdmin.grantRole("callback_admin", guardian);

            // OHM Authority Vault
            legacyAuth.setKernel(address(mintr));

            // Register bond manager to create bond markets with a callback
            vm.prank(guardian);
            fixedExpirySDA.setCallbackAuthStatus(address(bondManager), true);
        }
    }

    //============================================================================================//
    //                                      ADMIN FUNCTIONS                                       //
    //============================================================================================//

    /// []  setBondProtocolParameters()
    ///     []  Can only be accessed by an address with bondmanager_admin role
    ///     []  Correctly sets parameters

    function testCorrectness_setBondParametersRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        bondManager.setBondProtocolParameters(
            INITIAL_PRICE,
            MIN_PRICE,
            DEBT_BUFFER,
            AUCTION_TIME,
            DEPOSIT_INTERVAL
        );
    }

    function testCorrectness_correctlySetsBondParameters() public {
        // Verify initial state
        (
            uint256 initialPrice,
            uint256 minPrice,
            uint32 debtBuffer,
            uint256 auctionTime,
            uint32 depositInterval
        ) = bondManager.bondProtocolParameters();
        assertEq(initialPrice, 0);
        assertEq(minPrice, 0);
        assertEq(debtBuffer, 0);
        assertEq(auctionTime, 0);
        assertEq(depositInterval, 0);

        // Set parameters
        vm.prank(policy);
        bondManager.setBondProtocolParameters(
            INITIAL_PRICE,
            MIN_PRICE,
            DEBT_BUFFER,
            AUCTION_TIME,
            DEPOSIT_INTERVAL
        );

        // Verify end state
        (initialPrice, minPrice, debtBuffer, auctionTime, depositInterval) = bondManager
            .bondProtocolParameters();
        assertEq(initialPrice, INITIAL_PRICE);
        assertEq(minPrice, MIN_PRICE);
        assertEq(debtBuffer, DEBT_BUFFER);
        assertEq(auctionTime, AUCTION_TIME);
        assertEq(depositInterval, DEPOSIT_INTERVAL);
    }

    /// []  setGnosisAuctionParameters()
    ///     []  Can only be accessed by an address with bondmanager_admin role
    ///     []  Correctly sets parameters

    function testCorrectness_setGnosisParametersRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        bondManager.setGnosisAuctionParameters(
            AUCTION_CANCEL_TIME,
            AUCTION_TIME,
            MIN_RATIO_SOLD,
            MIN_BUY_AMOUNT,
            MIN_FUNDING_THRESHOLD
        );
    }

    function testCorrectness_correctlySetsGnosisParameters() public {
        // Verify initial state
        (
            uint256 auctionCancelTime,
            uint256 auctionTime,
            uint96 minRatioSold,
            uint256 minBuyAmount,
            uint256 minFundingThreshold
        ) = bondManager.gnosisAuctionParameters();
        assertEq(auctionCancelTime, 0);
        assertEq(auctionTime, 0);
        assertEq(minRatioSold, 0);
        assertEq(minBuyAmount, 0);
        assertEq(minFundingThreshold, 0);

        // Set parameters
        vm.prank(policy);
        bondManager.setGnosisAuctionParameters(
            AUCTION_CANCEL_TIME,
            AUCTION_TIME,
            MIN_RATIO_SOLD,
            MIN_BUY_AMOUNT,
            MIN_FUNDING_THRESHOLD
        );

        // Verify end state
        (
            auctionCancelTime,
            auctionTime,
            minRatioSold,
            minBuyAmount,
            minFundingThreshold
        ) = bondManager.gnosisAuctionParameters();
        assertEq(auctionCancelTime, AUCTION_CANCEL_TIME);
        assertEq(auctionTime, AUCTION_TIME);
        assertEq(minRatioSold, MIN_RATIO_SOLD);
        assertEq(minBuyAmount, MIN_BUY_AMOUNT);
        assertEq(minFundingThreshold, MIN_FUNDING_THRESHOLD);
    }

    /// []  setCallback()
    ///     []  Can only be accessed by an address with bondmanager_admin role
    ///     []  Correctly sets callback address

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

    /// []  createBondProtocolMarket()
    ///     []  Can only be accessed by an address with bondmanager_admin role
    ///     []  Correctly launches a Bond Protocol market
    ///     []  Market correctly mints on purchase

    function _createBondSetup() internal {
        vm.startPrank(policy);
        bondManager.setBondProtocolParameters(
            INITIAL_PRICE,
            MIN_PRICE,
            DEBT_BUFFER,
            AUCTION_TIME,
            DEPOSIT_INTERVAL
        );
        bondManager.setCallback(bondCallback);
        vm.stopPrank();
    }

    function testCorrectness_createBondRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        bondManager.createBondProtocolMarket(10_000_000_000_000, 1 weeks);
    }

    function testCorrectness_createBondLaunchesMarket() public {
        _createBondSetup();

        // Launch market
        vm.prank(policy);
        uint256 marketId = bondManager.createBondProtocolMarket(10_000_000_000_000, 1 weeks);

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

    function testCorrectness_correctlyMintsOnBondProtocolPurchase(uint256 amount_) public {
        vm.assume(amount_ != 0);

        // Logic
    }

    /// []  closeBondProtocolMarket()
    ///     []  Can only be accessed by an address with bondmanager_admin role
    ///     []  Correcly shuts down market

    function _closeMarketSetup() internal {
        vm.startPrank(policy);
        bondManager.setBondProtocolParameters(
            INITIAL_PRICE,
            MIN_PRICE,
            DEBT_BUFFER,
            AUCTION_TIME,
            DEPOSIT_INTERVAL
        );
        bondManager.setCallback(bondCallback);
        bondManager.createBondProtocolMarket(10_000_000_000_000, 1 weeks);
        vm.stopPrank();
    }

    function testCorrectness_closeBondRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        // This attempts to close a non-existent market but it doesn't matter since the
        // user check happens first. Thus, this is still valid.
        vm.prank(user_);
        bondManager.closeBondProtocolMarket(0);
    }

    function testCorrectness_closeBondClosesMarket() public {
        _closeMarketSetup();

        vm.prank(policy);
        bondManager.closeBondProtocolMarket(0);

        // Verify market state
        (, , , , , uint256 capacity, , , , , , ) = fixedExpirySDA.markets(0);
        assertEq(capacity, 0);
    }

    /// []  createGnosisAuction()
    ///     []  Can only be accessed by an address with bondmanager_admin role
    ///     []  Correctly launches a Gnosis Auction

    function _createGnosisSetup() internal {
        vm.prank(policy);
        bondManager.setGnosisAuctionParameters(
            AUCTION_CANCEL_TIME,
            AUCTION_TIME,
            MIN_RATIO_SOLD,
            MIN_BUY_AMOUNT,
            MIN_FUNDING_THRESHOLD
        );
    }

    function testCorrectness_createGnosisAuctionRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        // This attempts to create a market without any of the base parameters set,
        // but it doesn't matter since the user checks first. Thus, this is still valid.
        vm.prank(user_);
        bondManager.createGnosisAuction(10_000_000_000_000, 1 weeks);
    }

    function testCorrectness_correctlyLaunchesGnosisAuction() public {
        _createGnosisSetup();

        vm.prank(policy);
        uint256 auctionId = bondManager.createGnosisAuction(10_000_000_000_000, 1 weeks);

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

    /// []  settleGnosisAuction()
    ///     []  Can only be accessed by an address with bondmanager_admin role
    ///     []  Correctly settles auction

    function _settleGnosisSetup() internal {
        vm.startPrank(policy);
        bondManager.setGnosisAuctionParameters(
            AUCTION_CANCEL_TIME,
            AUCTION_TIME,
            MIN_RATIO_SOLD,
            MIN_BUY_AMOUNT,
            MIN_FUNDING_THRESHOLD
        );
        bondManager.createGnosisAuction(10_000_000_000_000, 1 weeks);
        vm.stopPrank();
    }

    function testCorrectness_settleGnosisAuctionRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        // This attempts to settle an auction without one existing in the first place,
        // but it doesn't matter since the user checks first. Thus, this is still valid.
        vm.prank(user_);
        bondManager.settleGnosisAuction(0);
    }

    // Not really much to test here
    function testCorrectness_settlesGnosisAuction() public {
        _settleGnosisSetup();
        uint256 auctionId = easyAuction.auctionCounter();

        // Settle auction
        vm.prank(policy);
        bondManager.settleGnosisAuction(auctionId);
    }

    //============================================================================================//
    //                                   EMERGENCY FUNCTIONS                                      //
    //============================================================================================//

    /// []  emergencyShutdownBondProtocolMarket()
    ///     []  Can only be accessed by an address with bondmanager_admin role
    ///     []  Closes market on auctioneer
    ///     []  Blacklists market on callback to stop minting OHM

    function testCorrectness_emergencyShutdownBondProtocolMarketRequiresRole(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("bondmanager_admin")
        );
        vm.expectRevert(err);

        // This attempts to shutdown an auction without one existing in the first place,
        // but it doesn't matter since the user checks first. Thus, this is still valid.
        vm.prank(user_);
        bondManager.emergencyShutdownBondProtocolMarket(0);
    }

    function testCorrectness_closesMarketOnAuctioneer() public {
        // Create market
        vm.startPrank(policy);
        bondManager.setBondProtocolParameters(
            INITIAL_PRICE,
            MIN_PRICE,
            DEBT_BUFFER,
            AUCTION_TIME,
            DEPOSIT_INTERVAL
        );
        bondManager.setCallback(bondCallback);
        uint256 marketId = bondManager.createBondProtocolMarket(10_000_000_000_000, 1 weeks);

        // Verify market
        assertTrue(fixedExpirySDA.isLive(marketId));

        // Shutdown market
        bondManager.emergencyShutdownBondProtocolMarket(marketId);

        // Verify shutdown
        assertFalse(fixedExpirySDA.isLive(marketId));
        vm.stopPrank();
    }

    function testCorrectness_blacklistsMarketOnCallback() public {
        // Create market
        vm.startPrank(policy);
        bondManager.setBondProtocolParameters(
            INITIAL_PRICE,
            MIN_PRICE,
            DEBT_BUFFER,
            AUCTION_TIME,
            DEPOSIT_INTERVAL
        );
        bondManager.setCallback(bondCallback);
        uint256 marketId = bondManager.createBondProtocolMarket(10_000_000_000_000, 1 weeks);

        // Verify on callback
        assertTrue(bondCallback.approvedMarkets(address(fixedExpiryTeller), marketId));

        // Blacklist
        bondManager.emergencyShutdownBondProtocolMarket(marketId);

        // Verify shutdown
        assertFalse(bondCallback.approvedMarkets(address(fixedExpiryTeller), marketId));
        vm.stopPrank();
    }

    /// []  emergencySetApproval()
    ///     []  Can only be accessed by an address with bondmanager_admin role
    ///     []  Sets OHM approval correctly

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

    /// []  emergencyWithdraw()
    ///     []  Can only be accessed by an address with bondmanager_admin role
    ///     []  Sends OHM to the treasury

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
        // Setup
        vm.prank(address(mintr));
        ohm.mint(address(bondManager), amount_);

        // Verify initial state
        assertEq(ohm.balanceOf(address(bondManager)), amount_);
        assertEq(ohm.balanceOf(address(trsry)), 0);

        // Emergency withdrawal
        vm.prank(policy);
        bondManager.emergencyWithdraw(amount_);

        // Verify end state
        assertEq(ohm.balanceOf(address(bondManager)), 0);
        assertEq(ohm.balanceOf(address(trsry)), amount_);
    }
}
