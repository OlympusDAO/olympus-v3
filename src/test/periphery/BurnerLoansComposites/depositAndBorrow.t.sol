// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";
import {stdError} from "forge-std/StdError.sol";

import {IBurnerLoansComposites} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";
import {ReentrantFeeToken} from "src/test/policies/BurnerLoans/fixtures/ReentrantFeeToken.sol";
import {BurnerLoansCompositesTest} from "src/test/periphery/BurnerLoansComposites/BurnerLoansCompositesTest.sol";

contract BurnerLoansCompositesDepositAndBorrowTest is BurnerLoansCompositesTest {
    // depositAndBorrow
    // given the caller pre-authorized the composite and funded collateral plus maximum fee
    //  when depositing and borrowing
    //   then one transaction creates the position, pays the fee, and leaves no residual tokens
    function test_givenPreAuthorization_depositsAndBorrows() public {
        _authorize(alice);
        _fundAndApproveCollateral(address(usds), alice, _COLLATERAL + _MAX_FEE);
        uint256 treasuryBefore = usds.balanceOf(address(trsry));

        vm.prank(alice);
        IBurnerLoansComposites.DepositAndBorrowResult memory result = composites.depositAndBorrow(
            _emptyAuthorization(),
            _emptySignature(),
            _depositParams(address(usds), alice)
        );

        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(result.depositedCollateral, _COLLATERAL, "deposited collateral");
        assertEq(result.totalCollateral, _COLLATERAL, "total collateral");
        assertEq(result.resultingDebtOhm, _BORROW, "resulting debt");
        assertEq(result.maturity, position.maturity, "maturity");
        assertEq(
            result.healthFactor,
            burnerLoans.positionHealthFactor(address(usds), _COLLATERAL, _BORROW),
            "health factor"
        );
        assertEq(position.debtOhm, _BORROW, "position debt");
        assertEq(ohm.balanceOf(alice), _BORROW, "borrowed OHM");
        assertEq(usds.balanceOf(address(trsry)), treasuryBefore + result.fee, "treasury fee");
        assertEq(usds.balanceOf(alice), _MAX_FEE - result.fee, "fee refund");
        _assertCompositeBalances(address(usds));
    }

    // depositAndBorrow
    // given the caller specifies a third-party OHM recipient
    //  when depositing and borrowing
    //   then borrowed OHM is routed only to that recipient
    function test_givenThirdPartyRecipient_routesBorrowedOhm() public {
        _authorize(alice);
        _fundAndApproveCollateral(address(usds), alice, _COLLATERAL + _MAX_FEE);

        vm.prank(alice);
        composites.depositAndBorrow(
            _emptyAuthorization(),
            _emptySignature(),
            _depositParams(address(usds), recipient)
        );

        assertEq(ohm.balanceOf(recipient), _BORROW, "recipient OHM");
        assertEq(ohm.balanceOf(alice), 0, "caller OHM");
        _assertCompositeBalances(address(usds));
    }

    // depositAndBorrow
    // given a signed authorization names the caller and this composite
    //  when depositing and borrowing without prior on-chain authorization
    //   then the signature is consumed and the composite succeeds
    function test_givenSignedAuthorization_depositsAndBorrows() public {
        (address borrower, uint256 privateKey) = makeAddrAndKey("signedBorrower");
        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(borrower, privateKey);
        _fundAndApproveCollateral(address(usds), borrower, _COLLATERAL + _MAX_FEE);

        vm.prank(borrower);
        composites.depositAndBorrow(
            authorization,
            signature,
            _depositParams(address(usds), borrower)
        );

        assertEq(
            burnerLoans.authorizationDeadlines(borrower, address(composites)),
            authorization.authorizationDeadline,
            "authorization deadline"
        );
        assertEq(burnerLoans.authorizationNonces(borrower), 1, "authorization nonce");
        assertEq(ohm.balanceOf(borrower), _BORROW, "borrowed OHM");
        _assertCompositeBalances(address(usds));
    }

    // depositAndBorrow
    // given the composite has not been authorized for the caller
    //  when depositing and borrowing without a signature
    //   then Burner Loans rejects the operation and all input remains with the caller
    function test_givenNoAuthorization_revertsAndRollsBack() public {
        uint256 input = _COLLATERAL + _MAX_FEE;
        _fundAndApproveCollateral(address(usds), alice, input);

        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        vm.prank(alice);
        composites.depositAndBorrow(
            _emptyAuthorization(),
            _emptySignature(),
            _depositParams(address(usds), alice)
        );

        assertEq(usds.balanceOf(alice), input, "caller collateral");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            0,
            "position collateral"
        );
        _assertCompositeBalances(address(usds));
    }

    // depositAndBorrow
    // given the caller has not approved the composite to pull collateral and maximum fee
    //  when depositing and borrowing
    //   then the token transfer reverts before any position mutation
    function test_givenMissingTokenApproval_reverts() public {
        _authorize(alice);
        usds.mint(alice, _COLLATERAL + _MAX_FEE);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(alice);
        composites.depositAndBorrow(
            _emptyAuthorization(),
            _emptySignature(),
            _depositParams(address(usds), alice)
        );
    }

    // depositAndBorrow
    // given the actual fee exceeds the caller's maximum fee
    //  when depositing and borrowing
    //   then the deposit, transfers, and authorization state all roll back
    function test_givenFeeAboveMax_revertsAndRollsBack() public {
        _authorize(alice);
        _fundAndApproveCollateral(address(usds), alice, _COLLATERAL);
        IBurnerLoansComposites.DepositAndBorrowParams memory params = _depositParams(
            address(usds),
            alice
        );
        params.maxFee = 0;

        vm.expectPartialRevert(IBurnerLoans.BurnerLoans_FeeExceedsMax.selector);
        vm.prank(alice);
        composites.depositAndBorrow(_emptyAuthorization(), _emptySignature(), params);

        assertEq(usds.balanceOf(alice), _COLLATERAL, "caller collateral");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            0,
            "position collateral"
        );
        _assertCompositeBalances(address(usds));
    }

    // depositAndBorrow
    // given a signature authorizes this composite for a different account than the caller
    //  when depositing and borrowing
    //   then the composite rejects the mismatched account before submitting the signature
    function test_givenAuthorizationForDifferentAccount_reverts() public {
        (address borrower, uint256 privateKey) = makeAddrAndKey("otherBorrower");
        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(borrower, privateKey);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansComposites.BurnerLoansComposites_InvalidAuthorizationAccount.selector,
                borrower,
                alice
            )
        );
        vm.prank(alice);
        composites.depositAndBorrow(authorization, signature, _depositParams(address(usds), alice));
    }

    // depositAndBorrow
    // given a collateral token callback attempts to reenter the composite
    //  when the outer deposit-and-borrow pulls inputs
    //   then reentrancy is rejected and the outer operation leaves no residual funds
    function test_givenReentrantCollateralToken_cannotEnterTwice() public {
        ReentrantFeeToken token = new ReentrantFeeToken();
        _configurePrice(address(token), 1e18);
        _configureDepositManagerAsset(address(token));
        vm.prank(admin);
        burnerLoans.addAsset(
            address(token),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
        _authorize(alice);
        uint128 collateral = 2_000e18;
        uint256 maxFee = 10e18;
        token.mint(alice, collateral + maxFee);
        vm.prank(alice);
        token.approve(address(composites), collateral + maxFee);
        IBurnerLoansComposites.DepositAndBorrowParams memory params = IBurnerLoansComposites
            .DepositAndBorrowParams({
                asset: address(token),
                collateralAmount: collateral,
                ohmAmount: _BORROW,
                recipient: alice,
                maxFee: maxFee
            });
        token.setCallback(
            address(composites),
            abi.encodeCall(
                composites.depositAndBorrow,
                (_emptyAuthorization(), _emptySignature(), params)
            )
        );

        vm.prank(alice);
        composites.depositAndBorrow(_emptyAuthorization(), _emptySignature(), params);

        assertFalse(token.callbackSucceeded(), "callback succeeded");
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "callback revert"
        );
        assertEq(burnerLoans.getPosition(address(token), alice).debtOhm, _BORROW, "position debt");
        _assertCompositeBalances(address(token));
    }
}
