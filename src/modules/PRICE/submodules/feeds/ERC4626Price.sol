// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/PRICE/PRICE.v2.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

contract ERC4626Price is PriceSubmodule {
    // ========== ERRORS ========== //

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
        // We assume that the asset passed conforms to ERC4626
        ERC4626 asset = ERC4626(asset_);
        uint256 assetScale = 10 ** asset.decimals();

        // Get the underlying asset from the ERC4626
        address underlying = address(asset.asset());

        // Get the number of underlying tokens per share
        // We assume that the underlying and asset have the same decimals
        uint256 underlyingPerShare = asset.convertToAssets(assetScale);

        // Get the price of the underlying asset
        uint256 underlyingPrice = _PRICE().getPrice(underlying);

        // Calculate the price of the asset
        uint256 assetPrice = (underlyingPrice * underlyingPerShare) / assetScale;

        // Convert to output decimals and return
        return (assetPrice * 10 ** outputDecimals_) / assetScale;
    }
}
