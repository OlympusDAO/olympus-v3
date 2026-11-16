// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

/// @notice Isolates the variant price overload so tests can reference its selector.
interface IPriceVariantReader {
    /// @notice Returns the requested price variant for an asset.
    /// @param asset Address of the asset to price.
    /// @param variant Oracle price variant to read.
    /// @return Price in the oracle's configured scale.
    /// @return Timestamp associated with the price.
    function getPrice(
        address asset,
        IPRICEv2.Variant variant
    ) external view returns (uint256, uint48);
}
