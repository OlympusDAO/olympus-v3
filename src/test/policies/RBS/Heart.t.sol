// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {ZeroDistributor} from "policies/Distributor/ZeroDistributor.sol";
import {MockStakingZD} from "test/mocks/MockStakingForZD.sol";
import {OlympusSupply} from "modules/SPPLY/OlympusSupply.sol";

import {FullMath} from "libraries/FullMath.sol";

import "src/Kernel.sol";

import {OlympusHeart} from "policies/RBS/Heart.sol";
import {IHeart} from "policies/RBS/interfaces/IHeart.sol";

import {IOperator} from "policies/RBS/interfaces/IOperator.sol";
import {IDistributor} from "policies/RBS/interfaces/IDistributor.sol";
import {IAppraiser} from "policies/OCA/interfaces/IAppraiser.sol";

/**
 * @notice Mock Operator to test Heart
 */
contract MockOperator is Policy {
    bool public result;
    address public ohm;
    address public reserve;
    error Operator_CustomError();

    constructor(Kernel kernel_, address ohm_, address reserve_) Policy(kernel_) {
        result = true;
        ohm = ohm_;
        reserve = reserve_;
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

/**
 * @notice Mock Appraiser to test Heart
 */
contract MockAppraiser is Policy {
    error Appraiser_CustomError();
    bool public result;

    constructor(Kernel kernel_) Policy(kernel_) {
        result = true;
    }

    // =========  FRAMEWORK CONFIFURATION ========= //
    function configureDependencies() external override returns (Keycode[] memory dependencies) {}

    function requestPermissions() external view override returns (Permissions[] memory requests) {}

    // =========  HEART FUNCTIONS ========= //
    function storeMetric(IAppraiser.Metric metric_) external view {
        if (!result) revert Appraiser_CustomError();
    }

    function storeMetricObservation(IAppraiser.Metric metric_) external view {
        if (!result) revert Appraiser_CustomError();
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
    MockGohm internal gohm;
    MockERC20 internal reserve;

    Kernel internal kernel;
    MockPrice internal PRICE;
    OlympusRoles internal ROLES;
    OlympusMinter internal MINTR;
    OlympusSupply internal SPPLY;

    MockOperator internal operator;
    MockAppraiser internal appraiser;
    OlympusHeart internal heart;
    RolesAdmin internal rolesAdmin;

    MockStakingZD internal staking;
    ZeroDistributor internal distributor;

    uint48 internal constant PRICE_FREQUENCY = uint48(8 hours);
    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals

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
        }
        {
            // Deploy token mocks
            ohm = new MockERC20("Olympus", "OHM", 9);
            gohm = new MockGohm(GOHM_INDEX);
            reserve = new MockERC20("Reserve", "RSV", 18);
        }
        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy modules (some mocks)
            PRICE = new MockPrice(kernel, uint8(18), uint32(8 hours));
            ROLES = new OlympusRoles(kernel);
            MINTR = new OlympusMinter(kernel, address(ohm));

            address[2] memory tokens = [address(ohm), address(gohm)];
            SPPLY = new OlympusSupply(kernel, tokens, 0, uint32(8 hours));

            // Configure prices on mock price module
            PRICE.setPrice(address(ohm), 100e18);
            PRICE.setPrice(address(reserve), 1e18);
            PRICE.setMovingAverage(address(ohm), 100e18);
            PRICE.setMovingAverage(address(reserve), 1e18);
        }

        {
            // Deploy mocks
            operator = new MockOperator(kernel, address(ohm), address(reserve));
            appraiser = new MockAppraiser(kernel);

            // Deploy mock staking and set distributor
            staking = new MockStakingZD(8 hours, 0, block.timestamp);
            distributor = new ZeroDistributor(address(staking));
            staking.setDistributor(address(distributor));

            IAppraiser.Metric[] memory movingAverageMetrics = new IAppraiser.Metric[](1);
            movingAverageMetrics[0] = IAppraiser.Metric.BACKING;

            // Deploy heart
            heart = new OlympusHeart(
                kernel,
                IOperator(address(operator)),
                IAppraiser(address(appraiser)),
                IDistributor(address(distributor)),
                movingAverageMetrics,
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
            kernel.executeAction(Actions.InstallModule, address(SPPLY));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(operator));
            kernel.executeAction(Actions.ActivatePolicy, address(heart));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

            // Configure access control

            // Heart ROLES
            rolesAdmin.grantRole("heart_admin", policy);

            // Do initial heart beat
            heart.beat();
        }
    }

    // ======== SETUP DEPENDENCIES ======= //

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](4);
        expectedDeps[0] = toKeycode("PRICE");
        expectedDeps[1] = toKeycode("ROLES");
        expectedDeps[2] = toKeycode("MINTR");
        expectedDeps[3] = toKeycode("SPPLY");

        Keycode[] memory deps = heart.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
        assertEq(fromKeycode(deps[2]), fromKeycode(expectedDeps[2]));
        assertEq(fromKeycode(deps[3]), fromKeycode(expectedDeps[3]));
    }

    function testRevert_configureDependencies_invalidFrequency() public {
        // Deploy mock staking with different frequency
        staking = new MockStakingZD(7 hours, 0, block.timestamp);
        distributor = new ZeroDistributor(address(staking));
        staking.setDistributor(address(distributor));

        address[] memory movingAverageAssets = new address[](2);
        movingAverageAssets[0] = address(ohm);
        movingAverageAssets[1] = address(reserve);

        IAppraiser.Metric[] memory movingAverageMetrics = new IAppraiser.Metric[](1);
        movingAverageMetrics[0] = IAppraiser.Metric.BACKING;

        // Deploy heart
        heart = new OlympusHeart(
            kernel,
            IOperator(address(operator)),
            IAppraiser(address(appraiser)),
            IDistributor(address(distributor)),
            movingAverageMetrics,
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

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](4);
        expectedPerms[0] = Permissions(PRICE.KEYCODE(), PRICE.storeObservations.selector);
        expectedPerms[1] = Permissions(MINTR.KEYCODE(), MINTR.mintOhm.selector);
        expectedPerms[2] = Permissions(MINTR.KEYCODE(), MINTR.increaseMintApproval.selector);
        expectedPerms[3] = Permissions(SPPLY.KEYCODE(), SPPLY.storeObservations.selector);

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

        vm.expectEmit(false, false, false, true);
        emit Beat(block.timestamp);

        // Beat the heart
        heart.beat();

        // Check that last beat has been updated to the current timestamp
        assertEq(heart.lastBeat(), block.timestamp);
        // Check that the last beat triggered a new rebase
        assertEq(epochLength, staking.secondsToNextEpoch());
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

        // Set the price mock to revert with price zero
        PRICE.setPrice(address(ohm), 0);

        // Try to beat the heart and expect revert
        heart.beat();
    }

    function testFail_beatFailsIfOperateReverts() public {
        // Get the beat frequency of the heart and wait that amount of time
        uint48 frequency = heart.frequency();
        vm.warp(block.timestamp + frequency);

        // Set the operator mock to return false
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

    function testCorrectness_viewFrequency() public {
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
    // [X] activate and deactivate
    // [X] setOperator
    // [X] setAppraiser
    // [X] setRewardAuctionParams
    // [X] cannot call admin functions without permissions
    // [X] constructor accepts moving average assets
    //  [X] reverts if zero address
    //  [X] reverts if duplicates
    //  [X] success

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

    function testRevert_setDistributor_invalidFrequency() public {
        // Deploy mock staking with different frequency
        staking = new MockStakingZD(7 hours, 0, block.timestamp);
        distributor = new ZeroDistributor(address(staking));
        staking.setDistributor(address(distributor));

        vm.startPrank(policy);
        // Since the staking frequency is different, the call to configureDependencies reverts
        bytes memory err = abi.encodeWithSelector(IHeart.Heart_InvalidFrequency.selector);
        vm.expectRevert(err);
        heart.setDistributor(address(distributor));
        vm.stopPrank();
    }

    function testCorrectness_setDistributor() public {
        // Use same staking contract for the new distributor
        address newDistributor = address(new ZeroDistributor(address(staking)));
        staking.setDistributor(newDistributor);

        vm.prank(policy);
        heart.setDistributor(newDistributor);

        // Check that the distributor has been updated
        assertEq(address(heart.distributor()), newDistributor);
    }

    function testCorrectness_setOperator(address newOperator) public {
        // Set the operator using the provided address
        vm.prank(policy);
        heart.setOperator(newOperator);

        // Check that the operator has been updated
        assertEq(address(heart.operator()), newOperator);
    }

    function testCorrectness_setAppraiser(address newAppraiser) public {
        // Set the appraiser using the provided address
        vm.prank(policy);
        heart.setAppraiser(newAppraiser);

        // Check that the appraiser has been updated
        assertEq(address(heart.appraiser()), newAppraiser);
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
        heart.setOperator(address(this));

        vm.expectRevert(err);
        heart.setAppraiser(address(this));

        vm.expectRevert(err);
        heart.setRewardAuctionParams(uint256(2e9), uint48(12 * 25));
    }

    //  [X]  constructor moving average metrics
    //      [X]  reverts if duplicates
    //      [X]  adds metrics

    function testReverts_constructor_movingAverageMetrics_duplicate() public {
        IAppraiser.Metric[] memory movingAverageMetrics = new IAppraiser.Metric[](3);
        movingAverageMetrics[0] = IAppraiser.Metric.BACKING;
        movingAverageMetrics[1] = IAppraiser.Metric.LIQUID_BACKING;
        movingAverageMetrics[2] = IAppraiser.Metric.BACKING;

        bytes memory err = abi.encodeWithSelector(IHeart.Heart_InvalidParams.selector);
        vm.expectRevert(err);

        // Deploy heart with moving average metrics containing a duplicate
        new OlympusHeart(
            kernel,
            IOperator(address(operator)),
            IAppraiser(address(appraiser)),
            IDistributor(address(distributor)),
            movingAverageMetrics,
            uint256(10e9), // max reward = 10 reward tokens
            uint48(12 * 50) // auction duration = 5 minutes (50 blocks on ETH mainnet)
        );
    }

    function testCorrectness_constructor_movingAverageMetrics() public {
        IAppraiser.Metric[] memory movingAverageMetrics = new IAppraiser.Metric[](3);
        movingAverageMetrics[0] = IAppraiser.Metric.BACKING;
        movingAverageMetrics[1] = IAppraiser.Metric.LIQUID_BACKING;
        movingAverageMetrics[2] = IAppraiser.Metric.MARKET_VALUE;

        // Deploy heart with moving average metrics
        OlympusHeart newHeart = new OlympusHeart(
            kernel,
            IOperator(address(operator)),
            IAppraiser(address(appraiser)),
            IDistributor(address(distributor)),
            movingAverageMetrics,
            uint256(10e9), // max reward = 10 reward tokens
            uint48(12 * 50) // auction duration = 5 minutes (50 blocks on ETH mainnet)
        );

        // Check that the moving average metrics are set correctly
        IAppraiser.Metric[] memory metrics = newHeart.getMovingAverageMetrics();
        assertEq(uint8(metrics[0]), 0, "backing");
        assertEq(uint8(metrics[1]), 1, "liquid backing");
        assertEq(uint8(metrics[2]), 3, "market value");
        assertEq(newHeart.getMovingAverageMetricsCount(), 3, "metric count");
    }

    //  [X]  addMovingAverageMetric
    //      [X]  can only be called by heart_admin
    //      [X]  reverts if metric already tracked
    //      [X]  adds metric to tracked metrics

    function testCorrectness_addMovingAverageMetricCallableOnlyByAdmin(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("heart_admin")
        );
        vm.expectRevert(err);

        // Add a metric as non-policy
        vm.prank(user_);
        heart.addMovingAverageMetric(IAppraiser.Metric.BACKING);
    }

    function testReverts_addMovingAverageMetric_duplicate() public {
        bytes memory err = abi.encodeWithSelector(IHeart.Heart_InvalidParams.selector);
        vm.expectRevert(err);

        // Add a duplicate metric
        vm.prank(policy);
        heart.addMovingAverageMetric(IAppraiser.Metric.BACKING);
    }

    function testCorrectness_addMovingAverageMetric() public {
        // Add a metric
        vm.prank(policy);
        heart.addMovingAverageMetric(IAppraiser.Metric.LIQUID_BACKING);

        // Check that the metric was added
        IAppraiser.Metric[] memory metrics = heart.getMovingAverageMetrics();
        assertEq(uint8(metrics[0]), 0);
        assertEq(uint8(metrics[1]), 1);
        assertEq(metrics.length, 2, "metric count");
    }

    //  [X]  removeMovingAverageMetric
    //      [X]  can only be called by heart_admin
    //      [X]  reverts if metric not tracked
    //      [X]  removes metric from tracked metrics

    function testCorrectness_removeMovingAverageMetricCallableOnlyByAdmin(address user_) public {
        vm.assume(user_ != policy);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("heart_admin")
        );
        vm.expectRevert(err);

        // Remove a metric as non-policy
        vm.prank(user_);
        heart.removeMovingAverageMetric(IAppraiser.Metric.LIQUID_BACKING);
    }

    function testReverts_removeMovingAverageMetric_doesNotExist() public {
        bytes memory err = abi.encodeWithSelector(IHeart.Heart_InvalidParams.selector);
        vm.expectRevert(err);

        // Remove a metric that does not exist
        vm.prank(policy);
        heart.removeMovingAverageMetric(IAppraiser.Metric.LIQUID_BACKING);
    }

    function testCorrectness_removeMovingAverageMetric() public {
        // Remove a metric
        vm.prank(policy);
        heart.removeMovingAverageMetric(IAppraiser.Metric.BACKING);

        // Check that the metric was removed
        IAppraiser.Metric[] memory metrics = heart.getMovingAverageMetrics();
        assertEq(metrics.length, 0, "metric count");

        // Add three metrics
        vm.startPrank(policy);
        heart.addMovingAverageMetric(IAppraiser.Metric.BACKING);
        heart.addMovingAverageMetric(IAppraiser.Metric.LIQUID_BACKING);
        heart.addMovingAverageMetric(IAppraiser.Metric.MARKET_VALUE);

        // Remove a metric
        heart.removeMovingAverageMetric(IAppraiser.Metric.LIQUID_BACKING);
        vm.stopPrank();

        IAppraiser.Metric[] memory newMetrics = heart.getMovingAverageMetrics();
        assertEq(uint8(newMetrics[0]), 0, "backing");
        assertEq(uint8(newMetrics[1]), 3, "market value");
    }

    //  [X]  getMovingAverageMetrics

    function testCorrectness_getMovingAverageMetrics() public {
        IAppraiser.Metric[] memory metrics = heart.getMovingAverageMetrics();
        assertEq(uint8(metrics[0]), 0, "backing");
        assertEq(metrics.length, 1, "metric count");

        // Add a metric
        vm.prank(policy);
        heart.addMovingAverageMetric(IAppraiser.Metric.MARKET_VALUE);

        // Check that the metric was added
        metrics = heart.getMovingAverageMetrics();
        assertEq(uint8(metrics[0]), 0, "backing");
        assertEq(uint8(metrics[1]), 3, "market value");
        assertEq(metrics.length, 2, "metric count");

        // Add a metric
        vm.prank(policy);
        heart.addMovingAverageMetric(IAppraiser.Metric.LIQUID_BACKING);

        // Check that the metric was added
        metrics = heart.getMovingAverageMetrics();
        assertEq(uint8(metrics[0]), 0, "backing");
        assertEq(uint8(metrics[1]), 3, "market value");
        assertEq(uint8(metrics[2]), 1, "liquid backing");
        assertEq(metrics.length, 3, "metric count");

        // Remove a metric
        vm.prank(policy);
        heart.removeMovingAverageMetric(IAppraiser.Metric.BACKING);

        // Check that the metric was removed
        metrics = heart.getMovingAverageMetrics();
        assertEq(uint8(metrics[0]), 1, "liquid backing");
        assertEq(uint8(metrics[1]), 3, "market value");
        assertEq(metrics.length, 2, "metric count");
    }

    //  [X]  getMovingAverageMetricsCount

    function testCorrectness_getMovingAverageMetricsCount() public {
        assertEq(heart.getMovingAverageMetricsCount(), 1, "metric count");

        // Add a metric
        vm.prank(policy);
        heart.addMovingAverageMetric(IAppraiser.Metric.MARKET_VALUE);

        // Check that the metric was added
        assertEq(heart.getMovingAverageMetricsCount(), 2, "metric count");

        // Add a metric
        vm.prank(policy);
        heart.addMovingAverageMetric(IAppraiser.Metric.LIQUID_BACKING);

        // Check that the metric was added
        assertEq(heart.getMovingAverageMetricsCount(), 3, "metric count");

        // Remove a metric
        vm.prank(policy);
        heart.removeMovingAverageMetric(IAppraiser.Metric.BACKING);

        // Check that the metric was removed
        assertEq(heart.getMovingAverageMetricsCount(), 2, "metric count");
    }
}