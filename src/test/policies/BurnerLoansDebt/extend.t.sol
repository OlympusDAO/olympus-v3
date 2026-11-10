// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20Errors} from "@openzeppelin-5.7.0/interfaces/draft-IERC6093.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {Actions} from "src/Kernel.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {BL_DEBT_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {LoanPositions} from "src/policies/burnerloans/libraries/LoanPositions.sol";

// Contracts
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {BurnerLoansDebtTest} from "src/test/policies/BurnerLoansDebt/BurnerLoansDebtTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, unsafe-typecast, unused-return)

contract BurnerLoansDebtExtendTest is BurnerLoansDebtTest {
    uint48 internal constant _TERM_LENGTH = 30 days;
    uint48 internal constant _MATURITY_HORIZON = 90 days;
    uint48 internal constant _AFTER_EXPIRY = 1 days;
    uint256 internal constant _MOCK_FEE = 7;
    uint256 internal constant _MAX_FEE = _MOCK_FEE - 1;

    // Scenarios: BLEXT-EXTEND-T04.
    function test_givenInsufficientFeeAllowance_whenExtended_reverts(
        uint128 fee_,
        uint256 allowance_,
        bool operator_
    ) public givenMockDebt {
        fee_ = uint128(bound(fee_, 1, type(uint128).max));
        allowance_ = bound(allowance_, 0, uint256(fee_) - 1);
        address payer = _authorizeFeePayer(operator_);
        _fundFeePayer(payer, fee_);
        vm.prank(payer);
        _asset.approve(address(_core), allowance_);
        _assertExtensionCollectionReverts(
            payer,
            fee_,
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(_core),
                allowance_,
                uint256(fee_)
            )
        );
    }

    // Scenarios: BLEXT-EXTEND-T05.
    function test_givenInsufficientFeeBalance_whenExtended_reverts(
        uint128 fee_,
        uint256 balance_,
        bool operator_
    ) public givenMockDebt {
        fee_ = uint128(bound(fee_, 1, type(uint128).max));
        balance_ = bound(balance_, 0, uint256(fee_) - 1);
        address payer = _authorizeFeePayer(operator_);
        _fundFeePayer(payer, fee_);
        _asset.burn(payer, _asset.balanceOf(payer) - balance_);
        _assertExtensionCollectionReverts(
            payer,
            fee_,
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                payer,
                balance_,
                uint256(fee_)
            )
        );
    }

    function _assertExtensionCollectionReverts(
        address payer_,
        uint256 fee_,
        bytes memory reason_
    ) internal {
        _mockRisk(fee_);
        bytes32 beforeState = _stateDigest(payer_);
        bytes32 beforePosition = keccak256(abi.encode(_position()));
        vm.prank(payer_);
        IBurnerLoansDebt.ExtendPreview memory quote = _debt.previewExtend(
            address(_asset),
            _borrower,
            1,
            fee_,
            address(0)
        );
        assertEq(quote.fee, fee_, "Preview does not require payer funds or approval");
        assertEq(_stateDigest(payer_), beforeState, "Preview leaves accounting untouched");
        vm.expectRevert(reason_);
        vm.prank(payer_);
        _debt.extend(address(_asset), _borrower, 1, fee_, address(0));
        assertEq(
            keccak256(abi.encode(_position())),
            beforePosition,
            "Old maturity and position restored"
        );
        assertEq(
            _stateDigest(payer_),
            beforeState,
            "Fee failure restores balances, allowances and ledgers"
        );
    }

    // Scenarios: BLEXT-EXTEND-T04.
    function test_givenZeroFeeAllowance_whenBorrowerExtends_reverts() public {
        test_givenInsufficientFeeAllowance_whenExtended_reverts(7, 0, false);
    }

    // Scenarios: BLEXT-EXTEND-T04.
    function test_givenFeeAllowanceOneBelow_whenOperatorExtends_reverts() public {
        test_givenInsufficientFeeAllowance_whenExtended_reverts(7, 6, true);
    }

    // Scenarios: BLEXT-EXTEND-T05.
    function test_givenZeroFeeBalance_whenBorrowerExtends_reverts() public {
        test_givenInsufficientFeeBalance_whenExtended_reverts(7, 0, false);
    }

    // Scenarios: BLEXT-EXTEND-T05.
    function test_givenFeeBalanceOneBelow_whenOperatorExtends_reverts() public {
        test_givenInsufficientFeeBalance_whenExtended_reverts(7, 6, true);
    }

    // Scenarios: BLEXT-EXTEND-T05.
    function test_givenMaximumUint256Fee_givenUnfundedOperator_whenExtended_reverts()
        public
        givenMockDebt
    {
        _authorizeOperator(_recipient, type(uint48).max);
        vm.prank(_recipient);
        _asset.approve(address(_core), type(uint256).max);
        _assertExtensionCollectionReverts(
            _recipient,
            type(uint256).max,
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                _recipient,
                uint256(0),
                type(uint256).max
            )
        );
    }

    // Scenarios: BLEXT-EXTEND-N05, BLEXT-EXTEND-N06, BLEXT-EXTEND-A01, BLEXT-EXTEND-L01, BLEXT-EXTEND-A12.
    function test_givenRiskFee_whenExtended_thenExactFeeIsSettled(
        uint256 fee_,
        uint16 terms_
    ) public givenDebtBearingPosition {
        _assertExtensionFeeHandoff(_borrower, fee_, terms_);
    }

    // Scenarios: BLEXT-EXTEND-N05, BLEXT-EXTEND-N06, BLEXT-EXTEND-A02, BLEXT-EXTEND-A03, BLEXT-EXTEND-A04, BLEXT-EXTEND-A12.
    function test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled(
        uint256 fee_,
        uint16 terms_
    ) public givenDebtBearingPosition {
        _authorizeOperator(_recipient, type(uint48).max);
        uint256 borrowerBalance = _asset.balanceOf(_borrower);
        _assertExtensionFeeHandoff(_recipient, fee_, terms_);
        assertEq(_asset.balanceOf(_borrower), borrowerBalance, "Operator pays from its own wallet");
    }

    function _assertExtensionFeeHandoff(address payer_, uint256 fee_, uint16 terms_) internal {
        terms_ = SafeCast.toUint16(bound(terms_, 1, 2));
        {
            uint256 existingBalance = _asset.balanceOf(payer_);
            uint256 maximumFee = type(uint256).max - (_asset.totalSupply() - existingBalance);
            fee_ = bound(fee_, 1, maximumFee);
        }
        IFLOANv1.Position memory beforePosition = _position();
        {
            IBurnerLoansCore.PriceSnapshot memory snapshot = _risk.snapshot(address(_asset));
            bytes memory feeCall = abi.encodeCall(
                IBurnerLoansRisk.fee,
                (
                    snapshot,
                    _core.marketId(address(_asset)),
                    beforePosition.principalDue,
                    terms_,
                    address(0)
                )
            );
            vm.mockCall(address(_risk), feeCall, abi.encode(uint256(fee_), uint256(0)));
            vm.expectCall(address(_risk), feeCall);
            // Custody's distribution is tested separately; retain incoming fees here to prove handoff.
            bytes memory creditCall = abi.encodeCall(
                IBurnerLoansPayout.creditFee,
                (address(_asset), uint256(fee_), address(0), uint256(0))
            );
            vm.mockCall(address(_payout), creditCall, "");
            vm.expectCall(address(_payout), creditCall, 1);
        }

        _asset.burn(payer_, _asset.balanceOf(payer_));
        vm.prank(payer_);
        assertTrue(_asset.approve(address(_core), 0), "Quote needs no payer allowance");
        address viewer = makeAddr("unrelatedQuoteViewer");
        bytes32 beforeQuote = _stateDigest(viewer);
        vm.prank(viewer);
        IBurnerLoansDebt.ExtendPreview memory quote = _debt.previewExtend(
            address(_asset),
            _borrower,
            terms_,
            type(uint256).max,
            address(0)
        );
        assertEq(_stateDigest(viewer), beforeQuote, "Unfunded viewer quote preserves all state");
        _fundFeePayer(payer_, fee_);
        uint256 payerBalance = _asset.balanceOf(payer_);
        uint256 custodyBalance = _asset.balanceOf(address(_payout));
        uint48 expectedMaturity = beforePosition.maturity + _TERM_LENGTH * terms_;
        vm.expectEmit(true, true, true, true, address(_debt));
        emit IBurnerLoansDebt.Extended(
            payer_,
            address(_asset),
            _borrower,
            expectedMaturity,
            fee_,
            address(0),
            0
        );
        vm.prank(payer_);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            terms_,
            fee_ + 1,
            address(0)
        );
        assertEq(result.fee, fee_, "Debt uses the Risk fee without recalculation");
        assertEq(result.maturity, expectedMaturity, "Terms add to the old maturity");
        assertEq(result.fee, quote.fee, "Preview and execution fee agree");
        assertEq(result.maturity, quote.maturity, "Preview and execution maturity agree");
        assertEq(result.healthFactor, quote.healthFactor, "Preview and execution health agree");
        assertEq(_asset.balanceOf(payer_), payerBalance - fee_, "Actual caller pays exact fee");
        assertEq(
            _asset.balanceOf(address(_payout)),
            custodyBalance + fee_,
            "Custody receives exact fee"
        );
        IFLOANv1.Position memory afterPosition = _position();
        assertEq(afterPosition.maturity, expectedMaturity, "FLOAN stores the extended maturity");
        assertEq(afterPosition.principalDue, beforePosition.principalDue, "Principal is unchanged");
        assertEq(afterPosition.collateral, beforePosition.collateral, "Collateral is unchanged");
    }

    // Scenarios: BLEXT-EXTEND-N09.
    function test_givenZeroFee_whenExtended_thenNoFeeHandoff() public givenDebtBearingPosition {
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(0, uint256(0))
        );
        vm.mockCallRevert(
            address(_payout),
            abi.encodeWithSelector(IBurnerLoansPayout.creditFee.selector),
            "unexpected credit"
        );
        vm.prank(_borrower);
        assertTrue(_asset.approve(address(_core), 0), "Payer removes the fee allowance");
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            1,
            0,
            address(0)
        );
        assertEq(result.fee, 0, "Zero fee needs neither approval nor Custody handoff");
    }

    // Scenarios: BLEXT-EXTEND-N05, BLEXT-EXTEND-N06, BLEXT-EXTEND-A01, BLEXT-EXTEND-L01.
    function test_givenOneUnitFee_whenExtended_thenExactFeeIsSettled() public {
        test_givenRiskFee_whenExtended_thenExactFeeIsSettled(1, 1);
    }

    // Scenarios: BLEXT-EXTEND-N05.
    function test_givenMaximumUint128Fee_whenOperatorExtends_thenExactFeeIsSettled() public {
        test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled(type(uint128).max, 2);
    }

    // Scenarios: BLEXT-EXTEND-N08.
    function test_givenInventoryDisabled_whenExtended_thenSucceeds()
        public
        givenDebtBearingPosition
    {
        _inventory.disable("");
        uint48 oldMaturity = _position().maturity;
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            1,
            type(uint256).max,
            address(0)
        );
        assertEq(
            result.maturity,
            oldMaturity + _TERM_LENGTH,
            "Extension does not need Inventory operations"
        );
    }

    // Scenarios: BLEXT-EXTEND-A06, BLEXT-EXTEND-A11.
    function test_givenOtherOperatorGrant_whenUnrelatedCallerExtends_reverts(
        address caller_
    ) public givenDebtBearingPosition {
        vm.assume(caller_ != _borrower && caller_ != _recipient);
        _authorizeOperator(_recipient, type(uint48).max);
        bytes32 rollbackBefore = _stateDigest(_borrower);
        vm.expectRevert(_unauthorizedOperatorError(caller_));
        vm.prank(caller_);
        // Expected revert: no result exists to assert.
        // forge-lint: disable-next-line(unused-return)
        _debt.extend(address(_asset), _borrower, 1, type(uint256).max, address(0));
        assertEq(
            _stateDigest(_borrower),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLEXT-EXTEND-A09.
    function test_givenDebtRoleRevoked_whenExtended_reverts() public givenDebtBearingPosition {
        _rolesAdmin.revokeRole(BL_DEBT_POLICY_ROLE, address(_debt));
        bytes32 rollbackBefore = _stateDigest(_borrower);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_DEBT_POLICY_ROLE)
        );
        vm.prank(makeAddr("unrelatedQuoteViewer"));
        // Expected revert: no quote exists to assert.
        // forge-lint: disable-next-line(unused-return)
        _debt.previewExtend(address(_asset), _borrower, 1, type(uint256).max, address(0));
        assertEq(_stateDigest(_borrower), rollbackBefore, "Rejected quote preserves all state");
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_DEBT_POLICY_ROLE)
        );
        vm.prank(_borrower);
        // Expected revert: no result exists to assert.
        // forge-lint: disable-next-line(unused-return)
        _debt.extend(address(_asset), _borrower, 1, type(uint256).max, address(0));
        assertEq(
            _stateDigest(_borrower),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    function test_givenOnlyRetiredExtensionRole_whenSettled_reverts()
        public
        givenDebtBearingPosition
    {
        _rolesAdmin.grantRole("burner_loans_extension", address(_collateral));
        uint48 maturity = _position().maturity + _TERM_LENGTH;
        bytes32 rollbackBefore = _stateDigest(_borrower);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_DEBT_POLICY_ROLE)
        );
        vm.prank(address(_collateral));
        // Expected revert: no result exists to assert.
        // forge-lint: disable-next-line(unused-return)
        _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(_asset),
                borrower: _borrower,
                payer: _borrower,
                maturity: maturity,
                protocolFee: 0,
                referrer: address(0),
                referralFee: 0
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(
            _stateDigest(_borrower),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLEXT-EXTEND-I01.
    function test_whenTermsAreZero_reverts() public givenDebtBearingPosition {
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ZeroAmount.selector);
        // Expected revert: no result exists to assert.
        // forge-lint: disable-next-line(unused-return)
        vm.prank(_borrower);
        _debt.previewExtend(address(_asset), _borrower, 0, type(uint256).max, address(0));
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ZeroAmount.selector);
        vm.prank(_borrower);
        // Expected revert: no result exists to assert.
        // forge-lint: disable-next-line(unused-return)
        _debt.extend(address(_asset), _borrower, 0, type(uint256).max, address(0));
    }

    // Scenarios: BLEXT-EXTEND-I03.
    function test_givenNoDebt_whenExtended_reverts() public {
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_NoDebt.selector);
        // Expected revert: no result exists to assert.
        // forge-lint: disable-next-line(unused-return)
        vm.prank(_borrower);
        _debt.previewExtend(address(_asset), _borrower, 1, type(uint256).max, address(0));
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_NoDebt.selector);
        vm.prank(_borrower);
        // Expected revert: no result exists to assert.
        // forge-lint: disable-next-line(unused-return)
        _debt.extend(address(_asset), _borrower, 1, type(uint256).max, address(0));
    }

    // Scenarios: BLEXT-EXTEND-N02.
    function test_givenFeeAboveMaximum_whenExtended_reverts() public givenDebtBearingPosition {
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(_MOCK_FEE, uint256(0))
        );
        uint48 oldMaturity = _position().maturity;
        bytes32 rollbackBefore = _stateDigest(_borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_FeeExceedsMax.selector,
                _MOCK_FEE,
                _MAX_FEE
            )
        );
        vm.prank(_borrower);
        // Expected revert: no result exists to assert.
        // forge-lint: disable-next-line(unused-return)
        _debt.extend(address(_asset), _borrower, 1, _MAX_FEE, address(0));
        assertEq(_position().maturity, oldMaturity, "Rejected fee preserves maturity");
        assertEq(
            _stateDigest(_borrower),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLEXT-EXTEND-N01.
    function test_whenTermsExceedHorizon_reverts(uint16 terms_) public givenDebtBearingPosition {
        terms_ = SafeCast.toUint16(bound(terms_, 3, type(uint16).max));
        uint256 maturity = uint256(_position().maturity) + uint256(_TERM_LENGTH) * terms_;
        bytes memory errorData = abi.encodeWithSelector(
            IBurnerLoansDebt.BurnerLoans_MaturityHorizonExceeded.selector,
            maturity,
            block.timestamp + _MATURITY_HORIZON
        );
        vm.expectRevert(errorData);
        // Expected revert: no result exists to assert.
        // forge-lint: disable-next-line(unused-return)
        vm.prank(_borrower);
        _debt.previewExtend(address(_asset), _borrower, terms_, type(uint256).max, address(0));
        vm.expectRevert(errorData);
        vm.prank(_borrower);
        // Expected revert: no result exists to assert.
        // forge-lint: disable-next-line(unused-return)
        _debt.extend(address(_asset), _borrower, terms_, type(uint256).max, address(0));
    }

    // Scenarios: BLEXT-EXTEND-N01.
    function test_whenMaximumTermsExceedHorizon_reverts() public {
        test_whenTermsExceedHorizon_reverts(type(uint16).max);
    }

    function test_givenExpiredHealthyDebt_whenExtended_thenOldMaturityIsUsed()
        public
        givenDebtBearingPosition
    {
        uint48 oldMaturity = _position().maturity;
        vm.warp(uint256(oldMaturity) + _AFTER_EXPIRY);
        _price.setTimestamp(oldMaturity + _AFTER_EXPIRY);
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            1,
            type(uint256).max,
            address(0)
        );
        assertEq(
            result.maturity,
            oldMaturity + _TERM_LENGTH,
            "Expired debt adds terms to the original maturity"
        );
    }

    function test_givenReEnabledDebt_whenExtended_thenSucceeds() public givenDebtBearingPosition {
        uint48 oldMaturity = _position().maturity;
        _debt.disable("");
        _debt.reEnable();
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            1,
            type(uint256).max,
            address(0)
        );
        assertEq(
            result.maturity,
            oldMaturity + _TERM_LENGTH,
            "Re-enabled Debt resumes extension settlement"
        );
    }

    // Scenarios: BLEXT-EXTEND-L02.
    function test_givenDebtDisabled_whenExtended_reverts() public givenDebtBearingPosition {
        _debt.disable("");
        bytes32 rollbackBefore = _stateDigest(_borrower);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(_borrower);
        // Expected revert: no result exists to assert.
        // forge-lint: disable-next-line(unused-return)
        _debt.extend(address(_asset), _borrower, 1, type(uint256).max, address(0));
        assertEq(
            _stateDigest(_borrower),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLEXT-EXTEND-L06.
    function test_givenDebtInactive_whenExtended_reverts() public givenDebtBearingPosition {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_debt));
        bytes32 rollbackBefore = _stateDigest(_borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_debt)
            )
        );
        vm.prank(_borrower);
        // Expected revert: no result exists to assert.
        // forge-lint: disable-next-line(unused-return)
        _debt.extend(address(_asset), _borrower, 1, type(uint256).max, address(0));
        assertEq(
            _stateDigest(_borrower),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLDEBT-ERC165-P01.
    function test_whenInterfaceQueried_thenMergedDebtIsAdvertised() public view {
        assertTrue(
            _debt.supportsInterface(type(IBurnerLoansDebt).interfaceId),
            "Merged Debt interface is supported"
        );
    }

    // Scenarios: BLEXT-EXTEND-C06.
    // Scenarios: BLEXT-EXTEND-T02.
    function _nestedExtendInstruction(
        address token_,
        uint48 maturity_,
        uint256 fee_
    ) internal view returns (bytes memory) {
        return
            abi.encodeCall(
                IBurnerLoansCore.settleExtend,
                (
                    IBurnerLoansCore.ExtendRequest({
                        asset: token_,
                        borrower: _borrower,
                        payer: token_,
                        maturity: maturity_,
                        protocolFee: fee_,
                        referrer: address(0),
                        referralFee: uint256(0)
                    }),
                    token_,
                    _operatorAuthContext(_borrower, token_, 8)
                )
            );
    }

    // Scenarios: BLEXT-EXTEND-T02, BLEXT-EXTEND-C06.
    function test_givenCollateralCallback_whenExtended_revertsAtomically() public {
        (ReentrantFeeToken token, uint256 fee) = _prepareCollateralCallback();
        (, , IFLOANv1.Position memory beforePosition) = LoanPositions.forCore(
            _core,
            address(token),
            _borrower
        );
        uint256 payerBalance = token.balanceOf(_borrower);
        uint256 custodyBalance = token.balanceOf(address(_payout));

        token.setBubbleCallbackFailure(true);
        // The nested, authorized action must reach Core after the outer maturity update.
        vm.expectCall(
            address(_core),
            _nestedExtendInstruction(
                address(token),
                beforePosition.maturity + 2 * _TERM_LENGTH,
                fee
            )
        );
        bytes32 rollbackBefore = _stateDigestFor(address(token), _borrower);
        vm.expectRevert(ReentrantFeeToken.CallbackFailed.selector);
        vm.prank(_borrower);
        // Expected revert: no result exists to assert.
        // forge-lint: disable-next-line(unused-return)
        _debt.extend(address(token), _borrower, 1, type(uint256).max, address(0));
        (, , IFLOANv1.Position memory afterPosition) = LoanPositions.forCore(
            _core,
            address(token),
            _borrower
        );
        assertEq(
            afterPosition.maturity,
            beforePosition.maturity,
            "Failed callback restores maturity"
        );
        assertEq(
            afterPosition.principalDue,
            beforePosition.principalDue,
            "Failed callback preserves principal"
        );
        assertEq(
            afterPosition.collateral,
            beforePosition.collateral,
            "Failed callback preserves collateral"
        );
        assertEq(
            token.balanceOf(_borrower),
            payerBalance,
            "Failed callback restores payer balance"
        );
        assertEq(
            token.balanceOf(address(_payout)),
            custodyBalance,
            "Failed callback restores Custody balance"
        );
        assertEq(
            token.allowance(_borrower, address(_core)),
            fee,
            "Failed callback restores allowance"
        );
        assertEq(
            _stateDigestFor(address(token), _borrower),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    function test_givenCaughtCollateralCallback_whenExtended_thenOnlyOuterOperationSucceeds()
        public
    {
        (ReentrantFeeToken token, ) = _prepareCollateralCallback();
        (, , IFLOANv1.Position memory beforePosition) = LoanPositions.forCore(
            _core,
            address(token),
            _borrower
        );

        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory caught = _debt.extend(
            address(token),
            _borrower,
            1,
            type(uint256).max,
            address(0)
        );
        assertEq(
            caught.maturity,
            beforePosition.maturity + _TERM_LENGTH,
            "Caught callback permits exactly one extension"
        );
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Authorized funded nested extension reaches Core guard"
        );
    }

    function _prepareCollateralCallback() internal returns (ReentrantFeeToken token, uint256 fee) {
        token = new ReentrantFeeToken();
        _price.setPrice(address(token), 1e18);
        _admit(address(token));
        token.mint(_borrower, 3000e18);
        vm.startPrank(_borrower);
        assertTrue(
            token.approve(address(_core), type(uint256).max),
            "Borrower approves callback asset"
        );
        // Setup only; the canonical position is captured below.
        // forge-lint: disable-next-line(unused-return)
        _collateral.depositCollateral(address(token), 2000e18, _borrower);
        // Setup only; the canonical position is captured below.
        // forge-lint: disable-next-line(unused-return)
        _debt.borrow(address(token), 100e9, _borrower, _borrower, 100e18, address(0));
        _approveOperatorForAsset(_borrower, address(token), type(uint48).max, address(token));
        vm.stopPrank();
        vm.prank(_borrower);
        fee = _debt.previewExtend(address(token), _borrower, 1, type(uint256).max, address(0)).fee;
        vm.prank(_borrower);
        assertTrue(token.approve(address(_core), fee), "Borrower approves exactly the outer fee");
        token.setCallbackFrom(
            address(_core),
            address(_debt),
            abi.encodeCall(
                IBurnerLoansDebt.extend,
                (address(token), _borrower, 1, type(uint256).max, address(0))
            )
        );
        token.setCallbackPhases(false, true);
        token.mint(address(token), fee);
        vm.prank(address(token));
        assertTrue(token.approve(address(_core), fee), "Nested operator approves its fee");
    }

    // Scenarios: BLEXT-EXTEND-N05.
    function test_givenMaximumFundableUint256Fee_whenExtended_thenExactReceipt() public {
        uint256 maximumFee = type(uint256).max - _asset.totalSupply();
        test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled(maximumFee, 1);
    }

    error ExtensionFailed();

    // Scenarios: BLEXT-EXTEND-A10.
    function test_givenReportedKernelMismatch_whenExtended_thenGetterIsNotRead(
        bool operator_
    ) public {
        vm.mockCall(
            address(_debt),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0x1234))
        );
        _assertExtensionWithoutActionKernelRead(operator_);
    }

    // Scenarios: BLEXT-EXTEND-A10.
    function test_givenActionKernelGetterReverts_whenExtended_thenGetterIsNotRead(
        bool operator_
    ) public {
        vm.mockCallRevert(address(_debt), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        _assertExtensionWithoutActionKernelRead(operator_);
    }

    function _assertExtensionWithoutActionKernelRead(
        bool operator_
    ) private givenDebtBearingPosition {
        address payer = _authorizeFeePayer(operator_);
        vm.expectCall(address(_debt), abi.encodeWithSignature("kernel()"), uint64(0));
        _assertExtensionFeeHandoff(payer, 7, 1);
    }

    // Scenarios: BLEXT-EXTEND-T03.
    function test_givenFloanRejectsExtension_whenExtended_thenNoFeeOrExpiryChange()
        public
        givenMockDebt
    {
        _mockRisk(7);
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.extendMaturity.selector),
            abi.encodeWithSelector(ExtensionFailed.selector)
        );
        uint256 balance = _asset.balanceOf(_borrower);
        uint48 expiry = _position().maturity;
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory quote = _debt.previewExtend(
            address(_asset),
            _borrower,
            1,
            7,
            address(0)
        );
        assertEq(quote.fee, 7, "View does not execute FLOAN write");
        bytes32 rollbackBefore = _stateDigest(_borrower);
        vm.expectRevert(ExtensionFailed.selector);
        vm.prank(_borrower);
        _debt.extend(address(_asset), _borrower, 1, 7, address(0));
        assertEq(_position().maturity, expiry, "Rejected write preserves expiry");
        assertEq(_asset.balanceOf(_borrower), balance, "Rejected write never collects fee");
        assertEq(_asset.balanceOf(address(_payout)), 0, "No fee credited");
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Funding exposure unchanged");
        assertEq(
            _stateDigest(_borrower),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLEXT-EXTEND-D04.
    function test_givenOriginationsDisabled_whenExtended_reverts() public givenMockDebt {
        _config.setAssetOriginationsEnabled(address(_asset), false);
        _expectExtendRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetOriginationsDisabled.selector,
                address(_asset)
            ),
            1,
            0,
            _borrower
        );
    }

    // Scenarios: BLEXT-EXTEND-P01.
    function test_givenCustodyInsolvent_whenExtended_reverts() public givenMockDebt {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature(
                "getOperatorAssets(address,address)",
                address(_asset),
                address(_core)
            ),
            abi.encode(uint256(2000e6), uint256(2000e6 - 1))
        );
        _expectExtendRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_Insolvent.selector,
                address(_asset),
                uint256(2000e6),
                uint256(2000e6 - 1),
                uint256(0)
            ),
            1,
            0,
            _borrower
        );
    }

    // Scenarios: BLEXT-EXTEND-P02, BLEXT-EXTEND-P03.
    function test_givenResultingExpiryNotFuture_whenExtended_reverts(
        uint48 elapsed_
    ) public givenMockDebt {
        uint256 next = uint256(_position().maturity) + 30 days;
        vm.warp(next + elapsed_);
        _expectExtendRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_ExtensionMaturityNotFuture.selector,
                next,
                block.timestamp
            ),
            1,
            0,
            _borrower
        );
    }

    // Scenarios: BLEXT-EXTEND-P03.
    function test_givenResultingExpiryEqualsNow_whenExtended_reverts() public givenMockDebt {
        test_givenResultingExpiryNotFuture_whenExtended_reverts(0);
    }

    // Scenarios: BLEXT-EXTEND-P04.
    function test_givenUnhealthyPosition_whenExtended_reverts(
        uint256 health_
    ) public givenMockDebt {
        health_ = bound(health_, 0, 1e18 - 1);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.validateHealth.selector),
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_UnhealthyPosition.selector, health_)
        );
        _expectExtendRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_UnhealthyPosition.selector,
                health_
            ),
            1,
            0,
            _borrower
        );
    }

    // Scenarios: BLEXT-EXTEND-N02.
    function test_givenRiskFee_whenLimitBelowFee_reverts(
        uint128 fee_,
        uint256 limit_
    ) public givenMockDebt {
        fee_ = uint128(bound(fee_, 1, type(uint128).max));
        limit_ = bound(limit_, 0, uint256(fee_) - 1);
        _mockRisk(fee_);
        _expectExtendRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_FeeExceedsMax.selector,
                uint256(fee_),
                limit_
            ),
            1,
            limit_,
            _borrower
        );
    }

    // Scenarios: BLEXT-EXTEND-N03, BLEXT-EXTEND-N04.
    function test_givenExactHealthAndExpiryThresholds_whenExtended_thenAccepted()
        public
        givenMockDebt
    {
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.validateHealth.selector),
            abi.encode(uint256(1e18))
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory quote = _debt.previewExtend(
            address(_asset),
            _borrower,
            2,
            0,
            address(0)
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            2,
            0,
            address(0)
        );
        assertEq(result.maturity, block.timestamp + 90 days, "Exact horizon accepted");
        assertEq(result.healthFactor, 1e18, "Exact health accepted");
        assertEq(quote.maturity, result.maturity, "Same expiry quote");
    }

    // Scenarios: BLEXT-EXTEND-N07.
    function test_givenOneSecondTerm_whenMaximumTermsExtended_thenNoTruncation()
        public
        givenMockDebt
    {
        _config.setAssetRiskConfig(
            address(_asset),
            IBurnerLoansRisk.AssetRiskConfigInput(8500, 12500, 100, 1, 90 days, 1000e6)
        );
        uint48 expected = _position().maturity + type(uint16).max;
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory quote = _debt.previewExtend(
            address(_asset),
            _borrower,
            type(uint16).max,
            0,
            address(0)
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            type(uint16).max,
            0,
            address(0)
        );
        assertEq(result.maturity, expected, "MAX16 terms multiply at full width");
        assertEq(quote.maturity, expected, "MAX16 preview");
    }

    // Scenarios: BLEXT-EXTEND-N09.
    function test_givenZeroFeeAndNoWalletFunds_whenOperatorExtends_thenNoCollection()
        public
        givenMockDebt
    {
        _authorizeOperator(_recipient, type(uint48).max);
        _assertZeroFeeExtension(_recipient, 0);
    }

    // Scenarios: BLEXT-EXTEND-N09.
    function test_givenZeroFeeAndNoWalletFunds_whenBorrowerExtends_thenNoCollection()
        public
        givenMockDebt
    {
        _assertZeroFeeExtension(_borrower, 0);
    }

    // Scenarios: BLEXT-EXTEND-N09.
    function test_givenZeroFeeAndMaximumLimit_whenExtended_thenNoCollection() public givenMockDebt {
        _assertZeroFeeExtension(_borrower, type(uint256).max);
    }

    // Scenarios: BLEXT-EXTEND-N09.
    function test_givenZeroFeeAndMaximumLimit_whenOperatorExtends_thenNoCollection()
        public
        givenMockDebt
    {
        _authorizeOperator(_recipient, type(uint48).max);
        _assertZeroFeeExtension(_recipient, type(uint256).max);
    }

    function _assertZeroFeeExtension(address payer_, uint256 maxFee_) internal {
        _asset.burn(payer_, _asset.balanceOf(payer_));
        vm.prank(payer_);
        _asset.approve(address(_core), 0);
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSelector(_asset.transferFrom.selector),
            abi.encodeWithSelector(ExtensionFailed.selector)
        );
        vm.prank(payer_);
        IBurnerLoansDebt.ExtendPreview memory quote = _debt.previewExtend(
            address(_asset),
            _borrower,
            1,
            maxFee_,
            address(0)
        );
        vm.prank(payer_);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            1,
            maxFee_,
            address(0)
        );
        assertEq(result.fee, 0, "No fee");
        assertEq(quote.fee, 0, "No preview fee");
        assertEq(_asset.balanceOf(payer_), 0, "No funds required");
        assertEq(_position().principalDue, 100e9, "Extension preserves principal");
    }

    // Scenarios: BLEXT-EXTEND-I03.
    function test_givenCollateralWithNoDebt_whenExtended_reverts() public givenMockDebt {
        vm.roll(block.number + 1);
        vm.prank(_borrower);
        _ohm.approve(address(_core), 100e9);
        vm.prank(_borrower);
        _debt.repay(address(_asset), 100e9, _borrower);
        _expectExtendRevert(
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_NoDebt.selector),
            1,
            0,
            _borrower
        );
    }

    // Scenarios: BLEXT-EXTEND-A02, BLEXT-EXTEND-A03, BLEXT-EXTEND-A04.
    function test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached(
        uint48 deadline_,
        uint48 now_
    ) public {
        deadline_ = uint48(bound(deadline_, 1, type(uint48).max));
        now_ = uint48(bound(now_, 1, deadline_));
        vm.warp(1);
        _authorizeOperator(_recipient, deadline_);
        vm.warp(now_);
        _expectExtendRevert(
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_ZeroAmount.selector),
            0,
            0,
            _recipient
        );
    }

    // Scenarios: BLEXT-EXTEND-A03, BLEXT-EXTEND-A04.
    function test_givenMaximumDeadline_whenAtEquality_thenOperatorAdmitted() public {
        test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached(
            type(uint48).max,
            type(uint48).max
        );
    }

    // Scenarios: BLEXT-EXTEND-A08.
    function test_givenExpiredGrant_whenOperatorActs_reverts(
        uint48 deadline_,
        uint256 now_
    ) public {
        deadline_ = uint48(bound(deadline_, 1, type(uint48).max));
        now_ = bound(now_, uint256(deadline_) + 1, type(uint256).max);
        vm.warp(1);
        _authorizeOperator(_recipient, deadline_);
        vm.warp(now_);
        _expectExtendExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_ExpiredGrant.selector, deadline_),
            0,
            0,
            _recipient
        );
        assertEq(
            _authorizationDeadline(_borrower, _recipient),
            0,
            "Expired authority is hidden by the live-only getter"
        );
        // Read again at the inclusive deadline to prove the failed operation did not erase
        // permission data or advance cancellation epochs; only the clock made it unavailable.
        vm.warp(deadline_);
        assertEq(
            _authorizationDeadline(_borrower, _recipient),
            deadline_,
            "Failed use preserves the accepted grant"
        );
    }

    // Scenarios: BLEXT-EXTEND-A08.
    function test_givenMaximumTimestamp_whenGrantExpired_reverts() public {
        test_givenExpiredGrant_whenOperatorActs_reverts(type(uint48).max, type(uint256).max);
    }

    // Scenarios: BLEXT-EXTEND-A07.
    function test_givenCancelledGrant_whenOperatorActs_reverts() public {
        vm.startPrank(_borrower);
        _approveOperator(_borrower, _recipient, type(uint48).max);
        _auth.cancelGrant(_recipient);
        vm.stopPrank();
        _expectExtendExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidContext.selector),
            0,
            0,
            _recipient
        );
    }

    // Scenarios: BLEXT-EXTEND-A06.
    function test_givenNoGrant_whenUnrelatedCallerActs_reverts(
        address caller_
    ) public givenDebtBearingPosition {
        vm.assume(!_isSenderAuthorized(caller_, _borrower));
        _expectExtendExecutionRevert(_unauthorizedOperatorError(caller_), 0, 0, caller_);
    }

    // Scenarios: BLEXT-EXTEND-A11.
    function test_givenAnotherValidOperator_whenUnrelatedCallerActs_reverts(
        address caller_,
        uint48 deadline_,
        uint48 now_
    ) public {
        vm.assume(caller_ != _borrower && caller_ != _recipient);
        deadline_ = uint48(bound(deadline_, 1, type(uint48).max));
        now_ = uint48(bound(now_, 1, deadline_));
        vm.warp(1);
        _authorizeOperator(_recipient, deadline_);
        vm.warp(now_);
        _expectExtendExecutionRevert(_unauthorizedOperatorError(caller_), 0, 0, caller_);
    }

    // Scenarios: BLEXT-EXTEND-A05.
    function test_whenBorrowerZero_thenExplicitError(address caller_) public {
        bytes memory reason = abi.encodeWithSelector(
            IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector
        );
        vm.expectRevert(reason);
        vm.prank(caller_);
        _debt.previewExtend(address(_asset), address(0), 1, 0, address(0));
        vm.expectRevert(reason);
        vm.prank(caller_);
        _debt.extend(address(_asset), address(0), 1, 0, address(0));
    }

    // Scenarios: BLEXT-EXTEND-L06, BLEXT-EXTEND-L07, BLEXT-EXTEND-L08, BLEXT-EXTEND-L09, BLEXT-EXTEND-L10, BLEXT-EXTEND-L11, BLEXT-EXTEND-L12, BLEXT-EXTEND-L13.
    function test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified(
        bool enabled_,
        bool coreActive_,
        bool coreEnabled_,
        address caller_,
        bool validInput_
    ) public {
        _setPolicyState(_debt, false, enabled_);
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _expectExtendRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_debt)
            ),
            validInput_ ? 1 : 0,
            type(uint256).max,
            caller_
        );
    }

    // Scenarios: BLEXT-EXTEND-L02, BLEXT-EXTEND-L03, BLEXT-EXTEND-L04, BLEXT-EXTEND-L05.
    function test_givenDisabledDebtAction_whenCalled_thenPauseWins(
        bool coreActive_,
        bool coreEnabled_,
        address caller_,
        bool validInput_
    ) public {
        _debt.disable("");
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _expectExtendRevert(
            abi.encodeWithSelector(IEnabler.NotEnabled.selector),
            validInput_ ? 1 : 0,
            type(uint256).max,
            caller_
        );
    }

    // Scenarios: BLEXT-EXTEND-D01, BLEXT-EXTEND-D02, BLEXT-EXTEND-D03.
    function test_givenCoreUnavailable_whenCalled_thenDependencyIdentified(
        bool active_,
        bool enabled_,
        address caller_,
        bool validInput_
    ) public {
        vm.assume(!active_ || !enabled_);
        _setPolicyState(_core, active_, enabled_);
        _expectExtendRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            ),
            validInput_ ? 1 : 0,
            type(uint256).max,
            caller_
        );
    }

    // Scenarios: BLEXT-EXTEND-A02, BLEXT-EXTEND-A03, BLEXT-EXTEND-A04.
    function test_givenValidOperatorGrant_whenExtended_thenActualOperatorPays(
        uint48 deadline_,
        uint48 now_
    ) public {
        deadline_ = uint48(bound(deadline_, 1, type(uint48).max));
        uint256 latest = deadline_ < type(uint48).max - 90 days
            ? deadline_
            : type(uint48).max - 90 days;
        now_ = uint48(bound(now_, 1, latest));
        vm.warp(1);
        _authorizeOperator(_recipient, deadline_);
        vm.warp(now_);
        _depositCollateral(2000e6);
        _mockRisk(0);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 0, address(0));
        _assertExtensionFeeHandoff(_recipient, 7, 1);
        assertEq(
            _authorizationDeadline(_borrower, _recipient),
            deadline_,
            "Extension preserves operator grant"
        );
    }

    // Scenarios: BLEXT-EXTEND-A02, BLEXT-EXTEND-A03, BLEXT-EXTEND-A04, BLEXT-EXTEND-A08.
    function test_whenAuthorizationEndpoints_thenAdmissionIsInclusive() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached(2, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore initial position");
        test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached(2, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore grant and fee accounting");
        test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached(type(uint48).max, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore for maximum timestamp admission");
        test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached(
            type(uint48).max,
            type(uint48).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore expired grant boundary");
        test_givenExpiredGrant_whenOperatorActs_reverts(1, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore widened expiration boundary");
        test_givenExpiredGrant_whenOperatorActs_reverts(
            type(uint48).max,
            uint256(type(uint48).max) + 1
        );
    }

    // Scenarios: BLEXT-EXTEND-N03, BLEXT-EXTEND-N06.
    function test_givenClampedHorizon_whenExpiryIsMaximum_thenNoTruncation() public {
        vm.warp(uint256(type(uint48).max) - 60 days);
        _depositCollateral(2000e6);
        _mockRisk(0);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 0, address(0));
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory q = _debt.previewExtend(
            address(_asset),
            _borrower,
            1,
            0,
            address(0)
        );
        assertEq(q.maturity, type(uint48).max, "Clamped inclusive horizon quote");
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            1,
            0,
            address(0)
        );
        assertEq(result.maturity, type(uint48).max, "Maximum expiry accepted exactly");
        assertEq(_position().maturity, type(uint48).max, "Maximum expiry stored without narrowing");
        _expectExtendRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_MaturityHorizonExceeded.selector,
                uint256(type(uint48).max) + 30 days,
                uint256(type(uint48).max)
            ),
            1,
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-EXTEND-D01, BLDEBT-EXTEND-D02, BLDEBT-EXTEND-D03.
    function test_givenPayoutUnavailable_whenFeeBearingOperation_reverts(
        bool active_,
        bool enabled_
    ) public givenMockDebt {
        vm.assume(!active_ || !enabled_);
        _mockRisk(7);
        _setPolicyState(_payout, active_, enabled_);
        bytes memory reason = abi.encodeWithSelector(
            PolicyDependency.PolicyDependency_NotActive.selector,
            address(_payout)
        );
        _expectExtendRevert(reason, 1, 7, _borrower);
    }

    // Scenarios: BLEXT-EXTEND-A02.
    function test_givenBeforeDeadline_whenOperatorExtended_thenSuccessfulSettlement() public {
        test_givenValidOperatorGrant_whenExtended_thenActualOperatorPays(2, 1);
    }

    // Scenarios: BLEXT-EXTEND-A03.
    function test_givenAtDeadline_whenOperatorExtended_thenSuccessfulSettlement() public {
        test_givenValidOperatorGrant_whenExtended_thenActualOperatorPays(2, 2);
    }

    // Scenarios: BLEXT-EXTEND-A02, BLEXT-EXTEND-A04.
    function test_givenMaximumDeadline_whenOperatorExtended_thenSuccessfulSettlement() public {
        test_givenValidOperatorGrant_whenExtended_thenActualOperatorPays(type(uint48).max, 1);
    }

    // Scenarios: BLEXT-EXTEND-L06, BLEXT-EXTEND-L07, BLEXT-EXTEND-L08, BLEXT-EXTEND-L09, BLEXT-EXTEND-L10, BLEXT-EXTEND-L11, BLEXT-EXTEND-L12, BLEXT-EXTEND-L13.
    function test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError() public {
        for (uint256 enabled; enabled < 2; ++enabled) {
            for (uint256 active; active < 2; ++active) {
                for (uint256 coreEnabled; coreEnabled < 2; ++coreEnabled) {
                    for (uint256 valid; valid < 2; ++valid) {
                        uint256 checkpoint = vm.snapshotState();
                        test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified(
                            enabled != 0,
                            active != 0,
                            coreEnabled != 0,
                            address(0xbeef),
                            valid != 0
                        );
                        assertTrue(
                            vm.revertToState(checkpoint),
                            "Restore subject and dependency state for each admission seed"
                        );
                    }
                }
            }
        }
    }

    // Scenarios: BLEXT-EXTEND-L02, BLEXT-EXTEND-L03, BLEXT-EXTEND-L04, BLEXT-EXTEND-L05.
    function test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError() public {
        for (uint256 active; active < 2; ++active) {
            for (uint256 coreEnabled; coreEnabled < 2; ++coreEnabled) {
                for (uint256 valid; valid < 2; ++valid) {
                    uint256 checkpoint = vm.snapshotState();
                    test_givenDisabledDebtAction_whenCalled_thenPauseWins(
                        active != 0,
                        coreEnabled != 0,
                        address(0xbeef),
                        valid != 0
                    );
                    assertTrue(
                        vm.revertToState(checkpoint),
                        "Restore subject and dependency state for each admission seed"
                    );
                }
            }
        }
    }

    // Scenarios: BLEXT-EXTEND-L01.
    function test_givenPolicyReactivated_whenExtendExecuted_thenSucceeds() public givenMockDebt {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_debt));
        _kernel.executeAction(Actions.ActivatePolicy, address(_debt));
        _mockRisk(0);
        vm.prank(_borrower);
        _debt.extend(address(_asset), _borrower, 1, 0, address(0));
        assertEq(
            _position().maturity,
            block.timestamp + 60 days,
            "Reactivated extension stores new maturity"
        );
    }

    // Scenarios: BLEXT-EXTEND-A01, BLEXT-EXTEND-A02, BLEXT-EXTEND-A03, BLEXT-EXTEND-A04, BLEXT-EXTEND-A06, BLEXT-EXTEND-A07, BLEXT-EXTEND-A08, BLEXT-EXTEND-A11, BLEXT-EXTEND-A12.
    function test_whenAnyViewerQuotesWithoutAuthorizationRead(
        address viewer_
    ) public givenMockDebt {
        // Poison the complete authorization selector: neither viewer nor borrower grants may be read.
        vm.mockCallRevert(
            address(_auth),
            abi.encodeWithSelector(IOperatorAuth.captureAuthorization.selector),
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidContext.selector)
        );
        _assertPermissionlessQuote(viewer_);
    }

    function _assertPermissionlessQuote(address viewer_) private {
        bytes32 beforeState = _stateDigest(viewer_);
        uint48 oldMaturity = _position().maturity;
        vm.recordLogs();
        vm.prank(viewer_);
        IBurnerLoansDebt.ExtendPreview memory quote = _debt.previewExtend(
            address(_asset),
            _borrower,
            1,
            0,
            address(0)
        );
        assertEq(quote.fee, 0, "independent zero-fee expectation");
        assertEq(
            quote.maturity,
            uint256(oldMaturity) + 30 days,
            "quote extends specified borrower's stored maturity"
        );
        assertEq(quote.healthFactor, _HEALTH, "independent Risk health response");
        assertEq(vm.getRecordedLogs().length, 0, "quote emits no logs");
        assertEq(_stateDigest(viewer_), beforeState, "quote preserves wallets, debt and custody");
    }

    // Scenarios: BLEXT-EXTEND-A06, BLEXT-EXTEND-A13.
    function test_givenNoGrant_whenUnrelatedViewerQuotes() public givenMockDebt {
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer);
        _expectExtendExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidContext.selector),
            1,
            0,
            _recipient
        );
    }

    // Scenarios: BLEXT-EXTEND-A02, BLEXT-EXTEND-A11, BLEXT-EXTEND-A13.
    function test_givenValidGrant_whenUnrelatedViewerQuotes() public givenMockDebt {
        _authorizeOperator(_recipient, 10);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer);
        vm.prank(_recipient);
        _debt.extend(address(_asset), _borrower, 1, 0, address(0));
    }

    // Scenarios: BLEXT-EXTEND-A03, BLEXT-EXTEND-A13.
    function test_givenGrantDeadline_whenUnrelatedViewerQuotes() public givenMockDebt {
        _authorizeOperator(_recipient, 10);
        vm.warp(10);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer);
        vm.prank(_recipient);
        _debt.extend(address(_asset), _borrower, 1, 0, address(0));
    }

    // Scenarios: BLEXT-EXTEND-A08, BLEXT-EXTEND-A13.
    function test_givenExpiredGrant_whenUnrelatedViewerQuotes() public givenMockDebt {
        _authorizeOperator(_recipient, 10);
        vm.warp(11);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer);
        _expectExtendExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_ExpiredGrant.selector, uint48(10)),
            1,
            0,
            _recipient
        );
    }

    // Scenarios: BLEXT-EXTEND-A07, BLEXT-EXTEND-A13.
    function test_givenRevokedGrant_whenUnrelatedViewerQuotes() public givenMockDebt {
        _authorizeOperator(_recipient, 10);
        vm.prank(_borrower);
        _auth.cancelGrant(_recipient);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer);
        _expectExtendExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidContext.selector),
            1,
            0,
            _recipient
        );
    }

    // Scenarios: BLEXT-EXTEND-A14.
    function test_whenViewerHasNoPosition_thenSpecifiedBorrowerQuoted() public givenMockDebt {
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer);
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_NoDebt.selector);
        vm.prank(viewer);
        _debt.previewExtend(address(_asset), viewer, 1, 0, address(0));
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, unsafe-typecast, unused-return)
