// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IBondAuctioneer} from "src/interfaces/IBondAuctioneer.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2Config} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Config.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {Errors} from "src/libraries/Errors.sol";
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Constants.sol";

// Modules
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

// Contracts
import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";

/// @title YieldRepurchaseFacilityV2DependenciesLib
/// @notice An external library that resolves and validates the dependencies of the
///         YieldRepurchaseFacilityV2: the Kernel modules and their versions, the
///         configurator, the backing oracle, and the bond contracts.
/// @dev The library is deployed separately and reached through `DELEGATECALL`, so the
///      facility is `address(this)` and the errors belong to the facility interface. The
///      library holds no state: the facility passes its Kernel and stores what the library
///      resolves.
library YieldRepurchaseFacilityV2DependenciesLib {
    /// @notice Keycode of the TRSRY module dependency.
    /// @dev Pre-computed to avoid the runtime cost of `toKeycode("TRSRY")`.
    Keycode internal constant KEYCODE_TRSRY = Keycode.wrap(0x5452535259); // toKeycode("TRSRY")

    /// @notice Keycode of the PRICE module dependency.
    /// @dev Pre-computed to avoid the runtime cost of `toKeycode("PRICE")`.
    Keycode internal constant KEYCODE_PRICE = Keycode.wrap(0x5052494345); // toKeycode("PRICE")

    /// @notice Keycode of the CHREG module dependency.
    /// @dev Pre-computed to avoid the runtime cost of `toKeycode("CHREG")`.
    Keycode internal constant KEYCODE_CHREG = Keycode.wrap(0x4348524547); // toKeycode("CHREG")

    /// @notice Keycode of the ROLES module dependency.
    /// @dev Pre-computed to avoid the runtime cost of `toKeycode("ROLES")`.
    Keycode internal constant KEYCODE_ROLES = Keycode.wrap(0x524f4c4553); // toKeycode("ROLES")

    /// @notice The number of module dependencies of the facility.
    uint256 private constant _DEPENDENCY_COUNT = 4;

    /// @notice The number of module permissions the facility requests.
    uint256 private constant _PERMISSION_COUNT = 2;

    /// @notice The module handles resolved by `configureDependencies`.
    /// @param trsry The TRSRY module.
    /// @param price The PRICE module.
    /// @param chreg The CHREG module.
    /// @param roles The ROLES module.
    /// @param oracleDecimals The decimals the PRICE module reports.
    struct Modules {
        address trsry;
        address price;
        address chreg;
        address roles;
        uint8 oracleDecimals;
    }

    /// @notice Resolves the module dependencies of the facility from the Kernel and
    ///         validates their versions.
    /// @dev The dependency order is TRSRY, PRICE, CHREG, ROLES.
    ///
    ///      Reverts if:
    ///      - A dependency is not installed in the Kernel (`Policy_ModuleDoesNotExist`).
    ///      - Any of the TRSRY, PRICE, CHREG, or ROLES modules does not report major
    ///        version 1 (`Policy_WrongModuleVersion`).
    ///      - The PRICE module reports a minor version below 2
    ///        (`Policy_WrongModuleVersion`): the facility prices the assets through
    ///        `PRICE.getPriceIn`, which the PRICE surface provides from version 1.2.
    ///      - `PRICE.decimals()` is not 18, the decimals of the backing value
    ///        (`IYieldRepurchaseFacilityV2_UnsupportedOracleDecimals`).
    /// @param kernel_ The Kernel of the facility.
    /// @return dependencies The keycodes of the dependencies, in the order the facility
    ///         reports them.
    /// @return modules The resolved module handles and the PRICE decimals.
    function configureDependencies(
        Kernel kernel_
    ) external view returns (Keycode[] memory dependencies, Modules memory modules) {
        dependencies = new Keycode[](_DEPENDENCY_COUNT);
        dependencies[0] = KEYCODE_TRSRY;
        dependencies[1] = KEYCODE_PRICE;
        dependencies[2] = KEYCODE_CHREG;
        dependencies[3] = KEYCODE_ROLES;

        modules.trsry = _moduleAddress(kernel_, dependencies[0]);
        modules.price = _moduleAddress(kernel_, dependencies[1]);
        modules.chreg = _moduleAddress(kernel_, dependencies[2]);
        modules.roles = _moduleAddress(kernel_, dependencies[3]);

        // TRSRY compatibility depends only on its major version
        // forge-lint: disable-next-line(unused-return)
        (uint8 trsryMajor, ) = TRSRYv1(modules.trsry).VERSION();
        (uint8 priceMajor, uint8 priceMinor) = PRICEv2(modules.price).VERSION();
        // CHREG compatibility depends only on its major version
        // forge-lint: disable-next-line(unused-return)
        (uint8 chregMajor, ) = CHREGv1(modules.chreg).VERSION();
        // ROLES compatibility depends only on its major version
        // forge-lint: disable-next-line(unused-return)
        (uint8 rolesMajor, ) = ROLESv1(modules.roles).VERSION();
        if (trsryMajor != 1 || priceMajor != 1 || chregMajor != 1 || rolesMajor != 1)
            revert Policy.Policy_WrongModuleVersion(abi.encode([1, 1, 1, 1]));

        // The `getPriceIn` surface is provided by the PRICE module from version 1.2
        if (priceMinor < 2) revert Policy.Policy_WrongModuleVersion(abi.encode([1, 2]));

        // The oracle price is compared against the 18-decimal backing value, so the
        // oracle must report 18 decimals.
        modules.oracleDecimals = PRICEv2(modules.price).decimals();
        if (modules.oracleDecimals != YieldRepurchaseFacilityV2Constants.BACKING_DECIMALS)
            revert IYieldRepurchaseFacilityV2
                .IYieldRepurchaseFacilityV2_UnsupportedOracleDecimals();
    }

    /// @notice Returns the module permissions the facility requests: the TRSRY
    ///         `withdrawReserves` and `increaseWithdrawApproval` functions.
    /// @return permissions_ The requested permissions.
    function permissions() external pure returns (Permissions[] memory permissions_) {
        permissions_ = new Permissions[](_PERMISSION_COUNT);
        permissions_[0] = Permissions({
            keycode: KEYCODE_TRSRY,
            funcSelector: TRSRYv1.withdrawReserves.selector
        });
        permissions_[1] = Permissions({
            keycode: KEYCODE_TRSRY,
            funcSelector: TRSRYv1.increaseWithdrawApproval.selector
        });
    }

    /// @notice Reverts unless `configurator_` is a configuration policy bound to the
    ///         calling facility.
    /// @dev Reverts with `IYieldRepurchaseFacilityV2_InvalidConfigurator` if:
    ///      - `configurator_` is the zero address.
    ///      - `configurator_` is not an active policy of `kernel_`.
    ///      - `configurator_` does not report `kernel_` as its own.
    ///      - `configurator_` does not advertise `IYieldRepurchaseFacilityV2Config` through
    ///        ERC165, which includes a `supportsInterface` query that reverts.
    ///      - `facility()` does not return the calling facility.
    ///
    ///      An active policy that does not implement `kernel()` or `facility()` reverts in
    ///      the call itself.
    /// @param kernel_ The Kernel of the facility.
    /// @param configurator_ The configuration policy to validate.
    function validateConfigurator(Kernel kernel_, address configurator_) external view {
        if (
            configurator_ == address(0) ||
            !kernel_.isPolicyActive(Policy(configurator_)) ||
            address(Policy(configurator_).kernel()) != address(kernel_) ||
            !ERC165Checker.supportsInterface(
                configurator_,
                type(IYieldRepurchaseFacilityV2Config).interfaceId
            ) ||
            IYieldRepurchaseFacilityV2Config(configurator_).facility() != address(this)
        )
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_InvalidConfigurator(
                configurator_
            );
    }

    /// @notice Validates a backing oracle before the facility stores it.
    /// @dev The registry activation is checked only when `requireActive_` is set: the
    ///      constructor of the facility runs this validation before the deployment is
    ///      activated in the Kernel, the admin setter after.
    ///
    ///      Reverts if:
    ///      - `backingOracle_` is the zero address (`Errors.BadInput`).
    ///      - `requireActive_` is set and the oracle is not an active policy of `kernel_`
    ///        (`IYieldRepurchaseFacilityV2_InvalidBackingOracle`).
    ///      - The oracle does not report `kernel_` as its own
    ///        (`IYieldRepurchaseFacilityV2_InvalidBackingOracle`). An oracle wired to a
    ///        different Kernel, or an address without a Kernel (for example a token whose
    ///        `decimals()` also reports 18), is rejected here.
    ///      - The oracle does not report the 18 decimals of the backing value
    ///        (`IYieldRepurchaseFacilityV2_UnsupportedOracleDecimals`). The backing value
    ///        is compared against the 18-decimal oracle prices and scaled by the 18-decimal
    ///        convention in the burn pricing.
    /// @param kernel_ The Kernel of the facility.
    /// @param backingOracle_ The backing oracle policy to validate.
    /// @param requireActive_ Whether the oracle must be an active policy of `kernel_`.
    function validateBackingOracle(
        Kernel kernel_,
        address backingOracle_,
        bool requireActive_
    ) external view {
        if (backingOracle_ == address(0)) revert Errors.BadInput("backingOracle");

        if (requireActive_ && !kernel_.isPolicyActive(Policy(backingOracle_)))
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_InvalidBackingOracle(
                backingOracle_
            );

        if (address(Policy(backingOracle_).kernel()) != address(kernel_))
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_InvalidBackingOracle(
                backingOracle_
            );

        if (
            IBackingOracle(backingOracle_).decimals() !=
            YieldRepurchaseFacilityV2Constants.BACKING_DECIMALS
        ) revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_UnsupportedOracleDecimals();
    }

    /// @notice Resolves the teller of a bond auctioneer before the facility stores the pair.
    /// @dev The teller is resolved through `getTeller()` of the supplied auctioneer, so the
    ///      pair is consistent by construction.
    ///
    ///      Reverts if:
    ///      - `bondAuctioneer_` is the zero address, or it reports the zero address as
    ///        its teller (`Errors.BadInput`).
    ///      - `requireCallbackAuthorized_` is set and the calling facility is not
    ///        authorized as a market callback on the auctioneer
    ///        (`IYieldRepurchaseFacilityV2_CallbackNotAuthorized`).
    /// @param bondAuctioneer_ The SDA auctioneer.
    /// @param requireCallbackAuthorized_ Whether the callback authorization is checked.
    /// @return bondTeller The teller the auctioneer reports.
    function resolveBondContracts(
        address bondAuctioneer_,
        bool requireCallbackAuthorized_
    ) external view returns (address bondTeller) {
        if (bondAuctioneer_ == address(0)) revert Errors.BadInput("bondAuctioneer");
        bondTeller = address(IBondAuctioneer(bondAuctioneer_).getTeller());
        if (bondTeller == address(0)) revert Errors.BadInput("bondTeller");

        if (requireCallbackAuthorized_) requireCallbackAuthorized(bondAuctioneer_);
    }

    /// @notice Reverts unless the calling facility is authorized as a market callback on
    ///         the bond auctioneer.
    /// @param bondAuctioneer_ The SDA auctioneer.
    function requireCallbackAuthorized(address bondAuctioneer_) public view {
        if (!IBondAuctioneer(bondAuctioneer_).callbackAuthorized(address(this)))
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_CallbackNotAuthorized();
    }

    /// @notice Returns the address of an installed module.
    /// @dev Reverts with `Policy_ModuleDoesNotExist` when the Kernel reports no module for
    ///      the keycode.
    function _moduleAddress(Kernel kernel_, Keycode keycode_) private view returns (address) {
        address moduleForKeycode = address(kernel_.getModuleForKeycode(keycode_));
        if (moduleForKeycode == address(0)) revert Policy.Policy_ModuleDoesNotExist(keycode_);
        return moduleForKeycode;
    }
}
