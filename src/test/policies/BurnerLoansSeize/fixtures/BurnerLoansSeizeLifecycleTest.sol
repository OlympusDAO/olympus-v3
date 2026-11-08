// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansSeize} from "src/policies/interfaces/burnerloans/IBurnerLoansSeize.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {BL_LIQUIDATION_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions, Policy} from "src/Kernel.sol";
import {BurnerLoansDebtTest} from "src/test/policies/BurnerLoansDebt/BurnerLoansDebtTest.sol";

// Literals are independent expected values and boundary seeds.
// Fixture casts are bounded; seed loops intentionally call external contracts.
// Fixture calls and ignored returns are checked through errors and ledger assertions.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, unsafe-typecast, unused-return)

abstract contract BurnerLoansSeizeLifecycleTest is BurnerLoansDebtTest {
    bytes32 internal _initialAccounting;
    bytes32 internal constant _SETTLEMENT_ROLE = BL_LIQUIDATION_POLICY_ROLE;
    bytes4 internal constant _INTERFACE_ID = type(IBurnerLoansSeize).interfaceId;

    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(_borrower);
        _collateral.depositCollateral(address(_asset), 2000e6, _borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 100e6, address(0));
        vm.stopPrank();
        IBurnerLoansCore.Position memory position = _lens.getPosition(address(_asset), _borrower);
        assertEq(position.depositedCollateral, 2000e6, "Fixture establishes live collateral");
        assertEq(position.debtOhm, 100e9, "Fixture establishes live debt");
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Fixture establishes funding ledger");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            2000e6,
            "Fixture establishes DM operator liabilities"
        );
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            2000e6,
            "Fixture establishes actual custody"
        );
        _initialAccounting = _stateDigest(_borrower);
    }

    function _assertLoansPreserved() internal view {
        assertEq(
            _stateDigest(_borrower),
            _initialAccounting,
            "Lifecycle preserves every accounting, custody, allowance and index component"
        );
    }

    function _assertActivationRejected(uint48 last_) internal view {
        assertFalse(_liquidation.isEnabled(), "Failed activation leaves action disabled");
        assertEq(_liquidation.lastTransitionAt(), last_, "Failed activation preserves history");
        _assertLoansPreserved();
    }

    function _grantReEnableCaller(address caller_, bool blAdmin_, bool overlap_) internal {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(blAdmin_ ? BURNER_LOANS_ADMIN_ROLE : ADMIN_ROLE, caller_);
        if (overlap_)
            _rolesAdmin.grantRole(blAdmin_ ? ADMIN_ROLE : BURNER_LOANS_ADMIN_ROLE, caller_);
    }

    function _grantDisableCaller(address caller_, bool emergency_, bool overlap_) internal {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(emergency_ ? EMERGENCY_ROLE : ADMIN_ROLE, caller_);
        if (overlap_) _rolesAdmin.grantRole(emergency_ ? ADMIN_ROLE : EMERGENCY_ROLE, caller_);
    }

    function _mockUnavailableCoreViews() internal {
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("isEnabled()"), hex"deadbeef");
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("kernel()"), hex"deadbeef");
    }

    function _setEnabledHistory(bool zeroHistory_) internal {
        if (zeroHistory_) {
            _liquidation.disable("");
            vm.warp(0);
            _liquidation.enable("");
        }
    }

    function _expectEnabledTransition(address caller_) internal {
        vm.expectEmit(address(_liquidation));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_liquidation));
        emit IEnablerV2.Transition(caller_, true, "", uint48(vm.getBlockTimestamp()));
    }

    modifier givenRecoveryWindow(
        uint48 last_,
        uint32 grace_,
        uint48 now_
    ) {
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        last_ = uint48(bound(last_, 1, type(uint48).max - grace_));
        now_ = uint48(bound(now_, last_, uint256(last_) + grace_));
        _liquidation.setGracePeriod(grace_);
        vm.warp(last_);
        _liquidation.disable("");
        vm.warp(now_);
        _;
    }

    function _restorePolicyState(Policy subject_, bool active_, bool enabled_) internal {
        if (!active_) _kernel.executeAction(Actions.ActivatePolicy, address(subject_));
        if (!enabled_) IEnabler(address(subject_)).enable("");
    }

    function _expectDependencyUnavailable(Policy dependency_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(dependency_)
            )
        );
    }

    function _assertEnabled() internal view {
        assertTrue(_liquidation.isEnabled(), "Action is enabled");
        assertEq(
            _liquidation.lastTransitionAt(),
            vm.getBlockTimestamp(),
            "Transition records current timestamp"
        );
        _assertLoansPreserved();
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, unsafe-typecast, unused-return)
