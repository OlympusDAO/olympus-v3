// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansConfig} from "src/policies/burnerloans/BurnerLoansConfig.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansConfigEnableTest is BurnerLoansConfigTest {
    // Scenarios: BLCFG-ENABLE-A01.
    function test_givenAdmin_whenEnabled(address caller_) public givenConfigDisabled {
        _grantAdmin(caller_);
        bytes32 economics = _economicDigest();
        vm.expectEmit(address(_config));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_config));
        emit IEnablerV2.Transition(caller_, true, "", uint48(vm.getBlockTimestamp()));
        vm.prank(caller_);
        _config.enable("");
        assertTrue(_config.isEnabled(), "Enabled");
        assertEq(_config.lastTransitionAt(), vm.getBlockTimestamp(), "Exact transition time");
        assertEq(_economicDigest(), economics, "Activation preserves economics");
    }

    // Scenarios: BLCFG-ENABLE-A02, BLCFG-ENABLE-I03.
    function test_whenCallerIsNotAdmin_reverts(
        address caller_,
        bytes memory data_
    ) public givenConfigDisabled {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.enable, (data_)),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: BLCFG-ENABLE-I01.
    function test_whenEnablePayloadIsNonempty_reverts(
        bytes memory data_
    ) public givenConfigDisabled {
        vm.assume(data_.length > 0 && data_.length <= 256);
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.enable, (data_)),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector)
        );
    }

    // Scenarios: BLCFG-ENABLE-L01, BLCFG-ENABLE-I02.
    function test_givenAlreadyEnabled_whenActivationRetried_reverts(
        address caller_,
        bool active_
    ) public {
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.enable, ("")),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: BLCFG-ENABLE-L02.
    function test_givenInactivePolicy_whenActivated_reverts() public givenConfigDisabled {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.enable, ("")),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCFG-ENABLE-D05.
    function test_givenCoreInactiveEnabled_whenActivated_reverts() public givenConfigDisabled {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.enable, ("")),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-ENABLE-D07.
    function test_givenCoreActiveDisabled_whenActivated_reverts() public givenConfigDisabled {
        _core.disable("");
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.enable, ("")),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-ENABLE-D09.
    function test_givenCoreInactiveDisabled_whenActivated_reverts() public givenConfigDisabled {
        _core.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.enable, ("")),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-ENABLE-D01.
    function test_givenRevertingEnabled_whenActivated_reverts() public givenConfigDisabled {
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSignature("MockBeforeEnableReverted()")
        );
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.enable, ("")),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-ENABLE-D02.
    function test_givenMalformedEnabled_whenActivated_reverts() public givenConfigDisabled {
        vm.mockCall(address(_core), abi.encodeWithSignature("isEnabled()"), hex"01");
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.enable, ("")),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-ENABLE-D11.
    function test_givenWrongKernel_whenActivated_reverts() public givenConfigDisabled {
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0xBAD))
        );
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.enable, ("")),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(_kernel),
                address(0xBAD)
            )
        );
    }

    // Scenarios: BLCFG-ENABLE-D12.
    function test_givenMissingCoreInterface_whenActivated_reverts() public givenConfigDisabled {
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansCore).interfaceId
            ),
            abi.encode(false)
        );
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.enable, ("")),
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidCore.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-ENABLE-D13.
    function test_givenMissingEnabler_whenActivated_reverts() public givenConfigDisabled {
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("supportsInterface(bytes4)", type(IEnabler).interfaceId),
            abi.encode(false)
        );
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.enable, ("")),
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidCore.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-ENABLE-D14.
    function test_givenDifferentOhm_whenActivated_reverts() public givenConfigDisabled {
        vm.mockCall(address(_core), abi.encodeWithSignature("ohm()"), abi.encode(address(_asset)));
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.enable, ("")),
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidCore.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-ENABLE-D15.
    function test_givenDifferentConfigurator_whenActivated_reverts() public givenConfigDisabled {
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("configOperator()"),
            abi.encode(address(0xBAD))
        );
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.enable, ("")),
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidCore.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-ENABLE-D23.
    function test_givenIndependentInventoryState_whenActivated(
        bool active_,
        bool enabled_
    ) public givenConfigDisabled {
        _setPolicyState(_inventory, active_, enabled_);
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("inventory()"), hex"deadbeef");
        bytes32 beforeEconomics = _economicDigest();
        vm.expectEmit(address(_config));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_config));
        emit IEnablerV2.Transition(address(this), true, "", uint48(vm.getBlockTimestamp()));
        _config.enable("");
        assertEq(_config.lastTransitionAt(), vm.getBlockTimestamp(), "Exact enable timestamp");
        assertTrue(_config.isEnabled(), "Inventory is not Config's direct dependency");
        assertEq(_economicDigest(), beforeEconomics, "No Inventory or market writes");
    }

    // Scenarios: BLCFG-ENABLE-L03.
    function test_givenFreshPolicyWithoutRoles_whenEnabled_reverts(address caller_) public {
        BurnerLoansConfig fresh = new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
        vm.prank(caller_);
        // No ROLES address has been configured; this opaque call has no typed revert data.
        vm.expectRevert(bytes(""));
        fresh.enable("");
    }

    // Scenarios: BLCFG-ENABLE-I01.
    function test_whenNonemptyPayloadBoundariesSeeded_reverts() public givenConfigDisabled {
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.enable, (hex"00")),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector)
        );
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.enable, (hex"01")),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector)
        );
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.enable, (abi.encode(uint256(0)))),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector)
        );
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.enable, (new bytes(256))),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector)
        );
    }

    // Scenarios: BLCFG-ENABLE-I02.
    function test_givenEnabled_whenNonemptyEnablePayloadSubmitted_reverts(address caller_) public {
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.enable, (hex"01")),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }
}
