// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansSeizeLifecycleTest} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeLifecycleTest.sol";

// Literals are independent expected values and boundary seeds.
// Fixture casts are bounded; seed loops intentionally call external contracts.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansSeizeSetGracePeriodTest is BurnerLoansSeizeLifecycleTest {
    // Scenarios: BLLIQGR-P01.
    function test_whenGraceSetToSameValue_thenStillEmits(uint32 grace_, address caller_) public {
        vm.assume(caller_ != address(0));
        _grantRoleIfMissing(ADMIN_ROLE, caller_);
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        vm.prank(caller_);
        _liquidation.setGracePeriod(grace_);
        uint48 last = _liquidation.lastTransitionAt();
        vm.expectEmit(address(_liquidation));
        emit IGracePeriod.GracePeriodSet(grace_);
        vm.prank(caller_);
        _liquidation.setGracePeriod(grace_);
        assertTrue(_liquidation.isEnabled(), "Same period does not alter enabled state");
        assertEq(_liquidation.gracePeriod(), grace_, "Same period retained");
        assertEq(_liquidation.lastTransitionAt(), last, "Setter is not a transition");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQGR-I01.
    function test_whenGraceIsZero_reverts() public {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        _liquidation.setGracePeriod(0);
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQGR-A01, BLLIQGR-A02.
    function test_whenUnauthorizedGraceSetter_revertsBeforeInput(
        address caller_,
        bool zero_
    ) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _liquidation.setGracePeriod(zero_ ? 0 : 1);
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQGR-L01, BLLIQGR-L02.
    function test_givenDisabled_whenGraceSet_thenPauseWins(address caller_, bool zero_) public {
        _liquidation.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _liquidation.setGracePeriod(zero_ ? 0 : 1);
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQGR-L03, BLLIQGR-L04, BLLIQGR-L05, BLLIQGR-L06, BLLIQGR-N01.
    function test_givenCoreState_whenGraceSet_thenControllerIndependent(
        bool coreActive_,
        bool coreEnabled_,
        uint32 period_
    ) public {
        period_ = uint32(bound(period_, 1, type(uint32).max));
        _setPolicyState(_core, coreActive_, coreEnabled_);
        uint48 last = _liquidation.lastTransitionAt();
        vm.expectEmit(address(_liquidation));
        emit IGracePeriod.GracePeriodSet(period_);
        _liquidation.setGracePeriod(period_);
        assertEq(_liquidation.gracePeriod(), period_, "Full width grace stored");
        assertEq(
            _liquidation.lastTransitionAt(),
            last,
            "Grace setter leaves transition time unchanged"
        );
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQGR-L07.
    function test_givenInactiveSubject_whenGraceSet_reverts(address caller_) public {
        vm.assume(caller_ != address(0));
        _grantRoleIfMissing(ADMIN_ROLE, caller_);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_liquidation));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_liquidation)
            )
        );
        vm.prank(caller_);
        _liquidation.setGracePeriod(1);
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQGR-N01, BLLIQGR-P01.
    function test_whenPeriodIsOne_thenStoredAndEmitted() public {
        test_whenGraceSetToSameValue_thenStillEmits(1, address(0xabc1));
    }

    // Scenarios: BLLIQGR-N01, BLLIQGR-P01.
    function test_whenPeriodIsMaximum_thenStoredAndEmitted() public {
        test_whenGraceSetToSameValue_thenStillEmits(type(uint32).max, address(0xabc1));
    }

    // Scenarios: BLLIQGR-L03, BLLIQGR-L04, BLLIQGR-L05, BLLIQGR-L06, BLLIQGR-N01.
    function test_givenEveryCoreState_whenGraceSetToOne_thenControllerIndependent() public {
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                uint256 checkpoint = vm.snapshotState();
                test_givenCoreState_whenGraceSet_thenControllerIndependent(
                    active != 0,
                    enabled != 0,
                    1
                );
                assertTrue(vm.revertToState(checkpoint), "Restore independent Core lifecycle axes");
            }
        }
    }

    // Scenarios: BLLIQGR-N01, BLLIQGR-P01.
    function test_whenPeriodUnchangedFromDefault_thenStoredAndEmitted() public {
        test_whenGraceSetToSameValue_thenStillEmits(7 days, address(0xabc1));
    }

    // Scenarios: BLLIQGR-L07.
    function test_givenInactiveAndDisabled_whenAnyCallerSetsGrace_reverts(address caller_) public {
        _liquidation.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_liquidation));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_liquidation)
            )
        );
        vm.prank(caller_);
        _liquidation.setGracePeriod(0);
    }

    // Scenarios: BLLIQGR-P01.
    function test_givenExistingAdmin_whenGraceSetToSameValue_thenStillEmits() public {
        test_whenGraceSetToSameValue_thenStillEmits(1, address(this));
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, unsafe-typecast)
