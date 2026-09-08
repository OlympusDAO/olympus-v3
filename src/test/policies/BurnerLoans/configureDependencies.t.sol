// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

import {IERC20} from "src/interfaces/IERC20.sol";
import {Actions, Kernel, Keycode, Module, toKeycode} from "src/Kernel.sol";
import {OlympusFixedTermLoan} from "src/modules/FLOAN/OlympusFixedTermLoan.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {MockDepositManager} from "src/test/mocks/MockDepositManager.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";
import {BurnerLoansHarness} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarness.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

// Scenario-specific contracts and fixtures have no cross-file consumers.
// forge-lint: disable-start(multi-contract-file)

contract BurnerLoansConfigureDependenciesTest is BurnerLoansTest {
    // configureDependencies
    // given BurnerLoans has been activated by the kernel
    //  when configured module dependencies are inspected
    //   then expected module references are stored
    function test_configureDependencies_setsModules() public view {
        assertEq(address(burnerLoans.floanForTest()), address(floan), "FLOAN");
        assertEq(burnerLoans.floan(), address(floan), "public FLOAN getter");
        assertEq(address(burnerLoans.PRICE()), address(price), "PRICE");
        assertEq(address(burnerLoans.ROLES()), address(roles), "ROLES");
        assertEq(address(burnerLoans.TRSRY()), address(trsry), "TRSRY");
    }

    // configureDependencies
    // given the FLOAN module uses an unsupported major version
    //  when BurnerLoans is activated by the kernel
    //   then activation reverts with InvalidModuleVersion
    function test_givenFloanModuleVersionUnsupported_configureDependenciesReverts() public {
        Kernel localKernel = new Kernel();

        _expectActivatePolicyWithModulesReverts(
            localKernel,
            new MockUnsupportedFloan(localKernel),
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
            new OlympusFixedTermLoan(localKernel),
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
            new OlympusFixedTermLoan(localKernel),
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
            new OlympusFixedTermLoan(localKernel),
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
            new OlympusFixedTermLoan(localKernel),
            new MockPrice(localKernel, PRICE_DECIMALS, uint32(8 hours)),
            new OlympusRoles(localKernel),
            new MockUnsupportedTrsry(localKernel)
        );
    }

    function _expectActivatePolicyWithModulesReverts(
        Kernel kernel_,
        Module floan_,
        Module price_,
        Module roles_,
        Module trsry_
    ) internal {
        BurnerLoansHarness localBurnerLoans = new BurnerLoansHarness(
            kernel_,
            IERC20(address(ohm)),
            new MockDepositManager(kernel_, address(usds)),
            backingOracle
        );

        kernel_.executeAction(Actions.InstallModule, address(floan_));
        kernel_.executeAction(Actions.InstallModule, address(price_));
        kernel_.executeAction(Actions.InstallModule, address(roles_));
        kernel_.executeAction(Actions.InstallModule, address(trsry_));

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidModuleVersion.selector);
        kernel_.executeAction(Actions.ActivatePolicy, address(localBurnerLoans));
    }
}

contract MockUnsupportedFloan is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("FLOAN");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 2;
        minor = 0;
    }
}

// This fixture reports all interfaces as supported to isolate version validation.
// forge-lint: disable-next-line(missing-inheritance)
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

// This fixture rejects all interfaces to exercise missing PRICE v2 support.
// forge-lint: disable-next-line(missing-inheritance)
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

// forge-lint: disable-end(multi-contract-file)

// forge-lint: disable-end(literal-instead-of-constant)
