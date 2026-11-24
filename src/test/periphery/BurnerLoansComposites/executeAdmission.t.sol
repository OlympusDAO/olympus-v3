// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansCompositesGrantModesTest} from "./fixtures/BurnerLoansCompositesGrantModesTest.sol";

contract BurnerLoansCompositesExecuteAdmissionTest is BurnerLoansCompositesGrantModesTest {
    struct RawOperation {
        uint8 kind;
        bytes data;
    }

    // Scenarios: BLREX-N13.
    function test_whenLendingBatchDeadlineHasPassed_reverts(
        bool inlineGrant_,
        uint48 deadline_,
        uint48 timestamp_
    ) public {
        deadline_ = uint48(bound(deadline_, 0, type(uint48).max - 1));
        timestamp_ = uint48(bound(timestamp_, uint256(deadline_) + 1, type(uint48).max));
        vm.warp(timestamp_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(true));
        vm.prank(_borrower);
        assertTrue(_asset.approve(address(_executor), 1), "Approve the lending input");
        IExecutor.Funding[] memory funding = _funding(address(_asset), 1);
        IExecutor.Operation[] memory operations = _single(_deposit(1));
        IExecutor.Output[] memory outputs = new IExecutor.Output[](0);
        IExecutor.FlashLoan memory flash = IExecutor.FlashLoan(0, 0);

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
        vm.expectRevert(
            abi.encodeWithSelector(IExecutor.BurnerLoansComposites_BatchExpired.selector, deadline_)
        );
        vm.prank(_borrower);
        if (inlineGrant_) {
            _executor.executeWithGrant(funding, operations, outputs, flash, deadline_, signed);
        } else {
            _executor.execute(funding, operations, outputs, flash, deadline_);
        }
        _assertAdmissionRollback(inlineGrant_, true);
    }

    // Scenarios: BLREX-N13.
    function test_whenBatchDeadlineExceedsUint48_reverts() public {
        _prepareGrantMode(false, _grant(true));
        vm.prank(_borrower);
        assertTrue(_asset.approve(address(_executor), 1), "Approve the lending input");
        bytes memory data = abi.encodeWithSelector(
            IExecutor.execute.selector,
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            uint256(type(uint48).max) + 1
        );

        vm.prank(_borrower);
        (bool success, bytes memory reason) = address(_executor).call(data);
        assertFalse(success, "Entry rejects a deadline outside uint48");
        assertEq(reason.length, 0, "ABI decoder returns empty revert data");
        _assertAdmissionRollback(false, true);
    }

    // Scenarios: BLREX-I01.
    function test_whenBatchIsEmpty_reverts(bool inlineGrant_, bool multiple_) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        vm.expectRevert(IExecutor.BurnerLoansComposites_EmptyOperations.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1),
            new IExecutor.Operation[](0),
            new IExecutor.Output[](0)
        );
        _assertAdmissionRollback(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-I02.
    function test_whenFundingTokenIsRepeated_reverts(
        bool inlineGrant_,
        bool multiple_,
        uint256 raw_
    ) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        IExecutor.Funding[] memory funding = new IExecutor.Funding[](2);
        funding[0] = IExecutor.Funding(address(_asset), 0);
        funding[1] = IExecutor.Funding(address(_asset), raw_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_DuplicateFunding.selector,
                address(_asset)
            )
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            funding,
            _single(_deposit(1)),
            new IExecutor.Output[](0)
        );
        _assertAdmissionRollback(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-I03.
    function test_whenWithdrawalTokenHasNoCode_reverts(
        bool inlineGrant_,
        bool multiple_,
        bool zero_
    ) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        address token = zero_ ? address(0) : _recipient;
        IExecutor.Operation memory op = IExecutor.Operation(
            IExecutor.OperationKind.Withdraw,
            abi.encode(IExecutor.Withdraw(address(_asset), 1, _borrower, token, 0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(IExecutor.BurnerLoansComposites_InvalidToken.selector, token)
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1),
            _single(op),
            new IExecutor.Output[](0)
        );
        _assertAdmissionRollback(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-I04.
    function test_whenLendingPayloadIsTruncated_reverts(
        bool inlineGrant_,
        bool multiple_,
        uint8 kind_
    ) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        IExecutor.Operation memory op = IExecutor.Operation(
            IExecutor.OperationKind(kind_ % 5),
            hex"01"
        );
        // Solidity's ABI decoder returns empty revert data on a truncated tuple.
        vm.expectRevert(bytes(""));
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1),
            _single(op),
            new IExecutor.Output[](0)
        );
        _assertAdmissionRollback(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-I04.
    function test_whenOperationKindIsOutsideEnum_reverts(uint8 kind_) public {
        RawOperation[] memory operations = new RawOperation[](1);
        operations[0] = RawOperation(
            uint8(
                bound(kind_, uint8(IExecutor.OperationKind.SwapExactOutput) + 1, type(uint8).max)
            ),
            _deposit(1).data
        );
        bytes memory data = abi.encodeWithSelector(
            IExecutor.execute.selector,
            _funding(address(_asset), 1),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        vm.prank(_borrower);
        (bool success, bytes memory reason) = address(_executor).call(data);
        assertFalse(success, "Invalid enum rejected by entry decoder");
        assertEq(reason.length, 0, "ABI decoder returns empty revert data");
        _assertAdmissionRollback(false, false);
    }

    // Scenarios: BLREX-A07.
    function test_whenNewGrantDeadlineIsOneSecondAway(
        bool inlineGrant_,
        bool multiple_,
        bool expired_
    ) public {
        vm.warp(100);
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        grant.deadline = expired_ ? 99 : 101;
        if (expired_) {
            _rejectNewGrant(
                inlineGrant_,
                grant,
                abi.encodeWithSelector(
                    IOperatorAuth.OperatorAuth_ExpiredGrant.selector,
                    grant.deadline
                )
            );
            return;
        }
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0)
        );
        _assertSettled(1, 0);
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-A07.
    function test_whenNewGrantHasExpired_reverts(
        bool inlineGrant_,
        uint48 deadline_,
        uint48 time_
    ) public {
        deadline_ = uint48(bound(deadline_, 0, type(uint48).max - 1));
        time_ = uint48(bound(time_, uint256(deadline_) + 1, type(uint48).max));
        vm.warp(time_);
        IOperatorAuth.Grant memory grant = _grant(true);
        grant.deadline = deadline_;
        _rejectNewGrant(
            inlineGrant_,
            grant,
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_ExpiredGrant.selector, deadline_)
        );
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            0,
            "Expired grant cannot advance nonce"
        );
    }

    // Scenarios: BLREX-A07.
    function test_whenNewGrantMatchesTimestampBoundary(
        bool inlineGrant_,
        bool multiple_,
        bool max_
    ) public {
        uint48 time = max_ ? type(uint48).max : 100;
        vm.warp(time);
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        grant.deadline = time;
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0)
        );
        _assertSettled(1, 0);
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-A08.
    function test_whenNewGrantPredatesCancellation_reverts(
        bool inlineGrant_,
        bool accountWide_
    ) public {
        IOperatorAuth.Grant memory stale = _grant(true);
        vm.prank(_borrower);
        if (accountWide_) _auth.cancelAllGrants();
        else _auth.cancelGrant(address(_executor));
        _rejectNewGrant(
            inlineGrant_,
            stale,
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidEpoch.selector)
        );
        assertEq(
            _auth.accountEpochs(_borrower),
            accountWide_ ? 1 : 0,
            "Cancellation epoch preserved"
        );
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            accountWide_ ? 0 : 1,
            "Pair epoch unchanged by rejected grant"
        );
    }

    // Scenarios: BLREX-A08.
    function test_whenNewGrantPredatesReplacement_reverts(bool inlineGrant_) public {
        _account.approveGrant(_auth, _grant(true));
        IOperatorAuth.Grant memory stale = _grant(true);
        _account.approveGrant(_auth, _grant(true));
        _rejectNewGrant(
            inlineGrant_,
            stale,
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidEpoch.selector)
        );
        assertEq(_auth.pairEpochs(_borrower, address(_executor)), 2, "Replacement remains current");
    }

    // Scenarios: BLREX-A29.
    function test_whenNewGrantPermissionsAreMalformed_reverts(
        bool inlineGrant_,
        bool wrongLength_
    ) public {
        IOperatorAuth.Grant memory grant = _grant(true);
        if (wrongLength_) grant.permissions = hex"01";
        else {
            // Set the high bits of the first address word while retaining canonical length.
            grant.permissions[0] = bytes1(uint8(1));
        }
        _rejectNewGrant(
            inlineGrant_,
            grant,
            abi.encodeWithSelector(IBurnerLoansAuth.BurnerLoansAuth_InvalidPermissions.selector)
        );
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            0,
            "Rejected permissions leave epoch unchanged"
        );
    }

    function _rejectNewGrant(
        bool inlineGrant_,
        IOperatorAuth.Grant memory grant_,
        bytes memory reason_
    ) private {
        IExecutor.SignedGrant memory signed = _signedGrant(grant_);
        vm.expectRevert(reason_);
        if (inlineGrant_) {
            _account.run(
                _executor,
                _funding(address(_asset), 1),
                _single(_deposit(1)),
                new IExecutor.Output[](0),
                signed
            );
        } else {
            _account.approveGrant(_auth, grant_);
        }
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Rejected grant leaves funding untouched");
        _assertSettled(0, 0);
    }

    function _assertAdmissionRollback(bool inlineGrant_, bool multiple_) private view {
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Rejected batch leaves funding untouched");
        _assertSettled(0, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }
}
