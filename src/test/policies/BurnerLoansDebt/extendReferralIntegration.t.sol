// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansRiskConfigTimelock} from "src/policies/burnerloans/BurnerLoansRiskConfigTimelock.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {BurnerLoansDebtIntegrationTest} from "./fixtures/BurnerLoansDebtIntegrationTest.sol";

contract BurnerLoansDebtExtendReferralIntegrationTest is BurnerLoansDebtIntegrationTest {
    error FeeCalculationFailed(uint256 code);
    address internal _referrer = address(0xFEED);
    address internal _secondReferrer = address(0xBEEF);

    modifier givenReferralDebt() {
        _risk.setReferralFeeBps(2500);
        _risk.setReferrerAllowed(_referrer, true);
        _risk.setReferrerAllowed(_secondReferrer, true);
        _depositCollateral(2000e6);
        vm.mockCall(
            address(_asset),
            abi.encodeWithSelector(_asset.transfer.selector, _referrer),
            abi.encode(false)
        );
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 312500, _referrer);
        _;
    }

    // Scenarios: BLEXT-EXTEND-I09.
    function test_givenWhitelistedPayout_whenPositiveReferral_reverts() public givenReferralDebt {
        _risk.setReferrerAllowed(address(_payout), true);
        _risk.setReferralFeeBps(10000);
        bytes32 beforeState = _stateDigest(_borrower);
        bytes memory reason = abi.encodeWithSelector(
            IBurnerLoansPayout.BurnerLoansPayout_InvalidRecipient.selector,
            address(_payout)
        );
        vm.expectRevert(reason);
        _debt.previewExtend(address(_asset), _borrower, 1, 314063, address(_payout));
        vm.expectRevert(reason);
        vm.prank(_borrower);
        _debt.extend(address(_asset), _borrower, 1, 314063, address(_payout));
        assertEq(
            _stateDigest(_borrower),
            beforeState,
            "Rejected self referral preserves all state"
        );
    }

    // Scenarios: BLEXT-EXTEND-P17.
    function test_givenWhitelistedPayout_whenReferralShareZero() public givenReferralDebt {
        _risk.setReferrerAllowed(address(_payout), true);
        _risk.setReferralFeeBps(0);
        uint256 payerBefore = _asset.balanceOf(_borrower);
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        IBurnerLoansDebt.ExtendPreview memory quote = _debt.previewExtend(
            address(_asset),
            _borrower,
            1,
            314063,
            address(_payout)
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            1,
            314063,
            address(_payout)
        );
        // Share is zero: the independently known total fee goes entirely to the protocol.
        assertEq(quote.fee, 314063, "Quote retains the full protocol fee");
        assertEq(result.fee, 314063, "Execution agrees with the independent quote");
        assertEq(_asset.balanceOf(_borrower), payerBefore - 314063, "Payer funds protocol fee");
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + 314063,
            "Protocol fee delivered"
        );
        assertEq(
            _payout.pendingReferralFee(address(_asset), address(_payout)),
            0,
            "No self entitlement recorded"
        );
    }

    // Scenarios: BLEXT-EXTEND-P15, BLEXT-EXTEND-P16, BLEXT-EXTEND-A15.
    function test_givenBorrowReferrer_whenOperatorExtendsWithAnotherReferrer()
        public
        givenReferralDebt
    {
        _authorizeOperator(_recipient, type(uint48).max);
        _fundFeePayer(_recipient, 314063);
        uint256 payerBefore = _asset.balanceOf(_recipient);
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        uint48 originalMaturity = _position().maturity;
        IBurnerLoansDebt.ExtendPreview memory quote = _debt.previewExtend(
            address(_asset),
            _borrower,
            1,
            314063,
            _secondReferrer
        );
        vm.expectEmit(address(_debt));
        emit IBurnerLoansDebt.Extended(
            _recipient,
            address(_asset),
            _borrower,
            originalMaturity + 30 days,
            235548,
            _secondReferrer,
            78515
        );
        vm.prank(_recipient);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            1,
            314063,
            _secondReferrer
        );
        // Utilization is 0.1%; gross=ceil(125e6*25.125/10000)=314063 raw units.
        // Referral=floor(314063/4)=78515; protocol residual=235548.
        assertEq(quote.fee, 314063, "Independent extension fee");
        assertEq(result.fee, 314063, "Execution returns the total extension fee");
        assertEq(
            _asset.balanceOf(_recipient),
            payerBefore - 314063,
            "Operator pays full combined fee"
        );
        assertEq(
            _asset.balanceOf(_secondReferrer),
            78515,
            "Second referrer receives extension reward"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + 235548,
            "Protocol receives exact component"
        );
        assertEq(
            _payout.pendingReferralFee(address(_asset), _referrer),
            78125,
            "Original borrow reward keeps its owner and amount"
        );
        assertEq(_position().principalDue, 100e9, "Extension preserves principal");
        assertEq(
            result.maturity,
            originalMaturity + 30 days,
            "Extension uses stored deadline and configured term"
        );
        treasuryBefore = _asset.balanceOf(_payout.treasury());
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory next = _debt.extend(
            address(_asset),
            _borrower,
            1,
            314063,
            address(0)
        );
        assertEq(next.fee, 314063, "Later extension returns total fee");
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + 314063,
            "Later zero attribution leaves full protocol fee"
        );
        assertEq(
            _payout.pendingReferralFee(address(_asset), _referrer),
            78125,
            "Later zero attribution cannot consume original pending reward"
        );
        assertEq(
            _asset.balanceOf(_secondReferrer),
            78515,
            "Later zero attribution cannot pay the previous referrer again"
        );
    }

    // Scenarios: BLEXT-EXTEND-I08.
    function test_givenReferrerRemovedAfterQuote_whenExtended_reverts() public givenReferralDebt {
        _debt.previewExtend(address(_asset), _borrower, 1, 314063, _secondReferrer);
        _risk.setReferrerAllowed(_secondReferrer, false);
        bytes32 beforeState = _stateDigest(_borrower);
        bytes memory reason = abi.encodeWithSelector(
            IBurnerLoansRisk.BurnerLoansRisk_ReferrerNotAllowed.selector,
            _secondReferrer
        );
        vm.expectRevert(reason);
        _debt.previewExtend(address(_asset), _borrower, 1, 314063, _secondReferrer);
        vm.expectRevert(reason);
        vm.prank(_borrower);
        _debt.extend(address(_asset), _borrower, 1, 314063, _secondReferrer);
        assertEq(
            _stateDigest(_borrower),
            beforeState,
            "Rejected extension leaves maturity and accrued rewards unchanged"
        );
        assertEq(
            _payout.pendingReferralFee(address(_asset), _referrer),
            78125,
            "Old borrow entitlement is unaffected by another removal"
        );
    }

    // Scenarios: BLEXT-EXTEND-P14.
    function test_givenOldQuote_whenShareChangesBeforeExtension() public givenReferralDebt {
        IBurnerLoansDebt.ExtendPreview memory oldQuote = _debt.previewExtend(
            address(_asset),
            _borrower,
            1,
            314063,
            _secondReferrer
        );
        assertEq(oldQuote.fee, 314063, "Original quote returns total fee only");
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        _risk.setReferralFeeBps(10000);
        vm.expectEmit(address(_debt));
        emit IBurnerLoansDebt.Extended(
            _borrower,
            address(_asset),
            _borrower,
            oldQuote.maturity,
            0,
            _secondReferrer,
            314063
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            1,
            314063,
            _secondReferrer
        );
        assertEq(result.fee, 314063, "Gross fee independent of referral share");
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore,
            "Current full referral share consumes whole fee"
        );
        assertEq(
            _asset.balanceOf(_secondReferrer),
            314063,
            "Current recipient receives whole new fee"
        );
        assertEq(
            _payout.pendingReferralFee(address(_asset), _referrer),
            78125,
            "Old quarter-share credit is never repriced"
        );
    }

    // Scenarios: BLEXT-EXTEND-T07.
    function test_givenReferralDeliveryRejected_whenExtended() public givenReferralDebt {
        uint256 payerBefore = _asset.balanceOf(_borrower);
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        uint48 maturityBefore = _position().maturity;
        vm.prank(_borrower);
        _debt.extend(address(_asset), _borrower, 1, 314063, _referrer);
        assertEq(
            _asset.balanceOf(_borrower),
            payerBefore - 314063,
            "Mandatory combined fee collected"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + 235548,
            "Protocol remainder delivered"
        );
        assertEq(
            _payout.pendingReferralFee(address(_asset), _referrer),
            156640,
            "Old 78125 plus new 78515 remain fixed and pending"
        );
        assertEq(
            _asset.balanceOf(address(_payout)),
            156640,
            "All deferred referral liabilities backed"
        );
        assertEq(
            _position().maturity,
            maturityBefore + 30 days,
            "Optional transfer failure preserves extension"
        );
    }

    // Scenarios: BLEXT-EXTEND-T10.
    function test_givenStaleCache_whenRiskFeeFails_reverts() public givenReferralDebt {
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
        _debt.previewExtend(address(_asset), _borrower, 1, type(uint256).max, _secondReferrer);
        vm.expectRevert(reason);
        vm.prank(_borrower);
        _debt.extend(address(_asset), _borrower, 1, type(uint256).max, _secondReferrer);
        assertEq(
            keccak256(abi.encode(cache.getCachedPrice(address(_ohm), address(_asset)))),
            cached,
            "Failed extension rolls back earlier price refresh"
        );
        assertEq(
            _stateDigest(_borrower),
            beforeState,
            "Fee calculation failure preserves lending and reward state"
        );
    }

    // Scenarios: BLEXT-EXTEND-D06.
    function test_givenRiskOperatorChanged_whenExtended() public givenReferralDebt {
        _risk.setConfigOperator(address(0xD00D));
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            1,
            314063,
            _secondReferrer
        );
        assertEq(
            _asset.balanceOf(_secondReferrer),
            78515,
            "Stored policy operates after upstream operator change"
        );
        assertEq(result.fee, 314063, "Total fee remains unchanged after operator change");
        assertEq(
            _payout.pendingReferralFee(address(_asset), _referrer),
            78125,
            "Prior earned reward remains fixed"
        );
    }

    // Scenarios: BLEXT-EXTEND-P12.
    function test_givenZeroGrossFee_whenAllowedReferrerExtended() public givenReferralDebt {
        _config.setAssetFeeConfig(address(_asset), IBurnerLoansRisk.AssetFeeConfig(0, 0, 0, 0));
        _payout.disable("");
        vm.prank(_borrower);
        _asset.approve(address(_core), 0);
        uint256 payerBefore = _asset.balanceOf(_borrower);
        uint48 maturityBefore = _position().maturity;
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
        IBurnerLoansDebt.ExtendPreview memory quote = _debt.previewExtend(
            address(_asset),
            _borrower,
            1,
            0,
            _secondReferrer
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            1,
            0,
            _secondReferrer
        );
        assertEq(quote.fee, 0, "Real zero curve quotes no extension charge");
        assertEq(result.fee, 0, "No extension charge collected");
        assertEq(_asset.balanceOf(_borrower), payerBefore, "Zero fee needs no payer allowance");
        assertEq(
            result.maturity,
            maturityBefore + 30 days,
            "Extension succeeds independently of paused Payout"
        );
        assertEq(
            _payout.pendingReferralFee(address(_asset), _referrer),
            78125,
            "Existing reward is not swept or repriced by a zero-fee action"
        );
        assertEq(
            _payout.pendingReferralFee(address(_asset), _secondReferrer),
            0,
            "No new zero-reward bucket created"
        );
    }

    // Scenarios: BLEXT-EXTEND-D06, BLRISK-SPLIT-P02.
    function test_givenRiskQueueLifecycle_whenExtended(
        bool active_,
        bool enabled_
    ) public givenReferralDebt {
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
        IBurnerLoansDebt.ExtendPreview memory quote = _debt.previewExtend(
            address(_asset),
            _borrower,
            1,
            314063,
            _secondReferrer
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            1,
            314063,
            _secondReferrer
        );
        assertEq(quote.fee, 314063, "Independent gross quote survives upstream queue drift");
        assertEq(result.fee, 314063, "Gross fee remains unchanged across queue states");
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + 235548,
            "Protocol settlement ignores upstream queue lifecycle"
        );
        assertEq(
            _asset.balanceOf(_secondReferrer),
            78515,
            "Referral settlement ignores upstream queue lifecycle"
        );
        assertEq(
            _risk.configOperator(),
            address(queue),
            "Queue remains selected while unavailable"
        );
    }

    // Scenarios: BLEXT-EXTEND-D06, BLRISK-SPLIT-P02.
    function test_givenRiskQueueOperational_whenExtended() public {
        test_givenRiskQueueLifecycle_whenExtended(true, true);
    }

    // Scenarios: BLEXT-EXTEND-D06, BLRISK-SPLIT-P02.
    function test_givenRiskQueuePaused_whenExtended() public {
        test_givenRiskQueueLifecycle_whenExtended(true, false);
    }

    // Scenarios: BLEXT-EXTEND-D06, BLRISK-SPLIT-P02.
    function test_givenRiskQueueInactive_whenExtended() public {
        test_givenRiskQueueLifecycle_whenExtended(false, true);
    }

    // Scenarios: BLEXT-EXTEND-D06, BLRISK-SPLIT-P02.
    function test_givenRiskQueueInactivePaused_whenExtended() public {
        test_givenRiskQueueLifecycle_whenExtended(false, false);
    }
}
