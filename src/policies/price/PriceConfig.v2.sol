// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Libraries
import {Deviation} from "src/libraries/Deviation.sol";
import {FullMath} from "src/libraries/FullMath.sol";

// Bophades
import {Kernel, Keycode, toKeycode, Policy, Permissions, Module} from "src/Kernel.sol";
import {SubKeycode, Submodule} from "src/Submodules.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @notice     Policy to configure PRICEv2
/// @dev        Some functions in this policy are gated to addresses with the "price_admin" or "admin" roles
contract PriceConfigv2 is Policy, PolicyEnabler, IPriceConfigv2, IVersioned {
    using FullMath for uint256;

    // ========== STATE ========== //

    bytes5 internal constant _PRICE_KEYCODE = "PRICE";
    bytes5 internal constant _ROLES_KEYCODE = "ROLES";

    bytes32 internal constant _PRICE_ADMIN_ROLE = "price_admin";
    uint16 internal constant _BPS_MAX = 10_000;

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
    /// @dev        Reverts if:
    ///             - The configured PRICE module version is unsupported
    ///             - The configured PRICE module does not implement IPRICEv2
    ///             - The configured ROLES module major version is unsupported
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode(_ROLES_KEYCODE);
        dependencies[1] = toKeycode(_PRICE_KEYCODE);

        address priceModule = getModuleAddress(dependencies[1]);

        // Require PRICE v1.2+ (major=1, minor>=2) or v2+ (major>=2)
        // Cast to Module to access VERSION() function
        (uint8 major, uint8 minor) = Module(priceModule).VERSION();
        if ((major == 1 && minor < 2) || major < 1)
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
    /// @dev        Does not revert.
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
            funcSelector: PRICE.storeObservation.selector
        });
        requests[7] = Permissions({
            keycode: PRICE_KEYCODE,
            funcSelector: PRICE.storeObservations.selector
        });
    }

    /// @inheritdoc IVersioned
    /// @dev        Does not revert.
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

    /// @notice                         Validates each feed against its configured expected price
    /// @dev                            This is a configuration-time plausibility check only. It does
    ///                                 not prove feed identity, since another asset with a similar
    ///                                 price can still pass within tolerance.
    ///
    /// @param asset_                   The address of the asset being configured
    /// @param feeds_                   The feeds to validate
    /// @param feedExpectations_        The expected price and tolerance for each feed
    function _validatePriceFeedExpectations(
        address asset_,
        IPRICEv2.Component[] memory feeds_,
        PriceFeedExpectation[] memory feedExpectations_
    ) internal view {
        uint256 len = feeds_.length;
        if (feedExpectations_.length != len)
            revert IPriceConfigv2_FeedExpectationCountInvalid(
                asset_,
                feedExpectations_.length,
                len
            );

        uint8 priceDecimals = PRICE.decimals();
        for (uint256 i; i < len; ) {
            PriceFeedExpectation memory expectation = feedExpectations_[i];
            if (expectation.expectedPrice == 0 || expectation.toleranceBps > _BPS_MAX)
                revert IPriceConfigv2_FeedExpectationInvalid(asset_, i);

            (bool success, bytes memory data) = address(
                PRICE.getSubmoduleForKeycode(feeds_[i].target)
            ).staticcall(
                    abi.encodeWithSelector(
                        feeds_[i].selector,
                        asset_,
                        priceDecimals,
                        feeds_[i].params
                    )
                );

            if (!success || data.length != 32) revert IPriceConfigv2_PriceFeedCallFailed(asset_, i);

            uint256 price = abi.decode(data, (uint256));

            if (
                price == 0 ||
                Deviation.isDeviating(
                    price,
                    expectation.expectedPrice,
                    expectation.toleranceBps,
                    _BPS_MAX
                )
            ) {
                uint256 lowerBound = expectation.expectedPrice.mulDiv(
                    _BPS_MAX - expectation.toleranceBps,
                    _BPS_MAX
                );
                uint256 upperBound = expectation.expectedPrice.mulDivUp(
                    _BPS_MAX + expectation.toleranceBps,
                    _BPS_MAX
                );

                revert IPriceConfigv2_PriceFeedOutOfBounds(
                    asset_,
                    i,
                    price,
                    lowerBound,
                    upperBound
                );
            }

            unchecked {
                ++i;
            }
        }
    }

    // ========== PRICE MANAGEMENT ========== //

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - PRICE rejects the asset configuration
    function addAsset(
        address asset_,
        bool storeMovingAverage_,
        bool useMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_,
        IPRICEv2.Component memory strategy_,
        IPRICEv2.Component[] memory feeds_,
        PriceFeedExpectation[] memory feedExpectations_
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

        _validatePriceFeedExpectations(asset_, feeds_, feedExpectations_);
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - PRICE rejects the removal
    function removeAssetPrice(address asset_) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.removeAsset(asset_);
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - PRICE rejects the update
    function updateAsset(
        address asset_,
        IPRICEv2.UpdateAssetParams memory params_,
        PriceFeedExpectation[] memory feedExpectations_
    ) external override onlyEnabled onlyPriceOrAdminRole {
        uint256 expectedCount = params_.updateFeeds ? params_.feeds.length : 0;
        if (feedExpectations_.length != expectedCount)
            revert IPriceConfigv2_FeedExpectationCountInvalid(
                asset_,
                feedExpectations_.length,
                expectedCount
            );

        PRICE.updateAsset(asset_, params_);

        if (params_.updateFeeds)
            _validatePriceFeedExpectations(asset_, params_.feeds, feedExpectations_);
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - PRICE rejects storing the observation
    function storeObservation(address asset_) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.storeObservation(asset_);
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - PRICE rejects storing observations
    function storeObservations() external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.storeObservations();
    }

    // ========== SUBMODULE MANAGEMENT ========== //

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - PRICE rejects submodule installation
    function installSubmodule(
        address submodule_
    ) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.installSubmodule(Submodule(submodule_));
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - PRICE rejects submodule upgrade
    function upgradeSubmodule(
        address submodule_
    ) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.upgradeSubmodule(Submodule(submodule_));
    }

    /// @inheritdoc IPriceConfigv2
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - PRICE rejects the submodule call
    function execOnSubmodule(
        SubKeycode subKeycode_,
        bytes calldata data_
    ) external override onlyEnabled onlyPriceOrAdminRole {
        PRICE.execOnSubmodule(subKeycode_, data_);
    }

    // ========== ERC165 ========== //

    /// @notice Query if a contract implements an interface
    /// @dev    Does not revert.
    ///
    /// @param  interfaceId The interface identifier, as specified in ERC-165
    /// @return bool        True if the contract implements `interfaceId`
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IPriceConfigv2).interfaceId ||
            interfaceId == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
