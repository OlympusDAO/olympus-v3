// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// External libraries
import {ReentrancyGuard} from "@solmate-6.2.0/utils/ReentrancyGuard.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

// Internal libraries
import {TransferHelper} from "src/libraries/TransferHelper.sol";

// Interfaces
import {IDistributor} from "src/policies/interfaces/IDistributor.sol";
import {IOperator} from "src/policies/interfaces/IOperator.sol";
import {IYieldRepo} from "src/policies/interfaces/IYieldRepo.sol";
import {IHeart} from "src/policies/interfaces/IHeart.sol";
import {IReserveMigrator} from "src/policies/interfaces/IReserveMigrator.sol";
import {IEmissionManager} from "src/policies/interfaces/IEmissionManager.sol";

// Modules
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";
import {PRICEv1} from "src/modules/PRICE/PRICE.v1.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

// Kernel
import {Kernel, Policy, Keycode, Permissions, toKeycode} from "src/Kernel.sol";

/// @title  Olympus Heart
/// @notice Olympus Heart (Policy) Contract
/// @dev    The Olympus Heart contract provides keeper rewards to call the heart beat function which fuels
///         Olympus market operations. The Heart orchestrates state updates in the correct order to ensure
///         market operations use up to date information.
///         This version implements an auction style reward system where the reward is linearly increasing up to a max reward.
///         Rewards are issued in OHM.
contract OlympusHeart is IHeart, Policy, RolesConsumer, ReentrancyGuard {
    using TransferHelper for ERC20;

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
    TRSRYv1 internal TRSRY;

    // Policies
    IOperator public operator;
    IDistributor public distributor;
    IYieldRepo public yieldRepo;
    IReserveMigrator public reserveMigrator;
    IEmissionManager public emissionManager;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    /// @dev Auction duration must be less than or equal to frequency, but we cannot validate that in the constructor because PRICE is not yet set.
    ///      Therefore, manually ensure that the value is valid when deploying the contract.
    constructor(
        Kernel kernel_,
        IOperator operator_,
        IDistributor distributor_,
        IYieldRepo yieldRepo_,
        IReserveMigrator reserveMigrator_,
        IEmissionManager emissionManager_,
        uint256 maxReward_,
        uint48 auctionDuration_
    ) Policy(kernel_) {
        operator = operator_;
        distributor = distributor_;
        yieldRepo = yieldRepo_;
        reserveMigrator = reserveMigrator_;
        emissionManager = emissionManager_;

        active = true;
        auctionDuration = auctionDuration_;
        maxReward = maxReward_;

        emit RewardUpdated(maxReward_, auctionDuration_);
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](5);
        dependencies[0] = toKeycode("PRICE");
        dependencies[1] = toKeycode("ROLES");
        dependencies[2] = toKeycode("MINTR");
        dependencies[3] = toKeycode("TRSRY");

        PRICE = PRICEv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));
        MINTR = MINTRv1(getModuleAddress(dependencies[2]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[3]));

        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();
        (uint8 PRICE_MAJOR, ) = PRICE.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1, 1, 1]);
        if (MINTR_MAJOR != 1 || PRICE_MAJOR != 1 || ROLES_MAJOR != 1 || TRSRY_MAJOR != 1)
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
        if (!active) revert Heart_BeatStopped();
        uint48 currentTime = uint48(block.timestamp);
        if (currentTime < lastBeat + frequency()) revert Heart_OutOfCycle();

        // Update the moving average on the Price module
        PRICE.updateMovingAverage();

        // Migrate reserves, if necessary
        reserveMigrator.migrate();

        // Trigger price range update and market operations
        operator.operate();

        // Trigger protocol loop
        yieldRepo.endEpoch();

        // Trigger rebase
        distributor.triggerRebase();

        // Trigger emission manager
        emissionManager.execute();

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

    /// @inheritdoc IHeart
    function setDistributor(address distributor_) external onlyRole("heart_admin") {
        distributor = IDistributor(distributor_);
        _syncBeatWithDistributor();
    }

    /// @inheritdoc IHeart
    function setYieldRepo(address yieldRepo_) external onlyRole("heart_admin") {
        yieldRepo = IYieldRepo(yieldRepo_);
    }

    /// @inheritdoc IHeart
    function setReserveMigrator(address reserveMigrator_) external onlyRole("heart_admin") {
        reserveMigrator = IReserveMigrator(reserveMigrator_);
    }

    /// @inheritdoc IHeart
    function setEmissionManager(address emissionManager_) external onlyRole("heart_admin") {
        emissionManager = IEmissionManager(emissionManager_);
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
                currentTime - nextBeat >= duration
                    ? maxReward
                    : (uint256(currentTime - nextBeat) * maxReward) / duration;
        }
    }
}
