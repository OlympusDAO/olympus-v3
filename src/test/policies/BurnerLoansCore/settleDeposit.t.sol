// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";
import {BL_COLLATERAL_POLICY_ROLE, BL_DEBT_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {CoreService} from "./fixtures/CoreService.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions, Kernel, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansCoreSettleDepositTest is BurnerLoansCoreTest {
    CoreService internal _actor;

    function setUp() public override {
        super.setUp();
        _actor = _service();
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(_actor));
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-I04.
    function test_whenMalformedEconomicRequest_thenAbiDecodingRejectsBeforeRoleCheck() public {
        bytes32 beforeState = _state();
        // A static request tuple has the same word order as these flat ABI values.
        // A uint256 word deliberately exceeds the request's narrower field type.
        bytes memory instruction = abi.encodeWithSelector(
            IBurnerLoansCore.settleDeposit.selector,
            address(_asset),
            uint256(type(uint128).max) + 1,
            _borrower,
            _borrower,
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

    // Scenarios: BLCORE-SETTLE-DEPOSIT-A02.
    function test_givenLiveGrant_whenUnadmittedCallerReusesContext_reverts(
        address caller_,
        bool owner_
    ) public {
        vm.assume(!_roles.hasRole(caller_, BL_COLLATERAL_POLICY_ROLE));
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
            1
        );
        IBurnerLoansCore.DepositRequest memory request = IBurnerLoansCore.DepositRequest({
            asset: address(_asset),
            amount: 1,
            payer: _borrower,
            borrower: _borrower
        });
        bytes32 beforeState = _ledger();
        uint256 pairEpoch = _auth.pairEpochs(_borrower, _recipient);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_COLLATERAL_POLICY_ROLE)
        );
        vm.prank(caller_);
        _core.settleDeposit(request, operator, original);
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

    // Scenarios: BLCORE-SETTLE-DEPOSIT-A02.
    function test_whenCallerLacksSettlementRole_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, BL_COLLATERAL_POLICY_ROLE));
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_COLLATERAL_POLICY_ROLE)
        );
        vm.prank(caller_);
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(0),
                amount: 0,
                payer: address(0),
                borrower: address(0)
            }),
            address(0),
            _ownerAuthContext()
        );
        assertEq(_state(), before, "Unauthorized instruction has no effects");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-A03.
    function test_givenOnlySiblingRole_whenSettled_reverts() public {
        CoreService sibling = _service();
        _rolesAdmin.grantRole(BL_DEBT_POLICY_ROLE, address(sibling));
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_COLLATERAL_POLICY_ROLE)
        );
        vm.prank(address(sibling));
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(0),
                amount: 0,
                payer: address(0),
                borrower: address(0)
            }),
            address(0),
            _ownerAuthContext()
        );
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-A04.
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

    // Scenarios: BLCORE-SETTLE-DEPOSIT-L01.
    function test_givenCoreDisabled_whenSettled_reverts() public {
        _core.disable("");
        bytes32 before = _state();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(_actor));
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(0),
                amount: 0,
                payer: address(0),
                borrower: address(0)
            }),
            address(0),
            _ownerAuthContext()
        );
        assertEq(_state(), before, "Disabled Core rejects before inputs");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-L02, BLCORE-SETTLE-DEPOSIT-L03.
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
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(0),
                amount: 0,
                payer: address(0),
                borrower: address(0)
            }),
            address(0),
            _ownerAuthContext()
        );
        assertEq(_state(), before, "Own inactivity precedes local state and inputs");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-D01.
    function test_givenCallerInactive_whenSettled() public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_actor));
        test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer(false, address(_core));
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-D02.
    function test_givenRoleHoldingEOA_whenSettled(address caller_) public {
        vm.assume(caller_.code.length == 0 && caller_ != address(0));
        _grantRole(BL_COLLATERAL_POLICY_ROLE, caller_);
        _settleAsCaller(caller_);
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-A01.
    function test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer(
        bool disabled_,
        address bound_
    ) public {
        if (disabled_) _actor.disable("");
        _actor.setCore(bound_);
        _settleAsCaller(address(_actor));
    }

    function _settleAsCaller(address caller_) internal {
        vm.prank(caller_);
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(_position().depositedCollateral, 1, "Role-holding caller credits collateral");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-P01.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function test_whenCreditedDepositIsPositive(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, type(uint128).max));
        _asset.mint(_borrower, amount_);
        uint256 payerBefore = _asset.balanceOf(_borrower);
        vm.prank(address(_actor));
        (uint128 credit, uint128 collateral) = _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: amount_,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(credit, amount_, "Idle custody credits exact incoming amount");
        assertEq(collateral, amount_, "Canonical collateral uses actual credit");
        assertEq(_asset.balanceOf(_borrower), payerBefore - amount_, "Payer debited exactly once");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            amount_,
            "Custody principal equals credit"
        );
        assertEq(
            _floan.getMarketCollateral(_core.marketId(address(_asset))),
            amount_,
            "Aggregate collateral matches position"
        );
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: BLCORE-SETTLE-DEPOSIT-P01.
    function test_whenDepositAmountSeeds() public {
        uint256 saved = vm.snapshotState();
        test_whenCreditedDepositIsPositive(1);
        vm.revertToState(saved);
        test_whenCreditedDepositIsPositive(type(uint128).max);
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-P02.
    function test_givenCollateralOnlyPosition_whenOriginationsArePaused(bool originations_) public {
        _deposit(2000e6);
        _config.setAssetOriginationsEnabled(address(_asset), originations_);
        IBurnerLoansCore.Position memory previous = _position();
        uint64 count = _floan.getPositionCount();
        vm.prank(address(_actor));
        (uint128 credit, uint128 collateral) = _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(credit, 1, "Top-up credits actual output");
        assertEq(collateral, previous.depositedCollateral + 1, "Existing collateral increases");
        assertEq(_floan.getPositionCount(), count, "No duplicate canonical position");
        assertEq(_position().debtOhm, previous.debtOhm, "Principal unchanged");
        assertEq(_position().maturity, previous.maturity, "Maturity unchanged");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-P07.
    function test_givenDebtBearingPosition_whenOriginationsArePaused(bool originations_) public {
        _deposit(2000e6);
        _borrow(100e9);
        _config.setAssetOriginationsEnabled(address(_asset), originations_);
        IBurnerLoansCore.Position memory previous = _position();
        uint64 count = _floan.getPositionCount();
        vm.prank(address(_actor));
        (uint128 credit, uint128 collateral) = _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(credit, 1, "Top-up credits actual output");
        assertEq(collateral, previous.depositedCollateral + 1, "Existing collateral increases");
        assertEq(_floan.getPositionCount(), count, "No duplicate canonical position");
        assertEq(_position().debtOhm, previous.debtOhm, "Principal unchanged");
        assertEq(_position().maturity, previous.maturity, "Maturity unchanged");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-P02.
    function test_whenCollateralOnlyTopUpOriginationStatesSeeded() public {
        uint256 snapshot = vm.snapshotState();
        test_givenCollateralOnlyPosition_whenOriginationsArePaused(true);
        vm.revertToState(snapshot);
        test_givenCollateralOnlyPosition_whenOriginationsArePaused(false);
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-P07.
    function test_whenDebtBearingTopUpOriginationStatesSeeded() public {
        uint256 snapshot = vm.snapshotState();
        test_givenDebtBearingPosition_whenOriginationsArePaused(true);
        vm.revertToState(snapshot);
        test_givenDebtBearingPosition_whenOriginationsArePaused(false);
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-I03.
    function test_givenOriginationsDisabledAndNoPosition_whenDeposited() public {
        _config.setAssetOriginationsEnabled(address(_asset), false);
        uint64 count = _floan.getPositionCount();
        uint256 custody = _asset.balanceOf(address(_depositManager));
        vm.prank(address(_actor));
        (uint128 credit, uint128 collateral) = _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(credit, 1, "Origination pause permits actual deposit credit");
        assertEq(collateral, 1, "First deposit initializes collateral");
        assertEq(_floan.getPositionCount(), count + 1, "First deposit creates one position");
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            custody + 1,
            "Custody receives deposit"
        );
        assertEq(_position().depositedCollateral, 1, "Canonical position records actual credit");
        assertEq(_position().debtOhm, 0, "Deposit originates no debt");
        assertEq(_position().maturity, 0, "Collateral-only position has no maturity");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-I01.
    function test_givenZeroActualCredit_whenDeposited_reverts() public {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("deposit((address,uint8,address,uint256,bool))"),
            abi.encode(uint256(0), uint256(0))
        );
        bytes32 before = _state();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ZeroCollateralCredit.selector);
        vm.prank(address(_actor));
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(_state(), before, "Zero credit rolls back incoming transfer and approval");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-N01.
    function test_givenCreditExceedsUint128_whenDeposited_reverts(uint256 credit_) public {
        credit_ = bound(credit_, uint256(type(uint128).max) + 1, type(uint256).max);
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("deposit((address,uint8,address,uint256,bool))"),
            abi.encode(uint256(0), credit_)
        );
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(128),
                credit_
            )
        );
        vm.prank(address(_actor));
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(_state(), before, "Oversized credit never creates collateral");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-P03.
    function test_givenPreexistingDonation_whenDeposited() public {
        _asset.mint(address(_core), 17);
        vm.prank(address(_actor));
        (uint128 credit, ) = _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(credit, 1, "Donation is not fresh credited collateral");
        assertEq(_asset.balanceOf(address(_core)), 17, "Old donation stays separate");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-I02.
    function test_givenNoReceiptManager_whenDeposited() public {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("getReceiptTokenManager()"),
            abi.encode(address(0))
        );
        vm.prank(address(_actor));
        (uint128 credit, ) = _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(credit, 1, "Optional receipt approval is skipped");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-D03.
    function test_givenExistingReceiptApproval_whenDeposited() public {
        address receipts = address(_depositManager.getReceiptTokenManager());
        uint256 receipt = _depositManager.getReceiptTokenId(
            IERC20(address(_asset)),
            1,
            address(_core)
        );
        vm.mockCall(
            receipts,
            abi.encodeWithSignature(
                "allowance(address,address,uint256)",
                address(_core),
                address(_depositManager),
                receipt
            ),
            abi.encode(type(uint256).max)
        );
        vm.expectCall(
            receipts,
            abi.encodeWithSignature("approve(address,uint256,uint256)"),
            uint64(0)
        );
        vm.prank(address(_actor));
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-D04.
    function test_givenFreshReceiptApproval_whenDeposited() public {
        address receipts = address(_depositManager.getReceiptTokenManager());
        uint256 receipt = _depositManager.getReceiptTokenId(
            IERC20(address(_asset)),
            1,
            address(_core)
        );
        vm.expectCall(
            receipts,
            abi.encodeWithSignature(
                "approve(address,uint256,uint256)",
                address(_depositManager),
                receipt,
                type(uint256).max
            ),
            uint64(1)
        );
        vm.prank(address(_actor));
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-P04.
    function test_givenRejectedReceiptApproval_whenDeposited_reverts() public {
        address receipts = address(_depositManager.getReceiptTokenManager());
        uint256 receipt = _depositManager.getReceiptTokenId(
            IERC20(address(_asset)),
            1,
            address(_core)
        );
        vm.mockCall(
            receipts,
            abi.encodeWithSignature("approve(address,uint256,uint256)"),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_ReceiptApprovalFailed.selector,
                receipts
            )
        );
        vm.prank(address(_actor));
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-C01.
    function test_givenSettlementCallback_whenCaught() public {
        CoreCallbackToken token = _callbackAsset();
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
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Otherwise-authorized nested Settlement reaches settlement guard"
        );
        assertEq(_position().depositedCollateral, 1, "One outer collateral credit");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-C02.
    function test_givenSettlementCallback_whenPropagated() public {
        CoreCallbackToken token = _callbackAsset();
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
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(
            _ledger(),
            before,
            "Propagated mandatory callback rolls back accounting and custody"
        );
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-P05.
    function test_givenShortIncomingReceipt_whenSettled_reverts() public {
        CoreCallbackToken token = _callbackAsset();
        token.setCallbackFrom(
            address(_core),
            address(token),
            abi.encodeWithSignature("burn(address,uint256)", address(_core), uint256(1))
        );
        token.setCallbackPhases(false, true);
        bytes32 before = _ledger();
        uint256 allowance = token.allowance(_borrower, address(_core));
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(token),
                address(_core),
                uint256(1),
                uint256(0)
            )
        );
        vm.prank(address(_actor));
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(_ledger(), before, "Inexact mandatory receipt rolls back custody and accounting");
        assertEq(
            token.allowance(_borrower, address(_core)),
            allowance,
            "Allowance restored on failure"
        );
        assertTrue(token.callbackEnabled(), "Callback state rolled back with transfer");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-P06.
    function test_givenExcessIncomingReceipt_whenSettled_reverts() public {
        CoreCallbackToken token = _callbackAsset();
        token.setCallbackFrom(
            address(_core),
            address(token),
            abi.encodeWithSignature("mint(address,uint256)", address(_core), uint256(1))
        );
        token.setCallbackPhases(false, true);
        bytes32 before = _ledger();
        uint256 allowance = token.allowance(_borrower, address(_core));
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(token),
                address(_core),
                uint256(1),
                uint256(2)
            )
        );
        vm.prank(address(_actor));
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(_ledger(), before, "Inexact mandatory receipt rolls back custody and accounting");
        assertEq(
            token.allowance(_borrower, address(_core)),
            allowance,
            "Allowance restored on failure"
        );
        assertTrue(token.callbackEnabled(), "Callback state rolled back with transfer");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-N01.
    function test_whenCreditOverflowBoundarySeeds_reverts() public {
        test_givenCreditExceedsUint128_whenDeposited_reverts(uint256(type(uint128).max) + 1);
        test_givenCreditExceedsUint128_whenDeposited_reverts(type(uint256).max);
    }
}
// forge-lint: disable-end(unused-return)
