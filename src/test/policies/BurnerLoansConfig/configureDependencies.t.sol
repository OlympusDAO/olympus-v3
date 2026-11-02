// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Contracts
import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";
import {Actions, Keycode, Policy, toKeycode} from "src/Kernel.sol";
import {OlympusFixedTermLoan} from "src/modules/FLOAN/OlympusFixedTermLoan.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansConfigConfigureDependenciesTest is BurnerLoansConfigTest {
    // Scenarios: BLCFG-DEPENDENCIES-P01.
    function test_whenDependenciesConfigured(address caller_) public {
        vm.prank(caller_);
        Keycode[] memory keys = _config.configureDependencies();
        assertEq(keys.length, 2, "Two direct modules");
        assertEq(Keycode.unwrap(keys[0]), bytes5("FLOAN"), "FLOAN first");
        assertEq(Keycode.unwrap(keys[1]), bytes5("ROLES"), "ROLES second");
        vm.prank(caller_);
        keys = _config.configureDependencies();
        assertEq(keys.length, 2, "Repeated configuration supported");
    }

    // Scenarios: BLCFG-DEPENDENCIES-I01.
    function test_givenFLOANMissing_whenDependenciesConfigured_reverts(address caller_) public {
        vm.mockCall(
            address(_kernel),
            abi.encodeCall(_kernel.getModuleForKeycode, (toKeycode("FLOAN"))),
            abi.encode(address(0))
        );
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.configureDependencies, ()),
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, bytes5("FLOAN"))
        );
    }

    // Scenarios: BLCFG-DEPENDENCIES-I01.
    function test_givenFLOANMajorUnsupported_whenDependenciesConfigured_reverts(
        address caller_
    ) public {
        vm.mockCall(
            address(_floan),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(uint8(2), uint8(0))
        );
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.configureDependencies, ()),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidModuleVersion.selector)
        );
    }

    // Scenarios: BLCFG-DEPENDENCIES-I01.
    function test_givenROLESMissing_whenDependenciesConfigured_reverts(address caller_) public {
        vm.mockCall(
            address(_kernel),
            abi.encodeCall(_kernel.getModuleForKeycode, (toKeycode("ROLES"))),
            abi.encode(address(0))
        );
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.configureDependencies, ()),
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, bytes5("ROLES"))
        );
    }

    // Scenarios: BLCFG-DEPENDENCIES-I01.
    function test_givenROLESMajorUnsupported_whenDependenciesConfigured_reverts(
        address caller_
    ) public {
        vm.mockCall(
            address(_roles),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(uint8(2), uint8(0))
        );
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.configureDependencies, ()),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidModuleVersion.selector)
        );
    }

    // Scenarios: BLCFG-DEPENDENCIES-P01.
    function test_givenCompatibleReplacement_whenDependenciesConfigured(address caller_) public {
        OlympusFixedTermLoan replacement = new OlympusFixedTermLoan(_kernel);
        _kernel.executeAction(Actions.UpgradeModule, address(replacement));
        vm.prank(caller_);
        _config.configureDependencies();
        assertEq(
            address(_kernel.getModuleForKeycode(toKeycode("FLOAN"))),
            address(replacement),
            "Authoritative replacement module"
        );
        vm.expectCall(address(replacement), abi.encodeCall(replacement.getMarket, (_market)));
        _validationReverts(
            caller_,
            _capValidation(1),
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, _market)
        );
    }

    // Scenarios: BLCFG-DEPENDENCIES-P01.
    function test_givenCompatibleRolesReplacement_whenConfigured(address caller_) public {
        OlympusRoles replacement = new OlympusRoles(_kernel);
        vm.mockCall(
            address(_kernel),
            abi.encodeCall(_kernel.getModuleForKeycode, (toKeycode("ROLES"))),
            abi.encode(address(replacement))
        );
        vm.mockCall(
            address(replacement),
            abi.encodeWithSignature("hasRole(address,bytes32)", _recipient, ADMIN_ROLE),
            abi.encode(true)
        );
        vm.prank(caller_);
        _config.configureDependencies();
        vm.expectCall(
            address(replacement),
            abi.encodeWithSignature("hasRole(address,bytes32)", _recipient, ADMIN_ROLE)
        );
        vm.prank(_recipient);
        _config.setConfigOperator(_recipient);
        assertEq(_config.configOperator(), _recipient, "Authorization uses refreshed ROLES handle");
    }
}
