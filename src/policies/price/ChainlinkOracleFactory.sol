// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity ^0.8.15;

// Libraries
import {Strings} from "@openzeppelin-5.7.0/utils/Strings.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {BaseOracleFactory} from "src/policies/price/BaseOracleFactory.sol";
import {ChainlinkOracleCloneable} from "src/policies/price/ChainlinkOracleCloneable.sol";

/// @title  ChainlinkOracleFactory
/// @author OlympusDAO
/// @notice Factory contract for deploying ChainlinkOracle clones for base/quote token pairs
/// @dev    Uses ClonesWithImmutableArgs for gas-efficient oracle deployment
contract ChainlinkOracleFactory is BaseOracleFactory {
    using Strings for uint256;

    // ========== STATE ========== //

    /// @notice Reference implementation for cloning
    ChainlinkOracleCloneable public immutable ORACLE_IMPLEMENTATION;

    // ========== CONSTRUCTOR ========== //

    /// @notice Constructs a new ChainlinkOracleFactory
    /// @dev Reverts if:
    ///      - priceCache_ is not a valid IPriceCache policy for this Kernel.
    ///
    /// @param  kernel_ The Kernel address
    /// @param  priceCache_ The price cache policy address
    constructor(Kernel kernel_, address priceCache_) BaseOracleFactory(kernel_, priceCache_) {
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
    /// @dev    Generates oracle name and encodes immutable args.
    function _encodeOracleData(
        address baseToken_,
        address quoteToken_,
        uint48 maxAge_,
        bytes calldata
    ) internal view override returns (bytes memory) {
        // Compose name from token symbols and maxAge: "base/quote CL {maxAge}s"
        string memory baseSymbol = priceCache.assetSymbol(baseToken_);
        string memory quoteSymbol = priceCache.assetSymbol(quoteToken_);
        // Display names retain exactly the first 32 bytes and are not used as oracle identifiers.
        // This multiline operation needs a range; the suppression ends immediately after it.
        // forge-lint: disable-start(unsafe-typecast)
        bytes32 oracleName = bytes32(
            bytes(
                string.concat(
                    baseSymbol,
                    "/",
                    quoteSymbol,
                    " CL ",
                    uint256(maxAge_).toString(),
                    "s"
                )
            )
        );
        // forge-lint: disable-end(unsafe-typecast)
        // Intentionally snapshot cache decimals at oracle creation so each oracle keeps a fixed scale.
        uint8 priceCacheDecimals = priceCache.decimals();

        // Create clone with immutable args
        // Layout:
        // factory (20 bytes) | base (20 bytes) | quote (20 bytes) | cache decimals (1 byte) | maxAge (8 bytes) | name (32 bytes)
        return
            abi.encodePacked(
                address(this), // factory address (20 bytes, ends at 0x14)
                baseToken_, // base token address (20 bytes, ends at 0x28)
                quoteToken_, // quote token address (20 bytes, ends at 0x3C)
                priceCacheDecimals, // cache decimals at creation (1 byte, at 0x3C)
                uint64(maxAge_), // max age (8 bytes, starts at 0x3D)
                oracleName // name (32 bytes, starts at 0x45)
            );
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
