/// SPDX-License-Identifier: AGPL-3.0
// solhint-disable one-contract-per-file
pragma solidity 0.8.15;

import {Keycode, toKeycode} from "src/Kernel.sol";
import {ModuleWithSubmodules, Submodule} from "src/Submodules.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

/// @notice     Abstract Bophades module for price resolution
/// @author     Oighty
abstract contract PRICEv2 is ModuleWithSubmodules, IPRICEv2 {
    // ========== STATIC VARIABLES ========== //

    /// @notice     The frequency of price observations (in seconds)
    uint32 public observationFrequency;

    /// @notice     The number of decimals to used in output values
    uint8 public decimals;

    /// @notice     The addresses of tracked assets
    address[] public assets;

    /// @notice     Maps asset addresses to configuration data
    mapping(address => Asset) internal _assetData;
}

abstract contract PriceSubmodule is Submodule {
    // ========== SUBMODULE SETUP ========== //

    /// @inheritdoc Submodule
    function PARENT() public pure override returns (Keycode) {
        return toKeycode("PRICE");
    }

    /// @notice The parent PRICE module
    function _PRICE() internal view returns (PRICEv2) {
        return PRICEv2(address(parent));
    }
}
