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
import {IYieldRepurchaseRecipient} from "src/policies/interfaces/IYieldRepurchaseRecipient.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

/// @title Burner Loans Dependency Validation
/// @notice Validates module interfaces and versions when the policy is activated.
library BurnerLoansDependencies {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Burner Loans-owned yield-routing storage passed to linked-library operations.
    /// @param repurchaseRecipient Facility-wide recipient of repurchase-directed yield shares.
    /// @param assetRouting Complete declarative route for each registered collateral asset.
    struct YieldRoutingState {
        address repurchaseRecipient;
        mapping(address asset => IBurnerLoans.AssetYieldRouting routing) assetRouting;
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

    /// @notice Validates a yield repurchase recipient against reserved destinations and live state.
    /// @dev Reserved-address checks precede interface calls so self and Treasury are rejected with
    ///      the routing-specific error even when they do not implement ERC-165.
    function validateYieldRepurchaseRecipient(address treasury_, address recipient_) public view {
        if (recipient_ == address(0) || recipient_ == address(this) || recipient_ == treasury_)
            revert IBurnerLoans.BurnerLoans_InvalidYieldRepurchaseRecipient(recipient_);

        bytes4[] memory interfaceIds = new bytes4[](2);
        interfaceIds[0] = type(IYieldRepurchaseRecipient).interfaceId;
        interfaceIds[1] = type(IEnabler).interfaceId;
        if (!ERC165Checker.supportsAllInterfaces(recipient_, interfaceIds)) {
            revert IBurnerLoans.BurnerLoans_InvalidYieldRepurchaseRecipient(recipient_);
        }
        Kernel kernel_ = Policy(address(this)).kernel();
        if (!kernel_.isPolicyActive(Policy(recipient_))) {
            revert IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientNotActivePolicy(recipient_);
        }
        if (!IEnabler(recipient_).isEnabled()) {
            revert IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientNotEnabled(recipient_);
        }
    }

    /// @notice Validates one exact DepositManager asset-vault pair for a repurchase recipient.
    function validateYieldRepurchaseRecipientAsset(
        IDepositManager depositManager_,
        address treasury_,
        address recipient_,
        address asset_
    ) public view {
        validateYieldRepurchaseRecipient(treasury_, recipient_);
        _validateYieldRepurchaseRecipientAsset(depositManager_, recipient_, asset_);
    }

    /// @notice Validates one recipient route against DepositManager's exact asset-vault pair.
    function _validateYieldRepurchaseRecipientAsset(
        IDepositManager depositManager_,
        address recipient_,
        address asset_
    ) private view {
        // Facility-wide recipient validation is intentionally atomic: any incompatible asset-vault
        // route must reject the complete recipient update.
        // forge-lint: disable-start(require-revert-in-loop)
        // The governance-controlled asset registry is expected to remain small, and every
        // configured asset must be checked before a facility-wide recipient change.
        // forge-lint: disable-next-line(calls-loop)
        address vault = depositManager_.getAssetConfiguration(IERC20(asset_)).vault;
        if (vault == address(0)) {
            revert IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientVaultRequired(asset_);
        }
        // Each configured asset may map to a different vault, so recipient compatibility requires
        // one view call per vault.
        // forge-lint: disable-start(calls-loop)
        IYieldRepurchaseRecipient.VaultConfig memory config = IYieldRepurchaseRecipient(recipient_)
            .getVaultConfig(vault);
        // forge-lint: disable-end(calls-loop)

        if (config.vault != vault) {
            revert IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientAssetVaultMismatch(
                vault,
                config.vault
            );
        }
        if (config.asset != asset_) {
            revert IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientAssetMismatch(
                asset_,
                config.asset
            );
        }
        if (!config.enabled) {
            revert IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientAssetNotEnabled(
                recipient_,
                asset_,
                vault
            );
        }
        // forge-lint: disable-end(require-revert-in-loop)
    }

    /// @notice Adds an asset to the append-only registry with implicit Treasury-only routing.
    function registerAsset(EnumerableSet.AddressSet storage assets_, address asset_) public {
        if (!assets_.add(asset_)) revert IBurnerLoans.BurnerLoans_AssetAlreadyConfigured(asset_);
        emit IBurnerLoans.AssetRegistered(asset_);
    }

    /// @notice Applies a validated facility-wide yield-repurchase-recipient transition.
    function setYieldRepurchaseRecipient(
        YieldRoutingState storage state_,
        EnumerableSet.AddressSet storage assets_,
        IDepositManager depositManager_,
        address treasury_,
        address recipient_
    ) public {
        if (recipient_ == address(0)) {
            uint256 assetCount = assets_.length();
            uint256 activeAssetCount;
            for (uint256 i; i < assetCount; ++i) {
                if (state_.assetRouting[assets_.at(i)].repurchaseRecipientBps != 0) {
                    ++activeAssetCount;
                }
            }
            if (activeAssetCount != 0) {
                revert IBurnerLoans.BurnerLoans_YieldRepurchaseAllocationsActive(activeAssetCount);
            }
            if (state_.repurchaseRecipient == address(0)) return;
        } else {
            validateYieldRepurchaseRecipient(treasury_, recipient_);
            uint256 assetCount = assets_.length();
            for (uint256 i; i < assetCount; ++i) {
                address asset = assets_.at(i);
                IBurnerLoans.AssetYieldRouting storage routing = state_.assetRouting[asset];
                uint256 directCount = routing.directAllocations.length;
                for (uint256 j; j < directCount; ++j) {
                    if (routing.directAllocations[j].recipient == recipient_) {
                        // The recipient transition is intentionally atomic: a conflicting direct
                        // allocation must reject the complete facility-wide update.
                        // forge-lint: disable-next-line(require-revert-in-loop)
                        revert IBurnerLoans.BurnerLoans_InvalidDirectYieldRecipient(recipient_);
                    }
                }
                if (routing.repurchaseRecipientBps != 0) {
                    _validateYieldRepurchaseRecipientAsset(depositManager_, recipient_, asset);
                }
            }
            if (state_.repurchaseRecipient == recipient_) return;
        }

        state_.repurchaseRecipient = recipient_;
        emit IBurnerLoans.YieldRepurchaseRecipientSet(recipient_);
    }

    /// @notice Atomically replaces one registered asset's complete yield route.
    function setYieldAssetRouting(
        YieldRoutingState storage state_,
        EnumerableSet.AddressSet storage assets_,
        IDepositManager depositManager_,
        address treasury_,
        address asset_,
        IBurnerLoans.AssetYieldRouting calldata routing_
    ) public {
        validateAssetYieldRoutingInput(
            state_,
            assets_,
            depositManager_,
            treasury_,
            asset_,
            routing_
        );

        IBurnerLoans.AssetYieldRouting storage current = state_.assetRouting[asset_];
        if (_assetYieldRoutingEquals(current, routing_)) return;

        current.repurchaseRecipientBps = routing_.repurchaseRecipientBps;
        delete current.directAllocations;
        uint256 directCount = routing_.directAllocations.length;
        for (uint256 i; i < directCount; ++i) {
            current.directAllocations.push(routing_.directAllocations[i]);
        }

        emit IBurnerLoans.YieldAssetRoutingSet(asset_, routing_);
    }

    /// @notice Validates a proposed complete yield route without changing storage.
    function validateAssetYieldRoutingInput(
        YieldRoutingState storage state_,
        EnumerableSet.AddressSet storage assets_,
        IDepositManager depositManager_,
        address treasury_,
        address asset_,
        IBurnerLoans.AssetYieldRouting calldata routing_
    ) public view {
        if (!assets_.contains(asset_)) {
            revert IBurnerLoans.BurnerLoans_AssetNotConfigured(asset_);
        }
        _validateAssetYieldRoutingInput(
            state_.repurchaseRecipient,
            depositManager_,
            treasury_,
            asset_,
            routing_
        );
    }

    /// @notice Returns a complete stored route including its dynamic allocation array.
    function getYieldAssetRouting(
        YieldRoutingState storage state_,
        address asset_
    ) public view returns (IBurnerLoans.AssetYieldRouting memory routing) {
        return state_.assetRouting[asset_];
    }

    /// @notice Validates a complete stored route against current reserved destinations and state.
    function validateStoredAssetYieldRouting(
        YieldRoutingState storage state_,
        IDepositManager depositManager_,
        address treasury_,
        address asset_
    ) public view {
        IBurnerLoans.AssetYieldRouting storage routing = state_.assetRouting[asset_];
        _validateStoredDirectAllocations(routing, treasury_, state_.repurchaseRecipient);
        if (routing.repurchaseRecipientBps != 0) {
            if (state_.repurchaseRecipient == address(0)) {
                revert IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientNotConfigured();
            }
            validateYieldRepurchaseRecipientAsset(
                depositManager_,
                treasury_,
                state_.repurchaseRecipient,
                asset_
            );
        }
    }

    /// @dev Direct allocations intentionally have no explicit count cap. Nonzero BPS and the
    ///      10,000-BPS maximum impose a theoretical maximum of 10,000 entries, while storage and
    ///      claim gas grow with the configured length.
    function _validateAssetYieldRoutingInput(
        address repurchaseRecipient_,
        IDepositManager depositManager_,
        address treasury_,
        address asset_,
        IBurnerLoans.AssetYieldRouting calldata routing_
    ) private view {
        uint256 directCount = routing_.directAllocations.length;
        uint256 totalBps = routing_.repurchaseRecipientBps;
        // Route replacement is intentionally atomic: any invalid or duplicate allocation must
        // reject the complete route rather than apply a partial configuration.
        // forge-lint: disable-start(require-revert-in-loop)
        for (uint256 i; i < directCount; ++i) {
            IBurnerLoans.DirectYieldAllocation calldata allocation = routing_.directAllocations[i];
            if (
                allocation.recipient == address(0) ||
                allocation.recipient == address(this) ||
                allocation.recipient == treasury_ ||
                allocation.recipient == repurchaseRecipient_
            ) {
                revert IBurnerLoans.BurnerLoans_InvalidDirectYieldRecipient(allocation.recipient);
            }
            if (allocation.bps == 0) {
                revert IBurnerLoans.BurnerLoans_InvalidDirectYieldAllocationBps(
                    allocation.recipient
                );
            }
            for (uint256 j; j < i; ++j) {
                if (routing_.directAllocations[j].recipient == allocation.recipient) {
                    revert IBurnerLoans.BurnerLoans_DuplicateDirectYieldRecipient(
                        allocation.recipient
                    );
                }
            }
            totalBps += allocation.bps;
        }
        // forge-lint: disable-end(require-revert-in-loop)
        if (totalBps > BurnerLoansConstants.MAX_BPS) {
            revert IBurnerLoans.BurnerLoans_InvalidAssetYieldRoutingTotal(totalBps);
        }

        if (routing_.repurchaseRecipientBps != 0) {
            if (repurchaseRecipient_ == address(0)) {
                revert IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientNotConfigured();
            }
            validateYieldRepurchaseRecipientAsset(
                depositManager_,
                treasury_,
                repurchaseRecipient_,
                asset_
            );
        }
    }

    /// @dev Revalidates conditions that can drift after storage. Recipient uniqueness is enforced
    ///      once by the only route-writing path and cannot change independently afterward.
    function _validateStoredDirectAllocations(
        IBurnerLoans.AssetYieldRouting storage routing_,
        address treasury_,
        address repurchaseRecipient_
    ) private view {
        uint256 directCount = routing_.directAllocations.length;
        uint256 totalBps = routing_.repurchaseRecipientBps;
        // Stored-route validation is intentionally atomic: any invalid allocation must reject the
        // complete operation that consumes the route.
        // forge-lint: disable-start(require-revert-in-loop)
        for (uint256 i; i < directCount; ++i) {
            IBurnerLoans.DirectYieldAllocation storage allocation = routing_.directAllocations[i];
            if (
                allocation.recipient == address(0) ||
                allocation.recipient == address(this) ||
                allocation.recipient == treasury_ ||
                allocation.recipient == repurchaseRecipient_
            ) {
                revert IBurnerLoans.BurnerLoans_InvalidDirectYieldRecipient(allocation.recipient);
            }
            if (allocation.bps == 0) {
                revert IBurnerLoans.BurnerLoans_InvalidDirectYieldAllocationBps(
                    allocation.recipient
                );
            }
            totalBps += allocation.bps;
        }
        // forge-lint: disable-end(require-revert-in-loop)
        if (totalBps > BurnerLoansConstants.MAX_BPS) {
            revert IBurnerLoans.BurnerLoans_InvalidAssetYieldRoutingTotal(totalBps);
        }
    }

    function _assetYieldRoutingEquals(
        IBurnerLoans.AssetYieldRouting storage stored_,
        IBurnerLoans.AssetYieldRouting calldata candidate_
    ) private view returns (bool) {
        if (
            stored_.repurchaseRecipientBps != candidate_.repurchaseRecipientBps ||
            stored_.directAllocations.length != candidate_.directAllocations.length
        ) return false;

        uint256 directCount = candidate_.directAllocations.length;
        for (uint256 i; i < directCount; ++i) {
            IBurnerLoans.DirectYieldAllocation storage storedAllocation = stored_.directAllocations[
                i
            ];
            IBurnerLoans.DirectYieldAllocation calldata candidateAllocation = candidate_
                .directAllocations[i];
            if (
                storedAllocation.recipient != candidateAllocation.recipient ||
                storedAllocation.bps != candidateAllocation.bps
            ) return false;
        }
        return true;
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
