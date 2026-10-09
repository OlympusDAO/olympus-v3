pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {IBurnerLoansRescue} from "src/policies/interfaces/IBurnerLoansRescue.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {ReentrantPayoutToken} from "src/test/mocks/ReentrantPayoutToken.sol";
import {BurnerLoansSurplusRescueTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansSurplusRescueTest.sol";

// Queue requests use fixed quantities; only the permissionless executor is fuzzed on success.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unused-return,unsafe-typecast)
contract BurnerLoansConfigTimelockQueueRescueTest is BurnerLoansSurplusRescueTestBase {
    uint256 internal constant _ADDITIONAL_CUSTODY = 7;
    uint256 internal constant _INCREASED_SURPLUS = _SURPLUS_AMOUNT + _ADDITIONAL_CUSTODY;
    uint256 internal constant _INCREASED_REWARD = _REWARD_AMOUNT + _SURPLUS_AMOUNT;

    ReentrantPayoutToken internal _asset;

    function setUp() public override {
        super.setUp();
        _setDefaultConfigOperator();
        _enableConfigTimelock();
        _asset = _createFixedRescueToken(_ALL_BUCKETS);
        _asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
    }

    // Scenarios: L-01, L-02, L-09, P-01, P-04, P-05, P-06, P-07, P-08, P-09, P-10.
    function test_givenBucketSubset_whenEachRoleQueuesAndExecutorExecutes(
        uint8 bucketMask_,
        bool facilityDisabled_,
        address executor_
    ) public {
        _caseQueuedBuckets(
            uint8(bound(bucketMask_, 0, _ALL_BUCKETS)),
            facilityDisabled_,
            executor_
        );
    }

    // Scenarios: L-01, L-02, L-09, P-01, P-04, P-05, P-06, P-07, P-08, P-09, P-10.
    function test_givenBucketSubsets_whenLocalStatesAreSeeded() public {
        for (uint8 mask; mask <= _ALL_BUCKETS; ++mask)
            for (uint256 disabled; disabled < 2; ++disabled) {
                uint256 snapshot = vm.snapshotState();
                _caseQueuedBuckets(mask, disabled != 0, address(0));
                assertTrue(vm.revertToState(snapshot), "restore queued bucket/local state seed");
            }
    }

    function _caseQueuedBuckets(uint8 mask_, bool facilityDisabled_, address executor_) internal {
        ReentrantPayoutToken asset = _createFixedRescueToken(mask_);
        asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
        asset.mint(_destination, 3);
        if (facilityDisabled_) {
            vm.prank(admin);
            burnerLoans.disable("");
        }
        bytes32 unrelatedBefore = _surplusAccountingHash(address(_asset));
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            uint64 id = _assertSurplusQueued(asset, _destination, callers[c]);
            _executeVerifiedSurplus(id, asset, _destination, _SURPLUS_AMOUNT, executor_);
            assertEq(
                _surplusAccountingHash(address(_asset)),
                unrelatedBefore,
                "queued payment preserves unrelated raw liabilities/indexes"
            );
            assertEq(
                _asset.balanceOf(address(burnerLoans)),
                _FULL_CUSTODY,
                "queued payment preserves unrelated custody"
            );
            assertTrue(vm.revertToState(snapshot), "restore queued proposer class");
        }
    }

    // Scenarios: P-02, P-03.
    function test_givenNoSurplus_whenQueuedExecutionCompletes() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 populated; populated < 2; ++populated)
            for (uint256 below; below < (populated == 0 ? 1 : 2); ++below)
                for (uint256 c; c < callers.length; ++c) {
                    uint256 snapshot = vm.snapshotState();
                    ReentrantPayoutToken asset = _createFixedRescueToken(
                        populated == 0 ? 0 : _ALL_BUCKETS
                    );
                    if (below != 0) asset.burn(address(burnerLoans), 1);
                    uint64 id = _assertSurplusQueued(asset, _destination, callers[c]);
                    _executeVerifiedSurplus(id, asset, _destination, 0, address(this));
                    assertTrue(vm.revertToState(snapshot), "restore queued no-op state");
                }
    }

    // Scenarios: L-03.
    function test_givenValidTimelock_whenUnauthorizedCallerQueues_reverts(address caller_) public {
        vm.assume(caller_ != admin && caller_ != burnerLoansAdmin);
        bytes memory failure = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        _assertSurplusQueueFailure(_asset, address(_asset), _destination, caller_, failure);
        _assertSurplusQueueFailure(_asset, address(0), address(0), caller_, failure);
    }

    // Scenarios: L-03.
    function test_givenUnauthorizedIdentities_whenQueueing_reverts() public {
        address[4] memory callers = [address(0), emergency, _keeper, address(configTimelock)];
        for (uint256 c; c < callers.length; ++c)
            test_givenValidTimelock_whenUnauthorizedCallerQueues_reverts(callers[c]);
    }

    // Scenarios: L-04.
    function test_givenTimelockDisabled_whenRescueQueued_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            configTimelock.disable("");
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(IEnabler.NotEnabled.selector);
            _assertSurplusQueueFailure(_asset, address(_asset), _destination, callers[c], failure);
            _assertSurplusQueueFailure(_asset, address(0), address(0), callers[c], failure);
            assertTrue(vm.revertToState(snapshot), "restore independent queue gate");
        }
    }

    // Scenarios: L-05.
    function test_givenTimelockInactive_whenRescueQueued_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_PolicyInactive.selector,
                address(configTimelock)
            );
            _assertSurplusQueueFailure(_asset, address(_asset), _destination, callers[c], failure);
            _assertSurplusQueueFailure(_asset, address(0), address(0), callers[c], failure);
            assertTrue(vm.revertToState(snapshot), "restore independent queue gate");
        }
    }

    // Scenarios: L-08.
    function test_givenConfigDisabled_whenRescueQueued_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            burnerLoansConfig.disable("");
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(IEnabler.NotEnabled.selector);
            _assertSurplusQueueFailure(_asset, address(_asset), _destination, callers[c], failure);
            _assertSurplusQueueFailure(_asset, address(0), address(0), callers[c], failure);
            assertTrue(vm.revertToState(snapshot), "restore independent queue gate");
        }
    }

    // Scenarios: L-06.
    function test_givenConfigInactive_whenRescueQueued_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoansConfig));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_PolicyInactive.selector,
                address(burnerLoansConfig)
            );
            _assertSurplusQueueFailure(_asset, address(_asset), _destination, callers[c], failure);
            _assertSurplusQueueFailure(_asset, address(0), address(0), callers[c], failure);
            assertTrue(vm.revertToState(snapshot), "restore independent queue gate");
        }
    }

    // Scenarios: L-07.
    function test_givenOperatorRemoved_whenRescueQueued_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            burnerLoansConfig.setConfigOperator(address(0));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                address(configTimelock)
            );
            _assertSurplusQueueFailure(_asset, address(_asset), _destination, callers[c], failure);
            _assertSurplusQueueFailure(_asset, address(0), address(0), callers[c], failure);
            assertTrue(vm.revertToState(snapshot), "restore independent queue gate");
        }
    }

    // Scenarios: BLCT-E12.
    function test_givenQueuedRescue_whenTimelockDisabled_reverts() public {
        uint256 snapshot = vm.snapshotState();
        uint64 id = _assertSurplusQueued(_asset, _destination, admin);
        vm.startPrank(admin);
        configTimelock.disable("");
        vm.stopPrank();
        bytes memory failure = abi.encodeWithSelector(IEnabler.NotEnabled.selector);
        _assertSurplusExecutionFailure(id, _asset, _destination, failure);
        assertTrue(vm.revertToState(snapshot), "restore execution gate");
    }

    // Scenarios: L-05.
    function test_givenQueuedRescue_whenTimelockInactive_reverts() public {
        uint256 snapshot = vm.snapshotState();
        uint64 id = _assertSurplusQueued(_asset, _destination, admin);
        vm.startPrank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
        vm.stopPrank();
        bytes memory failure = abi.encodeWithSelector(
            IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_PolicyInactive.selector,
            address(configTimelock)
        );
        _assertSurplusExecutionFailure(id, _asset, _destination, failure);
        assertTrue(vm.revertToState(snapshot), "restore execution gate");
    }

    // Scenarios: L-08.
    function test_givenQueuedRescue_whenConfigDisabled_reverts() public {
        uint256 snapshot = vm.snapshotState();
        uint64 id = _assertSurplusQueued(_asset, _destination, admin);
        vm.startPrank(admin);
        burnerLoansConfig.disable("");
        vm.stopPrank();
        bytes memory failure = abi.encodeWithSelector(IEnabler.NotEnabled.selector);
        _assertSurplusExecutionFailure(id, _asset, _destination, failure);
        assertTrue(vm.revertToState(snapshot), "restore execution gate");
    }

    // Scenarios: L-06.
    function test_givenQueuedRescue_whenConfigInactive_reverts() public {
        uint256 snapshot = vm.snapshotState();
        uint64 id = _assertSurplusQueued(_asset, _destination, admin);
        vm.startPrank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoansConfig));
        vm.stopPrank();
        bytes memory failure = abi.encodeWithSelector(
            IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_PolicyInactive.selector,
            address(burnerLoansConfig)
        );
        _assertSurplusExecutionFailure(id, _asset, _destination, failure);
        assertTrue(vm.revertToState(snapshot), "restore execution gate");
    }

    // Scenarios: L-10.
    function test_givenFacilityInactive_whenRescueQueued_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 disabledBL; disabledBL < 2; ++disabledBL)
            for (uint256 c; c < callers.length; ++c) {
                uint256 snapshot = vm.snapshotState();
                vm.startPrank(admin);
                if (disabledBL != 0) burnerLoans.disable("");
                kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
                vm.stopPrank();
                bytes memory failure = abi.encodeWithSelector(
                    IBurnerLoans.BurnerLoans_PolicyInactive.selector
                );
                _assertSurplusQueueFailure(
                    _asset,
                    address(_asset),
                    _destination,
                    callers[c],
                    failure
                );
                // Policy activity is checked before inputs, in both typed and batch queue paths.
                _assertSurplusQueueFailure(_asset, address(0), address(0), callers[c], failure);
                assertTrue(vm.revertToState(snapshot), "restore inactive queue fixture");
            }
    }

    // Scenarios: LIVE-04.
    // The request is valid when queued; deactivation during the delay blocks execution only.
    function test_givenQueuedRescue_whenFacilityBecomesInactive_revertsThenRetries() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 disabledBL; disabledBL < 2; ++disabledBL)
            for (uint256 c; c < callers.length; ++c) {
                uint256 snapshot = vm.snapshotState();
                if (disabledBL != 0) {
                    vm.prank(admin);
                    burnerLoans.disable("");
                }
                uint64 id = _assertSurplusQueued(_asset, _destination, callers[c]);
                vm.prank(admin);
                kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
                _assertSurplusExecutionFailure(
                    id,
                    _asset,
                    _destination,
                    abi.encodeWithSelector(IBurnerLoans.BurnerLoans_PolicyInactive.selector)
                );
                vm.prank(admin);
                kernel.executeAction(Actions.ActivatePolicy, address(burnerLoans));
                _executeVerifiedSurplus(id, _asset, _destination, _SURPLUS_AMOUNT, address(this));
                assertTrue(vm.revertToState(snapshot), "restore deactivation during delay");
            }
    }

    // Scenarios: I-01.
    function test_whenAssetHasNoCode_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 c; c < callers.length; ++c) {
            address[2] memory invalidAssets = [address(0), makeAddr("BLCT no-code rescue token")];
            for (uint256 a; a < invalidAssets.length; ++a)
                _assertSurplusQueueFailure(
                    _asset,
                    invalidAssets[a],
                    _destination,
                    callers[c],
                    abi.encodeWithSelector(
                        IBurnerLoansRescue.BurnerLoans_InvalidAsset.selector,
                        invalidAssets[a]
                    )
                );
        }
    }

    // Scenarios: I-02.
    function test_whenDestinationIsForbidden_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 c; c < callers.length; ++c) {
            address[_SURPLUS_AMOUNT] memory forbidden = [
                address(0),
                address(burnerLoans),
                address(_asset),
                address(burnerLoansConfig),
                address(kernel)
            ];
            for (uint256 d; d < forbidden.length; ++d)
                _assertSurplusQueueFailure(
                    _asset,
                    address(_asset),
                    forbidden[d],
                    callers[c],
                    abi.encodeWithSelector(
                        IBurnerLoansRescue.BurnerLoans_InvalidRescueDestination.selector,
                        forbidden[d]
                    )
                );
        }
    }

    // Scenarios: I-03.
    function test_whenBalanceQueryReverts_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 c; c < callers.length; ++c) {
            bytes32 fundsBefore = _surplusFundsHash(_asset, _destination);
            vm.mockCallRevert(
                address(_asset),
                abi.encodeWithSelector(IERC20.balanceOf.selector, address(burnerLoans)),
                abi.encodeWithSelector(BalanceQueryFailed.selector)
            );
            MockERC20 tracker = new MockERC20("Queue tracker", "QTR", 18);
            _assertSurplusQueueFailure(
                tracker,
                address(_asset),
                _destination,
                callers[c],
                abi.encodeWithSelector(BalanceQueryFailed.selector)
            );
            vm.clearMockedCalls();
            assertEq(
                _surplusFundsHash(_asset, _destination),
                fundsBefore,
                "preview dependency failure preserves actual funds and ledger"
            );
        }
    }

    // Scenarios: Q-01.
    function test_givenSurplusKeyOwned_whenSameOrDifferentDestinationQueued_reverts() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        address[2] memory destinations = [_destination, alice];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            uint64 id = _assertSurplusQueued(_asset, _destination, callers[c]);
            bytes memory failure = abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _surplusKey(address(_asset)),
                id
            );
            for (uint256 d; d < destinations.length; ++d)
                _assertSurplusQueueFailure(
                    _asset,
                    address(_asset),
                    destinations[d],
                    callers[c],
                    failure
                );
            _executeVerifiedSurplus(id, _asset, _destination, _SURPLUS_AMOUNT, address(this));
            assertTrue(vm.revertToState(snapshot), "restore conflict owner");
        }
    }

    // Scenarios: Q-05.
    function test_givenDifferentTokens_whenRescuesQueuedAndExecuted() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 c; c < callers.length; ++c)
            for (uint256 reverse; reverse < 2; ++reverse) {
                uint256 snapshot = vm.snapshotState();
                ReentrantPayoutToken other = _createFixedRescueToken(_ALL_BUCKETS);
                other.mint(address(burnerLoans), _SURPLUS_AMOUNT);
                uint64 first = _assertSurplusQueued(_asset, _destination, callers[c]);
                uint64 second = _assertSurplusQueued(other, alice, callers[c]);
                assertEq(
                    configTimelock.pendingActionId(_surplusKey(address(_asset))),
                    first,
                    "first asset owns independent key"
                );
                assertEq(
                    configTimelock.pendingActionId(_surplusKey(address(other))),
                    second,
                    "second asset owns independent key"
                );
                if (reverse == 0) {
                    _executeVerifiedSurplus(
                        first,
                        _asset,
                        _destination,
                        _SURPLUS_AMOUNT,
                        address(this)
                    );
                    _executeVerifiedSurplus(second, other, alice, _SURPLUS_AMOUNT, address(this));
                } else {
                    _executeVerifiedSurplus(second, other, alice, _SURPLUS_AMOUNT, address(this));
                    _executeVerifiedSurplus(
                        first,
                        _asset,
                        _destination,
                        _SURPLUS_AMOUNT,
                        address(this)
                    );
                }
                assertTrue(vm.revertToState(snapshot), "restore independent token execution order");
            }
    }

    // Scenarios: Q-02.
    function test_givenSurplusAndTwoPendingRecipients_whenQueueAndExecutionOrdersVary() public {
        address[2] memory callers = [admin, burnerLoansAdmin];
        for (uint256 c; c < callers.length; ++c)
            for (uint256 reverseQueue; reverseQueue < 2; ++reverseQueue)
                for (uint256 reverseExecution; reverseExecution < 2; ++reverseExecution) {
                    uint256 snapshot = vm.snapshotState();
                    uint64 surplus;
                    uint64 keeper;
                    uint64 treasury;
                    if (reverseQueue == 0)
                        surplus = _assertSurplusQueued(_asset, _destination, callers[c]);
                    vm.prank(callers[c]);
                    keeper = configTimelock.queueRescuePendingPayout(
                        address(_asset),
                        _keeper,
                        alice,
                        4
                    );
                    vm.prank(callers[c]);
                    treasury = configTimelock.queueRescuePendingPayout(
                        address(_asset),
                        address(trsry),
                        alice,
                        4
                    );
                    if (reverseQueue != 0)
                        surplus = _assertSurplusQueued(_asset, _destination, callers[c]);
                    (bytes32 keeperKey, ) = configTimelock.getQueuedConfigState(keeper, 0, 0);
                    (bytes32 treasuryKey, ) = configTimelock.getQueuedConfigState(treasury, 0, 0);
                    assertTrue(
                        keeperKey != treasuryKey &&
                            keeperKey != _surplusKey(address(_asset)) &&
                            treasuryKey != _surplusKey(address(_asset)),
                        "surplus and each original recipient have distinct keys"
                    );
                    assertEq(
                        configTimelock.pendingActionId(keeperKey),
                        keeper,
                        "keeper key owner correct"
                    );
                    assertEq(
                        configTimelock.pendingActionId(treasuryKey),
                        treasury,
                        "Treasury key owner correct"
                    );
                    if (reverseExecution == 0)
                        _executeVerifiedSurplus(
                            surplus,
                            _asset,
                            _destination,
                            _SURPLUS_AMOUNT,
                            address(this)
                        );
                    vm.warp(configTimelock.getQueuedAction(keeper).executableAt);
                    configTimelock.executeQueuedAction(keeper);
                    configTimelock.executeQueuedAction(treasury);
                    if (reverseExecution != 0)
                        _executeVerifiedSurplus(
                            surplus,
                            _asset,
                            _destination,
                            _SURPLUS_AMOUNT,
                            address(this)
                        );
                    _assertPendingPayouts(address(_asset), _keeper, 16, _SEIZURE_AMOUNT, 6);
                    assertEq(
                        _asset.balanceOf(address(burnerLoans)),
                        52,
                        "only surplus 5 and two pending payments of 4 leave custody"
                    );
                    assertEq(
                        _asset.balanceOf(alice),
                        8,
                        "pending destinations receive exactly eight"
                    );
                    _assertSurplusCompleted(keeper, keeperKey);
                    _assertSurplusCompleted(treasury, treasuryKey);
                    assertTrue(
                        vm.revertToState(snapshot),
                        "restore coexistence queue/execution ordering"
                    );
                }
    }

    // Scenarios: LIVE-01.
    function test_givenQueuedRescue_whenCustodyIncreases() public {
        uint64 id = _assertSurplusQueued(_asset, _destination, admin);
        uint256 expectedSurplus = _SURPLUS_AMOUNT;

        _asset.mint(address(burnerLoans), _ADDITIONAL_CUSTODY);
        expectedSurplus = _INCREASED_SURPLUS;

        _executeVerifiedSurplus(id, _asset, _destination, expectedSurplus, address(this));
        _assertPendingPayouts(
            address(_asset),
            _keeper,
            _FEE_AMOUNT,
            _SEIZURE_AMOUNT,
            _REWARD_AMOUNT
        );
    }

    // Scenarios: LIVE-02.
    function test_givenQueuedRescue_whenKeeperRetryPaysDebt() public {
        uint64 id = _assertSurplusQueued(_asset, _destination, admin);
        uint256 expectedSurplus = _SURPLUS_AMOUNT;
        burnerLoans.transferPendingPayout(address(_asset), _keeper);
        _executeVerifiedSurplus(id, _asset, _destination, expectedSurplus, address(this));
        _assertPendingPayouts(address(_asset), _keeper, _FEE_AMOUNT, _SEIZURE_AMOUNT, 0);
    }

    // Scenarios: LIVE-03.
    function test_givenQueuedRescue_whenNewDebtConsumesSurplus() public {
        uint64 id = _assertSurplusQueued(_asset, _destination, admin);
        uint256 expectedSurplus = _SURPLUS_AMOUNT;

        vm.mockCall(
            address(_asset),
            abi.encodeWithSelector(IERC20.transfer.selector, _keeper),
            abi.encode(false)
        );
        burnerLoans.recordPendingSeizureRewardForTest(address(_asset), _keeper, _SURPLUS_AMOUNT);
        vm.clearMockedCalls();
        expectedSurplus = 0;

        _executeVerifiedSurplus(id, _asset, _destination, expectedSurplus, address(this));
        _assertPendingPayouts(
            address(_asset),
            _keeper,
            _FEE_AMOUNT,
            _SEIZURE_AMOUNT,
            _INCREASED_REWARD
        );
    }

    // Scenarios: BIND-01.
    function test_givenQueuedRescue_whenFacilityConfiguratorChanges_reverts() public {
        uint64 id = _assertSurplusQueued(_asset, _destination, admin);
        address replacement = address(_activateReplacementConfigurator());
        vm.startPrank(admin);
        burnerLoans.disable("");
        burnerLoans.setConfigurator(replacement);
        vm.stopPrank();
        _assertSurplusExecutionFailure(
            id,
            _asset,
            _destination,
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: TX-01.
    function test_givenQueuedRescue_whenTransferFailsThenRecovers() public {
        uint64 id = _assertSurplusQueued(_asset, _destination, admin);
        _asset.setTransferBlocked(_destination, true);
        _assertSurplusExecutionFailure(
            id,
            _asset,
            _destination,
            abi.encodeWithSelector(ReentrantPayoutToken.TransferBlocked.selector, _destination)
        );
        _asset.setTransferBlocked(_destination, false);
        _executeVerifiedSurplus(id, _asset, _destination, _SURPLUS_AMOUNT, address(this));
    }

    uint64 internal _surplusActionId;

    function _surplusKey(address asset_) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    address(burnerLoansConfig),
                    keccak256(
                        abi.encode(
                            keccak256("BURNER_LOANS_RESCUE"),
                            IBurnerLoansConfig.rescue.selector,
                            asset_
                        )
                    )
                )
            );
    }

    function _surplusFundsHash(
        MockERC20 asset_,
        address destination_
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _surplusAccountingHash(address(asset_)),
                    asset_.balanceOf(address(burnerLoans)),
                    asset_.balanceOf(destination_),
                    asset_.balanceOf(address(configTimelock)),
                    asset_.totalSupply()
                )
            );
    }

    /// @dev Assert exact ABI, state guard, scoped key, timing, flags, queue events and no payment.
    function _assertSurplusQueued(
        MockERC20 asset_,
        address destination_,
        address proposer_
    ) internal returns (uint64 id) {
        bytes32 fundsBefore = _surplusFundsHash(asset_, destination_);
        uint64 next = configTimelock.nextActionId();
        bytes memory payload = abi.encode(address(asset_), destination_);
        bytes32 key = _surplusKey(address(asset_));
        bytes32 configHash = keccak256(abi.encode(burnerLoansConfig.facility()));
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](1);
        batch[0] = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.rescue.selector,
            payload: payload
        });
        vm.expectEmit(true, true, true, true, address(configTimelock));
        emit IConfigTimelockBatchQueue.ConfigStateQueued(
            next,
            0,
            key,
            0,
            address(burnerLoansConfig),
            configHash
        );
        vm.expectEmit(true, true, true, true, address(configTimelock));
        emit ITimelockBatchQueue.TimelockSubActionQueued(
            next,
            address(burnerLoansConfig),
            IBurnerLoansConfig.rescue.selector,
            0,
            keccak256(payload)
        );
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit ITimelockBatchQueue.TimelockActionQueued(
            next,
            proposer_,
            keccak256(abi.encode(batch)),
            uint48(block.timestamp + configTimelock.timelockDelay()),
            uint48(
                block.timestamp + configTimelock.timelockDelay() + configTimelock.EXECUTION_WINDOW()
            )
        );
        vm.recordLogs();
        vm.prank(proposer_);
        id = configTimelock.queueRescue(address(asset_), destination_);
        assertEq(vm.getRecordedLogs().length, 3, "exact queue event count");
        assertEq(id, next, "queue returns prior action counter");
        assertEq(configTimelock.nextActionId(), next + 1, "queue increments counter once");
        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(id);
        assertEq(action.proposer, proposer_, "proposer stored");
        assertEq(action.queuedAt, block.timestamp, "queue time stored");
        assertEq(
            action.executableAt,
            block.timestamp + configTimelock.timelockDelay(),
            "ready time stored"
        );
        assertEq(
            action.expiresAt,
            action.executableAt + configTimelock.EXECUTION_WINDOW(),
            "expiry stored"
        );
        assertFalse(action.executed || action.cancelled, "new action pending");
        assertEq(action.actions.length, 1, "one sub-action stored");
        assertEq(action.actions[0].target, address(burnerLoansConfig), "rescue target stored");
        assertEq(
            action.actions[0].selector,
            IBurnerLoansConfig.rescue.selector,
            "surplus selector stored"
        );
        assertEq(action.actions[0].payload, payload, "both addresses preserved exactly");
        assertEq(
            configTimelock.getQueuedConfigDestination(id, 0),
            address(burnerLoansConfig),
            "correct guard destination"
        );
        assertEq(configTimelock.getQueuedConfigStateCount(id, 0), 1, "one state guard stored");
        (bytes32 storedKey, bytes32 storedHash) = configTimelock.getQueuedConfigState(id, 0, 0);
        assertEq(storedKey, key, "independently encoded key stored");
        assertEq(storedHash, configHash, "independent config state hash stored");
        assertEq(configTimelock.pendingActionId(key), id, "new action owns scoped key");
        assertEq(
            _surplusFundsHash(asset_, destination_),
            fundsBefore,
            "queue preserves all balances, debts, indexes and configuration"
        );
    }

    /// @dev Include every queued action/guard/key as well as represented funds in rollback checks.
    function _surplusQueueState(
        MockERC20 asset_,
        address destination_
    ) internal view returns (bytes32 state) {
        uint64 next = configTimelock.nextActionId();
        state = keccak256(
            abi.encode(
                next,
                configTimelock.isEnabled(),
                _surplusFundsHash(asset_, destination_),
                configTimelock.pendingActionId(_surplusKey(address(asset_)))
            )
        );
        for (uint64 id = 1; id < next; ++id) {
            state = keccak256(
                abi.encode(
                    state,
                    configTimelock.getQueuedAction(id),
                    configTimelock.getQueuedConfigStateCount(id, 0)
                )
            );
            if (configTimelock.getQueuedConfigStateCount(id, 0) != 0) {
                (bytes32 key, bytes32 value) = configTimelock.getQueuedConfigState(id, 0, 0);
                state = keccak256(
                    abi.encode(state, key, value, configTimelock.pendingActionId(key))
                );
            }
        }
    }

    /// @dev Exercise the typed and single-item batch entry points against the same exact failure.
    function _assertSurplusQueueFailure(
        MockERC20 tracker_,
        address requestedAsset_,
        address destination_,
        address caller_,
        bytes memory failure_
    ) internal {
        bytes32 beforeState = _surplusQueueState(tracker_, destination_);
        vm.recordLogs();
        vm.expectRevert(failure_);
        vm.prank(caller_);
        configTimelock.queueRescue(requestedAsset_, destination_);
        assertEq(vm.getRecordedLogs().length, 0, "rejected typed queue emits no logs");
        assertEq(
            _surplusQueueState(tracker_, destination_),
            beforeState,
            "rejected typed queue preserves counter, actions, guards, keys and funds"
        );
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](1);
        batch[0] = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.rescue.selector,
            payload: abi.encode(requestedAsset_, destination_)
        });
        vm.recordLogs();
        vm.expectRevert(failure_);
        vm.prank(caller_);
        configTimelock.queueBatch(batch);
        assertEq(vm.getRecordedLogs().length, 0, "rejected batch queue emits no logs");
        assertEq(
            _surplusQueueState(tracker_, destination_),
            beforeState,
            "rejected batch preserves all represented state"
        );
    }

    function _executeVerifiedSurplus(
        uint64 id_,
        MockERC20 asset_,
        address destination_,
        uint256 surplus_,
        address executor_
    ) internal {
        _surplusActionId = id_;
        vm.warp(configTimelock.getQueuedAction(id_).executableAt);
        _assertSurplusPayment(asset_, destination_, surplus_, executor_);
        _assertSurplusCompleted(id_, _surplusKey(address(asset_)));
    }

    function _assertSurplusCompleted(uint64 id_, bytes32 key_) internal view {
        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(id_);
        assertTrue(action.executed, "executed action marked complete");
        assertFalse(action.cancelled, "completed action not cancelled");
        assertEq(action.actions.length, 0, "completed payload cleared");
        assertEq(configTimelock.getQueuedConfigStateCount(id_, 0), 0, "completed guards cleared");
        assertEq(configTimelock.pendingActionId(key_), 0, "completed scoped key released");
    }

    function _assertSurplusExecutionFailure(
        uint64 id_,
        MockERC20 asset_,
        address destination_,
        bytes memory failure_
    ) internal {
        vm.warp(configTimelock.getQueuedAction(id_).executableAt);
        bytes32 beforeState = _surplusQueueState(asset_, destination_);
        vm.expectRevert(failure_);
        configTimelock.executeQueuedAction(id_);
        assertEq(
            _surplusQueueState(asset_, destination_),
            beforeState,
            "failed execution retains action, guards, key, debt and all balances"
        );
    }

    function _executeSurplusRescue(
        address asset_,
        address destination_,
        address caller_
    ) internal override {
        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(
            _surplusActionId
        );
        assertEq(
            action.actions[0].payload,
            abi.encode(asset_, destination_),
            "execution uses the stored request unchanged"
        );
        vm.prank(caller_);
        configTimelock.executeQueuedAction(_surplusActionId);
    }

    function _surplusExecutionLogCount(uint256 amount_) internal pure override returns (uint256) {
        return amount_ == 0 ? 2 : 4;
    }

    function _expectSurplusCompletionEvents(address caller_) internal override {
        vm.expectEmit(true, true, true, true, address(configTimelock));
        emit ITimelockBatchQueue.TimelockSubActionExecuted(
            _surplusActionId,
            address(burnerLoansConfig),
            IBurnerLoansConfig.rescue.selector,
            0
        );
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit ITimelockBatchQueue.TimelockActionExecuted(_surplusActionId, caller_);
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unused-return,unsafe-typecast)
