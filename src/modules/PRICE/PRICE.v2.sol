/// SPDX-License-Identifier: AGPL-3.0
// solhint-disable one-contract-per-file
/// forge-lint: disable-start(mixed-case-function)
pragma solidity >=0.8.15;

// Interfaces
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

// Bophades
import {Kernel, Keycode, Module, toKeycode} from "src/Kernel.sol";
import {ModuleWithSubmodules, Submodule} from "src/Submodules.sol";

/// @notice     Abstract Bophades module for price resolution
/// @author     Oighty
abstract contract PRICEv2 is ModuleWithSubmodules, IPRICEv2, IERC165 {
    // ========== STATIC VARIABLES ========== //

    // 840 is the ISO 4217 numeric currency code for USD.
    address internal constant _UNIT_OF_ACCOUNT = address(840);

    /// @notice     The frequency of price observations (in seconds)
    uint48 internal _observationFrequency;

    /// @notice     The number of decimals to used in output values
    uint8 internal _decimals;

    /// @notice     The addresses of tracked assets
    address[] public assets;

    /// @notice     Maps asset addresses to configuration data
    mapping(address => Asset) internal _assetData;

    /// @notice     Tracks registered non-contract assets
    mapping(address => bool) public isNonContractAsset;

    constructor(Kernel kernel_) Module(kernel_) {
        isNonContractAsset[_UNIT_OF_ACCOUNT] = true;
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IPRICEv2
    function observationFrequency() external view virtual override returns (uint48) {
        return _observationFrequency;
    }

    /// @inheritdoc IPRICEv2
    function decimals() external view virtual override returns (uint8) {
        return _decimals;
    }

    /// @inheritdoc IPRICEv2
    function unitOfAccount() external pure virtual override returns (address) {
        return _UNIT_OF_ACCOUNT;
    }

    /// @notice         Reverts unless `asset_` is a contract or a registered non-contract asset
    /// @dev            Will revert if:
    /// @dev            - `asset_` is a non-contract address that is not registered
    function _validateAssetIsManageable(address asset_) internal view {
        if (asset_.code.length == 0 && !isNonContractAsset[asset_]) {
            revert PRICE_InvalidAsset(asset_);
        }
    }

    // ========== ERC165 FUNCTIONS ========== //

    function supportsInterface(bytes4 interfaceId_) public pure virtual returns (bool) {
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
