// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

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

    // Scenarios: BLCORE-SETTLE-EXTEND-I05.
    function test_whenMalformedEconomicRequest_thenAbiDecodingRejectsBeforeRoleCheck() public {
        bytes32 beforeState = _state();
        // A static request tuple has the same word order as these flat ABI values.
        // A uint256 word deliberately exceeds the request's narrower field type.
        bytes memory instruction = abi.encodeWithSelector(
            IBurnerLoansCore.settleExtend.selector,
            address(_asset),
            _borrower,
            _borrower,
            uint256(type(uint48).max) + 1,
            uint256(0),
            address(0),
            uint256(0),
            _borrower,
            _ownerAuthContext()
        );
        vm.prank(_recipient);
        (bool success, bytes memory result) = address(_core).call(instruction);
        assertFalse(success, "Malformed economic request cannot settle");
        // The pinned compiler's ABI decoder rejects before entering role-guarded code.
        assertEq(result.length, 0, "Malformed request fails in the ABI decoder");
        assertEq(_state(), beforeState, "Malformed request leaves custody and positions unchanged");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-A02.
    function test_givenLiveGrant_whenUnadmittedCallerReusesContext_reverts(
        address caller_,
        bool owner_
    ) public {
        vm.assume(!_roles.hasRole(caller_, BL_DEBT_POLICY_ROLE));
        vm.assume(caller_ != _borrower && caller_ != _recipient);
        _deposit(2000e6);
        _borrow(100e9);
        _approveOperator(_borrower, _recipient, type(uint48).max);
        address operator = owner_ ? _borrower : _recipient;
        // The attacker can read a real stamp; the view result is not settlement authority.
        vm.prank(caller_);
        IBurnerLoansCore.AuthorizationContext memory original = _operatorAuthContext(
            _borrower,
            operator,
            8
        );
        IBurnerLoansCore.ExtendRequest memory request = IBurnerLoansCore.ExtendRequest({
            asset: address(_asset),
            borrower: _borrower,
            payer: _borrower,
            maturity: _position().maturity + 30 days,
            protocolFee: 0,
            referrer: address(0),
            referralFee: 0
        });
        bytes32 beforeState = _ledger();
        uint256 pairEpoch = _auth.pairEpochs(_borrower, _recipient);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_DEBT_POLICY_ROLE)
        );
        vm.prank(caller_);
        _core.settleExtend(request, operator, original);
        assertEq(
            _ledger(),
            beforeState,
            "Publicly readable authority cannot move custody or change a position"
        );
        assertEq(
            _auth.pairEpochs(_borrower, _recipient),
            pairEpoch,
            "Rejected impersonation preserves the genuine grant"
        );
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-A02.
    function test_whenCallerLacksSettlementRole_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, BL_DEBT_POLICY_ROLE));
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_DEBT_POLICY_ROLE)
        );
        vm.prank(caller_);
        _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(0),
                borrower: address(0),
                payer: address(0),
                maturity: 0,
                protocolFee: 0,
                referrer: address(0),
                referralFee: 0
            }),
            address(0),
            _ownerAuthContext()
        );
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
        _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(0),
                borrower: address(0),
                payer: address(0),
                maturity: 0,
                protocolFee: 0,
                referrer: address(0),
                referralFee: 0
            }),
            address(0),
            _ownerAuthContext()
        );
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-A04.
    function test_givenWrongKernelCaller_whenSettled() public {
        Kernel other = new Kernel();
        vm.prank(address(_kernel));
        _actor.changeKernel(other);
        vm.expectCall(address(_actor), abi.encodeWithSelector(_core.kernel.selector), uint64(0));
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
        _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(0),
                borrower: address(0),
                payer: address(0),
                maturity: 0,
                protocolFee: 0,
                referrer: address(0),
                referralFee: 0
            }),
            address(0),
            _ownerAuthContext()
        );
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
        _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(0),
                borrower: address(0),
                payer: address(0),
                maturity: 0,
                protocolFee: 0,
                referrer: address(0),
                referralFee: 0
            }),
            address(0),
            _ownerAuthContext()
        );
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

    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function _settleAsCaller(address caller_) internal {
        _deposit(2000e6);
        _borrow(2);
        vm.prank(caller_);
        _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(_asset),
                borrower: _borrower,
                payer: _borrower,
                maturity: uint48(vm.getBlockTimestamp() + 31 days),
                protocolFee: 0,
                referrer: address(0),
                referralFee: 0
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(
            _position().maturity,
            vm.getBlockTimestamp() + 31 days,
            "Role-holding caller extends maturity"
        );
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: BLCORE-SETTLE-EXTEND-D03.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
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
            IBurnerLoansCore.ExtendRequest({
                asset: address(_asset),
                borrower: _borrower,
                payer: _borrower,
                maturity: uint48(vm.getBlockTimestamp() + 31 days),
                protocolFee: 0,
                referrer: address(0),
                referralFee: 0
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(_ledger(), before, "Extension failure preserves prior maturity, fees and debt");
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: BLCORE-SETTLE-EXTEND-I01.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function test_givenNoDebt_whenExtended_reverts() public {
        _deposit(1);
        bytes32 before = _ledger();
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        vm.prank(address(_actor));
        _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(_asset),
                borrower: _borrower,
                payer: _borrower,
                maturity: uint48(vm.getBlockTimestamp() + 31 days),
                protocolFee: 0,
                referrer: address(0),
                referralFee: 0
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(_ledger(), before, "Extension failure preserves prior maturity, fees and debt");
    }

    // forge-lint: disable-end(unsafe-typecast)

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
        _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(_asset),
                borrower: _borrower,
                payer: _borrower,
                maturity: maturity_,
                protocolFee: 0,
                referrer: address(0),
                referralFee: 0
            }),
            _borrower,
            _ownerAuthContext()
        );
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
        _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(_asset),
                borrower: _borrower,
                payer: _borrower,
                maturity: old + 1,
                protocolFee: 0,
                referrer: address(0),
                referralFee: 0
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(_ledger(), before, "Extension failure preserves prior maturity, fees and debt");
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-N01.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
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
        _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(_asset),
                borrower: _borrower,
                payer: _borrower,
                maturity: maturity_,
                protocolFee: 0,
                referrer: address(0),
                referralFee: 0
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(_ledger(), before, "Extension failure preserves prior maturity, fees and debt");
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: BLCORE-SETTLE-EXTEND-P01.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function test_givenMissingPosition_whenExtended_reverts() public {
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_NoDebt.selector);
        vm.prank(address(_actor));
        _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(_asset),
                borrower: _borrower,
                payer: _borrower,
                maturity: uint48(vm.getBlockTimestamp() + 31 days),
                protocolFee: 0,
                referrer: address(0),
                referralFee: 0
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(_ledger(), before, "Extension failure preserves prior maturity, fees and debt");
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: BLCORE-SETTLE-EXTEND-P03.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function test_givenMandatoryFeeFailure_whenExtended_reverts() public {
        _deposit(2000e6);
        _borrow(1);
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSelector(IERC20.transferFrom.selector, _borrower, address(_payout), 1),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        bytes32 before = _ledger();
        vm.expectRevert(DependencyFailed.selector);
        vm.prank(address(_actor));
        _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(_asset),
                borrower: _borrower,
                payer: _borrower,
                maturity: uint48(vm.getBlockTimestamp() + 31 days),
                protocolFee: 1,
                referrer: address(0),
                referralFee: 0
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(_ledger(), before, "Extension failure preserves prior maturity, fees and debt");
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: BLCORE-SETTLE-EXTEND-I04, BLCORE-SETTLE-EXTEND-P02.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
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
                abi.encodeWithSelector(IBurnerLoansPayout.creditFee.selector),
                uint64(0)
            );
        vm.prank(address(_actor));
        uint48 result = _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(_asset),
                borrower: _borrower,
                payer: _borrower,
                maturity: maturity_,
                protocolFee: fee_,
                referrer: address(0),
                referralFee: 0
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(result, maturity_, "Exact new maturity returned");
        assertEq(_position().maturity, maturity_, "Stored maturity agrees");
        assertEq(_core.totalActiveDebtOhm(), principal, "Extension creates no principal");
        assertEq(_position().depositedCollateral, collateral, "Extension preserves collateral");
        assertEq(_asset.balanceOf(_borrower), payerBefore - fee_, "Mandatory fee paid once");
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: BLCORE-SETTLE-EXTEND-P04.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function test_givenOptionalPayoutFailure_whenExtended() public {
        _deposit(2000e6);
        _borrow(1);
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSelector(IERC20.transfer.selector, _payout.treasury(), 17),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        uint48 maturity = uint48(vm.getBlockTimestamp() + 31 days);
        vm.prank(address(_actor));
        _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(_asset),
                borrower: _borrower,
                payer: _borrower,
                maturity: maturity,
                protocolFee: 17,
                referrer: address(0),
                referralFee: 0
            }),
            _borrower,
            _ownerAuthContext()
        );
        (uint256 fee, , , , uint256 total) = _payout.pendingAmounts(address(_asset));
        assertEq(fee, 17, "Pending fee retained");
        assertEq(total, 17, "Reserve aggregate backed");
        assertEq(_asset.balanceOf(address(_payout)), 17, "Exact fee backing");
        assertEq(
            _position().maturity,
            maturity,
            "Optional delivery failure does not cancel extension"
        );
    }

    // forge-lint: disable-end(unsafe-typecast)

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
                abi.encodeWithSelector(
                    IBurnerLoansCollateral.depositCollateral.selector,
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
        _core.settleExtend(_callbackExtendRequest(), _borrower, _ownerAuthContext());
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
                abi.encodeWithSelector(
                    IBurnerLoansCollateral.depositCollateral.selector,
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
        _core.settleExtend(_callbackExtendRequest(), _borrower, _ownerAuthContext());
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
                abi.encodeWithSelector(IGracePeriod.setGracePeriod.selector, uint32(1))
            )
        );
        token.setCallbackPhases(false, true);
        token.setBubbleCallbackFailure(false);
        bytes32 before = _ledger();
        vm.prank(address(_actor));
        _core.settleExtend(_callbackExtendRequest(), _borrower, _ownerAuthContext());
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
                abi.encodeWithSelector(IGracePeriod.setGracePeriod.selector, uint32(1))
            )
        );
        token.setCallbackPhases(false, true);
        token.setBubbleCallbackFailure(true);
        bytes32 before = _ledger();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(address(_actor));
        _core.settleExtend(_callbackExtendRequest(), _borrower, _ownerAuthContext());
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
                abi.encodeWithSelector(
                    IBurnerLoansCore.rescue.selector,
                    address(_asset),
                    _recipient
                )
            )
        );
        token.setCallbackPhases(false, true);
        token.setBubbleCallbackFailure(false);
        bytes32 before = _ledger();
        vm.prank(address(_actor));
        _core.settleExtend(_callbackExtendRequest(), _borrower, _ownerAuthContext());
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
                abi.encodeWithSelector(
                    IBurnerLoansCore.rescue.selector,
                    address(_asset),
                    _recipient
                )
            )
        );
        token.setCallbackPhases(false, true);
        token.setBubbleCallbackFailure(true);
        bytes32 before = _ledger();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(address(_actor));
        _core.settleExtend(_callbackExtendRequest(), _borrower, _ownerAuthContext());
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
                abi.encodeWithSelector(
                    IBurnerLoansCore.rescue.selector,
                    address(_asset),
                    _recipient
                )
            )
        );
        token.setCallbackPhases(true, false);
        token.setCallbackTransferRecipient(_payout.treasury());
        token.setBubbleCallbackFailure(false);
        vm.prank(address(_actor));
        _core.settleExtend(_callbackExtendRequest(), _borrower, _ownerAuthContext());
        uint256 expected = 17;
        uint256 pending = _payout.pendingRecipientAmount(address(_asset), _payout.treasury());
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
                abi.encodeWithSelector(
                    IBurnerLoansCore.rescue.selector,
                    address(_asset),
                    _recipient
                )
            )
        );
        token.setCallbackPhases(true, false);
        token.setCallbackTransferRecipient(_payout.treasury());
        token.setBubbleCallbackFailure(true);
        vm.prank(address(_actor));
        _core.settleExtend(_callbackExtendRequest(), _borrower, _ownerAuthContext());
        uint256 expected = 17;
        uint256 pending = _payout.pendingRecipientAmount(address(_asset), _payout.treasury());
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

    // Scenarios: BLCORE-SETTLE-EXTEND-P05.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function test_whenFeeComponentsForwarded(uint256 total_, uint256 protocol_) public {
        _deposit(2000e6);
        _borrow(1);
        total_ = bound(total_, 1, type(uint256).max - _asset.totalSupply());
        protocol_ = bound(protocol_, 0, total_);
        uint256 referral = total_ - protocol_;
        address referrer = address(0xFEED);
        _asset.mint(_recipient, total_);
        vm.prank(_recipient);
        _asset.approve(address(_core), total_);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            uint64(0)
        );
        bytes memory credit = abi.encodeCall(
            IBurnerLoansPayout.creditFee,
            (address(_asset), protocol_, referrer, referral)
        );
        vm.mockCall(address(_payout), credit, bytes(""));
        vm.expectCall(address(_payout), credit, uint64(1));
        uint256 payerBalance = _asset.balanceOf(_recipient);
        uint256 payoutBalance = _asset.balanceOf(address(_payout));
        uint256 coreBalance = _asset.balanceOf(address(_core));
        vm.prank(address(_actor));
        _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(_asset),
                borrower: _borrower,
                payer: _recipient,
                maturity: uint48(vm.getBlockTimestamp() + 31 days),
                protocolFee: protocol_,
                referrer: referrer,
                referralFee: referral
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(
            _asset.balanceOf(_recipient),
            payerBalance - total_,
            "Exact combined fee collected from independent payer"
        );
        assertEq(
            _asset.balanceOf(address(_payout)),
            payoutBalance + total_,
            "Selected Payout receives both fee components"
        );
        assertEq(_asset.balanceOf(address(_core)), coreBalance, "Core retains no fee tokens");
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: BLCORE-SETTLE-EXTEND-N02.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function test_whenFeeComponentSumOverflows_reverts(
        uint256 protocol_,
        uint256 referral_
    ) public {
        _deposit(2000e6);
        _borrow(1);
        protocol_ = bound(protocol_, 1, type(uint256).max);
        uint256 referral = bound(referral_, type(uint256).max - protocol_ + 1, type(uint256).max);
        bytes32 beforeState = _ledger();
        vm.expectCall(
            address(_asset),
            abi.encodeWithSelector(_asset.transferFrom.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_payout),
            abi.encodeWithSelector(IBurnerLoansPayout.creditFee.selector),
            uint64(0)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_FeeOverflow.selector,
                protocol_,
                referral
            )
        );
        vm.prank(address(_actor));
        _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(_asset),
                borrower: _borrower,
                payer: _borrower,
                maturity: uint48(vm.getBlockTimestamp() + 31 days),
                protocolFee: protocol_,
                referrer: address(0xFEED),
                referralFee: referral
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(
            _ledger(),
            beforeState,
            "Overflow restores position and all settlement accounting"
        );
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: BLCORE-SETTLE-EXTEND-P05.
    function test_whenLiteralComponentFunding() public {
        test_whenFeeComponentsForwarded(101, 76);
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-P05.
    function test_whenOnlyReferralFunded() public {
        test_whenFeeComponentsForwarded(1, 0);
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-P05.
    function test_whenOnlyProtocolFunded() public {
        test_whenFeeComponentsForwarded(1, 1);
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-N02.
    function test_whenMinimumProtocolOverflows_reverts() public {
        test_whenFeeComponentSumOverflows_reverts(1, type(uint256).max);
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-N02.
    function test_whenMaximumProtocolOverflows_reverts() public {
        test_whenFeeComponentSumOverflows_reverts(type(uint256).max, 1);
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-P05.
    function test_whenMaximumFundableProtocolComponent() public {
        uint256 maximum = type(uint256).max - _asset.totalSupply() - 2000e6;
        test_whenFeeComponentsForwarded(maximum, maximum);
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-P05.
    function test_whenMaximumFundableReferralComponent() public {
        uint256 maximum = type(uint256).max - _asset.totalSupply() - 2000e6;
        test_whenFeeComponentsForwarded(maximum, 0);
    }

    function _callbackExtendRequest()
        internal
        view
        returns (IBurnerLoansCore.ExtendRequest memory)
    {
        return
            IBurnerLoansCore.ExtendRequest({
                asset: address(_asset),
                borrower: _borrower,
                payer: _borrower,
                // The controlled fixture clock plus 31 days fits within uint48.
                // forge-lint: disable-next-line(unsafe-typecast)
                maturity: uint48(vm.getBlockTimestamp() + 31 days),
                protocolFee: 17,
                referrer: address(0),
                referralFee: 0
            });
    }
}
// forge-lint: disable-end(unused-return)
