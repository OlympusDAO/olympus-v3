// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Bophades
import {Kernel} from "src/Kernel.sol";
import {BaseOracleFactory} from "src/policies/price/BaseOracleFactory.sol";
import {MorphoOracleCloneable} from "src/policies/price/MorphoOracleCloneable.sol";

import {LibString} from "@solmate-6.2.0/utils/LibString.sol";

/// @title  MorphoOracleFactory
/// @author OlympusDAO
/// @notice Factory contract for deploying MorphoOracle clones for collateral/loan token pairs
/// @dev    Uses ClonesWithImmutableArgs for gas-efficient oracle deployment
contract MorphoOracleFactory is BaseOracleFactory {
    using LibString for uint256;

    // ========== STATE ========== //

    /// @notice Reference implementation for cloning
    MorphoOracleCloneable public immutable ORACLE_IMPLEMENTATION;

    /// @notice The Morpho scale factor decimals
    uint8 internal constant MORPHO_DECIMALS = 36;

    // ========== ERRORS ========== //

    /// @notice Thrown when token decimals result in invalid scale factor (overflow or negative)
    ///
    /// @param  collateralToken The collateral token address
    /// @param  loanToken       The loan token address
    error MorphoOracleFactory_TokenDecimalsOutOfBounds(address collateralToken, address loanToken);

    // ========== CONSTRUCTOR ========== //

    /// @notice Constructs a new MorphoOracleFactory
    /// @dev    Reverts if `priceCache_` is not a valid IPriceCache policy for this Kernel.
    ///
    /// @param  kernel_ The Kernel address
    /// @param  priceCache_ The price cache policy address
    constructor(Kernel kernel_, address priceCache_) BaseOracleFactory(kernel_, priceCache_) {
        // Deploy implementation for cloning
        ORACLE_IMPLEMENTATION = new MorphoOracleCloneable();
    }

    // ========== ABSTRACT METHOD IMPLEMENTATIONS ========== //

    /// @inheritdoc BaseOracleFactory
    /// @notice Returns the Morpho oracle implementation address for cloning
    ///
    /// @return The address of the MorphoOracleCloneable implementation
    function _getOracleImplementation() internal view override returns (address) {
        return address(ORACLE_IMPLEMENTATION);
    }

    /// @inheritdoc BaseOracleFactory
    /// @notice Encodes Morpho-specific oracle data for cloning
    /// @dev    Performs Morpho-specific validation (decimals bounds check),
    ///         calculates scale factor, generates oracle name, and encodes immutable args.
    ///         Note: baseToken_ is used as collateralToken, quoteToken_ is used as loanToken.
    function _encodeOracleData(
        address collateralToken_,
        address loanToken_,
        uint48 maxAge_,
        bytes calldata
    ) internal view override returns (bytes memory) {
        // Calculate scale factor
        uint8 collateralDecimals = priceCache.assetDecimals(collateralToken_);
        uint8 loanDecimals = priceCache.assetDecimals(loanToken_);

        // Validate decimals to prevent overflow (max exponent ~77 for uint256)
        // MORPHO_DECIMALS = 36, so we need loanDecimals - collateralDecimals < 41
        // This is extremely unlikely in practice (tokens typically have 0-18 decimals)
        // but we add a check for safety
        /// forge-lint: disable-next-line(unsafe-typecast)
        int256 exponent = int256(uint256(loanDecimals)) -
            int256(uint256(collateralDecimals)) +
            int256(uint256(MORPHO_DECIMALS));
        if (exponent < 0 || exponent > 77) {
            revert MorphoOracleFactory_TokenDecimalsOutOfBounds(collateralToken_, loanToken_);
        }

        /// forge-lint: disable-next-line(unsafe-typecast)
        uint256 scaleFactor = 10 ** uint256(exponent);

        // Compose name from token symbols and maxAge: "collateral/loan M {maxAge}s"
        string memory collateralSymbol = priceCache.assetSymbol(collateralToken_);
        string memory loanSymbol = priceCache.assetSymbol(loanToken_);
        bytes32 oracleName = bytes32(
            abi.encodePacked(
                collateralSymbol,
                "/",
                loanSymbol,
                " M ",
                uint256(maxAge_).toString(),
                "s"
            )
        );

        // Create clone with immutable args
        // Layout:
        // factory (20 bytes) | collateral (20 bytes) | loan (20 bytes) | maxAge (8 bytes) | scaleFactor (32 bytes) | name (32 bytes)
        return
            abi.encodePacked(
                address(this), // factory address
                collateralToken_, // collateral token address
                loanToken_, // loan token address
                uint64(maxAge_), // max age
                scaleFactor, // scale factor
                oracleName // name
            );
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
