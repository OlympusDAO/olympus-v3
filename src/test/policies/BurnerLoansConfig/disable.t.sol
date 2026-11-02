// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansConfig} from "src/policies/burnerloans/BurnerLoansConfig.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansConfigDisableTest is BurnerLoansConfigTest {
    function _grantPauseCaller(address caller_, bool admin_, bool emergency_) internal {
        vm.assume(caller_ != address(0));
        vm.assume(admin_ || emergency_);
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && !_roles.hasRole(caller_, EMERGENCY_ROLE));
        if (admin_) _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (emergency_) _rolesAdmin.grantRole(EMERGENCY_ROLE, caller_);
    }

    // Scenarios: BLCFG-DISABLE-A03, BLCFG-DISABLE-I04.
    function test_whenCallerHasNoPauseRole_reverts(address caller_, bytes memory data_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && !_roles.hasRole(caller_, EMERGENCY_ROLE));
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.disable, (data_)),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: BLCFG-DISABLE-A01, BLCFG-DISABLE-L03, BLCFG-DISABLE-L04, BLCFG-DISABLE-L05, BLCFG-DISABLE-L06, BLCFG-DISABLE-L07, BLCFG-DISABLE-L08, BLCFG-DISABLE-L09, BLCFG-DISABLE-L10, BLCFG-DISABLE-L11, BLCFG-DISABLE-L12.
    function test_givenPermittedPauseCaller_whenDependenciesOrPolicyInactive(
        address caller_,
        bool admin_,
        bool emergency_,
        bool localActive_,
        bool coreActive_,
        bool coreEnabled_,
        bool inventoryActive_,
        bool inventoryEnabled_
    ) public {
        _grantPauseCaller(caller_, admin_, emergency_);
        _setPolicyState(_core, coreActive_, coreEnabled_);
        if (!localActive_) _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _setPolicyState(_inventory, inventoryActive_, inventoryEnabled_);
        bytes32 economics = _economicDigest();
        vm.expectEmit(address(_config));
        emit IEnabler.Disabled();
        vm.expectEmit(address(_config));
        emit IEnablerV2.Transition(caller_, false, "", uint48(vm.getBlockTimestamp()));
        vm.prank(caller_);
        _config.disable("");
        assertFalse(_config.isEnabled(), "Locally paused");
        assertEq(_config.lastTransitionAt(), vm.getBlockTimestamp(), "Exact pause time");
        assertEq(_economicDigest(), economics, "Pause preserves positions and funds");
    }

    // Scenarios: BLCFG-DISABLE-L01, BLCFG-DISABLE-L02, BLCFG-DISABLE-I03.
    function test_givenDisabled_whenPausedAgain_reverts(
        address caller_,
        bool active_,
        bytes memory data_
    ) public givenConfigDisabled {
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.disable, (data_)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCFG-DISABLE-I01.
    function test_whenPauseDataIsNonempty_reverts(
        bytes memory data_,
        address caller_,
        bool admin_,
        bool emergency_
    ) public {
        _grantPauseCaller(caller_, admin_, emergency_);
        vm.assume(data_.length > 0 && data_.length <= 256);
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.disable, (data_)),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector)
        );
    }

    // Scenarios: BLCFG-DISABLE-L13.
    function test_givenFreshUnconfiguredPolicy_whenDisabled_reverts(address caller_) public {
        BurnerLoansConfig fresh = new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
        vm.prank(caller_);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        fresh.disable("");
        assertFalse(fresh.isEnabled(), "Fresh remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "History unchanged");
    }

    // Scenarios: BLCFG-DISABLE-D01, BLCFG-DISABLE-D02, BLCFG-DISABLE-D03, BLCFG-DISABLE-D04, BLCFG-DISABLE-D05, BLCFG-DISABLE-D06, BLCFG-DISABLE-D07, BLCFG-DISABLE-D08, BLCFG-DISABLE-D09, BLCFG-DISABLE-D10.
    function test_givenUnavailableBindings_whenPaused() public {
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            hex"deadbeef"
        );
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("ohm()"), hex"deadbeef");
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSignature("configOperator()"),
            hex"deadbeef"
        );
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("inventory()"), hex"deadbeef");
        _config.disable("");
        assertFalse(_config.isEnabled(), "Broken metadata cannot prevent pause");
    }

    // Scenarios: BLCFG-DISABLE-I01.
    function test_whenNonemptyPayloadBoundariesSeeded_reverts() public {
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.disable, (hex"00")),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector)
        );
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.disable, (hex"01")),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector)
        );
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.disable, (abi.encode(uint256(0)))),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector)
        );
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.disable, (new bytes(256))),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector)
        );
    }
}
