// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Contracts
import {BurnerLoansSeizeTestBase} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeTestBase.sol";

// Literals are independent expected values and boundary seeds.
// Fixture calls and ignored returns are checked through errors and ledger assertions.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

contract BurnerLoansSeizePayoutTest is BurnerLoansSeizeTestBase {
    // The mock Risk reward is 7 raw units; redemption yields 2,000,000,000 raw units.
    // The independent remainder is 1,999,999,993 raw units. No fee is created by default.
    // Scenarios: BLLIQ-SEIZE-P15.
    function test_givenKeeperPayoutFails_whenSeized_thenOnlyKeeperRemainsPending() public {
        _failPayout(_recipient, 7);
        _assertSeizurePendingAndRetry(7, 0, 7);
    }

    // Scenarios: BLLIQ-SEIZE-P16.
    function test_givenTreasuryPayoutFails_whenSeized_thenOnlyTreasuryRemainsPending() public {
        _failPayout(_payout.treasury(), 1_999_999_993);
        _assertSeizurePendingAndRetry(0, 1_999_999_993, 1_999_999_993);
    }

    // Scenarios: BLLIQ-SEIZE-P17.
    function test_givenBothPayoutsFail_whenSeized_thenBothRemainPending() public {
        _failPayout(_recipient, 7);
        _failPayout(_payout.treasury(), 1_999_999_993);
        _assertSeizurePendingAndRetry(7, 1_999_999_993, 2_000_000_000);
    }

    function _failPayout(address recipient_, uint256 amount_) internal {
        vm.mockCall(
            address(_asset),
            abi.encodeCall(_asset.transfer, (recipient_, amount_)),
            abi.encode(false)
        );
    }

    function _assertSeizurePendingAndRetry(
        uint256 keeper_,
        uint256 treasury_,
        uint256 total_
    ) internal {
        IBurnerLoansCore.SeizePreview memory quote = _liquidation.previewSeizeFor(
            _recipient,
            address(_asset),
            _borrowers()
        );
        assertEq(quote.keeperReward, 7, "Quote does not predict payout delivery failure");
        assertEq(quote.collateralToTreasury, 1_999_999_993, "Independent quoted remainder");
        uint256 keeperBefore = _asset.balanceOf(_recipient);
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        vm.prank(_recipient);
        _liquidation.seize(address(_asset), _borrowers());
        (uint256 fee, uint256 seized, uint256 total) = _payout.payoutReserves(address(_asset));
        assertEq(fee, 0, "No fee obligation created by default");
        assertEq(seized, treasury_, "Only failed Treasury proceeds reserved");
        assertEq(
            _payout.pendingPayout(address(_asset), _recipient),
            keeper_,
            "Only failed keeper allocation pending"
        );
        assertEq(total, total_, "Independent hard-coded reserve total");
        assertEq(_asset.balanceOf(address(_payout)), total_, "Pending payouts fully backed");
        assertEq(
            _inventory.activePrincipalOhm(),
            0,
            "Optional payout failure cannot block default"
        );
        assertEq(
            _asset.balanceOf(_recipient),
            keeperBefore + 7 - keeper_,
            "Only delivered keeper amount received"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + 1_999_999_993 - treasury_,
            "Only delivered Treasury amount received"
        );
        assertEq(_position().principalDue, 0, "Default commits despite optional delivery failure");
        assertEq(_position().collateral, 0, "Collateral cleared despite delivery failure");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            0,
            "DM liability released"
        );
        vm.clearMockedCalls();
        _payout.transferPendingPayout(address(_asset), _recipient);
        _payout.transferPendingPayout(address(_asset), _payout.treasury());
        assertEq(
            _asset.balanceOf(address(_payout)),
            0,
            "Later retry drains only backed obligations"
        );
        _payout.transferPendingPayout(address(_asset), _recipient);
        _payout.transferPendingPayout(address(_asset), _payout.treasury());
        assertEq(_asset.balanceOf(_recipient), keeperBefore + 7, "Keeper paid once across retries");
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore + 1_999_999_993,
            "Treasury paid once across retries"
        );
        (fee, seized, total) = _payout.payoutReserves(address(_asset));
        assertEq(fee, 0, "No fee after retries");
        assertEq(seized, 0, "Treasury reserve cleared");
        assertEq(total, 0, "All pending reserves cleared");
        assertEq(
            _payout.pendingPayout(address(_asset), _recipient),
            0,
            "Keeper obligation cleared"
        );
    }

    // Scenarios: BLLIQ-SEIZE-A01.
    function test_whenZeroAddressKeeperSeizes_thenRewardRemainsBacked() public {
        IBurnerLoansCore.SeizePreview memory quote = _liquidation.previewSeizeFor(
            address(0),
            address(_asset),
            _borrowers()
        );
        assertEq(quote.keeperReward, 7, "Zero actor receives ordinary reward quote");
        vm.prank(address(0));
        _liquidation.seize(address(_asset), _borrowers());
        assertEq(_inventory.activePrincipalOhm(), 0, "Permissionless zero caller defaults debt");
        assertEq(
            _payout.pendingPayout(address(_asset), address(0)),
            7,
            "Unsendable reward remains owed"
        );
        (, uint256 seized, uint256 total) = _payout.payoutReserves(address(_asset));
        assertEq(seized, 0, "Treasury allocation delivered");
        assertEq(total, 7, "Only unsendable reward reserved");
        assertEq(_asset.balanceOf(address(_payout)), 7, "Unsendable reward remains backed");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
