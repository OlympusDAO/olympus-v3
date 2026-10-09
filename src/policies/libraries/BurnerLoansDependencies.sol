// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {EnumerableSet} from "@openzeppelin-5.7.0/utils/structs/EnumerableSet.sol";
import {SafeCallDecoder} from "src/libraries/SafeCallDecoder.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

/// @title Burner Loans Dependency Validation
/// @notice Validates module interfaces and versions when the policy is activated.
library BurnerLoansDependencies {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeCallDecoder for address;

    /// @dev FLOAN module keycode.
    // Each literal is exactly five bytes, so wrapping cannot truncate data.
    // forge-lint: disable-next-line(unsafe-typecast)
    Keycode internal constant _FLOAN_KEYCODE = Keycode.wrap(bytes5("FLOAN"));
    /// @dev PRICE module keycode.
    // forge-lint: disable-next-line(unsafe-typecast)
    Keycode internal constant _PRICE_KEYCODE = Keycode.wrap(bytes5("PRICE"));
    /// @dev ROLES module keycode.
    // forge-lint: disable-next-line(unsafe-typecast)
    Keycode internal constant _ROLES_KEYCODE = Keycode.wrap(bytes5("ROLES"));
    /// @dev TRSRY module keycode.
    // forge-lint: disable-next-line(unsafe-typecast)
    Keycode internal constant _TRSRY_KEYCODE = Keycode.wrap(bytes5("TRSRY"));
    // The selector is the leading four bytes of the signature hash by ABI definition.
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes4 internal constant _KERNEL_SELECTOR = bytes4(keccak256("kernel()"));

    /// @notice Validates the distributor binding before a revenue route is configured.
    /// @dev Reverts if:
    ///      - The address lacks the distributor or enabler interface.
    ///      - The distributor's Kernel or enabled-state getter cannot be read canonically.
    ///      - The distributor belongs to another Kernel, is inactive, or is locally disabled.
    function validateRevenueDistributor(Kernel kernel_, address distributor_) public view {
        bytes4[] memory interfaceIds = new bytes4[](2);
        interfaceIds[0] = type(IRevenueDistributor).interfaceId;
        interfaceIds[1] = type(IEnabler).interfaceId;
        if (!ERC165Checker.supportsAllInterfaces(distributor_, interfaceIds)) {
            revert IBurnerLoans.BurnerLoans_InvalidRevenueDistributor(distributor_);
        }
        (bool kernelRead, address reportedKernel) = distributor_.safeReadAddress(_KERNEL_SELECTOR);
        if (!kernelRead || reportedKernel != address(kernel_)) {
            revert IBurnerLoans.BurnerLoans_InvalidRevenueDistributor(distributor_);
        }
        if (!kernel_.isPolicyActive(Policy(distributor_))) {
            revert IBurnerLoans.BurnerLoans_InvalidRevenueDistributor(distributor_);
        }
        (bool enabledRead, bool enabled) = distributor_.safeReadBool(IEnabler.isEnabled.selector);
        if (!enabledRead || !enabled) {
            revert IBurnerLoans.BurnerLoans_InvalidRevenueDistributor(distributor_);
        }
    }

    /// @notice Validates that an address implements the backing-oracle interface.
    /// @dev Reverts if:
    ///      - The address is zero, has no code, or lacks the backing-oracle interface.
    function validateBackingOracle(address backingOracle_) public view {
        if (backingOracle_ == address(0)) revert IBurnerLoans.BurnerLoans_ZeroAddress();
        if (
            backingOracle_.code.length == 0 ||
            !IERC165(backingOracle_).supportsInterface(type(IOlympusBackingOracle).interfaceId)
        ) {
            revert IBurnerLoans.BurnerLoans_InvalidBackingOracle(backingOracle_);
        }
    }

    /// @notice Validates an optional PriceCache dependency.
    /// @dev Zero selects direct PRICE mode. A configured cache is validated without requiring it
    ///      to be active or enabled so governance can stage and repair the dependency separately.
    ///      Reverts if:
    ///      - A nonzero cache lacks a required interface or supported major version.
    ///      - The cache belongs to another Kernel.
    function validatePriceCache(Kernel kernel_, address priceCache_) public view {
        if (priceCache_ == address(0)) return;

        bytes4[] memory interfaceIds = new bytes4[](3);
        interfaceIds[0] = type(IPriceCache).interfaceId;
        interfaceIds[1] = type(IEnabler).interfaceId;
        interfaceIds[2] = type(IVersioned).interfaceId;
        if (!ERC165Checker.supportsAllInterfaces(priceCache_, interfaceIds)) {
            revert IBurnerLoans.BurnerLoans_InvalidPriceCache(priceCache_);
        }

        (uint8 major, uint8 minor) = IVersioned(priceCache_).VERSION();
        if (major != 1) {
            revert IBurnerLoans.BurnerLoans_UnsupportedPriceCacheVersion(priceCache_, major, minor);
        }

        address priceCacheKernel = address(Policy(priceCache_).kernel());
        if (priceCacheKernel != address(kernel_)) {
            revert IBurnerLoans.BurnerLoans_DependencyKernelMismatch(
                priceCache_,
                address(kernel_),
                priceCacheKernel
            );
        }
    }

    /// @notice Validates a PriceCache and requires a configured cache to be an active policy.
    /// @dev Zero remains valid and selects direct PRICE mode. Enabled state is intentionally not
    ///      required because an active disabled cache falls back to PRICE at runtime.
    ///      Reverts if:
    ///      - A nonzero cache fails compatibility validation or is Kernel-inactive.
    function validateActivePriceCache(Kernel kernel_, address priceCache_) public view {
        validatePriceCache(kernel_, priceCache_);
        if (priceCache_ != address(0) && !kernel_.isPolicyActive(Policy(priceCache_))) {
            revert IBurnerLoans.BurnerLoans_DependencyNotActive(priceCache_);
        }
    }

    /// @notice Adds an asset to the append-only registry.
    /// @dev Reverts if:
    ///      - The asset is already registered.
    function registerAsset(EnumerableSet.AddressSet storage assets_, address asset_) public {
        if (!assets_.add(asset_)) revert IBurnerLoans.BurnerLoans_AssetAlreadyConfigured(asset_);
        emit IBurnerLoans.AssetRegistered(asset_);
    }

    /// @notice Validates an active Burner Loans Inventory link before it is stored.
    /// @dev Reverts if:
    ///      - Inventory is zero, inactive, or bound to a different facility, OHM, or Kernel.
    function validateInventoryLink(
        Kernel kernel_,
        address facility_,
        address ohm_,
        address inventory_
    ) public view {
        if (inventory_ == address(0)) revert IBurnerLoans.BurnerLoans_InvalidInventory(inventory_);
        _requireInventoryActive(kernel_, inventory_);
        _validateInventoryCompatibility(facility_, ohm_, inventory_);
    }

    /// @notice Validates an active Burner Loans Config link before it is stored.
    /// @dev Reverts if:
    ///      - Config is inactive, incompatible, or bound to a different facility, OHM, or Kernel.
    function validateConfiguratorLink(
        Kernel kernel_,
        address facility_,
        address ohm_,
        address configurator_
    ) public view {
        _requireConfiguratorActive(kernel_, configurator_);
        _validateConfigurator(facility_, ohm_, configurator_);
    }

    /// @notice Transfers every matching registered facility market from one Config manager to another.
    /// @dev Each asset must resolve to at least one market and every matching market must still name
    ///      `outgoingConfigurator_` as manager. A later failure reverts every earlier rotation.
    ///      Reverts if:
    ///      - A registered asset has no matching market or a market has another manager.
    ///      - FLOAN rejects a manager update.
    function migrateMarketManagers(
        EnumerableSet.AddressSet storage assets_,
        IFLOANv1 floan_,
        address facility_,
        address debtToken_,
        address outgoingConfigurator_,
        address replacementConfigurator_
    ) public {
        uint256 assetCount = assets_.length();
        // Migration is intentionally atomic over the governance-controlled append-only registry.
        // forge-lint: disable-start(calls-loop,require-revert-in-loop)
        for (uint256 i; i < assetCount; ++i) {
            address asset = assets_.at(i);
            uint256[] memory marketIds = floan_.getMarketIds(facility_, asset, debtToken_);
            if (marketIds.length == 0) {
                revert IBurnerLoans.BurnerLoans_AssetNotConfigured(asset);
            }

            for (uint256 j; j < marketIds.length; ++j) {
                // FLOAN indexes only uint32-typed market IDs in this uint256-backed set.
                // forge-lint: disable-next-line(unsafe-typecast)
                uint32 marketId = uint32(marketIds[j]);
                address manager = floan_.getMarket(marketId).manager;
                if (manager != outgoingConfigurator_) {
                    revert IBurnerLoans.BurnerLoans_MarketManagerMismatch(
                        marketId,
                        outgoingConfigurator_,
                        manager
                    );
                }
                floan_.setMarketManager(marketId, replacementConfigurator_);
            }
        }
        // forge-lint: disable-end(calls-loop,require-revert-in-loop)
    }

    /// @notice Validates every linked Burner Loans policy before operational enablement.
    /// @dev Reverts if:
    ///      - DepositManager, Inventory, or Config is inactive or incompatible.
    ///      - Inventory is disabled or its Config binding is inconsistent.
    function validateConfiguration(
        Kernel kernel_,
        address facility_,
        address ohm_,
        address depositManager_,
        address inventory_,
        address configurator_
    ) public view {
        if (!kernel_.isPolicyActive(Policy(depositManager_))) {
            revert IBurnerLoans.BurnerLoans_InvalidDepositManager(depositManager_);
        }

        if (inventory_ == address(0)) revert IBurnerLoans.BurnerLoans_InvalidInventory(inventory_);
        _requireInventoryActive(kernel_, inventory_);
        _validateInventoryCompatibility(facility_, ohm_, inventory_);
        if (!IEnabler(inventory_).isEnabled()) {
            revert IBurnerLoans.BurnerLoans_InventoryNotEnabled(inventory_);
        }

        _requireConfiguratorActive(kernel_, configurator_);
        _validateConfigurator(facility_, ohm_, configurator_);
        if (IBurnerLoansInventory(inventory_).configurator() != configurator_) {
            revert IBurnerLoansConfig.BurnerLoansConfig_InvalidInventory(inventory_);
        }
    }

    /// @notice Returns the modules required by the lifecycle policy in dependency-slot order.
    function keycodes() public pure returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = _FLOAN_KEYCODE;
        dependencies[1] = _PRICE_KEYCODE;
        dependencies[2] = _ROLES_KEYCODE;
        dependencies[3] = _TRSRY_KEYCODE;
    }

    /// @notice Returns the FLOAN permissions required by the lifecycle policy.
    function permissions() public pure returns (Permissions[] memory requests) {
        requests = new Permissions[](8);
        requests[0] = Permissions({
            keycode: _FLOAN_KEYCODE,
            funcSelector: IFLOANv1.addCollateral.selector
        });
        requests[1] = Permissions({
            keycode: _FLOAN_KEYCODE,
            funcSelector: IFLOANv1.removeCollateral.selector
        });
        requests[2] = Permissions({
            keycode: _FLOAN_KEYCODE,
            funcSelector: IFLOANv1.increaseDebt.selector
        });
        requests[3] = Permissions({
            keycode: _FLOAN_KEYCODE,
            funcSelector: IFLOANv1.createPosition.selector
        });
        requests[4] = Permissions({
            keycode: _FLOAN_KEYCODE,
            funcSelector: IFLOANv1.decreaseDebt.selector
        });
        requests[5] = Permissions({
            keycode: _FLOAN_KEYCODE,
            funcSelector: IFLOANv1.extendMaturity.selector
        });
        requests[6] = Permissions({
            keycode: _FLOAN_KEYCODE,
            funcSelector: IFLOANv1.defaultPosition.selector
        });
        requests[7] = Permissions({
            keycode: _FLOAN_KEYCODE,
            funcSelector: IFLOANv1.setMarketManager.selector
        });
    }

    /// @notice Validates dependency interfaces and supported major versions during activation.
    /// @dev PRICE supports v1.2 or any v2 release; every other dependency requires major v1.
    ///      Reverts if:
    ///      - PRICE lacks its required interface or any module has an unsupported version.
    function validate(
        IFLOANv1 floan_,
        address priceAddress_,
        ROLESv1 roles_,
        TRSRYv1 trsry_
    ) public view returns (IPRICEv2 price) {
        if (!IERC165(priceAddress_).supportsInterface(type(IPRICEv2).interfaceId)) {
            revert IBurnerLoans.BurnerLoans_InvalidModuleVersion();
        }

        // FLOAN compatibility depends only on its major version.
        // forge-lint: disable-next-line(unused-return)
        (uint8 floanMajor, ) = Module(address(floan_)).VERSION();
        (uint8 priceMajor, uint8 priceMinor) = Module(priceAddress_).VERSION();
        // ROLES compatibility depends only on its major version.
        // forge-lint: disable-next-line(unused-return)
        (uint8 rolesMajor, ) = roles_.VERSION();
        // TRSRY compatibility depends only on its major version.
        // forge-lint: disable-next-line(unused-return)
        (uint8 trsryMajor, ) = trsry_.VERSION();

        if (
            floanMajor != 1 ||
            (priceMajor != 2 && (priceMajor != 1 || priceMinor < 2)) ||
            rolesMajor != 1 ||
            trsryMajor != 1
        ) revert IBurnerLoans.BurnerLoans_InvalidModuleVersion();

        return IPRICEv2(priceAddress_);
    }

    /// @notice Validates the Inventory interface and immutable OHM/facility bindings.
    /// @dev Reverts if:
    ///      - Inventory lacks the required interface or reports another OHM token or facility.
    function _validateInventoryCompatibility(
        address facility_,
        address ohm_,
        address inventory_
    ) private view {
        if (!ERC165Checker.supportsInterface(inventory_, type(IBurnerLoansInventory).interfaceId)) {
            revert IBurnerLoans.BurnerLoans_InvalidInventory(inventory_);
        }

        IBurnerLoansInventory inventory = IBurnerLoansInventory(inventory_);
        address inventoryOhm = inventory.ohm();
        if (inventoryOhm != ohm_) {
            revert IBurnerLoans.BurnerLoans_InventoryOhmMismatch(ohm_, inventoryOhm);
        }

        address inventoryFacility = inventory.facility();
        if (inventoryFacility != facility_) {
            revert IBurnerLoans.BurnerLoans_InventoryFacilityMismatch(facility_, inventoryFacility);
        }
    }

    /// @notice Validates the Config interface and immutable OHM/facility bindings.
    /// @dev Reverts if:
    ///      - Config is zero, lacks its interface, or reports another OHM token or facility.
    function _validateConfigurator(
        address facility_,
        address ohm_,
        address configurator_
    ) private view {
        if (
            configurator_ == address(0) ||
            !ERC165Checker.supportsInterface(configurator_, type(IBurnerLoansConfig).interfaceId) ||
            IBurnerLoansConfig(configurator_).facility() != facility_ ||
            IBurnerLoansConfig(configurator_).ohm() != ohm_
        ) revert IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility(configurator_);
    }

    /// @notice Requires Inventory to be an active, same-Kernel policy.
    /// @dev Reverts if:
    ///      - Inventory is Kernel-inactive or reports another Kernel.
    function _requireInventoryActive(Kernel kernel_, address inventory_) private view {
        if (!kernel_.isPolicyActive(Policy(inventory_))) {
            revert IBurnerLoans.BurnerLoans_DependencyNotActive(inventory_);
        }
        if (!_reportsKernel(inventory_, kernel_)) {
            revert IBurnerLoans.BurnerLoans_InvalidInventory(inventory_);
        }
    }

    /// @notice Requires Config to be an active, same-Kernel policy.
    /// @dev Reverts if:
    ///      - Config is Kernel-inactive or reports another Kernel.
    function _requireConfiguratorActive(Kernel kernel_, address configurator_) private view {
        if (
            !kernel_.isPolicyActive(Policy(configurator_)) ||
            !_reportsKernel(configurator_, kernel_)
        ) {
            revert IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility(configurator_);
        }
    }

    /// @notice Returns whether a policy reports the expected Kernel.
    /// @dev Returns false if the policy getter reverts.
    function _reportsKernel(address policy_, Kernel kernel_) private view returns (bool) {
        try Policy(policy_).kernel() returns (Kernel reportedKernel) {
            return address(reportedKernel) == address(kernel_);
        } catch {
            return false;
        }
    }
}
