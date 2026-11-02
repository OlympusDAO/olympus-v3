// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansYieldClaimerTaskTest} from "./BurnerLoansYieldClaimerTaskTest.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansYieldClaimerTask} from "src/policies/burnerloans/BurnerLoansYieldClaimerTask.sol";

contract BurnerLoansYieldClaimerTaskDisableTest is BurnerLoansYieldClaimerTaskTest {
    // Scenarios: BLYC-DISABLE-A01, BLYC-DISABLE-A02, BLYC-DISABLE-A04, BLYC-DISABLE-L03, BLYC-DISABLE-L04, BLYC-DISABLE-L05, BLYC-DISABLE-L06, BLYC-DISABLE-L07, BLYC-DISABLE-L08, BLYC-DISABLE-L09, BLYC-DISABLE-L10.
    function test_whenPermittedCallerDisables(
        address caller_,
        uint8 roleClass_,
        bool active_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        vm.assume(caller_ != address(0) && caller_ != admin && caller_ != _emergency);
        roleClass_ = uint8(bound(roleClass_, 0, 2));
        vm.startPrank(admin);
        if (roleClass_ != 1) rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (roleClass_ != 0) rolesAdmin.grantRole(EMERGENCY_ROLE, caller_);
        vm.stopPrank();
        _setTargetLifecycle(coreActive_, coreEnabled_);
        _setClaimerLifecycle(active_, true);
        target.setAssetViewReverts(true);
        vm.warp(2 days);
        bytes32 settings = _settingsDigest();
        _expectTransition(caller_, false);
        vm.prank(caller_);
        claimer.disable("");
        _assertTransition(false, settings);
    }

    // Scenarios: BLYC-DISABLE-A01, BLYC-DISABLE-A02, BLYC-DISABLE-A04.
    function test_whenExclusiveAndOverlappingRoleSeedsDisable() public {
        uint256 snapshot = vm.snapshotState();
        for (uint8 roleClass; roleClass < 3; ++roleClass) {
            test_whenPermittedCallerDisables(address(0xBEEF), roleClass, true, true, true);
            vm.revertToState(snapshot);
        }
    }

    // Scenarios: BLYC-DISABLE-A03, BLYC-DISABLE-I04.
    function test_whenUnauthorizedCallerDisables_reverts(
        address caller_,
        bytes calldata data_
    ) public {
        vm.assume(caller_ != admin && caller_ != _emergency);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        claimer.disable(data_);
        assertTrue(claimer.isEnabled(), "Unauthorized pause has no effects");
    }

    // Scenarios: BLYC-DISABLE-L01, BLYC-DISABLE-L02, BLYC-DISABLE-I03.
    function test_givenDisabled_whenDisabledAgain_reverts(
        address caller_,
        bool active_,
        bytes calldata data_
    ) public {
        _setClaimerLifecycle(active_, false);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        claimer.disable(data_);
        assertFalse(claimer.isEnabled(), "State precedence retains disabled flag");
    }

    // Scenarios: BLYC-DISABLE-I01.
    function test_whenPayloadIsNonempty_reverts(
        uint16 length_,
        uint8 roleClass_,
        address caller_
    ) public {
        vm.assume(caller_ != address(0) && caller_ != admin && caller_ != _emergency);
        roleClass_ = uint8(bound(roleClass_, 0, 2));
        vm.startPrank(admin);
        if (roleClass_ != 1) rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (roleClass_ != 0) rolesAdmin.grantRole(EMERGENCY_ROLE, caller_);
        vm.stopPrank();
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        vm.prank(caller_);
        claimer.disable(new bytes(bound(length_, 1, 256)));
        assertTrue(claimer.isEnabled(), "Bad payload cannot pause");
    }

    // Scenarios: BLYC-DISABLE-L11.
    function test_givenNeverActivated_whenDisabled_reverts(address caller_) public {
        BurnerLoansYieldClaimerTask fresh = new BurnerLoansYieldClaimerTask(
            kernel,
            address(target),
            1
        );
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        fresh.disable("");
        assertEq(fresh.lastTransitionAt(), 0, "No initialization from failed pause");
    }
}
