// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test-utils/UserFactory.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockPrice} from "../mocks/MockPrice.sol";
import {MockAuthGiver} from "../mocks/MockAuthGiver.sol";

import {FullMath} from "libraries/FullMath.sol";

import {Kernel, Policy, Actions} from "../../Kernel.sol";
import {OlympusAuthority} from "modules/AUTHR.sol";

import {Heart} from "policies/Heart.sol";

import {IOperator, ERC20, IBondAuctioneer, IBondCallback} from "policies/interfaces/IOperator.sol";

/**
 * @notice Mock Operator to test Heart
 */
contract MockOperator is Policy, IOperator, Auth {
    bool public result;
    error Operator_CustomError();

    constructor(Kernel kernel_)
        Policy(kernel_)
        Auth(address(kernel_), Authority(address(0)))
    {
        result = true;
    }

    /* ========== FRAMEWORK CONFIFURATION ========== */
    function configureReads() external override onlyKernel {
        setAuthority(Authority(getModuleAddress("AUTHR")));
    }

    function requestRoles()
        external
        view
        override
        onlyKernel
        returns (Kernel.Role[] memory roles)
    {}

    /* ========== HEART FUNCTIONS ========== */
    function operate() external requiresAuth {
        if (!result) revert Operator_CustomError();
    }

    function setResult(bool result_) external {
        result = result_;
    }

    /* ========== OPEN MARKET OPERATIONS (WALL) ========== */

    function swap(ERC20 tokenIn_, uint256 amountIn_)
        external
        pure
        returns (uint256 amountOut)
    {
        amountOut = 0;
    }

    function getAmountOut(ERC20 tokenIn_, uint256 amountIn_)
        external
        pure
        returns (uint256)
    {
        return 0;
    }

    /* ========== OPERATOR CONFIGURATION ========== */
    function setSpreads(uint256 cushionSpread_, uint256 wallSpread_) external {}

    function setThresholdFactor(uint256 thresholdFactor_) external {}

    function setCushionFactor(uint32 cushionFactor_) external override {}

    function setCushionParams(
        uint32 duration_,
        uint32 debtBuffer_,
        uint32 depositInterval_
    ) external override {}

    function setReserveFactor(uint32 reserveFactor_) external override {}

    function setRegenParams(
        uint32 wait_,
        uint32 threshold_,
        uint32 observe_
    ) external override {}

    function setBondContracts(
        IBondAuctioneer auctioneer_,
        IBondCallback callback_
    ) external override {}

    function initialize() external override {}

    /* ========== VIEW FUNCTIONS ========== */

    function fullCapacity(bool high_) external view override returns (uint256) {
        return 0;
    }

    function status() external view override returns (Status memory) {
        return
            Status(
                Regen(0, 0, 0, new bool[](0)),
                Regen(0, 0, 0, new bool[](0))
            );
    }

    function config() external view override returns (Config memory) {
        return Config(0, 0, 0, 0, 0, 0, 0, 0);
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
    OlympusAuthority internal authr;

    MockOperator internal operator;
    MockAuthGiver internal authGiver;

    Heart internal heart;

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
            price = new MockPrice(kernel);
            authr = new OlympusAuthority(kernel);

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
            heart = new Heart(
                kernel,
                operator,
                uint256(8 hours),
                rewardToken,
                uint256(1e18) // 1 reward token
            );

            // Deploy mock auth giver
            authGiver = new MockAuthGiver(kernel);
        }

        {
            /// Initialize system and kernel

            /// Install modules
            kernel.executeAction(Actions.InstallModule, address(authr));
            kernel.executeAction(Actions.InstallModule, address(price));

            /// Approve policies
            kernel.executeAction(Actions.ApprovePolicy, address(operator));
            kernel.executeAction(Actions.ApprovePolicy, address(heart));
            kernel.executeAction(Actions.ApprovePolicy, address(authGiver));

            /// Configure access control

            /// Set role permissions

            /// Role 0 = Heart
            authGiver.setRoleCapability(
                uint8(0),
                address(operator),
                operator.operate.selector
            );

            /// Role 1 = Guardian
            authGiver.setRoleCapability(
                uint8(1),
                address(operator),
                operator.operate.selector
            );
            authGiver.setRoleCapability(
                uint8(1),
                address(heart),
                heart.resetBeat.selector
            );
            authGiver.setRoleCapability(
                uint8(1),
                address(heart),
                heart.toggleBeat.selector
            );
            authGiver.setRoleCapability(
                uint8(1),
                address(heart),
                heart.setReward.selector
            );
            authGiver.setRoleCapability(
                uint8(1),
                address(heart),
                heart.setRewardToken.selector
            );
            authGiver.setRoleCapability(
                uint8(1),
                address(heart),
                heart.withdrawUnspentRewards.selector
            );
            authGiver.setRoleCapability(
                uint8(1),
                address(heart),
                heart.setFrequency.selector
            );

            /// Give roles to users
            authGiver.setUserRole(address(heart), uint8(0));
            authGiver.setUserRole(guardian, uint8(1));
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

    /* ========== ADMIN FUNCTIONS ========== */
    /// DONE
    /// [X] resetBeat
    /// [X] toggleBeat
    /// [X] setReward
    /// [X] setRewardToken
    /// [X] withdrawUnspentRewards
    /// [X] setFrequency
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

    function testCorrectness_setReward() public {
        /// Set the heart's reward to a new value
        uint256 newReward = uint256(2e18);
        vm.prank(guardian);
        heart.setReward(newReward);

        /// Expect the heart's reward to be the new value
        assertEq(heart.reward(), newReward);

        /// Beat the heart and expect the contract's reward token balance to increase by the new reward amount
        uint256 startBalance = rewardToken.balanceOf(address(this));
        uint256 frequency = heart.frequency();
        vm.warp(block.timestamp + frequency);
        heart.beat();

        uint256 endBalance = rewardToken.balanceOf(address(this));
        assertEq(endBalance, startBalance + newReward);
    }

    function testCorrectness_setRewardToken() public {
        /// Set the heart's reward token to a new token
        MockERC20 newToken = new MockERC20("New Token", "NT", 18);
        vm.prank(guardian);
        heart.setRewardToken(newToken);
        assertEq(address(heart.rewardToken()), address(newToken));

        /// Mint some new tokens to the heart to pay rewards
        newToken.mint(address(heart), uint256(1000 * 1e18));

        /// Expect the heart to reward the new token on a beat
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

    function testCorrectness_setFrequency() public {
        /// Try to set frequency to a value less than 1 hour and expect revert
        uint256 newFrequency = uint256(59);
        bytes memory err = abi.encodeWithSignature("Heart_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(guardian);
        heart.setFrequency(newFrequency);

        /// Set the heart's frequency to a new value that is valid
        newFrequency = uint256(4 hours);
        vm.prank(guardian);
        heart.setFrequency(newFrequency);

        /// Expect the heart's frequency to be the new value
        assertEq(heart.frequency(), newFrequency);

        /// Move time forward by the new frequency and expect it to work
        vm.warp(block.timestamp + newFrequency);

        /// Beat the heart and expect it to work
        heart.beat();
    }

    function testCorrectness_cannotCallAdminFunctionsWithoutPermissions()
        public
    {
        /// Try to call admin functions on the heart as non-guardian and expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");

        vm.expectRevert(err);
        heart.resetBeat();

        vm.expectRevert(err);
        heart.toggleBeat();

        vm.expectRevert(err);
        heart.setReward(uint256(2e18));

        vm.expectRevert(err);
        heart.setRewardToken(rewardToken);

        vm.expectRevert(err);
        heart.withdrawUnspentRewards(rewardToken);

        vm.expectRevert(err);
        heart.setFrequency(uint256(4 hours));
    }
}
