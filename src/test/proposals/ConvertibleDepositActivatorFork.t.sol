// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "@forge-std-1.9.6/Test.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {Kernel, Actions, toKeycode, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {OlympusDepositPositionManager} from "src/modules/DEPOS/OlympusDepositPositionManager.sol";
import {PositionTokenRenderer} from "src/modules/DEPOS/PositionTokenRenderer.sol";
import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {ConvertibleDepositFacility} from "src/policies/deposits/ConvertibleDepositFacility.sol";
import {ConvertibleDepositAuctioneer} from "src/policies/deposits/ConvertibleDepositAuctioneer.sol";
import {DepositRedemptionVault} from "src/policies/deposits/DepositRedemptionVault.sol";
import {EmissionManager} from "src/policies/EmissionManager.sol";
import {OlympusHeart} from "src/policies/Heart.sol";
import {ReserveWrapper} from "src/policies/ReserveWrapper.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IDistributor} from "src/policies/interfaces/IDistributor.sol";
import {IHeart} from "src/policies/interfaces/IHeart.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

import {AggregatorV3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";

import {ConvertibleDepositActivator} from "src/proposals/ConvertibleDepositActivator.sol";

// solhint-disable max-states-count
contract ConvertibleDepositActivatorForkTest is Test {
    // Constants
    string internal constant CD_NAME = "cdf";
    uint256 internal constant USDS_MAX_CAPACITY = 1_000_000e18; // 1M USDS
    uint256 internal constant USDS_MIN_DEPOSIT = 1e18; // 1 USDS
    uint8 internal constant PERIOD_1M = 1;
    uint8 internal constant PERIOD_2M = 2;
    uint8 internal constant PERIOD_3M = 3;
    uint16 internal constant RECLAIM_RATE = 90e2; // 90%

    // Fork configuration - using a pinned block before CD deployment
    string public RPC_URL = vm.envString("FORK_TEST_RPC_URL");
    uint256 internal constant FORK_BLOCK = 23324427; // Pinned block before CD deployment

    // Mainnet system contracts
    Kernel public kernel;
    ROLESv1 public roles;
    RolesAdmin public rolesAdmin;
    TRSRYv1 public treasury;

    // These addresses are hard-coded as the values in env.json can change, while this test operates on a specific block
    // Mainnet addresses from env.json
    address public constant KERNEL = 0x2286d7f9639e8158FaD1169e76d1FbC38247f54b;
    address public constant ROLES_ADMIN = 0xb216d714d91eeC4F7120a732c11428857C659eC8;
    address public constant TIMELOCK = 0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39;
    address public constant DAO_MS = 0x245cc372C84B3645Bf0Ffe6538620B04a217988B;
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address public constant OHM = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address public constant GOHM = 0x0ab87046fBb341D058F17CBC4c1133F25a20a52f;
    address public constant STAKING = 0xB63cac384247597756545b500253ff8E607a8020;
    address public constant BOND_AUCTIONEER = 0x007F7A1cb838A872515c8ebd16bE4b14Ef43a222;
    address public constant BOND_TELLER = 0x007F7735baF391e207E3aA380bb53c4Bd9a5Fed6;
    address public constant ZERO_DISTRIBUTOR = 0x44A7a09CcdDb4338E062f1a3849F9a82BDbf2AaA;

    // Existing system contracts that the activator references
    address public constant RESERVE_MIGRATOR = 0x986b99579BEc7B990331474b66CcDB94Fa2419F5;
    address public constant OPERATOR = 0x6417F206a0a6628Da136C0Faa39026d0134D2b52;
    address public constant YIELD_REPO = 0x271e35a8555a62F6bA76508E85dfD76D580B0692;

    // Deployed CD system contracts
    ConvertibleDepositActivator public activator;
    OlympusDepositPositionManager public depos;
    PositionTokenRenderer public positionRenderer;
    ReceiptTokenManager public receiptTokenManager;
    DepositManager public depositManager;
    ConvertibleDepositFacility public cdFacility;
    ConvertibleDepositAuctioneer public cdAuctioneer;
    DepositRedemptionVault public depositRedemptionVault;
    EmissionManager public emissionManager;
    OlympusHeart public heart;
    ReserveWrapper public reserveWrapper;

    // Test accounts
    address public user;

    // Oracle addresses for mocking
    address public constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public constant CHAINLINK_OHM_ETH = 0x9a72298ae3886221820B1c878d12D872087D3a23;
    address public constant CHAINLINK_DAI_ETH = 0x773616E4d11A78F511299002da57A0a94577F1f4;

    function setUp() public {
        // Fork mainnet at specific block
        vm.createSelectFork(RPC_URL, FORK_BLOCK);

        // Setup test accounts
        user = makeAddr("user");

        // Load mainnet contracts
        kernel = Kernel(KERNEL);
        roles = ROLESv1(address(kernel.getModuleForKeycode(toKeycode("ROLES"))));
        rolesAdmin = RolesAdmin(ROLES_ADMIN);
        treasury = TRSRYv1(address(kernel.getModuleForKeycode(toKeycode("TRSRY"))));

        // Deploy CD system contracts
        _deployConvertibleDepositSystem();

        // Install modules and activate policies in kernel
        _installModulesAndPolicies();

        // Deploy the activator with timelock as owner
        activator = new ConvertibleDepositActivator(
            TIMELOCK, // owner (timelock)
            address(depositManager),
            address(cdFacility),
            address(cdAuctioneer),
            address(depositRedemptionVault),
            address(emissionManager),
            address(heart),
            address(reserveWrapper)
        );
    }

    function _deployConvertibleDepositSystem() internal {
        // Deploy supporting contracts first
        positionRenderer = new PositionTokenRenderer();
        receiptTokenManager = new ReceiptTokenManager();

        // Deploy DEPOS module
        depos = new OlympusDepositPositionManager(address(kernel), address(positionRenderer));

        // Deploy policies
        depositManager = new DepositManager(address(kernel), address(receiptTokenManager));

        cdFacility = new ConvertibleDepositFacility(address(kernel), address(depositManager));

        cdAuctioneer = new ConvertibleDepositAuctioneer(address(kernel), address(cdFacility), USDS);

        depositRedemptionVault = new DepositRedemptionVault(
            address(kernel),
            address(depositManager)
        );

        emissionManager = new EmissionManager(
            kernel,
            OHM,
            GOHM,
            USDS,
            SUSDS,
            BOND_AUCTIONEER,
            address(cdAuctioneer),
            BOND_TELLER
        );

        heart = new OlympusHeart(
            kernel,
            IDistributor(ZERO_DISTRIBUTOR), // Use existing ZeroDistributor
            40e9, // maxReward (40 OHM)
            1200 // auctionDuration (20 minutes)
        );

        reserveWrapper = new ReserveWrapper(address(kernel), USDS, SUSDS);
    }

    function _installModulesAndPolicies() internal {
        // Need to be DAO MS to install modules and activate policies
        vm.startPrank(DAO_MS);

        // Install DEPOS module
        kernel.executeAction(Actions.InstallModule, address(depos));

        // Activate all policies
        kernel.executeAction(Actions.ActivatePolicy, address(depositManager));
        kernel.executeAction(Actions.ActivatePolicy, address(cdFacility));
        kernel.executeAction(Actions.ActivatePolicy, address(cdAuctioneer));
        kernel.executeAction(Actions.ActivatePolicy, address(depositRedemptionVault));
        kernel.executeAction(Actions.ActivatePolicy, address(emissionManager));
        kernel.executeAction(Actions.ActivatePolicy, address(heart));
        kernel.executeAction(Actions.ActivatePolicy, address(reserveWrapper));

        vm.stopPrank();
    }

    function _mockChainlinkOracles() internal {
        // Mock OHM/ETH oracle with higher value to ensure >= 100% premium over backing
        // This prevents Price_BadFeed errors when warping time and ensures EmissionManager conditions are met
        vm.mockCall(
            CHAINLINK_OHM_ETH,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(
                uint80(block.number), // roundId
                int256(9192000000000000), // Set OHM/ETH to ~0.009192 ETH per OHM for ~$40 OHM price
                block.timestamp, // startedAt (updated)
                block.timestamp, // updatedAt (updated)
                uint80(block.number) // answeredInRound
            )
        );

        // Mock DAI/ETH oracle with current value but updated timestamp
        // This prevents Price_BadFeed errors when warping time
        vm.mockCall(
            CHAINLINK_DAI_ETH,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(
                uint80(block.number), // roundId
                int256(229816680425243), // Current DAI/ETH price from the traces
                block.timestamp, // startedAt (updated)
                block.timestamp, // updatedAt (updated)
                uint80(block.number) // answeredInRound
            )
        );
    }

    function _grantRequiredRoles() internal {
        vm.startPrank(TIMELOCK);

        // Grant roles as specified in the ConvertibleDepositProposal
        rolesAdmin.grantRole("deposit_operator", address(cdFacility));
        rolesAdmin.grantRole("cd_auctioneer", address(cdAuctioneer));
        rolesAdmin.grantRole("cd_emissionmanager", address(emissionManager));
        rolesAdmin.grantRole("heart", address(heart));
        rolesAdmin.grantRole("admin", address(activator));

        vm.stopPrank();
    }

    function _setupUserWithUSDSBalance() internal {
        // Deal USDS directly to user for testing
        deal(USDS, user, 10_000e18); // 10k USDS

        // User approves contracts to spend USDS
        vm.startPrank(user);
        IERC20(USDS).approve(address(cdFacility), type(uint256).max);
        IERC20(USDS).approve(address(depositManager), type(uint256).max);
        vm.stopPrank();
    }

    function _inflatePremium() internal {
        // Deposit USDS into treasury to inflate backing (and premium)

        // Deal USDS
        address premiumProvider = makeAddr("premiumProvider");
        deal(USDS, premiumProvider, 10_000_000e18);

        // Transfer USDS to treasury to simulate premium
        vm.prank(premiumProvider);
        IERC20(USDS).transfer(address(treasury), 10_000_000e18);
    }

    function _performHeartbeats(uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            // Warp forward by heart frequency (assumed to be daily)
            vm.warp(block.timestamp + 86400); // 1 day

            // Mock oracle with updated timestamp to prevent stale data
            _mockChainlinkOracles();

            // Perform heartbeat
            vm.prank(address(heart));
            IHeart(address(heart)).beat();
        }
    }

    function _setupSystemWithPremiumAndHeartbeats() internal {
        // Inflate premium to provide conditions for tuning
        _inflatePremium();

        // Perform 3 heartbeats to allow system to tune properly
        _performHeartbeats(3);
    }

    // ========== CONSTRUCTOR TESTS ========== //

    function test_constructor_setsParametersCorrectly() public view {
        assertEq(activator.owner(), TIMELOCK);
        assertEq(activator.DEPOSIT_MANAGER(), address(depositManager));
        assertEq(activator.CD_FACILITY(), address(cdFacility));
        assertEq(activator.CD_AUCTIONEER(), address(cdAuctioneer));
        assertEq(activator.REDEMPTION_VAULT(), address(depositRedemptionVault));
        assertEq(activator.EMISSION_MANAGER(), address(emissionManager));
        assertEq(activator.HEART(), address(heart));
        assertEq(activator.RESERVE_WRAPPER(), address(reserveWrapper));
        assertFalse(activator.isActivated());
    }

    function test_constructor_constants() public view {
        assertEq(activator.CD_NAME(), CD_NAME);
        assertEq(activator.USDS(), USDS);
        assertEq(activator.SUSDS(), SUSDS);
        assertEq(activator.USDS_MAX_CAPACITY(), USDS_MAX_CAPACITY);
        assertEq(activator.USDS_MIN_DEPOSIT(), USDS_MIN_DEPOSIT);
        assertEq(activator.PERIOD_1M(), PERIOD_1M);
        assertEq(activator.PERIOD_2M(), PERIOD_2M);
        assertEq(activator.PERIOD_3M(), PERIOD_3M);
        assertEq(activator.RECLAIM_RATE(), RECLAIM_RATE);
        assertEq(activator.RESERVE_MIGRATOR(), RESERVE_MIGRATOR);
        assertEq(activator.OPERATOR(), OPERATOR);
        assertEq(activator.YIELD_REPURCHASE_FACILITY(), YIELD_REPO);
    }

    // ========== ACCESS CONTROL TESTS ========== //

    function test_activate_revertsWhen_notOwner(address caller_) public {
        vm.assume(caller_ != TIMELOCK);

        _grantRequiredRoles();

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(caller_);
        activator.activate();
    }

    function test_activate_revertsWhen_alreadyActivated() public {
        // Setup: Grant required roles and activate once
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        // Should revert on second activation
        vm.expectRevert(ConvertibleDepositActivator.AlreadyActivated.selector);
        vm.prank(TIMELOCK);
        activator.activate();
    }

    // ========== ACTIVATION TESTS ========== //

    function test_activate_setsActivatedFlag() public {
        _grantRequiredRoles();

        assertFalse(activator.isActivated());

        vm.prank(TIMELOCK);
        activator.activate();

        assertTrue(activator.isActivated());
    }

    function test_activate_emitsActivatedEvent() public {
        _grantRequiredRoles();

        vm.expectEmit(true, false, false, false);
        emit ConvertibleDepositActivator.Activated(TIMELOCK);

        vm.prank(TIMELOCK);
        activator.activate();
    }

    // ========== CONFIGURATION TESTS ========== //

    function test_activate_configuresContracts() public {
        _grantRequiredRoles();

        // Before activation - contracts should not be enabled
        assertFalse(IEnabler(address(depositManager)).isEnabled());
        assertFalse(IEnabler(address(cdFacility)).isEnabled());
        assertFalse(IEnabler(address(depositRedemptionVault)).isEnabled());
        assertFalse(IEnabler(address(cdAuctioneer)).isEnabled());
        assertFalse(IEnabler(address(emissionManager)).isEnabled());
        assertFalse(IEnabler(address(reserveWrapper)).isEnabled());
        assertFalse(IEnabler(address(heart)).isEnabled());

        // Activate
        vm.prank(TIMELOCK);
        activator.activate();

        // After activation - contracts should be enabled
        assertTrue(IEnabler(address(depositManager)).isEnabled());
        assertTrue(IEnabler(address(cdFacility)).isEnabled());
        assertTrue(IEnabler(address(depositRedemptionVault)).isEnabled());
        assertTrue(IEnabler(address(cdAuctioneer)).isEnabled());
        assertTrue(IEnabler(address(emissionManager)).isEnabled());
        assertTrue(IEnabler(address(reserveWrapper)).isEnabled());
        assertTrue(IEnabler(address(heart)).isEnabled());
    }

    function test_activate_configuresAssets() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        // Verify USDS asset configuration
        IAssetManager.AssetConfiguration memory assetConfig = IAssetManager(address(depositManager))
            .getAssetConfiguration(IERC20(USDS));
        assertEq(assetConfig.vault, SUSDS);
        assertEq(assetConfig.depositCap, USDS_MAX_CAPACITY);
        assertEq(assetConfig.minimumDeposit, USDS_MIN_DEPOSIT);

        // Verify deposit periods configuration
        IDepositManager.AssetPeriod memory period1M = IDepositManager(address(depositManager))
            .getAssetPeriod(IERC20(USDS), PERIOD_1M, address(cdFacility));
        assertEq(period1M.operator, address(cdFacility));

        IDepositManager.AssetPeriod memory period2M = IDepositManager(address(depositManager))
            .getAssetPeriod(IERC20(USDS), PERIOD_2M, address(cdFacility));
        assertEq(period2M.operator, address(cdFacility));

        IDepositManager.AssetPeriod memory period3M = IDepositManager(address(depositManager))
            .getAssetPeriod(IERC20(USDS), PERIOD_3M, address(cdFacility));
        assertEq(period3M.operator, address(cdFacility));

        // Verify reclaim rate
        uint16 reclaimRate1M = cdFacility.getAssetPeriodReclaimRate(IERC20(USDS), PERIOD_1M);
        assertEq(reclaimRate1M, RECLAIM_RATE);

        uint16 reclaimRate2M = cdFacility.getAssetPeriodReclaimRate(IERC20(USDS), PERIOD_2M);
        assertEq(reclaimRate2M, RECLAIM_RATE);

        uint16 reclaimRate3M = cdFacility.getAssetPeriodReclaimRate(IERC20(USDS), PERIOD_3M);
        assertEq(reclaimRate3M, RECLAIM_RATE);
    }

    function test_activate_configuresAuction() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        // Verify deposit periods are enabled in auctioneer
        (bool period1MEnabled, ) = IConvertibleDepositAuctioneer(address(cdAuctioneer))
            .isDepositPeriodEnabled(PERIOD_1M);
        assertTrue(period1MEnabled);

        (bool period2MEnabled, ) = IConvertibleDepositAuctioneer(address(cdAuctioneer))
            .isDepositPeriodEnabled(PERIOD_2M);
        assertTrue(period2MEnabled);

        (bool period3MEnabled, ) = IConvertibleDepositAuctioneer(address(cdAuctioneer))
            .isDepositPeriodEnabled(PERIOD_3M);
        assertTrue(period3MEnabled);

        // Verify auction parameters are set correctly
        IConvertibleDepositAuctioneer.AuctionParameters
            memory params = IConvertibleDepositAuctioneer(address(cdAuctioneer))
                .getAuctionParameters();
        assertEq(params.target, activator.CDA_INITIAL_TARGET()); // Should be 0
        assertEq(params.tickSize, activator.CDA_INITIAL_TICK_SIZE()); // Should be 0
        assertEq(params.minPrice, activator.CDA_INITIAL_MIN_PRICE()); // Should be 0

        // Verify tick step is set correctly
        assertEq(
            IConvertibleDepositAuctioneer(address(cdAuctioneer)).getTickStep(),
            activator.CDA_INITIAL_TICK_STEP_MULTIPLIER()
        ); // Should be 10075

        // Verify auction tracking period is set correctly
        assertEq(
            IConvertibleDepositAuctioneer(address(cdAuctioneer)).getAuctionTrackingPeriod(),
            activator.CDA_AUCTION_TRACKING_PERIOD()
        ); // Should be 7 days
    }

    function test_activate_configuresPeriodicTasks() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        // Verify periodic tasks are configured
        assertEq(IPeriodicTaskManager(address(heart)).getPeriodicTaskCount(), 5);

        (address[] memory periodicTasks, ) = IPeriodicTaskManager(address(heart))
            .getPeriodicTasks();
        assertEq(periodicTasks[0], RESERVE_MIGRATOR);
        assertEq(periodicTasks[1], address(reserveWrapper));
        assertEq(periodicTasks[2], OPERATOR);
        assertEq(periodicTasks[3], YIELD_REPO);
        assertEq(periodicTasks[4], address(emissionManager));
    }

    function test_activate_configuresAuthorizations() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        // Verify operator name is set
        assertEq(
            keccak256(
                bytes(IDepositManager(address(depositManager)).getOperatorName(address(cdFacility)))
            ),
            keccak256(bytes(CD_NAME))
        );

        // Verify facility authorizations
        assertTrue(
            IDepositRedemptionVault(address(depositRedemptionVault)).isAuthorizedFacility(
                address(cdFacility)
            )
        );
        assertTrue(
            IDepositFacility(address(cdFacility)).isAuthorizedOperator(
                address(depositRedemptionVault)
            )
        );
    }

    // ========== INTEGRATION TESTS ========== //

    function test_fullActivationWorkflow() public {
        // This test simulates the full workflow as described in the ConvertibleDepositProposal

        // 1. Grant required roles (simulating proposal execution)
        _grantRequiredRoles();

        // 2. Verify admin role is granted
        assertTrue(roles.hasRole(address(activator), "admin"));

        // 3. Activate the system
        vm.prank(TIMELOCK);
        activator.activate();

        // 4. Verify activation completed
        assertTrue(activator.isActivated());

        // 5. Revoke admin role (simulating proposal cleanup)
        vm.prank(TIMELOCK);
        rolesAdmin.revokeRole("admin", address(activator));

        // 6. Verify admin role is revoked
        assertFalse(roles.hasRole(address(activator), "admin"));

        // 7. Verify cannot activate again
        vm.expectRevert(ConvertibleDepositActivator.AlreadyActivated.selector);
        vm.prank(TIMELOCK);
        activator.activate();
    }

    function test_heartbeat_runsSuccessfully_afterActivation() public {
        // Setup: Grant required roles and activate
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        // Test that heartbeat can run successfully
        // This tests the periodic task configuration
        vm.prank(address(heart));
        IHeart(address(heart)).beat();

        // If we reach here without reverting, the heartbeat succeeded
        assertTrue(true);
    }

    // ========== SYSTEM FUNCTIONALITY TESTS ========== //

    function test_depositFunctionality_worksAfterActivation() public {
        // Setup: Activate system and setup user
        _grantRequiredRoles();
        vm.prank(TIMELOCK);
        activator.activate();
        _setupUserWithUSDSBalance();
        _setupSystemWithPremiumAndHeartbeats();

        uint256 depositAmount = 1000e18; // 1000 USDS

        // User makes a deposit
        vm.prank(user);
        (uint256 receiptTokenId, uint256 actualAmount) = cdFacility.deposit(
            IERC20(USDS),
            PERIOD_1M,
            depositAmount,
            false
        );

        // Verify deposit succeeded
        assertEq(receiptTokenManager.balanceOf(user, receiptTokenId), actualAmount);
    }

    function test_auctionFunctionality_worksAfterActivation() public {
        // Setup: Activate system and make a deposit
        _grantRequiredRoles();
        vm.prank(TIMELOCK);
        activator.activate();
        _setupUserWithUSDSBalance();

        // User makes a deposit first
        vm.prank(user);
        cdFacility.deposit(IERC20(USDS), PERIOD_1M, 1000e18, false);

        // Setup system with premium and heartbeats to tune the auction
        _setupSystemWithPremiumAndHeartbeats();

        // After heartbeats, the auction should be tuned with proper parameters
        IConvertibleDepositAuctioneer.AuctionParameters
            memory params = IConvertibleDepositAuctioneer(address(cdAuctioneer))
                .getAuctionParameters();

        // The auction should now have been tuned with non-zero parameters
        // (exact values depend on EmissionManager tuning logic)
        console2.log("Target after tuning:", params.target);
        console2.log("Tick size after tuning:", params.tickSize);
        console2.log("Min price after tuning:", params.minPrice);

        // Approve spending
        vm.prank(user);
        IERC20(USDS).approve(address(depositManager), 500e18);

        // Test bidding functionality
        vm.prank(user);
        (uint256 ohmOut, uint256 newPositionId, , ) = cdAuctioneer.bid(
            PERIOD_1M,
            500e18, // 500 USDS
            0, // No minimum OHM out
            false, // Don't wrap position
            false // Don't wrap receipt
        );

        // Verify bid succeeded
        assertTrue(ohmOut > 0);
        assertEq(newPositionId, 0);
    }

    function test_emissionManagerFunctionality_worksAfterActivation() public {
        // Setup: Activate system
        _grantRequiredRoles();
        vm.prank(TIMELOCK);
        activator.activate();

        // Verify emission manager is enabled and configured
        assertTrue(IEnabler(address(emissionManager)).isEnabled());

        // Test that emission manager can perform its basic functions
        // The exact functionality depends on the EmissionManager implementation
        // but we can test that it's enabled and has the right roles
        assertTrue(roles.hasRole(address(emissionManager), "cd_emissionmanager"));
    }

    function test_redemptionFunctionality_worksAfterActivation() public {
        // Setup: Activate system and make a deposit
        _grantRequiredRoles();
        vm.prank(TIMELOCK);
        activator.activate();
        _setupUserWithUSDSBalance();
        _setupSystemWithPremiumAndHeartbeats();

        // User makes a deposit via the auctioneer (this creates a position)
        vm.prank(user);
        (, , uint256 receiptTokenId, uint256 actualAmount) = cdAuctioneer.bid(
            PERIOD_1M,
            1000e18, // 1000 USDS
            0, // No minimum OHM out
            false, // Don't wrap position
            false // Don't wrap receipt
        );

        // Test that redemption works through the DepositRedemptionVault
        // First approve the redemption vault to spend the receipt tokens
        vm.prank(user);
        receiptTokenManager.approve(address(depositRedemptionVault), receiptTokenId, actualAmount);

        // Start redemption
        vm.prank(user);
        uint16 redemptionId = depositRedemptionVault.startRedemption(
            IERC20(USDS),
            PERIOD_1M,
            actualAmount,
            address(cdFacility)
        );

        // Fast forward past the deposit period
        vm.warp(block.timestamp + 35 days); // 1 month + buffer
        _mockChainlinkOracles(); // Update oracle timestamp after warping

        uint256 userBalanceBefore = IERC20(USDS).balanceOf(user);

        // Finish redemption
        vm.prank(user);
        depositRedemptionVault.finishRedemption(redemptionId);

        // Verify user received their USDS back
        assertTrue(IERC20(USDS).balanceOf(user) > userBalanceBefore);
    }

    function test_heartbeatWithAllTasks_worksAfterActivation() public {
        // Setup: Activate system
        _grantRequiredRoles();
        vm.prank(TIMELOCK);
        activator.activate();

        // Setup system with premium and heartbeats to ensure proper tuning
        _setupSystemWithPremiumAndHeartbeats();

        // If we reach here, all heartbeats succeeded and tasks ran properly
        assertTrue(true);

        // Verify that the auction was tuned after multiple heartbeats
        IConvertibleDepositAuctioneer.AuctionParameters
            memory params = IConvertibleDepositAuctioneer(address(cdAuctioneer))
                .getAuctionParameters();

        // The EmissionManager should have tuned the auction parameters
        // The exact values depend on the tuning logic, but we can verify they changed from initial values
        console2.log("Final target:", params.target);
        console2.log("Final tick size:", params.tickSize);
        console2.log("Final min price:", params.minPrice);
    }

    function test_roleAssignments_areCorrectAfterActivation() public {
        // Setup: Activate system
        _grantRequiredRoles();
        vm.prank(TIMELOCK);
        activator.activate();

        // Verify all required roles are assigned correctly
        assertTrue(roles.hasRole(address(cdFacility), "deposit_operator"));
        assertTrue(roles.hasRole(address(cdAuctioneer), "cd_auctioneer"));
        assertTrue(roles.hasRole(address(emissionManager), "cd_emissionmanager"));
        assertTrue(roles.hasRole(address(heart), "heart"));

        // Verify activator no longer has admin role (cleaned up in full workflow test)
        vm.prank(TIMELOCK);
        rolesAdmin.revokeRole("admin", address(activator));
        assertFalse(roles.hasRole(address(activator), "admin"));
    }

    // ========== NEGATIVE TESTS ========== //

    function test_cannotActivate_withoutAdminRole() public {
        // Should fail with specific role error when activator doesn't have admin role
        vm.expectRevert(); // Specific ROLES error from kernel
        vm.prank(TIMELOCK);
        activator.activate();
    }

    function test_cannotActivate_twice() public {
        // Setup: Grant required roles and activate once
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        // Should revert on second activation with specific error
        vm.expectRevert(ConvertibleDepositActivator.AlreadyActivated.selector);
        vm.prank(TIMELOCK);
        activator.activate();
    }

    function test_policiesAreActive_afterActivation() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        // Verify all policies are active in the kernel
        assertTrue(Policy(address(depositManager)).isActive());
        assertTrue(Policy(address(cdFacility)).isActive());
        assertTrue(Policy(address(cdAuctioneer)).isActive());
        assertTrue(Policy(address(depositRedemptionVault)).isActive());
        assertTrue(Policy(address(emissionManager)).isActive());
        assertTrue(Policy(address(heart)).isActive());
        assertTrue(Policy(address(reserveWrapper)).isActive());
    }

    function test_systemFunctionality_failsBeforeActivation() public {
        // Setup: Grant roles but don't activate
        _grantRequiredRoles();
        _setupUserWithUSDSBalance();

        // Try to make a deposit before activation - should fail
        vm.expectRevert(); // Should fail because contracts are not enabled
        vm.prank(user);
        cdFacility.deposit(IERC20(USDS), PERIOD_1M, 1000e18, false);
    }
}
