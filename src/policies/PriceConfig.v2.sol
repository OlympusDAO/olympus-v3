// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity 0.8.15;

// Interfaces
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";

// Bophades

import {Kernel, Keycode, toKeycode, Policy, Permissions} from "src/Kernel.sol";
import {SubKeycode, Submodule} from "src/Submodules.sol";
import {ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";
import {PolicyEnabler} from "policies/utils/PolicyEnabler.sol";

/// @notice     Policy to configure PRICEv2
/// @dev        Some functions in this policy are gated to addresses with the "price_manager" or "admin" roles
contract PriceConfigv2 is Policy, PolicyEnabler, IPriceConfigv2 {
    // DONE
    // [X] Policy setup
    // [X] Install/upgrade submodules
    // [X] Add asset to PRICEv2
    // [X] Remove asset from PRICEv2
    // [X] Update price feeds for asset on PRICEv2
    // [X] Update price strategy for asset on PRICEv2
    // [X] Update moving average data for asset on PRICEv2

    // ========== ERRORS ========== //

    // ========== EVENTS ========== //

    // ========== STATE ========== //

    bytes32 internal constant _PRICE_MANAGER_ROLE = "price_manager";

    // Modules
    PRICEv2 public PRICE;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_) Policy(kernel_) {}

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("PRICE");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        PRICE = PRICEv2(getModuleAddress(dependencies[1]));

        (uint8 PRICE_MAJOR, ) = PRICE.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([2, 1]);
        if (PRICE_MAJOR != 2 || ROLES_MAJOR != 1) revert Policy_WrongModuleVersion(expected);
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
            funcSelector: PRICE.updateAssetPriceFeeds.selector
        });
        requests[3] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.updateAssetPriceStrategy.selector
        });
        requests[4] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.updateAssetMovingAverage.selector
        });
        requests[5] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.installSubmodule.selector
        });
        requests[6] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.upgradeSubmodule.selector
        });
        requests[7] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.execOnSubmodule.selector
        });
    }

    /// @inheritdoc IPriceConfigv2
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 2;
        minor = 0;
    }

    //==================================================================================================//
    //                                      MODIFIERS                                                   //
    //==================================================================================================//

    function _onlyPriceManagerOrAdminRole() internal view {
        if (!ROLES.hasRole(msg.sender, _PRICE_MANAGER_ROLE) && !_isAdmin(msg.sender)) {
            revert NotAuthorised();
        }
    }

    /// @notice Modifier that reverts if the caller does not have the admin or price_manager role
    modifier onlyPriceManagerOrAdminRole() {
        _onlyPriceManagerOrAdminRole();
        _;
    }

    //==================================================================================================//
    //                                      PRICE MANAGEMENT                                            //
    //==================================================================================================//

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
    ) external override onlyEnabled onlyPriceManagerOrAdminRole {
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
    function removeAssetPrice(
        address asset_
    ) external override onlyEnabled onlyPriceManagerOrAdminRole {
        PRICE.removeAsset(asset_);
    }

    /// @inheritdoc IPriceConfigv2
    function updateAssetPriceFeeds(
        address asset_,
        IPRICEv2.Component[] memory feeds_
    ) external override onlyEnabled onlyPriceManagerOrAdminRole {
        PRICE.updateAssetPriceFeeds(asset_, feeds_);
    }

    /// @inheritdoc IPriceConfigv2
    function updateAssetPriceStrategy(
        address asset_,
        IPRICEv2.Component memory strategy_,
        bool useMovingAverage_
    ) external override onlyEnabled onlyPriceManagerOrAdminRole {
        PRICE.updateAssetPriceStrategy(asset_, strategy_, useMovingAverage_);
    }

    /// @inheritdoc IPriceConfigv2
    function updateAssetMovingAverage(
        address asset_,
        bool storeMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_
    ) external override onlyEnabled onlyPriceManagerOrAdminRole {
        PRICE.updateAssetMovingAverage(
            asset_,
            storeMovingAverage_,
            movingAverageDuration_,
            lastObservationTime_,
            observations_
        );
    }

    //==================================================================================================//
    //                                      SUBMODULE MANAGEMENT                                        //
    //==================================================================================================//

    /// @inheritdoc IPriceConfigv2
    function installSubmodule(address submodule_) external override onlyEnabled onlyAdminRole {
        PRICE.installSubmodule(Submodule(submodule_));
    }

    /// @inheritdoc IPriceConfigv2
    function upgradeSubmodule(address submodule_) external override onlyEnabled onlyAdminRole {
        PRICE.upgradeSubmodule(Submodule(submodule_));
    }

    /// @inheritdoc IPriceConfigv2
    function execOnSubmodule(
        SubKeycode subKeycode_,
        bytes calldata data_
    ) external override onlyEnabled onlyPriceManagerOrAdminRole {
        PRICE.execOnSubmodule(subKeycode_, data_);
    }

    // ========== ERC165 ========== //

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IPriceConfigv2).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
