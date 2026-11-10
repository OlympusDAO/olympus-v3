// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {BL_COLLATERAL_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";

// Contracts
import {MockBackingOracle} from "src/test/mocks/MockBackingOracle.sol";
import {BurnerLoansCollateralActionTest} from "./fixtures/BurnerLoansCollateralActionTest.sol";
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralWithdrawCollateralTest is BurnerLoansCollateralActionTest {
    // Scenarios: BLCOL-WITHDRAW-D07.
    function test_givenDepositManagerInactive_whenWithdrawn_reverts()
        public
        givenDebtFreeCollateral
    {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_depositManager));
        _expectWithdrawRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_depositManager)
            ),
            _borrower,
            1
        );
    }

    // Scenarios: BLCOL-WITHDRAW-D05.
    function test_givenDepositManagerPaused_whenWithdrawn_reverts() public givenDebtFreeCollateral {
        _depositManager.disable("");
        _expectWithdrawRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager.selector,
                address(_depositManager)
            ),
            _borrower,
            1
        );
    }

    // Scenarios: BLCOL-WITHDRAW-D06.
    function test_givenDepositPeriodDisabled_whenWithdrawn_thenExitRemainsAvailable()
        public
        givenDebtFreeCollateral
    {
        _depositManager.disableAssetPeriod(IERC20(address(_asset)), 1, address(_core));
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(_asset),
            1,
            _borrower,
            _recipient
        );
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory result = _collateral.withdrawCollateral(
            address(_asset),
            1,
            _borrower,
            _recipient
        );
        assertEq(result.returnAmount, 1, "Disabled deposit period still permits servicing");
        assertEq(abi.encode(result), abi.encode(quote), "Exit quote matches settlement");
        assertEq(_asset.balanceOf(_recipient), 1, "Recipient receives exact raw unit");
    }

    bool internal constant _FINAL_POSITION = true;

    // Scenarios: BLCOL-WITHDRAW-D04.
    function test_givenCoreReportsAnotherKernel_whenWithdrawn_thenKernelMismatch()
        public
        givenDebtFreeCollateral
    {
        address reported = makeAddr("foreignCoreKernel");
        vm.mockCall(address(_core), abi.encodeWithSignature("kernel()"), abi.encode(reported));
        _expectWithdrawRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(_kernel),
                reported
            ),
            _borrower,
            1
        );
    }

    // Scenarios: BLCOL-WITHDRAW-N01, BLCOL-WITHDRAW-N02, BLCOL-WITHDRAW-A01, BLCOL-WITHDRAW-L01.
    function test_givenDebtFreePosition_whenCollateralIsWithdrawn_thenNoPriceIsRequired(
        uint128 amount_
    ) public givenDebtFreeCollateral {
        amount_ = uint128(bound(amount_, 1, 100e6));
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.refreshSnapshot.selector),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory result = _collateral.withdrawCollateral(
            address(_asset),
            amount_,
            _borrower,
            _recipient
        );
        assertEq(
            result.returnAmount,
            amount_,
            "Recipient receives the requested direct collateral"
        );
        assertEq(
            result.remainingDepositedCollateral,
            100e6 - amount_,
            "Returned collateral reflects settlement"
        );
        assertEq(result.resultingHealthFactor, type(uint256).max, "Debt-free exits bypass Risk");
        assertEq(_asset.balanceOf(_recipient), amount_, "Wallet delta agrees with output");
    }

    // Scenarios: BLCOL-WITHDRAW-N03.
    function test_givenDebt_whenPostSettlementRiskValidationFails_thenTransfersAndAccountingRollBack()
        public
        givenDebtBearingPosition
    {
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.validateHealth.selector),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        bytes32 rollbackState = _accountingDigest(address(_asset));
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector);
        vm.prank(_borrower);
        _collateral.previewWithdrawCollateral(address(_asset), 1e6, _borrower, _recipient);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector);
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(_asset), 1e6, _borrower, _recipient);
        assertEq(
            _asset.balanceOf(_recipient),
            0,
            "Failed final health invariant rolls back payout"
        );
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            2000e6,
            "Failed final invariant restores collateral"
        );
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-A06.
    function test_givenDebtFreePosition_whenCallerIsUnauthorized_reverts(
        address caller_
    ) public givenDebtFreeCollateral {
        vm.assume(!_core.isSenderAuthorized(caller_, _borrower));
        _expectWithdrawExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            caller_,
            1
        );
    }

    // Scenarios: BLCOL-WITHDRAW-I01.
    function test_givenCollateral_whenAmountIsZero_reverts() public givenDebtFreeCollateral {
        _expectWithdrawRevert(
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_ZeroAmount.selector),
            _borrower,
            0
        );
    }

    // Scenarios: BLCOL-WITHDRAW-I06.
    function test_givenCollateral_whenAmountExceedsBalance_reverts(
        uint128 amount_
    ) public givenDebtFreeCollateral {
        amount_ = uint128(bound(amount_, 100e6 + 1, type(uint128).max));
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.refreshSnapshot.selector),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        _expectWithdrawRevert(
            abi.encodeWithSelector(
                IBurnerLoansCollateral.BurnerLoans_InsufficientCollateral.selector,
                amount_,
                100e6
            ),
            _borrower,
            amount_
        );
    }

    // Scenarios: BLCOL-WITHDRAW-I02.
    function test_givenCollateral_whenRecipientIsZero_reverts() public givenDebtFreeCollateral {
        _expectInvalidRecipient(
            address(0),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector)
        );
    }

    // Scenarios: BLCOL-WITHDRAW-I05.
    function test_givenCollateral_whenRecipientIsAction_reverts() public givenDebtFreeCollateral {
        _expectInvalidRecipient(
            address(_collateral),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRecipient.selector,
                address(_collateral)
            )
        );
    }

    // Scenarios: BLCOL-WITHDRAW-I03.
    function test_givenCollateral_whenRecipientIsCore_reverts() public givenDebtFreeCollateral {
        _expectInvalidRecipient(
            address(_core),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRecipient.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCOL-WITHDRAW-I04.
    function test_givenCollateral_whenRecipientIsCustody_reverts() public givenDebtFreeCollateral {
        _expectInvalidRecipient(
            address(_payout),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRecipient.selector,
                address(_payout)
            )
        );
    }

    function _expectInvalidRecipient(address recipient_, bytes memory reason_) internal {
        bytes32 beforeState = _accountingDigest(address(_asset));
        vm.expectRevert(reason_);
        vm.prank(_borrower);
        _collateral.previewWithdrawCollateral(address(_asset), 1, _borrower, recipient_);
        assertEq(
            _accountingDigest(address(_asset)),
            beforeState,
            "Rejected quote preserves accounting"
        );
        vm.expectRevert(reason_);
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(_asset), 1, _borrower, recipient_);
        assertEq(
            _accountingDigest(address(_asset)),
            beforeState,
            "Rejected withdrawal preserves accounting"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-L02.
    function test_givenCollateral_whenActionIsDisabled_reverts() public givenDebtFreeCollateral {
        _setPolicyState(_collateral, true, false);
        _expectWithdrawRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector), _borrower, 1);
    }

    // Scenarios: BLCOL-WITHDRAW-L06.
    function test_givenCollateral_whenActionIsInactive_reverts() public givenDebtFreeCollateral {
        _setPolicyState(_collateral, false, true);
        _expectWithdrawRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_collateral)
            ),
            _borrower,
            1
        );
    }

    // Scenarios: BLCOL-WITHDRAW-D01.
    function test_givenCollateral_whenCoreIsDisabled_reverts() public givenDebtFreeCollateral {
        _setPolicyState(_core, true, false);
        _expectWithdrawRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            ),
            _borrower,
            1
        );
    }

    // Scenarios: BLCOL-WITHDRAW-D02.
    function test_givenCollateral_whenCoreIsInactive_reverts() public givenDebtFreeCollateral {
        _setPolicyState(_core, false, true);
        _expectWithdrawRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            ),
            _borrower,
            1
        );
    }

    // Scenarios: BLCOL-WITHDRAW-T02.
    function test_givenUnexpectedWithdrawalToken_whenWithdrawn_thenCollateralDebitRollsBack()
        public
    {
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 100e6, _borrower);
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSelector(IDepositManagerV1_1.withdraw.selector),
            abi.encode(address(_ohm), uint256(1))
        );
        bytes32 rollbackState = _accountingDigest(address(_asset));
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_InvalidSettlement.selector);
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(_asset), 1, _borrower, _recipient);
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            100e6,
            "Unexpected token restores canonical collateral"
        );
        assertEq(_asset.balanceOf(address(_depositManager)), 100e6, "Custody remains intact");
        assertEq(_asset.balanceOf(_recipient), 0, "No output delivered");
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-T05.
    function test_givenWithdrawalTokenReturnsFalse_whenWithdrawn_thenEntireExitRollsBack() public {
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 100e6, _borrower);
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(_asset),
            1,
            _borrower,
            _recipient
        );
        assertEq(quote.returnAmount, 1, "Quote does not attempt actual delivery");
        vm.mockCall(
            address(_asset),
            abi.encodeCall(_asset.transfer, (_recipient, uint256(1))),
            abi.encode(false)
        );
        bytes32 rollbackState = _accountingDigest(address(_asset));
        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(_asset))
        );
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(_asset), 1, _borrower, _recipient);
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            100e6,
            "Failed delivery restores collateral"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            100e6,
            "Failed delivery restores liabilities"
        );
        assertEq(_asset.balanceOf(address(_depositManager)), 100e6, "Underlying remains custodied");
        assertEq(_asset.balanceOf(_recipient), 0, "Recipient receives nothing");
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-A11.
    function test_givenOtherOperatorGrant_whenUnrelatedCallerActs_reverts(
        address caller_,
        uint48 deadline_,
        uint48 now_
    ) public {
        vm.assume(caller_ != _borrower && caller_ != _recipient);
        deadline_ = uint48(bound(deadline_, 2, type(uint48).max));
        _grantOperator(deadline_);
        vm.warp(bound(now_, 1, deadline_));
        _expectWithdrawExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            caller_,
            1
        );
        assertEq(
            _core.authorizationDeadlines(_borrower, _recipient),
            deadline_,
            "Unrelated caller preserves valid grant"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-A07.
    function test_givenCancelledGrant_whenOperatorActs_reverts(address caller_) public {
        vm.assume(caller_ != _borrower);
        vm.startPrank(_borrower);
        _core.setAuthorization(caller_, type(uint48).max);
        _core.cancelAuthorization(caller_);
        vm.stopPrank();
        _expectWithdrawExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            caller_,
            1
        );
    }

    // Scenarios: BLCOL-WITHDRAW-A08.
    function test_givenExpiredGrant_whenOperatorActs_reverts(
        uint48 deadline_,
        uint256 now_
    ) public {
        deadline_ = uint48(bound(deadline_, 1, type(uint48).max));
        vm.warp(1);
        vm.prank(_borrower);
        _core.setAuthorization(_recipient, deadline_);
        now_ = bound(now_, uint256(deadline_) + 1, type(uint256).max);
        vm.warp(now_);
        _expectWithdrawExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            _recipient,
            1
        );
    }

    // Scenarios: BLCOL-WITHDRAW-L06, BLCOL-WITHDRAW-L07, BLCOL-WITHDRAW-L08, BLCOL-WITHDRAW-L09, BLCOL-WITHDRAW-L10, BLCOL-WITHDRAW-L11, BLCOL-WITHDRAW-L12, BLCOL-WITHDRAW-L13.
    function test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified(
        address caller_,
        bool enabled_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        _depositAsset(_asset, 7, _borrower);
        _setPolicyState(_collateral, false, enabled_);
        _setPolicyState(_core, coreActive_, coreEnabled_);
        bytes memory reason = abi.encodeWithSelector(
            IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
            address(_collateral)
        );
        _expectWithdrawRevert(reason, caller_, 1);
        _expectWithdrawRevert(reason, caller_, 0);
    }

    // Scenarios: BLCOL-WITHDRAW-L02, BLCOL-WITHDRAW-L03, BLCOL-WITHDRAW-L04, BLCOL-WITHDRAW-L05.
    function test_givenDisabledAction_whenInvoked_thenLocalPauseWins(
        address caller_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        _depositAsset(_asset, 7, _borrower);
        _collateral.disable("");
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _expectWithdrawRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector), caller_, 1);
        _expectWithdrawRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector), caller_, 0);
    }

    // Scenarios: BLCOL-WITHDRAW-D01, BLCOL-WITHDRAW-D02, BLCOL-WITHDRAW-D03.
    function test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _depositAsset(_asset, 7, _borrower);
        vm.assume(!active_ || !enabled_);
        _setPolicyState(_core, active_, enabled_);
        _expectWithdrawRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            ),
            caller_,
            1
        );
        _expectWithdrawRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            ),
            caller_,
            0
        );
    }

    // Scenarios: BLCOL-WITHDRAW-A10.
    function test_givenReportedKernelMismatch_whenWithdrawn_thenGetterIsNotRead(
        bool operator_
    ) public {
        vm.mockCall(
            address(_collateral),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0x1234))
        );
        _assertActionWithoutKernelRead(operator_);
    }

    // Scenarios: BLCOL-WITHDRAW-A10.
    function test_givenActionKernelGetterReverts_whenWithdrawn_thenGetterIsNotRead(
        bool operator_
    ) public {
        vm.mockCallRevert(address(_collateral), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        _assertActionWithoutKernelRead(operator_);
    }

    function _assertActionWithoutKernelRead(bool operator_) private {
        address caller = operator_ ? _recipient : _borrower;
        if (operator_) _grantOperator(type(uint48).max);
        vm.expectCall(address(_collateral), abi.encodeWithSignature("kernel()"), uint64(0));
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 7, _borrower);
        _assertDirectWithdrawal(caller, 1, 7);
    }

    // Scenarios: BLCOL-WITHDRAW-N04, BLCOL-WITHDRAW-N05.
    function test_givenDebt_whenRiskReturnsBoundaryHealth_thenExactValueReturned(
        uint256 health_
    ) public givenDebtBearingPosition {
        health_ = bound(health_, 1e18, type(uint256).max);
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.validateHealth.selector),
            abi.encode(health_)
        );
        IBurnerLoansCore.PriceSnapshot memory snapshot = _risk.snapshot(address(_asset));
        vm.expectCall(
            address(_risk),
            abi.encodeCall(
                IBurnerLoansRisk.validateHealth,
                (
                    snapshot,
                    _core.marketId(address(_asset)),
                    uint256(2000e6 - 1),
                    uint256(100e9),
                    _FINAL_POSITION
                )
            ),
            uint64(2)
        );
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(_asset),
            1,
            _borrower,
            _recipient
        );
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory actual = _collateral.withdrawCollateral(
            address(_asset),
            1,
            _borrower,
            _recipient
        );
        assertEq(actual.resultingHealthFactor, health_, "Final Risk result forwarded unchanged");
        assertEq(quote.resultingHealthFactor, health_, "Same final-position validation");
        _assertWithdrawal(quote, address(_asset), 1, 2000e6 - 1, health_);
        _assertWithdrawal(actual, address(_asset), 1, 2000e6 - 1, health_);
        _assertDirectCollateral(2000e6 - 1);
    }

    // Scenarios: BLCOL-WITHDRAW-N04.
    function test_givenDebt_whenHealthExactlyOne_thenAccepted() public {
        test_givenDebt_whenRiskReturnsBoundaryHealth_thenExactValueReturned(1e18);
    }

    // Scenarios: BLCOL-WITHDRAW-A05.
    function test_whenWithdrawalBorrowerZero_reverts(address caller_) public {
        bytes32 rollbackState = _accountingDigest(address(_asset));
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector);
        vm.prank(caller_);
        _collateral.previewWithdrawCollateral(address(_asset), 1, address(0), _recipient);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector);
        vm.prank(caller_);
        _collateral.withdrawCollateral(address(_asset), 1, address(0), _recipient);
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-N06, BLCOL-WITHDRAW-N07.
    function test_givenOriginationsAndInventoryDisabled_whenHealthyWithdrawn_thenServicingOpen()
        public
        givenDebtBearingPosition
    {
        _config.setAssetOriginationsEnabled(address(_asset), false);
        _inventory.disable("");
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(_asset),
            1,
            _borrower,
            _recipient
        );
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory result = _collateral.withdrawCollateral(
            address(_asset),
            1,
            _borrower,
            _recipient
        );
        assertEq(result.returnAmount, 1, "Servicing exit delivered");
        assertEq(
            quote.resultingHealthFactor,
            result.resultingHealthFactor,
            "Servicing preview agrees"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-A02.
    function test_givenOperatorGrant_whenBeforeDeadline_thenAllWithdrawalEffectsAgree(
        uint48 deadline_,
        uint48 now_
    ) public {
        _depositAsset(_asset, 7, _borrower);
        deadline_ = uint48(bound(deadline_, 2, type(uint48).max));
        _grantOperator(deadline_);
        vm.warp(bound(now_, 1, uint256(deadline_) - 1));
        _assertDirectWithdrawal(_recipient, 7, 7);
    }

    // Scenarios: BLCOL-WITHDRAW-A03.
    function test_givenOperatorGrant_whenAtDeadline_thenWithdrawalSucceeds(
        uint48 deadline_
    ) public {
        _depositAsset(_asset, 7, _borrower);
        deadline_ = uint48(bound(deadline_, 1, type(uint48).max));
        _grantOperator(deadline_);
        vm.warp(deadline_);
        _assertDirectWithdrawal(_recipient, 7, 7);
    }

    // Scenarios: BLCOL-WITHDRAW-A02, BLCOL-WITHDRAW-A03, BLCOL-WITHDRAW-A04.
    function test_givenMaximumOperatorDeadline_whenWithdrawalBoundaryTimesUsed() public {
        _depositAsset(_asset, 3, _borrower);
        _grantOperator(type(uint48).max);
        vm.warp(1);
        _assertDirectWithdrawal(_recipient, 1, 3);
        vm.warp(type(uint48).max - 1);
        _assertDirectWithdrawal(_recipient, 1, 2);
        vm.warp(type(uint48).max);
        _assertDirectWithdrawal(_recipient, 1, 1);
    }

    // Scenarios: BLCOL-WITHDRAW-A09.
    function test_givenSettlementRoleRevoked_whenWithdrawing_thenBothPathsReject()
        public
        givenDebtFreeCollateral
    {
        _rolesAdmin.revokeRole(BL_COLLATERAL_POLICY_ROLE, address(_collateral));
        _expectWithdrawRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_COLLATERAL_POLICY_ROLE),
            _borrower,
            1
        );
    }

    // Scenarios: BLCOL-WITHDRAW-N01, BLCOL-WITHDRAW-N02, BLCOL-WITHDRAW-A01, BLCOL-WITHDRAW-L01.
    function test_givenDebtFreePosition_whenFullRangeWithdrawal_thenAllReturnsAndCustodyAgree(
        uint128 collateral_,
        uint128 amount_
    ) public {
        collateral_ = uint128(bound(collateral_, 1, type(uint128).max));
        amount_ = uint128(bound(amount_, 1, collateral_));
        _depositAsset(_asset, collateral_, _borrower);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector),
            hex"deadbeef"
        );
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.refreshSnapshot.selector),
            hex"deadbeef"
        );
        _assertDirectWithdrawal(_borrower, amount_, collateral_);
    }

    // Scenarios: BLCOL-WITHDRAW-N01.
    function test_givenMaximumCollateral_whenFullyWithdrawn_thenAllReturnsAndCustodyAgree() public {
        test_givenDebtFreePosition_whenFullRangeWithdrawal_thenAllReturnsAndCustodyAgree(
            type(uint128).max,
            type(uint128).max
        );
    }

    // Scenarios: BLCOL-WITHDRAW-N01.
    function test_givenOneUnitCollateral_whenFullyWithdrawn_thenAllReturnsAndCustodyAgree() public {
        test_givenDebtFreePosition_whenFullRangeWithdrawal_thenAllReturnsAndCustodyAgree(1, 1);
    }

    // Scenarios: BLCOL-WITHDRAW-I06.
    function test_givenCollateral_whenImmediatelyOverBalance_thenBothPathsReject()
        public
        givenDebtFreeCollateral
    {
        _expectWithdrawRevert(
            abi.encodeWithSelector(
                IBurnerLoansCollateral.BurnerLoans_InsufficientCollateral.selector,
                uint256(100e6 + 1),
                uint256(100e6)
            ),
            _borrower,
            100e6 + 1
        );
    }

    // Scenarios: BLCOL-WITHDRAW-I06.
    function test_givenCollateral_whenMaximumAmount_thenBothPathsReject()
        public
        givenDebtFreeCollateral
    {
        _expectWithdrawRevert(
            abi.encodeWithSelector(
                IBurnerLoansCollateral.BurnerLoans_InsufficientCollateral.selector,
                uint256(type(uint128).max),
                uint256(100e6)
            ),
            _borrower,
            type(uint128).max
        );
    }

    // Scenarios: BLCOL-WITHDRAW-N03.
    function test_givenUnhealthyFinalPosition_whenWithdrawn_thenExactErrorAndFullRollback(
        uint256 health_
    ) public givenDebtBearingPosition {
        health_ = bound(health_, 0, 1e18 - 1);
        bytes memory errorData = abi.encodeWithSelector(
            IBurnerLoansRisk.BurnerLoans_UnhealthyFinalPosition.selector,
            health_
        );
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.validateHealth.selector),
            errorData
        );
        _expectWithdrawRevert(errorData, _borrower, 1);
    }

    // Scenarios: BLCOL-WITHDRAW-N03.
    function test_givenHealthImmediatelyBelowOne_whenWithdrawn_reverts() public {
        test_givenUnhealthyFinalPosition_whenWithdrawn_thenExactErrorAndFullRollback(1e18 - 1);
    }

    // Scenarios: BLCOL-WITHDRAW-N05.
    function test_givenMaximumHealth_whenWithdrawn_thenExactValueReturned() public {
        test_givenDebt_whenRiskReturnsBoundaryHealth_thenExactValueReturned(type(uint256).max);
    }

    // Scenarios: BLCOL-WITHDRAW-N05.
    function test_givenHealthImmediatelyAboveOne_whenWithdrawn_thenExactValueReturned() public {
        test_givenDebt_whenRiskReturnsBoundaryHealth_thenExactValueReturned(1e18 + 1);
    }

    // Scenarios: BLCOL-WITHDRAW-L01.
    function test_givenReEnabledAction_whenWithdrawn_thenOperational()
        public
        givenDebtFreeCollateral
    {
        _collateral.disable("");
        _collateral.reEnable();
        _assertDirectWithdrawal(_borrower, 1, 100e6);
    }

    // Scenarios: BLCOL-WITHDRAW-L01.
    function test_givenReactivatedAction_whenWithdrawn_thenOperational()
        public
        givenDebtFreeCollateral
    {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_collateral));
        _kernel.executeAction(Actions.ActivatePolicy, address(_collateral));
        _assertDirectWithdrawal(_borrower, 1, 100e6);
    }

    // Scenarios: BLCOL-WITHDRAW-L06, BLCOL-WITHDRAW-L07, BLCOL-WITHDRAW-L08, BLCOL-WITHDRAW-L09, BLCOL-WITHDRAW-L10, BLCOL-WITHDRAW-L11, BLCOL-WITHDRAW-L12, BLCOL-WITHDRAW-L13.
    function test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins() public {
        for (uint256 flags; flags < 8; ++flags) {
            uint256 checkpoint = vm.snapshotState();
            test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified(
                _borrower,
                flags & 1 != 0,
                flags & 2 != 0,
                flags & 4 != 0
            );
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore lifecycle between equivalent rejection seeds"
            );
        }
    }

    // Scenarios: BLCOL-WITHDRAW-L02, BLCOL-WITHDRAW-L03, BLCOL-WITHDRAW-L04, BLCOL-WITHDRAW-L05.
    function test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins() public {
        for (uint256 flags; flags < 4; ++flags) {
            uint256 checkpoint = vm.snapshotState();
            test_givenDisabledAction_whenInvoked_thenLocalPauseWins(
                _borrower,
                flags & 1 != 0,
                flags & 2 != 0
            );
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore lifecycle between equivalent rejection seeds"
            );
        }
    }

    // Scenarios: BLCOL-WITHDRAW-D01, BLCOL-WITHDRAW-D02, BLCOL-WITHDRAW-D03.
    function test_givenUnavailableCore_whenAllLifecycleSeedsUsed_thenAdmissionWins() public {
        for (uint256 flags; flags < 3; ++flags) {
            uint256 checkpoint = vm.snapshotState();
            test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified(
                _borrower,
                flags == 1,
                flags == 2
            );
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore lifecycle between equivalent rejection seeds"
            );
        }
    }

    // Scenarios: BLCOL-WITHDRAW-N08.
    function test_givenTokenIsRecipient_whenWithdrawn_thenAllowedOverlap()
        public
        givenDebtFreeCollateral
    {
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(_asset),
            1,
            _borrower,
            address(_asset)
        );
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory actual = _collateral.withdrawCollateral(
            address(_asset),
            1,
            _borrower,
            address(_asset)
        );
        _assertWithdrawal(quote, address(_asset), 1, 100e6 - 1, type(uint256).max);
        _assertWithdrawal(actual, address(_asset), 1, 100e6 - 1, type(uint256).max);
        assertEq(_asset.balanceOf(address(_asset)), 1, "Token address receives actual output");
        _assertDirectCollateral(100e6 - 1);
    }

    // Scenarios: BLCOL-WITHDRAW-A08.
    function test_givenExpiredGrant_whenDeadlineBoundarySeedsUsed_thenUnauthorized() public {
        test_givenExpiredGrant_whenOperatorActs_reverts(1, 2);
        test_givenExpiredGrant_whenOperatorActs_reverts(
            type(uint48).max,
            uint256(type(uint48).max) + 1
        );
        test_givenExpiredGrant_whenOperatorActs_reverts(1, type(uint256).max);
    }

    // Scenarios: BLCOL-WITHDRAW-A11.
    function test_givenAnotherOperatorGrant_whenIndependentBoundaryTimesUsed_thenUnrelatedCallerRejected()
        public
    {
        test_givenOtherOperatorGrant_whenUnrelatedCallerActs_reverts(
            address(0),
            type(uint48).max,
            1
        );
        test_givenOtherOperatorGrant_whenUnrelatedCallerActs_reverts(
            address(0),
            type(uint48).max,
            type(uint48).max
        );
    }

    // Scenarios: BLCOL-WITHDRAW-I06.
    function test_givenDebtAndBrokenPricing_whenAmountExceedsCollateral_thenBoundsWin(
        uint128 amount_
    ) public givenDebtBearingPosition {
        amount_ = uint128(bound(amount_, 2000e6 + 1, type(uint128).max));
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector),
            hex"deadbeef"
        );
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.refreshSnapshot.selector),
            hex"deadbeef"
        );
        _expectWithdrawRevert(
            abi.encodeWithSelector(
                IBurnerLoansCollateral.BurnerLoans_InsufficientCollateral.selector,
                amount_,
                uint128(2000e6)
            ),
            _borrower,
            amount_
        );
    }

    // Scenarios: BLCOL-WITHDRAW-I06.
    function test_givenNoPosition_whenPositiveWithdrawal_thenBothPathsReject(
        uint128 amount_
    ) public {
        amount_ = uint128(bound(amount_, 1, type(uint128).max));
        _expectWithdrawRevert(
            abi.encodeWithSelector(
                IBurnerLoansCollateral.BurnerLoans_InsufficientCollateral.selector,
                amount_,
                uint128(0)
            ),
            _borrower,
            amount_
        );
    }

    // Scenarios: BLCOL-WITHDRAW-A01, BLCOL-WITHDRAW-A02, BLCOL-WITHDRAW-A03, BLCOL-WITHDRAW-A04, BLCOL-WITHDRAW-A06, BLCOL-WITHDRAW-A07, BLCOL-WITHDRAW-A08, BLCOL-WITHDRAW-A11, BLCOL-WITHDRAW-A12.
    function test_whenAnyViewerQuotesWithoutAuthorizationRead(
        address viewer_,
        uint128 amount_
    ) public givenDebtFreeCollateral {
        amount_ = uint128(bound(amount_, 1, 100e6));
        // Poison the complete authorization selector: neither viewer nor borrower grants may be read.
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSelector(IOperatorAuth.isSenderAuthorized.selector),
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector)
        );
        _assertPermissionlessQuote(viewer_, amount_);
    }

    function _assertPermissionlessQuote(address viewer_, uint128 amount_) private {
        bytes32 beforeState = _accountingDigest(address(_asset));
        vm.recordLogs();
        vm.prank(viewer_);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(_asset),
            amount_,
            _borrower,
            _recipient
        );
        _assertWithdrawal(quote, address(_asset), amount_, 100e6 - amount_, type(uint256).max);
        assertEq(vm.getRecordedLogs().length, 0, "quote emits no logs");
        assertEq(
            _accountingDigest(address(_asset)),
            beforeState,
            "quote preserves all custody and positions"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-A06, BLCOL-WITHDRAW-A13.
    function test_givenNoGrant_whenUnrelatedViewerQuotes() public givenDebtFreeCollateral {
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        _expectWithdrawExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            _recipient,
            7
        );
    }

    // Scenarios: BLCOL-WITHDRAW-A02, BLCOL-WITHDRAW-A11, BLCOL-WITHDRAW-A13.
    function test_givenValidGrant_whenUnrelatedViewerQuotes() public givenDebtFreeCollateral {
        _grantOperator(10);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        _assertDirectWithdrawal(_recipient, 7, 100e6);
    }

    // Scenarios: BLCOL-WITHDRAW-A03, BLCOL-WITHDRAW-A13.
    function test_givenGrantDeadline_whenUnrelatedViewerQuotes() public givenDebtFreeCollateral {
        _grantOperator(10);
        vm.warp(10);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        _assertDirectWithdrawal(_recipient, 7, 100e6);
    }

    // Scenarios: BLCOL-WITHDRAW-A08, BLCOL-WITHDRAW-A13.
    function test_givenExpiredGrant_whenUnrelatedViewerQuotes() public givenDebtFreeCollateral {
        _grantOperator(10);
        vm.warp(11);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        _expectWithdrawExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            _recipient,
            7
        );
    }

    // Scenarios: BLCOL-WITHDRAW-A07, BLCOL-WITHDRAW-A13.
    function test_givenRevokedGrant_whenUnrelatedViewerQuotes() public givenDebtFreeCollateral {
        _grantOperator(10);
        vm.prank(_borrower);
        _core.cancelAuthorization(_recipient);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        _expectWithdrawExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            _recipient,
            7
        );
    }

    // Scenarios: BLCOL-WITHDRAW-A14.
    function test_whenViewerHasAnotherPosition_thenSpecifiedBorrowerQuoted()
        public
        givenDebtFreeCollateral
    {
        _depositAsset(_asset, 50, _OTHER_BORROWER);
        bytes32 beforeState = _accountingDigest(address(_asset));
        vm.prank(_OTHER_BORROWER);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(_asset),
            7,
            _borrower,
            _recipient
        );
        _assertWithdrawal(quote, address(_asset), 7, 100e6 - 7, type(uint256).max);
        assertEq(
            _accountingDigest(address(_asset)),
            beforeState,
            "viewer, borrower and recipient remain distinct and unchanged"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-D08.
    function test_givenDebtAndBackingPaused_whenCollateralChanged_revertsWithoutSettlement()
        public
    {
        _depositAsset(_asset, 2000e6, _borrower);
        _asset.mint(_borrower, 100e6);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, type(uint256).max, address(0));
        address oracle = _risk.backingOracle();
        MockBackingOracle(oracle).setEnabled(false);
        bytes32 beforeState = _accountingDigest(address(_asset));
        vm.expectRevert(
            abi.encodeWithSelector(PolicyDependency.PolicyDependency_NotActive.selector, oracle)
        );
        _collateral.previewWithdrawCollateral(address(_asset), 1e6, _borrower, _recipient);
        vm.expectRevert(
            abi.encodeWithSelector(PolicyDependency.PolicyDependency_NotActive.selector, oracle)
        );
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(_asset), 1e6, _borrower, _recipient);
        assertEq(
            _accountingDigest(address(_asset)),
            beforeState,
            "backing outage leaves collateral and custody unchanged"
        );
    }

    // Scenarios: BLCOL-WITHDRAW-D09.
    function test_givenDebtFreeAndBackingPaused_whenCollateralChanged()
        public
        givenDebtFreeCollateral
    {
        MockBackingOracle(_risk.backingOracle()).setEnabled(false);
        _asset.mint(_borrower, 1e6);
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory result = _collateral.withdrawCollateral(
            address(_asset),
            1e6,
            _borrower,
            _recipient
        );
        assertEq(
            result.remainingDepositedCollateral,
            99e6,
            "debt-free exit removes collateral during backing outage"
        );
        assertEq(
            result.returnAmount,
            1e6,
            "debt-free exit transfers exact output during backing outage"
        );
        assertEq(
            result.resultingHealthFactor,
            type(uint256).max,
            "debt-free exit requires no backing"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
