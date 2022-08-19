// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockPrice} from "test/mocks/MockPrice.sol";

import {FullMath} from "libraries/FullMath.sol";

import "src/Kernel.sol";

import {OlympusHeart} from "policies/Heart.sol";

import {IOperator, ERC20, IBondAuctioneer, IBondCallback} from "policies/interfaces/IOperator.sol";

/**
 * @notice Mock Operator to test Heart
 */
contract MockOperator is Policy {
    bool public result;
    error Operator_CustomError();

    constructor(Kernel kernel_) Policy(kernel_) {
        result = true;
    }

    /* ========== FRAMEWORK CONFIFURATION ========== */
    function configureDependencies() external override returns (Keycode[] memory dependencies) {}

    function requestPermissions() external view override returns (Permissions[] memory requests) {}

    /* ========== HEART FUNCTIONS ========== */
    function operate() external view onlyRole("operator_operate") {
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
    address internal guardian;
    address internal policy;

    MockERC20 internal rewardToken;

    Kernel internal kernel;
    MockPrice internal price;

    MockOperator internal operator;

    OlympusHeart internal heart;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            address[] memory users = userCreator.create(5);
            alice = users[0];
            bob = users[1];
            guardian = users[2];
            policy = users[3];
        }
        {
            /// Deploy token mocks
            rewardToken = new MockERC20("Reward Token", "RWD", 18);
        }

        {
            /// Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            /// Deploy modules (some mocks)
            price = new MockPrice(kernel, uint48(8 hours));

            /// Configure mocks
            price.setMovingAverage(100 * 1e18);
            price.setLastPrice(100 * 1e18);
            price.setCurrentPrice(100 * 1e18);
            price.setDecimals(18);
        }

        {
            /// Deploy mock operator
            operator = new MockOperator(kernel);

            /// Deploy heart
            heart = new OlympusHeart(
                kernel,
                IOperator(address(operator)),
                rewardToken,
                uint256(1e18) // 1 reward token
            );
        }

        {
            /// Initialize system and kernel

            /// Install modules
            kernel.executeAction(Actions.InstallModule, address(price));

            /// Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(operator));
            kernel.executeAction(Actions.ActivatePolicy, address(heart));

            /// Configure access control

            /// Heart roles
            kernel.grantRole(toRole("heart_admin"), guardian);

            /// Operator roles
            kernel.grantRole(toRole("operator_operate"), address(heart));
            kernel.grantRole(toRole("operator_operate"), guardian);
        }

        {
            /// Mint reward tokens to heart contract
            rewardToken.mint(address(heart), uint256(1000 * 1e18));
        }
    }

    /* ========== HELPER FUNCTIONS ========== */

    /* ========== KEEPER FUNCTIONS ========== */
    /// DONE
    /// [X] beat
    ///     [X] active and frequency has passed
    ///     [X] cannot beat if not active
    ///     [X] cannot beat if not enough time has passed
    ///     [X] fails if price or operator revert

    function testCorrectness_beat() public {
        /// Get the beat frequency of the heart and wait that amount of time
        uint256 frequency = heart.frequency();
        vm.warp(block.timestamp + frequency);

        /// Store this contract's current reward token balance
        uint256 startBalance = rewardToken.balanceOf(address(this));

        /// Beat the heart
        heart.beat();

        /// Check that the contract's reward token balance has increased by the reward amount
        uint256 endBalance = rewardToken.balanceOf(address(this));
        assertEq(endBalance, startBalance + heart.reward());
    }

    function testCorrectness_cannotBeatIfInactive() public {
        /// Set the heart to inactive
        vm.prank(guardian);
        heart.toggleBeat();

        /// Try to beat the heart and expect revert
        bytes memory err = abi.encodeWithSignature("Heart_BeatStopped()");
        vm.expectRevert(err);
        heart.beat();
    }

    function testCorrectness_cannotBeatIfTooEarly() public {
        /// Try to beat the heart and expect revert since it hasn't been more than the frequency since the last beat (deployment)
        bytes memory err = abi.encodeWithSignature("Heart_OutOfCycle()");
        vm.expectRevert(err);
        heart.beat();
    }

    function testFail_beatFailsIfPriceReverts() public {
        /// Get the beat frequency of the heart and wait that amount of time
        uint256 frequency = heart.frequency();
        vm.warp(block.timestamp + frequency);

        /// Set the price mock to return false
        price.setResult(false);

        /// Try to beat the heart and expect revert
        heart.beat();
    }

    function testFail_beatFailsIfOperateReverts() public {
        /// Get the beat frequency of the heart and wait that amount of time
        uint256 frequency = heart.frequency();
        vm.warp(block.timestamp + frequency);

        /// Set the price mock to return false
        operator.setResult(false);

        /// Try to beat the heart and expect revert
        heart.beat();
    }

    /* ========== VIEW FUNCTIONS ========== */
    /// [X] frequency

    function testCorrectness_viewFrequency() public {
        /// Get the beat frequency of the heart
        uint256 frequency = heart.frequency();

        /// Check that the frequency is correct
        assertEq(frequency, uint256(8 hours));
    }

    /* ========== ADMIN FUNCTIONS ========== */
    /// DONE
    /// [X] resetBeat
    /// [X] toggleBeat
    /// [X] setRewardTokenAndAmount
    /// [X] withdrawUnspentRewards
    /// [X] cannot call admin functions without permissions

    function testCorrectness_resetBeat() public {
        /// Try to beat the heart and expect the revert since not enough time has passed
        bytes memory err = abi.encodeWithSignature("Heart_OutOfCycle()");
        vm.expectRevert(err);
        heart.beat();

        /// Reset the beat so that it can be called without moving the time forward
        vm.prank(guardian);
        heart.resetBeat();

        /// Store this contract's current reward token balance
        uint256 startBalance = rewardToken.balanceOf(address(this));

        /// Beat the heart and expect it to work
        heart.beat();

        /// Check that the contract's reward token balance has increased by the reward amount
        uint256 endBalance = rewardToken.balanceOf(address(this));
        assertEq(endBalance, startBalance + heart.reward());
    }

    function testCorrectness_toggleBeat() public {
        /// Expect the heart to be active to begin with
        assertTrue(heart.active());

        /// Toggle the heart to make it inactive
        vm.prank(guardian);
        heart.toggleBeat();

        /// Expect the heart to be inactive
        assertTrue(!heart.active());

        /// Toggle the heart to make it active again
        vm.prank(guardian);
        heart.toggleBeat();

        /// Expect the heart to be active again
        assertTrue(heart.active());
    }

    function testCorrectness_setRewardTokenAndAmount() public {
        /// Set the heart's reward token to a new token and amount to a new amount
        MockERC20 newToken = new MockERC20("New Token", "NT", 18);
        uint256 newReward = uint256(2e18);
        vm.prank(guardian);
        heart.setRewardTokenAndAmount(newToken, newReward);

        /// Expect the heart's reward token and reward to be updated
        assertEq(address(heart.rewardToken()), address(newToken));
        assertEq(heart.reward(), newReward);

        /// Mint some new tokens to the heart to pay rewards
        newToken.mint(address(heart), uint256(1000 * 1e18));

        /// Expect the heart to reward the new token and amount on a beat
        uint256 startBalance = newToken.balanceOf(address(this));
        uint256 frequency = heart.frequency();
        vm.warp(block.timestamp + frequency);
        heart.beat();

        uint256 endBalance = newToken.balanceOf(address(this));
        assertEq(endBalance, startBalance + heart.reward());
    }

    function testCorrectness_withdrawUnspentRewards() public {
        /// Get the balance of the reward token on the contract
        uint256 startBalance = rewardToken.balanceOf(address(guardian));
        uint256 heartBalance = rewardToken.balanceOf(address(heart));

        /// Withdraw the heart's unspent rewards
        vm.prank(guardian);
        heart.withdrawUnspentRewards(rewardToken);
        uint256 endBalance = rewardToken.balanceOf(address(guardian));

        /// Expect the heart's reward token balance to be 0
        assertEq(rewardToken.balanceOf(address(heart)), uint256(0));

        /// Expect this contract's reward token balance to be increased by the heart's unspent rewards
        assertEq(endBalance, startBalance + heartBalance);
    }

    function testCorrectness_cannotCallAdminFunctionsWithoutPermissions() public {
        /// Try to call admin functions on the heart as non-guardian and expect revert
        bytes memory err = abi.encodeWithSelector(Policy_OnlyRole.selector, toRole("heart_admin"));

        vm.expectRevert(err);
        heart.resetBeat();

        vm.expectRevert(err);
        heart.toggleBeat();

        vm.expectRevert(err);
        heart.setRewardTokenAndAmount(rewardToken, uint256(2e18));

        vm.expectRevert(err);
        heart.withdrawUnspentRewards(rewardToken);
    }
}
