// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20Errors} from "@openzeppelin-5.7.0/interfaces/draft-IERC6093.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";
import {BL_DEBT_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";

// Contracts
import {Actions, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansDebtTest} from "src/test/policies/BurnerLoansDebt/BurnerLoansDebtTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, unsafe-typecast, unused-return)

contract BurnerLoansDebtRepayTest is BurnerLoansDebtTest {
    error PricingUnavailable();
    uint128 internal constant _PRINCIPAL = 100e9;

    function setUp() public override {
        super.setUp();
        _depositCollateral(2000e6);
        _mockRisk(0);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), _PRINCIPAL, _borrower, _borrower, 0, address(0));
        vm.roll(block.number + 1);
    }

    // Scenarios: BLDEBT-REPAY-A01, BLDEBT-REPAY-N01, BLDEBT-REPAY-L01.
    function test_givenPartialDebt_whenAnyPayerRepays_thenExactAccounting(
        address payer_,
        uint128 amount_
    ) public {
        vm.assume(
            payer_ != address(0) && payer_ != address(_inventory) && payer_ != address(_core)
        );
        amount_ = uint128(bound(amount_, 1, _PRINCIPAL - 1));
        _fundRepayer(payer_, amount_);
        uint256 payerBefore = _ohm.balanceOf(payer_);
        IFLOANv1.Position memory beforePosition = _position();
        vm.prank(payer_);
        (uint128 quoted, uint256 quotedHealth) = _debt.previewRepay(
            address(_asset),
            amount_,
            _borrower
        );
        assertEq(quoted, _PRINCIPAL - amount_, "Independent remaining principal");
        assertEq(quotedHealth, _HEALTH, "Risk health forwarded unchanged");
        assertEq(_position().principalDue, _PRINCIPAL, "Preview preserves debt");
        vm.expectEmit(address(_debt));
        emit IBurnerLoansDebt.Repaid(
            payer_,
            address(_asset),
            _borrower,
            amount_,
            _PRINCIPAL - amount_
        );
        vm.prank(payer_);
        (uint128 remaining, uint256 health) = _debt.repay(address(_asset), amount_, _borrower);
        assertEq(remaining, _PRINCIPAL - amount_, "Actual remaining principal");
        assertEq(health, _HEALTH, "Actual health uses remaining debt");
        assertEq(_ohm.balanceOf(payer_), payerBefore - amount_, "Only payer supplies repayment");
        assertEq(_inventory.activePrincipalOhm(), remaining, "Inventory principal reconciled");
        assertEq(
            _floan.getMarketPrincipalDue(_core.marketId(address(_asset))),
            remaining,
            "FLOAN aggregate reconciled"
        );
        assertEq(_position().collateral, beforePosition.collateral, "Collateral preserved");
        assertEq(
            _position().maturity,
            beforePosition.maturity,
            "Expiry preserved for partial repayment"
        );
        assertEq(_ohm.balanceOf(address(_core)), 0, "Core retains no repayment");
    }

    // Scenarios: BLDEBT-REPAY-N01.
    function test_whenOneRawUnitRepaid_thenExactRemainingDebt() public {
        test_givenPartialDebt_whenAnyPayerRepays_thenExactAccounting(address(0xcafe), 1);
    }

    // Scenarios: BLDEBT-REPAY-N01.
    function test_whenAllButOneRawUnitRepaid_thenOneRemains() public {
        test_givenPartialDebt_whenAnyPayerRepays_thenExactAccounting(
            address(0xcafe),
            _PRINCIPAL - 1
        );
    }

    // Scenarios: BLDEBT-REPAY-N02, BLDEBT-REPAY-N07, BLDEBT-REPAY-A01.
    function test_givenFullDebt_whenAnyPayerRepays_thenNoPricing(address payer_) public {
        vm.assume(
            payer_ != address(0) && payer_ != address(_inventory) && payer_ != address(_core)
        );
        _fundRepayer(payer_, _PRINCIPAL);
        _mockRiskSnapshotFailure(abi.encodeWithSelector(PricingUnavailable.selector));
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encodeWithSelector(PricingUnavailable.selector)
        );
        vm.prank(payer_);
        (uint128 quote, uint256 quotedHealth) = _debt.previewRepay(
            address(_asset),
            _PRINCIPAL,
            _borrower
        );
        vm.prank(payer_);
        (uint128 remaining, uint256 health) = _debt.repay(address(_asset), _PRINCIPAL, _borrower);
        assertEq(quote, 0, "Full repayment quote");
        assertEq(remaining, 0, "No principal remains");
        assertEq(quotedHealth, type(uint256).max, "Debt-free quote");
        assertEq(health, type(uint256).max, "Debt-free result");
        assertEq(_inventory.activePrincipalOhm(), 0, "Inventory principal cleared");
        assertEq(_position().collateral, 2000e6, "Full repayment retains collateral");
        assertEq(
            _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
            0,
            "Active debt index cleared"
        );
    }

    // Scenarios: BLDEBT-REPAY-N03.
    function test_givenExpiredDebt_whenFullyRepaid_thenAllowed(uint256 now_) public {
        vm.warp(bound(now_, _position().maturity, type(uint256).max));
        test_givenFullDebt_whenAnyPayerRepays_thenNoPricing(_borrower);
    }

    // Scenarios: BLDEBT-REPAY-N04.
    function test_givenUnhealthyDebt_whenPartiallyRepaid_thenHelpfulRepaymentAllowed() public {
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encode(uint256(1))
        );
        _fundRepayer(_recipient, 1);
        vm.prank(_recipient);
        (, uint256 quotedHealth) = _debt.previewRepay(address(_asset), 1, _borrower);
        vm.prank(_recipient);
        (, uint256 health) = _debt.repay(address(_asset), 1, _borrower);
        assertEq(quotedHealth, 1, "Unhealthy quote allowed");
        assertEq(health, 1, "Helpful repayment need not cure all debt");
    }

    // Scenarios: BLDEBT-REPAY-N05.
    function test_givenOriginationsDisabled_whenRepaid_thenAllowed() public {
        _config.setAssetOriginationsEnabled(address(_asset), false);
        test_givenFullDebt_whenAnyPayerRepays_thenNoPricing(_borrower);
    }

    // Scenarios: BLDEBT-REPAY-N06.
    function test_givenInsolventCollateral_whenFullyRepaid_thenAllowed() public {
        _asset.burn(address(_depositManager), 1);
        test_givenFullDebt_whenAnyPayerRepays_thenNoPricing(_borrower);
    }

    // Scenarios: BLDEBT-REPAY-I01.
    function test_whenAmountZero_reverts(address payer_) public {
        _expectRepayRevert(
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_ZeroAmount.selector),
            0,
            _borrower,
            payer_
        );
    }

    // Scenarios: BLDEBT-REPAY-I02.
    function test_whenBorrowerZero_reverts(address payer_) public {
        _expectRepayRevert(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector),
            1,
            address(0),
            payer_
        );
    }

    // Scenarios: BLDEBT-REPAY-I04.
    function test_whenPositionAbsent_reverts(address payer_, address borrower_) public {
        vm.assume(borrower_ != address(0) && borrower_ != _borrower);
        _expectRepayRevert(
            abi.encodeWithSelector(IBurnerLoansDebt.BurnerLoans_NoCollateral.selector),
            1,
            borrower_,
            payer_
        );
    }

    // Scenarios: BLDEBT-REPAY-I05.
    function test_givenZeroDebt_whenPositiveRepayment_reverts(
        uint128 amount_,
        address payer_
    ) public {
        test_givenFullDebt_whenAnyPayerRepays_thenNoPricing(_borrower);
        amount_ = uint128(bound(amount_, 1, type(uint128).max));
        _expectRepayRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_RepayExceedsDebt.selector,
                uint256(amount_),
                uint256(0)
            ),
            amount_,
            _borrower,
            payer_
        );
    }

    // Scenarios: BLDEBT-REPAY-I06.
    function test_whenRepaymentExceedsDebt_reverts(uint128 amount_, address payer_) public {
        amount_ = uint128(bound(amount_, uint256(_PRINCIPAL) + 1, type(uint128).max));
        _expectRepayRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_RepayExceedsDebt.selector,
                uint256(amount_),
                uint256(_PRINCIPAL)
            ),
            amount_,
            _borrower,
            payer_
        );
    }

    // Scenarios: BLDEBT-REPAY-I07.
    function test_givenLatestBorrowBlock_whenRepaid_reverts() public {
        vm.roll(_position().lastBorrowBlock);
        _expectRepayRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_SameBlockRepay.selector,
                _position().lastBorrowBlock
            ),
            1,
            _borrower,
            _recipient
        );
    }

    // Scenarios: BLDEBT-REPAY-I03, BLDEBT-REPAY-D08, BLDEBT-REPAY-D09.
    function test_givenInventoryUnavailable_whenRepaid_reverts(bool active_, bool enabled_) public {
        vm.assume(!active_ || !enabled_);
        _setPolicyState(_inventory, active_, enabled_);
        _expectRepayRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_inventory)
            ),
            1,
            _borrower,
            _recipient
        );
    }

    // Scenarios: BLDEBT-REPAY-D04.
    function test_givenPartialDebt_whenPricingFails_reverts() public {
        _mockRiskSnapshotFailure(abi.encodeWithSelector(PricingUnavailable.selector));
        _expectRepayRevert(
            abi.encodeWithSelector(PricingUnavailable.selector),
            1,
            _borrower,
            _recipient
        );
    }

    // Scenarios: BLDEBT-REPAY-D05.
    function test_whenIncomingOhmInexact_thenDebtAndAllowanceRollBack() public {
        vm.mockCall(
            address(_ohm),
            abi.encodeWithSelector(
                _ohm.transferFrom.selector,
                _borrower,
                address(_inventory),
                uint256(1)
            ),
            abi.encode(true)
        );
        bytes32 rollbackBefore = _stateDigest(_borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(_ohm),
                address(_inventory),
                uint256(1),
                uint256(0)
            )
        );
        vm.prank(_borrower);
        _debt.repay(address(_asset), 1, _borrower);
        assertEq(_position().principalDue, _PRINCIPAL, "Inexact receipt rolls back FLOAN decrease");
        assertEq(_inventory.activePrincipalOhm(), _PRINCIPAL, "Inventory remains reconciled");
        assertEq(
            _stateDigest(_borrower),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLDEBT-REPAY-D06.
    function test_givenMintrBurnFailure_whenRepaid_thenDebtReducedAndOhmRetained(
        address payer_
    ) public {
        vm.assume(payer_ != address(0) && payer_ != address(_inventory));
        _ohm.mint(payer_, 1);
        uint256 payerBalance = _ohm.balanceOf(payer_);
        address mintr = address(_kernel.getModuleForKeycode(toKeycode("MINTR")));
        bytes memory failure = abi.encodeWithSelector(PricingUnavailable.selector);
        vm.mockCallRevert(
            mintr,
            abi.encodeWithSignature("burnOhm(address,uint256)", address(_inventory), uint256(1)),
            failure
        );
        vm.prank(payer_);
        _ohm.approve(address(_core), 1);
        vm.expectEmit(address(_inventory));
        emit IBurnerLoansInventory.OhmBurnFailed(1, failure);
        vm.prank(payer_);
        (uint128 remaining, ) = _debt.repay(address(_asset), 1, _borrower);
        assertEq(remaining, _PRINCIPAL - 1, "Burn failure cannot prevent repayment");
        assertEq(_ohm.balanceOf(address(_inventory)), 1, "Failed burn remains recoverable surplus");
        assertEq(
            _ohm.balanceOf(payer_),
            payerBalance - 1,
            "Actual payer charged once despite best-effort failure"
        );
        assertEq(_inventory.activePrincipalOhm(), _PRINCIPAL - 1, "Inventory debt decreases once");
        assertEq(
            _floan.getMarketPrincipalDue(_core.marketId(address(_asset))),
            _PRINCIPAL - 1,
            "Canonical debt decreases once"
        );
    }

    // Scenarios: BLDEBT-REPAY-D07.
    function test_givenMintrApprovalFailure_whenRepaid_thenSafeApprovalDeficitRemains(
        address payer_
    ) public {
        vm.assume(payer_ != address(0) && payer_ != address(_inventory));
        _ohm.mint(payer_, 1);
        uint256 payerBalance = _ohm.balanceOf(payer_);
        address mintr = address(_kernel.getModuleForKeycode(toKeycode("MINTR")));
        bytes memory failure = abi.encodeWithSelector(PricingUnavailable.selector);
        vm.mockCallRevert(
            mintr,
            abi.encodeWithSignature(
                "increaseMintApproval(address,uint256)",
                address(_inventory),
                uint256(1)
            ),
            failure
        );
        vm.prank(payer_);
        _ohm.approve(address(_core), 1);
        vm.expectEmit(address(_inventory));
        emit IBurnerLoansInventory.ApprovalRestorationFailed(1, failure);
        vm.prank(payer_);
        (uint128 remaining, ) = _debt.repay(address(_asset), 1, _borrower);
        assertEq(
            remaining,
            _PRINCIPAL - 1,
            "Approval restoration failure cannot prevent repayment"
        );
        assertEq(_ohm.balanceOf(address(_inventory)), 0, "Repayment was burned once");
        assertEq(
            _ohm.balanceOf(payer_),
            payerBalance - 1,
            "Actual payer charged once despite best-effort failure"
        );
        assertEq(_inventory.activePrincipalOhm(), _PRINCIPAL - 1, "Inventory debt decreases once");
        assertEq(
            _floan.getMarketPrincipalDue(_core.marketId(address(_asset))),
            _PRINCIPAL - 1,
            "Canonical debt decreases once"
        );
    }

    // Scenarios: BLDEBT-REPAY-A02.
    function test_givenActionRoleRevoked_whenRepaid_reverts() public {
        _rolesAdmin.revokeRole(BL_DEBT_POLICY_ROLE, address(_debt));
        _expectRepayRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_DEBT_POLICY_ROLE),
            1,
            _borrower,
            _recipient
        );
    }

    // Scenarios: BLDEBT-REPAY-A03.
    function test_givenActionReportedKernelMismatch_whenRepaid_thenGetterIsNotRead(
        address payer_
    ) public {
        vm.mockCall(
            address(_debt),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0x1234))
        );
        vm.expectCall(address(_debt), abi.encodeWithSignature("kernel()"), uint64(0));
        test_givenPartialDebt_whenAnyPayerRepays_thenExactAccounting(payer_, 1);
    }

    // Scenarios: BLDEBT-REPAY-A03.
    function test_givenActionKernelGetterReverts_whenRepaid_thenGetterIsNotRead(
        address payer_
    ) public {
        vm.mockCallRevert(address(_debt), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        vm.expectCall(address(_debt), abi.encodeWithSignature("kernel()"), uint64(0));
        test_givenPartialDebt_whenAnyPayerRepays_thenExactAccounting(payer_, 1);
    }

    // Scenarios: BLDEBT-REPAY-L06, BLDEBT-REPAY-L07, BLDEBT-REPAY-L08, BLDEBT-REPAY-L09, BLDEBT-REPAY-L10, BLDEBT-REPAY-L11, BLDEBT-REPAY-L12, BLDEBT-REPAY-L13.
    function test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified(
        bool enabled_,
        bool coreActive_,
        bool coreEnabled_,
        address caller_,
        bool validInput_
    ) public {
        _setPolicyState(_debt, false, enabled_);
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _expectRepayRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_debt)
            ),
            validInput_ ? 1 : 0,
            _borrower,
            caller_
        );
    }

    // Scenarios: BLDEBT-REPAY-L02, BLDEBT-REPAY-L03, BLDEBT-REPAY-L04, BLDEBT-REPAY-L05.
    function test_givenDisabledDebtAction_whenCalled_thenPauseWins(
        bool coreActive_,
        bool coreEnabled_,
        address caller_,
        bool validInput_
    ) public {
        _debt.disable("");
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _expectRepayRevert(
            abi.encodeWithSelector(IEnabler.NotEnabled.selector),
            validInput_ ? 1 : 0,
            _borrower,
            caller_
        );
    }

    // Scenarios: BLDEBT-REPAY-D01, BLDEBT-REPAY-D02, BLDEBT-REPAY-D03.
    function test_givenCoreUnavailable_whenCalled_thenDependencyIdentified(
        bool active_,
        bool enabled_,
        address caller_,
        bool validInput_
    ) public {
        vm.assume(!active_ || !enabled_);
        _setPolicyState(_core, active_, enabled_);
        _expectRepayRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            ),
            validInput_ ? 1 : 0,
            _borrower,
            caller_
        );
    }

    function _replacePrincipal(uint128 principal_) internal {
        vm.prank(_borrower);
        _ohm.approve(address(_core), _PRINCIPAL);
        vm.prank(_borrower);
        _debt.repay(address(_asset), _PRINCIPAL, _borrower);
        _inventory.setGlobalDebtCap(type(uint128).max);
        _config.setAssetDebtCap(address(_asset), type(uint128).max);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), principal_, _borrower, _borrower, 0, address(0));
        vm.roll(block.number + 1);
    }

    // Scenarios: BLDEBT-REPAY-N01, BLDEBT-REPAY-A01.
    function test_givenAnyPrincipal_whenPartiallyRepaid_thenAggregatesAgree(
        uint128 principal_,
        uint128 amount_,
        address payer_
    ) public {
        // OZ OHM rejects the zero sender; its separate test proves that delivery failure.
        vm.assume(payer_ != address(0) && payer_ != address(_inventory));
        principal_ = uint128(bound(principal_, 2, type(uint128).max));
        amount_ = uint128(bound(amount_, 1, uint256(principal_) - 1));
        _replacePrincipal(principal_);
        _fundRepayer(payer_, amount_);
        uint256 balance = _ohm.balanceOf(payer_);
        bytes32 beforeQuote = _stateDigest(payer_);
        vm.prank(payer_);
        (uint128 quoted, uint256 quotedHealth) = _debt.previewRepay(
            address(_asset),
            amount_,
            _borrower
        );
        assertEq(_stateDigest(payer_), beforeQuote, "Partial repayment quote is read only");
        assertEq(quoted, principal_ - amount_, "Independent remaining principal");
        assertEq(quotedHealth, _HEALTH, "Exact mocked health");
        vm.expectEmit(address(_debt));
        emit IBurnerLoansDebt.Repaid(
            payer_,
            address(_asset),
            _borrower,
            amount_,
            principal_ - amount_
        );
        vm.prank(payer_);
        (uint128 remaining, uint256 health) = _debt.repay(address(_asset), amount_, _borrower);
        assertEq(remaining, principal_ - amount_, "Independent partial result");
        assertEq(health, _HEALTH, "Health returned unchanged");
        assertEq(_ohm.balanceOf(payer_), balance - amount_, "Actual payer supplies OHM");
        assertEq(_position().principalDue, remaining, "Position agrees with returned debt");
        assertEq(
            _floan.getMarketPrincipalDue(_core.marketId(address(_asset))),
            remaining,
            "Market agrees"
        );
        assertEq(_inventory.activePrincipalOhm(), remaining, "Inventory agrees");
        assertEq(_position().collateral, 2000e6, "Collateral unchanged");
        assertEq(
            _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
            1,
            "Partial repayment retains debt index"
        );
    }

    // Scenarios: BLDEBT-REPAY-N02, BLDEBT-REPAY-N07, BLDEBT-REPAY-A01.
    function test_givenAnyPrincipal_whenFullyRepaid_thenEpisodeAndFundingClear(
        uint128 principal_,
        address payer_
    ) public {
        // OZ OHM rejects the zero sender; its separate test proves that delivery failure.
        vm.assume(payer_ != address(0) && payer_ != address(_inventory));
        principal_ = uint128(bound(principal_, 1, type(uint128).max));
        _replacePrincipal(principal_);
        _fundRepayer(payer_, principal_);
        _mockRiskSnapshotFailure(abi.encodeWithSelector(PricingUnavailable.selector));
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encodeWithSelector(PricingUnavailable.selector)
        );
        bytes32 beforeQuote = _stateDigest(payer_);
        vm.prank(payer_);
        (uint128 q, uint256 h) = _debt.previewRepay(address(_asset), principal_, _borrower);
        assertEq(q, 0, "Full quote has no debt");
        assertEq(h, type(uint256).max, "Debt free health quote");
        assertEq(_stateDigest(payer_), beforeQuote, "Full quote is read only");
        uint256 balance = _ohm.balanceOf(payer_);
        vm.expectEmit(address(_debt));
        emit IBurnerLoansDebt.Repaid(payer_, address(_asset), _borrower, principal_, 0);
        vm.prank(payer_);
        (uint128 remaining, uint256 health) = _debt.repay(address(_asset), principal_, _borrower);
        assertEq(remaining, 0, "No debt remains");
        assertEq(health, type(uint256).max, "Debt free health");
        assertEq(_ohm.balanceOf(payer_), balance - principal_, "Payer supplies full principal");
        assertEq(_inventory.activePrincipalOhm(), 0, "Inventory reconciled");
        assertEq(
            _floan.getMarketPrincipalDue(_core.marketId(address(_asset))),
            0,
            "Market debt cleared"
        );
        assertEq(
            _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
            0,
            "Debt index cleared"
        );
        assertEq(_position().principalDue, 0, "Position debt cleared");
        assertEq(_position().maturity, 0, "Episode maturity cleared");
        assertEq(_position().collateral, 2000e6, "Collateral retained");
    }

    // Scenarios: BLDEBT-REPAY-N02, BLDEBT-REPAY-N07.
    function test_whenOneUnitFullRepayment_thenNoNarrowing() public {
        test_givenAnyPrincipal_whenFullyRepaid_thenEpisodeAndFundingClear(1, _recipient);
    }

    // Scenarios: BLDEBT-REPAY-N02, BLDEBT-REPAY-N07.
    function test_whenMaximumFullRepayment_thenNoNarrowing() public {
        test_givenAnyPrincipal_whenFullyRepaid_thenEpisodeAndFundingClear(
            type(uint128).max,
            _recipient
        );
    }

    // Scenarios: BLDEBT-REPAY-N01.
    function test_whenOneUnitPartialRepayment_thenNoNarrowing() public {
        test_givenAnyPrincipal_whenPartiallyRepaid_thenAggregatesAgree(
            type(uint128).max,
            1,
            _recipient
        );
    }

    // Scenarios: BLDEBT-REPAY-N01.
    function test_whenMaximumPartialRepayment_thenNoNarrowing() public {
        test_givenAnyPrincipal_whenPartiallyRepaid_thenAggregatesAgree(
            type(uint128).max,
            type(uint128).max - 1,
            _recipient
        );
    }

    // Scenarios: BLDEBT-REPAY-A01.
    function test_whenPayerIsZero_thenQuoteSucceedsAndTokenRejectsAllowance() public {
        vm.prank(address(0));
        (uint128 remaining, ) = _debt.previewRepay(address(_asset), 1, _borrower);
        assertEq(
            remaining,
            _PRINCIPAL - 1,
            "No borrower authorization requirement for zero caller"
        );
        bytes32 state = _stateDigest(address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(_core),
                uint256(0),
                uint256(1)
            )
        );
        vm.prank(address(0));
        _debt.repay(address(_asset), 1, _borrower);
        assertEq(_stateDigest(address(0)), state, "Token delivery failure restores all accounting");
    }

    // Scenarios: BLDEBT-REPAY-I06.
    function test_givenAnyDebt_whenRepaymentExceedsIt_thenExactLiveDebtError(
        uint128 principal_,
        uint128 amount_,
        address payer_
    ) public {
        principal_ = uint128(bound(principal_, 1, type(uint128).max - 1));
        amount_ = uint128(bound(amount_, uint256(principal_) + 1, type(uint128).max));
        _replacePrincipal(principal_);
        _expectRepayRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_RepayExceedsDebt.selector,
                uint256(amount_),
                uint256(principal_)
            ),
            amount_,
            _borrower,
            payer_
        );
    }

    // Scenarios: BLDEBT-REPAY-I06.
    function test_givenOneUnitDebt_whenRepaymentExceedsByOne_reverts() public {
        test_givenAnyDebt_whenRepaymentExceedsIt_thenExactLiveDebtError(1, 2, _recipient);
    }

    // Scenarios: BLDEBT-REPAY-I06.
    function test_givenNearMaximumDebt_whenMaximumRepaid_reverts() public {
        test_givenAnyDebt_whenRepaymentExceedsIt_thenExactLiveDebtError(
            type(uint128).max - 1,
            type(uint128).max,
            _recipient
        );
    }

    // Scenarios: BLDEBT-REPAY-A01.
    function test_whenPayerIsInventory_thenQuoteSucceedsAndExactReceiptRejectsSelfTransfer()
        public
    {
        _ohm.mint(address(_inventory), 1);
        vm.prank(address(_inventory));
        _ohm.approve(address(_core), 1);
        vm.prank(address(_inventory));
        (uint128 remaining, ) = _debt.previewRepay(address(_asset), 1, _borrower);
        assertEq(remaining, _PRINCIPAL - 1, "Inventory caller needs no borrower authorization");
        bytes32 state = _stateDigest(address(_inventory));
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(_ohm),
                address(_inventory),
                uint256(1),
                uint256(0)
            )
        );
        vm.prank(address(_inventory));
        _debt.repay(address(_asset), 1, _borrower);
        assertEq(_stateDigest(address(_inventory)), state, "Self transfer credits no repayment");
    }

    // Scenarios: BLDEBT-REPAY-L06, BLDEBT-REPAY-L07, BLDEBT-REPAY-L08, BLDEBT-REPAY-L09, BLDEBT-REPAY-L10, BLDEBT-REPAY-L11, BLDEBT-REPAY-L12, BLDEBT-REPAY-L13.
    function test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError() public {
        for (uint256 enabled; enabled < 2; ++enabled) {
            for (uint256 active; active < 2; ++active) {
                for (uint256 coreEnabled; coreEnabled < 2; ++coreEnabled) {
                    for (uint256 valid; valid < 2; ++valid) {
                        uint256 checkpoint = vm.snapshotState();
                        test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified(
                            enabled != 0,
                            active != 0,
                            coreEnabled != 0,
                            address(0xbeef),
                            valid != 0
                        );
                        assertTrue(
                            vm.revertToState(checkpoint),
                            "Restore subject and dependency state for each admission seed"
                        );
                    }
                }
            }
        }
    }

    // Scenarios: BLDEBT-REPAY-L02, BLDEBT-REPAY-L03, BLDEBT-REPAY-L04, BLDEBT-REPAY-L05.
    function test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError() public {
        for (uint256 active; active < 2; ++active) {
            for (uint256 coreEnabled; coreEnabled < 2; ++coreEnabled) {
                for (uint256 valid; valid < 2; ++valid) {
                    uint256 checkpoint = vm.snapshotState();
                    test_givenDisabledDebtAction_whenCalled_thenPauseWins(
                        active != 0,
                        coreEnabled != 0,
                        address(0xbeef),
                        valid != 0
                    );
                    assertTrue(
                        vm.revertToState(checkpoint),
                        "Restore subject and dependency state for each admission seed"
                    );
                }
            }
        }
    }

    // Scenarios: BLDEBT-REPAY-L01.
    function test_givenPolicyReactivated_whenRepayExecuted_thenSucceeds() public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_debt));
        _kernel.executeAction(Actions.ActivatePolicy, address(_debt));
        test_givenFullDebt_whenAnyPayerRepays_thenNoPricing(_recipient);
    }

    // Scenarios: BLDEBT-REPAY-L01.
    function test_givenReEnabled_whenRepayExecuted_thenSucceeds() public {
        _debt.disable("");
        _debt.reEnable();
        test_givenFullDebt_whenAnyPayerRepays_thenNoPricing(_recipient);
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, unsafe-typecast, unused-return)
