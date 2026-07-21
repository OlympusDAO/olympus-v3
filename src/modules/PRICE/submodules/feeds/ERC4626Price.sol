// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function)
pragma solidity >=0.8.15;

// Interfaces
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {ERC4626} from "@solmate-6.2.0/mixins/ERC4626.sol";
import {FullMath} from "src/libraries/FullMath.sol";

// Bophades
import {Module} from "src/Kernel.sol";
import {PRICEv2, PriceSubmodule} from "modules/PRICE/PRICE.v2.sol";
import {Submodule, SubKeycode, toSubKeycode} from "src/Submodules.sol";

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

    /// @notice                     The value for the ERC4626 underlying decimals is more than the maximum decimals allowed
    ///
    /// @param underlyingDecimals_  The underlying asset decimals
    /// @param maxDecimals_         The maximum decimals allowed
    error ERC4626_UnderlyingDecimalsOutOfBounds(uint8 underlyingDecimals_, uint8 maxDecimals_);

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
        return (1, 0);
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
    /// @dev                    - The underlying decimals are more than the maximum decimals allowed
    /// @dev                    - The underlying asset is not set
    /// @dev                    - The price of the underlying asset cannot be determined using PRICE
    ///
    /// @dev                    Limitations:
    /// @dev                    - This adapter trusts the raw ERC4626 `convertToAssets()` share rate. It does not
    /// @dev                      smooth, bound, or otherwise sanity-check vault accounting changes, so it should
    /// @dev                      only be configured for vaults whose share conversion is already trusted on oracle
    /// @dev                      timescales.
    /// @dev                    - This adapter reports the ERC4626 idealized average-user conversion. It does not
    /// @dev                      account for withdrawal fees, redemption gates, slippage, or other execution
    /// @dev                      conditions that may make actual exits worse than `convertToAssets()`.
    ///
    /// @param asset_           The address of the ERC4626 asset
    /// @param outputDecimals_  The number of output decimals (assumed to be the same as PRICE decimals)
    /// @return uint256         The price of `asset_` in USD (in the scale of `outputDecimals_`)
    function getPriceFromUnderlying(
        address asset_,
        uint8 outputDecimals_,
        bytes calldata
    ) external view returns (uint256) {
        // Check output decimals
        if (outputDecimals_ > BASE_10_MAX_EXPONENT) {
            revert ERC4626_OutputDecimalsOutOfBounds(outputDecimals_, BASE_10_MAX_EXPONENT);
        }

        // We assume that the asset passed conforms to ERC4626
        ERC4626 asset = ERC4626(asset_);
        address underlying = address(asset.asset());

        // Should not be possible, but we check anyway
        if (underlying == address(0)) {
            revert ERC4626_UnderlyingNotSet(asset_);
        }

        // Check decimals
        uint256 assetScale;
        uint256 underlyingScale;
        {
            uint8 assetDecimals = asset.decimals();
            uint8 underlyingDecimals = ERC20(underlying).decimals();

            // Don't allow an unreasonably large number of decimals that would result in an overflow
            if (assetDecimals > BASE_10_MAX_EXPONENT) {
                revert ERC4626_AssetDecimalsOutOfBounds(assetDecimals, BASE_10_MAX_EXPONENT);
            }
            if (underlyingDecimals > BASE_10_MAX_EXPONENT) {
                revert ERC4626_UnderlyingDecimalsOutOfBounds(
                    underlyingDecimals,
                    BASE_10_MAX_EXPONENT
                );
            }

            assetScale = 10 ** assetDecimals;
            underlyingScale = 10 ** underlyingDecimals;
        }

        // Get the price of the underlying asset
        // We assume that getPrice() returns in outputDecimals
        // If the underlying price is not set, PRICE will revert
        // Scale: output decimals
        (uint256 underlyingPrice, ) = PRICEv2(_PRICE()).getPrice(
            underlying,
            IPRICEv2.Variant.CURRENT
        );

        // Calculate the price of one whole share.
        // underlyingPrice: output decimals
        // assetScale: one whole share, in share token decimals
        // convertToAssets(assetScale): underlying asset amount, in underlying token decimals
        // underlyingScale: underlying token decimals
        // Result: output decimals, rounded down by mulDiv.
        // Scale: output decimals
        uint256 assetPrice = (underlyingPrice).mulDiv(
            asset.convertToAssets(assetScale),
            underlyingScale
        );

        return assetPrice;
    }
}
/// forge-lint: disable-end(mixed-case-function)
