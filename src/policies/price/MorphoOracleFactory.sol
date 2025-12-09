// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {MorphoOracleCloneable} from "src/policies/price/MorphoOracleCloneable.sol";
import {BaseOracleFactory} from "src/policies/price/BaseOracleFactory.sol";

// Bophades
import {Kernel} from "src/Kernel.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

/// @title  MorphoOracleFactory
/// @author OlympusDAO
/// @notice Factory contract for deploying MorphoOracle clones for collateral/loan token pairs
/// @dev    Uses ClonesWithImmutableArgs for gas-efficient oracle deployment
contract MorphoOracleFactory is BaseOracleFactory {
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
    ///
    /// @param  kernel_ The Kernel address
    constructor(Kernel kernel_) BaseOracleFactory(kernel_) {
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
    ///         calculates scale factor, generates oracle name, and encodes immutable args
    ///
    /// @param  collateralToken_    The collateral token address
    /// @param  loanToken_          The loan token address
    /// @return bytes               The encoded bytes for cloning
    function _encodeOracleData(
        address collateralToken_,
        address loanToken_,
        bytes calldata
    ) internal view override returns (bytes memory) {
        // Calculate scale factor
        uint8 collateralDecimals = ERC20(collateralToken_).decimals();
        uint8 loanDecimals = ERC20(loanToken_).decimals();

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

        // Compose name from token symbols: "collateral/loan Morpho Oracle"
        string memory collateralSymbol = ERC20(collateralToken_).symbol();
        string memory loanSymbol = ERC20(loanToken_).symbol();
        bytes32 oracleName = bytes32(
            abi.encodePacked(collateralSymbol, "/", loanSymbol, " Morpho Oracle")
        );

        // Create clone with immutable args
        // Layout: factory (20 bytes) | collateral (20 bytes) | loan (20 bytes) | scaleFactor (32 bytes) | name (32 bytes)
        return
            abi.encodePacked(
                address(this), // factory address
                collateralToken_, // collateral token address
                loanToken_, // loan token address
                scaleFactor, // scale factor
                oracleName // name
            );
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
