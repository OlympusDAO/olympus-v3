// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";
import {Actions, Kernel, Keycode, toKeycode} from "src/Kernel.sol";
import {Policy} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";

contract BurnerLoansRiskConfigTimelockConfigureDependenciesTest is
    BurnerLoansRiskConfigTimelockTest
{
    // Scenarios: BLRCT-DEPENDENCIES-P01.
    function test_whenDependenciesConfigured(
        address caller_,
        bool active_,
        bool enabled_,
        uint8 minor_
    ) public {
        _setState(_timelock, active_, enabled_);
        vm.mockCall(
            address(_roles),
            abi.encodeCall(IVersioned.VERSION, ()),
            abi.encode(uint8(1), minor_)
        );
        vm.prank(caller_);
        Keycode[] memory result = _timelock.configureDependencies();
        assertEq(result.length, 1, "one module dependency");
        assertEq(Keycode.unwrap(result[0]), bytes5("ROLES"), "exact ROLES dependency");
        assertEq(_timelock.requestPermissions().length, 0, "no FLOAN write authority");
    }

    // Scenarios: BLRCT-DEPENDENCIES-I02.
    function test_whenUnsupportedMajor_reverts(uint8 major_) public {
        vm.assume(major_ != 1);
        OlympusRoles invalid = new OlympusRoles(_kernel);
        vm.mockCall(
            address(invalid),
            abi.encodeCall(IVersioned.VERSION, ()),
            abi.encode(major_, uint8(0))
        );
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", bytes5("ROLES")),
            abi.encode(address(invalid))
        );
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidModuleVersion.selector);
        _timelock.configureDependencies();
        assertEq(
            address(_timelock.ROLES()),
            address(_roles),
            "failed configuration preserves cached module"
        );
    }

    // Scenarios: BLRCT-DEPENDENCIES-I01.
    function test_givenMissingRoles_whenDependenciesConfigured_reverts() public {
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", bytes5("ROLES")),
            abi.encode(address(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
        _timelock.configureDependencies();
        assertEq(
            address(_timelock.ROLES()),
            address(_roles),
            "failed configuration preserves cached module"
        );
    }

    // Scenarios: BLRCT-DEPENDENCIES-P02.
    function test_givenRolesUpgraded_whenReconfigured() public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        bytes32 queued = _queueDigest(id);
        OlympusRoles replacement = new OlympusRoles(_kernel);
        _kernel.executeAction(Actions.UpgradeModule, address(replacement));
        assertEq(
            address(_timelock.ROLES()),
            address(replacement),
            "Kernel upgrade refreshes cached role module"
        );
        assertEq(_timelock.nextActionId(), 2, "dependency refresh preserves queue IDs");
        assertEq(_queueDigest(id), queued, "module refresh preserves pending payloads and keys");
    }
}
