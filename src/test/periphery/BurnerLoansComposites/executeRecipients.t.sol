// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";

// Contracts
import {BurnerLoansCompositesGrantModesTest} from "./fixtures/BurnerLoansCompositesGrantModesTest.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";

contract BurnerLoansCompositesExecuteRecipientsTest is BurnerLoansCompositesGrantModesTest {
    // Scenarios: BLREX-P03.
    function test_givenCollateralPosition_whenGrantSpecifiesPayoutRecipient(
        bool inlineGrant_,
        bool multiple_,
        bool borrowToCaller_
    ) public givenCollateralPosition {
        address borrowRecipient = borrowToCaller_ ? _borrower : _recipient;
        address withdrawRecipient = borrowToCaller_ ? _recipient : _borrower;
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        permissions.borrowRecipient = borrowRecipient;
        permissions.withdrawRecipient = withdrawRecipient;
        grant.permissions = abi.encode(permissions);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _borrow(100e9, 1e6, borrowRecipient);
        operations[1] = IExecutor.Operation(
            IExecutor.OperationKind.Withdraw,
            abi.encode(
                IExecutor.Withdraw(
                    address(_asset),
                    100e6,
                    withdrawRecipient,
                    address(_asset),
                    100e6
                )
            )
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1e6),
            operations,
            new IExecutor.Output[](0)
        );
        _assertSettled(1900e6, 100e9);
        assertEq(
            _ohm.balanceOf(borrowRecipient),
            100e9,
            "Only the bound recipient receives borrowed OHM"
        );
        assertEq(_ohm.balanceOf(withdrawRecipient), 0, "Withdrawal recipient receives no OHM");
        // 125e6 required collateral times 25 bps is 312500 raw fee units.
        assertEq(
            _asset.balanceOf(_borrower),
            8000e6 - 312_500 + (borrowToCaller_ ? 0 : 100e6),
            "Caller settles fee and receives collateral only if named"
        );
        assertEq(
            _asset.balanceOf(_recipient),
            borrowToCaller_ ? 100e6 : 0,
            "Third-party payout matches grant"
        );
    }

    // Scenarios: BLREX-P07.
    function test_whenVaultSharesAreRefunded(bool inlineGrant_, bool multiple_) public {
        MockERC20 underlying = new MockERC20("Vault asset", "VA", 6);
        MockERC4626 vault = new MockERC4626(OZERC20(address(underlying)), "Share", "SH");
        _registerShareMarket(underlying, vault);
        underlying.mint(address(this), 17);
        assertTrue(underlying.approve(address(vault), 17), "Approve initial vault deposit");
        assertEq(vault.deposit(17, address(_executor)), 17, "Seed protected shares at 1:1");
        underlying.mint(_borrower, 20e6);
        IOperatorAuth.Grant memory grant = _operatorGrantForAsset(
            _borrower,
            address(_executor),
            type(uint48).max,
            address(underlying)
        );
        grant.multiple = multiple_;
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = IExecutor.Operation(
            IExecutor.OperationKind.Deposit,
            abi.encode(IExecutor.Deposit(address(underlying), 20e6))
        );
        operations[1] = IExecutor.Operation(
            IExecutor.OperationKind.Withdraw,
            abi.encode(
                IExecutor.Withdraw(
                    address(underlying),
                    20e6,
                    address(_executor),
                    address(vault),
                    20e6
                )
            )
        );
        IExecutor.Output[] memory outputs = new IExecutor.Output[](1);
        outputs[0] = IExecutor.Output(address(vault), 20e6);
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(underlying), 20e6),
            operations,
            outputs
        );
        IBurnerLoansCollateral.WithdrawPreview memory withdrawal = abi.decode(
            results[1],
            (IBurnerLoansCollateral.WithdrawPreview)
        );
        assertEq(
            withdrawal.returnToken,
            address(vault),
            "Withdrawal returns the admitted share token"
        );
        assertEq(
            withdrawal.returnAmount,
            20e6,
            "At 1:1 the 20e6 credited units return 20e6 shares"
        );
        assertEq(vault.balanceOf(_borrower), 20e6, "Caller receives the raw share output");
        assertEq(vault.balanceOf(address(_executor)), 17, "Protect pre-existing shares");
        assertEq(vault.balanceOf(address(_depositManager)), 0, "Vault custody settled");
        assertEq(
            _lens.getPosition(address(underlying), _borrower).depositedCollateral,
            0,
            "Position collateral cleared"
        );
    }

    // Scenarios: BLREX-P04.
    function test_givenCollateralPosition_whenWithdrawalFundsLaterDeposit(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _withdraw(10e6);
        operations[1] = _deposit(9e6);
        IExecutor.Output[] memory outputs = new IExecutor.Output[](1);
        outputs[0] = IExecutor.Output(address(_asset), 1e6);
        _executeGrantMode(inlineGrant_, signed, new IExecutor.Funding[](0), operations, outputs);
        _assertSettled(1999e6, 0);
        assertEq(_asset.balanceOf(_borrower), 8001e6, "Only withdrawn surplus goes to caller");
    }

    function _registerShareMarket(MockERC20 underlying_, MockERC4626 vault_) private {
        _price.setPrice(address(underlying_), 1e18);
        vm.prank(_fixtureAdmin);
        _depositManager.addAsset(
            IERC20(address(underlying_)),
            IERC4626(address(vault_)),
            type(uint256).max,
            0
        );
        vm.prank(_fixtureAdmin);
        _depositManager.addAssetPeriod(
            IERC20(address(underlying_)),
            LoanParameters._DEPOSIT_PERIOD,
            address(_core)
        );
        vm.prank(_fixtureAdmin);
        _config.addAsset(
            address(underlying_),
            100_000e9,
            IBurnerLoansRisk.AssetRiskConfigInput(8500, 12500, 100, 30 days, 90 days, 1000e6),
            IBurnerLoansRisk.AssetFeeConfig(0, 0, 0, 0),
            true
        );
    }
}
