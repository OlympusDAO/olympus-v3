// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IBondAuctioneer} from "src/interfaces/IBondAuctioneer.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2Config} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Config.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {YieldRepurchaseFacilityV2BackingOracleLib} from "src/policies/YieldRepurchaseFacility/libraries/internal/YieldRepurchaseFacilityV2BackingOracleLib.sol";
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/libraries/internal/YieldRepurchaseFacilityV2Constants.sol";

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
///         configurator, the backing oracle, and the bond contracts. It also reads the
///         backing value of the backing oracle and the prices of the PRICE module for the
///         facility.
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

    /// @notice One whole unit of a price of the PRICE module, whose prices carry the 18
    ///         decimals `configureDependencies` requires.
    uint256 private constant _PRICE_UNIT = 1e18;

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
    ///      - Any of the TRSRY, CHREG, or ROLES modules does not report major version 1, or
    ///        the PRICE module reports a major version other than 1 and 2
    ///        (`Policy_WrongModuleVersion` with `abi.encode([1, 2, 1, 1])`).
    ///      - The PRICE module reports major version 1 with a minor version below 2
    ///        (`Policy_WrongModuleVersion` with `abi.encode([1, 2])`): the facility prices
    ///        the assets through `PRICE.getPrice(asset, variant)` and `PRICE.getPriceIn`,
    ///        which the PRICE module provides from version 1.2.
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
        if (
            trsryMajor != 1 ||
            (priceMajor != 1 && priceMajor != 2) ||
            chregMajor != 1 ||
            rolesMajor != 1
        ) revert Policy.Policy_WrongModuleVersion(abi.encode([1, 2, 1, 1]));

        // `getPrice(asset, variant)` and `getPriceIn` are provided by the PRICE module from
        // version 1.2.
        if (priceMajor == 1 && priceMinor < 2)
            revert Policy.Policy_WrongModuleVersion(abi.encode([1, 2]));

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
    /// @dev Reverts if:
    ///      - `configurator_` is the zero address
    ///        (`IYieldRepurchaseFacilityV2_InvalidConfigurator`).
    ///      - The `kernel()` read of `configurator_` fails or returns a malformed word
    ///        (`PolicyDependency_InvalidDependency`).
    ///      - `configurator_` reports a kernel other than `kernel_`
    ///        (`PolicyDependency_KernelMismatch`).
    ///      - `configurator_` is not an active policy of `kernel_`
    ///        (`PolicyDependency_NotActive`).
    ///      - `configurator_` does not advertise `IYieldRepurchaseFacilityV2Config` through
    ///        ERC165, which includes a `supportsInterface` query that reverts
    ///        (`IYieldRepurchaseFacilityV2_InvalidConfigurator`).
    ///      - `facility()` does not return the calling facility
    ///        (`IYieldRepurchaseFacilityV2_InvalidConfigurator`).
    ///
    ///      A configurator that does not implement `facility()` reverts in the call itself.
    /// @param kernel_ The Kernel of the facility.
    /// @param configurator_ The configuration policy to validate.
    function validateConfigurator(Kernel kernel_, address configurator_) public view {
        if (configurator_ == address(0))
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_InvalidConfigurator(
                configurator_
            );
        PolicyDependency.requireActive(configurator_, address(kernel_));
        if (
            !ERC165Checker.supportsInterface(
                configurator_,
                type(IYieldRepurchaseFacilityV2Config).interfaceId
            ) || IYieldRepurchaseFacilityV2Config(configurator_).facility() != address(this)
        )
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_InvalidConfigurator(
                configurator_
            );
    }

    /// @notice Validates the policy dependencies of the facility before it is enabled or
    ///         re-enabled: the configurator binding, and the compatibility and the readiness
    ///         of the backing oracle.
    /// @dev The configurator is validated first, with the conditions of
    ///      `validateConfigurator`. The backing oracle is then checked for the interfaces
    ///      and the Kernel binding `validateBackingOracle` requires, and for its readiness;
    ///      its `decimals()` are not read again.
    ///
    ///      Reverts if:
    ///      - `validateConfigurator` reverts for `configurator_`.
    ///      - `backingOracle_` does not advertise `IBackingOracle` and `IEnabler` through
    ///        ERC165 (`IYieldRepurchaseFacilityV2_InvalidBackingOracle`).
    ///      - The `kernel()` or the `isEnabled()` read of the oracle fails or returns a
    ///        malformed word (`PolicyDependency_InvalidDependency`).
    ///      - The oracle reports a kernel other than `kernel_`
    ///        (`PolicyDependency_KernelMismatch`).
    ///      - The oracle is not an active policy of `kernel_`, or is disabled
    ///        (`PolicyDependency_NotActive`).
    /// @param kernel_ The Kernel of the facility.
    /// @param configurator_ The configuration policy of the facility.
    /// @param backingOracle_ The backing oracle policy of the facility.
    function validateActivation(
        Kernel kernel_,
        address configurator_,
        address backingOracle_
    ) external view {
        validateConfigurator(kernel_, configurator_);

        _requireBackingOracleInterfaces(backingOracle_);
        PolicyDependency.requireActiveAndEnabled(backingOracle_, address(kernel_));
    }

    /// @notice Validates a backing oracle before the facility stores it.
    /// @dev The compatibility of the candidate is checked before its Kernel membership. The
    ///      registry activation is checked only when `requireActive_` is set: the
    ///      constructor of the facility runs this validation before the deployment is
    ///      activated in the Kernel, the admin setter after. The enabled state of the oracle
    ///      is not read.
    ///
    ///      Reverts if:
    ///      - `backingOracle_` is the zero address
    ///        (`IYieldRepurchaseFacilityV2_InvalidBackingOracle`).
    ///      - `backingOracle_` does not advertise `IBackingOracle` and `IEnabler` through
    ///        ERC165 (`IYieldRepurchaseFacilityV2_InvalidBackingOracle`), see
    ///        `_requireBackingOracleInterfaces`.
    ///      - The `kernel()` read of the oracle fails or returns a malformed word
    ///        (`PolicyDependency_InvalidDependency`).
    ///      - The oracle reports a kernel other than `kernel_`
    ///        (`PolicyDependency_KernelMismatch`).
    ///      - `requireActive_` is set and the oracle is not an active policy of `kernel_`
    ///        (`PolicyDependency_NotActive`).
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
        if (backingOracle_ == address(0))
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_InvalidBackingOracle(
                backingOracle_
            );
        _requireBackingOracleInterfaces(backingOracle_);

        if (requireActive_) PolicyDependency.requireActive(backingOracle_, address(kernel_));
        else PolicyDependency.requireSameKernel(backingOracle_, address(kernel_));

        if (
            IBackingOracle(backingOracle_).decimals() !=
            YieldRepurchaseFacilityV2Constants.BACKING_DECIMALS
        ) revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_UnsupportedOracleDecimals();
    }

    /// @notice Returns the backing value of the backing oracle, in 18 decimals, or zero
    ///         while the oracle is not an active policy of `kernel_` or is disabled.
    /// @dev The read is `YieldRepurchaseFacilityV2BackingOracleLib.readBacking`, compiled
    ///      into this library for the facility and into the lens.
    ///
    ///      Reverts if:
    ///      - The `kernel()` or the `isEnabled()` read of the oracle fails or returns a
    ///        malformed word (`PolicyDependency_InvalidDependency`).
    ///      - The oracle reports a kernel other than `kernel_`
    ///        (`PolicyDependency_KernelMismatch`).
    ///      - The `backing()` read of an active and enabled oracle reverts.
    /// @param kernel_ The Kernel of the facility.
    /// @param backingOracle_ The backing oracle policy of the facility.
    /// @return The backing value, in 18 decimals, or zero.
    function readBacking(Kernel kernel_, address backingOracle_) external view returns (uint256) {
        return
            YieldRepurchaseFacilityV2BackingOracleLib.readBacking(address(kernel_), backingOracle_);
    }

    /// @notice Returns the OHM price a daily beat of the facility prices with, in 18
    ///         decimals: the last observation the PRICE module stored for OHM when that
    ///         observation carries the timestamp of the current block and a non-zero price,
    ///         and the current OHM price of the module otherwise.
    /// @dev `OlympusHeart.beat` stores the observations (`PRICE.updateMovingAverage`) before
    ///      it runs the periodic tasks: while the module stores observations for OHM, a beat
    ///      made through it reads the observation of its block here, and the module does not
    ///      resolve the OHM feeds again.
    ///
    ///      The module stores an observation as the price it resolves from the feeds of the
    ///      asset without the moving average. While the module does not include the moving
    ///      average in the current OHM price (`useMovingAverage` unset), the observation is
    ///      the current price as resolved when the observation was stored; with
    ///      `useMovingAverage` set, the current price includes the moving average and the
    ///      observation does not.
    ///
    ///      A revert of the observation read is not propagated, and the `catch` clause copies
    ///      no return data: the current price is read instead, as it is for an observation
    ///      of another block and for a zero observation. The module reverts that read with
    ///      `PRICE_MovingAverageNotStored` while it stores no observations for OHM. A
    ///      response that does not decode as a price and a 48-bit timestamp reverts.
    ///
    ///      Reverts if the current OHM price is read and that read reverts: OHM is not an
    ///      approved asset of the module, or the module cannot resolve its price.
    /// @param price_ The PRICE module.
    /// @param ohm_ The OHM token.
    /// @return The OHM price, in 18 decimals (units of account per OHM).
    function readOhmPrice(address price_, address ohm_) external view returns (uint256) {
        try PRICEv2(price_).getPrice(ohm_, IPRICEv2.Variant.LAST) returns (
            uint256 lastPrice,
            uint48 observedAt
        ) {
            // The equality selects the observation stored in the current block
            // forge-lint: disable-next-line(block-timestamp)
            if (observedAt == block.timestamp && lastPrice != 0) return lastPrice;
        } catch {}

        // The second value is the timestamp of the read, the block timestamp
        // forge-lint: disable-next-line(unused-return)
        (uint256 currentPrice, ) = PRICEv2(price_).getPrice(ohm_, IPRICEv2.Variant.CURRENT);
        return currentPrice;
    }

    /// @notice Returns an OHM price denominated in a reserve token, in 18 decimals, at the
    ///         current price of the reserve token in the PRICE module.
    /// @dev The module resolves the current price from the feeds configured for the
    ///      reserve, under their freshness thresholds.
    ///
    ///      ohmPrice_ (18 decimals, units of account per OHM) * 1e18 / reservePrice
    ///      (18 decimals, units of account per reserve token) -> 18 decimals, reserve tokens
    ///      per OHM, rounded down. It is the full-precision division `PRICE.getPriceIn`
    ///      performs on the current prices of the two assets, so with the current OHM price
    ///      as `ohmPrice_` the result is the value of `PRICE.getPriceIn(ohm, reserve_)`.
    ///
    ///      Reverts if:
    ///      - The current price read of `reserve_` reverts: the reserve is not an approved
    ///        asset of the module, or the module cannot resolve its price.
    ///      - The division fails (a revert without data): the reserve price is zero, or the
    ///        quotient does not fit in 256 bits.
    /// @param price_ The PRICE module.
    /// @param ohmPrice_ The OHM price, in 18 decimals (units of account per OHM).
    /// @param reserve_ The reserve token.
    /// @return The OHM price, in 18 decimals (reserve tokens per OHM).
    function readPriceIn(
        address price_,
        uint256 ohmPrice_,
        address reserve_
    ) external view returns (uint256) {
        // The second value is the timestamp of the read, the block timestamp
        // forge-lint: disable-next-line(unused-return)
        (uint256 reservePrice, ) = PRICEv2(price_).getPrice(reserve_, IPRICEv2.Variant.CURRENT);
        return FullMath.mulDiv(ohmPrice_, _PRICE_UNIT, reservePrice);
    }

    /// @notice Resolves the teller of a bond auctioneer before the facility stores the pair.
    /// @dev The teller is resolved through `getTeller()` of the supplied auctioneer, so the
    ///      pair is consistent by construction.
    ///
    ///      Reverts if:
    ///      - `bondAuctioneer_` is the zero address, or it reports the zero address as
    ///        its teller (`IYieldRepurchaseFacilityV2_InvalidBondAuctioneer`).
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
        if (bondAuctioneer_ == address(0))
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_InvalidBondAuctioneer(
                bondAuctioneer_
            );
        bondTeller = address(IBondAuctioneer(bondAuctioneer_).getTeller());
        if (bondTeller == address(0))
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_InvalidBondAuctioneer(
                bondAuctioneer_
            );

        if (requireCallbackAuthorized_) requireCallbackAuthorized(bondAuctioneer_);
    }

    /// @notice Reverts unless the calling facility is authorized as a market callback on
    ///         the bond auctioneer.
    /// @param bondAuctioneer_ The SDA auctioneer.
    function requireCallbackAuthorized(address bondAuctioneer_) public view {
        if (!IBondAuctioneer(bondAuctioneer_).callbackAuthorized(address(this)))
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_CallbackNotAuthorized();
    }

    /// @notice Reverts with `IYieldRepurchaseFacilityV2_InvalidBackingOracle` unless
    ///         `backingOracle_` advertises `IBackingOracle` and `IEnabler` through ERC165.
    /// @dev The queries run through `ERC165Checker`, which reads a failed query as an
    ///      unsupported interface: an address without code, a `supportsInterface` call that
    ///      reverts, and a response shorter than one word are rejected with the same error.
    function _requireBackingOracleInterfaces(address backingOracle_) private view {
        if (
            !ERC165Checker.supportsInterface(backingOracle_, type(IBackingOracle).interfaceId) ||
            !ERC165Checker.supportsInterface(backingOracle_, type(IEnabler).interfaceId)
        )
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_InvalidBackingOracle(
                backingOracle_
            );
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
