// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {BL_COLLATERAL_POLICY_ROLE, BL_DEBT_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {CoreService} from "./fixtures/CoreService.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions, Kernel, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansCoreSettleExtendTest is BurnerLoansCoreTest {
    CoreService internal _actor;

    function setUp() public override {
        super.setUp();
        _actor = _service();
        _rolesAdmin.grantRole(BL_DEBT_POLICY_ROLE, address(_actor));
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-A02.
    function test_whenCallerLacksSettlementRole_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, BL_DEBT_POLICY_ROLE));
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_DEBT_POLICY_ROLE)
        );
        vm.prank(caller_);
        _core.settleExtend(address(0), address(0), address(0), 0, 0);
        assertEq(_state(), before, "Unauthorized instruction has no effects");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-A03.
    function test_givenOnlySiblingRole_whenSettled_reverts() public {
        CoreService sibling = _service();
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(sibling));
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_DEBT_POLICY_ROLE)
        );
        vm.prank(address(sibling));
        _core.settleExtend(address(0), address(0), address(0), 0, 0);
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-A04.
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

    // Scenarios: BLCORE-SETTLE-EXTEND-L01.
    function test_givenCoreDisabled_whenSettled_reverts() public {
        _core.disable("");
        bytes32 before = _state();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(_actor));
        _core.settleExtend(address(0), address(0), address(0), 0, 0);
        assertEq(_state(), before, "Disabled Core rejects before inputs");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-L02, BLCORE-SETTLE-EXTEND-L03.
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
        _core.settleExtend(address(0), address(0), address(0), 0, 0);
        assertEq(_state(), before, "Own inactivity precedes local state and inputs");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-D01.
    function test_givenCallerInactive_whenSettled() public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_actor));
        test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer(false, address(_core));
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-D02.
    function test_givenRoleHoldingEOA_whenSettled(address caller_) public {
        vm.assume(caller_.code.length == 0 && caller_ != address(0));
        _grantRole(BL_DEBT_POLICY_ROLE, caller_);
        _settleAsCaller(caller_);
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-A01.
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
        vm.prank(caller_);
        _core.settleExtend(
            address(_asset),
            _borrower,
            _borrower,
            uint48(vm.getBlockTimestamp() + 31 days),
            0
        );
        assertEq(
            _position().maturity,
            vm.getBlockTimestamp() + 31 days,
            "Role-holding caller extends maturity"
        );
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-D03.
    function test_givenOriginationsDisabled_whenExtended_reverts() public {
        _deposit(2000e6);
        _borrow(1);
        _config.setAssetOriginationsEnabled(address(_asset), false);
        bytes32 before = _ledger();
        vm.expectRevert(
            abi.encodeWithSelector(
                IFLOANv1.FLOAN_OriginationsDisabled.selector,
                _core.marketId(address(_asset))
            )
        );
        vm.prank(address(_actor));
        _core.settleExtend(
            address(_asset),
            _borrower,
            _borrower,
            uint48(vm.getBlockTimestamp() + 31 days),
            0
        );
        assertEq(_ledger(), before, "Extension failure preserves prior maturity, fees and debt");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-I01.
    function test_givenNoDebt_whenExtended_reverts() public {
        _deposit(1);
        bytes32 before = _ledger();
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        vm.prank(address(_actor));
        _core.settleExtend(
            address(_asset),
            _borrower,
            _borrower,
            uint48(vm.getBlockTimestamp() + 31 days),
            0
        );
        assertEq(_ledger(), before, "Extension failure preserves prior maturity, fees and debt");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-I02.
    function test_givenNotLater_whenExtended_reverts(uint48 maturity_) public {
        _deposit(2000e6);
        _borrow(1);
        uint48 old = _position().maturity;
        maturity_ = _bounds48(maturity_, 0, old);
        bytes32 before = _ledger();
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMaturity.selector, old, maturity_)
        );
        vm.prank(address(_actor));
        _core.settleExtend(address(_asset), _borrower, _borrower, maturity_, 0);
        assertEq(_ledger(), before, "Extension failure preserves prior maturity, fees and debt");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-I03.
    function test_givenExpiredNewMaturity_whenExtended_reverts() public {
        _deposit(2000e6);
        _borrow(1);
        uint48 old = _position().maturity;
        vm.warp(uint256(old) + 2);
        bytes32 before = _ledger();
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMaturity.selector, old, old + 1)
        );
        vm.prank(address(_actor));
        _core.settleExtend(address(_asset), _borrower, _borrower, old + 1, 0);
        assertEq(_ledger(), before, "Extension failure preserves prior maturity, fees and debt");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-N01.
    function test_givenHorizonExceeded_whenExtended_reverts(uint48 maturity_) public {
        _deposit(2000e6);
        _borrow(1);
        uint48 maximum = uint48(vm.getBlockTimestamp() + 90 days);
        maturity_ = _bounds48(maturity_, maximum + 1, type(uint48).max);
        bytes32 before = _ledger();
        vm.expectRevert(
            abi.encodeWithSelector(
                IFLOANv1.FLOAN_MaturityHorizonExceeded.selector,
                maturity_,
                maximum
            )
        );
        vm.prank(address(_actor));
        _core.settleExtend(address(_asset), _borrower, _borrower, maturity_, 0);
        assertEq(_ledger(), before, "Extension failure preserves prior maturity, fees and debt");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-P01.
    function test_givenMissingPosition_whenExtended_reverts() public {
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_NoDebt.selector);
        vm.prank(address(_actor));
        _core.settleExtend(
            address(_asset),
            _borrower,
            _borrower,
            uint48(vm.getBlockTimestamp() + 31 days),
            0
        );
        assertEq(_ledger(), before, "Extension failure preserves prior maturity, fees and debt");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-P03.
    function test_givenMandatoryFeeFailure_whenExtended_reverts() public {
        _deposit(2000e6);
        _borrow(1);
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                _borrower,
                address(_payout),
                1
            ),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        bytes32 before = _ledger();
        vm.expectRevert(DependencyFailed.selector);
        vm.prank(address(_actor));
        _core.settleExtend(
            address(_asset),
            _borrower,
            _borrower,
            uint48(vm.getBlockTimestamp() + 31 days),
            1
        );
        assertEq(_ledger(), before, "Extension failure preserves prior maturity, fees and debt");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-I04, BLCORE-SETTLE-EXTEND-P02.
    function test_givenValidMaturity_whenExtended(uint48 maturity_, uint128 fee_) public {
        _deposit(2000e6);
        _borrow(1);
        uint48 old = _position().maturity;
        maturity_ = _bounds48(maturity_, old + 1, uint48(vm.getBlockTimestamp() + 90 days));
        _asset.mint(_borrower, fee_);
        uint256 payerBefore = _asset.balanceOf(_borrower);
        uint256 principal = _core.totalActiveDebtOhm();
        uint256 collateral = _position().depositedCollateral;
        if (fee_ == 0)
            vm.expectCall(
                address(_payout),
                abi.encodeWithSignature("creditFee(address,uint256)"),
                uint64(0)
            );
        vm.prank(address(_actor));
        uint48 result = _core.settleExtend(address(_asset), _borrower, _borrower, maturity_, fee_);
        assertEq(result, maturity_, "Exact new maturity returned");
        assertEq(_position().maturity, maturity_, "Stored maturity agrees");
        assertEq(_core.totalActiveDebtOhm(), principal, "Extension creates no principal");
        assertEq(_position().depositedCollateral, collateral, "Extension preserves collateral");
        assertEq(_asset.balanceOf(_borrower), payerBefore - fee_, "Mandatory fee paid once");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-P04.
    function test_givenOptionalPayoutFailure_whenExtended() public {
        _deposit(2000e6);
        _borrow(1);
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSignature("transfer(address,uint256)", _payout.treasury(), 17),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        uint48 maturity = uint48(vm.getBlockTimestamp() + 31 days);
        vm.prank(address(_actor));
        _core.settleExtend(address(_asset), _borrower, _borrower, maturity, 17);
        (uint256 fee, , uint256 total) = _payout.payoutReserves(address(_asset));
        assertEq(fee, 17, "Pending fee retained");
        assertEq(total, 17, "Reserve aggregate backed");
        assertEq(_asset.balanceOf(address(_payout)), 17, "Exact fee backing");
        assertEq(
            _position().maturity,
            maturity,
            "Optional delivery failure does not cancel extension"
        );
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-C01.
    function test_givenSettlementCallback_whenCaught() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
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
        _core.settleExtend(
            address(_asset),
            _borrower,
            _borrower,
            uint48(vm.getBlockTimestamp() + 31 days),
            17
        );
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Otherwise-authorized nested Settlement reaches settlement guard"
        );
        assertEq(_position().maturity, vm.getBlockTimestamp() + 31 days, "One outer extension");
        assertEq(_position().debtOhm, 1, "No extra debt");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-C02.
    function test_givenSettlementCallback_whenPropagated() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
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
        _core.settleExtend(
            address(_asset),
            _borrower,
            _borrower,
            uint48(vm.getBlockTimestamp() + 31 days),
            17
        );
        assertEq(
            _ledger(),
            before,
            "Propagated mandatory callback rolls back accounting and custody"
        );
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-C01.
    function test_givenAdminMutationCallback_whenCaught() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_actor));
        token.setCallbackFrom(
            address(_core),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_core),
                abi.encodeWithSignature("setGracePeriod(uint32)", uint32(1))
            )
        );
        token.setCallbackPhases(false, true);
        token.setBubbleCallbackFailure(false);
        bytes32 before = _ledger();
        vm.prank(address(_actor));
        _core.settleExtend(
            address(_asset),
            _borrower,
            _borrower,
            uint48(vm.getBlockTimestamp() + 31 days),
            17
        );
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Otherwise-authorized nested AdminMutation reaches settlement guard"
        );
        assertEq(_position().maturity, vm.getBlockTimestamp() + 31 days, "One outer extension");
        assertEq(_position().debtOhm, 1, "No extra debt");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-C02.
    function test_givenAdminMutationCallback_whenPropagated() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_actor));
        token.setCallbackFrom(
            address(_core),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_core),
                abi.encodeWithSignature("setGracePeriod(uint32)", uint32(1))
            )
        );
        token.setCallbackPhases(false, true);
        token.setBubbleCallbackFailure(true);
        bytes32 before = _ledger();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(address(_actor));
        _core.settleExtend(
            address(_asset),
            _borrower,
            _borrower,
            uint48(vm.getBlockTimestamp() + 31 days),
            17
        );
        assertEq(
            _ledger(),
            before,
            "Propagated mandatory callback rolls back accounting and custody"
        );
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-C01.
    function test_givenPayoutRecoveryCallback_whenCaught() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_actor));
        token.setCallbackFrom(
            address(_core),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_payout),
                abi.encodeWithSignature("rescue(address,address)", address(_asset), _recipient)
            )
        );
        token.setCallbackPhases(false, true);
        token.setBubbleCallbackFailure(false);
        bytes32 before = _ledger();
        vm.prank(address(_actor));
        _core.settleExtend(
            address(_asset),
            _borrower,
            _borrower,
            uint48(vm.getBlockTimestamp() + 31 days),
            17
        );
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Otherwise-authorized nested PayoutRecovery reaches settlement guard"
        );
        assertEq(_position().maturity, vm.getBlockTimestamp() + 31 days, "One outer extension");
        assertEq(_position().debtOhm, 1, "No extra debt");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-C02.
    function test_givenPayoutRecoveryCallback_whenPropagated() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_actor));
        token.setCallbackFrom(
            address(_core),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_payout),
                abi.encodeWithSignature("rescue(address,address)", address(_asset), _recipient)
            )
        );
        token.setCallbackPhases(false, true);
        token.setBubbleCallbackFailure(true);
        bytes32 before = _ledger();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(address(_actor));
        _core.settleExtend(
            address(_asset),
            _borrower,
            _borrower,
            uint48(vm.getBlockTimestamp() + 31 days),
            17
        );
        assertEq(
            _ledger(),
            before,
            "Propagated mandatory callback rolls back accounting and custody"
        );
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-C03.
    function test_givenOptionalFeeCallback_whenCaught() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_actor));
        token.setCallbackFrom(
            address(_payout),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_payout),
                abi.encodeWithSignature("rescue(address,address)", address(_asset), _recipient)
            )
        );
        token.setCallbackPhases(true, false);
        token.setCallbackTransferRecipient(_payout.treasury());
        token.setBubbleCallbackFailure(false);
        vm.prank(address(_actor));
        _core.settleExtend(
            address(_asset),
            _borrower,
            _borrower,
            uint48(vm.getBlockTimestamp() + 31 days),
            17
        );
        uint256 expected = 17;
        uint256 pending = _payout.pendingPayout(address(_asset), _payout.treasury());
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Payout local guard rejects nested recovery"
        );
        assertEq(pending, 0, "Caught optional callback permits delivery");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-C04.
    function test_givenOptionalFeeCallback_whenPropagated() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        _borrow(1);
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_actor));
        token.setCallbackFrom(
            address(_payout),
            address(_actor),
            abi.encodeWithSelector(
                CoreService.forward.selector,
                address(_payout),
                abi.encodeWithSignature("rescue(address,address)", address(_asset), _recipient)
            )
        );
        token.setCallbackPhases(true, false);
        token.setCallbackTransferRecipient(_payout.treasury());
        token.setBubbleCallbackFailure(true);
        vm.prank(address(_actor));
        _core.settleExtend(
            address(_asset),
            _borrower,
            _borrower,
            uint48(vm.getBlockTimestamp() + 31 days),
            17
        );
        uint256 expected = 17;
        uint256 pending = _payout.pendingPayout(address(_asset), _payout.treasury());
        assertEq(pending, expected, "Optional callback propagation defers exactly one entitlement");
        assertEq(token.balanceOf(address(_payout)), expected, "Deferred entitlement backed");
        token.setCallbackFrom(address(0), address(0), bytes(""));
        uint256 before = token.balanceOf(_payout.treasury());
        uint256 paid = _payout.transferPendingPayout(address(_asset), _payout.treasury());
        assertEq(paid, expected, "Later retry pays exact entitlement");
        assertEq(token.balanceOf(_payout.treasury()), before + expected, "Recipient credited once");
        assertEq(
            _payout.transferPendingPayout(address(_asset), _payout.treasury()),
            0,
            "Second retry cannot pay again"
        );
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-N01.
    function test_whenMaturityMaximumSeed_reverts() public {
        test_givenHorizonExceeded_whenExtended_reverts(type(uint48).max);
    }
}
