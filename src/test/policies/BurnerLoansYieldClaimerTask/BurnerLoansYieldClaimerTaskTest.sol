// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {MockBurnerLoansYieldClaimerTaskTarget} from "./MockBurnerLoansYieldClaimerTaskTarget.sol";
import {Test} from "@forge-std-1.16.2/Test.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {BurnerLoansYieldClaimerTask} from "src/policies/burnerloans/BurnerLoansYieldClaimerTask.sol";

abstract contract BurnerLoansYieldClaimerTaskTest is Test {
    uint32 internal constant _EXECUTION_GAS_LIMIT = 1_000_000;

    address internal admin;
    address internal burnerLoansAdmin;
    address internal _emergency;
    address internal heart;

    Kernel internal kernel;
    OlympusRoles internal roles;
    RolesAdmin internal rolesAdmin;
    MockBurnerLoansYieldClaimerTaskTarget internal target;
    BurnerLoansYieldClaimerTask internal claimer;

    function setUp() public virtual {
        admin = makeAddr("admin");
        burnerLoansAdmin = makeAddr("burnerLoansAdmin");
        _emergency = makeAddr("emergency");
        heart = makeAddr("heart");

        vm.startPrank(admin);
        kernel = new Kernel();
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        target = new MockBurnerLoansYieldClaimerTaskTarget(kernel);
        claimer = new BurnerLoansYieldClaimerTask(kernel, address(target), _EXECUTION_GAS_LIMIT);
        vm.label(address(kernel), "Kernel");
        vm.label(address(roles), "ROLES");
        vm.label(address(rolesAdmin), "Roles admin");
        vm.label(address(target), "Burner Loans yield target");
        vm.label(address(claimer), "Burner Loans yield claimer task");

        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(target));
        kernel.executeAction(Actions.ActivatePolicy, address(claimer));
        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, burnerLoansAdmin);
        rolesAdmin.grantRole(EMERGENCY_ROLE, _emergency);
        rolesAdmin.grantRole(HEART_ROLE, heart);
        rolesAdmin.grantRole(BL_YIELD_CLAIMER_ROLE, address(claimer));
        claimer.enable("");
        vm.stopPrank();
    }

    function _grantClaimerAdmin(address caller_, uint8 roleClass_) internal {
        vm.assume(caller_ != address(0));
        vm.assume(caller_ != admin && caller_ != burnerLoansAdmin);
        roleClass_ = uint8(bound(roleClass_, 0, 2));
        vm.startPrank(admin);
        if (roleClass_ != 1) rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (roleClass_ != 0) rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
        vm.stopPrank();
    }

    function _setLocalMode(uint8 mode_) internal {
        mode_ = uint8(bound(mode_, 0, 2));
        if (mode_ == 0) return;
        vm.prank(admin);
        claimer.disable("");
        if (mode_ == 2) {
            vm.prank(admin);
            claimer.reEnable();
        }
    }

    function _settingsDigest() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    claimer.core(),
                    claimer.executionGasLimit(),
                    claimer.minimumGasToAttempt(),
                    claimer.gasReserve(),
                    claimer.gracePeriod(),
                    claimer.nextAssetIndex(),
                    target.claimCalls()
                )
            );
    }

    function _expectTransition(address caller_, bool enabled_) internal {
        vm.expectEmit(false, false, false, true, address(claimer));
        if (enabled_) emit IEnabler.Enabled();
        else emit IEnabler.Disabled();
        vm.expectEmit(true, true, false, true, address(claimer));
        emit IEnablerV2.Transition(caller_, enabled_, "", uint48(vm.getBlockTimestamp()));
    }

    function _assertTransition(bool enabled_, bytes32 settings_) internal view {
        assertEq(claimer.isEnabled(), enabled_, "Exact local enabled state");
        assertEq(claimer.lastTransitionAt(), vm.getBlockTimestamp(), "Exact transition timestamp");
        assertEq(_settingsDigest(), settings_, "Lifecycle preserves settings and claims");
    }

    function _setClaimerLifecycle(bool active_, bool enabled_) internal {
        if (!enabled_) {
            vm.prank(_emergency);
            claimer.disable("");
        }
        if (!active_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(claimer));
        }
    }

    function _setTargetLifecycle(bool active_, bool enabled_) internal {
        if (!enabled_) target.disable("");
        if (!active_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(target));
        }
    }

    function _boundUint32(uint32 value_, uint32 min_, uint32 max_) internal pure returns (uint32) {
        // bound() guarantees that the result remains within the supplied uint32 interval.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint32(bound(value_, min_, max_));
    }

    function _boundUint8(uint8 value_, uint8 min_, uint8 max_) internal pure returns (uint8) {
        // bound() guarantees that the result remains within the supplied uint8 interval.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint8(bound(value_, min_, max_));
    }

    function _boundUint48(uint48 value_, uint48 min_, uint48 max_) internal pure returns (uint48) {
        // bound() guarantees that the result remains within the supplied uint48 interval.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint48(bound(value_, min_, max_));
    }
}
