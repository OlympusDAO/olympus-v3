pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IRevenueDistributorRescue} from "src/policies/interfaces/IRevenueDistributorRescue.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";
import {RevenueDistributorSurplusRescueTestBase} from "src/test/policies/RevenueDistributor/fixtures/RevenueDistributorSurplusRescueTest.sol";

// Fixed queue inputs; fuzz only the permissionless execution caller, not meaningless addresses.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unused-return,unsafe-typecast)
contract RevenueDistributorConfigTimelockQueueRescueTest is
    RevenueDistributorSurplusRescueTestBase
{
    uint256 internal constant _QUEUED_CUSTODY = 7;
    uint256 internal constant _DESTINATION_BALANCE = 3;
    uint256 internal constant _ADDITIONAL_CUSTODY = 5;
    uint256 internal constant _INCREASED_CUSTODY = _QUEUED_CUSTODY + _ADDITIONAL_CUSTODY;

    error TransferRejected(address destination);

    function setUp() public override {
        super.setUp();
        _createManagedRescueDebt();
        token.mint(address(distributor), _QUEUED_CUSTODY);
        token.mint(bob, _DESTINATION_BALANCE);
        vm.prank(admin);
        rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, alice);
        MockYieldRepurchaseRecipient(distributor.yieldRecipient()).setVaultConfig(
            address(token),
            address(token),
            true
        );
    }

    // Scenarios: I-06.
    function test_givenSurplusThenInvalidPendingRescue_previewFailurePrecedesKeyConflict() public {
        address[2] memory callers = [admin, alice];
        for (uint256 i; i < callers.length; ++i) {
            uint256 snapshot = vm.snapshotState();
            MockERC20 neverListed = new MockERC20("Never listed", "NEW", 18);
            neverListed.mint(address(distributor), 1);
            ITimelockBatchQueue.BatchAction[]
                memory actions = new ITimelockBatchQueue.BatchAction[](2);
            actions[0] = ITimelockBatchQueue.BatchAction({
                target: address(distributor),
                selector: IRevenueDistributorRescue.rescue.selector,
                payload: abi.encode(address(neverListed), bob)
            });
            actions[1] = ITimelockBatchQueue.BatchAction({
                target: address(distributor),
                selector: IRevenueDistributorRescue.rescuePendingPayout.selector,
                payload: abi.encode(address(neverListed), alice, bob, uint256(1))
            });

            vm.expectRevert(
                abi.encodeWithSelector(
                    IRevenueDistributorRescue
                        .RevenueDistributor_InsufficientPendingDistribution
                        .selector,
                    address(neverListed),
                    1,
                    0
                )
            );
            vm.prank(callers[i]);
            configTimelock.queueBatch(actions);

            assertEq(configTimelock.nextActionId(), 1, "preview failure consumes no ID");
            assertEq(
                neverListed.balanceOf(address(distributor)),
                1,
                "preview failure moves no funds"
            );
            assertTrue(vm.revertToState(snapshot), "restore proposer case");
        }
    }

    // Scenarios: I-07.
    function test_givenPendingThenInvalidSurplusRescue_previewFailurePrecedesKeyConflict() public {
        address[2] memory callers = [admin, alice];
        for (uint256 i; i < callers.length; ++i) {
            uint256 snapshot = vm.snapshotState();
            ITimelockBatchQueue.BatchAction[]
                memory actions = new ITimelockBatchQueue.BatchAction[](2);
            actions[0] = ITimelockBatchQueue.BatchAction({
                target: address(distributor),
                selector: IRevenueDistributorRescue.rescuePendingPayout.selector,
                payload: abi.encode(address(_managedAsset), alice, bob, uint256(1))
            });
            actions[1] = ITimelockBatchQueue.BatchAction({
                target: address(distributor),
                selector: IRevenueDistributorRescue.rescue.selector,
                payload: abi.encode(address(_managedAsset), bob)
            });

            vm.expectRevert(
                abi.encodeWithSelector(
                    IRevenueDistributorRescue.RevenueDistributor_AssetManaged.selector,
                    address(_managedAsset)
                )
            );
            vm.prank(callers[i]);
            configTimelock.queueBatch(actions);

            assertEq(configTimelock.nextActionId(), 1, "preview failure consumes no ID");
            assertTrue(vm.revertToState(snapshot), "restore proposer case");
        }
    }

    // Scenarios: L-01, L-02, L-07, P-01.
    function test_givenDistributorLocalStates_whenEachRoleQueuesAndAnyExecutorExecutes(
        address executor_
    ) public {
        address[2] memory callers = [admin, alice];
        address[3] memory destinations = [address(treasury), address(configTimelock), bob];
        for (uint256 disabledRD; disabledRD < 2; ++disabledRD) {
            for (uint256 c; c < callers.length; ++c) {
                for (uint256 d; d < destinations.length; ++d) {
                    uint256 snapshot = vm.snapshotState();
                    if (disabledRD != 0) {
                        vm.prank(admin);
                        distributor.disable("");
                    }
                    if (destinations[d] != bob) token.mint(destinations[d], 3);
                    uint64 id = _assertSurplusQueued(token, destinations[d], callers[c]);
                    _executeVerifiedSurplus(id, token, destinations[d], _QUEUED_CUSTODY, executor_);
                    assertTrue(
                        vm.revertToState(snapshot),
                        "restore proposer/local state/destination"
                    );
                }
            }
        }
    }

    // Scenarios: L-01, L-02, L-07, P-01.
    function test_givenPermissionlessExecutorIdentities_whenSeeded() public {
        address[3] memory executors = [address(0), emergency, bob];
        for (uint256 e; e < executors.length; ++e) {
            test_givenDistributorLocalStates_whenEachRoleQueuesAndAnyExecutorExecutes(executors[e]);
        }
    }

    // Scenarios: P-02.
    function test_givenZeroCustodyAtQueue_whenExecuted() public {
        token.burn(address(distributor), _QUEUED_CUSTODY);
        address[2] memory callers = [admin, alice];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            uint64 id = _assertSurplusQueued(token, bob, callers[c]);
            _executeVerifiedSurplus(id, token, bob, 0, address(this));
            assertTrue(vm.revertToState(snapshot), "restore zero-custody queued request");
        }
    }

    // Scenarios: L-03.
    function test_givenEnabledActiveSelectedTimelock_whenCallerUnauthorized_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != admin && caller_ != alice);
        _assertSurplusQueueFailure(
            token,
            address(token),
            bob,
            caller_,
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
        _assertSurplusQueueFailure(
            token,
            address(0),
            address(0),
            caller_,
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: L-03.
    function test_givenUnauthorizedIdentities_whenQueueing_reverts() public {
        address[3] memory callers = [address(0), emergency, address(configTimelock)];
        for (uint256 c; c < callers.length; ++c) {
            test_givenEnabledActiveSelectedTimelock_whenCallerUnauthorized_reverts(callers[c]);
        }
    }

    // Scenarios: L-04.
    function test_givenTimelockDisabled_whenRescueQueued_reverts() public {
        address[2] memory callers = [admin, alice];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            configTimelock.disable("");
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(IEnabler.NotEnabled.selector);
            _assertSurplusQueueFailure(token, address(token), bob, callers[c], failure);
            _assertSurplusQueueFailure(token, address(0), address(0), callers[c], failure);
            assertTrue(vm.revertToState(snapshot), "restore queue gate");
        }
    }

    // Scenarios: L-05.
    function test_givenTimelockInactive_whenRescueQueued_reverts() public {
        address[2] memory callers = [admin, alice];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_PolicyInactive
                    .selector,
                address(configTimelock)
            );
            _assertSurplusQueueFailure(token, address(token), bob, callers[c], failure);
            _assertSurplusQueueFailure(token, address(0), address(0), callers[c], failure);
            assertTrue(vm.revertToState(snapshot), "restore queue gate");
        }
    }

    // Scenarios: L-06.
    function test_givenOperatorRemoved_whenRescueQueued_reverts() public {
        address[2] memory callers = [admin, alice];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            distributor.setConfigOperator(address(0));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(configTimelock)
            );
            _assertSurplusQueueFailure(token, address(token), bob, callers[c], failure);
            _assertSurplusQueueFailure(token, address(0), address(0), callers[c], failure);
            assertTrue(vm.revertToState(snapshot), "restore queue gate");
        }
    }

    // Scenarios: L-04.
    function test_givenQueuedRescue_whenTimelockDisabled_reverts() public {
        uint256 snapshot = vm.snapshotState();
        uint64 id = _assertSurplusQueued(token, bob, admin);
        vm.startPrank(admin);
        configTimelock.disable("");
        vm.stopPrank();
        bytes memory failure = abi.encodeWithSelector(IEnabler.NotEnabled.selector);
        _assertSurplusExecutionFailure(id, token, bob, failure);
        assertTrue(vm.revertToState(snapshot), "restore unavailable execution gate");
    }

    // Scenarios: L-05.
    function test_givenQueuedRescue_whenTimelockInactive_reverts() public {
        uint256 snapshot = vm.snapshotState();
        uint64 id = _assertSurplusQueued(token, bob, admin);
        vm.startPrank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
        vm.stopPrank();
        bytes memory failure = abi.encodeWithSelector(
            IRevenueDistributorConfigTimelock
                .RevenueDistributorConfigTimelock_PolicyInactive
                .selector,
            address(configTimelock)
        );
        _assertSurplusExecutionFailure(id, token, bob, failure);
        assertTrue(vm.revertToState(snapshot), "restore unavailable execution gate");
    }

    // Scenarios: L-08, L-09.
    function test_givenDistributorInactive_whenSurplusRescueQueued_reverts() public {
        address[2] memory callers = [admin, alice];
        for (uint256 disabledRD; disabledRD < 2; ++disabledRD) {
            for (uint256 c; c < callers.length; ++c) {
                uint256 snapshot = vm.snapshotState();
                vm.startPrank(admin);
                if (disabledRD != 0) distributor.disable("");
                kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
                vm.stopPrank();
                bytes memory failure = abi.encodeWithSelector(
                    IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
                );
                _assertSurplusQueueFailure(token, address(token), bob, callers[c], failure);
                _assertSurplusQueueFailure(token, address(0), address(0), callers[c], failure);
                assertTrue(vm.revertToState(snapshot), "restore inactive queue fixture");
            }
        }
    }

    // Scenarios: LIVE-05.
    // Deactivation after a valid queue preserves the request for retry after reactivation.
    function test_givenQueuedSurplusRescue_whenDistributorBecomesInactive_revertsThenRetries()
        public
    {
        address[2] memory callers = [admin, alice];
        for (uint256 disabledRD; disabledRD < 2; ++disabledRD) {
            for (uint256 c; c < callers.length; ++c) {
                uint256 snapshot = vm.snapshotState();
                if (disabledRD != 0) {
                    vm.prank(admin);
                    distributor.disable("");
                }
                uint64 id = _assertSurplusQueued(token, bob, callers[c]);
                vm.prank(admin);
                kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
                _assertSurplusExecutionFailure(
                    id,
                    token,
                    bob,
                    abi.encodeWithSelector(
                        IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
                    )
                );
                vm.prank(admin);
                kernel.executeAction(Actions.ActivatePolicy, address(distributor));
                _executeVerifiedSurplus(id, token, bob, _QUEUED_CUSTODY, address(this));
                assertTrue(vm.revertToState(snapshot), "restore deactivation during delay");
            }
        }
    }

    // Scenarios: I-01.
    function test_whenAssetHasNoCode_reverts() public {
        address[2] memory callers = [admin, alice];
        for (uint256 c; c < callers.length; ++c) {
            address[2] memory invalidAssets = [address(0), makeAddr("RDCT no-code rescue asset")];
            for (uint256 a; a < invalidAssets.length; ++a) {
                _assertSurplusQueueFailure(
                    token,
                    invalidAssets[a],
                    bob,
                    callers[c],
                    abi.encodeWithSelector(
                        IRevenueDistributor.RevenueDistributor_InvalidAsset.selector,
                        invalidAssets[a]
                    )
                );
            }
        }
    }

    // Scenarios: I-02.
    function test_whenDestinationIsForbidden_reverts() public {
        address[2] memory callers = [admin, alice];
        for (uint256 c; c < callers.length; ++c) {
            address[4] memory forbidden = [
                address(0),
                address(kernel),
                address(distributor),
                address(token)
            ];
            for (uint256 d; d < forbidden.length; ++d) {
                _assertSurplusQueueFailure(
                    token,
                    address(token),
                    forbidden[d],
                    callers[c],
                    abi.encodeWithSelector(
                        IRevenueDistributorRescue
                            .RevenueDistributor_InvalidRescueDestination
                            .selector,
                        forbidden[d]
                    )
                );
            }
        }
    }

    // Scenarios: I-04.
    function test_whenBalanceQueryReverts_reverts() public {
        address[2] memory callers = [admin, alice];
        for (uint256 c; c < callers.length; ++c) {
            bytes32 fundsBefore = _surplusFundsHash(token, bob);
            vm.mockCallRevert(
                address(token),
                abi.encodeWithSelector(IERC20.balanceOf.selector, address(distributor)),
                abi.encodeWithSelector(BalanceQueryFailed.selector)
            );
            MockERC20 tracker = new MockERC20("Queue tracker", "QTR", 18);
            _assertSurplusQueueFailure(
                tracker,
                address(token),
                bob,
                callers[c],
                abi.encodeWithSelector(BalanceQueryFailed.selector)
            );
            vm.clearMockedCalls();
            assertEq(
                _surplusFundsHash(token, bob),
                fundsBefore,
                "preview error preserves actual funds and obligations"
            );
        }
    }

    // Scenarios: I-03, I-05.
    function test_givenManagedAsset_whenRescueQueued_reverts() public {
        address[2] memory callers = [admin, alice];
        for (uint256 c; c < callers.length; ++c) {
            for (uint256 retired; retired < 2; ++retired) {
                uint256 snapshot = vm.snapshotState();
                IRevenueDistributor.AssetRoute[]
                    memory routes = new IRevenueDistributor.AssetRoute[](0);
                vm.prank(admin);
                distributor.setAssetRoutes(address(token), 0, routes);
                if (retired != 0) {
                    vm.prank(admin);
                    distributor.disableAssetRoutes(address(token));
                }
                _assertSurplusQueueFailure(
                    token,
                    address(token),
                    bob,
                    callers[c],
                    abi.encodeWithSelector(
                        IRevenueDistributorRescue.RevenueDistributor_AssetManaged.selector,
                        address(token)
                    )
                );
                assertTrue(vm.revertToState(snapshot), "restore managed queue asset state");
            }
        }
    }

    // Scenarios: Q-01.
    function test_givenAssetKeyOwned_whenRescueAndRouteQueuesConflict() public {
        address[2] memory callers = [admin, alice];
        for (uint256 c; c < callers.length; ++c) {
            for (uint256 routeFirst; routeFirst < 2; ++routeFirst) {
                uint256 snapshot = vm.snapshotState();
                IRevenueDistributor.AssetRoute[]
                    memory routes = new IRevenueDistributor.AssetRoute[](0);
                uint64 id;
                if (routeFirst == 0) {
                    id = _assertSurplusQueued(token, bob, callers[c]);
                } else {
                    vm.prank(callers[c]);
                    id = configTimelock.queueSetAssetRoutes(address(token), 0, routes);
                }
                bytes memory failure = abi.encodeWithSelector(
                    IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                    _surplusKey(address(token)),
                    id
                );
                _assertSurplusQueueFailure(token, address(token), bob, callers[c], failure);
                _assertSurplusQueueFailure(token, address(token), emergency, callers[c], failure);
                if (routeFirst == 0) {
                    bytes32 beforeState = _surplusQueueState(token, bob);
                    vm.expectRevert(failure);
                    vm.prank(callers[c]);
                    configTimelock.queueSetAssetRoutes(address(token), 0, routes);
                    assertEq(
                        _surplusQueueState(token, bob),
                        beforeState,
                        "route conflict retains existing surplus request"
                    );
                    _executeVerifiedSurplus(id, token, bob, _QUEUED_CUSTODY, address(this));
                } else {
                    vm.warp(configTimelock.getQueuedAction(id).executableAt);
                    configTimelock.executeQueuedAction(id);
                    _assertSurplusCompleted(id, _surplusKey(address(token)));
                    assertEq(
                        token.balanceOf(address(distributor)),
                        _QUEUED_CUSTODY,
                        "original route action remains executable without rescue payment"
                    );
                }
                assertTrue(vm.revertToState(snapshot), "restore route/rescue conflict ordering");
            }
        }
    }

    // Scenarios: Q-02.
    function test_givenIndependentAsset_whenSurplusRescueQueuedAndExecutedInEitherOrder() public {
        address[2] memory callers = [admin, alice];
        for (uint256 c; c < callers.length; ++c) {
            for (uint256 reverseQueue; reverseQueue < 2; ++reverseQueue) {
                for (uint256 reverseExecution; reverseExecution < 2; ++reverseExecution) {
                    uint256 snapshot = vm.snapshotState();
                    MockERC20 other = new MockERC20("Other surplus", "OSUR", 18);
                    other.mint(address(distributor), _QUEUED_CUSTODY);
                    uint64 surplus;
                    if (reverseQueue == 0) surplus = _assertSurplusQueued(token, bob, callers[c]);
                    uint64 independent = _assertSurplusQueued(other, emergency, callers[c]);
                    if (reverseQueue != 0) surplus = _assertSurplusQueued(token, bob, callers[c]);
                    (bytes32 independentKey, ) = configTimelock.getQueuedConfigState(
                        independent,
                        0,
                        0
                    );
                    assertTrue(
                        independentKey != _surplusKey(address(token)),
                        "independent action owns a different key"
                    );
                    assertEq(
                        configTimelock.pendingActionId(independentKey),
                        independent,
                        "independent key owner retained"
                    );
                    if (reverseExecution == 0) {
                        _executeVerifiedSurplus(
                            surplus,
                            token,
                            bob,
                            _QUEUED_CUSTODY,
                            address(this)
                        );
                    }
                    _executeVerifiedSurplus(
                        independent,
                        other,
                        emergency,
                        _QUEUED_CUSTODY,
                        address(this)
                    );
                    if (reverseExecution != 0) {
                        _executeVerifiedSurplus(
                            surplus,
                            token,
                            bob,
                            _QUEUED_CUSTODY,
                            address(this)
                        );
                    }
                    assertTrue(
                        vm.revertToState(snapshot),
                        "restore independent queue/execution order"
                    );
                }
            }
        }
    }

    // Scenarios: Q-02.
    function test_givenYieldConfigurationAction_whenSurplusRescueQueuedAndExecutedInEitherOrder()
        public
    {
        address[2] memory callers = [admin, alice];
        for (uint256 c; c < callers.length; ++c) {
            for (uint256 reverseQueue; reverseQueue < 2; ++reverseQueue) {
                for (uint256 reverseExecution; reverseExecution < 2; ++reverseExecution) {
                    uint256 snapshot = vm.snapshotState();

                    uint64 surplus;
                    if (reverseQueue == 0) surplus = _assertSurplusQueued(token, bob, callers[c]);
                    address currentYieldRecipient = distributor.yieldRecipient();
                    vm.prank(callers[c]);
                    uint64 independent = configTimelock.queueSetYieldRecipient(
                        currentYieldRecipient
                    );
                    if (reverseQueue != 0) surplus = _assertSurplusQueued(token, bob, callers[c]);
                    (bytes32 independentKey, ) = configTimelock.getQueuedConfigState(
                        independent,
                        0,
                        0
                    );
                    assertTrue(
                        independentKey != _surplusKey(address(token)),
                        "independent action owns a different key"
                    );
                    assertEq(
                        configTimelock.pendingActionId(independentKey),
                        independent,
                        "independent key owner retained"
                    );
                    if (reverseExecution == 0) {
                        _executeVerifiedSurplus(
                            surplus,
                            token,
                            bob,
                            _QUEUED_CUSTODY,
                            address(this)
                        );
                    }
                    vm.warp(configTimelock.getQueuedAction(independent).executableAt);
                    configTimelock.executeQueuedAction(independent);
                    _assertSurplusCompleted(independent, independentKey);
                    if (reverseExecution != 0) {
                        _executeVerifiedSurplus(
                            surplus,
                            token,
                            bob,
                            _QUEUED_CUSTODY,
                            address(this)
                        );
                    }
                    assertTrue(
                        vm.revertToState(snapshot),
                        "restore independent queue/execution order"
                    );
                }
            }
        }
    }

    // Scenarios: LIVE-01.
    function test_givenQueuedRescue_whenCustodyIncreases() public {
        uint64 id = _assertSurplusQueued(token, bob, admin);
        token.mint(address(distributor), _ADDITIONAL_CUSTODY);
        _executeVerifiedSurplus(id, token, bob, _INCREASED_CUSTODY, address(this));
    }

    // Scenarios: LIVE-02.
    function test_givenQueuedRescue_whenAdminAlreadyRescued() public {
        uint64 id = _assertSurplusQueued(token, bob, admin);

        vm.prank(admin);
        distributor.rescue(address(token), bob);

        _executeVerifiedSurplus(id, token, bob, 0, address(this));
    }

    // Scenarios: LIVE-03.
    function test_givenQueuedNeverListedAsset_whenActivated_reverts() public {
        uint64 id = _assertSurplusQueued(token, bob, admin);
        (bytes32 key, bytes32 expectedHash) = configTimelock.getQueuedConfigState(id, 0, 0);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(admin);
        distributor.setAssetRoutes(address(token), 0, routes);

        bytes32 currentHash = keccak256(abi.encode(distributor.assetState(address(token))));
        _assertSurplusExecutionFailure(
            id,
            token,
            bob,
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                id,
                0,
                key,
                expectedHash,
                currentHash
            )
        );
    }

    // Scenarios: LIVE-04.
    function test_givenQueuedNeverListedAsset_whenActivatedThenRetired_reverts() public {
        uint64 id = _assertSurplusQueued(token, bob, admin);
        (bytes32 key, bytes32 expectedHash) = configTimelock.getQueuedConfigState(id, 0, 0);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(admin);
        distributor.setAssetRoutes(address(token), 0, routes);

        vm.prank(admin);
        distributor.disableAssetRoutes(address(token));

        bytes32 currentHash = keccak256(abi.encode(distributor.assetState(address(token))));
        _assertSurplusExecutionFailure(
            id,
            token,
            bob,
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                id,
                0,
                key,
                expectedHash,
                currentHash
            )
        );
    }

    // Scenarios: TX-01.
    function test_givenQueuedSurplus_whenTransferFailsThenRecovers() public {
        uint64 id = _assertSurplusQueued(token, bob, admin);
        bytes memory failure = abi.encodeWithSelector(TransferRejected.selector, bob);
        vm.mockCallRevert(
            address(token),
            abi.encodeWithSelector(IERC20.transfer.selector, bob),
            failure
        );
        _assertSurplusExecutionFailure(id, token, bob, failure);
        vm.clearMockedCalls();
        _executeVerifiedSurplus(id, token, bob, _QUEUED_CUSTODY, address(this));
    }

    uint64 internal _surplusActionId;

    function _surplusKey(address asset_) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    address(distributor),
                    keccak256(abi.encode(keccak256("REVENUE_DISTRIBUTOR_ASSET"), asset_))
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
                    _rdSurplusStateHash(address(asset_)),
                    asset_.balanceOf(address(distributor)),
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
        bytes32 configHash = keccak256(abi.encode(distributor.assetState(address(asset_))));
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](1);
        batch[0] = ITimelockBatchQueue.BatchAction({
            target: address(distributor),
            selector: IRevenueDistributorRescue.rescue.selector,
            payload: payload
        });
        vm.expectEmit(true, true, true, true, address(configTimelock));
        emit IConfigTimelockBatchQueue.ConfigStateQueued(
            next,
            0,
            key,
            0,
            address(distributor),
            configHash
        );
        vm.expectEmit(true, true, true, true, address(configTimelock));
        emit ITimelockBatchQueue.TimelockSubActionQueued(
            next,
            address(distributor),
            IRevenueDistributorRescue.rescue.selector,
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
        assertEq(action.actions[0].target, address(distributor), "rescue target stored");
        assertEq(
            action.actions[0].selector,
            IRevenueDistributorRescue.rescue.selector,
            "surplus selector stored"
        );
        assertEq(action.actions[0].payload, payload, "both addresses preserved exactly");
        assertEq(
            configTimelock.getQueuedConfigDestination(id, 0),
            address(distributor),
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
            target: address(distributor),
            selector: IRevenueDistributorRescue.rescue.selector,
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
        _assertRDSurplusPayment(asset_, destination_, surplus_, executor_);
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

    function _executeRDSurplusRescue(
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

    function _rdSurplusExecutionLogCount(uint256 amount_) internal pure override returns (uint256) {
        return amount_ == 0 ? 2 : 4;
    }

    function _expectSurplusCompletionEvents(address caller_) internal override {
        vm.expectEmit(true, true, true, true, address(configTimelock));
        emit ITimelockBatchQueue.TimelockSubActionExecuted(
            _surplusActionId,
            address(distributor),
            IRevenueDistributorRescue.rescue.selector,
            0
        );
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit ITimelockBatchQueue.TimelockActionExecuted(_surplusActionId, caller_);
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unused-return,unsafe-typecast)
