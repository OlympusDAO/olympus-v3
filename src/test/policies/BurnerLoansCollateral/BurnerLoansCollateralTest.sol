// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Libraries
import {BL_COLLATERAL_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCollateralActionTest} from "./fixtures/BurnerLoansCollateralActionTest.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {BurnerLoansCollateral} from "src/policies/burnerloans/BurnerLoansCollateral.sol";
import {BurnerLoansCore} from "src/policies/burnerloans/BurnerLoansCore.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

/// @notice Lifecycle proofs keep real debt, custody and an unrelated borrower live.
abstract contract BurnerLoansCollateralTest is BurnerLoansCollateralActionTest {
    uint48 internal constant START_TIMESTAMP = 1000;
    Kernel internal kernel;
    OlympusRoles internal roles;
    RolesAdmin internal rolesAdmin;
    BurnerLoansCore internal policy;
    address internal admin;
    address internal emergency = address(0xE911);
    bytes32 internal _preservedAccounting;

    event Enabled();
    event Disabled();
    event Transition(address indexed caller, bool indexed enabled, bytes data, uint48 timestamp);

    function setUp() public virtual override {
        vm.warp(START_TIMESTAMP);
        super.setUp();
        kernel = _kernel;
        roles = _roles;
        rolesAdmin = _rolesAdmin;
        policy = _core;
        admin = address(this);
        _rolesAdmin.grantRole(EMERGENCY_ROLE, emergency);
        vm.startPrank(_borrower);
        _collateral.depositCollateral(address(_asset), 2000e6, _borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 100e6, address(0));
        vm.stopPrank();
        _depositAsset(_asset, 17, _OTHER_BORROWER);
        _preservedAccounting = _accountingDigest(address(_asset));
        // A fresh action has no transition history; Core's positions remain in place.
        _collateral = new BurnerLoansCollateral(kernel, _core);
        kernel.executeAction(Actions.ActivatePolicy, address(_collateral));
        rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(_collateral));
    }

    modifier givenCollateralEnabled() {
        vm.prank(admin);
        _collateral.enable("");
        _;
    }

    modifier givenCollateralDisabledAfterEnable() {
        vm.prank(admin);
        _collateral.enable("");
        vm.prank(admin);
        _collateral.disable("");
        _;
    }

    modifier givenCollateralInactive() {
        kernel.executeAction(Actions.DeactivatePolicy, address(_collateral));
        _;
    }

    /// @dev Grant every selected equivalent caller class; explicit tests seed exclusive/overlap cases.
    function _grantCaller(address caller_, uint8 roleMask_, bytes32 secondRole_) internal {
        if (roleMask_ & 1 != 0 && !roles.hasRole(caller_, ADMIN_ROLE))
            rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (roleMask_ & 2 != 0 && !roles.hasRole(caller_, secondRole_))
            rolesAdmin.grantRole(secondRole_, caller_);
    }

    function _assumeUnauthorized(address caller_, bytes32 secondRole_) internal view {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        vm.assume(!roles.hasRole(caller_, secondRole_));
    }

    function _prepareDisabledAt(uint48 last_, uint32 period_) internal {
        vm.warp(last_);
        vm.startPrank(admin);
        _collateral.enable("");
        _collateral.setGracePeriod(period_);
        _collateral.disable("");
        vm.stopPrank();
    }

    function _assertLifecycle(bool enabled_, uint48 at_) internal view {
        _assertAccountingPreserved();
        assertEq(_collateral.isEnabled(), enabled_, "Collateral enabled flag mismatch");
        assertEq(_collateral.lastTransitionAt(), at_, "Collateral transition timestamp mismatch");
        assertTrue(policy.isEnabled(), "Collateral transition must preserve Core enablement");
        assertTrue(
            kernel.isPolicyActive(policy),
            "Collateral transition must preserve Core membership"
        );
    }

    function _assertRejection(bool enabled_, uint48 at_) internal view {
        _assertAccountingPreserved();
        assertEq(
            _collateral.isEnabled(),
            enabled_,
            "Rejected transition must preserve enabled flag"
        );
        assertEq(
            _collateral.lastTransitionAt(),
            at_,
            "Rejected transition must preserve timestamp"
        );
    }

    function _assertAccountingPreserved() internal view {
        assertEq(
            _accountingDigest(address(_asset)),
            _preservedAccounting,
            "Lifecycle preserves both borrowers, debt, custody, receipts and allowances"
        );
    }

    function _restoreCoreState(bool active_, bool enabled_) internal {
        if (!active_) kernel.executeAction(Actions.ActivatePolicy, address(policy));
        if (!enabled_) {
            vm.prank(admin);
            policy.enable("");
        }
    }

    function _expectEnabledTransition(address caller_) internal {
        vm.expectEmit(address(_collateral));
        emit Enabled();
        vm.expectEmit(address(_collateral));
        emit Transition(caller_, true, "", uint48(vm.getBlockTimestamp()));
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
