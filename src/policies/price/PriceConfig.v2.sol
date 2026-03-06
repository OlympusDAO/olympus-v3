// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Bophades
import {Kernel, Keycode, toKeycode, Policy, Permissions, Module} from "src/Kernel.sol";
import {SubKeycode, Submodule} from "src/Submodules.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @notice     Policy to configure PRICEv2
/// @dev        Some functions in this policy are gated to addresses with the "price_admin" or "admin" roles
contract PriceConfigv2 is Policy, PolicyEnabler, IPriceConfigv2, IVersioned {
    // ========== STATE ========== //

    bytes5 internal constant _PRICE_KEYCODE = "PRICE";
    bytes5 internal constant _ROLES_KEYCODE = "ROLES";

    bytes32 internal constant _PRICE_ADMIN_ROLE = "price_admin";

    // Modules
    PRICEv2 public PRICE;

    // ========== POLICY SETUP ========== //

    constructor(Kernel kernel_) Policy(kernel_) {
        // Unlike normal policies, we want this to be enabled by default
        // This allows the "price_admin" to configure assets in the same transaction batch as the module install/upgrade.
        isEnabled = true;
        emit Enabled();
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode(_ROLES_KEYCODE);
        dependencies[1] = toKeycode(_PRICE_KEYCODE);

        address priceModule = getModuleAddress(dependencies[1]);

        // Require PRICE v1.2+ (major=1, minor>=2) or v2+ (major>=2)
        // Cast to Module to access VERSION() function
        (uint8 major, uint8 minor) = Module(priceModule).VERSION();
        if (major == 1 && minor < 2)
            revert IPriceConfigv2_UnsupportedModuleVersion(_PRICE_KEYCODE, major, minor);

        // Verify the PRICE module supports IPRICEv2 interface
        if (!IERC165(priceModule).supportsInterface(type(IPRICEv2).interfaceId))
            revert IPriceConfigv2_UnsupportedModuleInterface(
                _PRICE_KEYCODE,
                type(IPRICEv2).interfaceId
            );

        // Set ROLES module (required by PolicyEnabler)
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        // Set PRICE module
        PRICE = PRICEv2(priceModule);

        // Ensure ROLES module is using the expected major version
        (uint8 rolesMajor, uint8 rolesMinor) = ROLES.VERSION();
        if (rolesMajor != 1)
            revert IPriceConfigv2_UnsupportedModuleVersion(_ROLES_KEYCODE, rolesMajor, rolesMinor);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode PRICE_KEYCODE = toKeycode("PRICE");

        requests = new Permissions[](8);
        // PRICE Permissions
        requests[0] = Permissions({keycode: PRICE_KEYCODE, funcSelector: PRICE.addAsset.selector});
        requests[1] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.removeAsset.selector
        });
        requests[2] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.updateAsset.selector
        });
        requests[3] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.installSubmodule.selector
        });
        requests[4] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.upgradeSubmodule.selector
        });
        requests[5] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.execOnSubmodule.selector
        });
        requests[6] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.storePrice.selector
        });
        requests[7] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.storeObservations.selector
        });
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8, uint8) {
        return (2, 0);
    }

    // ========== MODIFIERS ========== //

    function _onlyPriceOrAdminRole() internal view {
        if (!ROLES.hasRole(msg.sender, _PRICE_ADMIN_ROLE) && !_isAdmin(msg.sender)) {
            revert NotAuthorised();
        }
    }

    /// @notice Modifier that reverts if the caller does not have the admin or price_admin role
    modifier onlyPriceOrAdminRole() {
        _onlyPriceOrAdminRole();
        _;
    }

    // ========== PRICE MANAGEMENT ========== //

    /// @inheritdoc IPriceConfigv2
    function addAssetPrice(
        address asset_,
        bool storeMovingAverage_,
        bool useMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_,
        IPRICEv2.Component memory strategy_,
        IPRICEv2.Component[] memory feeds_
    ) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.addAsset(
            asset_,
            storeMovingAverage_,
            useMovingAverage_,
            movingAverageDuration_,
            lastObservationTime_,
            observations_,
            strategy_,
            feeds_
        );
    }

    /// @inheritdoc IPriceConfigv2
    function removeAssetPrice(address asset_) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.removeAsset(asset_);
    }

    /// @inheritdoc IPriceConfigv2
    function updateAsset(
        address asset_,
        IPRICEv2.UpdateAssetParams memory params_
    ) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.updateAsset(asset_, params_);
    }

    /// @inheritdoc IPriceConfigv2
    function storePrice(address asset_) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.storePrice(asset_);
    }

    /// @inheritdoc IPriceConfigv2
    function storeObservations() external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.storeObservations();
    }

    // ========== SUBMODULE MANAGEMENT ========== //

    /// @inheritdoc IPriceConfigv2
    function installSubmodule(
        address submodule_
    ) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.installSubmodule(Submodule(submodule_));
    }

    /// @inheritdoc IPriceConfigv2
    function upgradeSubmodule(
        address submodule_
    ) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.upgradeSubmodule(Submodule(submodule_));
    }

    /// @inheritdoc IPriceConfigv2
    function execOnSubmodule(
        SubKeycode subKeycode_,
        bytes calldata data_
    ) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.execOnSubmodule(subKeycode_, data_);
    }

    // ========== ERC165 ========== //

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IPriceConfigv2).interfaceId ||
            interfaceId == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
