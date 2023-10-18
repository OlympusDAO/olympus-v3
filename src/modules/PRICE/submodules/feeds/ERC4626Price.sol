// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/PRICE/PRICE.v2.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

contract ERC4626Price is PriceSubmodule {
    using FullMath for uint256;

    /// @notice     Any token or pool with a decimal scale greater than this would result in an overflow
    uint8 internal constant BASE_10_MAX_EXPONENT = 50;

    // TODO
    // [X] handle different decimals between ERC4626 and underlying
    // [ ] assert asset decimals within bounds
    // [ ] assert underlying decimals within bounds
    // [ ] assert underlying is set

    // ========== ERRORS ========== //

    /// @notice                     The value for output decimals is more than the maximum decimals allowed
    /// @param outputDecimals_      The output decimals provided as a parameter
    /// @param maxDecimals_         The maximum decimals allowed
    error ERC4626_OutputDecimalsOutOfBounds(uint8 outputDecimals_, uint8 maxDecimals_);

    /// @notice                     The value for the ERC4626 decimals is more than the maximum decimals allowed
    /// @param assetDecimals_       The asset decimals
    /// @param maxDecimals_         The maximum decimals allowed
    error ERC4626_AssetDecimalsOutOfBounds(uint8 assetDecimals_, uint8 maxDecimals_);

    /// @notice                     The value for the ERC4626 underlying asset's decimals is more than the maximum decimals allowed
    /// @param underlyingDecimals_  The underlying asset decimals
    /// @param maxDecimals_         The maximum decimals allowed
    error ERC4626_UnderlyingDecimalsOutOfBounds(uint8 underlyingDecimals_, uint8 maxDecimals_);

    /// @notice                     The underlying asset is not set
    /// @param asset_               The address of the ERC4626 asset
    error ERC4626_UnderlyingNotSet(address asset_);

    // ========== EVENTS ========== //

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_) Submodule(parent_) {}

    // ========== SUBMODULE FUNCTIONS =========== //

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.ERC4626");
    }

    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // ========== PRICE FUNCTIONS ========== //
    function getPriceFromUnderlying(
        address asset_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        uint256 outputScale = 10 ** outputDecimals_;

        // We assume that the asset passed conforms to ERC4626
        ERC4626 asset = ERC4626(asset_);
        uint256 assetScale = 10 ** asset.decimals();

        // Get the underlying asset from the ERC4626
        address underlying = address(asset.asset());

        // Get the decimals for the underlying asset
        uint256 underlyingScale = 10 ** ERC20(underlying).decimals();

        // Get the number of underlying tokens per share
        // Scale: output decimals
        uint256 underlyingPerShare = asset.convertToAssets(assetScale).mulDiv(outputScale, underlyingScale);

        // Get the price of the underlying asset
        // We assume that getPrice() returns in outputDecimals
        uint256 underlyingPrice = _PRICE().getPrice(underlying);

        // Calculate the price of the asset
        // Scale: output decimals
        uint256 assetPrice = underlyingPrice.mulDiv(underlyingPerShare, outputScale);

        return assetPrice;
    }
}
