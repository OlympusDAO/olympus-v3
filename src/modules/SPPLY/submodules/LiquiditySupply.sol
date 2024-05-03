// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {Module} from "src/Kernel.sol";
import {Submodule, SubKeycode, toSubKeycode} from "src/Submodules.sol";
import {SupplySubmodule} from "src/modules/SPPLY/SPPLY.v1.sol";

import {CustomSupply} from "modules/SPPLY/submodules/CustomSupply.sol";

/// @title      LiquiditySupply
/// @author     0xJem
/// @notice     SPPLY submodule representing an admin-defined amount of OHM in protocol-owned liquidity.
///             This can be used in instances where the OHM is deployed in liquidity pools,
///             but the LP token or position is not managed by the on-chain accounting system
///             and hence not accounted for.
contract LiquiditySupply is CustomSupply {
    // ========== CONSTRUCTOR ========== //

    constructor(
        Module parent_,
        uint256 protocolOwnedLiquidityOhm_,
        address source_
    ) CustomSupply(parent_, 0, 0, protocolOwnedLiquidityOhm_, 0, source_) {
        // Nothing to do
    }

    // ========== SUBMODULE SETUP ========== //

    /// @inheritdoc Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("SPPLY.LIQSPPLY");
    }

    /// @inheritdoc Submodule
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    /// @inheritdoc Submodule
    function INIT() external override onlyParent {}

    // ========== SUBMODULE FUNCTIONS ========== //

    /// @inheritdoc SupplySubmodule
    function storeObservations() external virtual override {
        // Nothing to do
    }
}
