// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {OlympusERC20Token} from "src/external/OlympusERC20.sol";
import {TransferHelper} from "libraries/TransferHelper.sol";

import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import "src/Kernel.sol";


interface IInverseBondDepo {
    function burn() external;
}


/// @title Olympus Legacy Burner Policy
contract LegacyBurner is Policy {

    // ========= ERRORS ========= //

    // ========= EVENTS ========= //

    event Burn(uint256 amount, uint256 reward);

    // ========= STATE ========= //

    // Modules
    MINTRv1 internal MINTR;

    // Token
    OlympusERC20Token public immutable ohm;

    // Burn Targets
    address public bondManager;
    address public inverseBondDepo;

    // Rewards Calculation
    uint256 internal lastRewardTime;
    uint256 internal rewardsPerSecond;
    uint256 internal maxRewardRate; // out of 100_000_000

    uint256 internal constant DENOMINATOR = 100_000_000;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        address ohm_,
        address bondManager_,
        address inverseBondDepo_,
        uint256 rewardsPerSecond_,
        uint256 maxRewardRate_ // out of 100_000_000
    ) Policy(kernel_) {
        // Address config
        ohm = OlympusERC20Token(ohm_);
        bondManager = bondManager_;
        inverseBondDepo = inverseBondDepo_;

        // Rewards config
        rewardsPerSecond = rewardsPerSecond_;
        maxRewardRate = maxRewardRate_;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("MINTR");

        MINTR = MINTRv1(getModuleAddress(dependencies[0]));

        // Set last reward time at time of activation
        lastRewardTime = block.timestamp;

        // Approve MINTR to burn OHM
        ohm.increaseAllowance(address(MINTR), type(uint256).max);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode MINTR_KEYCODE = MINTR.KEYCODE();
        
        requests = new Permissions[](3);
        requests[0] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
        requests[1] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        requests[2] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
    }

    //============================================================================================//
    //                                         BURN FUNCTIONS                                     //
    //============================================================================================//

    /// @notice Burn OHM from desired sources, send rewards to the caller
    /// @dev    Calculates linearly increasing reward (up to cap) for the amount of OHM burned, burns OHM from
    ///         BondManager and InverseBondDepo, and mints rewards to the caller. We use this approach of burning
    ///         everything and then reminting the rewards because the InverseBondDepo does not allow partial burns
    ///         or the transfer of OHM to another address. We have to burn the entire amount of OHM in the contract.
    ///         So we burn everything, then mint the rewards to the caller.
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
        MINTR.increaseMintApproval(address(this), reward);
        MINTR.mintOhm(msg.sender, reward);

        // Emit event
        emit Burn(bondManagerOhm + inverseBondDepoOhm, reward);
    }

    //============================================================================================//
    //                                       INTERNAL FUNCTIONS                                   //
    //============================================================================================//

    /// @notice Calculates the reward as a percentage of a given amount of OHM being burned. Reward rate linearly increases from the
    ///         last reward time to the current time, up to the max reward rate.
    function _getReward(uint256 amount) internal view returns (uint256 reward) {
        // Calculate reward rate
        uint256 timeElapsed = block.timestamp - lastRewardTime;
        uint256 rewardRate = timeElapsed * rewardsPerSecond;

        // Bound by max
        if (rewardRate > maxRewardRate) {
            rewardRate = maxRewardRate;
        }

        // Calculate reward
        reward = amount * rewardRate / DENOMINATOR;
    }

    /// @notice Burns OHM from the bond manager
    /// @dev    An infinite approval (via Policy MS) for this contract to spend OHM from the bond manager is required
    function _burnBondManagerOhm(uint256 amount_) internal {
        // Transfer from BondManager
        ohm.transferFrom(bondManager, address(this), amount_);

        // Burn the OHM
        MINTR.burnOhm(address(this), amount_);
    }

    /// @notice Burns OHM from the legacy inverse bond depository
    /// @dev    The only way to burn is to burn the entire amount of OHM in the contract, cannot transfer here first.
    ///         The burn function requires the caller to be specified as the `policy` address on an OlympusAuthority
    ///         contract. So in order for this to work we have to also deploy a mock OlympusAuthority contract that
    ///         specifies this contract as the policy address and then update the authority address on the inverse
    ///         bond depository contract.
    function _burnInverseBondDepoOhm() internal {
        // Cast address to interface
        IInverseBondDepo inverseBondDepo_ = IInverseBondDepo(inverseBondDepo);

        // Burn the OHM
        inverseBondDepo_.burn();
    }
}