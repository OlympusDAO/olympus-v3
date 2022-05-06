// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {OlympusStaking} from "../modules/STK.sol";
import {OlympusIndex} from "../modules/IDX.sol";

import {Kernel, Policy} from "../Kernel.sol";

contract Rebaser is Policy, ReentrancyGuard {
    error Rebaser_AmountMustBeNonzero();

    event Rebased(
        uint256 indexed epoch_,
        uint256 blockNumber_,
        uint256 rebasePct_,
        uint256 newIndex_
    );

    struct Epoch {
        uint256 length;
        uint256 number;
        uint256 end;
        uint256 toDistribute;
    }

    struct RateAdjustment {
        uint256 increment;
        uint256 targetRate;
    }

    uint256 private constant RATE_UNITS = 1e6;
    uint256 private constant SERIALIZED_UNITS = 1e18;

    OlympusIndex private IDX;
    OlympusStaking private STK;

    /// @notice Rate at which supply of OHM rebases. 6 decimals.
    uint256 public rebaseRate;

    /// @notice Current epoch information. Past epochs are emitted as events.
    Epoch public currentEpoch;

    /// @notice Bounty paid to callers of rebase.
    uint256 public bounty;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureModules() external override onlyKernel {
        STK = OlympusStaking(requireModule("STK"));
        IDX = OlympusIndex(requireModule("IDX"));
    }

    function requestPermissions()
        external
        view
        override
        onlyKernel
        returns (bytes3[] memory permissions)
    {
        permissions[1] = "STK";
        permissions[2] = "MNT";
    }

    function rebase() external nonReentrant {
        // TODO is reentrantGuard needed?
        if (currentEpoch.end <= block.timestamp) {
            // Trigger rebase by increasing the index
            uint256 newIndex = IDX.increaseIndex(rebaseRate);

            // Derive rebase information for next epoch
            currentEpoch.end += currentEpoch.length;
            currentEpoch.number++;

            // TODO is it necessary to design for distribution of OHM to contracts other than this?
            // TODO when would this ever be needed?

            // Calculate how much next rebase will need to distribute.
            currentEpoch.toDistribute = getNextDistribution();

            emit Rebased(
                currentEpoch.number,
                block.number,
                rebaseRate,
                newIndex
            );
        }
    }

    function getNextDistribution() public view returns (uint256) {
        // TODO verify
        return (STK.indexedSupply() * IDX.index() * rebaseRate) / RATE_UNITS;
    }

    function mintAndSync() external nonReentrant {
        // TODO mint&sync logic
    }

    function setRebaseRate(uint256 newRate_) external {
        if (newRate_ == 0) revert Rebaser_AmountMustBeNonzero();
        rebaseRate = newRate_;
    }

    function setBounty(uint256 newBounty_) external {
        if (newBounty_ == 0) revert Rebaser_AmountMustBeNonzero();
        bounty = newBounty_;
    }
}
