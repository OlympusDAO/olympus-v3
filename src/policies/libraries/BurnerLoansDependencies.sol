// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";

// Contracts
import {Keycode, Module, Permissions} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

/// @title Burner Loans Dependency Validation
/// @notice Validates module interfaces and versions when the policy is activated.
library BurnerLoansDependencies {
    /// @dev FLOAN module keycode.
    // Each literal is exactly five bytes, so wrapping cannot truncate data.
    // forge-lint: disable-next-line(unsafe-typecast)
    Keycode internal constant _FLOAN_KEYCODE = Keycode.wrap(bytes5("FLOAN"));
    /// @dev MINTR module keycode.
    // forge-lint: disable-next-line(unsafe-typecast)
    Keycode internal constant _MINTR_KEYCODE = Keycode.wrap(bytes5("MINTR"));
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

    /// @notice Returns the modules required by the lifecycle policy in dependency-slot order.
    function keycodes() public pure returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](5);
        dependencies[0] = _FLOAN_KEYCODE;
        dependencies[1] = _MINTR_KEYCODE;
        dependencies[2] = _PRICE_KEYCODE;
        dependencies[3] = _ROLES_KEYCODE;
        dependencies[4] = _TRSRY_KEYCODE;
    }

    /// @notice Returns the MINTR and FLOAN permissions required by the lifecycle policy.
    function permissions() public pure returns (Permissions[] memory requests) {
        requests = new Permissions[](11);
        requests[0] = Permissions({
            keycode: _MINTR_KEYCODE,
            funcSelector: MINTRv1.mintOhm.selector
        });
        requests[1] = Permissions({
            keycode: _MINTR_KEYCODE,
            funcSelector: MINTRv1.burnOhm.selector
        });
        requests[2] = Permissions({
            keycode: _MINTR_KEYCODE,
            funcSelector: MINTRv1.increaseMintApproval.selector
        });
        requests[3] = Permissions({
            keycode: _MINTR_KEYCODE,
            funcSelector: MINTRv1.decreaseMintApproval.selector
        });
        requests[4] = Permissions({
            keycode: _FLOAN_KEYCODE,
            funcSelector: IFLOANv1.addCollateral.selector
        });
        requests[5] = Permissions({
            keycode: _FLOAN_KEYCODE,
            funcSelector: IFLOANv1.removeCollateral.selector
        });
        requests[6] = Permissions({
            keycode: _FLOAN_KEYCODE,
            funcSelector: IFLOANv1.increaseDebt.selector
        });
        requests[7] = Permissions({
            keycode: _FLOAN_KEYCODE,
            funcSelector: IFLOANv1.createPosition.selector
        });
        requests[8] = Permissions({
            keycode: _FLOAN_KEYCODE,
            funcSelector: IFLOANv1.decreaseDebt.selector
        });
        requests[9] = Permissions({
            keycode: _FLOAN_KEYCODE,
            funcSelector: IFLOANv1.extendMaturity.selector
        });
        requests[10] = Permissions({
            keycode: _FLOAN_KEYCODE,
            funcSelector: IFLOANv1.defaultPosition.selector
        });
    }

    /// @notice Validates dependency interfaces and supported major versions during activation.
    /// @dev PRICE supports v1.2 or any v2 release; every other dependency requires major v1.
    function validate(
        IFLOANv1 floan_,
        MINTRv1 mintr_,
        address priceAddress_,
        ROLESv1 roles_,
        TRSRYv1 trsry_
    ) public view returns (IPRICEv2 price) {
        if (!IERC165(priceAddress_).supportsInterface(type(IPRICEv2).interfaceId)) {
            revert IBurnerLoans.BurnerLoans_InvalidModuleVersion();
        }

        (uint8 floanMajor, ) = Module(address(floan_)).VERSION();
        (uint8 mintrMajor, ) = mintr_.VERSION();
        (uint8 priceMajor, uint8 priceMinor) = Module(priceAddress_).VERSION();
        (uint8 rolesMajor, ) = roles_.VERSION();
        (uint8 trsryMajor, ) = trsry_.VERSION();

        if (
            floanMajor != 1 ||
            mintrMajor != 1 ||
            (priceMajor != 2 && (priceMajor != 1 || priceMinor < 2)) ||
            rolesMajor != 1 ||
            trsryMajor != 1
        ) revert IBurnerLoans.BurnerLoans_InvalidModuleVersion();

        return IPRICEv2(priceAddress_);
    }
}
