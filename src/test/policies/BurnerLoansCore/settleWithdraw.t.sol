// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {BL_COLLATERAL_POLICY_ROLE, BL_DEBT_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {CoreService} from "./fixtures/CoreService.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions, Kernel, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansCoreSettleWithdrawTest is BurnerLoansCoreTest {
    CoreService internal _actor;

    function setUp() public override {
        super.setUp();
        _actor = _service();
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(_actor));
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-A02.
    function test_whenCallerLacksSettlementRole_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, BL_COLLATERAL_POLICY_ROLE));
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_COLLATERAL_POLICY_ROLE)
        );
        vm.prank(caller_);
        _core.settleWithdraw(address(0), 0, address(0), address(0));
        assertEq(_state(), before, "Unauthorized instruction has no effects");
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-A03.
    function test_givenOnlySiblingRole_whenSettled_reverts() public {
        CoreService sibling = _service();
        _rolesAdmin.grantRole(BL_DEBT_POLICY_ROLE, address(sibling));
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_COLLATERAL_POLICY_ROLE)
        );
        vm.prank(address(sibling));
        _core.settleWithdraw(address(0), 0, address(0), address(0));
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-A04.
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

    // Scenarios: BLCORE-SETTLE-WITHDRAW-L01.
    function test_givenCoreDisabled_whenSettled_reverts() public {
        _core.disable("");
        bytes32 before = _state();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(_actor));
        _core.settleWithdraw(address(0), 0, address(0), address(0));
        assertEq(_state(), before, "Disabled Core rejects before inputs");
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-L02, BLCORE-SETTLE-WITHDRAW-L03.
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
        _core.settleWithdraw(address(0), 0, address(0), address(0));
        assertEq(_state(), before, "Own inactivity precedes local state and inputs");
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-D01.
    function test_givenCallerInactive_whenSettled() public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_actor));
        test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer(false, address(_core));
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-D02.
    function test_givenRoleHoldingEOA_whenSettled(address caller_) public {
        vm.assume(caller_.code.length == 0 && caller_ != address(0));
        _grantRole(BL_COLLATERAL_POLICY_ROLE, caller_);
        _settleAsCaller(caller_);
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-A01.
    function test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer(
        bool disabled_,
        address bound_
    ) public {
        if (disabled_) _actor.disable("");
        _actor.setCore(bound_);
        _settleAsCaller(address(_actor));
    }

    function _settleAsCaller(address caller_) internal {
        _deposit(2);
        vm.prank(caller_);
        _core.settleWithdraw(address(_asset), 1, _borrower, _recipient);
        assertEq(_position().depositedCollateral, 1, "Role-holding caller withdraws collateral");
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-N01.
    function test_givenZeroAmount_whenWithdrawn_reverts() public {
        _deposit(2);
        bytes32 before = _ledger();
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        vm.prank(address(_actor));
        _core.settleWithdraw(address(_asset), 0, _borrower, _recipient);
        assertEq(_ledger(), before, "Failed redemption rolls back collateral and custody");
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-N02.
    function test_givenAboveCollateral_whenWithdrawn_reverts(uint128 amount_) public {
        _deposit(2);
        amount_ = uint128(bound(amount_, 3, type(uint128).max));
        bytes32 before = _ledger();
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        vm.prank(address(_actor));
        _core.settleWithdraw(address(_asset), amount_, _borrower, _recipient);
        assertEq(_ledger(), before, "Failed redemption rolls back collateral and custody");
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-P01.
    function test_givenMissingPosition_whenWithdrawn_reverts() public {
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_NoDebt.selector);
        vm.prank(address(_actor));
        _core.settleWithdraw(address(_asset), 1, _borrower, _recipient);
        assertEq(_ledger(), before, "Failed redemption rolls back collateral and custody");
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-I01.
    function test_givenZeroOutput_whenWithdrawn_reverts() public {
        _deposit(2);
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("withdraw((address,uint8,address,address,uint256,bool),bool)"),
            abi.encode(address(_asset), uint256(0))
        );
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ZeroCollateralWithdrawal.selector);
        vm.prank(address(_actor));
        _core.settleWithdraw(address(_asset), 1, _borrower, _recipient);
        assertEq(_ledger(), before, "Failed redemption rolls back collateral and custody");
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-I02.
    function test_givenUnexpectedOutputToken_whenWithdrawn_reverts() public {
        _deposit(2);
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("withdraw((address,uint8,address,address,uint256,bool),bool)"),
            abi.encode(address(_ohm), uint256(1))
        );
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_InvalidSettlement.selector);
        vm.prank(address(_actor));
        _core.settleWithdraw(address(_asset), 1, _borrower, _recipient);
        assertEq(_ledger(), before, "Failed redemption rolls back collateral and custody");
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-P02.
    function test_givenActualOutputDifferentFromDebit_whenWithdrawn(
        uint128 debit_,
        uint256 output_
    ) public {
        debit_ = uint128(bound(debit_, 1, type(uint128).max));
        output_ = bound(output_, 1, type(uint256).max);
        _deposit(debit_);
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("withdraw((address,uint8,address,address,uint256,bool),bool)"),
            abi.encode(address(_asset), output_)
        );
        vm.prank(address(_actor));
        (address token, uint256 output, uint128 remaining) = _core.settleWithdraw(
            address(_asset),
            debit_,
            _borrower,
            _recipient
        );
        assertEq(token, address(_asset), "Actual output token returned");
        assertEq(
            output,
            output_,
            "Actual dependency output forwarded without nominal substitution"
        );
        assertEq(remaining, 0, "FLOAN debits credited units");
        assertEq(_position().depositedCollateral, 0, "Stored collateral agrees with return");
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-P02.
    function test_givenRealCustody_whenWithdrawn(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, type(uint128).max));
        _deposit(amount_);
        uint256 before = _asset.balanceOf(_recipient);
        uint256 liabilities = _depositManager.getOperatorLiabilities(
            IERC20(address(_asset)),
            address(_core)
        );
        vm.prank(address(_actor));
        (address token, uint256 output, uint128 remaining) = _core.settleWithdraw(
            address(_asset),
            amount_,
            _borrower,
            _recipient
        );
        assertEq(token, address(_asset), "Raw-asset output");
        assertEq(output, amount_, "No vault conversion in raw-asset fixture");
        assertEq(remaining, 0, "Full withdrawal clears collateral");
        assertEq(_asset.balanceOf(_recipient) - before, output, "Authoritative recipient delta");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            liabilities - amount_,
            "Custody liabilities reduced once"
        );
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-D03.
    function test_givenPayoutRecipientAndInexactDelta_whenWithdrawn_reverts() public {
        _deposit(2);
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("withdraw((address,uint8,address,address,uint256,bool),bool)"),
            abi.encode(address(_asset), uint256(1))
        );
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_InvalidSettlement.selector);
        vm.prank(address(_actor));
        _core.settleWithdraw(address(_asset), 1, _borrower, address(_payout));
        assertEq(_ledger(), before, "Old balance cannot substitute for new receipt");
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-P02.
    function test_whenWithdrawalBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenRealCustody_whenWithdrawn(1);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenRealCustody_whenWithdrawn(type(uint128).max);
        vm.revertToState(snapshot);
        test_givenActualOutputDifferentFromDebit_whenWithdrawn(1, type(uint256).max);
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-C01.
    function test_givenSettlementCallback_whenCaught() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _authorizeCollateralCallback(_actor);
        token.setCallbackFrom(
            address(_depositManager),
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
        token.setCallbackPhases(true, false);
        token.setBubbleCallbackFailure(false);
        bytes32 before = _ledger();
        vm.prank(address(_actor));
        _core.settleWithdraw(address(_asset), 1, _borrower, _recipient);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Otherwise-authorized nested Settlement reaches settlement guard"
        );
        assertEq(_position().depositedCollateral, 99, "One outer collateral debit");
        assertEq(token.balanceOf(_recipient), 1, "One outer recipient delivery");
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-C02.
    function test_givenSettlementCallback_whenPropagated() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _authorizeCollateralCallback(_actor);
        token.setCallbackFrom(
            address(_depositManager),
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
        token.setCallbackPhases(true, false);
        token.setBubbleCallbackFailure(true);
        bytes32 before = _ledger();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(address(_actor));
        _core.settleWithdraw(address(_asset), 1, _borrower, _recipient);
        assertEq(
            _ledger(),
            before,
            "Propagated mandatory callback rolls back accounting and custody"
        );
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-N02.
    function test_whenCollateralDebitMaximumSeed_reverts() public {
        test_givenAboveCollateral_whenWithdrawn_reverts(type(uint128).max);
    }
}
