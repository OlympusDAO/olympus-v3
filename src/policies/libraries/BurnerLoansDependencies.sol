// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";
import {IYieldRecipient} from "src/policies/interfaces/IYieldRecipient.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

/// @title Burner Loans Dependency Validation
/// @notice Validates module interfaces and versions when the policy is activated.
library BurnerLoansDependencies {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Burner Loans-owned yield-routing storage passed to linked-library operations.
    /// @param recipient Facility-wide recipient of configured collateral-yield shares.
    /// @param assetBps Per-collateral-asset recipient share in basis points.
    /// @param activeAssetCount Number of assets with a nonzero recipient share.
    struct YieldRoutingState {
        address recipient;
        mapping(address asset => uint16 bps) assetBps;
        uint256 activeAssetCount;
    }

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

    /// @notice Validates that an address implements the backing-oracle interface.
    /// @dev Reverts for a zero address, an EOA, or a contract that reports no interface support.
    function validateBackingOracle(address backingOracle_) public view {
        if (backingOracle_ == address(0)) revert IBurnerLoans.BurnerLoans_ZeroAddress();
        if (
            backingOracle_.code.length == 0 ||
            !IERC165(backingOracle_).supportsInterface(type(IOlympusBackingOracle).interfaceId)
        ) {
            revert IBurnerLoans.BurnerLoans_InvalidBackingOracle(backingOracle_);
        }
    }

    /// @notice Validates a yield recipient against the facility Kernel and enablement state.
    /// @dev Recipient identity is anchored exclusively to the supplied Kernel's active-policy
    ///      registry. Kernel-executor activation is authoritative even if the recipient reports a
    ///      different Kernel; a recipient-reported getter is not part of this trust decision.
    function validateYieldRecipient(Kernel kernel_, address recipient_) public view {
        if (
            recipient_ == address(0) ||
            !ERC165Checker.supportsInterface(recipient_, type(IYieldRecipient).interfaceId) ||
            !ERC165Checker.supportsInterface(recipient_, type(IEnabler).interfaceId)
        ) revert IBurnerLoans.BurnerLoans_InvalidYieldRecipient(recipient_);
        if (!kernel_.isPolicyActive(Policy(recipient_))) {
            revert IBurnerLoans.BurnerLoans_YieldRecipientNotActivePolicy(recipient_);
        }
        if (!IEnabler(recipient_).isEnabled()) {
            revert IBurnerLoans.BurnerLoans_YieldRecipientNotEnabled(recipient_);
        }
    }

    /// @notice Validates one exact DepositManager asset-vault pair for a yield recipient.
    /// @dev Revalidates the global policy/interface/enablement checks before reading the asset route
    ///      so a recipient that became invalid after configuration cannot receive yield. The
    ///      recipient's `getVaultConfig` revert data bubbles unchanged.
    function validateYieldRecipientAsset(
        Kernel kernel_,
        IDepositManager depositManager_,
        address recipient_,
        address asset_
    ) public view {
        validateYieldRecipient(kernel_, recipient_);
        _validateYieldRecipientAsset(depositManager_, recipient_, asset_);
    }

    /// @notice Validates one recipient route against DepositManager's exact asset-vault pair.
    function _validateYieldRecipientAsset(
        IDepositManager depositManager_,
        address recipient_,
        address asset_
    ) private view {
        address vault = depositManager_.getAssetConfiguration(IERC20(asset_)).vault;
        IYieldRecipient.VaultConfig memory config = IYieldRecipient(recipient_).getVaultConfig(
            vault
        );

        if (config.vault != vault) {
            revert IBurnerLoans.BurnerLoans_YieldRecipientAssetVaultMismatch(vault, config.vault);
        }
        if (config.asset != asset_) {
            revert IBurnerLoans.BurnerLoans_YieldRecipientAssetMismatch(asset_, config.asset);
        }
        if (!config.enabled) {
            revert IBurnerLoans.BurnerLoans_YieldRecipientAssetNotEnabled(
                recipient_,
                asset_,
                vault
            );
        }
    }

    /// @notice Applies a validated facility-wide yield-recipient transition.
    function setYieldRecipient(
        YieldRoutingState storage state_,
        EnumerableSet.AddressSet storage assets_,
        Kernel kernel_,
        IDepositManager depositManager_,
        address recipient_
    ) public {
        if (recipient_ == address(0)) {
            // Clearing the recipient first would strand nonzero per-asset allocations.
            if (state_.activeAssetCount != 0) {
                revert IBurnerLoans.BurnerLoans_YieldAllocationsActive(state_.activeAssetCount);
            }
            if (state_.recipient == address(0)) return;
        } else {
            validateYieldRecipient(kernel_, recipient_);
            // Recipient rotation preserves allocations, so every live route must be compatible
            // with the replacement before the single facility-wide pointer changes.
            uint256 assetCount = assets_.length();
            for (uint256 i; i < assetCount; ++i) {
                address asset = assets_.at(i);
                if (state_.assetBps[asset] != 0) {
                    _validateYieldRecipientAsset(depositManager_, recipient_, asset);
                }
            }
            if (state_.recipient == recipient_) return;
        }

        state_.recipient = recipient_;
        emit IBurnerLoans.YieldRecipientSet(recipient_);
    }

    /// @notice Applies a validated per-asset yield-recipient allocation transition.
    /// @dev Reverts if bps exceeds 10_000, the asset is unregistered, or no recipient is configured.
    ///      Nonzero bps also requires a currently valid recipient and live asset-vault route. Zero
    ///      bps deliberately permits cleanup after recipient drift.
    function setYieldRecipientAssetBps(
        YieldRoutingState storage state_,
        EnumerableSet.AddressSet storage assets_,
        Kernel kernel_,
        IDepositManager depositManager_,
        address asset_,
        uint16 bps_
    ) public {
        if (bps_ > 10_000) revert IBurnerLoans.BurnerLoans_InvalidBps(bps_);
        if (!assets_.contains(asset_)) {
            revert IBurnerLoans.BurnerLoans_AssetNotConfigured(asset_);
        }
        // Even a zero/no-op call must target the configured routing domain. Rejecting calls while
        // the recipient is unset keeps setter semantics uniform for every bps value.
        if (state_.recipient == address(0)) revert IBurnerLoans.BurnerLoans_ZeroAddress();
        uint16 currentBps = state_.assetBps[asset_];

        if (bps_ == 0) {
            if (currentBps == 0) return;
            delete state_.assetBps[asset_];
            --state_.activeAssetCount;
        } else {
            validateYieldRecipientAsset(kernel_, depositManager_, state_.recipient, asset_);
            if (currentBps == bps_) return;
            state_.assetBps[asset_] = bps_;
            if (currentBps == 0) ++state_.activeAssetCount;
        }

        emit IBurnerLoans.YieldRecipientAssetBpsSet(asset_, bps_);
    }

    /// @notice Validates an active Burner Loans Inventory link before it is stored.
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
    function validateConfiguratorLink(
        Kernel kernel_,
        address facility_,
        address ohm_,
        address configurator_
    ) public view {
        _requireConfiguratorActive(kernel_, configurator_);
        _validateConfigurator(facility_, ohm_, configurator_);
    }

    /// @notice Validates every linked Burner Loans policy before operational enablement.
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
        requests = new Permissions[](7);
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
    }

    /// @notice Validates dependency interfaces and supported major versions during activation.
    /// @dev PRICE supports v1.2 or any v2 release; every other dependency requires major v1.
    function validate(
        IFLOANv1 floan_,
        address priceAddress_,
        ROLESv1 roles_,
        TRSRYv1 trsry_
    ) public view returns (IPRICEv2 price) {
        if (!IERC165(priceAddress_).supportsInterface(type(IPRICEv2).interfaceId)) {
            revert IBurnerLoans.BurnerLoans_InvalidModuleVersion();
        }

        (uint8 floanMajor, ) = Module(address(floan_)).VERSION();
        (uint8 priceMajor, uint8 priceMinor) = Module(priceAddress_).VERSION();
        (uint8 rolesMajor, ) = roles_.VERSION();
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
    function _requireInventoryActive(Kernel kernel_, address inventory_) private view {
        if (!kernel_.isPolicyActive(Policy(inventory_))) {
            revert IBurnerLoans.BurnerLoans_InventoryNotActive(inventory_);
        }
        if (!_reportsKernel(inventory_, kernel_)) {
            revert IBurnerLoans.BurnerLoans_InvalidInventory(inventory_);
        }
    }

    /// @notice Requires Config to be an active, same-Kernel policy.
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
