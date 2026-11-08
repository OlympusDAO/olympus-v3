// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions, Policy} from "src/Kernel.sol";
import {BurnerLoansConfigTimelock} from "src/policies/burnerloans/BurnerLoansConfigTimelock.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";
import {MockOlympusBackingOracle} from "src/test/mocks/MockOlympusBackingOracle.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

/// @dev Real modular deployment; expected commitments are encoded independently of queue internals.
abstract contract BurnerLoansConfigTimelockTest is BurnerLoansModularTest {
    BurnerLoansConfigTimelock internal _timelock;
    bytes32 internal _beforeQueue;
    uint64 internal _next;

    function setUp() public virtual override {
        super.setUp();
        _timelock = new BurnerLoansConfigTimelock(_kernel, _config);
        _kernel.executeAction(Actions.ActivatePolicy, address(_timelock));
        _config.setConfigOperator(address(_timelock));
        _timelock.enable("");
        _rolesAdmin.grantRole(EMERGENCY_ROLE, address(this));
    }

    function _setState(Policy policy_, bool active_, bool enabled_) internal {
        if (!enabled_) IEnabler(address(policy_)).disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(policy_));
    }

    function _proposer(address caller_, uint8 role_) internal {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        role_ = uint8(bound(role_, 0, 2));
        if (role_ != 1) _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (role_ != 0) _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
    }

    function _outsider(address caller_) internal view {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        vm.assume(!_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE));
    }

    function _riskInput() internal pure returns (IBurnerLoansRisk.AssetRiskConfigInput memory) {
        return IBurnerLoansRisk.AssetRiskConfigInput(7500, 11000, 200, 14 days, 120 days, 500e6);
    }

    function _fees() internal pure returns (IBurnerLoansRisk.AssetFeeConfig memory) {
        return IBurnerLoansRisk.AssetFeeConfig(100, 5000, 200, 300);
    }

    function _riskFields(
        IBurnerLoansCore.AssetConfig memory c_
    ) internal pure returns (IBurnerLoansRisk.AssetRiskConfigInput memory) {
        return
            IBurnerLoansRisk.AssetRiskConfigInput(
                c_.maxLtvBps,
                c_.backingMultiplierBps,
                c_.keeperRewardBps,
                c_.termLength,
                c_.maxMaturityHorizon,
                c_.maxKeeperReward
            );
    }

    function _capAction(
        address asset_,
        uint128 cap_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            ITimelockBatchQueue.BatchAction(
                address(_config),
                IBurnerLoansConfig.setAssetDebtCap.selector,
                abi.encode(asset_, cap_)
            );
    }

    function _riskAction(
        address asset_,
        IBurnerLoansRisk.AssetRiskConfigInput memory c_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            ITimelockBatchQueue.BatchAction(
                address(_config),
                IBurnerLoansConfig.setAssetRiskConfig.selector,
                abi.encode(asset_, c_)
            );
    }

    function _feeAction(
        address asset_,
        IBurnerLoansRisk.AssetFeeConfig memory c_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            ITimelockBatchQueue.BatchAction(
                address(_config),
                IBurnerLoansConfig.setAssetFeeConfig.selector,
                abi.encode(asset_, c_)
            );
    }

    function _sharesAction(
        address asset_,
        bool shares_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            ITimelockBatchQueue.BatchAction(
                address(_config),
                IBurnerLoansConfig.setAssetWithdrawAsShares.selector,
                abi.encode(asset_, shares_)
            );
    }

    function _originationsAction(
        address asset_,
        bool enabled_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            ITimelockBatchQueue.BatchAction(
                address(_config),
                IBurnerLoansConfig.setAssetOriginationsEnabled.selector,
                abi.encode(asset_, enabled_)
            );
    }

    function _ageAction(
        uint48 age_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            ITimelockBatchQueue.BatchAction(
                _core.risk(),
                IBurnerLoansRisk.setPriceCacheMaxAge.selector,
                abi.encode(age_)
            );
    }

    function _rescueAction(
        address token_,
        address destination_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            ITimelockBatchQueue.BatchAction(
                address(_config),
                IBurnerLoansConfig.rescue.selector,
                abi.encode(token_, destination_)
            );
    }

    function _single(
        ITimelockBatchQueue.BatchAction memory a_
    ) internal pure returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = a_;
    }

    function _pair(
        ITimelockBatchQueue.BatchAction memory a_,
        ITimelockBatchQueue.BatchAction memory b_
    ) internal pure returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = a_;
        actions[1] = b_;
    }

    function _key(ITimelockBatchQueue.BatchAction memory a_) internal pure returns (bytes32) {
        bytes32 local = a_.selector == IBurnerLoansRisk.setPriceCacheMaxAge.selector
            ? keccak256(abi.encode(a_.selector))
            : keccak256(abi.encode(a_.selector, abi.decode(a_.payload, (address))));
        return keccak256(abi.encode(a_.target, local));
    }

    function _hash(ITimelockBatchQueue.BatchAction memory a_) internal view returns (bytes32) {
        if (a_.selector == IBurnerLoansRisk.setPriceCacheMaxAge.selector)
            return
                keccak256(
                    abi.encode(
                        address(_core),
                        _core.risk(),
                        IBurnerLoansRisk(_core.risk()).priceCacheMaxAge()
                    )
                );
        if (a_.selector == IBurnerLoansConfig.rescue.selector)
            return
                keccak256(
                    abi.encode(address(_core), _core.configOperator(), _config.configOperator())
                );
        address asset = abi.decode(a_.payload, (address));
        if (a_.selector == IBurnerLoansConfig.setAssetFeeConfig.selector)
            return
                keccak256(
                    abi.encode(
                        address(_core),
                        asset,
                        _config.getAssetFeeConfig(asset),
                        _config.configOperator()
                    )
                );
        IBurnerLoansCore.AssetConfig memory c = _config.getAssetConfig(asset);
        if (a_.selector == IBurnerLoansConfig.setAssetRiskConfig.selector)
            return
                keccak256(
                    abi.encode(address(_core), asset, _riskFields(c), _config.configOperator())
                );
        if (a_.selector == IBurnerLoansConfig.setAssetDebtCap.selector)
            return
                keccak256(abi.encode(address(_core), asset, c.debtCap, _config.configOperator()));
        if (a_.selector == IBurnerLoansConfig.setAssetOriginationsEnabled.selector)
            return
                keccak256(
                    abi.encode(
                        address(_core),
                        asset,
                        c.originationsEnabled,
                        _config.configOperator()
                    )
                );
        return
            keccak256(
                abi.encode(address(_core), asset, c.withdrawAsShares, _config.configOperator())
            );
    }

    function _economicDigest() internal view returns (bytes32) {
        uint32 market = _core.marketId(address(_asset));
        return
            keccak256(
                abi.encode(
                    _floan.getMarket(market),
                    _floan.getMarketConfigData(market),
                    _inventory.activePrincipalOhm(),
                    _inventory.suppliedOhm(),
                    _ohm.totalSupply(),
                    _ohm.balanceOf(address(_inventory)),
                    _asset.balanceOf(address(_core)),
                    _asset.balanceOf(address(_payout)),
                    _asset.balanceOf(_borrower),
                    _asset.balanceOf(_recipient),
                    IBurnerLoansRisk(_core.risk()).priceCacheMaxAge()
                )
            );
    }

    function _queueDigest(uint64 id_) internal view returns (bytes32 digest) {
        ITimelockBatchQueue.QueuedAction memory q = _timelock.getQueuedAction(id_);
        digest = keccak256(abi.encode(q));
        for (uint256 i; i < q.actions.length; ++i) {
            (bytes32 key, bytes32 h) = _timelock.getQueuedConfigState(id_, i, 0);
            digest = keccak256(
                abi.encode(
                    digest,
                    _timelock.getQueuedConfigDestination(id_, i),
                    key,
                    h,
                    _timelock.pendingActionId(key)
                )
            );
        }
    }

    function _expectQueue(
        ITimelockBatchQueue.BatchAction[] memory actions_,
        address caller_
    ) internal {
        _next = _timelock.nextActionId();
        _beforeQueue = _economicDigest();
        for (uint256 i; i < actions_.length; ++i) {
            vm.expectEmit(address(_timelock));
            emit IConfigTimelockBatchQueue.ConfigStateQueued(
                _next,
                i,
                _key(actions_[i]),
                0,
                actions_[i].target,
                _hash(actions_[i])
            );
        }
        for (uint256 i; i < actions_.length; ++i) {
            vm.expectEmit(address(_timelock));
            emit ITimelockBatchQueue.TimelockSubActionQueued(
                _next,
                actions_[i].target,
                actions_[i].selector,
                i,
                keccak256(actions_[i].payload)
            );
        }
        vm.expectEmit(address(_timelock));
        emit ITimelockBatchQueue.TimelockActionQueued(
            _next,
            caller_,
            keccak256(abi.encode(actions_)),
            uint48(vm.getBlockTimestamp() + 1 days),
            uint48(vm.getBlockTimestamp() + 4 days)
        );
    }

    function _assertQueued(
        uint64 id_,
        ITimelockBatchQueue.BatchAction[] memory actions_,
        address caller_
    ) internal view {
        assertEq(id_, _next, "Return reserved ID");
        ITimelockBatchQueue.QueuedAction memory q = _timelock.getQueuedAction(id_);
        assertEq(q.proposer, caller_, "Exact proposer");
        assertEq(q.queuedAt, vm.getBlockTimestamp(), "Queue timestamp");
        assertEq(q.executableAt, vm.getBlockTimestamp() + 1 days, "One-day delay");
        assertEq(q.expiresAt, vm.getBlockTimestamp() + 4 days, "Three-day window");
        assertFalse(q.executed || q.cancelled, "New action pending");
        assertEq(abi.encode(q.actions), abi.encode(actions_), "Exact ordered payloads");
        assertEq(_timelock.getQueuedActionLength(id_), actions_.length, "Length getter");
        for (uint256 i; i < actions_.length; ++i) {
            (address target, bytes4 selector, bytes memory payload) = _timelock.getQueuedSubAction(
                id_,
                i
            );
            assertEq(
                abi.encode(target, selector, payload),
                abi.encode(actions_[i].target, actions_[i].selector, actions_[i].payload),
                "Subaction getter agrees"
            );
            assertEq(
                _timelock.getQueuedConfigDestination(id_, i),
                actions_[i].target,
                "Concrete destination"
            );
            assertEq(_timelock.getQueuedConfigStateCount(id_, i), 1, "One commitment");
            (bytes32 key, bytes32 h) = _timelock.getQueuedConfigState(id_, i, 0);
            assertEq(key, _key(actions_[i]), "Independent selector/asset key");
            assertEq(h, _hash(actions_[i]), "Complete pre-state commitment");
            assertEq(_timelock.pendingActionId(key), id_, "Action owns key");
        }
        assertEq(_timelock.nextActionId(), uint256(id_) + 1, "One ID consumed");
        assertEq(_economicDigest(), _beforeQueue, "Queue changes no target or accounting");
    }

    function _expectRejectedQueue(bytes memory reason_) internal {
        _next = _timelock.nextActionId();
        _beforeQueue = _economicDigest();
        vm.expectRevert(reason_);
    }

    function _assertRejectedQueue(ITimelockBatchQueue.BatchAction[] memory actions_) internal view {
        assertEq(_timelock.nextActionId(), _next, "Rejected queue consumes no ID");
        assertEq(_economicDigest(), _beforeQueue, "Rejected queue preserves accounting");
        for (uint256 i; i < actions_.length; ++i) {
            assertEq(_timelock.getQueuedConfigStateCount(_next, i), 0, "No partial commitment");
            assertEq(
                _timelock.getQueuedConfigDestination(_next, i),
                address(0),
                "No partial destination"
            );
        }
    }

    function _makeReady(uint64 id_) internal {
        vm.warp(_timelock.getQueuedAction(id_).executableAt);
    }

    function _assertCleared(
        uint64 id_,
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) internal view {
        assertEq(_timelock.getQueuedAction(id_).actions.length, 0, "Terminal payloads cleared");
        for (uint256 i; i < actions_.length; ++i) {
            assertEq(_timelock.pendingActionId(_key(actions_[i])), 0, "Key released");
            assertEq(_timelock.getQueuedConfigStateCount(id_, i), 0, "Commitment cleared");
            assertEq(
                _timelock.getQueuedConfigDestination(id_, i),
                address(0),
                "Destination cleared"
            );
        }
    }

    function _executeReverts(uint64 id_, address caller_, bytes memory reason_) internal {
        bytes32 queue = _queueDigest(id_);
        bytes32 funds = _economicDigest();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _timelock.executeQueuedAction(id_);
        assertEq(
            _queueDigest(id_),
            queue,
            "Failed execution preserves guards, owners and payloads"
        );
        assertEq(_economicDigest(), funds, "Failed batch rolls back all writes and transfers");
    }

    function _stateChanged(
        uint64 id_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory a_,
        bytes32 expected_
    ) internal view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                id_,
                index_,
                _key(a_),
                expected_,
                _hash(a_)
            );
    }

    function _pending(
        ITimelockBatchQueue.BatchAction memory a_,
        uint64 owner_
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _key(a_),
                owner_
            );
    }

    function _invalid(
        ITimelockBatchQueue.BatchAction memory a_
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                a_.target,
                a_.selector
            );
    }

    function _executeAndAssert(uint64 id_, address executor_) internal {
        ITimelockBatchQueue.BatchAction[] memory actions = _timelock.getQueuedAction(id_).actions;
        bytes32[] memory expectedMarkets = new bytes32[](actions.length);
        for (uint256 i; i < actions.length; ++i) {
            if (
                actions[i].selector != IBurnerLoansRisk.setPriceCacheMaxAge.selector &&
                actions[i].selector != IBurnerLoansConfig.rescue.selector
            )
                expectedMarkets[i] = _expectedMarket(
                    actions,
                    abi.decode(actions[i].payload, (address))
                );
        }
        bytes32 accounting = _principalDigest();
        for (uint256 i; i < actions.length; ++i) {
            _expectSetterEvent(actions[i]);
            vm.expectEmit(address(_timelock));
            emit ITimelockBatchQueue.TimelockSubActionExecuted(
                id_,
                actions[i].target,
                actions[i].selector,
                i
            );
        }
        vm.expectEmit(address(_timelock));
        emit ITimelockBatchQueue.TimelockActionExecuted(id_, executor_);
        vm.prank(executor_);
        _timelock.executeQueuedAction(id_);
        assertTrue(_timelock.getQueuedAction(id_).executed, "Executed marker retained");
        _assertCleared(id_, actions);
        assertEq(
            _principalDigest(),
            accounting,
            "Configuration changes no custody, principal, interest or provider claims"
        );
        for (uint256 i; i < actions.length; ++i) {
            if (actions[i].selector == IBurnerLoansRisk.setPriceCacheMaxAge.selector)
                assertEq(
                    IBurnerLoansRisk(actions[i].target).priceCacheMaxAge(),
                    abi.decode(actions[i].payload, (uint48)),
                    "Exact Risk age"
                );
            if (expectedMarkets[i] != bytes32(0)) {
                address asset = abi.decode(actions[i].payload, (address));
                assertEq(
                    keccak256(
                        abi.encode(_config.getAssetConfig(asset), _config.getAssetFeeConfig(asset))
                    ),
                    expectedMarkets[i],
                    "Complete resulting market; unrelated fields preserved"
                );
            }
        }
    }

    function _independentActions(
        ITimelockBatchQueue.BatchAction memory a_,
        ITimelockBatchQueue.BatchAction memory b_,
        address caller_
    ) internal {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 order; order < 2; ++order) {
            _expectQueue(_single(a_), caller_);
            vm.prank(caller_);
            uint64 first = _timelock.queueBatch(_single(a_));
            _assertQueued(first, _single(a_), caller_);
            bytes32 original = _queueDigest(first);
            _expectQueue(_single(b_), caller_);
            vm.prank(caller_);
            uint64 second = _timelock.queueBatch(_single(b_));
            _assertQueued(second, _single(b_), caller_);
            assertEq(_queueDigest(first), original, "Second proposal preserves first action");
            _makeReady(first);
            _executeAndAssert(order == 0 ? first : second, caller_);
            _executeAndAssert(order == 0 ? second : first, caller_);
            assertTrue(vm.revertToState(checkpoint), "Restore independent execution order");
        }
    }

    function _vaultAsset() internal returns (address token, address vault) {
        MockERC20 collateral = new MockERC20("Vault collateral", "VC", 6);
        MockERC4626 receipt = new MockERC4626(OZERC20(address(collateral)), "Vault", "V");
        token = address(collateral);
        vault = address(receipt);
        _price.setPrice(token, 1e18);
        _depositManager.addAsset(IERC20(token), IERC4626(vault), type(uint256).max, 0);
        _depositManager.addAssetPeriod(IERC20(token), 1, address(_core));
        _config.addAsset(token, 100000e9, _riskInput(), _fees(), false);
    }

    function _supportedActions()
        internal
        view
        returns (ITimelockBatchQueue.BatchAction[] memory a)
    {
        a = new ITimelockBatchQueue.BatchAction[](6);
        a[0] = _capAction(address(_asset), 200000e9);
        a[1] = _originationsAction(address(_asset), false);
        a[2] = _riskAction(address(_asset), _riskInput());
        a[3] = _sharesAction(address(_asset), false);
        a[4] = _feeAction(address(_asset), _fees());
        a[5] = _rescueAction(address(_asset), _recipient);
    }

    function _alternative(
        ITimelockBatchQueue.BatchAction memory a_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory b) {
        b = ITimelockBatchQueue.BatchAction(a_.target, a_.selector, bytes.concat(a_.payload));
        if (a_.selector == IBurnerLoansConfig.setAssetDebtCap.selector)
            b.payload = abi.encode(address(_asset), uint128(300000e9));
        else if (
            a_.selector == IBurnerLoansConfig.setAssetOriginationsEnabled.selector ||
            a_.selector == IBurnerLoansConfig.setAssetWithdrawAsShares.selector
        ) b.payload = abi.encode(address(_asset), true);
        else if (a_.selector == IBurnerLoansConfig.setAssetRiskConfig.selector)
            b.payload = abi.encode(
                address(_asset),
                _riskFields(_config.getAssetConfig(address(_asset)))
            );
        else b.payload = abi.encode(address(_asset), _config.getAssetFeeConfig(address(_asset)));
    }

    function _batchPair(
        ITimelockBatchQueue.BatchAction memory a_,
        ITimelockBatchQueue.BatchAction memory b_,
        address caller_
    ) internal {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 order; order < 2; ++order) {
            ITimelockBatchQueue.BatchAction[] memory batch = order == 0
                ? _pair(a_, b_)
                : _pair(b_, a_);
            _expectQueue(batch, caller_);
            vm.prank(caller_);
            uint64 id = _timelock.queueBatch(batch);
            _assertQueued(id, batch, caller_);
            _makeReady(id);
            _executeAndAssert(id, caller_);
            assertTrue(vm.revertToState(checkpoint), "Restore independent batch order");
        }
    }

    function _openDebt() internal {
        _supplyInventory(_borrower, 1000e9);
        vm.startPrank(_borrower);
        _collateral.depositCollateral(address(_asset), 2000e6, _borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 100e6, address(0));
        vm.stopPrank();
    }

    /// @dev Arbitrary uint128 debt cannot be economically funded; isolate the authoritative FLOAN read.
    function _mockDebt(uint128 debt_) internal {
        vm.mockCall(
            address(_floan),
            abi.encodeWithSignature(
                "getMarketPrincipalDue(uint32)",
                _core.marketId(address(_asset))
            ),
            abi.encode(debt_)
        );
    }

    function _replaceRisk(uint48 age_) internal returns (BurnerLoansRisk replacement) {
        replacement = new BurnerLoansRisk(
            _kernel,
            IERC20(address(_ohm)),
            address(new MockOlympusBackingOracle(1e18)),
            address(0),
            age_,
            address(_core)
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        replacement.enable("");
        replacement.setConfigOperator(address(_config));
        _core.setRisk(address(replacement));
        replacement.setConfigOperator(address(_timelock));
    }

    function _assertNoTargetLogs(Vm.Log[] memory logs_, address target_) internal pure {
        for (uint256 i; i < logs_.length; ++i)
            assertTrue(logs_[i].emitter != target_, "No event from unchanged target");
    }

    function _lifecycleDigest() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _timelock.isEnabled(),
                    _timelock.lastTransitionAt(),
                    _timelock.gracePeriod(),
                    _timelock.nextActionId(),
                    _economicDigest()
                )
            );
    }

    function _transitionReverts(
        bytes memory call_,
        address caller_,
        bytes memory reason_
    ) internal {
        bytes32 beforeState = _lifecycleDigest();
        vm.prank(caller_);
        (bool ok, bytes memory result) = address(_timelock).call(call_);
        assertFalse(ok, "Transition must revert");
        assertEq(result, reason_, "Exact lifecycle error");
        assertEq(
            _lifecycleDigest(),
            beforeState,
            "Rejected lifecycle call preserves history and accounting"
        );
    }

    function _admin(address caller_) internal {
        vm.assume(caller_ != address(0));
        if (!_roles.hasRole(caller_, ADMIN_ROLE)) _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
    }

    function _pauseCaller(address caller_, uint8 role_) internal {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        role_ = uint8(bound(role_, 0, 2));
        if (role_ != 1) _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (role_ != 0) _rolesAdmin.grantRole(EMERGENCY_ROLE, caller_);
    }

    function _nonempty(bytes memory data_) internal pure returns (bytes memory) {
        if (data_.length == 0) return hex"00";
        if (data_.length > 256) {
            assembly ("memory-safe") {
                mstore(data_, 256)
            }
        }
        return data_;
    }

    function _expectTransition(address caller_, bool enabled_, bytes memory data_) internal {
        vm.expectEmit(address(_timelock));
        if (enabled_) emit IEnabler.Enabled();
        else emit IEnabler.Disabled();
        vm.expectEmit(address(_timelock));
        emit IEnablerV2.Transition(caller_, enabled_, data_, uint48(vm.getBlockTimestamp()));
    }

    function _cancelReverts(uint64 id_, address caller_, bytes memory reason_) internal {
        bytes32 queue = _queueDigest(id_);
        bytes32 funds = _economicDigest();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _timelock.cancelQueuedAction(id_);
        assertEq(_queueDigest(id_), queue, "Rejected cancellation preserves queue");
        assertEq(_economicDigest(), funds, "Rejected cancellation preserves accounting");
    }

    function _cancelAndAssert(uint64 id_, address caller_) internal {
        ITimelockBatchQueue.BatchAction[] memory actions = _timelock.getQueuedAction(id_).actions;
        bytes32 funds = _economicDigest();
        vm.expectEmit(address(_timelock));
        emit ITimelockBatchQueue.TimelockActionCancelled(id_, caller_);
        vm.prank(caller_);
        _timelock.cancelQueuedAction(id_);
        assertTrue(_timelock.getQueuedAction(id_).cancelled, "Cancellation marker retained");
        _assertCleared(id_, actions);
        assertEq(_economicDigest(), funds, "Cancellation changes no target or balance");
    }

    function _useVaultAsset() internal {
        (address token, ) = _vaultAsset();
        _asset = MockERC20(token);
    }

    function _mutableVaultAsset()
        internal
        returns (address token, MockERC7540ExternalShareVault vault)
    {
        MockERC20 collateral = new MockERC20("Capability collateral", "CC", 18);
        token = address(collateral);
        vault = new MockERC7540ExternalShareVault(OZERC20(token), false, false, true);
        _price.setPrice(token, 1e18);
        _depositManager.addAsset(IERC20(token), IERC4626(address(vault)), type(uint256).max, 0);
        _depositManager.addAssetPeriod(IERC20(token), 1, address(_core));
        _config.addAsset(token, 100000e9, _riskInput(), _fees(), false);
    }

    function _restore(uint256 checkpoint_) internal {
        assertTrue(vm.revertToState(checkpoint_), "Restore independent scenario seed");
        vm.clearMockedCalls();
    }

    function _principalDigest() internal view returns (bytes32) {
        uint32 market = _core.marketId(address(_asset));
        return
            keccak256(
                abi.encode(
                    _floan.getMarketPrincipalDue(market),
                    _floan.getMarketInterestDue(market),
                    _floan.getMarketCollateral(market),
                    _inventory.activePrincipalOhm(),
                    _inventory.suppliedOhm(),
                    _ohm.totalSupply(),
                    _ohm.balanceOf(address(_inventory)),
                    _asset.balanceOf(address(_payout)),
                    _asset.balanceOf(_borrower)
                )
            );
    }

    function _expectedMarket(
        ITimelockBatchQueue.BatchAction[] memory actions_,
        address asset_
    ) internal view returns (bytes32) {
        IBurnerLoansCore.AssetConfig memory c = _config.getAssetConfig(asset_);
        IBurnerLoansRisk.AssetFeeConfig memory f = _config.getAssetFeeConfig(asset_);
        for (uint256 i; i < actions_.length; ++i) {
            ITimelockBatchQueue.BatchAction memory a = actions_[i];
            if (
                a.target != address(_config) ||
                a.selector == IBurnerLoansConfig.rescue.selector ||
                abi.decode(a.payload, (address)) != asset_
            ) continue;
            if (a.selector == IBurnerLoansConfig.setAssetDebtCap.selector)
                (, c.debtCap) = abi.decode(a.payload, (address, uint128));
            else if (a.selector == IBurnerLoansConfig.setAssetOriginationsEnabled.selector)
                (, c.originationsEnabled) = abi.decode(a.payload, (address, bool));
            else if (a.selector == IBurnerLoansConfig.setAssetWithdrawAsShares.selector)
                (, c.withdrawAsShares) = abi.decode(a.payload, (address, bool));
            else if (a.selector == IBurnerLoansConfig.setAssetFeeConfig.selector)
                (, f) = abi.decode(a.payload, (address, IBurnerLoansRisk.AssetFeeConfig));
            else {
                (, IBurnerLoansRisk.AssetRiskConfigInput memory r) = abi.decode(
                    a.payload,
                    (address, IBurnerLoansRisk.AssetRiskConfigInput)
                );
                c.maxLtvBps = r.maxLtvBps;
                c.backingMultiplierBps = r.backingMultiplierBps;
                c.keeperRewardBps = r.keeperRewardBps;
                c.termLength = r.termLength;
                c.maxMaturityHorizon = r.maxMaturityHorizon;
                c.maxKeeperReward = r.maxKeeperReward;
            }
        }
        return keccak256(abi.encode(c, f));
    }

    function _expectSetterEvent(ITimelockBatchQueue.BatchAction memory a_) internal {
        if (a_.selector == IBurnerLoansRisk.setPriceCacheMaxAge.selector) {
            uint48 age = abi.decode(a_.payload, (uint48));
            if (age != IBurnerLoansRisk(a_.target).priceCacheMaxAge()) {
                vm.expectEmit(a_.target);
                emit IBurnerLoansRisk.PriceCacheMaxAgeSet(age);
            }
            return;
        }
        address asset = abi.decode(a_.payload, (address));
        if (a_.selector == IBurnerLoansConfig.rescue.selector) {
            (, address destination) = abi.decode(a_.payload, (address, address));
            uint256 amount = IERC20(asset).balanceOf(address(_core));
            if (amount != 0) {
                vm.expectEmit(address(_core));
                emit IBurnerLoansCore.AssetRescued(asset, destination, amount);
            }
            return;
        }
        IBurnerLoansCore.AssetConfig memory c = _config.getAssetConfig(asset);
        if (a_.selector == IBurnerLoansConfig.setAssetDebtCap.selector) {
            (, uint128 cap) = abi.decode(a_.payload, (address, uint128));
            if (cap != c.debtCap) {
                vm.expectEmit(a_.target);
                emit IBurnerLoansConfig.AssetDebtCapSet(asset, cap);
            }
        } else if (a_.selector == IBurnerLoansConfig.setAssetRiskConfig.selector) {
            (, IBurnerLoansRisk.AssetRiskConfigInput memory risk) = abi.decode(
                a_.payload,
                (address, IBurnerLoansRisk.AssetRiskConfigInput)
            );
            if (keccak256(abi.encode(risk)) != keccak256(abi.encode(_riskFields(c)))) {
                vm.expectEmit(a_.target);
                emit IBurnerLoansConfig.AssetRiskConfigSet(asset, risk);
            }
        } else if (a_.selector == IBurnerLoansConfig.setAssetFeeConfig.selector) {
            (, IBurnerLoansRisk.AssetFeeConfig memory fees) = abi.decode(
                a_.payload,
                (address, IBurnerLoansRisk.AssetFeeConfig)
            );
            if (
                keccak256(abi.encode(fees)) !=
                keccak256(abi.encode(_config.getAssetFeeConfig(asset)))
            ) {
                vm.expectEmit(a_.target);
                emit IBurnerLoansConfig.AssetFeeConfigSet(asset, fees);
            }
        } else {
            (, bool value) = abi.decode(a_.payload, (address, bool));
            if (a_.selector == IBurnerLoansConfig.setAssetOriginationsEnabled.selector) {
                if (value != c.originationsEnabled) {
                    vm.expectEmit(a_.target);
                    emit IBurnerLoansConfig.AssetOriginationsSet(asset, value);
                }
            } else if (value != c.withdrawAsShares) {
                vm.expectEmit(a_.target);
                emit IBurnerLoansConfig.AssetWithdrawAsSharesSet(asset, value);
            }
        }
    }

    function _assertNoTargetWrites(address target_) internal {
        (, bytes32[] memory writes) = vm.accesses(target_);
        assertEq(writes.length, 0, "No storage write for unchanged target configuration");
    }
}
