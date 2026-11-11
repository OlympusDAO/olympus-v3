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

contract BurnerLoansDebtBorrowReferralTest is BurnerLoansReferralTest {
    function setUp() public override {
        super.setUp();
        _depositCollateral(2000e6);
        _mockRisk(0);
    }

    // Scenarios: BLDEBT-BORROW-I10.
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
            abi.encodeWithSelector(IBurnerLoansCore.settleBorrow.selector),
            uint64(0)
        );
        vm.expectRevert(reason);
        _debt.previewBorrow(
            address(_asset),
            100e9,
            _borrower,
            _recipient,
            type(uint256).max,
            address(_payout)
        );
        vm.expectRevert(reason);
        vm.prank(payer);
        _debt.borrow(
            address(_asset),
            100e9,
            _borrower,
            _recipient,
            type(uint256).max,
            address(_payout)
        );
        assertEq(
            _stateDigest(payer),
            beforeState,
            "Invalid referral cannot change custody or debt"
        );
    }

    // Scenarios: BLDEBT-BORROW-I10.
    function test_whenOneUnitSelfReferral_reverts() public {
        test_whenReferrerIsPayout_whenAllocationPositive_reverts(1, false);
    }

    // Scenarios: BLDEBT-BORROW-I10.
    function test_whenMaximumSelfReferral_reverts() public {
        test_whenReferrerIsPayout_whenAllocationPositive_reverts(type(uint256).max, true);
    }

    // Scenarios: BLDEBT-BORROW-P24.
    function test_whenReferrerIsPayout_whenAllocationZero(
        uint256 protocol_,
        bool operator_
    ) public {
        _referrer = address(_payout);
        test_whenRiskReturnsComponents(protocol_, 0, operator_);
    }

    // Scenarios: BLDEBT-BORROW-P24.
    function test_whenSelfReferrerZeroFee() public {
        test_whenReferrerIsPayout_whenAllocationZero(0, false);
    }

    // Scenarios: BLDEBT-BORROW-P24.
    function test_whenSelfReferrerMaximumProtocolFee() public {
        test_whenReferrerIsPayout_whenAllocationZero(type(uint256).max, true);
    }

    // Scenarios: BLDEBT-BORROW-A15.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
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
        uint48 maturity = uint48(vm.getBlockTimestamp() + 30 days);
        IBurnerLoansCore.BorrowRequest memory instruction = IBurnerLoansCore.BorrowRequest(
            address(_asset),
            _borrower,
            payer,
            _recipient,
            100e9,
            maturity,
            protocol_,
            _referrer,
            referral_
        );
        vm.mockCall(
            address(_core),
            abi.encodeCall(
                IBurnerLoansCore.settleBorrow,
                (instruction, payer, _operatorAuthContext(_borrower, payer, 2))
            ),
            abi.encode(uint128(100e9), maturity)
        );
        vm.expectCall(
            address(_core),
            abi.encodeCall(
                IBurnerLoansCore.settleBorrow,
                (instruction, payer, _operatorAuthContext(_borrower, payer, 2))
            ),
            uint64(1)
        );
        vm.expectCall(address(_risk), _feeCall(100e9, 1, _referrer), uint64(2));
        uint256 beforePayer = _asset.balanceOf(payer);
        IBurnerLoansDebt.BorrowPreview memory quote = _debt.previewBorrow(
            address(_asset),
            100e9,
            _borrower,
            _recipient,
            total,
            _referrer
        );
        vm.expectEmit(address(_debt));
        emit IBurnerLoansDebt.Borrowed(
            payer,
            address(_asset),
            _borrower,
            _recipient,
            100e9,
            protocol_,
            _referrer,
            referral_
        );
        vm.prank(payer);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            100e9,
            _borrower,
            _recipient,
            total,
            _referrer
        );
        assertEq(
            abi.encode(quote).length,
            4 * 32,
            "Borrow quote exposes only total fee and position"
        );
        assertEq(
            abi.encode(result).length,
            4 * 32,
            "Borrow result exposes only total fee and position"
        );
        assertEq(result.fee, total, "Existing total fee combines both components");
        assertEq(quote.fee, total, "Quote limits use combined fee");
        assertEq(
            _asset.balanceOf(payer),
            beforePayer,
            "Debt unit forwards settlement without collecting tokens"
        );
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: BLDEBT-BORROW-I08.
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
            abi.encodeWithSelector(IBurnerLoansCore.settleBorrow.selector),
            uint64(0)
        );
        vm.expectRevert(reason);
        _debt.previewBorrow(address(_asset), 100e9, _borrower, _recipient, maximum_, _referrer);
        vm.expectRevert(reason);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _recipient, maximum_, _referrer);
    }

    // Scenarios: BLDEBT-BORROW-N12.
    function test_whenComponentSumOverflows_reverts(uint256 protocol_, uint256 referral_) public {
        protocol_ = bound(protocol_, 1, type(uint256).max);
        referral_ = bound(referral_, type(uint256).max - protocol_ + 1, type(uint256).max);
        _mockFeeComponents(protocol_, referral_);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", uint256(0x11)));
        _debt.previewBorrow(
            address(_asset),
            100e9,
            _borrower,
            _recipient,
            type(uint256).max,
            _referrer
        );
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", uint256(0x11)));
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _recipient, type(uint256).max, _referrer);
    }

    // Scenarios: BLDEBT-BORROW-T13.
    function test_whenRiskFeeReverts_reverts(bytes memory reason_) public {
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            reason_
        );
        vm.expectCall(
            address(_core),
            abi.encodeWithSelector(IBurnerLoansCore.settleBorrow.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_payout),
            abi.encodeWithSelector(IBurnerLoansPayout.creditFee.selector),
            uint64(0)
        );
        bytes32 beforeState = _stateDigest(_borrower);
        // Even empty data is an exact configured dependency failure, not an unspecified expected revert.
        vm.expectRevert(reason_);
        _debt.previewBorrow(
            address(_asset),
            100e9,
            _borrower,
            _recipient,
            type(uint256).max,
            _referrer
        );
        vm.expectRevert(reason_);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _recipient, type(uint256).max, _referrer);
        assertEq(
            _stateDigest(_borrower),
            beforeState,
            "Risk failure leaves settlement and balances untouched"
        );
    }

    // Scenarios: BLDEBT-BORROW-A16.
    // Controlled test bindings/callers intentionally retain zero-address cases where applicable.
    // forge-lint: disable-start(missing-zero-check)
    function test_givenOnlyOtherOperatorAuthorized_whenReferrerBorrows_reverts(
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
        _debt.previewBorrow(address(_asset), 100e9, _borrower, _recipient, 101, _referrer);
        bytes32 beforeState = _stateDigest(caller_);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        vm.prank(_referrer);
        _debt.borrow(address(_asset), 100e9, _borrower, _recipient, 101, _referrer);
        assertEq(
            _stateDigest(caller_),
            beforeState,
            "Whitelist membership grants no borrower authority"
        );
    }

    // forge-lint: disable-end(missing-zero-check)

    // Scenarios: BLDEBT-BORROW-A15, BLDEBT-BORROW-P20.
    function test_whenZeroComponents() public {
        test_whenRiskReturnsComponents(0, 0, false);
    }

    // Scenarios: BLDEBT-BORROW-A15.
    function test_whenOneProtocolUnit() public {
        test_whenRiskReturnsComponents(1, 0, true);
    }

    // Scenarios: BLDEBT-BORROW-A15.
    function test_whenOneReferralUnit() public {
        test_whenRiskReturnsComponents(0, 1, false);
    }

    // Scenarios: BLDEBT-BORROW-A15.
    function test_whenLiteralSplit() public {
        test_whenRiskReturnsComponents(76, 25, true);
    }

    // Scenarios: BLDEBT-BORROW-A15.
    function test_whenMaximumProtocolComponent() public {
        test_whenRiskReturnsComponents(type(uint256).max, 0, false);
    }

    // Scenarios: BLDEBT-BORROW-A15.
    function test_whenMaximumReferralComponent() public {
        test_whenRiskReturnsComponents(0, type(uint256).max, true);
    }

    // Scenarios: BLDEBT-BORROW-P19.
    function test_whenZeroReferrer(uint256 protocol_) public {
        _referrer = address(0);
        test_whenRiskReturnsComponents(protocol_, 0, false);
    }

    // Scenarios: BLDEBT-BORROW-T13.
    function test_whenEmptyRiskError_reverts() public {
        test_whenRiskFeeReverts_reverts(bytes(""));
    }

    // Scenarios: BLDEBT-BORROW-T13.
    function test_whenTypedRiskError_reverts() public {
        test_whenRiskFeeReverts_reverts(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_ReferrerNotAllowed.selector,
                _referrer
            )
        );
    }

    // Scenarios: BLDEBT-BORROW-T13.
    function test_whenPanicRiskError_reverts() public {
        test_whenRiskFeeReverts_reverts(abi.encodeWithSignature("Panic(uint256)", uint256(0x11)));
    }

    // Scenarios: BLDEBT-BORROW-A15.
    function test_whenReferrerIsBorrower() public {
        _referrer = _borrower;
        test_whenRiskReturnsComponents(76, 25, false);
    }

    // Scenarios: BLDEBT-BORROW-A15.
    function test_whenReferrerIsOperator() public {
        _referrer = _recipient;
        test_whenRiskReturnsComponents(76, 25, true);
    }

    // Scenarios: BLDEBT-BORROW-A15.
    // Controlled test bindings/callers intentionally retain zero-address cases where applicable.
    // forge-lint: disable-start(missing-zero-check)
    function test_whenReferrerVaries(address referrer_, bool operator_) public {
        vm.assume(referrer_ != address(0) && referrer_ != address(_payout));
        _referrer = referrer_;
        test_whenRiskReturnsComponents(76, 25, operator_);
    }

    // forge-lint: disable-end(missing-zero-check)

    // Scenarios: BLDEBT-BORROW-I08.
    function test_whenFeeLimitEqualsProtocol_reverts() public {
        test_whenMaxFeeExcludesReferral_reverts(76, 25, 76);
    }

    // Scenarios: BLDEBT-BORROW-I08.
    function test_whenFeeLimitImmediatelyBelowTotal_reverts() public {
        test_whenMaxFeeExcludesReferral_reverts(76, 25, 100);
    }

    // Scenarios: BLDEBT-BORROW-I08.
    function test_whenMaximumTotalExceedsFeeLimit_reverts() public {
        test_whenMaxFeeExcludesReferral_reverts(0, type(uint256).max, type(uint256).max - 1);
    }

    // Scenarios: BLDEBT-BORROW-N12.
    function test_whenMinimumProtocolOverflows_reverts() public {
        test_whenComponentSumOverflows_reverts(1, type(uint256).max);
    }

    // Scenarios: BLDEBT-BORROW-N12.
    function test_whenMaximumProtocolOverflows_reverts() public {
        test_whenComponentSumOverflows_reverts(type(uint256).max, 1);
    }
}
// forge-lint: disable-end(unused-return)
