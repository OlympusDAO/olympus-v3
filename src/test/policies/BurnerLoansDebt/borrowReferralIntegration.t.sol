// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansRiskConfigTimelock} from "src/policies/burnerloans/BurnerLoansRiskConfigTimelock.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {BurnerLoansDebtIntegrationTest} from "./fixtures/BurnerLoansDebtIntegrationTest.sol";

contract BurnerLoansDebtBorrowReferralIntegrationTest is BurnerLoansDebtIntegrationTest {
    error FundingFailed();
    error FeeCalculationFailed(uint256 code);
    address internal _referrer = address(0xFEED);
    address internal _secondReferrer = address(0xBEEF);

    modifier givenReferralConfigured() {
        _risk.setReferralFeeBps(2500);
        _risk.setReferrerAllowed(_referrer, true);
        _risk.setReferrerAllowed(_secondReferrer, true);
        _depositCollateral(2000e6);
        _;
    }

    // Scenarios: BLDEBT-BORROW-I10.
    function test_givenWhitelistedPayout_whenPositiveReferral_reverts()
        public
        givenReferralConfigured
    {
        _risk.setReferrerAllowed(address(_payout), true);
        _risk.setReferralFeeBps(10000);
        bytes32 beforeState = _stateDigest(_borrower);
        bytes memory reason = abi.encodeWithSelector(
            IBurnerLoansPayout.BurnerLoansPayout_InvalidRecipient.selector,
            address(_payout)
        );
        vm.expectRevert(reason);
        _debt.previewBorrow(address(_asset), 100e9, _borrower, _borrower, 312500, address(_payout));
        vm.expectRevert(reason);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 312500, address(_payout));
        assertEq(
            _stateDigest(_borrower),
            beforeState,
            "Rejected self referral preserves all state"
        );
    }

    // Scenarios: BLDEBT-BORROW-P24.
    function test_givenWhitelistedPayout_whenReferralShareZero() public givenReferralConfigured {
        _risk.setReferrerAllowed(address(_payout), true);
        _risk.setReferralFeeBps(0);
        uint256 payerBefore = _asset.balanceOf(_borrower);
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        IBurnerLoansDebt.BorrowPreview memory quote = _debt.previewBorrow(
            address(_asset),
            100e9,
            _borrower,
            _borrower,
            312500,
            address(_payout)
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            100e9,
            _borrower,
            _borrower,
            312500,
            address(_payout)
        );
        // Share is zero: the independently known total fee goes entirely to the protocol.
        assertEq(quote.fee, 312500, "Quote retains the full protocol fee");
        assertEq(result.fee, 312500, "Execution agrees with the independent quote");
        assertEq(_asset.balanceOf(_borrower), payerBefore - 312500, "Payer funds protocol fee");
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + 312500,
            "Protocol fee delivered"
        );
        assertEq(
            _payout.pendingReferralFee(address(_asset), address(_payout)),
            0,
            "No self entitlement recorded"
        );
    }

    // Scenarios: BLDEBT-BORROW-P23, BLDEBT-BORROW-A15.
    function test_givenRealRisk_whenOperatorBorrows() public givenReferralConfigured {
        _authorizeOperator(_recipient, type(uint48).max);
        _fundFeePayer(_recipient, 312500);
        uint256 payerBefore = _asset.balanceOf(_recipient);
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        IBurnerLoansDebt.BorrowPreview memory quote = _debt.previewBorrow(
            address(_asset),
            100e9,
            _borrower,
            _borrower,
            312500,
            _referrer
        );
        vm.expectEmit(address(_debt));
        emit IBurnerLoansDebt.Borrowed(
            _recipient,
            address(_asset),
            _borrower,
            _borrower,
            100e9,
            234375,
            _referrer,
            78125
        );
        vm.prank(_recipient);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            100e9,
            _borrower,
            _borrower,
            312500,
            _referrer
        );
        // Required backing=125e6 raw collateral, rate=25 bps. F=312500 (6 decimals).
        // Referral=floor(312500*2500/10000)=78125; protocol residual=234375.
        assertEq(result.fee, 312500, "Independent total borrow fee");
        assertEq(quote.fee, 312500, "Independent quoted total");
        assertEq(_asset.balanceOf(_recipient), payerBefore - 312500, "Operator pays whole fee");
        assertEq(
            _asset.balanceOf(_referrer),
            78125,
            "Referral recipient paid exact earned allocation"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + 234375,
            "Protocol receives only protocol component"
        );
        assertEq(_asset.balanceOf(address(_core)), 0, "No fee retained in Core");
        assertEq(_asset.balanceOf(address(_payout)), 0, "Successful payouts leave no new reserve");
        assertEq(
            _ohm.balanceOf(_borrower),
            100e9,
            "Borrower receives principal independently of operator and referrer"
        );
        assertEq(_position().principalDue, 100e9, "Canonical position records principal only");
    }

    // Scenarios: BLDEBT-BORROW-I09.
    function test_givenReferrerRemovedAfterQuote_whenBorrowed_reverts()
        public
        givenReferralConfigured
    {
        _debt.previewBorrow(address(_asset), 100e9, _borrower, _borrower, 312500, _referrer);
        _risk.setReferrerAllowed(_referrer, false);
        bytes32 beforeState = _stateDigest(_borrower);
        bytes memory reason = abi.encodeWithSelector(
            IBurnerLoansRisk.BurnerLoansRisk_ReferrerNotAllowed.selector,
            _referrer
        );
        vm.expectRevert(reason);
        _debt.previewBorrow(address(_asset), 100e9, _borrower, _borrower, 312500, _referrer);
        vm.expectRevert(reason);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 312500, _referrer);
        assertEq(
            _stateDigest(_borrower),
            beforeState,
            "Removed attribution cannot settle or alter the position"
        );
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            100e9,
            _borrower,
            _borrower,
            312500,
            address(0)
        );
        assertEq(result.fee, 312500, "Retry without referral preserves total fee");
        assertEq(_asset.balanceOf(_referrer), 0, "Retry without referral pays no reward");
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + 312500,
            "No referral leaves the protocol the full fee"
        );
    }

    // Scenarios: BLDEBT-BORROW-P22, BLDEBT-BORROW-T09.
    function test_givenPendingReferralFee_whenShareChangesAfterQuote()
        public
        givenReferralConfigured
    {
        vm.mockCall(
            address(_asset),
            abi.encodeWithSelector(_asset.transfer.selector, _referrer),
            abi.encode(false)
        );
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 312500, _referrer);
        assertEq(
            _payout.pendingReferralFee(address(_asset), _referrer),
            78125,
            "First earned amount remains pending"
        );
        IBurnerLoansDebt.BorrowPreview memory oldQuote = _debt.previewBorrow(
            address(_asset),
            100e9,
            _borrower,
            _borrower,
            314063,
            _referrer
        );
        assertEq(oldQuote.fee, 314063, "Old quote returns total fee only");
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        _risk.setReferralFeeBps(10000);
        vm.expectEmit(address(_debt));
        emit IBurnerLoansDebt.Borrowed(
            _borrower,
            address(_asset),
            _borrower,
            _borrower,
            100e9,
            0,
            _referrer,
            314063
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            100e9,
            _borrower,
            _borrower,
            314063,
            _referrer
        );
        assertEq(result.fee, 314063, "Changing split leaves gross curve unchanged");
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore,
            "Full share leaves no new protocol allocation"
        );
        assertEq(
            _payout.pendingReferralFee(address(_asset), _referrer),
            392188,
            "Old 78125 is preserved and new 314063 added"
        );
        assertEq(
            _asset.balanceOf(address(_payout)),
            392188,
            "Both deferred credits remain fully backed"
        );
        assertEq(
            _position().principalDue,
            200e9,
            "Optional referral failure does not cancel top-up"
        );
    }

    // Scenarios: BLDEBT-BORROW-P21.
    function test_whenSuccessiveBorrowsChooseDifferentReferrers() public givenReferralConfigured {
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 312500, _referrer);
        uint48 originalMaturity = _position().maturity;
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        _price.setTimestamp(uint48(vm.getBlockTimestamp()));
        _authorizeOperator(_recipient, type(uint48).max);
        _fundFeePayer(_recipient, 314063);
        vm.prank(_recipient);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 314063, _secondReferrer);
        assertEq(
            _position().maturity,
            originalMaturity,
            "A top-up with a new referrer preserves the debt episode deadline"
        );
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        _price.setTimestamp(uint48(vm.getBlockTimestamp()));
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory third = _debt.borrow(
            address(_asset),
            100e9,
            _borrower,
            _borrower,
            315625,
            address(0)
        );
        assertEq(
            _asset.balanceOf(_referrer),
            78125,
            "First referrer only gets first transaction reward"
        );
        assertEq(
            _asset.balanceOf(_secondReferrer),
            78515,
            "Second referrer only gets second transaction reward"
        );
        assertEq(third.fee, 315625, "Third return exposes total fee");
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + 315625,
            "Third fee all belongs to protocol"
        );
        assertEq(_position().principalDue, 300e9, "All three principal increments settle");
        assertEq(
            third.maturity,
            originalMaturity,
            "Explicitly clearing attribution also preserves original maturity"
        );
    }

    // Scenarios: BLDEBT-BORROW-T12.
    function test_givenReferralDeliveredOrDeferred_whenPrincipalFundingFails_reverts(
        bool deferred_
    ) public givenReferralConfigured {
        if (deferred_)
            vm.mockCall(
                address(_asset),
                abi.encodeWithSelector(_asset.transfer.selector, _referrer),
                abi.encode(false)
            );
        vm.mockCallRevert(
            address(_inventory),
            abi.encodeWithSelector(IBurnerLoansInventory.draw.selector),
            abi.encodeWithSelector(FundingFailed.selector)
        );
        bytes32 beforeState = _stateDigest(_borrower);
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        vm.expectRevert(FundingFailed.selector);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 312500, _referrer);
        assertEq(
            _stateDigest(_borrower),
            beforeState,
            "Failed principal funding rolls back the entire origination"
        );
        assertEq(_asset.balanceOf(_referrer), 0, "Delivered referral rolls back with failed loan");
        assertEq(
            _payout.pendingReferralFee(address(_asset), _referrer),
            0,
            "Deferred referral also rolls back with failed loan"
        );
        assertEq(
            _payout.getPendingReferralRecipients(address(_asset)).length,
            0,
            "No reverted recipient index survives"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore,
            "Protocol delivery rolls back too"
        );
    }

    // Scenarios: BLDEBT-BORROW-T13.
    function test_givenStaleCache_whenRiskFeeFails_reverts() public givenReferralConfigured {
        PriceCache cache = _installPriceCache();
        _expireCacheAndHalveCollateralPrice();
        bytes32 cached = keccak256(
            abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))
        );
        bytes32 beforeState = _stateDigest(_borrower);
        bytes memory reason = abi.encodeWithSelector(FeeCalculationFailed.selector, uint256(17));
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            reason
        );
        vm.expectRevert(reason);
        _debt.previewBorrow(
            address(_asset),
            100e9,
            _borrower,
            _borrower,
            type(uint256).max,
            _referrer
        );
        vm.expectRevert(reason);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, type(uint256).max, _referrer);
        assertEq(
            keccak256(abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))),
            cached,
            "Earlier cache refresh rolls back after fee error"
        );
        assertEq(
            _stateDigest(_borrower),
            beforeState,
            "Risk fee error leaves all lending accounting unchanged"
        );
    }

    // Scenarios: BLDEBT-BORROW-D12.
    function test_givenRiskOperatorChanged_whenBorrowed() public givenReferralConfigured {
        _risk.setConfigOperator(address(0xD00D));
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            100e9,
            _borrower,
            _borrower,
            312500,
            _referrer
        );
        assertEq(
            _asset.balanceOf(_referrer),
            78125,
            "Stored referral policy remains usable without selected upstream operator lifecycle"
        );
        assertEq(result.fee, 312500, "Total fee remains unchanged after operator change");
    }

    // Scenarios: BLDEBT-BORROW-P20.
    function test_givenZeroGrossFee_whenAllowedReferrerBorrowed() public givenReferralConfigured {
        _config.setAssetFeeConfig(address(_asset), IBurnerLoansRisk.AssetFeeConfig(0, 0, 0, 0));
        _payout.disable("");
        vm.prank(_borrower);
        _asset.approve(address(_core), 0);
        uint256 payerBefore = _asset.balanceOf(_borrower);
        vm.expectCall(
            address(_payout),
            abi.encodeWithSelector(IBurnerLoansPayout.creditFee.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_asset),
            abi.encodeWithSelector(_asset.transferFrom.selector),
            uint64(0)
        );
        IBurnerLoansDebt.BorrowPreview memory quote = _debt.previewBorrow(
            address(_asset),
            100e9,
            _borrower,
            _borrower,
            0,
            _referrer
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            100e9,
            _borrower,
            _borrower,
            0,
            _referrer
        );
        assertEq(quote.fee, 0, "Real zero curve quotes no charge");
        assertEq(result.fee, 0, "Real zero curve incurs no charge");
        assertEq(_asset.balanceOf(_borrower), payerBefore, "No collateral fee collection");
        assertEq(_position().principalDue, 100e9, "Principal still settles while Payout is paused");
        assertEq(
            _payout.pendingReferralFee(address(_asset), _referrer),
            0,
            "Zero reward creates no liability"
        );
        assertEq(
            _payout.getPendingReferralRecipients(address(_asset)).length,
            0,
            "Zero reward creates no recipient index"
        );
    }

    // Scenarios: BLDEBT-BORROW-D12, BLRISK-SPLIT-P02.
    function test_givenRiskQueueLifecycle_whenBorrowed(
        bool active_,
        bool enabled_
    ) public givenReferralConfigured {
        BurnerLoansRiskConfigTimelock queue = new BurnerLoansRiskConfigTimelock(
            _kernel,
            IBurnerLoansRisk(address(_risk))
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(queue));
        _risk.setConfigOperator(address(queue));
        queue.enable("");
        if (!enabled_) queue.disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(queue));
        assertEq(
            _kernel.isPolicyActive(queue),
            active_,
            "Real queue membership independently selected"
        );
        assertEq(queue.isEnabled(), enabled_, "Real queue pause independently selected");
        bytes memory unavailable = abi.encodeWithSelector(
            FeeCalculationFailed.selector,
            uint256(99)
        );
        vm.mockCallRevert(address(queue), abi.encodeWithSignature("kernel()"), unavailable);
        vm.mockCallRevert(address(queue), abi.encodeWithSignature("isEnabled()"), unavailable);
        vm.expectCall(address(queue), abi.encodeWithSignature("kernel()"), uint64(0));
        vm.expectCall(address(queue), abi.encodeWithSignature("isEnabled()"), uint64(0));
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        IBurnerLoansDebt.BorrowPreview memory quote = _debt.previewBorrow(
            address(_asset),
            100e9,
            _borrower,
            _borrower,
            312500,
            _referrer
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            100e9,
            _borrower,
            _borrower,
            312500,
            _referrer
        );
        assertEq(quote.fee, 312500, "Independent gross quote survives upstream queue drift");
        assertEq(result.fee, 312500, "Gross fee remains unchanged across queue states");
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + 234375,
            "Protocol settlement ignores upstream queue lifecycle"
        );
        assertEq(
            _asset.balanceOf(_referrer),
            78125,
            "Referral settlement ignores upstream queue lifecycle"
        );
        assertEq(
            _risk.configOperator(),
            address(queue),
            "Queue remains selected while unavailable"
        );
    }

    // Scenarios: BLDEBT-BORROW-D12, BLRISK-SPLIT-P02.
    function test_givenRiskQueueOperational_whenBorrowed() public {
        test_givenRiskQueueLifecycle_whenBorrowed(true, true);
    }

    // Scenarios: BLDEBT-BORROW-D12, BLRISK-SPLIT-P02.
    function test_givenRiskQueuePaused_whenBorrowed() public {
        test_givenRiskQueueLifecycle_whenBorrowed(true, false);
    }

    // Scenarios: BLDEBT-BORROW-D12, BLRISK-SPLIT-P02.
    function test_givenRiskQueueInactive_whenBorrowed() public {
        test_givenRiskQueueLifecycle_whenBorrowed(false, true);
    }

    // Scenarios: BLDEBT-BORROW-D12, BLRISK-SPLIT-P02.
    function test_givenRiskQueueInactivePaused_whenBorrowed() public {
        test_givenRiskQueueLifecycle_whenBorrowed(false, false);
    }
}
