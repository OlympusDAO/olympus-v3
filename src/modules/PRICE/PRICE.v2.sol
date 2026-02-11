/// SPDX-License-Identifier: AGPL-3.0
// solhint-disable one-contract-per-file
/// forge-lint: disable-start(mixed-case-function)
pragma solidity >=0.8.15;

// Interfaces
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";

// Bophades
import {Keycode, toKeycode} from "src/Kernel.sol";
import {ModuleWithSubmodules, Submodule} from "src/Submodules.sol";

/// @notice     Abstract Bophades module for price resolution
/// @author     Oighty
abstract contract PRICEv2 is ModuleWithSubmodules, IPRICEv2, IERC165 {
    // ========== STATIC VARIABLES ========== //

    /// @notice     The frequency of price observations (in seconds)
    uint48 internal _observationFrequency;

    /// @notice     The number of decimals to used in output values
    uint8 internal _decimals;

    /// @notice     The addresses of tracked assets
    address[] public assets;

    /// @notice     Maps asset addresses to configuration data
    mapping(address => Asset) internal _assetData;

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IPRICEv2
    function observationFrequency() external view virtual override returns (uint48) {
        return _observationFrequency;
    }

    /// @inheritdoc IPRICEv2
    function decimals() external view virtual override returns (uint8) {
        return _decimals;
    }

    // ========== ERC165 FUNCTIONS ========== //

    function supportsInterface(bytes4 interfaceId_) public view virtual returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId || interfaceId_ == type(IPRICEv2).interfaceId;
    }
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
/// forge-lint: disable-end(mixed-case-function)
