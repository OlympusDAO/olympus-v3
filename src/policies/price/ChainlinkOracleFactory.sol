// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Bophades
import {Kernel} from "src/Kernel.sol";
import {BaseOracleFactory} from "src/policies/price/BaseOracleFactory.sol";
import {ChainlinkOracleCloneable} from "src/policies/price/ChainlinkOracleCloneable.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

/// @title  ChainlinkOracleFactory
/// @author OlympusDAO
/// @notice Factory contract for deploying ChainlinkOracle clones for base/quote token pairs
/// @dev    Uses ClonesWithImmutableArgs for gas-efficient oracle deployment
contract ChainlinkOracleFactory is BaseOracleFactory {
    // ========== STATE ========== //

    /// @notice Reference implementation for cloning
    ChainlinkOracleCloneable public immutable ORACLE_IMPLEMENTATION;

    // ========== CONSTRUCTOR ========== //

    /// @notice Constructs a new ChainlinkOracleFactory
    ///
    /// @param  kernel_ The Kernel address
    constructor(Kernel kernel_) BaseOracleFactory(kernel_) {
        // Deploy implementation for cloning
        ORACLE_IMPLEMENTATION = new ChainlinkOracleCloneable();
    }

    // ========== ABSTRACT METHOD IMPLEMENTATIONS ========== //

    /// @inheritdoc BaseOracleFactory
    /// @notice Returns the Chainlink oracle implementation address for cloning
    ///
    /// @return The address of the ChainlinkOracleCloneable implementation
    function _getOracleImplementation() internal view override returns (address) {
        return address(ORACLE_IMPLEMENTATION);
    }

    /// @inheritdoc BaseOracleFactory
    /// @dev    Validates tokens are configured in PRICE module, captures current PRICE decimals,
    ///         generates oracle name, and encodes immutable args.
    function _encodeOracleData(
        address baseToken_,
        address quoteToken_,
        bytes calldata
    ) internal view override returns (bytes memory) {
        // Compose name from token symbols: "base/quote Chainlink Oracle"
        string memory baseSymbol = ERC20(baseToken_).symbol();
        string memory quoteSymbol = ERC20(quoteToken_).symbol();
        bytes32 oracleName = bytes32(
            abi.encodePacked(baseSymbol, "/", quoteSymbol, " Chainlink Oracle")
        );

        // Create clone with immutable args
        // Layout: factory (20 bytes) | base (20 bytes) | quote (20 bytes) | PRICE decimals (1 byte) | name (32 bytes)
        return
            abi.encodePacked(
                address(this), // factory address (20 bytes, ends at 0x14)
                baseToken_, // base token address (20 bytes, ends at 0x28)
                quoteToken_, // quote token address (20 bytes, ends at 0x3C)
                PRICE_DECIMALS, // PRICE decimals at creation (1 byte, at 0x3C)
                oracleName // name (32 bytes, starts at 0x3D)
            );
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
