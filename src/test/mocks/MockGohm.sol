// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

interface IDelegate {
    function delegate(address) external;

    function delegates(address) external view returns (address);
}

/// @title MockGohm
/// @notice Mock gOHM token for testing the V1Migrator conversion
/// @dev    Uses an index that causes rounding to simulate production behavior
///         Index 269238508004 causes small rounding losses (e.g., 1000 OHM v1 -> 999.999999999 OHM v2)
contract MockGohm is MockERC20, IDelegate {
    /// @notice Index set to a value that causes rounding (not at base level of 1e9)
    ///         This simulates the real gOHM behavior where the index grows over time
    ///         At this index: balanceTo(balanceFrom(x)) < x for some values due to double rounding
    /// @dev    Made mutable to allow tests to set a custom index for specific scenarios
    uint256 public index = 269238508004;

    mapping(address => address) public override delegates;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) MockERC20(name_, symbol_, decimals_) {}

    function delegate(address delegatee_) public {
        delegates[msg.sender] = delegatee_;
    }

    /// @notice Set the gOHM index for testing purposes
    /// @param index_ The new index value (in 1e9 scale, where 1e9 = 1:1 ratio)
    function setIndex(uint256 index_) external {
        index = index_;
    }

    /// @notice Converts gOHM amount to OHM (what happens when unstaking)
    /// @param amount_ gOHM amount (18 decimals)
    /// @return OHM amount (9 decimals)
    function balanceFrom(uint256 amount_) public view returns (uint256) {
        return (amount_ * index) / 10 ** decimals;
    }

    /// @notice Converts OHM amount to gOHM (what happens when wrapping)
    /// @param amount_ OHM amount (9 decimals)
    /// @return gOHM amount (18 decimals)
    function balanceTo(uint256 amount_) public view returns (uint256) {
        return (amount_ * 10 ** decimals) / index;
    }
}
