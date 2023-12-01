pragma solidity 0.8.15;

import "modules/SPPLY/SPPLY.v1.sol";
import {CustomSupply} from "modules/SPPLY/submodules/CustomSupply.sol";

import {IgOHM} from "src/interfaces/IgOHM.sol";

/// @title      MigrationOffsetSupply
/// @author     0xJem
/// @notice     SPPLY submodule representing a manual adjustment for OHM in the migration contract
contract MigrationOffsetSupply is CustomSupply {
    /// @notice     The quantity of gOHM (in native decimals) to offset in the migration contract
    uint256 public gOhmOffset;

    // ========== EVENTS ========== //

    event GOhmOffsetUpdated(uint256 gOhmOffset_);

    // ========== CONSTRUCTOR ========== //

    constructor(
        Module parent_,
        address source_,
        uint256 gOhmOffset_
    ) CustomSupply(parent_, 0, 0, 0, 0, source_) {
        gOhmOffset = gOhmOffset_;

        emit GOhmOffsetUpdated(gOhmOffset_);
    }

    // ========== SUBMODULE SETUP ========== //

    /// @inheritdoc Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("SPPLY.MIGOFFSET");
    }

    /// @inheritdoc Submodule
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    /// @inheritdoc Submodule
    function INIT() external override onlyParent {}

    // ========== DATA FUNCTIONS ========== //

    /// @inheritdoc SupplySubmodule
    /// @dev        Calculated as the quantity of gOHM (`gOhmOffset`) multiplied by the current index
    function getProtocolOwnedTreasuryOhm() external view override returns (uint256) {
        // Convert from gOHM to OHM using the current index
        IgOHM gOHM = IgOHM(address(SPPLYv1(address(parent)).gohm()));

        return gOHM.balanceFrom(gOhmOffset);
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice     Set the quantity of gOHM (in native decimals) to offset in the migration contract
    ///
    /// @param      gOhmOffset_     The new quantity of gOHM to offset
    function setGOhmOffset(uint256 gOhmOffset_) external onlyParent {
        gOhmOffset = gOhmOffset_;

        emit GOhmOffsetUpdated(gOhmOffset_);
    }
}
