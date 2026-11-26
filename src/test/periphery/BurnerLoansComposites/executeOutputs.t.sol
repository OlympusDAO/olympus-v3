// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";

// Contracts
import {BurnerLoansCompositesGrantModesTest} from "./fixtures/BurnerLoansCompositesGrantModesTest.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

contract BurnerLoansCompositesExecuteOutputsTest is BurnerLoansCompositesGrantModesTest {
    // Scenarios: BLREX-O01.
    function test_whenRefundMeetsReturnMinimum(
        bool inlineGrant_,
        bool multiple_,
        uint256 minimum_
    ) public {
        minimum_ = bound(minimum_, 0, 5e6);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 15e6),
            _single(_deposit(10e6)),
            _outputs(address(_asset), minimum_)
        );
        _assertSettled(10e6, 0);
        _assertAcceptedGrant(multiple_);
        assertEq(
            _asset.balanceOf(_borrower),
            9990e6,
            "Five collateral tokens returned after deposit"
        );
    }

    // Scenarios: BLREX-O02.
    function test_whenReturnMinimumExceedsRefund_reverts(
        bool inlineGrant_,
        bool multiple_,
        uint256 minimum_
    ) public {
        minimum_ = bound(minimum_, 5e6 + 1, type(uint256).max);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _expectInsufficientReturn(address(_asset), minimum_, 5e6);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 15e6),
            _single(_deposit(10e6)),
            _outputs(address(_asset), minimum_)
        );
        _assertSettled(0, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
        assertEq(
            _asset.balanceOf(_borrower),
            10_000e6,
            "Failed final minimum restores wallet input"
        );
    }

    // Scenarios: BLREX-O01.
    function test_whenReturnMinimumBoundarySeeds() public {
        uint256[4] memory seeds = [uint256(0), 1, 5e6 - 1, 5e6];
        for (uint256 i; i < seeds.length; ++i) {
            for (uint256 mode; mode < 4; ++mode) {
                uint256 snapshot = vm.snapshotState();
                test_whenRefundMeetsReturnMinimum(mode < 2, mode % 2 == 0, seeds[i]);
                assertTrue(
                    vm.revertToState(snapshot),
                    "Restore each output boundary and grant mode"
                );
            }
        }
    }

    // Scenarios: BLREX-O02.
    function test_whenReturnMinimumFailureBoundarySeeds() public {
        uint256[2] memory seeds = [uint256(5e6 + 1), type(uint256).max];
        for (uint256 i; i < seeds.length; ++i) {
            for (uint256 mode; mode < 4; ++mode) {
                uint256 snapshot = vm.snapshotState();
                test_whenReturnMinimumExceedsRefund_reverts(mode < 2, mode % 2 == 0, seeds[i]);
                assertTrue(
                    vm.revertToState(snapshot),
                    "Restore each rejected minimum and grant mode"
                );
            }
        }
    }

    // Scenarios: BLREX-O03.
    function test_givenExistingWalletBalance_whenNoOutputProduced_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public {
        _ohm.mint(_borrower, 100e9);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _expectInsufficientReturn(address(_ohm), 1, 0);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            _outputs(address(_ohm), 1)
        );
        _assertSettled(0, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
        assertEq(
            _ohm.balanceOf(_borrower),
            100e9,
            "Existing wallet holdings cannot satisfy return minimum"
        );
    }

    // Scenarios: BLREX-O04.
    function test_givenCollateralPosition_whenBorrowPaidDirectlyToCaller(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        _ohm.mint(_borrower, 7e9);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1e6),
            _single(_borrow(100e9, 1e6, _borrower)),
            _outputs(address(_ohm), 100e9)
        );
        _assertSettled(2000e6, 100e9);
        _assertAcceptedGrant(multiple_);
        assertEq(
            _ohm.balanceOf(_borrower),
            107e9,
            "Direct principal payout counts above existing holdings"
        );
    }

    // Scenarios: BLREX-O05, BLREX-T16.
    function test_givenCollateralPosition_whenBorrowPaidToExecutor(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        _ohm.mint(address(_executor), 17e9);
        _asset.mint(address(_executor), 19);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1e6),
            _single(_borrow(100e9, 1e6, address(_executor))),
            _outputs(address(_ohm), 100e9)
        );
        assertEq(_ohm.balanceOf(_borrower), 100e9, "Borrow proceeds count only after final refund");
        assertEq(_ohm.balanceOf(address(_executor)), 17e9, "Protected executor OHM is retained");
        // The fee is 125e6 * 25 / 10_000 = 312500 raw collateral units.
        assertEq(_asset.balanceOf(_borrower), 8000e6 - 312_500, "Unused fee funding is returned");
        assertEq(_asset.balanceOf(address(_executor)), 19, "Only protected collateral is retained");
        assertEq(_asset.allowance(address(_executor), address(_core)), 0, "Core allowance cleared");
        assertEq(_position().debtOhm, 100e9, "Successful borrow records actual principal");
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-O06.
    function test_givenCollateralPosition_whenBorrowPaidElsewhere_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _expectInsufficientReturn(address(_ohm), 100e9, 0);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1e6),
            _single(_borrow(100e9, 1e6, _recipient)),
            _outputs(address(_ohm), 100e9)
        );
        _assertSettled(2000e6, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
        assertEq(
            _ohm.balanceOf(_recipient),
            0,
            "Third-party payout rolls back with caller minimum"
        );
    }

    // Scenarios: BLREX-O07.
    function test_givenCollateralPosition_whenMultipleReturnTokens(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IExecutor.Output[] memory outputs = new IExecutor.Output[](2);
        outputs[0] = IExecutor.Output(address(_ohm), 100e9);
        // Fee = 125e6 * 25 / 10_000 = 312500 raw six-decimal collateral units.
        outputs[1] = IExecutor.Output(address(_asset), 1e6 - 312_500);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1e6),
            _single(_borrow(100e9, 1e6, _borrower)),
            outputs
        );
        _assertSettled(2000e6, 100e9);
        _assertAcceptedGrant(multiple_);
        assertEq(_ohm.balanceOf(_borrower), 100e9, "OHM requirement satisfied");
        assertEq(
            _asset.balanceOf(_borrower),
            8000e6 - 312_500,
            "Collateral refund requirement satisfied"
        );
    }

    // Scenarios: BLREX-O07.
    function test_givenCollateralPosition_whenOneReturnTokenFallsShort_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IExecutor.Output[] memory outputs = new IExecutor.Output[](2);
        outputs[0] = IExecutor.Output(address(_ohm), 100e9);
        // Actual collateral refund = 1e6 - (125e6 * 25 / 10_000) = 687500 raw units.
        outputs[1] = IExecutor.Output(address(_asset), 687_501);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _expectInsufficientReturn(address(_asset), 687_501, 687_500);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1e6),
            _single(_borrow(100e9, 1e6, _borrower)),
            outputs
        );
        _assertSettled(2000e6, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
        assertEq(
            _ohm.balanceOf(_borrower),
            0,
            "Satisfied first output does not bypass failed second output"
        );
        assertEq(_asset.balanceOf(_borrower), 8000e6, "All fee funding restored");
    }

    // Scenarios: BLREX-O08.
    function test_whenDuplicateOutputToken_reverts(bool inlineGrant_, bool multiple_) public {
        IExecutor.Output[] memory outputs = new IExecutor.Output[](2);
        outputs[0] = IExecutor.Output(address(_asset), 0);
        outputs[1] = IExecutor.Output(address(_asset), 0);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_DuplicateOutput.selector,
                address(_asset)
            )
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            outputs
        );
        _assertSettled(0, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-O09.
    function test_whenOutputTokenIsZero_reverts(bool inlineGrant_, bool multiple_) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InvalidToken.selector,
                address(0)
            )
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            _outputs(address(0), 0)
        );
        _assertSettled(0, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-O09.
    function test_whenOutputTokenHasNoCode_reverts(bool inlineGrant_, bool multiple_) public {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InvalidToken.selector,
                _recipient
            )
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            _outputs(_recipient, 0)
        );
        _assertSettled(0, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-O10.
    function test_whenEntireMaximumInputReturned(bool inlineGrant_, bool multiple_) public {
        MockERC20 token = new MockERC20("Unused input", "IN", 18);
        token.mint(_borrower, type(uint256).max);
        IExecutor.Funding[] memory funding = new IExecutor.Funding[](2);
        funding[0] = IExecutor.Funding(address(_asset), 1);
        funding[1] = IExecutor.Funding(address(token), type(uint256).max);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _executeGrantMode(
            inlineGrant_,
            signed,
            funding,
            _single(_deposit(1)),
            _outputs(address(token), type(uint256).max)
        );
        assertEq(
            token.balanceOf(_borrower),
            type(uint256).max,
            "Maximum input counts as returned without overflow"
        );
        assertEq(token.balanceOf(address(_executor)), 0, "Maximum input fully refunded");
        _assertSettled(1, 0);
        _assertAcceptedGrant(multiple_);
    }

    function _outputs(
        address token_,
        uint256 minimum_
    ) private pure returns (IExecutor.Output[] memory outputs) {
        outputs = new IExecutor.Output[](1);
        outputs[0] = IExecutor.Output(token_, minimum_);
    }

    function _expectInsufficientReturn(address token_, uint256 minimum_, uint256 actual_) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientReturn.selector,
                token_,
                minimum_,
                actual_
            )
        );
    }
}
