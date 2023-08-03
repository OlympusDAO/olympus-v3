// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockPrice} from "test/mocks/MockPrice.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

import {FullMath} from "libraries/FullMath.sol";

import "src/Kernel.sol";

import {OlympusHeart} from "policies/Heart.sol";

import {IOperator} from "policies/interfaces/IOperator.sol";

/**
 * @notice Mock Operator to test Heart
 */
contract MockOperator is Policy {
    bool public result;
    address public ohm;
    error Operator_CustomError();

    constructor(Kernel kernel_, address ohm_) Policy(kernel_) {
        result = true;
        ohm = ohm_;
    }

    // =========  FRAMEWORK CONFIFURATION ========= //
    function configureDependencies() external override returns (Keycode[] memory dependencies) {}

    function requestPermissions() external view override returns (Permissions[] memory requests) {}

    // =========  HEART FUNCTIONS ========= //
    function operate() external view {
        if (!result) revert Operator_CustomError();
    }

    function setResult(bool result_) external {
        result = result_;
    }
}

contract HeartTest is Test {
    using FullMath for uint256;

    UserFactory public userCreator;
    address internal alice;
    address internal bob;
    address internal policy;

    MockERC20 internal ohm;

    Kernel internal kernel;
    MockPrice internal price;
    OlympusRoles internal roles;
    OlympusMinter internal mintr;

    MockOperator internal operator;
    OlympusHeart internal heart;
    RolesAdmin internal rolesAdmin;

    // MINTR
    event Mint(address indexed policy_, address indexed to_, uint256 amount_);

    // Heart
    event RewardUpdated(uint256 maxRewardAmount_, uint48 auctionDuration_);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            address[] memory users = userCreator.create(3);
            alice = users[0];
            bob = users[1];
            policy = users[2];
        }
        {
            // Deploy token mocks
            ohm = new MockERC20("Olympus", "OHM", 9);
        }
        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy modules (some mocks)
            price = new MockPrice(kernel, uint48(8 hours), 10 * 1e18);
            roles = new OlympusRoles(kernel);
            mintr = new OlympusMinter(kernel, address(ohm));

            // Configure mocks
            price.setMovingAverage(100 * 1e18);
            price.setLastPrice(100 * 1e18);
            price.setCurrentPrice(100 * 1e18);
            price.setDecimals(18);
        }

        {
            // Deploy mock operator
            operator = new MockOperator(kernel, address(ohm));

            // Deploy heart
            heart = new OlympusHeart(
                kernel,
                IOperator(address(operator)),
                uint256(10e9), // max reward = 10 reward tokens
                uint48(12 * 50) // auction duration = 5 minutes (50 blocks on ETH mainnet)
            );

            rolesAdmin = new RolesAdmin(kernel);
        }

        {
            // Initialize system and kernel

            // Install modules
            kernel.executeAction(Actions.InstallModule, address(price));
            kernel.executeAction(Actions.InstallModule, address(roles));
            kernel.executeAction(Actions.InstallModule, address(mintr));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(operator));
            kernel.executeAction(Actions.ActivatePolicy, address(heart));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

            // Configure access control

            // Heart roles
            rolesAdmin.grantRole("heart_admin", policy);
        }
    }

    // =========  KEEPER FUNCTIONS ========= //
    // DONE
    // [X] beat
    //     [X] active and frequency has passed
    //     [X] cannot beat if not active
    //     [X] cannot beat if not enough time has passed
    //     [X] fails if price or operator revert
    //     [X] reward auction functions correctly based on time since beat available
    // [X] Mints rewardToken correctly

    function testCorrectness_beat() public {
        // Get the beat frequency of the heart and wait that amount of time
        uint48 frequency = heart.frequency();
        vm.warp(block.timestamp + frequency);

        // Beat the heart
        heart.beat();

        // Check that last beat has been updated to the current timestamp
        assertEq(heart.lastBeat(), block.timestamp);
    }

    function testCorrectness_cannotBeatIfInactive() public {
        // Set the heart to inactive
        vm.prank(policy);
        heart.deactivate();

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

    function testFail_beatFailsIfPriceReverts() public {
        // Get the beat frequency of the heart and wait that amount of time
        uint48 frequency = heart.frequency();
        vm.warp(block.timestamp + frequency);

        // Set the price mock to return false
        price.setResult(false);

        // Try to beat the heart and expect revert
        heart.beat();
    }

    function testFail_beatFailsIfOperateReverts() public {
        // Get the beat frequency of the heart and wait that amount of time
        uint48 frequency = heart.frequency();
        vm.warp(block.timestamp + frequency);

        // Set the price mock to return false
        operator.setResult(false);

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
        }

        // Beat the heart
        heart.beat();

        // Reward issued should be half the max reward
        assertEq(ohm.balanceOf(address(this)), startBalance + expectedReward);
    }

    // =========  VIEW FUNCTIONS ========= //
    // [X] frequency
    // [X] currentReward

    function testCorrectness_viewFrequency() public {
        // Get the beat frequency of the heart
        uint48 frequency = heart.frequency();

        // Check that the frequency is correct
        assertEq(frequency, uint256(8 hours));
    }

    function test_currentReward(uint48 wait_) public {
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
    // [X] activate and deactivate
    // [X] setOperator
    // [X] setRewardAuctionParams
    // [X] cannot call admin functions without permissions

    function testCorrectness_resetBeat() public {
        // Try to beat the heart and expect the revert since not enough time has passed
        bytes memory err = abi.encodeWithSignature("Heart_OutOfCycle()");
        vm.expectRevert(err);
        heart.beat();

        // Reset the beat so that it can be called without moving the time forward
        vm.prank(policy);
        heart.resetBeat();

        // Beat the heart and expect it to work
        heart.beat();

        // Check that the last beat has been updated to the current timestamp
        assertEq(heart.lastBeat(), block.timestamp);
    }

    function testCorrectness_activate_deactivate() public {
        // Expect the heart to be active to begin with
        assertTrue(heart.active());

        uint256 lastBeat = heart.lastBeat();

        // Toggle the heart to make it inactive
        vm.prank(policy);
        heart.deactivate();

        // Expect the heart to be inactive and lastBeat to remain the same
        assertTrue(!heart.active());
        assertEq(heart.lastBeat(), lastBeat);

        // Toggle the heart to make it active again
        vm.prank(policy);
        heart.activate();

        // Expect the heart to be active again and lastBeat to be reset
        assertTrue(heart.active());
        assertEq(heart.lastBeat(), block.timestamp - heart.frequency());
    }

    function testCorrectness_setOperator(address newOperator) public {
        // Set the operator using the provided address
        vm.prank(policy);
        heart.setOperator(newOperator);

        // Check that the operator has been updated
        assertEq(address(heart.operator()), newOperator);
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
        vm.prank(policy);
        heart.setRewardAuctionParams(newMaxReward, newAuctionDuration);

        // Beat the heart
        heart.beat();

        // Expect the event to be emitted
        vm.expectEmit(false, false, false, true);
        emit RewardUpdated(newMaxReward, newAuctionDuration);

        // Set a new reward token and amount from the policy
        vm.prank(policy);
        heart.setRewardAuctionParams(newMaxReward, newAuctionDuration);

        // Expect the heart's reward to be updated
        assertEq(heart.maxReward(), newMaxReward);

        // Expect the heart to reward the new token and amount on a beat
        uint256 startBalance = ohm.balanceOf(address(this));

        vm.warp(block.timestamp + frequency + newAuctionDuration);
        heart.beat();

        uint256 endBalance = ohm.balanceOf(address(this));
        assertEq(endBalance, startBalance + heart.maxReward());
    }

    function testCorrectness_cannotCallAdminFunctionsWithoutPermissions() public {
        // Try to call admin functions on the heart as non-policy and expect revert
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("heart_admin")
        );

        vm.expectRevert(err);
        heart.resetBeat();

        vm.expectRevert(err);
        heart.deactivate();

        vm.expectRevert(err);
        heart.activate();

        vm.expectRevert(err);
        heart.setRewardAuctionParams(uint256(2e18), uint48(12 * 25));
    }
}
