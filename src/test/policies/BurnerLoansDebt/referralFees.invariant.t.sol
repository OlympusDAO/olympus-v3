// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Policy} from "src/Kernel.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";
import {BurnerLoansReferralHandler} from "./fixtures/BurnerLoansReferralHandler.sol";

/// @notice Real borrow/top-up/extend with governance, optional-delivery and lifecycle drift.
/// @dev Fixed $1 prices and fixed clock; one 6-decimal collateral market, two referrers, principal
///      at most 1000 OHM, flat 1% fee and 125% backing. Payout's separate handler covers multiple
///      assets, rescue, keeper/seizure categories and full-width backing.
/// forge-config: default.invariant.fail-on-revert = true
contract BurnerLoansDebtReferralFeesInvariantTest is BurnerLoansModularTest {
    BurnerLoansReferralHandler internal _handler;
    uint256 internal _initialPayerBalance;

    function setUp() public override {
        super.setUp();
        _config.setAssetFeeConfig(address(_asset), IBurnerLoansRisk.AssetFeeConfig(100, 0, 0, 0));
        _config.setAssetRiskConfig(
            address(_asset),
            IBurnerLoansRisk.AssetRiskConfigInput(8500, 12500, 100, 1, 90 days, 1000e6)
        );
        _asset.mint(_borrower, 1e24);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 2000e6, _borrower);
        _initialPayerBalance = _asset.balanceOf(_borrower);
        _handler = new BurnerLoansReferralHandler(
            BurnerLoansReferralHandler.Services({
                kernel: _kernel,
                core: _core,
                debt: _debt,
                risk: _risk,
                payout: _payout,
                lens: _lens,
                asset: _asset,
                borrower: _borrower,
                governance: address(this)
            })
        );
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_handler));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, _handler.BLA());
        _risk.setConfigOperator(_handler.OPERATOR());
        assertFalse(
            _roles.hasRole(_handler.OPERATOR(), ADMIN_ROLE),
            "Selected operator has no ADMIN role"
        );
        assertFalse(
            _roles.hasRole(_handler.OPERATOR(), BURNER_LOANS_ADMIN_ROLE),
            "Selected operator has no BLA role"
        );

        // Guarantee lending, deferred/fixed rewards, removal, authority failures and recovery
        // before the random campaign; these calls use actual production entry points.
        _handler.setShare(2500, false);
        _handler.setAllowed(0, true, false);
        _handler.setAllowed(1, true, true);
        _handler.setDeliveryBlocked(0, true);
        _handler.borrow(0);
        _handler.borrow(1);
        _handler.extend(0);
        _handler.setShare(10000, true);
        _handler.setAllowed(0, false, true);
        _handler.borrow(0);
        _handler.retry(0, address(0xCA11));
        _handler.setDeliveryBlocked(0, false);
        _handler.retry(0, address(0xCA11));
        _handler.setActive(0, false);
        _handler.borrow(1);
        _handler.setShare(1, true);
        _handler.setActive(0, true);
        _handler.setEnabled(0, false);
        _handler.extend(1);
        _handler.restoreServices();
        _handler.setEnabled(1, false);
        _handler.borrow(1);
        _handler.setActive(2, false);
        _handler.retry(1, address(0xCA11));
        _handler.setEnabled(3, false);
        _handler.borrow(1);
        _handler.restoreServices();
        _handler.setShare(0, false);
        _handler.borrow(1);
        _handler.unauthorizedShare(10000, true);
        _handler.unauthorizedShare(1, false);
        _handler.unauthorizedMembership(0, true, true);
        _handler.unauthorizedMembership(1, false, false);
        _handler.unauthorizedBorrow();
        assertEq(_handler.successfulBorrows(), 3, "Seeded fresh borrow and top-ups execute");
        assertEq(_handler.successfulExtensions(), 1, "Seeded real extension executes");
        assertGt(_handler.rejectedCalls(), 0, "Seeded unauthorized and unavailable calls reject");

        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = _handler.borrow.selector;
        selectors[1] = _handler.extend.selector;
        selectors[2] = _handler.setShare.selector;
        selectors[3] = _handler.setAllowed.selector;
        selectors[4] = _handler.unauthorizedShare.selector;
        selectors[5] = _handler.unauthorizedMembership.selector;
        selectors[6] = _handler.unauthorizedBorrow.selector;
        selectors[7] = _handler.setDeliveryBlocked.selector;
        selectors[8] = _handler.retry.selector;
        selectors[9] = _handler.setActive.selector;
        selectors[10] = _handler.setEnabled.selector;
        selectors[11] = _handler.restoreServices.selector;
        targetSelector(FuzzSelector(address(_handler), selectors));
        targetContract(address(_handler));
    }

    // Scenarios: BLCUTRY-P22.
    function invariant_referralReceiptsAndFixedFeesConserved() public view {
        uint256 pendingTotal;
        uint256 earnedTotal;
        address[] memory indexedRecipients = _payout.getPendingReferralRecipients(address(_asset));
        for (uint256 i; i < 2; ++i) {
            address recipient = _handler.recipients(i);
            uint256 pending = _handler.pending(i);
            uint256 earned = _handler.earned(i);
            assertEq(
                earned,
                _handler.paid(i) + pending,
                "Every fixed referral credit is paid or still reserved"
            );
            assertEq(
                _asset.balanceOf(recipient),
                _handler.paid(i),
                "Real token payments match fixed original recipient"
            );
            assertEq(
                _payout.pendingReferralFee(address(_asset), recipient),
                pending,
                "Raw referral bucket matches independent model"
            );
            assertEq(
                _payout.pendingRecipientAmount(address(_asset), recipient),
                pending,
                "Retry getter exposes original reward despite whitelist changes"
            );
            assertEq(
                _risk.isReferrerAllowed(recipient),
                _handler.allowed(i),
                "Only successful authorized membership writes change state"
            );
            bool present;
            for (uint256 j; j < indexedRecipients.length; ++j) {
                if (indexedRecipients[j] == recipient) present = true;
            }
            assertEq(
                present,
                pending != 0,
                "Referral index exists exactly while fixed liability remains"
            );
            pendingTotal += pending;
            earnedTotal += earned;
        }
        assertEq(
            _handler.gross(),
            _handler.protocolPaid() + earnedTotal,
            "Each gross receipt splits into protocol and referral allocations"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            _handler.protocolPaid(),
            "Protocol receives only its independently modelled residual"
        );
        assertEq(
            _initialPayerBalance - _asset.balanceOf(_borrower),
            _handler.gross(),
            "Actual payer funds exact cumulative gross receipts"
        );
        (uint256 fees, , uint256 seized, , uint256 total) = _payout.pendingAmounts(address(_asset));
        assertEq(fees, 0, "Protocol route remains payable in this campaign");
        assertEq(seized, 0, "No seizure action in this campaign");
        assertEq(total, pendingTotal, "Aggregate reserve includes every fixed referral liability");
        assertEq(
            _asset.balanceOf(address(_payout)),
            pendingTotal,
            "Every earned unpaid reward remains exactly funded"
        );
        assertEq(_asset.balanceOf(address(_core)), 0, "Core never retains fee custody");
        address[] memory tokens = _payout.getPendingPayoutTokens();
        assertEq(
            tokens.length,
            pendingTotal == 0 ? 0 : 1,
            "Pending token index follows live liabilities"
        );
        if (tokens.length != 0)
            assertEq(tokens[0], address(_asset), "Only campaign collateral token is indexed");
        assertEq(
            _risk.referralFeeBps(),
            _handler.bps(),
            "Only successful authorized share changes update setting"
        );
        IBurnerLoansCore.Position memory position = _lens.getPosition(address(_asset), _borrower);
        assertEq(
            position.debtOhm,
            _handler.principalUnits() * 1e9,
            "Real canonical debt matches accepted principal increments"
        );
        assertEq(
            position.maturity,
            _handler.maturity(),
            "Only accepted extensions advance canonical maturity"
        );
        assertEq(
            position.depositedCollateral,
            2000e6,
            "Lending and configuration never consume deposited collateral"
        );
        address[4] memory policies = [
            address(_risk),
            address(_core),
            address(_payout),
            address(_debt)
        ];
        for (uint256 i; i < 4; ++i) {
            assertEq(
                _kernel.isPolicyActive(Policy(policies[i])),
                _handler.active(i),
                "Kernel lifecycle matches selected independent transition"
            );
            assertEq(
                IEnabler(policies[i]).isEnabled(),
                _handler.enabled(i),
                "Local pause/recovery is independent of Kernel membership"
            );
        }
    }
}
