// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";
import {Actions} from "src/Kernel.sol";

/// @dev Four independent domains: age, shared BPS, membership of two fixed referrers.
contract BurnerLoansRiskConfigTimelockExecuteInvariantTest is BurnerLoansRiskConfigTimelockTest {
    uint64[4] internal _owners;
    uint256[4] internal _values;
    uint256[4] internal _beforeValues;
    uint256[4] internal _intents;
    bool internal _queueActive = true;
    bool internal _riskActive = true;
    bool internal _queueEnabled = true;
    bool internal _riskEnabled = true;
    address internal _selectedOperator;
    address internal _blaProposer;
    address internal _adminProposer;

    function setUp() public override {
        super.setUp();
        _selectedOperator = address(_timelock);
        _blaProposer = makeAddr("Invariant BLA proposer");
        _adminProposer = makeAddr("Invariant ADMIN proposer");
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, _blaProposer);
        _rolesAdmin.grantRole(ADMIN_ROLE, _adminProposer);
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, address(this));
        _values[0] = _risk.priceCacheMaxAge();
        // A funded fixed-owner reward must survive every governance/queue sequence.
        _asset.mint(address(_payout), 40);
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSelector(IERC20.transfer.selector, _recipient, uint256(40)),
            hex"deadbeef"
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_asset), 0, _recipient, 40);
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = this.actionQueue.selector;
        selectors[1] = this.actionExecute.selector;
        selectors[2] = this.actionCancel.selector;
        selectors[3] = this.actionDirectSetting.selector;
        selectors[4] = this.actionOperator.selector;
        selectors[5] = this.actionPause.selector;
        selectors[6] = this.actionMembership.selector;
        selectors[7] = this.actionTime.selector;
        targetSelector(FuzzSelector(address(this), selectors));
        targetContract(address(this));
    }

    function _action(
        uint256 domain_,
        uint256 value_
    ) private view returns (ITimelockBatchQueue.BatchAction memory) {
        if (domain_ == 0) return _ageAction(uint48(value_));
        if (domain_ == 1) return _bpsAction(uint16(value_));
        return _referrerAction(domain_ == 2 ? _recipient : _borrower, value_ == 1);
    }

    function _boundedValue(uint256 domain_, uint48 value_) private pure returns (uint256) {
        if (domain_ == 0) return value_;
        if (domain_ == 1) return uint256(value_) % 10001;
        return uint256(value_) % 2;
    }

    function _ready() private view returns (bool) {
        return
            _queueActive &&
            _queueEnabled &&
            _riskActive &&
            _riskEnabled &&
            _selectedOperator == address(_timelock);
    }

    function actionQueue(uint8 domain_, uint48 value_, uint8 role_) public {
        uint256 domain = bound(domain_, 0, 3);
        uint256 value = _boundedValue(domain, value_);
        ITimelockBatchQueue.BatchAction[] memory a = _single(_action(domain, value));
        bool expected = _ready() && _owners[domain] == 0;
        uint256 role = bound(role_, 0, 2);
        vm.prank(role == 0 ? address(this) : role == 1 ? _blaProposer : _adminProposer);
        (bool ok, bytes memory data) = address(_timelock).call(
            abi.encodeCall(_timelock.queueBatch, (a))
        );
        assertEq(ok, expected, "queue admission agrees with independent model");
        if (ok) {
            _owners[domain] = abi.decode(data, (uint64));
            _beforeValues[domain] = _values[domain];
            _intents[domain] = value;
        }
    }

    function actionExecute(uint8 domain_, address caller_) public {
        uint256 domain = bound(domain_, 0, 3);
        uint64 id = _owners[domain];
        bool expected;
        if (id != 0) {
            ITimelockBatchQueue.QueuedAction memory a = _timelock.getQueuedAction(id);
            expected =
                _ready() &&
                _values[domain] == _beforeValues[domain] &&
                vm.getBlockTimestamp() >= a.executableAt &&
                vm.getBlockTimestamp() <= a.expiresAt;
        }
        vm.prank(caller_);
        (bool ok, ) = address(_timelock).call(
            abi.encodeCall(ITimelockBatchQueue.executeQueuedAction, (id))
        );
        assertEq(ok, expected, "execution readiness/current-state commitment agrees with model");
        if (ok) {
            _values[domain] = _intents[domain];
            _owners[domain] = 0;
            assertTrue(_timelock.getQueuedAction(id).executed, "terminal execution recorded");
            (bool repeated, ) = address(_timelock).call(
                abi.encodeCall(ITimelockBatchQueue.executeQueuedAction, (id))
            );
            assertFalse(repeated, "executed intent cannot replay");
        }
    }

    function actionCancel(uint8 domain_) public {
        uint256 domain = bound(domain_, 0, 3);
        uint64 id = _owners[domain];
        (bool ok, ) = address(_timelock).call(
            abi.encodeCall(ITimelockBatchQueue.cancelQueuedAction, (id))
        );
        assertEq(
            ok,
            _queueActive && id != 0,
            "cancellation depends only on own activity and valid pending intent"
        );
        if (ok) {
            _owners[domain] = 0;
            assertTrue(_timelock.getQueuedAction(id).cancelled, "terminal cancellation recorded");
            (bool repeated, ) = address(_timelock).call(
                abi.encodeCall(ITimelockBatchQueue.cancelQueuedAction, (id))
            );
            assertFalse(repeated, "cancelled intent cannot replay");
        }
    }

    function actionDirectSetting(uint8 domain_, uint48 value_) public {
        uint256 domain = bound(domain_, 0, 3);
        uint256 value = _boundedValue(domain, value_);
        ITimelockBatchQueue.BatchAction memory a = _action(domain, value);
        (bool ok, ) = address(_risk).call(abi.encodePacked(a.selector, a.payload));
        assertEq(ok, _riskActive && _riskEnabled, "direct ADMIN mutation respects Risk lifecycle");
        if (ok) _values[domain] = value;
    }

    function actionOperator(bool selected_) public {
        address candidate = selected_ ? address(_timelock) : _recipient;
        (bool ok, ) = address(_risk).call(
            abi.encodeWithSignature("setConfigOperator(address)", candidate)
        );
        assertEq(ok, _riskActive && candidate != _selectedOperator, "operator change admission");
        if (ok) _selectedOperator = candidate;
    }

    function actionPause(bool risk_, bool enabled_) public {
        address target = risk_ ? address(_risk) : address(_timelock);
        bool current = risk_ ? _riskEnabled : _queueEnabled;
        bool ready = risk_
            ? _riskActive
            : (_queueActive && _riskActive && _selectedOperator == address(_timelock));
        bool expected = current != enabled_ && (!enabled_ || ready);
        (bool ok, ) = target.call(
            abi.encodeWithSignature(enabled_ ? "enable(bytes)" : "disable(bytes)", bytes(""))
        );
        assertEq(ok, expected, "lifecycle transition matches model");
        if (ok) {
            if (risk_) _riskEnabled = enabled_;
            else _queueEnabled = enabled_;
        }
    }

    function actionMembership(bool risk_, bool active_) public {
        bool current = risk_ ? _riskActive : _queueActive;
        if (current != active_) {
            _kernel.executeAction(
                active_ ? Actions.ActivatePolicy : Actions.DeactivatePolicy,
                risk_ ? address(_risk) : address(_timelock)
            );
            if (risk_) _riskActive = active_;
            else _queueActive = active_;
        }
    }

    function actionTime(uint32 elapsed_) public {
        vm.warp(vm.getBlockTimestamp() + bound(elapsed_, 0, 8 days));
    }

    // Scenarios: BLRCT-EXECUTE-P09, BLRISK-REFERRAL-BPS-P01, BLRISK-REFERRAL-BPS-P02, BLRISK-REFERRER-P02, BLRISK-REFERRER-P05.
    function invariant_pendingKeysAndSettingsMatchIndependentModel() public view {
        for (uint256 i; i < 4; ++i) {
            assertEq(
                _timelock.pendingActionId(_key(_action(i, 0))),
                _owners[i],
                "exact pending domain owner"
            );
            if (_owners[i] != 0) {
                ITimelockBatchQueue.QueuedAction memory a = _timelock.getQueuedAction(_owners[i]);
                assertFalse(a.executed || a.cancelled, "live owner references pending action");
                assertEq(a.actions[0].target, address(_risk), "immutable target");
            }
        }
        assertEq(_risk.priceCacheMaxAge(), _values[0], "model cache age");
        assertEq(_risk.referralFeeBps(), _values[1], "model referral percentage");
        assertEq(_risk.isReferrerAllowed(_recipient), _values[2] == 1, "model first membership");
        assertEq(_risk.isReferrerAllowed(_borrower), _values[3] == 1, "model second membership");
        assertEq(_risk.configOperator(), _selectedOperator, "model operator");
        assertEq(
            _payout.pendingReferralFee(address(_asset), _recipient),
            40,
            "governance never reprices earned reward"
        );
        assertEq(_asset.balanceOf(address(_payout)), 40, "reward backing preserved");
        assertEq(
            _floan.getMarketPrincipalDue(_core.marketId(address(_asset))),
            0,
            "settings never write principal"
        );
    }
}
