// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/SPPLY/SPPLY.v1.sol";
import {CustomSupply} from "modules/SPPLY/submodules/CustomSupply.sol";

/// @title      SiloArbSupply
/// @author     0xJem
/// @notice     SPPLY submodule representing OHM in Silo on Arbitrum
contract SiloArbSupply is CustomSupply {
    // ========== CONSTRUCTOR ========== //

    constructor(
        Module parent_,
        uint256 collateralizedOhm_,
        uint256 protocolOwnedBorrowableOhm_,
        uint256 protocolOwnedLiquidityOhm_,
        uint256 protocolOwnedTreasuryOhm_
    )
        CustomSupply(
            parent_,
            collateralizedOhm_,
            protocolOwnedBorrowableOhm_,
            protocolOwnedLiquidityOhm_,
            protocolOwnedTreasuryOhm_,
            address(0) // No source
        )
    {}

    // ========== SUBMODULE SETUP ========== //

    /// @inheritdoc Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("SPPLY.SILOARB");
    }

    /// @inheritdoc Submodule
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    /// @inheritdoc Submodule
    function INIT() external override onlyParent {}
}
