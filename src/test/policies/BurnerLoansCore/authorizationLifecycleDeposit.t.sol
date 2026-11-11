// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {BurnerLoansAuthorizationIntegrationTest} from "src/test/policies/BurnerLoansCore/authorizationLifecycleTest.sol";
import {AuthSelectionCandidate} from "src/test/policies/BurnerLoansCore/fixtures/AuthSelectionCandidate.sol";
import {CoreCallbackToken} from "src/test/policies/BurnerLoansCore/fixtures/CoreCallbackToken.sol";

contract BurnerLoansCoreDepositAuthorizationTest is BurnerLoansAuthorizationIntegrationTest {
    // Scenarios: BLCORE-AUTH-C02.
    function test_givenCapturedOwner_whenAuthRotatesAndReturns_reverts() public {
        IBurnerLoansCore.AuthorizationContext memory original = _ownerAuthContext();
        (address first, ) = _core.authConfig();
        _core.setAuth(address(new AuthSelectionCandidate(address(_core))));
        _core.setAuth(first);
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_InvalidAuthorizationContext.selector);
        vm.prank(address(_collateral));
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            original
        );
        assertEq(_ledger(), before, "Returning Auth cannot adopt an owner's stale preparation");
    }

    // Scenarios: BLCORE-AUTH-P02.
    function test_givenReusableGrant_whenAuthRotatesAndReturns_reverts() public {
        _acceptBounded(_boundedGrant(1, 100, 0, 0, 0));
        uint256 pairEpoch = _auth.pairEpochs(_borrower, _recipient);
        (address first, ) = _core.authConfig();
        _core.setAuth(address(new AuthSelectionCandidate(address(_core))));
        _core.setAuth(first);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        _auth.captureAuthorization(_borrower, _recipient, 1);
        assertEq(
            _auth.pairEpochs(_borrower, _recipient),
            pairEpoch,
            "Rotation never resets local pair counters"
        );
        _acceptBounded(_boundedGrant(1, 100, 0, 0, 0));
        assertTrue(
            _auth.captureAuthorization(_borrower, _recipient, 1) != bytes32(0),
            "Fresh approval uses the new Core generation"
        );
        assertEq(
            _auth.pairEpochs(_borrower, _recipient),
            pairEpoch + 1,
            "Fresh approval advances the same counter"
        );
    }

    // Scenarios: BLCORE-AUTH-C01.
    function test_givenSettlementCallback_whenAuthRotationCaught() public {
        CoreCallbackToken token = _callbackAsset();
        _grantAdmin(address(token));
        (address first, ) = _core.authConfig();
        uint256 epoch = _currentAuthEpoch();
        token.setCallbackFrom(
            address(_core),
            address(_core),
            abi.encodeCall(
                IBurnerLoansCore.setAuth,
                (address(new AuthSelectionCandidate(address(_core))))
            )
        );
        token.setCallbackPhases(false, true);
        token.setBubbleCallbackFailure(false);
        vm.prank(address(_collateral));
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(token),
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
            "Rotation shares settlement guard"
        );
        (address selected, ) = _core.authConfig();
        assertEq(selected, first, "Caught rotation preserves verifier");
        assertEq(_currentAuthEpoch(), epoch, "Caught rotation preserves generation");
        assertEq(_position().depositedCollateral, 1, "Outer settlement completes once");
    }

    // Scenarios: BLCORE-AUTH-C01.
    function test_givenSettlementCallback_whenAuthRotationPropagated_reverts() public {
        CoreCallbackToken token = _callbackAsset();
        _grantAdmin(address(token));
        token.setCallbackFrom(
            address(_core),
            address(_core),
            abi.encodeCall(
                IBurnerLoansCore.setAuth,
                (address(new AuthSelectionCandidate(address(_core))))
            )
        );
        token.setCallbackPhases(false, true);
        token.setBubbleCallbackFailure(true);
        bytes32 before = _ledger();
        uint256 epoch = _currentAuthEpoch();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(address(_collateral));
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(token),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
        assertEq(_ledger(), before, "Propagated rotation failure restores custody and accounting");
        assertEq(_currentAuthEpoch(), epoch, "Propagated rotation consumes no generation");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-N90.
    function test_givenDelegatedGrant_whenResultExceedsCollateralBound_reverts() public {
        _fundOperator(100);
        _acceptBounded(_boundedGrant(1, 99, 0, 0, 0));
        IBurnerLoansCore.AuthorizationContext memory original = _delegatedContext(1);
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ResultOutsideGrant.selector);
        vm.prank(address(_collateral));
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 100,
                payer: _recipient,
                borrower: _borrower
            }),
            _recipient,
            original
        );
        assertEq(
            _ledger(),
            before,
            "Failed canonical bound restores transfers, receipts and FLOAN"
        );
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-P90.
    function test_givenDelegatedGrant_whenResultEqualsCollateralBound() public {
        _fundOperator(100);
        _acceptBounded(_boundedGrant(1, 100, 0, 0, 0));
        IBurnerLoansCore.AuthorizationContext memory original = _delegatedContext(1);
        vm.prank(address(_collateral));
        (uint128 credit, uint128 collateral) = _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 100,
                payer: _recipient,
                borrower: _borrower
            }),
            _recipient,
            original
        );
        assertEq(credit, 100, "Actual direct custody credit is authoritative");
        assertEq(collateral, 100, "Exact resulting-position cap is inclusive");
    }

    // Scenarios: BLCORE-SETTLE-DEPOSIT-C90.
    function test_givenCapturedGrant_whenCancelledBeforeSettlement_reverts() public {
        _fundOperator(100);
        _acceptBounded(_boundedGrant(1, 100, 0, 0, 0));
        IBurnerLoansCore.AuthorizationContext memory original = _delegatedContext(1);
        vm.prank(_borrower);
        _auth.cancelGrant(_recipient);
        bytes32 before = _ledger();
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        vm.prank(address(_collateral));
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 100,
                payer: _recipient,
                borrower: _borrower
            }),
            _recipient,
            original
        );
        assertEq(_ledger(), before, "Stale authority is rejected before custody changes");
    }
}
// forge-lint: disable-end(unused-return)
