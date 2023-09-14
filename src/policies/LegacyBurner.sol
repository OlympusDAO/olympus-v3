// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {TransferHelper} from "libraries/TransferHelper.sol";

import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";

import "src/Kernel.sol";


interface IInverseBondDepo {
    function burn() external;
}


/// @title Olympus Legacy Burner Policy
contract LegacyBurner is Policy {
    using TransferHelper for ERC20;

    // ========= ERRORS ========= //

    // ========= EVENTS ========= //

    event Burn(uint256 amount, uint256 reward);

    // ========= STATE ========= //

    // Modules
    MINTRv1 internal MINTR;

    // Token
    ERC20 public immutable ohm;

    // Burn Targets
    address public bondManager;
    address public inverseBondDepo;

    // Rewards Calculation
    uint256 internal lastRewardTime;
    uint256 internal maxRewardRate;
    uint256 internal duration; // in seconds

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        ERC20 ohm_,
        address bondManager_,
        address inverseBondDepo_,
        uint256 maxRewardRate_,
        uint256 duration_
    ) Policy(kernel_) {
        // Address config
        ohm = ohm_;
        bondManager = bondManager_;
        inverseBondDepo = inverseBondDepo_;

        // Rewards config
        lastRewardTime = block.timestamp;
        maxRewardRate = maxRewardRate_;
        duration = duration_;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("MINTR");

        MINTR = MINTRv1(getModuleAddress(dependencies[0]));

        // Approve MINTR to burn OHM
        ohm.safeApprove(address(MINTR), type(uint256).max);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](2);
        requests[0] = Permissions(MINTR.KEYCODE(), MINTR.mintOhm.selector);
        requests[1] = Permissions(MINTR.KEYCODE(), MINTR.burnOhm.selector);
    }

    //============================================================================================//
    //                                         BURN FUNCTIONS                                     //
    //============================================================================================//

    /// @notice Burn OHM from desired sources, send rewards to the caller
    function burn() external {
        // Determine balance of burnable OHM
        uint256 bondManagerOhm = ohm.balanceOf(bondManager);
        uint256 inverseBondDepoOhm = ohm.balanceOf(inverseBondDepo);

        // Calculate reward
        uint256 reward = _getReward(bondManagerOhm + inverseBondDepoOhm);

        // Burn OHM
        _burnBondManagerOhm(bondManagerOhm);
        _burnInverseBondDepoOhm();

        // Mint reward
        MINTR.mintOhm(msg.sender, reward);

        // Emit event
        emit Burn(bondManagerOhm + inverseBondDepoOhm, reward);
    }

    //============================================================================================//
    //                                       INTERNAL FUNCTIONS                                   //
    //============================================================================================//

    function _getReward(uint256 amount) internal view returns (uint256 reward) {
        // Calculate reward rate
        uint256 timeElapsed = block.timestamp - lastRewardTime;
        uint256 rewardsPerSecond = maxRewardRate / duration;
        uint256 rewardRate = timeElapsed * rewardsPerSecond;

        // Bound by max
        if (rewardRate > maxRewardRate) {
            rewardRate = maxRewardRate;
        }

        // Calculate reward
        reward = amount * rewardRate / 100_000_000;
    }

    function _burnBondManagerOhm(uint256 amount_) internal {
        // Transfer from BondManager
        ohm.safeTransferFrom(bondManager, address(this), amount_);

        // Burn the OHM
        MINTR.burnOhm(address(this), amount_);
    }

    function _burnInverseBondDepoOhm() internal {
        // Cast address to interface
        IInverseBondDepo inverseBondDepo_ = IInverseBondDepo(inverseBondDepo);

        // Burn the OHM
        inverseBondDepo_.burn();
    }
}