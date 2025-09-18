// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.15;

// External libraries
import {ReentrancyGuard} from "@solmate-6.2.0/utils/ReentrancyGuard.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

// Internal libraries
import {TransferHelper} from "src/libraries/TransferHelper.sol";

// Interfaces
import {IDistributor} from "src/policies/interfaces/IDistributor.sol";
import {IHeart} from "src/policies/interfaces/IHeart.sol";

// Modules
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PRICEv1} from "src/modules/PRICE/PRICE.v1.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";

// Base Contracts
import {BasePeriodicTaskManager} from "src/bases/BasePeriodicTaskManager.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

// Kernel
import {Kernel, Policy, Keycode, Permissions, toKeycode} from "src/Kernel.sol";

/// @title  Olympus Heart
/// @notice Olympus Heart (Policy) Contract
/// @dev    The Olympus Heart contract provides keeper rewards to call the heart beat function which fuels
///         Olympus market operations. The Heart orchestrates state updates in the correct order to ensure
///         market operations use up to date information.
///         This version implements an auction style reward system where the reward is linearly increasing up to a max reward.
///         Rewards are issued in OHM.
contract OlympusHeart is IHeart, Policy, PolicyEnabler, ReentrancyGuard, BasePeriodicTaskManager {
    using TransferHelper for ERC20;

    // =========  STATE ========= //

    /// @notice Timestamp of the last beat (UTC, in seconds)
    uint48 public lastBeat;

    /// @notice Duration of the reward auction (in seconds)
    uint48 public auctionDuration;

    /// @notice Max reward for beating the Heart (in reward token decimals)
    uint256 public maxReward;

    // Modules
    PRICEv1 internal PRICE;
    MINTRv1 internal MINTR;

    // Policies
    IDistributor public distributor;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    /// @dev Auction duration must be less than or equal to frequency, but we cannot validate that in the constructor because PRICE is not yet set.
    ///      Therefore, manually ensure that the value is valid when deploying the contract.
    constructor(
        Kernel kernel_,
        IDistributor distributor_,
        uint256 maxReward_,
        uint48 auctionDuration_
    ) Policy(kernel_) {
        distributor = distributor_;

        auctionDuration = auctionDuration_;
        maxReward = maxReward_;

        emit RewardUpdated(maxReward_, auctionDuration_);

        // Disabled by default by PolicyEnabler
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("PRICE");
        dependencies[1] = toKeycode("ROLES");
        dependencies[2] = toKeycode("MINTR");

        PRICE = PRICEv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));
        MINTR = MINTRv1(getModuleAddress(dependencies[2]));

        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();
        (uint8 PRICE_MAJOR, ) = PRICE.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1, 1]);
        if (MINTR_MAJOR != 1 || PRICE_MAJOR != 1 || ROLES_MAJOR != 1)
            revert Policy_WrongModuleVersion(expected);

        // Sync beat with distributor if called from kernel
        if (msg.sender == address(kernel)) {
            _syncBeatWithDistributor();
        }
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode MINTR_KEYCODE = MINTR.KEYCODE();

        permissions = new Permissions[](3);
        permissions[0] = Permissions(PRICE.KEYCODE(), PRICE.updateMovingAverage.selector);
        permissions[1] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        permissions[2] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
    }

    /// @notice Returns the version of the policy.
    ///
    /// @return major The major version of the policy.
    /// @return minor The minor version of the policy.
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 7);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc IHeart
    function beat() external nonReentrant {
        if (!isEnabled) revert Heart_BeatStopped();
        uint48 currentTime = uint48(block.timestamp);
        if (currentTime < lastBeat + frequency()) revert Heart_OutOfCycle();

        // Update the moving average on the Price module
        // This cannot be a periodic task, because it requires a policy with permission to call the updateMovingAverage function
        PRICE.updateMovingAverage();

        // Trigger the rebase
        distributor.triggerRebase();

        // Execute periodic tasks
        _executePeriodicTasks();

        // Calculate the reward (0 <= reward <= maxReward) for the keeper
        uint256 reward = currentReward();

        // Update the last beat timestamp
        // Ensure that update frequency doesn't change, but do not allow multiple beats if one is skipped
        lastBeat = currentTime - ((currentTime - lastBeat) % frequency());

        // Issue the reward
        if (reward > 0) {
            MINTR.increaseMintApproval(address(this), reward);
            MINTR.mintOhm(msg.sender, reward);
            emit RewardIssued(msg.sender, reward);
        }

        emit Beat(block.timestamp);
    }

    //============================================================================================//
    //                                      ADMIN FUNCTIONS                                       //
    //============================================================================================//

    function _syncBeatWithDistributor() internal {
        (uint256 epochLength, , uint256 epochEnd, ) = distributor.staking().epoch();
        if (frequency() != epochLength) revert Heart_InvalidFrequency();
        lastBeat = uint48(epochEnd - epochLength);
    }

    function _resetBeat() internal {
        lastBeat = uint48(block.timestamp) - frequency();
    }

    /// @inheritdoc IHeart
    /// @dev        This function is gated to the ADMIN or MANAGER roles
    function resetBeat() external onlyManagerOrAdminRole {
        _resetBeat();
    }

    /// @inheritdoc PolicyEnabler
    function _enable(bytes calldata) internal override {
        _resetBeat();
    }

    /// @inheritdoc IHeart
    /// @dev        This function is gated to the ADMIN role
    function setDistributor(address distributor_) external onlyAdminRole {
        distributor = IDistributor(distributor_);
        _syncBeatWithDistributor();
    }

    modifier notWhileBeatAvailable() {
        // Prevent calling if a beat is available to avoid front-running a keeper
        if (uint48(block.timestamp) >= lastBeat + frequency()) revert Heart_BeatAvailable();
        _;
    }

    /// @inheritdoc IHeart
    /// @dev        This function is gated to the ADMIN role
    function setRewardAuctionParams(
        uint256 maxReward_,
        uint48 auctionDuration_
    ) external onlyAdminRole notWhileBeatAvailable {
        // auction duration should be less than or equal to frequency, otherwise frequency will be used
        if (auctionDuration_ > frequency()) revert Heart_InvalidParams();

        maxReward = maxReward_;
        auctionDuration = auctionDuration_;
        emit RewardUpdated(maxReward_, auctionDuration_);
    }

    //============================================================================================//
    //                                       VIEW FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc IHeart
    function frequency() public view returns (uint48) {
        return uint48(PRICE.observationFrequency());
    }

    /// @inheritdoc IHeart
    function currentReward() public view returns (uint256) {
        // If beat not available, return 0
        // Otherwise, calculate reward from linearly increasing auction bounded by maxReward and heart balance
        uint48 beatFrequency = frequency();
        uint48 nextBeat = lastBeat + beatFrequency;
        uint48 currentTime = uint48(block.timestamp);
        uint48 duration = auctionDuration > beatFrequency ? beatFrequency : auctionDuration;
        if (currentTime <= nextBeat) {
            return 0;
        } else {
            return
                currentTime - nextBeat >= duration
                    ? maxReward
                    : (uint256(currentTime - nextBeat) * maxReward) / duration;
        }
    }
}
