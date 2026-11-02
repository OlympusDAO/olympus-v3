// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";
import {BL_COLLATERAL_POLICY_ROLE, BL_DEBT_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {CoreService} from "./fixtures/CoreService.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions, Kernel, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansCoreSettleRepayTest is BurnerLoansCoreTest {
    CoreService internal _actor;

    function setUp() public override {
        super.setUp();
        _actor = _service();
        _rolesAdmin.grantRole(BL_DEBT_POLICY_ROLE, address(_actor));
    }

    // Scenarios: BLCORE-SETTLE-REPAY-A02.
    function test_whenCallerLacksSettlementRole_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, BL_DEBT_POLICY_ROLE));
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_DEBT_POLICY_ROLE)
        );
        vm.prank(caller_);
        _core.settleRepay(address(0), 0, address(0), address(0));
        assertEq(_state(), before, "Unauthorized instruction has no effects");
    }

    // Scenarios: BLCORE-SETTLE-REPAY-A03.
    function test_givenOnlySiblingRole_whenSettled_reverts() public {
        CoreService sibling = _service();
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(sibling));
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_DEBT_POLICY_ROLE)
        );
        vm.prank(address(sibling));
        _core.settleRepay(address(0), 0, address(0), address(0));
    }

    // Scenarios: BLCORE-SETTLE-REPAY-A04.
    function test_givenWrongKernelCaller_whenSettled() public {
        Kernel other = new Kernel();
        vm.prank(address(_kernel));
        _actor.changeKernel(other);
        vm.expectCall(address(_actor), abi.encodeWithSignature("kernel()"), uint64(0));
        vm.expectCall(
            address(_kernel),
            abi.encodeCall(_kernel.isPolicyActive, (Policy(address(_actor)))),
            uint64(0)
        );
        _settleAsCaller(address(_actor));
    }

    // Scenarios: BLCORE-SETTLE-REPAY-L01.
    function test_givenCoreDisabled_whenSettled_reverts() public {
        _core.disable("");
        bytes32 before = _state();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(_actor));
        _core.settleRepay(address(0), 0, address(0), address(0));
        assertEq(_state(), before, "Disabled Core rejects before inputs");
    }

    // Scenarios: BLCORE-SETTLE-REPAY-L02, BLCORE-SETTLE-REPAY-L03.
    function test_givenCoreInactive_whenSettled_reverts(bool enabled_) public {
        _setCoreLifecycle(false, enabled_);
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_core)
            )
        );
        vm.prank(address(_actor));
        _core.settleRepay(address(0), 0, address(0), address(0));
        assertEq(_state(), before, "Own inactivity precedes local state and inputs");
    }

    // Scenarios: BLCORE-SETTLE-REPAY-D01.
    function test_givenCallerInactive_whenSettled() public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_actor));
        test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer(false, address(_core));
    }

    // Scenarios: BLCORE-SETTLE-REPAY-D02.
    function test_givenRoleHoldingEOA_whenSettled(address caller_) public {
        vm.assume(caller_.code.length == 0 && caller_ != address(0));
        _grantRole(BL_DEBT_POLICY_ROLE, caller_);
        _settleAsCaller(caller_);
    }

    // Scenarios: BLCORE-SETTLE-REPAY-A01.
    function test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer(
        bool disabled_,
        address bound_
    ) public {
        if (disabled_) _actor.disable("");
        _actor.setCore(bound_);
        _settleAsCaller(address(_actor));
    }

    function _settleAsCaller(address caller_) internal {
        _deposit(2000e6);
        _borrow(2);
        vm.prank(_recipient);
        _ohm.approve(address(_core), type(uint256).max);
        vm.prank(caller_);
        _core.settleRepay(address(_asset), 1, _recipient, _borrower);
        assertEq(_position().debtOhm, 1, "Role-holding caller repays the requested debt");
    }

    // Scenarios: BLCORE-SETTLE-REPAY-I01.
    function test_givenNoDebt_whenRepaid_reverts() public {
        _deposit(2);
        bytes32 before = _ledger();
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        vm.prank(address(_actor));
        _core.settleRepay(address(_asset), 1, _recipient, _borrower);
        assertEq(_ledger(), before, "Rejected repayment rolls back ledger and OHM");
    }

    // Scenarios: BLCORE-SETTLE-REPAY-I02.
    function test_givenOverpayment_whenRepaid_reverts(uint128 amount_) public {
        _deposit(2000e6);
        _borrow(2);
        amount_ = uint128(bound(amount_, 3, type(uint128).max));
        bytes32 before = _ledger();
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        vm.prank(address(_actor));
        _core.settleRepay(address(_asset), amount_, _recipient, _borrower);
        assertEq(_ledger(), before, "Rejected repayment rolls back ledger and OHM");
    }

    // Scenarios: BLCORE-SETTLE-REPAY-N01.
    function test_givenZeroAmount_whenRepaid_reverts() public {
        _deposit(2000e6);
        _borrow(2);
        bytes32 before = _ledger();
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        vm.prank(address(_actor));
        _core.settleRepay(address(_asset), 0, _recipient, _borrower);
        assertEq(_ledger(), before, "Rejected repayment rolls back ledger and OHM");
    }

    // Scenarios: BLCORE-SETTLE-REPAY-P01.
    function test_givenMissingPosition_whenRepaid_reverts() public {
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_NoDebt.selector);
        vm.prank(address(_actor));
        _core.settleRepay(address(_asset), 1, _recipient, _borrower);
        assertEq(_ledger(), before, "Rejected repayment rolls back ledger and OHM");
    }

    // Scenarios: BLCORE-SETTLE-REPAY-P03.
    function test_givenInventoryFailure_whenRepaid_reverts() public {
        _deposit(2000e6);
        _borrow(2);
        vm.prank(_recipient);
        _ohm.approve(address(_core), type(uint256).max);
        vm.mockCallRevert(
            address(_inventory),
            abi.encodeWithSignature("settleRepayment(uint128)"),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        bytes32 before = _ledger();
        vm.expectRevert(DependencyFailed.selector);
        vm.prank(address(_actor));
        _core.settleRepay(address(_asset), 1, _recipient, _borrower);
        assertEq(_ledger(), before, "Rejected repayment rolls back ledger and OHM");
    }

    // Scenarios: BLCORE-SETTLE-REPAY-D03, BLCORE-SETTLE-REPAY-N02, BLCORE-SETTLE-REPAY-N03.
    function test_givenLiveDebt_whenRepaid(
        uint128 principal_,
        uint128 amount_,
        bool originations_
    ) public {
        principal_ = uint128(bound(principal_, 1, type(uint128).max));
        amount_ = uint128(bound(amount_, 1, principal_));
        _deposit(1);
        _config.setAssetDebtCap(address(_asset), type(uint128).max);
        _inventory.setGlobalDebtCap(type(uint128).max);
        _borrow(principal_);
        _config.setAssetOriginationsEnabled(address(_asset), originations_);
        vm.prank(_recipient);
        _ohm.approve(address(_core), type(uint256).max);
        IFLOANv1.Position memory before = _rawPosition();
        vm.prank(address(_actor));
        uint128 remaining = _core.settleRepay(address(_asset), amount_, _recipient, _borrower);
        assertEq(remaining, principal_ - amount_, "Exact returned principal");
        assertEq(_core.totalActiveDebtOhm(), remaining, "Canonical debt agrees");
        assertEq(_inventory.activePrincipalOhm(), remaining, "Inventory principal agrees");
        assertEq(_ohm.balanceOf(_recipient), remaining, "Payer OHM debited exactly once");
        assertEq(
            _position().depositedCollateral,
            before.collateral,
            "Repayment preserves collateral"
        );
        if (remaining == 0) {
            assertEq(_position().maturity, 0, "Full repayment clears episode maturity");
            assertEq(_rawPosition().principalDrawn, 0, "Full repayment clears episode draws");
            assertEq(
                _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
                0,
                "Underlying active index removed"
            );
        } else {
            assertEq(_position().maturity, before.maturity, "Partial repayment preserves maturity");
            assertEq(
                _rawPosition().principalDrawn,
                before.principalDrawn,
                "Partial repayment preserves episode draws"
            );
            assertEq(
                _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
                1,
                "Partial repayment retains active index"
            );
        }
    }

    // Scenarios: BLCORE-SETTLE-REPAY-D03, BLCORE-SETTLE-REPAY-N02, BLCORE-SETTLE-REPAY-N03.
    function test_whenRepaymentBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenLiveDebt_whenRepaid(1, 1, false);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenLiveDebt_whenRepaid(type(uint128).max, type(uint128).max - 1, true);
        vm.revertToState(snapshot);
        test_givenLiveDebt_whenRepaid(type(uint128).max, type(uint128).max, false);
    }

    // Scenarios: BLCORE-SETTLE-REPAY-D04.
    function test_givenBurnFailure_whenRepaid() public {
        _deposit(2000e6);
        _borrow(2);
        vm.prank(_recipient);
        _ohm.approve(address(_core), 2);
        address mintr = address(_kernel.getModuleForKeycode(toKeycode("MINTR")));
        vm.mockCallRevert(
            mintr,
            abi.encodeWithSignature("burnOhm(address,uint256)"),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.prank(address(_actor));
        _core.settleRepay(address(_asset), 2, _recipient, _borrower);
        assertEq(_position().debtOhm, 0, "Burn failure does not restore debt");
        assertEq(_inventory.activePrincipalOhm(), 0, "Inventory principal reduced");
        assertEq(_ohm.balanceOf(address(_inventory)), 2, "Failed burn retained as backed surplus");
    }

    // Scenarios: BLCORE-SETTLE-REPAY-C01.
    function test_givenOhmCallback_whenCaught() public {
        CoreCallbackToken implementation = new CoreCallbackToken();
        vm.etch(address(_ohm), address(implementation).code);
        CoreCallbackToken token = CoreCallbackToken(address(_ohm));
        _deposit(2000e6);
        _borrow(2);
        vm.prank(_recipient);
        _ohm.approve(address(_core), 2);
        _authorizeCollateralCallback(_actor);
        token.setCallbackFrom(
            address(_core),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_collateral),
                abi.encodeWithSignature(
                    "depositCollateral(address,uint128,address)",
                    address(_asset),
                    uint128(1),
                    _recipient
                )
            )
        );
        token.setCallbackPhases(false, true);
        token.setBubbleCallbackFailure(false);
        bytes32 before = _ledger();
        vm.prank(address(_actor));
        _core.settleRepay(address(_asset), 1, _recipient, _borrower);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Authorized nested settlement reaches Core lock"
        );
        assertEq(_position().debtOhm, 1, "Outer principal transition occurs once");
    }

    // Scenarios: BLCORE-SETTLE-REPAY-C02.
    function test_givenOhmCallback_whenPropagated() public {
        CoreCallbackToken implementation = new CoreCallbackToken();
        vm.etch(address(_ohm), address(implementation).code);
        CoreCallbackToken token = CoreCallbackToken(address(_ohm));
        _deposit(2000e6);
        _borrow(2);
        vm.prank(_recipient);
        _ohm.approve(address(_core), 2);
        _authorizeCollateralCallback(_actor);
        token.setCallbackFrom(
            address(_core),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_collateral),
                abi.encodeWithSignature(
                    "depositCollateral(address,uint128,address)",
                    address(_asset),
                    uint128(1),
                    _recipient
                )
            )
        );
        token.setCallbackPhases(false, true);
        token.setBubbleCallbackFailure(true);
        bytes32 before = _ledger();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(address(_actor));
        _core.settleRepay(address(_asset), 1, _recipient, _borrower);
        assertEq(
            _ledger(),
            before,
            "Propagated OHM callback rolls back principal, delivery and Inventory"
        );
    }

    // Scenarios: BLCORE-SETTLE-REPAY-P02.
    function test_givenShortIncomingReceipt_whenSettled_reverts() public {
        CoreCallbackToken implementation = new CoreCallbackToken();
        vm.etch(address(_ohm), address(implementation).code);
        CoreCallbackToken token = CoreCallbackToken(address(_ohm));
        _deposit(100);
        _borrow(2);
        vm.prank(_recipient);
        _ohm.approve(address(_core), 2);
        token.setCallbackFrom(
            address(_core),
            address(token),
            abi.encodeWithSignature("burn(address,uint256)", address(_inventory), uint256(1))
        );
        token.setCallbackPhases(false, true);
        bytes32 before = _ledger();
        uint256 allowance = token.allowance(_recipient, address(_core));
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(token),
                address(_inventory),
                uint256(1),
                uint256(0)
            )
        );
        vm.prank(address(_actor));
        _core.settleRepay(address(_asset), 1, _recipient, _borrower);
        assertEq(_ledger(), before, "Inexact mandatory receipt rolls back custody and accounting");
        assertEq(
            token.allowance(_recipient, address(_core)),
            allowance,
            "Allowance restored on failure"
        );
        assertTrue(token.callbackEnabled(), "Callback state rolled back with transfer");
    }

    // Scenarios: BLCORE-SETTLE-REPAY-P02.
    function test_givenExcessIncomingReceipt_whenSettled_reverts() public {
        CoreCallbackToken implementation = new CoreCallbackToken();
        vm.etch(address(_ohm), address(implementation).code);
        CoreCallbackToken token = CoreCallbackToken(address(_ohm));
        _deposit(100);
        _borrow(2);
        vm.prank(_recipient);
        _ohm.approve(address(_core), 2);
        token.setCallbackFrom(
            address(_core),
            address(token),
            abi.encodeWithSignature("mint(address,uint256)", address(_inventory), uint256(1))
        );
        token.setCallbackPhases(false, true);
        bytes32 before = _ledger();
        uint256 allowance = token.allowance(_recipient, address(_core));
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(token),
                address(_inventory),
                uint256(1),
                uint256(2)
            )
        );
        vm.prank(address(_actor));
        _core.settleRepay(address(_asset), 1, _recipient, _borrower);
        assertEq(_ledger(), before, "Inexact mandatory receipt rolls back custody and accounting");
        assertEq(
            token.allowance(_recipient, address(_core)),
            allowance,
            "Allowance restored on failure"
        );
        assertTrue(token.callbackEnabled(), "Callback state rolled back with transfer");
    }

    // Scenarios: BLCORE-SETTLE-REPAY-I02.
    function test_whenOverpaymentMaximumSeed_reverts() public {
        test_givenOverpayment_whenRepaid_reverts(type(uint128).max);
    }
}
