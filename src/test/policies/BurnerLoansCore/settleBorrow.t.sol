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
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {CoreService} from "./fixtures/CoreService.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions, Kernel, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansCoreSettleBorrowTest is BurnerLoansCoreTest {
    CoreService internal _actor;

    function setUp() public override {
        super.setUp();
        _actor = _service();
        _rolesAdmin.grantRole(BL_DEBT_POLICY_ROLE, address(_actor));
    }

    // Scenarios: BLCORE-SETTLE-BORROW-A02.
    function test_whenCallerLacksSettlementRole_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, BL_DEBT_POLICY_ROLE));
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_DEBT_POLICY_ROLE)
        );
        vm.prank(caller_);
        _core.settleBorrow(
            IBurnerLoansCore.BorrowRequest(address(0), address(0), address(0), address(0), 0, 0, 0)
        );
        assertEq(_state(), before, "Unauthorized instruction has no effects");
    }

    // Scenarios: BLCORE-SETTLE-BORROW-A03.
    function test_givenOnlySiblingRole_whenSettled_reverts() public {
        CoreService sibling = _service();
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(sibling));
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_DEBT_POLICY_ROLE)
        );
        vm.prank(address(sibling));
        _core.settleBorrow(
            IBurnerLoansCore.BorrowRequest(address(0), address(0), address(0), address(0), 0, 0, 0)
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-A04.
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

    // Scenarios: BLCORE-SETTLE-BORROW-L01.
    function test_givenCoreDisabled_whenSettled_reverts() public {
        _core.disable("");
        bytes32 before = _state();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(_actor));
        _core.settleBorrow(
            IBurnerLoansCore.BorrowRequest(address(0), address(0), address(0), address(0), 0, 0, 0)
        );
        assertEq(_state(), before, "Disabled Core rejects before inputs");
    }

    // Scenarios: BLCORE-SETTLE-BORROW-L02, BLCORE-SETTLE-BORROW-L03.
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
        _core.settleBorrow(
            IBurnerLoansCore.BorrowRequest(address(0), address(0), address(0), address(0), 0, 0, 0)
        );
        assertEq(_state(), before, "Own inactivity precedes local state and inputs");
    }

    // Scenarios: BLCORE-SETTLE-BORROW-D01.
    function test_givenCallerInactive_whenSettled() public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_actor));
        test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer(false, address(_core));
    }

    // Scenarios: BLCORE-SETTLE-BORROW-D02.
    function test_givenRoleHoldingEOA_whenSettled(address caller_) public {
        vm.assume(caller_.code.length == 0 && caller_ != address(0));
        _grantRole(BL_DEBT_POLICY_ROLE, caller_);
        _settleAsCaller(caller_);
    }

    // Scenarios: BLCORE-SETTLE-BORROW-A01.
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
        vm.prank(caller_);
        _core.settleBorrow(
            IBurnerLoansCore.BorrowRequest(
                address(_asset),
                _borrower,
                _borrower,
                _recipient,
                1,
                uint48(vm.getBlockTimestamp() + 30 days),
                0
            )
        );
        assertEq(_position().debtOhm, 1, "Role-holding caller originates the requested debt");
    }

    // Scenarios: BLCORE-SETTLE-BORROW-D03.
    function test_givenOriginationsDisabled_whenBorrowed_reverts() public {
        _deposit(2000e6);
        _config.setAssetOriginationsEnabled(address(_asset), false);
        bytes32 before = _ledger();
        vm.expectRevert(
            abi.encodeWithSelector(
                IFLOANv1.FLOAN_OriginationsDisabled.selector,
                _core.marketId(address(_asset))
            )
        );
        vm.prank(address(_actor));
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 0));
        assertEq(
            _ledger(),
            before,
            "Borrow failure rolls back debt, mandatory fee and Inventory funding"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-I01.
    function test_givenPastMaturity_whenBorrowed_reverts(uint48 maturity_) public {
        _deposit(2000e6);
        maturity_ = _bounds48(maturity_, 0, uint48(vm.getBlockTimestamp()));
        bytes32 before = _ledger();
        vm.expectRevert(
            abi.encodeWithSelector(
                IFLOANv1.FLOAN_InvalidMaturity.selector,
                uint48(vm.getBlockTimestamp()),
                maturity_
            )
        );
        vm.prank(address(_actor));
        _core.settleBorrow(_request(1, maturity_, 0));
        assertEq(
            _ledger(),
            before,
            "Borrow failure rolls back debt, mandatory fee and Inventory funding"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-I01.
    function test_whenPastMaturityBoundarySeeds_reverts() public {
        uint48 now_ = uint48(vm.getBlockTimestamp());
        uint256 snapshot = vm.snapshotState();
        test_givenPastMaturity_whenBorrowed_reverts(0);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenPastMaturity_whenBorrowed_reverts(now_ - 1);
        vm.revertToState(snapshot);
        test_givenPastMaturity_whenBorrowed_reverts(now_);
    }

    // Scenarios: BLCORE-SETTLE-BORROW-I02.
    function test_givenChangedActiveMaturity_whenBorrowed_reverts() public {
        _deposit(2000e6);
        _borrow(1);
        uint48 old = _position().maturity;
        bytes32 before = _ledger();
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMaturity.selector, old, old + 1)
        );
        vm.prank(address(_actor));
        _core.settleBorrow(_request(1, old + 1, 0));
        assertEq(
            _ledger(),
            before,
            "Borrow failure rolls back debt, mandatory fee and Inventory funding"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-N01.
    function test_givenZeroAmount_whenBorrowed_reverts() public {
        _deposit(2000e6);
        bytes32 before = _ledger();
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        vm.prank(address(_actor));
        _core.settleBorrow(_request(0, uint48(vm.getBlockTimestamp() + 30 days), 0));
        assertEq(
            _ledger(),
            before,
            "Borrow failure rolls back debt, mandatory fee and Inventory funding"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-N02.
    function test_givenHorizonExceeded_whenBorrowed_reverts(uint48 maturity_) public {
        _deposit(2000e6);
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
        _core.settleBorrow(_request(1, maturity_, 0));
        assertEq(
            _ledger(),
            before,
            "Borrow failure rolls back debt, mandatory fee and Inventory funding"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-N03.
    function test_givenCapExceeded_whenBorrowed_reverts() public {
        _deposit(2000e6);
        _config.setAssetDebtCap(address(_asset), 1);
        bytes32 before = _ledger();
        vm.expectRevert(
            abi.encodeWithSelector(
                IFLOANv1.FLOAN_PrincipalCapExceeded.selector,
                _core.marketId(address(_asset)),
                uint128(1)
            )
        );
        vm.prank(address(_actor));
        _core.settleBorrow(_request(2, uint48(vm.getBlockTimestamp() + 30 days), 0));
        assertEq(
            _ledger(),
            before,
            "Borrow failure rolls back debt, mandatory fee and Inventory funding"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-P01.
    function test_givenMissingPosition_whenBorrowed_reverts() public {
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_NoDebt.selector);
        vm.prank(address(_actor));
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 0));
        assertEq(
            _ledger(),
            before,
            "Borrow failure rolls back debt, mandatory fee and Inventory funding"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-P02.
    function test_givenMandatoryFeeFailure_whenBorrowed_reverts() public {
        _deposit(2000e6);
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
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 1));
        assertEq(
            _ledger(),
            before,
            "Borrow failure rolls back debt, mandatory fee and Inventory funding"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-P05.
    function test_givenInventoryFailureAfterFee_whenBorrowed_reverts() public {
        _deposit(2000e6);
        vm.mockCallRevert(
            address(_inventory),
            abi.encodeWithSignature("draw(address,uint128)", _recipient, 1),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        bytes32 before = _ledger();
        vm.expectRevert(DependencyFailed.selector);
        vm.prank(address(_actor));
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 1));
        assertEq(
            _ledger(),
            before,
            "Borrow failure rolls back debt, mandatory fee and Inventory funding"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-I03.
    function test_givenZeroFee_whenBorrowed(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, type(uint128).max));
        _deposit(1);
        _config.setAssetDebtCap(address(_asset), type(uint128).max);
        _inventory.setGlobalDebtCap(type(uint128).max);
        uint256 before = _ohm.balanceOf(_recipient);
        vm.expectCall(
            address(_payout),
            abi.encodeWithSignature("creditFee(address,uint256)"),
            uint64(0)
        );
        uint48 due = uint48(vm.getBlockTimestamp() + 30 days);
        vm.prank(address(_actor));
        (uint128 principal, uint48 maturity) = _core.settleBorrow(_request(amount_, due, 0));
        assertEq(principal, amount_, "Exact principal returned");
        assertEq(maturity, due, "Exact maturity returned");
        assertEq(_ohm.balanceOf(_recipient) - before, amount_, "Inventory delivers principal once");
        assertEq(_core.totalActiveDebtOhm(), amount_, "Canonical principal increases");
        assertEq(_inventory.activePrincipalOhm(), amount_, "Inventory principal agrees");
        assertEq(_rawPosition().principalDrawn, amount_, "Debt episode tracks draw");
    }

    // Scenarios: BLCORE-SETTLE-BORROW-I03.
    function test_whenPrincipalBoundarySeeds() public {
        test_givenZeroFee_whenBorrowed(type(uint128).max);
    }

    // Scenarios: BLCORE-SETTLE-BORROW-P04.
    function test_givenOptionalPayoutFailure_whenBorrowed() public {
        _deposit(2000e6);
        address treasury = _payout.treasury();
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSignature("transfer(address,uint256)", treasury, 17),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        uint256 payerBefore = _asset.balanceOf(_borrower);
        vm.prank(address(_actor));
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 17));
        (uint256 fee, , uint256 total) = _payout.payoutReserves(address(_asset));
        assertEq(fee, 17, "Failed optional route remains in fee bucket");
        assertEq(total, 17, "Exact reserved aggregate");
        assertEq(_asset.balanceOf(address(_payout)), 17, "Pending fee fully backed");
        assertEq(
            _asset.balanceOf(_borrower),
            payerBefore - 17,
            "Mandatory fee collected exactly once"
        );
        assertEq(_position().debtOhm, 1, "Optional delivery failure does not cancel borrow");
    }

    function _request(
        uint128 amount_,
        uint48 maturity_,
        uint256 fee_
    ) internal view returns (IBurnerLoansCore.BorrowRequest memory) {
        return
            IBurnerLoansCore.BorrowRequest(
                address(_asset),
                _borrower,
                _borrower,
                _recipient,
                amount_,
                maturity_,
                fee_
            );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-C01.
    function test_givenSettlementCallback_whenCaught() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
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
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 17));
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Otherwise-authorized nested Settlement reaches settlement guard"
        );
        assertEq(_position().debtOhm, 1, "One outer debt draw");
        assertEq(_ohm.balanceOf(_recipient), 1, "One Inventory delivery");
    }

    // Scenarios: BLCORE-SETTLE-BORROW-C02.
    function test_givenSettlementCallback_whenPropagated() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
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
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 17));
        assertEq(
            _ledger(),
            before,
            "Propagated mandatory callback rolls back accounting and custody"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-C01.
    function test_givenAdminMutationCallback_whenCaught() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
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
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 17));
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Otherwise-authorized nested AdminMutation reaches settlement guard"
        );
        assertEq(_position().debtOhm, 1, "One outer debt draw");
        assertEq(_ohm.balanceOf(_recipient), 1, "One Inventory delivery");
    }

    // Scenarios: BLCORE-SETTLE-BORROW-C02.
    function test_givenAdminMutationCallback_whenPropagated() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
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
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 17));
        assertEq(
            _ledger(),
            before,
            "Propagated mandatory callback rolls back accounting and custody"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-C01.
    function test_givenPayoutRecoveryCallback_whenCaught() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
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
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 17));
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Otherwise-authorized nested PayoutRecovery reaches settlement guard"
        );
        assertEq(_position().debtOhm, 1, "One outer debt draw");
        assertEq(_ohm.balanceOf(_recipient), 1, "One Inventory delivery");
    }

    // Scenarios: BLCORE-SETTLE-BORROW-C02.
    function test_givenPayoutRecoveryCallback_whenPropagated() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
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
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 17));
        assertEq(
            _ledger(),
            before,
            "Propagated mandatory callback rolls back accounting and custody"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-C05.
    function test_givenOptionalFeeCallback_whenCaught() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
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
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 17));
        uint256 expected = 17;
        uint256 pending = _payout.pendingPayout(address(_asset), _payout.treasury());
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Payout local guard rejects nested recovery"
        );
        assertEq(pending, 0, "Caught optional callback permits delivery");
    }

    // Scenarios: BLCORE-SETTLE-BORROW-C06.
    function test_givenOptionalFeeCallback_whenPropagated() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
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
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 17));
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

    // Scenarios: BLCORE-SETTLE-BORROW-C03.
    function test_givenOhmCallback_whenCaught() public {
        CoreCallbackToken implementation = new CoreCallbackToken();
        vm.etch(address(_ohm), address(implementation).code);
        CoreCallbackToken token = CoreCallbackToken(address(_ohm));
        _deposit(2000e6);
        _authorizeCollateralCallback(_actor);
        token.setCallbackFrom(
            address(_inventory),
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
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 0));
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Authorized nested settlement reaches Core lock"
        );
        assertEq(_position().debtOhm, 1, "Outer principal transition occurs once");
    }

    // Scenarios: BLCORE-SETTLE-BORROW-C04.
    function test_givenOhmCallback_whenPropagated() public {
        CoreCallbackToken implementation = new CoreCallbackToken();
        vm.etch(address(_ohm), address(implementation).code);
        CoreCallbackToken token = CoreCallbackToken(address(_ohm));
        _deposit(2000e6);
        _authorizeCollateralCallback(_actor);
        token.setCallbackFrom(
            address(_inventory),
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
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 0));
        assertEq(
            _ledger(),
            before,
            "Propagated OHM callback rolls back principal, delivery and Inventory"
        );
    }

    // Scenarios: BLCORE-SETTLE-BORROW-P03.
    function test_givenShortIncomingReceipt_whenSettled_reverts() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        token.setCallbackFrom(
            address(_core),
            address(token),
            abi.encodeWithSignature("burn(address,uint256)", address(_payout), uint256(1))
        );
        token.setCallbackPhases(false, true);
        bytes32 before = _ledger();
        uint256 allowance = token.allowance(_borrower, address(_core));
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(token),
                address(_payout),
                uint256(1),
                uint256(0)
            )
        );
        vm.prank(address(_actor));
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 1));
        assertEq(_ledger(), before, "Inexact mandatory receipt rolls back custody and accounting");
        assertEq(
            token.allowance(_borrower, address(_core)),
            allowance,
            "Allowance restored on failure"
        );
        assertTrue(token.callbackEnabled(), "Callback state rolled back with transfer");
    }

    // Scenarios: BLCORE-SETTLE-BORROW-P03.
    function test_givenExcessIncomingReceipt_whenSettled_reverts() public {
        CoreCallbackToken token = _callbackAsset();
        _deposit(100);
        token.setCallbackFrom(
            address(_core),
            address(token),
            abi.encodeWithSignature("mint(address,uint256)", address(_payout), uint256(1))
        );
        token.setCallbackPhases(false, true);
        bytes32 before = _ledger();
        uint256 allowance = token.allowance(_borrower, address(_core));
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(token),
                address(_payout),
                uint256(1),
                uint256(2)
            )
        );
        vm.prank(address(_actor));
        _core.settleBorrow(_request(1, uint48(vm.getBlockTimestamp() + 30 days), 1));
        assertEq(_ledger(), before, "Inexact mandatory receipt rolls back custody and accounting");
        assertEq(
            token.allowance(_borrower, address(_core)),
            allowance,
            "Allowance restored on failure"
        );
        assertTrue(token.callbackEnabled(), "Callback state rolled back with transfer");
    }

    // Scenarios: BLCORE-SETTLE-BORROW-I03.
    function test_whenOnePrincipalSeed() public {
        test_givenZeroFee_whenBorrowed(1);
    }
}
