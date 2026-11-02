// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansConfig} from "src/policies/burnerloans/BurnerLoansConfig.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansConfigReEnableTest is BurnerLoansConfigTest {
    function _grantRecoveryCaller(address caller_, bool admin_, bool recovery_) internal {
        vm.assume(caller_ != address(0));
        vm.assume(admin_ || recovery_);
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        if (admin_) _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (recovery_) _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
    }

    // Scenarios: BLCFG-REENABLE-A02.
    function test_whenCallerHasNoRecoveryRole_reverts(address caller_) public givenConfigDisabled {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        vm.warp(uint256(_config.lastTransitionAt()) + _config.gracePeriod() + 1);
        _core.disable("");
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: BLCFG-REENABLE-L01.
    function test_givenAlreadyEnabled_whenActivationRetried_reverts(
        address caller_,
        bool active_
    ) public {
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: BLCFG-REENABLE-L03.
    function test_givenInactivePolicy_whenActivated_reverts(
        address caller_,
        bool admin_,
        bool recovery_
    ) public givenConfigDisabled {
        _grantRecoveryCaller(caller_, admin_, recovery_);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCFG-REENABLE-D05.
    function test_givenCoreInactiveEnabled_whenActivated_reverts(
        address caller_,
        bool admin_,
        bool recovery_
    ) public givenConfigDisabled {
        _grantRecoveryCaller(caller_, admin_, recovery_);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-REENABLE-D07.
    function test_givenCoreActiveDisabled_whenActivated_reverts(
        address caller_,
        bool admin_,
        bool recovery_
    ) public givenConfigDisabled {
        _grantRecoveryCaller(caller_, admin_, recovery_);
        _core.disable("");
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-REENABLE-D09.
    function test_givenCoreInactiveDisabled_whenActivated_reverts(
        address caller_,
        bool admin_,
        bool recovery_
    ) public givenConfigDisabled {
        _grantRecoveryCaller(caller_, admin_, recovery_);
        _core.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-REENABLE-D01.
    function test_givenRevertingEnabled_whenActivated_reverts(
        address caller_,
        bool admin_,
        bool recovery_
    ) public givenConfigDisabled {
        _grantRecoveryCaller(caller_, admin_, recovery_);
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSignature("MockBeforeEnableReverted()")
        );
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-REENABLE-D02.
    function test_givenMalformedEnabled_whenActivated_reverts(
        address caller_,
        bool admin_,
        bool recovery_
    ) public givenConfigDisabled {
        _grantRecoveryCaller(caller_, admin_, recovery_);
        vm.mockCall(address(_core), abi.encodeWithSignature("isEnabled()"), hex"01");
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-REENABLE-D11.
    function test_givenWrongKernel_whenActivated_reverts(
        address caller_,
        bool admin_,
        bool recovery_
    ) public givenConfigDisabled {
        _grantRecoveryCaller(caller_, admin_, recovery_);
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0xBAD))
        );
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(_kernel),
                address(0xBAD)
            )
        );
    }

    // Scenarios: BLCFG-REENABLE-D12.
    function test_givenMissingCoreInterface_whenActivated_reverts(
        address caller_,
        bool admin_,
        bool recovery_
    ) public givenConfigDisabled {
        _grantRecoveryCaller(caller_, admin_, recovery_);
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansCore).interfaceId
            ),
            abi.encode(false)
        );
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidCore.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-REENABLE-D13.
    function test_givenMissingEnabler_whenActivated_reverts(
        address caller_,
        bool admin_,
        bool recovery_
    ) public givenConfigDisabled {
        _grantRecoveryCaller(caller_, admin_, recovery_);
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("supportsInterface(bytes4)", type(IEnabler).interfaceId),
            abi.encode(false)
        );
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidCore.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-REENABLE-D14.
    function test_givenDifferentOhm_whenActivated_reverts(
        address caller_,
        bool admin_,
        bool recovery_
    ) public givenConfigDisabled {
        _grantRecoveryCaller(caller_, admin_, recovery_);
        vm.mockCall(address(_core), abi.encodeWithSignature("ohm()"), abi.encode(address(_asset)));
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidCore.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-REENABLE-D15.
    function test_givenDifferentConfigurator_whenActivated_reverts(
        address caller_,
        bool admin_,
        bool recovery_
    ) public givenConfigDisabled {
        _grantRecoveryCaller(caller_, admin_, recovery_);
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("configOperator()"),
            abi.encode(address(0xBAD))
        );
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_InvalidCore.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-REENABLE-D23.
    function test_givenIndependentInventoryState_whenActivated(
        bool active_,
        bool enabled_,
        address caller_,
        bool admin_,
        bool recovery_
    ) public givenConfigDisabled {
        _grantRecoveryCaller(caller_, admin_, recovery_);
        _setPolicyState(_inventory, active_, enabled_);
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("inventory()"), hex"deadbeef");
        bytes32 beforeEconomics = _economicDigest();
        vm.expectEmit(address(_config));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_config));
        emit IEnablerV2.Transition(caller_, true, "", uint48(vm.getBlockTimestamp()));
        vm.prank(caller_);
        _config.reEnable();
        assertEq(_config.lastTransitionAt(), vm.getBlockTimestamp(), "Exact recovery timestamp");
        assertTrue(_config.isEnabled(), "Inventory is not Config's direct dependency");
        assertEq(_economicDigest(), beforeEconomics, "No Inventory or market writes");
    }

    // Scenarios: BLCFG-REENABLE-L02, BLCFG-REENABLE-L04.
    function test_givenNeverEnabled_whenRecoveryRequested_reverts(address caller_) public {
        BurnerLoansConfig fresh = new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
        vm.prank(caller_);
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        fresh.reEnable();
    }

    // Scenarios: BLCFG-REENABLE-P01.
    function test_givenWithinGrace_whenRecoveryRequested(
        uint48 l,
        uint32 g,
        uint256 now_,
        address caller_,
        bool admin_,
        bool recovery_
    ) public {
        g = uint32(bound(g, 1, type(uint32).max));
        l = uint48(bound(l, 1, type(uint48).max - g));
        uint256 d = uint256(l) + g;

        _config.setGracePeriod(g);
        vm.warp(l);
        _config.disable("");
        vm.warp(bound(now_, l, d - 1));
        _grantRecoveryCaller(caller_, admin_, recovery_);
        vm.expectEmit(address(_config));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_config));
        emit IEnablerV2.Transition(caller_, true, "", uint48(vm.getBlockTimestamp()));
        vm.prank(caller_);
        _config.reEnable();
        assertTrue(_config.isEnabled(), "Re-enabled");
        assertEq(_config.lastTransitionAt(), vm.getBlockTimestamp(), "Recovery timestamp");
    }

    // Scenarios: BLCFG-REENABLE-P02.
    function test_givenExactDeadline_whenRecoveryRequested(
        uint48 l,
        uint32 g,
        address caller_,
        bool admin_,
        bool recovery_
    ) public {
        g = uint32(bound(g, 1, type(uint32).max));
        l = uint48(bound(l, 1, type(uint48).max - g));
        uint256 d = uint256(l) + g;

        _config.setGracePeriod(g);
        vm.warp(l);
        _config.disable("");
        vm.warp(d);
        _grantRecoveryCaller(caller_, admin_, recovery_);
        vm.expectEmit(address(_config));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_config));
        emit IEnablerV2.Transition(caller_, true, "", uint48(vm.getBlockTimestamp()));
        vm.prank(caller_);
        _config.reEnable();
        assertTrue(_config.isEnabled(), "Re-enabled");
        assertEq(_config.lastTransitionAt(), vm.getBlockTimestamp(), "Recovery timestamp");
    }

    // Scenarios: BLCFG-REENABLE-P03.
    function test_givenExpiredGrace_whenRecoveryRequested_reverts(
        uint48 l,
        uint32 g,
        uint256 now_,
        address caller_,
        bool admin_,
        bool recovery_
    ) public {
        g = uint32(bound(g, 1, type(uint32).max));
        l = uint48(bound(l, 1, type(uint48).max - g));
        uint256 d = uint256(l) + g;
        vm.assume(d < type(uint48).max);
        _config.setGracePeriod(g);
        vm.warp(l);
        _config.disable("");
        vm.warp(bound(now_, d + 1, type(uint48).max));
        _grantRecoveryCaller(caller_, admin_, recovery_);
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, uint48(d))
        );
    }

    // Scenarios: BLCFG-REENABLE-N01.
    function test_givenGraceDeadlineOverflow_whenRecoveryRequested_reverts(
        uint48 l,
        uint32 g,
        address caller_,
        bool admin_,
        bool recovery_
    ) public {
        _grantRecoveryCaller(caller_, admin_, recovery_);
        g = uint32(bound(g, 1, type(uint32).max));
        l = uint48(bound(l, uint256(type(uint48).max) - g + 1, type(uint48).max));
        _config.setGracePeriod(g);
        vm.warp(l);
        _config.disable("");
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(l) + g
            )
        );
    }

    // Scenarios: BLCFG-REENABLE-A01.
    function test_givenWithinGrace_whenCallerHasNoRecoveryRole_reverts(
        address caller_
    ) public givenConfigDisabled {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: BLCFG-REENABLE-L01.
    function test_givenEnabledAtZeroTimestamp_whenRecoveryRequested_reverts(
        address caller_
    ) public {
        _config.disable("");
        vm.warp(0);
        _config.enable("");
        assertEq(_config.lastTransitionAt(), 0, "Reachable enabled zero-time history");
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: BLCFG-REENABLE-L02.
    function test_givenActivatedButNeverEnabled_whenRecoveryRequested_reverts(
        address caller_,
        bool active_
    ) public {
        BurnerLoansConfig fresh = new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
        _kernel.executeAction(Actions.ActivatePolicy, address(fresh));
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(fresh));
        vm.prank(caller_);
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        fresh.reEnable();
    }

    // Scenarios: BLCFG-REENABLE-P02.
    function test_givenMaximumRepresentableDeadline_whenRecoveryAtDeadline() public {
        _config.setGracePeriod(1);
        vm.warp(uint256(type(uint48).max) - 1);
        _config.disable("");
        vm.warp(type(uint48).max);
        _config.reEnable();
        assertTrue(_config.isEnabled(), "Maximum deadline is inclusive");
        assertEq(_config.lastTransitionAt(), type(uint48).max, "Maximum timestamp preserved");
    }

    // Scenarios: BLCFG-REENABLE-P03.
    function test_givenExpiredGraceBoundarySeeds_whenRecoveryRequested_reverts() public {
        _config.setGracePeriod(1);
        vm.warp(1);
        _config.disable("");
        vm.warp(3);
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, uint48(2))
        );
        vm.warp(type(uint48).max);
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, uint48(2))
        );
    }

    // Scenarios: BLCFG-REENABLE-N01.
    function test_givenMaximumGraceAndTransitionTimestamp_whenRecoveryRequested() public {
        _config.setGracePeriod(type(uint32).max);
        vm.warp(type(uint48).max);
        _config.disable("");
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.reEnable, ()),
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(type(uint48).max) + type(uint32).max
            )
        );
    }

    // Scenarios: BLCFG-REENABLE-P01.
    function test_givenGraceStartAndLastInteriorSecond_whenRecoveryRequested() public {
        _config.setGracePeriod(2);
        vm.warp(1);
        _config.disable("");
        uint256 paused = vm.snapshotState();
        _config.reEnable();
        assertTrue(_config.isEnabled(), "Recovery permitted at grace start");
        assertTrue(vm.revertToState(paused), "Restore disabled state for adjacent seed");
        vm.warp(2);
        _config.reEnable();
        assertTrue(_config.isEnabled(), "Recovery permitted one second before deadline");
        assertEq(_config.lastTransitionAt(), 2, "Exact last interior recovery timestamp");
    }
}
