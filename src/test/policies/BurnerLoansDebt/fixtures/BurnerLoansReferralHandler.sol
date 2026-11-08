// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {BurnerLoansCore} from "src/policies/burnerloans/BurnerLoansCore.sol";
import {BurnerLoansDebt} from "src/policies/burnerloans/BurnerLoansDebt.sol";
import {BurnerLoansLens} from "src/policies/burnerloans/BurnerLoansLens.sol";
import {BurnerLoansPayout} from "src/policies/burnerloans/BurnerLoansPayout.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

/// @dev Real lending at fixed prices/time: one 6-decimal collateral asset, two referrers,
///      1-OHM principal increments, a flat 1% curve and 125% backing. The bounded principal
///      is at most 1000 OHM; unit tests separately establish full-width arithmetic.
contract BurnerLoansReferralHandler is Test {
    struct Services {
        Kernel kernel;
        BurnerLoansCore core;
        BurnerLoansDebt debt;
        BurnerLoansRisk risk;
        BurnerLoansPayout payout;
        BurnerLoansLens lens;
        MockERC20 asset;
        address borrower;
        address governance;
    }

    Services internal _services;
    address internal constant _STRANGER = address(0xBADCA11);
    address public constant OPERATOR = address(0xC0F1A);
    address public constant BLA = address(0xB1A);
    address[2] public recipients = [address(0xFEED01), address(0xFEED02)];
    // Policy order: Risk, Core, Payout, Debt. Every lifecycle dimension is independent.
    bool[4] public active = [true, true, true, true];
    bool[4] public enabled = [true, true, true, true];
    bool[2] public allowed;
    bool[2] public blocked;
    uint256[2] public earned;
    uint256[2] public paid;
    uint256[2] public pending;
    uint256 public gross;
    uint256 public protocolPaid;
    uint256 public principalUnits;
    uint48 public maturity;
    uint16 public bps;
    uint256 public successfulBorrows;
    uint256 public successfulExtensions;
    uint256 public rejectedCalls;

    constructor(Services memory services_) {
        _services = services_;
    }

    function borrow(uint8 attribution_) external {
        if (principalUnits == 1000) return;
        address referrer = _referrer(attribution_);
        bytes memory failure = _actionFailure(referrer);
        if (failure.length != 0) {
            bytes32 beforeState = _stateDigest();
            vm.expectRevert(failure);
            vm.prank(_services.borrower);
            _services.debt.borrow(
                address(_services.asset),
                1e9,
                _services.borrower,
                _services.borrower,
                12500,
                referrer
            );
            assertEq(
                _stateDigest(),
                beforeState,
                "Rejected borrow preserves lending, fees and funded rewards"
            );
            ++rejectedCalls;
            return;
        }
        // 1 OHM * 125% backing = 1.25e6 raw collateral; 1%=12500 raw units.
        (uint256 protocolFee, uint256 referralFee) = _allocation(12500, referrer);
        IBurnerLoansDebt.BorrowPreview memory quote = _services.debt.previewBorrow(
            address(_services.asset),
            1e9,
            _services.borrower,
            _services.borrower,
            12500,
            referrer
        );
        vm.prank(_services.borrower);
        IBurnerLoansDebt.BorrowPreview memory result = _services.debt.borrow(
            address(_services.asset),
            1e9,
            _services.borrower,
            _services.borrower,
            12500,
            referrer
        );
        assertEq(quote.fee, 12500, "Independent flat-curve borrow quote");
        assertEq(result.fee, 12500, "Independent flat-curve borrow receipt");
        if (principalUnits == 0) maturity = uint48(vm.getBlockTimestamp() + 1);
        ++principalUnits;
        ++successfulBorrows;
        _recordCredit(12500, protocolFee, referralFee, referrer);
    }

    function extend(uint8 attribution_) external {
        if (principalUnits == 0) return;
        address referrer = _referrer(attribution_);
        uint256 fee = principalUnits * 12500;
        bytes memory failure = _actionFailure(referrer);
        if (failure.length != 0) {
            bytes32 beforeState = _stateDigest();
            vm.expectRevert(failure);
            vm.prank(_services.borrower);
            _services.debt.extend(address(_services.asset), _services.borrower, 1, fee, referrer);
            assertEq(
                _stateDigest(),
                beforeState,
                "Rejected extension preserves maturity and funded rewards"
            );
            ++rejectedCalls;
            return;
        }
        (uint256 protocolFee, uint256 referralFee) = _allocation(fee, referrer);
        IBurnerLoansDebt.ExtendPreview memory quote = _services.debt.previewExtend(
            address(_services.asset),
            _services.borrower,
            1,
            fee,
            referrer
        );
        vm.prank(_services.borrower);
        IBurnerLoansDebt.ExtendPreview memory result = _services.debt.extend(
            address(_services.asset),
            _services.borrower,
            1,
            fee,
            referrer
        );
        assertEq(quote.fee, fee, "Extension quote charges every current OHM at the flat fee");
        assertEq(result.fee, fee, "Extension collects independently modelled gross fee");
        ++maturity;
        ++successfulExtensions;
        _recordCredit(fee, protocolFee, referralFee, referrer);
    }

    function setShare(uint16 share_, bool operator_) external {
        address caller = operator_ ? OPERATOR : address(this);
        uint16 share = uint16(bound(share_, 0, 10000));
        bytes memory failure = _riskFailure();
        if (failure.length != 0) {
            bytes32 beforeState = _stateDigest();
            vm.expectRevert(failure);
            vm.prank(caller);
            _services.risk.setReferralFeeBps(share);
            assertEq(_stateDigest(), beforeState, "Unavailable Risk cannot change percentage");
            ++rejectedCalls;
            return;
        }
        vm.prank(caller);
        _services.risk.setReferralFeeBps(share);
        bps = share;
    }

    function setAllowed(uint8 recipient_, bool allowed_, bool operator_) external {
        address caller = operator_ ? OPERATOR : address(this);
        uint256 k = bound(recipient_, 0, 1);
        bytes memory failure = _riskFailure();
        if (failure.length != 0) {
            bytes32 beforeState = _stateDigest();
            vm.expectRevert(failure);
            vm.prank(caller);
            _services.risk.setReferrerAllowed(recipients[k], allowed_);
            assertEq(_stateDigest(), beforeState, "Unavailable Risk cannot change membership");
            ++rejectedCalls;
            return;
        }
        vm.prank(caller);
        _services.risk.setReferrerAllowed(recipients[k], allowed_);
        allowed[k] = allowed_;
    }

    function unauthorizedShare(uint16 share_, bool bla_) external {
        uint16 share = uint16(bound(share_, 0, 10000));
        bytes memory failure = _riskFailure();
        if (failure.length == 0)
            failure = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(failure);
        vm.prank(bla_ ? BLA : _STRANGER);
        _services.risk.setReferralFeeBps(share);
        assertEq(
            _stateDigest(),
            beforeState,
            "Unauthorized share change cannot mutate settings or rewards"
        );
        ++rejectedCalls;
    }

    function unauthorizedMembership(uint8 recipient_, bool allowed_, bool bla_) external {
        address recipient = recipients[bound(recipient_, 0, 1)];
        bytes memory failure = _riskFailure();
        if (failure.length == 0)
            failure = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(failure);
        vm.prank(bla_ ? BLA : _STRANGER);
        _services.risk.setReferrerAllowed(recipient, allowed_);
        assertEq(
            _stateDigest(),
            beforeState,
            "Unauthorized whitelist change cannot mutate settings or rewards"
        );
        ++rejectedCalls;
    }

    function unauthorizedBorrow() external {
        bytes memory failure = _localActionFailure();
        if (failure.length == 0)
            failure = abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector
            );
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(failure);
        vm.prank(_STRANGER);
        _services.debt.borrow(
            address(_services.asset),
            1e9,
            _services.borrower,
            _STRANGER,
            12500,
            address(0)
        );
        assertEq(
            _stateDigest(),
            beforeState,
            "Unauthorized caller cannot incur debt or earn a referral"
        );
        ++rejectedCalls;
    }

    function setDeliveryBlocked(uint8 recipient_, bool blocked_) external {
        blocked[bound(recipient_, 0, 1)] = blocked_;
        vm.clearMockedCalls();
        for (uint256 i; i < 2; ++i) {
            if (blocked[i])
                vm.mockCall(
                    address(_services.asset),
                    abi.encodeWithSelector(_services.asset.transfer.selector, recipients[i]),
                    abi.encode(false)
                );
        }
    }

    function retry(uint8 recipient_, address caller_) external {
        uint256 k = bound(recipient_, 0, 1);
        if (!active[2]) {
            bytes32 beforeState = _stateDigest();
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                    address(_services.payout)
                )
            );
            vm.prank(caller_);
            _services.payout.transferPendingPayout(address(_services.asset), recipients[k]);
            assertEq(
                _stateDigest(),
                beforeState,
                "Inactive Payout cannot consume an earned reward"
            );
            ++rejectedCalls;
            return;
        }
        uint256 expected = blocked[k] ? 0 : pending[k];
        vm.prank(caller_);
        uint256 actual = _services.payout.transferPendingPayout(
            address(_services.asset),
            recipients[k]
        );
        assertEq(actual, expected, "Permissionless retry pays only fixed backed entitlement");
        paid[k] += expected;
        pending[k] -= expected;
    }

    function setActive(uint8 policy_, bool active_) public {
        uint256 p = bound(policy_, 0, 3);
        if (active[p] == active_) return;
        vm.prank(_services.governance);
        _services.kernel.executeAction(
            active_ ? Actions.ActivatePolicy : Actions.DeactivatePolicy,
            _policy(p)
        );
        active[p] = active_;
    }

    function setEnabled(uint8 policy_, bool enabled_) public {
        uint256 p = bound(policy_, 0, 3);
        if (enabled[p] == enabled_) return;
        if (enabled_) {
            if (!active[p]) return;
            if (p == 1 && (!active[0] || !enabled[0] || !active[2] || !enabled[2])) return;
            if (p == 3 && (!active[1] || !enabled[1])) return;
            IEnabler(_policy(p)).enable("");
        } else IEnabler(_policy(p)).disable("");
        enabled[p] = enabled_;
    }

    function restoreServices() external {
        for (uint8 i; i < 4; ++i) setActive(i, true);
        setEnabled(0, true);
        setEnabled(2, true);
        setEnabled(1, true);
        setEnabled(3, true);
    }

    function _policy(uint256 p_) internal view returns (address) {
        if (p_ == 0) return address(_services.risk);
        if (p_ == 1) return address(_services.core);
        if (p_ == 2) return address(_services.payout);
        return address(_services.debt);
    }

    function _referrer(uint8 attribution_) internal view returns (address) {
        uint256 choice = bound(attribution_, 0, 2);
        return choice == 2 ? address(0) : recipients[choice];
    }

    function _allocation(
        uint256 fee_,
        address referrer_
    ) internal view returns (uint256 protocol, uint256 referral) {
        if (referrer_ != address(0)) referral = (fee_ * bps) / 10000;
        protocol = fee_ - referral;
    }

    function _recordCredit(
        uint256 fee_,
        uint256 protocol_,
        uint256 referral_,
        address referrer_
    ) internal {
        gross += fee_;
        protocolPaid += protocol_;
        if (referral_ == 0) return;
        uint256 k = referrer_ == recipients[0] ? 0 : 1;
        earned[k] += referral_;
        pending[k] += referral_;
        if (!blocked[k]) {
            paid[k] += pending[k];
            pending[k] = 0;
        }
    }

    function _localActionFailure() internal view returns (bytes memory) {
        if (!active[3])
            return
                abi.encodeWithSelector(
                    IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                    address(_services.debt)
                );
        if (!enabled[3]) return abi.encodeWithSelector(IEnabler.NotEnabled.selector);
        if (!active[1] || !enabled[1])
            return
                abi.encodeWithSelector(
                    PolicyDependency.PolicyDependency_NotActive.selector,
                    address(_services.core)
                );
        return bytes("");
    }

    function _riskFailure() internal view returns (bytes memory) {
        if (!active[0])
            return
                abi.encodeWithSelector(
                    IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                    address(_services.risk)
                );
        if (!enabled[0]) return abi.encodeWithSelector(IEnabler.NotEnabled.selector);
        return bytes("");
    }

    function _actionFailure(address referrer_) internal view returns (bytes memory) {
        bytes memory failure = _localActionFailure();
        if (failure.length != 0) return failure;
        failure = _riskFailure();
        if (failure.length != 0) return failure;
        if (referrer_ != address(0)) {
            uint256 k = referrer_ == recipients[0] ? 0 : 1;
            if (!allowed[k])
                return
                    abi.encodeWithSelector(
                        IBurnerLoansRisk.BurnerLoansRisk_ReferrerNotAllowed.selector,
                        referrer_
                    );
        }
        if (!active[2] || !enabled[2])
            return
                abi.encodeWithSelector(
                    PolicyDependency.PolicyDependency_NotActive.selector,
                    address(_services.payout)
                );
        return bytes("");
    }

    function _stateDigest() internal view returns (bytes32) {
        bytes32 lending = keccak256(
            abi.encode(
                _services.lens.getPosition(address(_services.asset), _services.borrower),
                _services.core.totalActiveDebtOhm(),
                _services.asset.balanceOf(_services.borrower),
                _services.asset.allowance(_services.borrower, address(_services.core))
            )
        );
        (uint256 fees, , uint256 seized, , uint256 total) = _services.payout.pendingAmounts(
            address(_services.asset)
        );
        bytes32 payout = keccak256(
            abi.encode(
                fees,
                seized,
                total,
                _services.payout.getPendingPayoutTokens(),
                _services.payout.getPendingReferralRecipients(address(_services.asset)),
                _services.asset.balanceOf(address(_services.payout)),
                _services.asset.balanceOf(_services.payout.treasury())
            )
        );
        bytes32 referrals = keccak256(
            abi.encode(
                _services.risk.referralFeeBps(),
                _services.risk.isReferrerAllowed(recipients[0]),
                _services.risk.isReferrerAllowed(recipients[1]),
                _services.payout.pendingReferralFee(address(_services.asset), recipients[0]),
                _services.payout.pendingReferralFee(address(_services.asset), recipients[1]),
                _services.asset.balanceOf(recipients[0]),
                _services.asset.balanceOf(recipients[1])
            )
        );
        return keccak256(abi.encode(lending, payout, referrals));
    }
}
