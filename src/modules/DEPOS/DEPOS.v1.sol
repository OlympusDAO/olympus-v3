// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.15;

// Interfaces
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";

// Libraries
import {ERC721} from "@solmate-6.2.0/tokens/ERC721.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";

// Bophades
import {Module} from "src/Kernel.sol";

/// @title  DEPOSv1
/// @notice This defines the interface for the DEPOS module.
///         The objective of this module is to track the terms of a deposit position.
abstract contract DEPOSv1 is Module, ERC721, IDepositPositionManager {
    // ========== CONSTANTS ========== //

    /// @notice The value used for the conversion price if conversion is not supported
    uint256 public constant NON_CONVERSION_PRICE = type(uint256).max;

    /// @notice The value used for the conversion expiry if conversion is not supported
    uint48 public constant NON_CONVERSION_EXPIRY = type(uint48).max;

    // ========== STATE VARIABLES ========== //

    /// @notice The number of positions created
    uint256 internal _positionCount;

    /// @notice Mapping of position records to an ID
    /// @dev    IDs are assigned sequentially starting from 0
    ///         Mapping entries should not be deleted, but can be overwritten
    mapping(uint256 => Position) internal _positions;

    /// @notice Mapping of user addresses to their position IDs
    mapping(address => EnumerableSet.UintSet) internal _userPositions;
}
