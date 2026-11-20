// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansReferralTest} from "./fixtures/BurnerLoansReferralTest.sol";

contract BurnerLoansDebtExtendReferralTest is BurnerLoansReferralTest {
    function setUp() public override {
        super.setUp();
        _depositCollateral(2000e6);
        _mockRisk(0);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 0, address(0));
    }

    // Scenarios: BLEXT-EXTEND-I09.
    function test_whenReferrerIsPayout_whenAllocationPositive_reverts(
        uint256 referral_,
        bool operator_
    ) public {
        referral_ = bound(referral_, 1, type(uint256).max);
        _mockFeeComponents(0, referral_);
        address payer = _authorizeFeePayer(operator_);
        bytes32 beforeState = _stateDigest(payer);
        bytes memory reason = abi.encodeWithSelector(
            IBurnerLoansPayout.BurnerLoansPayout_InvalidRecipient.selector,
            address(_payout)
        );
        vm.expectCall(
            address(_core),
            abi.encodeWithSelector(IBurnerLoansCore.settleExtend.selector),
            uint64(0)
        );
        vm.expectRevert(reason);
        _debt.previewExtend(address(_asset), _borrower, 1, type(uint256).max, address(_payout));
        vm.expectRevert(reason);
        vm.prank(payer);
        _debt.extend(address(_asset), _borrower, 1, type(uint256).max, address(_payout));
        assertEq(
            _stateDigest(payer),
            beforeState,
            "Invalid referral cannot change custody or debt"
        );
    }

    // Scenarios: BLEXT-EXTEND-I09.
    function test_whenOneUnitSelfReferral_reverts() public {
        test_whenReferrerIsPayout_whenAllocationPositive_reverts(1, false);
    }

    // Scenarios: BLEXT-EXTEND-I09.
    function test_whenMaximumSelfReferral_reverts() public {
        test_whenReferrerIsPayout_whenAllocationPositive_reverts(type(uint256).max, true);
    }

    // Scenarios: BLEXT-EXTEND-P17.
    function test_whenReferrerIsPayout_whenAllocationZero(
        uint256 protocol_,
        bool operator_
    ) public {
        _referrer = address(_payout);
        test_whenRiskReturnsComponents(protocol_, 0, operator_);
    }

    // Scenarios: BLEXT-EXTEND-P17.
    function test_whenSelfReferrerZeroFee() public {
        test_whenReferrerIsPayout_whenAllocationZero(0, false);
    }

    // Scenarios: BLEXT-EXTEND-P17.
    function test_whenSelfReferrerMaximumProtocolFee() public {
        test_whenReferrerIsPayout_whenAllocationZero(type(uint256).max, true);
    }

    // Scenarios: BLEXT-EXTEND-A15.
    function test_whenRiskReturnsComponents(
        uint256 protocol_,
        uint256 referral_,
        bool operator_
    ) public {
        referral_ = bound(referral_, 0, type(uint256).max - protocol_);
        uint256 total = protocol_ + referral_;
        address payer = _authorizeFeePayer(operator_);
        _mockFeeComponents(protocol_, referral_);
        vm.expectCall(
            address(_payout),
            abi.encodeCall(IBurnerLoansPayout.validatePayoutRecipient, (_referrer)),
            referral_ == 0 ? uint64(0) : uint64(2)
        );
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.referralFeeBps.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.isReferrerAllowed.selector),
            uint64(0)
        );
        uint48 maturity = _position().maturity + 60 days;
        bytes memory instruction = abi.encodeCall(
            IBurnerLoansCore.settleExtend,
            (
                IBurnerLoansCore.ExtendRequest({
                    asset: address(_asset),
                    borrower: _borrower,
                    payer: payer,
                    maturity: maturity,
                    protocolFee: protocol_,
                    referrer: _referrer,
                    referralFee: referral_
                }),
                payer,
                _operatorAuthContext(_borrower, payer, 8)
            )
        );
        vm.mockCall(address(_core), instruction, abi.encode(maturity));
        vm.expectCall(address(_core), instruction, uint64(1));
        vm.expectCall(address(_risk), _feeCall(100e9, 2, _referrer), uint64(2));
        uint256 beforePayer = _asset.balanceOf(payer);
        IBurnerLoansDebt.ExtendPreview memory quote = _debt.previewExtend(
            address(_asset),
            _borrower,
            2,
            total,
            _referrer
        );
        vm.expectEmit(address(_debt));
        emit IBurnerLoansDebt.Extended(
            payer,
            address(_asset),
            _borrower,
            maturity,
            protocol_,
            _referrer,
            referral_
        );
        vm.prank(payer);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            2,
            total,
            _referrer
        );
        assertEq(
            abi.encode(quote).length,
            3 * 32,
            "Extension quote exposes only total fee and position"
        );
        assertEq(
            abi.encode(result).length,
            3 * 32,
            "Extension result exposes only total fee and position"
        );
        assertEq(result.fee, total, "Existing total fee combines both components");
        assertEq(quote.fee, total, "Quote limits use combined fee");
        assertEq(result.maturity, maturity, "Settlement receives requested extended maturity");
        assertEq(
            _asset.balanceOf(payer),
            beforePayer,
            "Debt unit forwards settlement without collecting tokens"
        );
    }

    // Scenarios: BLEXT-EXTEND-I07.
    function test_whenMaxFeeExcludesReferral_reverts(
        uint256 protocol_,
        uint256 referral_,
        uint256 maximum_
    ) public {
        protocol_ = bound(protocol_, 0, type(uint256).max - 1);
        referral_ = bound(referral_, 1, type(uint256).max - protocol_);
        uint256 total = protocol_ + referral_;
        maximum_ = bound(maximum_, protocol_, total - 1);
        _mockFeeComponents(protocol_, referral_);
        bytes memory reason = abi.encodeWithSelector(
            IBurnerLoansDebt.BurnerLoans_FeeExceedsMax.selector,
            total,
            maximum_
        );
        vm.expectCall(
            address(_core),
            abi.encodeWithSelector(IBurnerLoansCore.settleExtend.selector),
            uint64(0)
        );
        vm.expectRevert(reason);
        _debt.previewExtend(address(_asset), _borrower, 1, maximum_, _referrer);
        vm.expectRevert(reason);
        vm.prank(_borrower);
        _debt.extend(address(_asset), _borrower, 1, maximum_, _referrer);
    }

    // Scenarios: BLEXT-EXTEND-N12.
    function test_whenComponentSumOverflows_reverts(uint256 protocol_, uint256 referral_) public {
        protocol_ = bound(protocol_, 1, type(uint256).max);
        referral_ = bound(referral_, type(uint256).max - protocol_ + 1, type(uint256).max);
        _mockFeeComponents(protocol_, referral_);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", uint256(0x11)));
        _debt.previewExtend(address(_asset), _borrower, 1, type(uint256).max, _referrer);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", uint256(0x11)));
        vm.prank(_borrower);
        _debt.extend(address(_asset), _borrower, 1, type(uint256).max, _referrer);
    }

    // Scenarios: BLEXT-EXTEND-T10.
    function test_whenRiskFeeReverts_reverts(bytes memory reason_) public {
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            reason_
        );
        vm.expectCall(
            address(_core),
            abi.encodeWithSelector(IBurnerLoansCore.settleExtend.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_payout),
            abi.encodeWithSelector(IBurnerLoansPayout.creditFee.selector),
            uint64(0)
        );
        bytes32 beforeState = _stateDigest(_borrower);
        // Exact configured dependency failure, including an explicitly empty payload.
        vm.expectRevert(reason_);
        _debt.previewExtend(address(_asset), _borrower, 1, type(uint256).max, _referrer);
        vm.expectRevert(reason_);
        vm.prank(_borrower);
        _debt.extend(address(_asset), _borrower, 1, type(uint256).max, _referrer);
        assertEq(
            _stateDigest(_borrower),
            beforeState,
            "Risk failure preserves maturity, custody and balances"
        );
    }

    // Scenarios: BLEXT-EXTEND-A16.
    // Controlled test bindings/callers intentionally retain zero-address cases where applicable.
    // forge-lint: disable-start(missing-zero-check)
    function test_givenOnlyOtherOperatorAuthorized_whenReferrerExtends_reverts(
        address caller_
    ) public {
        vm.assume(
            caller_ != address(0) &&
                caller_ != _borrower &&
                caller_ != _recipient &&
                caller_ != address(_payout)
        );
        _referrer = caller_;
        _risk.setReferrerAllowed(_referrer, true);
        _authorizeOperator(_recipient, type(uint48).max);
        _mockFeeComponents(76, 25);
        _debt.previewExtend(address(_asset), _borrower, 1, 101, _referrer);
        bytes32 beforeState = _stateDigest(caller_);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        vm.prank(_referrer);
        _debt.extend(address(_asset), _borrower, 1, 101, _referrer);
        assertEq(
            _stateDigest(caller_),
            beforeState,
            "Whitelist membership grants no borrower authority"
        );
    }

    // forge-lint: disable-end(missing-zero-check)

    // Scenarios: BLEXT-EXTEND-A15, BLEXT-EXTEND-P12.
    function test_whenZeroComponents() public {
        test_whenRiskReturnsComponents(0, 0, false);
    }

    // Scenarios: BLEXT-EXTEND-A15.
    function test_whenOneProtocolUnit() public {
        test_whenRiskReturnsComponents(1, 0, true);
    }

    // Scenarios: BLEXT-EXTEND-A15.
    function test_whenOneReferralUnit() public {
        test_whenRiskReturnsComponents(0, 1, false);
    }

    // Scenarios: BLEXT-EXTEND-A15.
    function test_whenLiteralSplit() public {
        test_whenRiskReturnsComponents(76, 25, true);
    }

    // Scenarios: BLEXT-EXTEND-A15.
    function test_whenMaximumProtocolComponent() public {
        test_whenRiskReturnsComponents(type(uint256).max, 0, false);
    }

    // Scenarios: BLEXT-EXTEND-A15.
    function test_whenMaximumReferralComponent() public {
        test_whenRiskReturnsComponents(0, type(uint256).max, true);
    }

    // Scenarios: BLEXT-EXTEND-P11.
    function test_whenZeroReferrer(uint256 protocol_) public {
        _referrer = address(0);
        test_whenRiskReturnsComponents(protocol_, 0, false);
    }

    // Scenarios: BLEXT-EXTEND-T10.
    function test_whenEmptyRiskError_reverts() public {
        test_whenRiskFeeReverts_reverts(bytes(""));
    }

    // Scenarios: BLEXT-EXTEND-T10.
    function test_whenTypedRiskError_reverts() public {
        test_whenRiskFeeReverts_reverts(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_ReferrerNotAllowed.selector,
                _referrer
            )
        );
    }

    // Scenarios: BLEXT-EXTEND-T10.
    function test_whenPanicRiskError_reverts() public {
        test_whenRiskFeeReverts_reverts(abi.encodeWithSignature("Panic(uint256)", uint256(0x11)));
    }

    // Scenarios: BLEXT-EXTEND-A15.
    function test_whenReferrerIsBorrower() public {
        _referrer = _borrower;
        test_whenRiskReturnsComponents(76, 25, false);
    }

    // Scenarios: BLEXT-EXTEND-A15.
    function test_whenReferrerIsOperator() public {
        _referrer = _recipient;
        test_whenRiskReturnsComponents(76, 25, true);
    }

    // Scenarios: BLEXT-EXTEND-A15.
    // Controlled test bindings/callers intentionally retain zero-address cases where applicable.
    // forge-lint: disable-start(missing-zero-check)
    function test_whenReferrerVaries(address referrer_, bool operator_) public {
        vm.assume(referrer_ != address(0) && referrer_ != address(_payout));
        _referrer = referrer_;
        test_whenRiskReturnsComponents(76, 25, operator_);
    }

    // forge-lint: disable-end(missing-zero-check)

    // Scenarios: BLEXT-EXTEND-I07.
    function test_whenFeeLimitEqualsProtocol_reverts() public {
        test_whenMaxFeeExcludesReferral_reverts(76, 25, 76);
    }

    // Scenarios: BLEXT-EXTEND-I07.
    function test_whenFeeLimitImmediatelyBelowTotal_reverts() public {
        test_whenMaxFeeExcludesReferral_reverts(76, 25, 100);
    }

    // Scenarios: BLEXT-EXTEND-I07.
    function test_whenMaximumTotalExceedsFeeLimit_reverts() public {
        test_whenMaxFeeExcludesReferral_reverts(0, type(uint256).max, type(uint256).max - 1);
    }

    // Scenarios: BLEXT-EXTEND-N12.
    function test_whenMinimumProtocolOverflows_reverts() public {
        test_whenComponentSumOverflows_reverts(1, type(uint256).max);
    }

    // Scenarios: BLEXT-EXTEND-N12.
    function test_whenMaximumProtocolOverflows_reverts() public {
        test_whenComponentSumOverflows_reverts(type(uint256).max, 1);
    }
}
// forge-lint: disable-end(unused-return)
