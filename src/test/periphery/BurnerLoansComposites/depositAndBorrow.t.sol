// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test actions assert their effects directly; return values are intentionally unused.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IERC20Errors} from "@openzeppelin-5.7.0/interfaces/draft-IERC6093.sol";
import {IBurnerLoansComposites} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {BurnerLoansCompositesTest} from "src/test/periphery/BurnerLoansComposites/BurnerLoansCompositesTest.sol";

contract BurnerLoansCompositesDepositAndBorrowTest is BurnerLoansCompositesTest {
    // depositAndBorrow
    // given the caller pre-authorized the composite and funded collateral plus maximum fee
    //  when depositing and borrowing
    //   then one transaction creates the position, pays the fee, and leaves no residual tokens
    function test_givenPreAuthorization_depositsAndBorrows() public {
        _authorize(_borrower);
        _fundAndApproveCollateral(address(_asset), _borrower, _COLLATERAL + _MAX_FEE);
        uint256 treasuryBefore = _asset.balanceOf(address(_treasury));

        vm.prank(_borrower);
        IBurnerLoansComposites.DepositAndBorrowResult memory result = composites.depositAndBorrow(
            _emptyAuthorization(),
            _emptySignature(),
            _depositParams(address(_asset), _borrower)
        );

        IBurnerLoansCore.Position memory position = _lens.getPosition(address(_asset), _borrower);
        assertEq(result.depositedCollateral, _COLLATERAL, "deposited collateral");
        assertEq(result.totalCollateral, _COLLATERAL, "total collateral");
        assertEq(result.resultingDebtOhm, _BORROW, "resulting debt");
        assertEq(result.maturity, position.maturity, "maturity");
        // collateral USD = 2_000e6 * 1e18 / 1e6 = 2_000e18 (18 decimals)
        // debt USD = 100e9 * 10e18 / 1e9 = 1_000e18 (18 decimals)
        // market requirement = ceil(1_000e18 * 10_000 / 8_500)
        //                    = 1_176_470_588_235_294_117_648 (18 decimals)
        // backing requirement = ceil(100e18 * 12_500 / 10_000) = 125e18
        // health = floor(2_000e18 * 1e18 / 1_176_470_588_235_294_117_648)
        //        = 1_699_999_999_999_999_999 (18 decimals)
        assertEq(result.healthFactor, 1_699_999_999_999_999_999, "health factor");
        assertEq(position.debtOhm, _BORROW, "position debt");
        assertEq(_ohm.balanceOf(_borrower), _BORROW, "borrowed OHM");
        assertEq(_asset.balanceOf(address(_treasury)), treasuryBefore + result.fee, "treasury fee");
        assertEq(_asset.balanceOf(_borrower), _MAX_FEE - result.fee, "fee refund");
        _assertCompositeBalances(address(_asset));
    }

    // depositAndBorrow
    // given the caller specifies a third-party OHM recipient
    //  when depositing and borrowing
    //   then borrowed OHM is routed only to that recipient
    function test_givenThirdPartyRecipient_routesBorrowedOhm() public {
        _authorize(_borrower);
        _fundAndApproveCollateral(address(_asset), _borrower, _COLLATERAL + _MAX_FEE);

        vm.prank(_borrower);
        composites.depositAndBorrow(
            _emptyAuthorization(),
            _emptySignature(),
            _depositParams(address(_asset), recipient)
        );

        assertEq(_ohm.balanceOf(recipient), _BORROW, "recipient OHM");
        assertEq(_ohm.balanceOf(_borrower), 0, "caller OHM");
        _assertCompositeBalances(address(_asset));
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
        _fundAndApproveCollateral(address(_asset), borrower, _COLLATERAL + _MAX_FEE);

        vm.prank(borrower);
        composites.depositAndBorrow(
            authorization,
            signature,
            _depositParams(address(_asset), borrower)
        );

        assertEq(
            _core.authorizationDeadlines(borrower, address(composites)),
            authorization.authorizationDeadline,
            "authorization deadline"
        );
        assertEq(_core.authorizationNonces(borrower), 1, "authorization nonce");
        assertEq(_ohm.balanceOf(borrower), _BORROW, "borrowed OHM");
        _assertCompositeBalances(address(_asset));
    }

    // depositAndBorrow
    // given the composite has not been authorized for the caller
    //  when depositing and borrowing without a signature
    //   then Burner Loans rejects the operation and all input remains with the caller
    function test_givenNoAuthorization_revertsAndRollsBack() public {
        uint256 input = _COLLATERAL + _MAX_FEE;
        _fundAndApproveCollateral(address(_asset), _borrower, input);

        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        vm.prank(_borrower);
        composites.depositAndBorrow(
            _emptyAuthorization(),
            _emptySignature(),
            _depositParams(address(_asset), _borrower)
        );

        assertEq(_asset.balanceOf(_borrower), input, "caller collateral");
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            0,
            "position collateral"
        );
        _assertCompositeBalances(address(_asset));
    }

    // depositAndBorrow
    // given the caller has not approved the composite to pull collateral and maximum fee
    //  when depositing and borrowing
    //   then the token transfer reverts before any position mutation
    function test_givenMissingTokenApproval_reverts() public {
        _authorize(_borrower);
        _asset.mint(_borrower, _COLLATERAL + _MAX_FEE);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(composites),
                0,
                _COLLATERAL + _MAX_FEE
            )
        );
        vm.prank(_borrower);
        composites.depositAndBorrow(
            _emptyAuthorization(),
            _emptySignature(),
            _depositParams(address(_asset), _borrower)
        );
    }

    // depositAndBorrow
    // given the actual fee exceeds the caller's maximum fee
    //  when depositing and borrowing
    //   then the deposit, transfers, and authorization state all roll back
    function test_givenFeeAboveMax_revertsAndRollsBack() public {
        _authorize(_borrower);
        _fundAndApproveCollateral(address(_asset), _borrower, _COLLATERAL);
        IBurnerLoansComposites.DepositAndBorrowParams memory params = _depositParams(
            address(_asset),
            _borrower
        );
        params.maxFee = 0;

        vm.expectPartialRevert(IBurnerLoansDebt.BurnerLoans_FeeExceedsMax.selector);
        vm.prank(_borrower);
        composites.depositAndBorrow(_emptyAuthorization(), _emptySignature(), params);

        assertEq(_asset.balanceOf(_borrower), _COLLATERAL, "caller collateral");
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            0,
            "position collateral"
        );
        _assertCompositeBalances(address(_asset));
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
                _borrower
            )
        );
        vm.prank(_borrower);
        composites.depositAndBorrow(
            authorization,
            signature,
            _depositParams(address(_asset), _borrower)
        );
    }

    // depositAndBorrow
    // given a collateral token callback attempts to reenter the composite
    //  when the outer deposit-and-borrow pulls inputs
    //   then reentrancy is rejected and the outer operation leaves no residual funds
    function test_givenReentrantCollateralToken_cannotEnterTwice() public {
        ReentrantFeeToken token = new ReentrantFeeToken();
        _configurePrice(address(token), 1e18);
        _configureDepositManagerAsset(address(token));
        vm.prank(address(this));
        _config.addAsset(
            address(token),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig(),
            false
        );
        _authorize(_borrower);
        uint128 collateral = 2_000e18;
        uint256 maxFee = 10e18;
        token.mint(_borrower, collateral + maxFee);
        vm.prank(_borrower);
        token.approve(address(composites), collateral + maxFee);
        IBurnerLoansComposites.DepositAndBorrowParams memory params = IBurnerLoansComposites
            .DepositAndBorrowParams({
                asset: address(token),
                collateralAmount: collateral,
                ohmAmount: _BORROW,
                recipient: _borrower,
                maxFee: maxFee
            });
        token.setCallback(
            address(composites),
            abi.encodeCall(
                composites.depositAndBorrow,
                (_emptyAuthorization(), _emptySignature(), params)
            )
        );

        vm.prank(_borrower);
        composites.depositAndBorrow(_emptyAuthorization(), _emptySignature(), params);

        assertFalse(token.callbackSucceeded(), "callback succeeded");
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "callback revert"
        );
        assertEq(_lens.getPosition(address(token), _borrower).debtOhm, _BORROW, "position debt");
        _assertCompositeBalances(address(token));
    }
}

// forge-lint: disable-end(unused-return)
