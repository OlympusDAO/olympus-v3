// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "src/test/lib/UserFactory.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockPrice} from "src/test/mocks/MockPrice.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {ZeroDistributor} from "policies/Distributor/ZeroDistributor.sol";
import {MockStakingZD} from "src/test/mocks/MockStakingForZD.sol";
import {MockYieldRepo} from "src/test/mocks/MockYieldRepo.sol";
import {MockReserveMigrator} from "src/test/mocks/MockReserveMigrator.sol";
import {MockEmissionManager} from "src/test/mocks/MockEmissionManager.sol";

import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {MockOperator} from "src/test/mocks/MockOperator.sol";

import {FullMath} from "libraries/FullMath.sol";

import {Actions, fromKeycode, Kernel, Keycode, Permissions, toKeycode} from "src/Kernel.sol";

import {OlympusHeart, IHeart} from "policies/Heart.sol";

import {IOperator} from "policies/interfaces/IOperator.sol";
import {IDistributor} from "policies/interfaces/IDistributor.sol";
import {IYieldRepo} from "policies/interfaces/IYieldRepo.sol";
import {IReserveMigrator} from "policies/interfaces/IReserveMigrator.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// solhint-disable max-states-count
contract HeartTest is Test {
    using FullMath for uint256;

    UserFactory public userCreator;
    address internal alice;
    address internal bob;
    address internal policy;
    address internal ADMIN;
    address internal MANAGER;
    address internal EMERGENCY;

    MockERC20 internal ohm;
    MockERC20 internal reserveToken;
    MockERC4626 internal vault;

    Kernel internal kernel;
    MockPrice internal PRICE;
    OlympusRoles internal ROLES;
    OlympusMinter internal MINTR;
    OlympusTreasury internal TRSRY;

    MockOperator internal operator;
    OlympusHeart internal heart;
    RolesAdmin internal rolesAdmin;

    MockStakingZD internal staking;
    ZeroDistributor internal distributor;

    MockYieldRepo internal yieldRepo;
    MockReserveMigrator internal reserveMigrator;
    MockEmissionManager internal emissionManager;

    uint48 internal constant PRICE_FREQUENCY = uint48(8 hours);

    // MINTR
    event Mint(address indexed policy_, address indexed to_, uint256 amount_);

    // Heart
    event Beat(uint256 timestamp_);
    event RewardIssued(address to_, uint256 rewardAmount_);
    event RewardUpdated(uint256 maxRewardAmount_, uint48 auctionDuration_);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            address[] memory users = userCreator.create(3);
            alice = users[0];
            bob = users[1];
            policy = users[2];

            ADMIN = makeAddr("ADMIN");
            MANAGER = makeAddr("MANAGER");
            EMERGENCY = makeAddr("EMERGENCY");
        }
        {
            // Deploy token mocks
            ohm = new MockERC20("Olympus", "OHM", 9);
            reserveToken = new MockERC20("USDS", "USDS", 18);
            vault = new MockERC4626(reserveToken, "sUSDS", "sUSDS");
        }
        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy modules (some mocks)
            PRICE = new MockPrice(kernel, PRICE_FREQUENCY, 10 * 1e18);
            ROLES = new OlympusRoles(kernel);
            MINTR = new OlympusMinter(kernel, address(ohm));
            TRSRY = new OlympusTreasury(kernel);

            // Configure mocks
            PRICE.setMovingAverage(100 * 1e18);
            PRICE.setLastPrice(100 * 1e18);
            PRICE.setCurrentPrice(100 * 1e18);
            PRICE.setDecimals(18);
        }

        {
            // Deploy mock operator
            operator = new MockOperator(kernel, address(ohm));

            // Deploy mock staking and set distributor
            staking = new MockStakingZD(8 hours, 0, block.timestamp);
            distributor = new ZeroDistributor(address(staking));
            staking.setDistributor(address(distributor));

            // Deploy mock yieldRepo
            yieldRepo = new MockYieldRepo();

            // Deploy mock reserve migrator
            reserveMigrator = new MockReserveMigrator();

            // Deploy mock emission manager
            emissionManager = new MockEmissionManager();

            // Deploy heart
            heart = new OlympusHeart(
                kernel,
                IDistributor(address(distributor)),
                uint256(10e9), // max reward = 10 reward tokens
                uint48(12 * 50) // auction duration = 5 minutes (50 blocks on ETH mainnet)
            );

            rolesAdmin = new RolesAdmin(kernel);
        }

        {
            // Initialize system and kernel

            // Install modules
            kernel.executeAction(Actions.InstallModule, address(PRICE));
            kernel.executeAction(Actions.InstallModule, address(ROLES));
            kernel.executeAction(Actions.InstallModule, address(MINTR));
            kernel.executeAction(Actions.InstallModule, address(TRSRY));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(operator));
            kernel.executeAction(Actions.ActivatePolicy, address(heart));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

            // Configure access control

            // Heart ROLES
            rolesAdmin.grantRole("heart_admin", policy);
            rolesAdmin.grantRole("admin", ADMIN);
            rolesAdmin.grantRole("manager", MANAGER);
            rolesAdmin.grantRole("emergency", EMERGENCY);
        }

        // Add periodic tasks
        vm.startPrank(ADMIN);
        heart.addPeriodicTaskAtIndex(
            address(reserveMigrator),
            IReserveMigrator.migrate.selector,
            0
        );
        heart.addPeriodicTaskAtIndex(address(operator), IOperator.operate.selector, 1);
        heart.addPeriodicTaskAtIndex(address(yieldRepo), IYieldRepo.endEpoch.selector, 2);
        heart.addPeriodicTask(address(emissionManager));
        vm.stopPrank();

        // Enable the heart
        vm.prank(ADMIN);
        heart.enable("");

        // Do initial beat
        heart.beat();
    }

    // ======== SETUP DEPENDENCIES ======= //

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](3);
        expectedDeps[0] = toKeycode("PRICE");
        expectedDeps[1] = toKeycode("ROLES");
        expectedDeps[2] = toKeycode("MINTR");

        Keycode[] memory deps = heart.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
        assertEq(fromKeycode(deps[2]), fromKeycode(expectedDeps[2]));
    }

    function testRevert_configureDependencies_invalidFrequency() public {
        // Deploy mock staking with different frequency
        staking = new MockStakingZD(7 hours, 0, block.timestamp);
        distributor = new ZeroDistributor(address(staking));
        staking.setDistributor(address(distributor));

        // Deploy heart
        heart = new OlympusHeart(
            kernel,
            IDistributor(address(distributor)),
            uint256(10e9), // max reward = 10 reward tokens
            uint48(12 * 50) // auction duration = 5 minutes (50 blocks on ETH mainnet)
        );

        vm.startPrank(address(kernel));
        // Since the staking frequency is different, the call to configureDependencies reverts
        bytes memory err = abi.encodeWithSelector(IHeart.Heart_InvalidFrequency.selector);
        vm.expectRevert(err);
        heart.configureDependencies();
        vm.stopPrank();
    }

    function test_requestPermissions() public view {
        Permissions[] memory expectedPerms = new Permissions[](3);

        expectedPerms[0] = Permissions(PRICE.KEYCODE(), PRICE.updateMovingAverage.selector);
        expectedPerms[1] = Permissions(MINTR.KEYCODE(), MINTR.mintOhm.selector);
        expectedPerms[2] = Permissions(MINTR.KEYCODE(), MINTR.increaseMintApproval.selector);

        Permissions[] memory perms = heart.requestPermissions();
        // Check: permission storage
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    // =========  KEEPER FUNCTIONS ========= //
    // DONE
    // [X] beat
    //     [X] active and frequency has passed
    //     [X] distributor is called and the rebase is triggered
    //     [X] cannot beat if not active
    //     [X] cannot beat if not enough time has passed
    //     [X] fails if PRICE or operator revert
    //     [X] reward auction functions correctly based on time since beat available
    //     [X] periodic tasks are executed
    //     [X] reverts if periodic task reverts
    // [X] Mints rewardToken correctly

    function testCorrectness_beat() public {
        // Manually trigger initial rebase to sync the distributor and staking
        distributor.triggerRebase();
        (uint256 epochLength, , , ) = staking.epoch();

        // Get the beat frequency of the heart and wait that amount of time
        uint48 frequency = heart.frequency();
        vm.warp(block.timestamp + frequency);

        // Check that the rebase can be triggered
        assertEq(0, staking.secondsToNextEpoch());

        // Assert the EmissionManager count
        assertEq(emissionManager.count(), 1, "emissionManager.count before");

        vm.expectEmit(false, false, false, true);
        emit Beat(block.timestamp);

        // Beat the heart
        heart.beat();

        // Check that last beat has been updated to the current timestamp
        assertEq(heart.lastBeat(), block.timestamp);
        // Check that the last beat triggered a new rebase
        assertEq(epochLength, staking.secondsToNextEpoch());

        // Check that the emission manager periodic task was executed
        assertEq(emissionManager.count(), 2, "emissionManager.count");
    }

    function testCorrectness_cannotBeatIfInactive() public {
        // Set the heart to inactive
        vm.prank(ADMIN);
        heart.disable("");

        // Try to beat the heart and expect revert
        bytes memory err = abi.encodeWithSignature("Heart_BeatStopped()");
        vm.expectRevert(err);
        heart.beat();
    }

    function testCorrectness_cannotBeatIfTooEarly() public {
        // Try to beat the heart and expect revert since it hasn't been more than the frequency since the last beat (deployment)
        bytes memory err = abi.encodeWithSignature("Heart_OutOfCycle()");
        vm.expectRevert(err);
        heart.beat();
    }

    function testCorrectness_cannotBeatRepeatedlyIfSkipped() public {
        // Warp forward 2 frequencies
        vm.warp(block.timestamp + heart.frequency() * 2);

        // Check that lastBeat is less than or equal to the current timestamp minus two frequencies
        assertLe(heart.lastBeat(), block.timestamp - heart.frequency() * 2);

        // Beat the heart
        heart.beat();

        // Check that lastBeat is greater than block.timestamp minus one frequency
        assertGt(heart.lastBeat(), block.timestamp - heart.frequency());

        // Try to beat heart again, expect to revert
        bytes memory err = abi.encodeWithSignature("Heart_OutOfCycle()");
        vm.expectRevert(err);
        heart.beat();
    }

    function test_beatFailsIfPrice_reverts() public {
        // Get the beat frequency of the heart and wait that amount of time
        uint48 frequency = heart.frequency();
        vm.warp(block.timestamp + frequency);

        // Set the PRICE mock to return false
        PRICE.setResult(false);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(MockPrice.Price_CustomError.selector));

        // Try to beat the heart and expect revert
        heart.beat();
    }

    function test_beatFailsIfOperate_reverts() public {
        // Get the beat frequency of the heart and wait that amount of time
        uint48 frequency = heart.frequency();
        vm.warp(block.timestamp + frequency);

        // Set the PRICE mock to return false
        operator.setResult(false);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IPeriodicTaskManager.PeriodicTaskManager_CustomSelectorFailed.selector,
                address(operator),
                IOperator.operate.selector,
                abi.encodeWithSelector(MockOperator.Operator_CustomError.selector)
            )
        );

        // Try to beat the heart and expect revert
        heart.beat();
    }

    function testFuzz_rewardAuction(uint48 wait_) public {
        // Get the beat frequency of the heart and wait that amount of time
        uint48 frequency = heart.frequency();

        if (wait_ > frequency) return; // return if wait is greater than frequency (not fuzzing passed that point)

        uint48 auctionDuration = heart.auctionDuration();
        vm.warp(block.timestamp + frequency);

        // Store this contract's current reward token balance
        uint256 startBalance = ohm.balanceOf(address(this));
        uint256 maxReward = heart.maxReward();
        uint256 expectedReward = wait_ > auctionDuration
            ? maxReward
            : (maxReward * wait_) / auctionDuration;

        // Warp forward the fuzzed wait time
        vm.warp(block.timestamp + wait_);

        // Expect the reward to be emitted
        if (expectedReward > 0) {
            vm.expectEmit(false, false, false, true);
            emit Mint(address(heart), address(this), expectedReward);
            emit RewardIssued(address(this), expectedReward);
        }

        // Beat the heart
        heart.beat();

        // Balance of this contract has increased by the reward amount.
        assertEq(ohm.balanceOf(address(this)), startBalance + expectedReward);
        // Mint capabilities are limited to the reward amount when the beat happens.
        assertEq(MINTR.mintApproval(address(heart)), 0);
    }

    // =========  VIEW FUNCTIONS ========= //
    // [X] frequency
    // [X] currentReward

    function testCorrectness_viewFrequency() public view {
        // Get the beat frequency of the heart
        uint48 frequency = heart.frequency();

        // Check that the frequency is correct
        assertEq(frequency, uint256(8 hours));
    }

    function testFuzz_currentReward(uint48 wait_) public {
        // Expect current reward to return zero since beat is not available
        assertEq(heart.currentReward(), uint256(0));

        // Get the beat frequency of the heart and wait that amount of time
        uint48 frequency = heart.frequency();
        if (wait_ > frequency) return; // return if wait is greater than frequency (not fuzzing passed that point)
        uint48 auctionDuration = heart.auctionDuration();
        vm.warp(block.timestamp + frequency + wait_);

        // Store this contract's current reward token balance
        uint256 maxReward = heart.maxReward();
        uint256 expectedReward = wait_ > auctionDuration
            ? maxReward
            : (maxReward * wait_) / auctionDuration;

        // Check that current reward is correct
        assertEq(heart.currentReward(), expectedReward);
    }

    // =========  ADMIN FUNCTIONS ========= //
    // DONE
    // [X] resetBeat
    // [X] enable and disable
    // [X] setRewardAuctionParams
    // [X] cannot call admin functions without permissions
    // [X] setDistributor

    function testCorrectness_resetBeat() public {
        // Try to beat the heart and expect the revert since not enough time has passed
        bytes memory err = abi.encodeWithSignature("Heart_OutOfCycle()");
        vm.expectRevert(err);
        heart.beat();

        // Reset the beat so that it can be called without moving the time forward
        vm.prank(ADMIN);
        heart.resetBeat();

        // Beat the heart and expect it to work
        heart.beat();

        // Check that the last beat has been updated to the current timestamp
        assertEq(heart.lastBeat(), block.timestamp, "lastBeat");
    }

    function testCorrectness_activate_deactivate() public {
        // Expect the heart to be active to begin with
        assertTrue(heart.isEnabled());

        uint256 lastBeat = heart.lastBeat();

        // Toggle the heart to make it inactive
        vm.prank(ADMIN);
        heart.disable("");

        // Expect the heart to be inactive and lastBeat to remain the same
        assertTrue(!heart.isEnabled(), "isEnabled after disable");
        assertEq(heart.lastBeat(), lastBeat, "lastBeat after disable");

        // Toggle the heart to make it active again
        vm.prank(ADMIN);
        heart.enable("");

        // Expect the heart to be active again and lastBeat to be reset
        assertTrue(heart.isEnabled(), "isEnabled after enable");
        assertEq(heart.lastBeat(), block.timestamp - heart.frequency(), "lastBeat after enable");
    }

    function testCorrectness_setRewardAuctionParams() public {
        // Set timestamp so that a heart beat is available
        uint48 frequency = heart.frequency();
        vm.warp(block.timestamp + frequency);

        // Set new params
        uint256 newMaxReward = uint256(2e9);
        uint48 newAuctionDuration = uint48(12 * 25); // 5 mins

        // Try to set new reward token and amount while a beat is available, expect to fail
        bytes memory err = abi.encodeWithSignature("Heart_BeatAvailable()");
        vm.expectRevert(err);
        vm.prank(ADMIN);
        heart.setRewardAuctionParams(newMaxReward, newAuctionDuration);

        // Beat the heart
        heart.beat();

        // Expect the event to be emitted
        vm.expectEmit(false, false, false, true);
        emit RewardUpdated(newMaxReward, newAuctionDuration);

        // Set a new reward token and amount from the policy
        vm.prank(ADMIN);
        heart.setRewardAuctionParams(newMaxReward, newAuctionDuration);

        // Expect the heart's reward to be updated
        assertEq(heart.maxReward(), newMaxReward, "maxReward");

        // Expect the heart to reward the new token and amount on a beat
        uint256 startBalance = ohm.balanceOf(address(this));

        vm.warp(block.timestamp + frequency + newAuctionDuration);
        heart.beat();

        uint256 endBalance = ohm.balanceOf(address(this));
        assertEq(endBalance, startBalance + heart.maxReward(), "endBalance");
    }

    function testCorrectness_enable(address caller_) public {
        vm.assume(caller_ != ADMIN);

        // Disable the heart (otherwise it will revert)
        vm.prank(ADMIN);
        heart.disable("");

        // Revert if the caller is not ADMIN
        bytes memory adminErr = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("admin")
        );

        vm.expectRevert(adminErr);
        vm.prank(caller_);
        heart.enable("");

        // Successful otherwise
        vm.prank(ADMIN);
        heart.enable("");
    }

    function testCorrectness_disable(address caller_) public {
        vm.assume(caller_ != ADMIN && caller_ != EMERGENCY);

        // Revert if the caller is not ADMIN or EMERGENCY
        bytes memory notAuthorisedErr = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);

        vm.expectRevert(notAuthorisedErr);
        vm.prank(caller_);
        heart.disable("");

        // Successful as ADMIN
        vm.prank(ADMIN);
        heart.disable("");

        // Enable again
        vm.prank(ADMIN);
        heart.enable("");

        // Successful as EMERGENCY
        vm.prank(EMERGENCY);
        heart.disable("");
    }

    function testCorrectness_resetBeat(address caller_) public {
        vm.assume(caller_ != ADMIN && caller_ != MANAGER);

        // Revert if the caller is not ADMIN or MANAGER
        bytes memory notAuthorisedErr = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);

        vm.expectRevert(notAuthorisedErr);
        vm.prank(caller_);
        heart.resetBeat();

        // Successful as ADMIN
        vm.prank(ADMIN);
        heart.resetBeat();

        // Successful as MANAGER
        vm.prank(MANAGER);
        heart.resetBeat();
    }

    function testCorrectness_setRewardAuctionParams(address caller_) public {
        vm.assume(caller_ != ADMIN);

        // Revert if the caller is not ADMIN
        bytes memory adminErr = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("admin")
        );

        vm.expectRevert(adminErr);
        vm.prank(caller_);
        heart.setRewardAuctionParams(uint256(2e18), uint48(12 * 25));

        // Successful otherwise
        vm.prank(ADMIN);
        heart.setRewardAuctionParams(uint256(2e18), uint48(12 * 25));

        // Validate that the reward auction params have been set
        assertEq(heart.maxReward(), uint256(2e18), "maxReward");
        assertEq(heart.auctionDuration(), uint48(12 * 25), "auctionDuration");
    }

    function testCorrectness_setDistributor() public {
        // Reverts if the caller is not "heart_admin"
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("admin")
        );
        vm.expectRevert(err);
        heart.setDistributor(address(distributor));

        // Successful otherwise
        vm.prank(ADMIN);
        heart.setDistributor(address(distributor));

        // Check that the distributor has been set
        assertEq(address(heart.distributor()), address(distributor), "distributor");
    }
}
