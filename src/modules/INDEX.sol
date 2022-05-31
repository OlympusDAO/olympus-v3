// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {Kernel, Module} from "../Kernel.sol";

// Module to keep track of index and total virtual supply of OHM
// (OHM that is staked and unstaked)
contract OlympusIndex is Module {
    event IndexUpdated(uint256 newIndex_, uint256 timestamp_);
    event RebaseRateUpdated(uint256 newRate_);

    uint256 public index;
    uint256 public lastUpdated;

    // Total supply of OHM that is staked and unstaked.
    // This is for keeping track of total dynamic supply due to
    // minting and burning the supply of OHM when staking/unstaking.
    uint256 public constant RATE_UNITS = 1e6;

    constructor(Kernel kernel_, uint256 initialIndex_) Module(kernel_) {
        index = initialIndex_;
        lastUpdated = block.timestamp;
    }

    function KEYCODE() public pure override returns (bytes5) {
        return "INDEX";
    }

    /// @notice Increase index by a given rate. Called by Rebaser policy.
    /// @param rebaseRate_ Rate at which supply of OHM rebases. 6 decimals.
    function increaseIndex(uint256 rebaseRate_)
        external
        onlyPermittedPolicies
        returns (uint256)
    {
        index = (index * (RATE_UNITS + rebaseRate_)) / RATE_UNITS;
        lastUpdated = block.timestamp;

        emit IndexUpdated(index, lastUpdated);

        return index;
    }

    function getLatestIndex() external view returns (uint256, uint256) {
        return (index, lastUpdated);
    }
}
