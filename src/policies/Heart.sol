// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

import {IDistributor} from "policies/interfaces/IDistributor.sol";
import {IOperator} from "policies/interfaces/IOperator.sol";
import {IHeart} from "policies/interfaces/IHeart.sol";

import {RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {PRICEv1} from "modules/PRICE/PRICE.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";

import "src/Kernel.sol";

/// @title  Olympus Heart
/// @notice Olympus Heart (Policy) Contract
/// @dev    The Olympus Heart contract provides keeper rewards to call the heart beat function which fuels
///         Olympus market operations. The Heart orchestrates state updates in the correct order to ensure
///         market operations use up to date information.
///         This version implements an auction style reward system where the reward is linearly increasing up to a max reward.
///         Rewards are issued in OHM.
contract OlympusHeart is IHeart, Policy, RolesConsumer, ReentrancyGuard {
    using TransferHelper for ERC20;

    // =========  ERRORS ========= //

    error Heart_WrongModuleVersion();

    // =========  STATE ========= //

    /// @notice Timestamp of the last beat (UTC, in seconds)
    uint48 public lastBeat;

    /// @notice Duration of the reward auction (in seconds)
    uint48 public auctionDuration;

    /// @notice Max reward for beating the Heart (in reward token decimals)
    uint256 public maxReward;

    /// @notice Status of the Heart, false = stopped, true = beating
    bool public active;

    // Modules
    PRICEv1 internal PRICE;
    MINTRv1 internal MINTR;

    // Policies
    IOperator public operator;
    IDistributor public distributor;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    /// @dev Auction duration must be less than or equal to frequency, but we cannot validate that in the constructor because PRICE is not yet set.
    ///      Therefore, manually ensure that the value is valid when deploying the contract.
    constructor(
        Kernel kernel_,
        IOperator operator_,
        IDistributor distributor_,
        uint256 maxReward_,
        uint48 auctionDuration_
    ) Policy(kernel_) {
        operator = operator_;
        distributor = distributor_;

        active = true;
        lastBeat = uint48(block.timestamp);
        auctionDuration = auctionDuration_;
        maxReward = maxReward_;

        emit RewardUpdated(maxReward_, auctionDuration_);
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

        (uint8 PRICE_MAJOR, ) = PRICE.VERSION();
        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        if (PRICE_MAJOR != 1 || MINTR_MAJOR != 1 || ROLES_MAJOR != 1)
            revert Heart_WrongModuleVersion();
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

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc IHeart
    function beat() external nonReentrant {
        if (!active) revert Heart_BeatStopped();
        uint48 currentTime = uint48(block.timestamp);
        if (currentTime < lastBeat + frequency()) revert Heart_OutOfCycle();

        // Update the moving average on the Price module
        PRICE.updateMovingAverage();

        // Trigger price range update and market operations
        operator.operate();

        // Trigger distributor rebase
        distributor.triggerRebase();

        // Calculate the reward
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

    function _resetBeat() internal {
        lastBeat = uint48(block.timestamp) - frequency();
    }

    /// @inheritdoc IHeart
    function resetBeat() external onlyRole("heart_admin") {
        _resetBeat();
    }

    /// @inheritdoc IHeart
    function activate() external onlyRole("heart_admin") {
        active = true;
        _resetBeat();
    }

    /// @inheritdoc IHeart
    function deactivate() external onlyRole("heart_admin") {
        active = false;
    }

    /// @inheritdoc IHeart
    function setOperator(address operator_) external onlyRole("heart_admin") {
        operator = IOperator(operator_);
    }

    modifier notWhileBeatAvailable() {
        // Prevent calling if a beat is available to avoid front-running a keeper
        if (uint48(block.timestamp) >= lastBeat + frequency()) revert Heart_BeatAvailable();
        _;
    }

    /// @inheritdoc IHeart
    function setRewardAuctionParams(
        uint256 maxReward_,
        uint48 auctionDuration_
    ) external onlyRole("heart_admin") notWhileBeatAvailable {
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
                currentTime - nextBeat > duration
                    ? maxReward
                    : (uint256(currentTime - nextBeat) * maxReward) / duration;
        }
    }
}
