// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/PRICE/PRICE.v2.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

/// @title      ERC4626Price
/// @author     0xJem
/// @notice     A PRICE submodule that provides the price for ERC4626 assets
contract ERC4626Price is PriceSubmodule {
    using FullMath for uint256;

    /// @notice     Any token or pool with a decimal scale greater than this would result in an overflow
    uint8 internal constant BASE_10_MAX_EXPONENT = 38;

    // [X] handle different decimals between ERC4626 and underlying
    // [X] assert underlying decimals within bounds
    // [X] assert underlying is set

    // ========== ERRORS ========== //

    /// @notice                     The value for output decimals is more than the maximum decimals allowed
    ///
    /// @param outputDecimals_      The output decimals provided as a parameter
    /// @param maxDecimals_         The maximum decimals allowed
    error ERC4626_OutputDecimalsOutOfBounds(uint8 outputDecimals_, uint8 maxDecimals_);

    /// @notice                     The value for the ERC4626 decimals is more than the maximum decimals allowed
    ///
    /// @param assetDecimals_       The asset decimals
    /// @param maxDecimals_         The maximum decimals allowed
    error ERC4626_AssetDecimalsOutOfBounds(uint8 assetDecimals_, uint8 maxDecimals_);

    /// @notice                     There is a mismatch between the decimals of the ERC4626 asset and underlying
    ///
    /// @param assetDecimals_       The asset decimals
    /// @param underlyingAssetDecimals_  The underlying asset decimals
    error ERC4626_AssetDecimalsMismatch(uint8 assetDecimals_, uint8 underlyingAssetDecimals_);

    /// @notice                     The underlying asset is not set
    ///
    /// @param asset_               The address of the ERC4626 asset
    error ERC4626_UnderlyingNotSet(address asset_);

    // ========== EVENTS ========== //

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_) Submodule(parent_) {}

    // ========== SUBMODULE FUNCTIONS =========== //

    /// @inheritdoc      Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.ERC4626");
    }

    /// @inheritdoc      Submodule
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // ========== PRICE FUNCTIONS ========== //

    /// @notice                 Determines the price of `asset_` in USD
    /// @dev                    This function performs the following:
    /// @dev                    - Performs basic checks
    /// @dev                    - Determines the underlying assets per share of `asset_`
    /// @dev                    - Determines the price of the underlying asset
    /// @dev                    - Returns the product
    ///
    /// @dev                    This function will revert if:
    /// @dev                    - The output decimals are more than the maximum decimals allowed
    /// @dev                    - The asset decimals are more than the maximum decimals allowed
    /// @dev                    - The asset and underlying decimals do not match
    /// @dev                    - The underlying asset is not set
    /// @dev                    - The price of the underlying asset cannot be determined using PRICE
    ///
    /// @param asset_           The address of the ERC4626 asset
    /// @param outputDecimals_  The number of decimals to return the price in
    /// @return                 The price of `asset_` in USD (in the scale of `outputDecimals_`)
    function getPriceFromUnderlying(
        address asset_,
        uint8 outputDecimals_,
        bytes calldata
    ) external view returns (uint256) {
        // Check output decimals
        if (outputDecimals_ > BASE_10_MAX_EXPONENT) {
            revert ERC4626_OutputDecimalsOutOfBounds(outputDecimals_, BASE_10_MAX_EXPONENT);
        }
        uint256 outputScale = 10 ** outputDecimals_;

        // We assume that the asset passed conforms to ERC4626
        ERC4626 asset = ERC4626(asset_);
        address underlying = address(asset.asset());

        // Should not be possible, but we check anyway
        if (underlying == address(0)) {
            revert ERC4626_UnderlyingNotSet(asset_);
        }

        // Check decimals
        uint256 assetScale;
        {
            uint8 assetDecimals = asset.decimals();
            uint8 underlyingDecimals = ERC20(underlying).decimals();
            // This shouldn't be possible, but we check anyway
            if (assetDecimals != underlyingDecimals) {
                revert ERC4626_AssetDecimalsMismatch(assetDecimals, underlyingDecimals);
            }

            // Don't allow an unreasonably large number of decimals that would result in an overflow
            if (assetDecimals > BASE_10_MAX_EXPONENT) {
                revert ERC4626_AssetDecimalsOutOfBounds(assetDecimals, BASE_10_MAX_EXPONENT);
            }

            assetScale = 10 ** assetDecimals;
        }

        // Get the number of underlying tokens per share
        // Scale: output decimals
        uint256 underlyingPerShare = asset.convertToAssets(assetScale).mulDiv(
            outputScale,
            assetScale
        );

        // Get the price of the underlying asset
        // We assume that getPrice() returns in outputDecimals
        // If the underlying price is not set, PRICE will revert
        uint256 underlyingPrice = _PRICE().getPrice(underlying);

        // Calculate the price of the asset
        // Scale: output decimals
        uint256 assetPrice = underlyingPrice.mulDiv(underlyingPerShare, outputScale);

        return assetPrice;
    }
}
