pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";

import "modules/SPPLY/SPPLY.v1.sol";
import {CustomSupply} from "modules/SPPLY/submodules/CustomSupply.sol";

import {IgOHM} from "src/interfaces/IgOHM.sol";

/// @title      BrickedSupply
/// @notice     SPPLY submodule representing a manual adjustment for OHM stuck in the sOHM v2 contract
contract BrickedSupply is CustomSupply {
    /// @notice     Addresses of tokens to check for bricked supply that are denominated in OHM
    address[] public ohmDenominatedTokens;

    /// @notice     Addresses of tokens to check for bricked supply that are denominated in gOHM
    address[] public gohmDenominatedTokens;

    // ========= CONSTRUCTOR ========= //

    constructor(
        Module parent_,
        address source_,
        address[] memory ohmDenominatedTokens_,
        address[] memory gohmDenominatedTokens_
    ) CustomSupply(parent_, 0, 0, 0, 0, source_) {
        ohmDenominatedTokens = ohmDenominatedTokens_;
        gohmDenominatedTokens = gohmDenominatedTokens_;
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
        uint256 brickedOhm;

        // Check OHM denominated tokens
        uint256 numOhmDenominatedTokens = ohmDenominatedTokens.length;
        for (uint256 i; i < numOhmDenominatedTokens; ) {
            address token = ohmDenominatedTokens[i];
            brickedOhm += ERC20(token).balanceOf(token);

            unchecked {
                ++i;
            }
        }

        // Check gOHM denominated tokens
        uint256 numGohmDenominatedTokens = gohmDenominatedTokens.length;
        for (uint256 i; i < numGohmDenominatedTokens; ) {
            address token = gohmDenominatedTokens[i];
            uint256 gohmBalance = ERC20(token).balanceOf(token);
            brickedOhm += IgOHM(token).balanceFrom(gohmBalance);

            unchecked {
                ++i;
            }
        }

        return brickedOhm;
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice     Set the addresses of tokens to check for bricked supply that are denominated in OHM
    ///
    /// @param      ohmDenominatedTokens_     The new addresses of tokens to check
    function setOhmDenominatedTokens(address[] memory ohmDenominatedTokens_) external onlyParent {
        ohmDenominatedTokens = ohmDenominatedTokens_;
    }

    /// @notice     Set the addresses of tokens to check for bricked supply that are denominated in gOHM
    ///
    /// @param      gohmDenominatedTokens_     The new addresses of tokens to check
    function setGohmDenominatedTokens(address[] memory gohmDenominatedTokens_) external onlyParent {
        gohmDenominatedTokens = gohmDenominatedTokens_;
    }
}