// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCollateralCallbackReceipts} from "./fixtures/BurnerLoansCollateralCallbackReceipts.sol";
import {BurnerLoansCollateralTokenCallbackTest} from "./fixtures/BurnerLoansCollateralTokenCallbackTest.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralDepositCollateralCallbacksTest is
    BurnerLoansCollateralTokenCallbackTest
{
    // Scenarios: BLCOL-DEPOSIT-C05.
    function test_givenPayerPullCallback_whenActionReentryCaught() public {
        _prepareDirectToken();
        _quoteDeposit(_borrower);
        _armNestedDeposit(address(_core));
        _assertDepositCaught(_borrower);
    }

    // Scenarios: BLCOL-DEPOSIT-C05.
    function test_givenPayerPullCallback_whenCoreReentryCaught() public {
        _prepareDirectToken();
        _quoteDeposit(_borrower);
        _armCoreConfiguration(address(_core));
        _assertDepositCaught(_borrower);
    }

    // Scenarios: BLCOL-DEPOSIT-C06.
    function test_givenPayerPullCallback_whenActionReentryPropagated() public {
        _prepareDirectToken();
        _quoteDeposit(_borrower);
        _armNestedDeposit(address(_core));
        _token.setBubbleCallbackFailure(true);
        _assertDepositRejected(_borrower);
    }

    // Scenarios: BLCOL-DEPOSIT-C06.
    function test_givenPayerPullCallback_whenCoreReentryPropagated() public {
        _prepareDirectToken();
        _quoteDeposit(_borrower);
        _armCoreConfiguration(address(_core));
        _token.setBubbleCallbackFailure(true);
        _assertDepositRejected(_borrower);
    }

    // Scenarios: BLCOL-DEPOSIT-C05.
    function test_givenManagerPullCallback_whenActionReentryCaught() public {
        _prepareDirectToken();
        _quoteDeposit(_borrower);
        _armNestedDeposit(address(_depositManager));
        _assertDepositCaught(_borrower);
    }

    // Scenarios: BLCOL-DEPOSIT-C05.
    function test_givenManagerPullCallback_whenCoreReentryCaught() public {
        _prepareDirectToken();
        _quoteDeposit(_borrower);
        _armCoreConfiguration(address(_depositManager));
        _assertDepositCaught(_borrower);
    }

    // Scenarios: BLCOL-DEPOSIT-C06.
    function test_givenManagerPullCallback_whenActionReentryPropagated() public {
        _prepareDirectToken();
        _quoteDeposit(_borrower);
        _armNestedDeposit(address(_depositManager));
        _token.setBubbleCallbackFailure(true);
        _assertDepositRejected(_borrower);
    }

    // Scenarios: BLCOL-DEPOSIT-C06.
    function test_givenManagerPullCallback_whenCoreReentryPropagated() public {
        _prepareDirectToken();
        _quoteDeposit(_borrower);
        _armCoreConfiguration(address(_depositManager));
        _token.setBubbleCallbackFailure(true);
        _assertDepositRejected(_borrower);
    }

    // Scenarios: BLCOL-DEPOSIT-C05.
    function test_givenVaultDepositCallback_whenActionReentryCaught() public {
        _prepareVaultToken();
        _quoteDeposit(_borrower);
        _armNestedDeposit(address(_vault));
        _assertDepositCaught(_borrower);
    }

    // Scenarios: BLCOL-DEPOSIT-C05.
    function test_givenVaultDepositCallback_whenCoreReentryCaught() public {
        _prepareVaultToken();
        _quoteDeposit(_borrower);
        _armCoreConfiguration(address(_vault));
        _assertDepositCaught(_borrower);
    }

    // Scenarios: BLCOL-DEPOSIT-C06.
    function test_givenVaultDepositCallback_whenActionReentryPropagated() public {
        _prepareVaultToken();
        _quoteDeposit(_borrower);
        _armNestedDeposit(address(_vault));
        _token.setBubbleCallbackFailure(true);
        _assertDepositRejected(_borrower);
    }

    // Scenarios: BLCOL-DEPOSIT-C06.
    function test_givenVaultDepositCallback_whenCoreReentryPropagated() public {
        _prepareVaultToken();
        _quoteDeposit(_borrower);
        _armCoreConfiguration(address(_vault));
        _token.setBubbleCallbackFailure(true);
        _assertDepositRejected(_borrower);
    }

    // Scenarios: BLCOL-DEPOSIT-C05.
    function test_givenOperatorFundedDeposit_whenCallbackCaught() public {
        _prepareDirectToken();
        _quoteDeposit(_recipient);
        _armNestedDeposit(address(_depositManager));
        _assertDepositCaught(_recipient);
    }

    // Scenarios: BLCOL-DEPOSIT-C06.
    function test_givenOperatorFundedDeposit_whenCallbackPropagated() public {
        _prepareDirectToken();
        _quoteDeposit(_recipient);
        _armNestedDeposit(address(_depositManager));
        _token.setBubbleCallbackFailure(true);
        _assertDepositRejected(_recipient);
    }

    // Scenarios: BLCOL-DEPOSIT-C05.
    function test_givenReceiptApprovalCallback_whenActionReentryCaught() public {
        _prepareDirectToken();
        _quoteDeposit(_borrower);
        BurnerLoansCollateralCallbackReceipts receipts = _callbackReceipts();
        _token.mint(address(receipts), 1);
        vm.prank(address(receipts));
        _token.approve(address(_core), 1);
        vm.prank(_borrower);
        _core.setAuthorization(address(receipts), type(uint48).max);
        receipts.arm(
            address(_collateral),
            abi.encodeCall(_collateral.depositCollateral, (address(_token), uint128(1), _borrower)),
            false
        );
        _assertDepositCaughtWithoutTokenHook(_borrower);
        assertEq(
            receipts.rejection(),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
            "Receipt approval callback reaches guarded Core"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-C06.
    function test_givenReceiptApprovalCallback_whenActionReentryPropagated() public {
        _prepareDirectToken();
        _quoteDeposit(_borrower);
        BurnerLoansCollateralCallbackReceipts receipts = _callbackReceipts();
        _token.mint(address(receipts), 1);
        vm.prank(address(receipts));
        _token.approve(address(_core), 1);
        vm.prank(_borrower);
        _core.setAuthorization(address(receipts), type(uint48).max);
        receipts.arm(
            address(_collateral),
            abi.encodeCall(_collateral.depositCollateral, (address(_token), uint128(1), _borrower)),
            true
        );
        _assertReceiptDepositRejected();
    }

    // Scenarios: BLCOL-DEPOSIT-C05.
    function test_givenReceiptApprovalCallback_whenCoreReentryCaught() public {
        _prepareDirectToken();
        _quoteDeposit(_borrower);
        BurnerLoansCollateralCallbackReceipts receipts = _callbackReceipts();
        _rolesAdmin.grantRole(ADMIN_ROLE, address(receipts));
        receipts.arm(address(_core), abi.encodeCall(_core.setGracePeriod, (uint32(1))), false);
        _assertDepositCaughtWithoutTokenHook(_borrower);
        assertEq(
            receipts.rejection(),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
            "Receipt approval callback reaches guarded Core"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-C06.
    function test_givenReceiptApprovalCallback_whenCoreReentryPropagated() public {
        _prepareDirectToken();
        _quoteDeposit(_borrower);
        BurnerLoansCollateralCallbackReceipts receipts = _callbackReceipts();
        _rolesAdmin.grantRole(ADMIN_ROLE, address(receipts));
        receipts.arm(address(_core), abi.encodeCall(_core.setGracePeriod, (uint32(1))), true);
        _assertReceiptDepositRejected();
    }

    function _assertReceiptDepositRejected() internal {
        bytes32 beforeState = _accountingDigest(address(_token));
        vm.expectRevert(BurnerLoansCollateralCallbackReceipts.CallbackFailed.selector);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_token), 1e18, _borrower);
        assertEq(
            _accountingDigest(address(_token)),
            beforeState,
            "Approval failure rolls back completed deposit"
        );
    }

    function _callbackReceipts() internal returns (BurnerLoansCollateralCallbackReceipts receipts) {
        receipts = BurnerLoansCollateralCallbackReceipts(
            address(_depositManager.getReceiptTokenManager())
        );
        // Install the derived hook only after receipt creation. The inherited storage layout,
        // real balances, ownership and approval implementation are preserved.
        vm.etch(address(receipts), address(new BurnerLoansCollateralCallbackReceipts()).code);
        uint256 id = _depositManager.getReceiptTokenId(IERC20(address(_token)), 1, address(_core));
        vm.prank(address(_core));
        receipts.approve(address(_depositManager), id, 0);
    }

    function _quoteDeposit(address caller_) internal {
        bytes32 beforeState = _accountingDigest(address(_token));
        vm.prank(caller_);
        (uint256 q, uint256 c, uint256 h) = _collateral.previewDepositCollateral(
            address(_token),
            1e18,
            _borrower
        );
        assertEq(q, 1e18, "Independent 1:1 credit quote");
        assertEq(c, 11e18, "Independent total quote");
        assertEq(h, type(uint256).max, "Debt-free quote");
        assertEq(
            _accountingDigest(address(_token)),
            beforeState,
            "Quote preserves custody and positions"
        );
    }

    function _assertDepositCaughtWithoutTokenHook(address caller_) internal {
        uint256 beforeWallet = _token.balanceOf(caller_);
        vm.prank(caller_);
        (uint128 q, uint128 c, uint256 h) = _collateral.depositCollateral(
            address(_token),
            1e18,
            _borrower
        );
        assertEq(q, 1e18, "One actual credit");
        assertEq(c, 11e18, "Only outer deposit applies");
        assertEq(h, type(uint256).max, "Debt remains zero");
        assertEq(_token.balanceOf(caller_), beforeWallet - 1e18, "Payer debited once");
        assertEq(
            _lens.getPosition(address(_token), _OTHER_BORROWER).depositedCollateral,
            17,
            "Unrelated borrower preserved"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_token)), address(_core)),
            11e18 + 17,
            "Aggregate liability includes exactly one top-up"
        );
        assertEq(_core.gracePeriod(), 7 days, "Nested configuration makes no mutation");
    }

    function _assertDepositCaught(address caller_) internal {
        _assertDepositCaughtWithoutTokenHook(caller_);
        _assertGuardCaught();
    }

    function _assertDepositRejected(address caller_) internal {
        bytes32 beforeState = _accountingDigest(address(_token));
        vm.expectRevert(ReentrantFeeToken.CallbackFailed.selector);
        vm.prank(caller_);
        _collateral.depositCollateral(address(_token), 1e18, _borrower);
        assertEq(
            _accountingDigest(address(_token)),
            beforeState,
            "Mandatory callback failure restores all accounting"
        );
        assertTrue(_token.callbackEnabled(), "Callback state is also rolled back");
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
