// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansCompositesTest} from "./fixtures/BurnerLoansCompositesTest.sol";
import {CompositesAccount} from "./fixtures/CompositesAccount.sol";

contract BurnerLoansCompositesExecuteWithGrantTest is BurnerLoansCompositesTest {
    // Scenarios: BLREX-A15.
    function test_whenSignedDebtConstraintExceeded_reverts() public {
        _fundSigner(2100e6);
        IOperatorAuth.Grant memory grant = _operatorGrant(
            _borrower,
            address(_executor),
            type(uint48).max
        );
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        permissions.maxDebt = 100e9 - 1;
        grant.permissions = abi.encode(permissions);
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _deposit(2000e6);
        operations[1] = _borrow(100e9, 100e6, _borrower);
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ResultOutsideGrant.selector);
        vm.prank(_borrower);
        _executor.executeWithGrant(
            _funding(address(_asset), 2100e6),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed
        );
        assertEq(
            _position().depositedCollateral,
            0,
            "Signed debt ceiling restores preceding deposit"
        );
        assertEq(_core.totalActiveDebtOhm(), 0, "Signed debt ceiling prevents principal creation");
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            0,
            "Debt ceiling failure restores grant acceptance"
        );
    }

    // Scenarios: BLREX-A16.
    function test_whenSignedConstraintsAreTampered_reverts() public {
        _fundSigner(10e6);
        IOperatorAuth.Grant memory grant = _operatorGrant(
            _borrower,
            address(_executor),
            type(uint48).max
        );
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        permissions.maxCollateral = 10e6;
        grant.permissions = abi.encode(permissions);
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        permissions.maxCollateral = type(uint128).max;
        signed.grant.permissions = abi.encode(permissions);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        vm.prank(_borrower);
        _executor.executeWithGrant(
            _funding(address(_asset), 10e6),
            _single(_deposit(10e6)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed
        );
        assertEq(_asset.balanceOf(_borrower), 10e6, "Tampered constraints collect no wallet funds");
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            0,
            "Tampered constraints consume no accepted epoch"
        );
    }

    // Scenarios: BLREX-A17.
    function test_whenGrantDeadlineEqualsCurrentTime() public {
        _fundSigner(1);
        vm.warp(100);
        IOperatorAuth.Grant memory grant = _operatorGrant(_borrower, address(_executor), 100);
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        vm.prank(_borrower);
        _executor.executeWithGrant(
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed
        );
        assertEq(
            _position().depositedCollateral,
            1,
            "Auth's inclusive grant deadline remains usable"
        );
    }

    // Scenarios: BLREX-I06.
    function test_whenSignedGrantHasEmptyOperations_reverts() public {
        _fundSigner(1);
        IOperatorAuth.Grant memory grant = _operatorGrant(
            _borrower,
            address(_executor),
            type(uint48).max
        );
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        vm.expectCall(
            address(_auth),
            abi.encodeWithSelector(IOperatorAuth.acceptGrant.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_asset),
            abi.encodeWithSelector(IERC20.transferFrom.selector),
            uint64(0)
        );
        vm.expectRevert(IExecutor.BurnerLoansComposites_EmptyOperations.selector);
        vm.prank(_borrower);
        _executor.executeWithGrant(
            _funding(address(_asset), 1),
            new IExecutor.Operation[](0),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed
        );
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            0,
            "Empty operations do not accept a signed grant"
        );
    }

    // Scenarios: BLREX-A01, BLREX-O01.
    function test_whenEoaAcceptsSignedTemporaryGrant() public {
        _borrower = vm.addr(_SIGNER_KEY);
        _asset.mint(_borrower, 15e6);
        vm.prank(_borrower);
        _asset.approve(address(_executor), 15e6);
        IOperatorAuth.Grant memory grant = _operatorGrant(
            _borrower,
            address(_executor),
            type(uint48).max
        );
        grant.multiple = false;
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        assertEq(_borrower.code.length, 0, "Submitting account is an undelegated EOA");
        IExecutor.Output[] memory outputs = new IExecutor.Output[](1);
        outputs[0] = IExecutor.Output(address(_asset), 5e6);
        vm.prank(_borrower);
        _executor.executeWithGrant(
            _funding(address(_asset), 15e6),
            _single(_deposit(10e6)),
            outputs,
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed
        );
        assertEq(
            _position().depositedCollateral,
            10e6,
            "Signed EOA execution credits its position"
        );
        assertEq(_asset.balanceOf(_borrower), 5e6, "Signed EOA receives its required unused input");
        assertEq(_auth.pairEpochs(_borrower, address(_executor)), 1, "Signature accepted once");
        assertEq(_borrower.code.length, 0, "Execution does not deploy or delegate the EOA");
        assertEq(
            _auth.getGrant(_borrower, address(_executor)).actions,
            0,
            "Temporary EOA authority expires after the execution transaction"
        );
    }

    // Scenarios: BLREX-A02.
    function test_givenVictimGrant_whenUnrelatedCallerUsesSignature_reverts(
        address caller_
    ) public {
        _borrower = vm.addr(_SIGNER_KEY);
        vm.assume(caller_ != _borrower);
        IOperatorAuth.Grant memory grant = _operatorGrant(
            _borrower,
            address(_executor),
            type(uint48).max
        );
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        vm.expectRevert(IExecutor.BurnerLoansComposites_InvalidGrant.selector);
        vm.prank(caller_);
        _executor.executeWithGrant(
            new IExecutor.Funding[](0),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed
        );
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            0,
            "Leaked signature does not consume victim epoch"
        );
        assertEq(_position().depositedCollateral, 0, "Victim position unchanged");
    }

    // Scenarios: BLREX-T03.
    function test_givenSignedGrant_whenLaterOperationFails_reverts() public {
        _borrower = vm.addr(_SIGNER_KEY);
        _asset.mint(_borrower, 10e6);
        vm.prank(_borrower);
        _asset.approve(address(_executor), 10e6);
        IOperatorAuth.Grant memory grant = _operatorGrant(
            _borrower,
            address(_executor),
            type(uint48).max
        );
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _deposit(10e6);
        operations[1] = _deposit(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientFunds.selector,
                address(_asset),
                1,
                0
            )
        );
        vm.prank(_borrower);
        _executor.executeWithGrant(
            _funding(address(_asset), 10e6),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed
        );
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            0,
            "Grant acceptance rolled back"
        );
        assertEq(_asset.balanceOf(_borrower), 10e6, "Wallet funding rolled back");
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            0,
            "Earlier custody transfer rolled back"
        );
        assertEq(_position().depositedCollateral, 0, "Earlier position mutation rolled back");
        assertEq(
            _asset.allowance(address(_executor), address(_core)),
            0,
            "Earlier approval rolled back"
        );
    }

    function _fundSigner(uint256 amount_) internal {
        _borrower = vm.addr(_SIGNER_KEY);
        _asset.mint(_borrower, amount_);
        vm.prank(_borrower);
        _asset.approve(address(_executor), amount_);
    }

    // Scenarios: BLREX-A12.
    function test_whenSignedGrantContainsCollateralConstraint() public {
        _fundSigner(10e6);
        IOperatorAuth.Grant memory grant = _operatorGrant(
            _borrower,
            address(_executor),
            type(uint48).max
        );
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        permissions.maxCollateral = 10e6;
        grant.permissions = abi.encode(permissions);
        grant.actions = 1;
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        vm.prank(_borrower);
        _executor.executeWithGrant(
            _funding(address(_asset), 10e6),
            _single(_deposit(10e6)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed
        );
        assertEq(
            _auth.getGrant(_borrower, address(_executor)).permissions,
            grant.permissions,
            "Complete user-signed constraints retained byte for byte"
        );
        assertEq(_position().depositedCollateral, 10e6, "Exact signed collateral ceiling succeeds");
        assertEq(
            _auth.getGrant(_borrower, address(_executor)).actions,
            1,
            "Signed action mask not widened"
        );
    }

    // Scenarios: BLREX-A13.
    function test_whenSignedCollateralConstraintExceeded_reverts() public {
        _fundSigner(10e6);
        IOperatorAuth.Grant memory grant = _operatorGrant(
            _borrower,
            address(_executor),
            type(uint48).max
        );
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        permissions.maxCollateral = 10e6 - 1;
        grant.permissions = abi.encode(permissions);
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ResultOutsideGrant.selector);
        vm.prank(_borrower);
        _executor.executeWithGrant(
            _funding(address(_asset), 10e6),
            _single(_deposit(10e6)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed
        );
        assertEq(
            _position().depositedCollateral,
            0,
            "Signed collateral ceiling enforced by real Core"
        );
        assertEq(_asset.balanceOf(_borrower), 10e6, "Constraint failure restores wallet funds");
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            0,
            "Constraint failure restores grant acceptance"
        );
    }

    // Scenarios: BLREX-A14.
    function test_whenSignedRecipientConstraintDiffers_reverts() public {
        _fundSigner(2100e6);
        IOperatorAuth.Grant memory grant = _operatorGrant(
            _borrower,
            address(_executor),
            type(uint48).max
        );
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        permissions.borrowRecipient = _recipient;
        grant.permissions = abi.encode(permissions);
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _deposit(2000e6);
        operations[1] = _borrow(100e9, 100e6, _borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansAuth.BurnerLoansAuth_RecipientMismatch.selector,
                _recipient,
                _borrower
            )
        );
        vm.prank(_borrower);
        _executor.executeWithGrant(
            _funding(address(_asset), 2100e6),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed
        );
        assertEq(
            _position().depositedCollateral,
            0,
            "Recipient mismatch restores preceding deposit"
        );
        assertEq(_core.totalActiveDebtOhm(), 0, "Recipient constraint prevents principal creation");
        assertEq(_asset.balanceOf(_borrower), 2100e6, "Recipient mismatch restores wallet funding");
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            0,
            "Recipient mismatch restores accepted epoch"
        );
    }

    // Scenarios: BLREX-A03.
    function test_whenGrantNamesWrongOperator_reverts() public {
        _borrower = vm.addr(_SIGNER_KEY);
        IOperatorAuth.Grant memory grant = _operatorGrant(_borrower, _recipient, type(uint48).max);
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidIdentity.selector);
        vm.prank(_borrower);
        _executor.executeWithGrant(
            new IExecutor.Funding[](0),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed
        );
        assertEq(_auth.pairEpochs(_borrower, _recipient), 0, "Wrong operator consumes no grant");
    }

    // Scenarios: BLREX-A06.
    function test_whenContractAccountAcceptsErc1271Grant() public {
        CompositesAccount account = new CompositesAccount(address(this), vm.addr(_SIGNER_KEY));
        _borrower = address(account);
        _asset.mint(_borrower, 10e6);
        IOperatorAuth.Grant memory grant = _operatorGrant(
            _borrower,
            address(_executor),
            type(uint48).max
        );
        grant.multiple = false;
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        account.run(
            _executor,
            _funding(address(_asset), 10e6),
            _single(_deposit(10e6)),
            new IExecutor.Output[](0),
            signed
        );
        assertEq(_position().depositedCollateral, 10e6, "ERC1271 account is borrower");
        assertEq(_auth.pairEpochs(_borrower, address(_executor)), 1, "ERC1271 grant consumed once");
    }

    // Scenarios: BLREX-A07.
    function test_whenSignedGrantExpired_reverts() public {
        _borrower = vm.addr(_SIGNER_KEY);
        vm.warp(100);
        IOperatorAuth.Grant memory grant = _operatorGrant(_borrower, address(_executor), 99);
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_ExpiredGrant.selector, uint48(99))
        );
        vm.prank(_borrower);
        _executor.executeWithGrant(
            new IExecutor.Funding[](0),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed
        );
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            0,
            "Expired grant acceptance rolled back"
        );
    }

    // Scenarios: BLREX-A08.
    function test_whenSignedGrantEpochIsStale_reverts() public {
        _borrower = vm.addr(_SIGNER_KEY);
        IOperatorAuth.Grant memory grant = _operatorGrant(
            _borrower,
            address(_executor),
            type(uint48).max
        );
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        vm.prank(_borrower);
        _auth.cancelGrant(address(_executor));
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidEpoch.selector);
        vm.prank(_borrower);
        _executor.executeWithGrant(
            new IExecutor.Funding[](0),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed
        );
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            1,
            "Stale signature does not consume another epoch"
        );
    }

    // Scenarios: BLREX-A18.
    function test_givenCallerHasOwnGrant_whenSubmittingAnotherAccountsSignature_reverts() public {
        _fundSigner(1);
        address caller = _recipient;
        _approveOperator(caller, address(_executor), type(uint48).max);
        _asset.mint(caller, 1);
        vm.prank(caller);
        _asset.approve(address(_executor), 1);
        IOperatorAuth.Grant memory grant = _operatorGrant(
            _borrower,
            address(_executor),
            type(uint48).max
        );
        IExecutor.SignedGrant memory signed = _signedGrant(grant);

        // The caller can execute its own deposit, but must not install the victim's leaked grant.
        vm.expectRevert(IExecutor.BurnerLoansComposites_InvalidGrant.selector);
        vm.prank(caller);
        _executor.executeWithGrant(
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed
        );
        assertEq(_asset.balanceOf(caller), 1, "Caller funding is not collected");
        assertEq(
            _lens.getPosition(address(_asset), caller).depositedCollateral,
            0,
            "Caller position does not change"
        );
        assertEq(_position().depositedCollateral, 0, "Victim position does not change");
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            0,
            "A caller with its own authority cannot consume the victim's signature"
        );
        assertEq(
            _auth.pairEpochs(caller, address(_executor)),
            1,
            "Caller's original grant remains installed"
        );
    }

    // Scenarios: BLREX-A19.
    function test_whenSignatureDataIsNonempty_reverts() public {
        _fundSigner(1);
        IOperatorAuth.Grant memory grant = _operatorGrant(
            _borrower,
            address(_executor),
            type(uint48).max
        );
        IExecutor.SignedGrant memory signed = _signedGrant(grant);
        signed.signatureData = hex"01";
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnsupportedSignatureData.selector);
        vm.prank(_borrower);
        _executor.executeWithGrant(
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed
        );
        assertEq(_asset.balanceOf(_borrower), 1, "Unsupported data collects no wallet funds");
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            0,
            "Unsupported data installs no grant"
        );
    }
}
