// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

/// @title Burner Loans Dependency Validation
/// @notice Validates module interfaces and versions when the policy is activated.
library BurnerLoansDependencies {
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

    function _validateInventoryCompatibility(
        address facility_,
        address ohm_,
        address inventory_
    ) private view {
        if (!ERC165Checker.supportsInterface(inventory_, type(IBurnerLoansInventory).interfaceId))
            revert IBurnerLoans.BurnerLoans_InvalidInventory(inventory_);

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

    function _requireInventoryActive(Kernel kernel_, address inventory_) private view {
        if (!kernel_.isPolicyActive(Policy(inventory_))) {
            revert IBurnerLoans.BurnerLoans_InventoryNotActive(inventory_);
        }
        if (!_reportsKernel(inventory_, kernel_)) {
            revert IBurnerLoans.BurnerLoans_InvalidInventory(inventory_);
        }
    }

    function _requireConfiguratorActive(Kernel kernel_, address configurator_) private view {
        if (
            !kernel_.isPolicyActive(Policy(configurator_)) ||
            !_reportsKernel(configurator_, kernel_)
        ) {
            revert IBurnerLoansConfig.BurnerLoansConfig_InvalidFacility(configurator_);
        }
    }

    function _reportsKernel(address policy_, Kernel kernel_) private view returns (bool) {
        try Policy(policy_).kernel() returns (Kernel reportedKernel) {
            return address(reportedKernel) == address(kernel_);
        } catch {
            return false;
        }
    }
}
