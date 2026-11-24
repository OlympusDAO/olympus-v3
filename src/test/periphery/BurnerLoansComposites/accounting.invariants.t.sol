// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansCompositesTest} from "./fixtures/BurnerLoansCompositesTest.sol";
import {CompositesAccountingHandler} from "./fixtures/CompositesAccountingHandler.sol";

/// @dev Four independent accounts exercise ordinary lending, surplus refunds and over-budget
///      rollbacks. Modeled OHM originates from minted principal and is burned on repayment.
/// forge-config: default.invariant.runs = 32
/// forge-config: default.invariant.depth = 32
/// forge-config: default.invariant.fail-on-revert = true
contract BurnerLoansCompositesAccountingInvariantsTest is BurnerLoansCompositesTest {
    CompositesAccountingHandler[4] internal _actors;
    uint256 internal _initialOhmSupply;

    function setUp() public override {
        super.setUp();
        _config.setAssetFeeConfig(address(_asset), IBurnerLoansRisk.AssetFeeConfig(0, 0, 0, 0));
        _asset.mint(address(_executor), 17);
        _ohm.mint(address(_executor), 11);
        _initialOhmSupply = _ohm.totalSupply();
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = CompositesAccountingHandler.deposit.selector;
        selectors[1] = CompositesAccountingHandler.failDeposit.selector;
        selectors[2] = CompositesAccountingHandler.borrow.selector;
        selectors[3] = CompositesAccountingHandler.repay.selector;
        selectors[4] = CompositesAccountingHandler.withdraw.selector;
        for (uint256 i; i < _actors.length; ++i) {
            _actors[i] = new CompositesAccountingHandler(
                _executor,
                _asset,
                _ohm,
                _auth,
                i > 1,
                _SIGNER_KEY
            );
            IOperatorAuth.Grant memory grant = _operatorGrant(
                address(_actors[i]),
                address(_executor),
                type(uint48).max
            );
            grant.multiple = i % 2 == 0;
            _actors[i].initialize(grant);
            targetContract(address(_actors[i]));
            targetSelector(FuzzSelector(address(_actors[i]), selectors));
        }
    }

    // Scenarios: BLREX-C06.
    function invariant_walletAndCustodyConservation() public view {
        uint256 deposits;
        uint256 principal;
        for (uint256 i; i < _actors.length; ++i) {
            CompositesAccountingHandler actor = _actors[i];
            IBurnerLoansCore.Position memory position = _lens.getPosition(
                address(_asset),
                address(actor)
            );
            uint256 modeledDeposit = actor.depositedTotal();
            assertEq(
                position.depositedCollateral,
                modeledDeposit,
                "Each account owns only its modeled deposits"
            );
            assertEq(
                _asset.balanceOf(address(actor)),
                actor.mintedTotal() - modeledDeposit,
                "Unused and reverted inputs stay with their account"
            );
            uint256 modeledDebt = actor.principal();
            assertEq(position.debtOhm, modeledDebt, "Each position owes modeled principal");
            assertEq(
                _ohm.balanceOf(address(actor)),
                modeledDebt,
                "Wallet OHM equals draws less repayment"
            );
            assertEq(
                actor.refundCallbacks(),
                actor.withdrawals(),
                "Every callback-bearing withdrawal refunds once"
            );
            assertEq(
                actor.callbackToken().balanceOf(address(actor)),
                1,
                "Callback input returns to original account"
            );
            assertEq(
                actor.callbackToken().balanceOf(address(_executor)),
                23,
                "Protected callback tokens remain"
            );
            assertEq(
                _auth.getGrant(address(actor), address(_executor)).actions,
                i % 2 == 0 ? 15 : 0,
                "Grant lifetime matches account mode"
            );
            deposits += modeledDeposit;
            principal += modeledDebt;
        }
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            deposits,
            "Actual custody equals sum of modeled account deposits"
        );
        assertEq(
            _asset.balanceOf(address(_executor)),
            17,
            "Every sequence preserves protected starting funds"
        );
        assertEq(
            _asset.allowance(address(_executor), address(_core)),
            0,
            "No Core allowance survives successful or failed executions"
        );
        assertEq(_core.totalActiveDebtOhm(), principal, "Core reconciles all account debts");
        assertEq(
            _inventory.activePrincipalOhm(),
            principal,
            "Inventory reconciles all account debts"
        );
        assertEq(
            _ohm.totalSupply(),
            _initialOhmSupply + principal,
            "Net minted OHM equals outstanding debt"
        );
        assertEq(_ohm.balanceOf(address(_executor)), 11, "Protected OHM stays with executor");
        assertEq(
            _ohm.allowance(address(_executor), address(_core)),
            0,
            "No OHM allowance survives"
        );
    }
}
