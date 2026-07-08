// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
pragma solidity >=0.8.24;

import {IERC20} from "src/interfaces/IERC20.sol";
import {Actions, Kernel, Keycode, Module, Permissions, toKeycode} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";
import {BurnerLoansHarness} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarness.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansConfigureDependenciesTest is BurnerLoansTest {
    // configureDependencies
    // given BurnerLoans has been activated by the kernel
    //  when configured module dependencies are inspected
    //   then expected module references are stored
    function test_configureDependencies_setsModules() public view {
        assertEq(address(burnerLoans.MINTR()), address(mintr), "MINTR");
        assertEq(address(burnerLoans.PRICE()), address(price), "PRICE");
        assertEq(address(burnerLoans.ROLES()), address(roles), "ROLES");
        assertEq(address(burnerLoans.TRSRY()), address(trsry), "TRSRY");
    }

    // configureDependencies
    // given the MINTR module uses an unsupported major version
    //  when BurnerLoans is activated by the kernel
    //   then activation reverts with InvalidModuleVersion
    function test_givenMintrModuleVersionUnsupported_configureDependenciesReverts() public {
        Kernel localKernel = new Kernel();

        _expectActivatePolicyWithModulesReverts(
            localKernel,
            new MockUnsupportedMintr(localKernel),
            new MockPrice(localKernel, PRICE_DECIMALS, uint32(8 hours)),
            new OlympusRoles(localKernel),
            new OlympusTreasury(localKernel)
        );
    }

    // configureDependencies
    // given the PRICE module uses an unsupported version
    //  when BurnerLoans is activated by the kernel
    //   then activation reverts with InvalidModuleVersion
    function test_givenPriceModuleVersionUnsupported_configureDependenciesReverts() public {
        Kernel localKernel = new Kernel();

        _expectActivatePolicyWithModulesReverts(
            localKernel,
            new OlympusMinter(localKernel, address(ohm)),
            new MockUnsupportedPrice(localKernel),
            new OlympusRoles(localKernel),
            new OlympusTreasury(localKernel)
        );
    }

    // configureDependencies
    // given the PRICE module does not implement IPRICEv2
    //  when BurnerLoans is activated by the kernel
    //   then activation reverts with InvalidModuleVersion
    function test_givenPriceModuleDoesNotImplementPriceV2_configureDependenciesReverts() public {
        Kernel localKernel = new Kernel();

        _expectActivatePolicyWithModulesReverts(
            localKernel,
            new OlympusMinter(localKernel, address(ohm)),
            new MockPriceWithoutV2(localKernel),
            new OlympusRoles(localKernel),
            new OlympusTreasury(localKernel)
        );
    }

    // configureDependencies
    // given the ROLES module uses an unsupported major version
    //  when BurnerLoans is activated by the kernel
    //   then activation reverts with InvalidModuleVersion
    function test_givenRolesModuleVersionUnsupported_configureDependenciesReverts() public {
        Kernel localKernel = new Kernel();

        _expectActivatePolicyWithModulesReverts(
            localKernel,
            new OlympusMinter(localKernel, address(ohm)),
            new MockPrice(localKernel, PRICE_DECIMALS, uint32(8 hours)),
            new MockUnsupportedRoles(localKernel),
            new OlympusTreasury(localKernel)
        );
    }

    // configureDependencies
    // given the TRSRY module uses an unsupported major version
    //  when BurnerLoans is activated by the kernel
    //   then activation reverts with InvalidModuleVersion
    function test_givenTrsryModuleVersionUnsupported_configureDependenciesReverts() public {
        Kernel localKernel = new Kernel();

        _expectActivatePolicyWithModulesReverts(
            localKernel,
            new OlympusMinter(localKernel, address(ohm)),
            new MockPrice(localKernel, PRICE_DECIMALS, uint32(8 hours)),
            new OlympusRoles(localKernel),
            new MockUnsupportedTrsry(localKernel)
        );
    }

    // requestPermissions
    // given BurnerLoans declares policy permissions
    //  when requestPermissions is called
    //   then MINTR mint and burn permissions are requested
    function test_requestPermissions_requestsMinterPermissions() public view {
        Permissions[] memory permissions = burnerLoans.requestPermissions();

        assertEq(permissions.length, 2, "permissions length");
        assertEq(
            Keycode.unwrap(permissions[0].keycode),
            Keycode.unwrap(toKeycode("MINTR")),
            "mint keycode"
        );
        assertEq(permissions[0].funcSelector, mintr.mintOhm.selector, "mint selector");
        assertEq(
            Keycode.unwrap(permissions[1].keycode),
            Keycode.unwrap(toKeycode("MINTR")),
            "burn keycode"
        );
        assertEq(permissions[1].funcSelector, mintr.burnOhm.selector, "burn selector");
    }

    function _expectActivatePolicyWithModulesReverts(
        Kernel kernel_,
        Module mintr_,
        Module price_,
        Module roles_,
        Module trsry_
    ) internal {
        BurnerLoansHarness localBurnerLoans = new BurnerLoansHarness(
            kernel_,
            IERC20(address(ohm)),
            depositManager
        );

        kernel_.executeAction(Actions.InstallModule, address(mintr_));
        kernel_.executeAction(Actions.InstallModule, address(price_));
        kernel_.executeAction(Actions.InstallModule, address(roles_));
        kernel_.executeAction(Actions.InstallModule, address(trsry_));

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidModuleVersion.selector);
        kernel_.executeAction(Actions.ActivatePolicy, address(localBurnerLoans));
    }
}

contract MockUnsupportedMintr is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("MINTR");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 2;
        minor = 0;
    }
}

contract MockUnsupportedPrice is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("PRICE");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 1;
    }

    function supportsInterface(bytes4) public pure returns (bool) {
        return true;
    }
}

contract MockPriceWithoutV2 is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("PRICE");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 2;
        minor = 0;
    }

    function supportsInterface(bytes4) public pure returns (bool) {
        return false;
    }
}

contract MockUnsupportedRoles is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("ROLES");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 2;
        minor = 0;
    }
}

contract MockUnsupportedTrsry is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("TRSRY");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 2;
        minor = 0;
    }
}
