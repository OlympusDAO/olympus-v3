// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {Auth, Authority} from "solmate/auth/Auth.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {TransferHelper} from "../libraries/TransferHelper.sol";

import {IERC20} from "../interfaces/IERC20.sol";
import {OlympusERC20Token as OHM} from "../external/OlympusERC20.sol";
import {OlympusStaking} from "../modules/STK.sol";
import {Kernel, Policy} from "../Kernel.sol";

//import "./OlympusErrors.sol";

/// @notice Handles minting/burning of OHM and sOHM, staking, sOHM<>gOHM conversions, and all rebase logic.
/// Also holds all debt facility functions.
/// @dev Minter go brrrr
contract OlympusMinterr is Policy, Auth, ReentrancyGuard {
    using TransferHelper for IERC20;
    using FixedPointMathLib for uint256;

    error AmountMustBeNonzero(uint256 amount_);

    event Minted(string indexed token_, address indexed to_, uint256 amount_);
    event Burned(string indexed token_, address indexed from_, uint256 amount_);
    /// @dev RebasePct is 6 decimals
    event Rebased(
        uint256 indexed epoch_,
        uint256 blockNumber_,
        uint256 rebasePct_,
        uint256 totalStakedBefore_,
        uint256 index_
    );
    event EpochLengthUpdated(uint256 epochLength_);
    event BountyUpdated(uint256 bounty_);
    event IncurredDebt(address indexed debtor_, uint256 amount_);
    event RepayedDebt(
        address indexed debtor_,
        uint256 amount_,
        uint256 remaining
    );

    // TODO pack this. Add descriptive comment
    /// @notice Contains all data pertaining to current epoch
    struct Epoch {
        uint256 length;
        uint256 number;
        uint256 end;
        uint256 toDistribute;
    }

    // TODO pack this
    /// @notice Hold data to guide rebase rate changes.
    /// @dev Intended to be declarative way for policy to change rebase rate.
    /// Should easily allow algorithmic control of rate adjustments as well.
    struct RateAdjustment {
        /// @dev Amount to increment rebase rate by. 6 decimals.
        uint256 increment;
        /// @dev Target rebase rate. Stops changing rate once target is met. 6 decimals.
        uint256 targetRate;
    }

    uint256 private constant RATE_UNITS = 1e6;
    uint256 private constant SERIALIZED_UNITS = 1e18;

    OlympusStaking private STK;
    OHM public ohm;

    /// @notice Rate at which supply of OHM rebases. 6 decimals.
    uint256 public rebaseRate;

    /// @notice Adjustments to rebase rate as defined by policy.
    RateAdjustment public adjustment;

    /// @notice Current epoch information. Past epochs are emitted as events.
    Epoch public currentEpoch;

    /// @notice Bounty paid to callers of rebase.
    uint256 public bounty;

    constructor(
        Kernel kernel_,
        OHM ohm_,
        uint256 epochLength_,
        uint256 firstEpochNumber_,
        uint256 firstEpochTime_,
        address owner_,
        Authority authority_
    ) Policy(kernel_) Auth(owner_, authority_) {
        ohm = ohm_;

        currentEpoch = Epoch({
            length: epochLength_,
            number: firstEpochNumber_,
            end: firstEpochTime_,
            toDistribute: 0
        });
    }

    function configureModules() external override {
        STK = OlympusStaking(requireModule("STK"));
    }

    /// @notice Function to rebase sOHM supply, mint new OHM into Minter, then set next rebase's target rate
    /// based on how much OHM was minted.
    /// @dev Rebases work in 3 steps:
    /// 1. Use the current `toDistribute` to increase the sOHM supply
    /// 2. Mint new OHM according to the current rebase rate and send to Minter.
    /// 3. Derive the next `toDistribute` amount by checking the difference between Minter OHM and
    function rebase() external nonReentrant {
        // TODO is reentrantGuard needed?
        if (currentEpoch.end <= block.timestamp) {
            // Rebase staked supply
            STK.rebaseSupply(currentEpoch.toDistribute);

            // Derive rebase information for next epoch
            currentEpoch.end += currentEpoch.length;
            currentEpoch.number++;

            // TODO is it necessary to design for distribution of OHM to contracts other than this?
            // TODO when would this ever be needed?

            // Mint OHM into Minter according to rebase rate. This new amount is used for the next rebase.
            // Bounty is minted and sent to caller
            uint256 nextRebaseAmount = ohm.totalSupply().mulDivDown(
                rebaseRate,
                RATE_UNITS
            );

            // TODO add bounty
            mintOhm(address(STK), nextRebaseAmount);

            // TODO add adjustment logic here if needed

            // Calculate how much next rebase will need to distribute.
            currentEpoch.toDistribute = STK.getNextDistribution();

            // TODO init mint&sync logic

            // TODO transmit gons offworld

            // messageBus.transmitGons()
            //emit Rebased(
            //    currentEpoch.number,
            //    block.number,
            //    currentEpoch.toDistribute,
            //    circulatingSupply,
            //    sOHM.gonsPerFragment
            //    0
            //);
        }
    }

    /// @notice Sets percent of OHM supply to mint for rebase.
    /// @dev Rate is 6 decimals.
    function setRebaseRate(uint256 newRate_) external {
        rebaseRate = newRate_;
        // TODO transmit this via messageBus
    }

    /// @notice Sets epoch length for use in rebase logic.
    function setEpochLength(uint256 length_) external {
        if (length_ == 0) revert AmountMustBeNonzero(length_);
        currentEpoch.length = length_;

        emit EpochLengthUpdated(length_);
    }

    /// @notice Set the bounty paid to caller of rebase function.
    function setBounty(uint256 newBounty_) external {
        if (newBounty_ == 0) revert AmountMustBeNonzero(newBounty_);

        bounty = newBounty_;

        emit BountyUpdated(newBounty_);
    }

    /// @notice Mints new OHM to an address. Must be authorized.
    /// @dev Addresses must be whitelisted to be able to mint. Mint requirements
    ///      are handled by the whitelisted contracts. Access must be scrutinized
    ///      and safeguarded by governance.
    function mintOhm(address to_, uint256 amount_) public requiresAuth {
        ohm.mint(to_, amount_);
    }

    /// @notice Burns OHM from an address. Must be authorized.
    /// @dev Addresses must be whitelisted to be able to burn. Burn requirements
    ///      are handled by the whitelisted contracts. Access must be guarded
    ///      by governance.
    function burnOhm(address from_, uint256 amount_) public requiresAuth {
        ohm.burnFrom(from_, amount_);
    }
}
