// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.34;

// Interfaces
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansCompositesTest} from "./BurnerLoansCompositesTest.sol";
import {CompositesAccount} from "./CompositesAccount.sol";

/// @dev Uses an optional contract account so direct temporary approval and execution share one
///      transaction. Existing EOA cases remain in execute.t.sol and executeWithGrant.t.sol.
abstract contract BurnerLoansCompositesGrantModesTest is BurnerLoansCompositesTest {
    CompositesAccount internal _account;
    address internal _accountOwner;

    function setUp() public virtual override {
        super.setUp();
        _accountOwner = makeAddr("compositesAccountOwner");
        _account = new CompositesAccount(_accountOwner, vm.addr(_SIGNER_KEY));
        _borrower = address(_account);
        _asset.mint(_borrower, 10_000e6);
        vm.prank(_borrower);
        _asset.approve(address(_core), type(uint256).max);
    }

    modifier givenCollateralPosition() {
        _seedCollateral(2000e6);
        _;
    }

    modifier givenOlderDebt() {
        _seedCollateral(2000e6);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 100e6, address(0));
        // This satisfies Debt's block-based repayment restriction; it does not expire grants.
        vm.roll(vm.getBlockNumber() + 1);
        _;
    }

    modifier givenCollateralBelowCeiling() {
        _seedCollateral(400e6);
        _;
    }

    function _seedCollateral(uint128 amount_) internal {
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), amount_, _borrower);
    }

    function _grant(bool multiple_) internal view returns (IOperatorAuth.Grant memory grant) {
        grant = _operatorGrant(_borrower, address(_executor), type(uint48).max);
        grant.multiple = multiple_;
    }

    function _prepareGrantMode(
        bool inlineGrant_,
        IOperatorAuth.Grant memory grant_
    ) internal returns (IExecutor.SignedGrant memory signed) {
        // Finish signature-domain reads before a test arms its expected execution revert.
        if (inlineGrant_) return _signedGrant(grant_);
        if (grant_.multiple) {
            vm.prank(_accountOwner);
            _account.approveGrant(_auth, grant_);
        }
        signed.grant = grant_;
    }

    /// @dev The flags choose only admission/lifetime, never an expected operation outcome.
    ///      Foundry isolate=true makes each call from the test to _account a new transaction.
    function _executeGrantMode(
        bool inlineGrant_,
        IExecutor.SignedGrant memory signed_,
        IExecutor.Funding[] memory funding_,
        IExecutor.Operation[] memory operations_,
        IExecutor.Output[] memory outputs_
    ) internal returns (bytes[] memory) {
        vm.prank(_accountOwner);
        if (inlineGrant_) return _account.run(_executor, funding_, operations_, outputs_, signed_);
        if (signed_.grant.multiple) {
            // The caller installed reusable direct authority in an earlier account transaction.
            return _account.runWithExistingGrant(_executor, funding_, operations_, outputs_);
        }
        // A direct temporary grant must be approved and used in the same account transaction.
        return
            _account.approveGrantAndRun(
                _auth,
                signed_.grant,
                _executor,
                funding_,
                operations_,
                outputs_
            );
    }

    function _withdraw(uint128 amount_) internal view returns (IExecutor.Operation memory) {
        return
            IExecutor.Operation(
                IExecutor.OperationKind.Withdraw,
                abi.encode(
                    IExecutor.Withdraw(
                        address(_asset),
                        amount_,
                        address(_executor),
                        address(_asset),
                        amount_
                    )
                )
            );
    }

    function _extend(uint16 terms_) internal view returns (IExecutor.Operation memory) {
        return
            IExecutor.Operation(
                IExecutor.OperationKind.Extend,
                abi.encode(IExecutor.Extend(address(_asset), terms_, 7, address(0)))
            );
    }

    function _assertSettled(uint128 collateral_, uint128 principal_) internal view {
        assertEq(
            _position().depositedCollateral,
            collateral_,
            "Canonical collateral matches operations"
        );
        assertEq(_position().debtOhm, principal_, "Canonical principal matches operations");
        assertEq(_core.totalActiveDebtOhm(), principal_, "Core principal aggregate agrees");
        assertEq(
            _inventory.activePrincipalOhm(),
            principal_,
            "Inventory principal aggregate agrees"
        );
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            collateral_,
            "Actual collateral custody agrees"
        );
        assertEq(_asset.balanceOf(address(_executor)), 0, "No unspent collateral remains");
        assertEq(_ohm.balanceOf(address(_executor)), 0, "No unspent OHM remains");
        assertEq(
            _asset.allowance(address(_executor), address(_core)),
            0,
            "Collateral allowance cleared"
        );
        assertEq(_ohm.allowance(address(_executor), address(_core)), 0, "OHM allowance cleared");
    }

    function _assertAcceptedGrant(bool multiple_) internal view {
        assertEq(_auth.pairEpochs(_borrower, address(_executor)), 1, "Grant accepted exactly once");
        IOperatorAuth.Grant memory live = _auth.getGrant(_borrower, address(_executor));
        assertEq(
            live.actions,
            multiple_ ? 15 : 0,
            "Only reusable authority survives the account transaction"
        );
        assertEq(live.multiple, multiple_, "Grant lifetime mode retained");
    }

    function _assertGrantAfterRevert(bool inlineGrant_, bool multiple_) internal view {
        // Earlier direct reusable approval is a separate successful transaction; other approval
        // modes share the reverted transaction with execution and must roll back their epoch.
        uint256 expectedEpoch = !inlineGrant_ && multiple_ ? 1 : 0;
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            expectedEpoch,
            "Grant rollback respects transaction boundary"
        );
    }
}
