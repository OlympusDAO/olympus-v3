// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Contracts
import {BurnerLoansActionHandler} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansActionHandler.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

/// @notice Arbitrary action sequences across the real accounting/custody boundary.
/// @dev Scope: one borrower, one direct-custody asset, fixed prices, ordinary keeper, no governance mutation.
contract BurnerLoansSeizeAccountingInvariantTest is BurnerLoansModularTest {
    BurnerLoansActionHandler internal _handler;

    function setUp() public override {
        super.setUp();
        _handler = new BurnerLoansActionHandler(
            _collateral,
            _debt,
            _liquidation,
            _asset,
            _ohm,
            _price,
            address(_core)
        );
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = _handler.deposit.selector;
        selectors[1] = _handler.borrow.selector;
        selectors[2] = _handler.repay.selector;
        selectors[3] = _handler.withdraw.selector;
        selectors[4] = _handler.seizeExpired.selector;
        targetSelector(FuzzSelector({addr: address(_handler), selectors: selectors}));
        targetContract(address(_handler));
    }

    // Scenarios: BLCOL-DEPOSIT-N01, BLCOL-WITHDRAW-N01, BLDEBT-BORROW-N06, BLDEBT-REPAY-N01, BLLIQ-SEIZE-P10.
    function invariant_modelMatchesEveryAuthoritativeLedger() public view {
        IBurnerLoansCore.Position memory position = _lens.getPosition(
            address(_asset),
            address(_handler)
        );
        assertEq(
            position.depositedCollateral,
            _handler.collateral(),
            "Canonical collateral equals independent model"
        );
        assertEq(
            position.debtOhm,
            _handler.principal(),
            "Canonical principal equals independent model"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            _handler.principal(),
            "Funding ledger equals modeled debt"
        );
        assertEq(
            _floan.getMarketPrincipalDue(_core.marketId(address(_asset))),
            _handler.principal(),
            "FLOAN market aggregate"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            _handler.collateral(),
            "DM operator liabilities equal modeled credit"
        );
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            _handler.collateral(),
            "Direct collateral backed exactly"
        );
        assertEq(_asset.balanceOf(address(_core)), 0, "Core retains no principal custody balance");
    }
}
