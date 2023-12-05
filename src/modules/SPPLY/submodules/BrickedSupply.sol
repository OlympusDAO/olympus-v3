pragma solidity 0.8.15;

import "modules/SPPLY/SPPLY.v1.sol";
import {CustomSupply} from "modules/SPPLY/submodules/CustomSupply.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title      BrickedSupply
/// @notice     SPPLY submodule representing a manual adjustment for OHM stuck in the sOHM v2 contract
contract BrickedSupply is CustomSupply {
    /// @notice     The sOHM v2 contract (any sOHM in here is bricked)
    address public immutable sOHMv2;

    // ========= CONSTRUCTOR ========= //

    constructor(
        Module parent_,
        address source_,
        address sOHMv2_
    ) CustomSupply(parent_, 0, 0, 0, 0, source_) {
        sOHMv2 = sOHMv2_;
    }

    // ========= SUBMODULE SETUP ========= //

    /// @inheritdoc Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("SPPLY.BRICKED");
    }

    /// @inheritdoc Submodule
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    /// @inheritdoc Submodule
    function INIT() external override onlyParent {}

    // ========= DATA FUNCTIONS ========= //

    /// @inheritdoc SupplySubmodule
    /// @dev        Calculated as the quantity of sOHM v2 in the contract
    function getProtocolOwnedTreasuryOhm() external view override returns (uint256) {
        // TODO: This can be extended to check for OHM in the OHM contract, gOHM in the gOHM contract, etc.
        return ERC20(sOHMv2).balanceOf(sOHMv2);
    }
}