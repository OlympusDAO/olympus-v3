pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorRescue} from "src/policies/interfaces/IRevenueDistributorRescue.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";

// Contracts
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions} from "src/Kernel.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {ReentrantPayoutToken} from "src/test/mocks/ReentrantPayoutToken.sol";
import {RevenueDistributorSurplusRescueTestBase} from "src/test/policies/RevenueDistributor/fixtures/RevenueDistributorSurplusRescueTest.sol";

// Quantities are base units; finite boundary/identity drivers avoid hidden state generators.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unused-return,unsafe-typecast)
contract RevenueDistributorRescueTest is RevenueDistributorSurplusRescueTestBase {
    uint256 internal constant _SURPLUS_CUSTODY = 19;
    uint256 internal constant _DESTINATION_BALANCE = 7;
    uint256 internal constant _ADDITIONAL_CUSTODY = 5;

    enum NestedAction {
        Surplus,
        PendingPayout,
        Retry,
        Distribute,
        Configuration
    }
    ReentrantPayoutToken internal _callbackAsset;

    // Scenarios: L-01.
    function test_givenDistributorEnabled_whenAdminRescues() public {
        _createManagedRescueDebt();
        token.mint(address(distributor), _SURPLUS_CUSTODY);
        token.mint(bob, _DESTINATION_BALANCE);

        assertEq(
            distributor.previewRescue(address(token), bob),
            _SURPLUS_CUSTODY,
            "surplus preview ignores local enablement"
        );
        _assertRDSurplusPayment(token, bob, _SURPLUS_CUSTODY, admin);
    }

    // Scenarios: L-06.
    function test_givenDistributorDisabled_whenAdminRescues() public {
        _createManagedRescueDebt();
        token.mint(address(distributor), _SURPLUS_CUSTODY);
        token.mint(bob, _DESTINATION_BALANCE);

        vm.startPrank(admin);
        distributor.disable("");

        vm.stopPrank();
        assertEq(
            distributor.previewRescue(address(token), bob),
            _SURPLUS_CUSTODY,
            "surplus preview ignores local enablement"
        );
        _assertRDSurplusPayment(token, bob, _SURPLUS_CUSTODY, admin);
    }

    // Scenarios: L-03.
    function test_givenDistributorInactive_whenAdminRescues_reverts() public {
        _createManagedRescueDebt();
        token.mint(address(distributor), _SURPLUS_CUSTODY);
        token.mint(bob, _DESTINATION_BALANCE);

        for (uint256 disabled; disabled < 2; ++disabled) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            if (disabled != 0) distributor.disable("");
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
            );
            vm.expectRevert(failure);
            distributor.previewRescue(address(token), bob);
            vm.expectRevert(failure);
            distributor.previewRescue(address(0), address(0));
            _assertRDSurplusFailure(token, address(token), bob, admin, failure);
            _assertRDSurplusFailure(token, address(0), address(0), admin, failure);

            assertTrue(vm.revertToState(snapshot), "restore authorized RD lifecycle");
        }
    }

    // Scenarios: L-02.
    function test_givenDistributorEnabled_whenOperatorRescues() public {
        _createManagedRescueDebt();
        token.mint(address(distributor), _SURPLUS_CUSTODY);
        token.mint(bob, _DESTINATION_BALANCE);

        assertEq(
            distributor.previewRescue(address(token), bob),
            _SURPLUS_CUSTODY,
            "surplus preview ignores local enablement"
        );
        _assertRDSurplusPayment(token, bob, _SURPLUS_CUSTODY, address(configTimelock));
    }

    // Scenarios: L-07.
    function test_givenDistributorDisabled_whenOperatorRescues() public {
        _createManagedRescueDebt();
        token.mint(address(distributor), _SURPLUS_CUSTODY);
        token.mint(bob, _DESTINATION_BALANCE);

        vm.startPrank(admin);
        distributor.disable("");

        vm.stopPrank();
        assertEq(
            distributor.previewRescue(address(token), bob),
            _SURPLUS_CUSTODY,
            "surplus preview ignores local enablement"
        );
        _assertRDSurplusPayment(token, bob, _SURPLUS_CUSTODY, address(configTimelock));
    }

    // Scenarios: L-04.
    function test_givenDistributorInactive_whenOperatorRescues_reverts() public {
        _createManagedRescueDebt();
        token.mint(address(distributor), _SURPLUS_CUSTODY);
        token.mint(bob, _DESTINATION_BALANCE);

        for (uint256 disabled; disabled < 2; ++disabled) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            if (disabled != 0) distributor.disable("");
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
            );
            vm.expectRevert(failure);
            distributor.previewRescue(address(token), bob);
            vm.expectRevert(failure);
            distributor.previewRescue(address(0), address(0));
            _assertRDSurplusFailure(token, address(token), bob, address(configTimelock), failure);
            _assertRDSurplusFailure(
                token,
                address(0),
                address(0),
                address(configTimelock),
                failure
            );

            assertTrue(vm.revertToState(snapshot), "restore authorized RD lifecycle");
        }
    }

    // Scenarios: L-05.
    function test_givenDistributorLifecycle_whenCallerUnauthorized_reverts(address caller_) public {
        address operator = distributor.configOperator();
        vm.assume(caller_ != admin && (operator == address(0) || caller_ != operator));
        token.mint(address(distributor), _SURPLUS_CUSTODY);
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint256 inactive; inactive < 2; ++inactive) {
                uint256 snapshot = vm.snapshotState();
                vm.startPrank(admin);
                if (disabled != 0) distributor.disable("");
                if (inactive != 0)
                    kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
                vm.stopPrank();
                bytes memory failure = abi.encodeWithSelector(
                    IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                    caller_
                );
                _assertRDSurplusFailure(token, address(token), bob, caller_, failure);
                _assertRDSurplusFailure(token, address(0), address(0), caller_, failure);
                assertTrue(vm.revertToState(snapshot), "restore unauthorized RD lifecycle");
            }
    }

    // Scenarios: L-01, L-02, L-05, L-06, L-07.
    // Preview ignores caller authorization and local enablement while RD is Kernel-active.
    function test_givenActiveDistributor_whenAnyCallerPreviews(
        address caller_,
        bool disabled_
    ) public {
        token.mint(address(distributor), _SURPLUS_CUSTODY);
        if (disabled_) {
            vm.prank(admin);
            distributor.disable("");
        }
        vm.prank(caller_);
        assertEq(
            distributor.previewRescue(address(token), bob),
            _SURPLUS_CUSTODY,
            "preview is permissionless"
        );
    }

    // Scenarios: L-03, L-04, L-05.
    // Activity is checked before invalid inputs, independently of caller identity.
    function test_givenInactiveDistributor_whenAnyCallerPreviews_reverts(
        address caller_,
        bool disabled_
    ) public {
        vm.startPrank(admin);
        if (disabled_) distributor.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        vm.stopPrank();
        bytes memory failure = abi.encodeWithSelector(
            IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
        );
        vm.expectRevert(failure);
        vm.prank(caller_);
        distributor.previewRescue(address(token), bob);
        vm.expectRevert(failure);
        vm.prank(caller_);
        distributor.previewRescue(address(0), address(0));
    }

    // Scenarios: L-05.
    function test_givenUnauthorizedIdentities_whenSeeded_reverts() public {
        address[3] memory callers = [address(0), emergency, alice];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            test_givenDistributorLifecycle_whenCallerUnauthorized_reverts(callers[c]);
            assertTrue(vm.revertToState(snapshot), "restore seeded unauthorized identity");
        }
        vm.prank(admin);
        distributor.setConfigOperator(alice);
        test_givenDistributorLifecycle_whenCallerUnauthorized_reverts(address(configTimelock));
    }

    // Scenarios: A-01.
    function test_givenTimelockUnavailable_whenAdminRescuesDirectly() public {
        for (uint256 inactiveTimelock; inactiveTimelock < 2; ++inactiveTimelock)
            for (uint256 disabledRD; disabledRD < 2; ++disabledRD) {
                uint256 snapshot = vm.snapshotState();
                _createManagedRescueDebt();
                token.mint(address(distributor), _SURPLUS_CUSTODY);
                vm.startPrank(admin);
                if (inactiveTimelock == 0) configTimelock.disable("");
                else kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
                if (disabledRD != 0) distributor.disable("");
                vm.stopPrank();
                uint64 counter = configTimelock.nextActionId();
                _assertRDSurplusPayment(token, bob, _SURPLUS_CUSTODY, admin);
                assertEq(
                    configTimelock.nextActionId(),
                    counter,
                    "direct recovery creates no queued action"
                );
                assertTrue(vm.revertToState(snapshot), "restore direct RD recovery");
            }
    }

    // Scenarios: P-01, ISO-01.
    function test_givenNeverListedAsset_whenFullCustodyRescued(
        uint256 balance_,
        address destination_
    ) public {
        vm.assume(
            destination_ != address(0) &&
                destination_ != address(kernel) &&
                destination_ != address(distributor) &&
                destination_ != address(token)
        );
        _createManagedRescueDebt();
        _caseFullCustody(bound(balance_, 1, type(uint256).max), destination_);
    }

    // Scenarios: P-01, ISO-01.
    function test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded() public {
        _createManagedRescueDebt();
        uint256[3] memory balances = [uint256(1), type(uint256).max - 1, type(uint256).max];
        address[3] memory destinations = [address(treasury), address(configTimelock), bob];
        for (uint256 b; b < balances.length; ++b)
            for (uint256 d; d < destinations.length; ++d) {
                uint256 snapshot = vm.snapshotState();
                _caseFullCustody(balances[b], destinations[d]);
                assertTrue(
                    vm.revertToState(snapshot),
                    "restore full-custody boundary and destination"
                );
            }
    }

    function _caseFullCustody(uint256 balance_, address destination_) internal {
        token.mint(address(distributor), balance_);
        uint256 supplyBudget = type(uint256).max - balance_;
        token.mint(
            destination_,
            supplyBudget < _DESTINATION_BALANCE ? supplyBudget : _DESTINATION_BALANCE
        );
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            _assertRDSurplusPayment(token, destination_, balance_, callers[c]);
            assertTrue(vm.revertToState(snapshot), "restore full custody between caller classes");
        }
    }

    // Scenarios: P-02.
    function test_givenZeroCustody_whenEachPermittedCallerRescues() public {
        _createManagedRescueDebt();
        _assertRDSurplusPayment(token, bob, 0, admin);
        _assertRDSurplusPayment(token, bob, 0, address(configTimelock));
    }

    // Scenarios: AUTH-01.
    function test_givenOperatorRotated_whenFormerOperatorRescues_reverts() public {
        address newOperator = alice;
        token.mint(address(distributor), _SURPLUS_CUSTODY);
        vm.prank(admin);
        distributor.setConfigOperator(newOperator);
        _assertRDSurplusFailure(
            token,
            address(token),
            bob,
            address(configTimelock),
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                address(configTimelock)
            )
        );
    }

    // Scenarios: AUTH-01.
    function test_givenOperatorRotated_whenCurrentAuthorityRescues() public {
        address newOperator = alice;
        token.mint(address(distributor), _SURPLUS_CUSTODY);
        vm.prank(admin);
        distributor.setConfigOperator(newOperator);
        address[2] memory callers = [admin, newOperator];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            _assertRDSurplusPayment(token, bob, _SURPLUS_CUSTODY, callers[c]);
            assertTrue(vm.revertToState(snapshot), "restore independent authorized payment");
        }
    }

    // Scenarios: AUTH-01.
    function test_givenOperatorRevoked_whenFormerOperatorOrZeroCallerRescues_reverts() public {
        address newOperator = alice;
        token.mint(address(distributor), _SURPLUS_CUSTODY);
        vm.prank(admin);
        distributor.setConfigOperator(newOperator);
        vm.prank(admin);
        distributor.setConfigOperator(address(0));
        address[2] memory callers = [newOperator, address(0)];
        for (uint256 c; c < callers.length; ++c)
            _assertRDSurplusFailure(
                token,
                address(token),
                bob,
                callers[c],
                abi.encodeWithSelector(
                    IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                    callers[c]
                )
            );
    }

    // Scenarios: AUTH-01.
    function test_givenOperatorRevoked_whenAdminRescues() public {
        address newOperator = alice;
        token.mint(address(distributor), _SURPLUS_CUSTODY);
        vm.prank(admin);
        distributor.setConfigOperator(newOperator);
        vm.prank(admin);
        distributor.setConfigOperator(address(0));
        _assertRDSurplusPayment(token, bob, _SURPLUS_CUSTODY, admin);
    }

    // Scenarios: I-01.
    function test_givenNeverListedAsset_whenAssetHasNoCode_reverts() public {
        _createManagedRescueDebt();
        address[2] memory callers = [admin, address(configTimelock)];
        uint256[3] memory balances = [uint256(0), 1, type(uint256).max];
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint256 c; c < callers.length; ++c)
                for (uint256 b; b < balances.length; ++b) {
                    uint256 snapshot = vm.snapshotState();
                    if (disabled != 0) {
                        vm.prank(admin);
                        distributor.disable("");
                    }
                    token.mint(address(distributor), balances[b]);
                    address[2] memory invalidAssets = [
                        address(0),
                        makeAddr("RD no-code rescue asset")
                    ];
                    for (uint256 a; a < invalidAssets.length; ++a) {
                        bytes memory failure = abi.encodeWithSelector(
                            IRevenueDistributor.RevenueDistributor_InvalidAsset.selector,
                            invalidAssets[a]
                        );
                        _assertRDMatchingError(token, invalidAssets[a], bob, callers[c], failure);
                        // Combining faults also proves asset validation precedes destination validation.
                        _assertRDMatchingError(
                            token,
                            invalidAssets[a],
                            address(0),
                            callers[c],
                            failure
                        );
                    }

                    assertTrue(vm.revertToState(snapshot), "restore invalid RD request");
                }
    }

    // Scenarios: I-02.
    function test_givenNeverListedAsset_whenDestinationIsForbidden_reverts() public {
        _createManagedRescueDebt();
        address[2] memory callers = [admin, address(configTimelock)];
        uint256[3] memory balances = [uint256(0), 1, type(uint256).max];
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint256 c; c < callers.length; ++c)
                for (uint256 b; b < balances.length; ++b) {
                    uint256 snapshot = vm.snapshotState();
                    if (disabled != 0) {
                        vm.prank(admin);
                        distributor.disable("");
                    }
                    token.mint(address(distributor), balances[b]);

                    address[4] memory forbidden = [
                        address(0),
                        address(kernel),
                        address(distributor),
                        address(token)
                    ];
                    for (uint256 d; d < forbidden.length; ++d)
                        _assertRDMatchingError(
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

                    assertTrue(vm.revertToState(snapshot), "restore invalid RD request");
                }
    }

    // Scenarios: I-05.
    function test_givenNeverListedAsset_whenBalanceQueryReverts_reverts() public {
        _createManagedRescueDebt();
        address[2] memory callers = [admin, address(configTimelock)];
        uint256[3] memory balances = [uint256(0), 1, type(uint256).max];
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint256 c; c < callers.length; ++c)
                for (uint256 b; b < balances.length; ++b) {
                    uint256 snapshot = vm.snapshotState();
                    if (disabled != 0) {
                        vm.prank(admin);
                        distributor.disable("");
                    }
                    token.mint(address(distributor), balances[b]);

                    _assertRDBalanceQueryFailure(token, callers[c]);
                    assertTrue(vm.revertToState(snapshot), "restore invalid RD request");
                }
    }

    /// @notice Managed assets are forbidden regardless of solvency, debt or local enablement.
    // Scenarios: I-03.
    function test_givenActiveAsset_whenSurplusRescueRequested_reverts() public {
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 custodyState; custodyState < 4; ++custodyState)
            for (uint256 disabled; disabled < 2; ++disabled)
                for (uint256 c; c < callers.length; ++c) {
                    uint256 snapshot = vm.snapshotState();
                    ReentrantPayoutToken asset;
                    if (custodyState == 0) {
                        asset = new ReentrantPayoutToken();
                        IRevenueDistributor.AssetRoute[]
                            memory routes = new IRevenueDistributor.AssetRoute[](0);
                        vm.prank(admin);
                        distributor.setAssetRoutes(address(asset), 0, routes);
                    } else {
                        asset = _createManagedRescueDebt();
                        if (custodyState == 1) asset.burn(address(distributor), 1);
                        if (custodyState == 3)
                            asset.mint(address(distributor), _ADDITIONAL_CUSTODY);
                    }

                    if (disabled != 0) {
                        vm.prank(admin);
                        distributor.disable("");
                    }
                    _assertRDMatchingError(
                        asset,
                        address(asset),
                        bob,
                        callers[c],
                        abi.encodeWithSelector(
                            IRevenueDistributorRescue.RevenueDistributor_AssetManaged.selector,
                            address(asset)
                        )
                    );
                    _assertRDMatchingError(
                        asset,
                        address(asset),
                        address(kernel),
                        callers[c],
                        abi.encodeWithSelector(
                            IRevenueDistributorRescue
                                .RevenueDistributor_InvalidRescueDestination
                                .selector,
                            address(kernel)
                        )
                    );
                    assertTrue(
                        vm.revertToState(snapshot),
                        "restore managed-asset custody and listing state"
                    );
                }
    }

    // Scenarios: I-04.
    function test_givenRetiredAsset_whenSurplusRescueRequested_reverts() public {
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 custodyState; custodyState < 4; ++custodyState)
            for (uint256 disabled; disabled < 2; ++disabled)
                for (uint256 c; c < callers.length; ++c) {
                    uint256 snapshot = vm.snapshotState();
                    ReentrantPayoutToken asset;
                    if (custodyState == 0) {
                        asset = new ReentrantPayoutToken();
                        IRevenueDistributor.AssetRoute[]
                            memory routes = new IRevenueDistributor.AssetRoute[](0);
                        vm.prank(admin);
                        distributor.setAssetRoutes(address(asset), 0, routes);
                    } else {
                        asset = _createManagedRescueDebt();
                        if (custodyState == 1) asset.burn(address(distributor), 1);
                        if (custodyState == 3)
                            asset.mint(address(distributor), _ADDITIONAL_CUSTODY);
                    }

                    vm.prank(admin);
                    distributor.disableAssetRoutes(address(asset));

                    if (disabled != 0) {
                        vm.prank(admin);
                        distributor.disable("");
                    }
                    _assertRDMatchingError(
                        asset,
                        address(asset),
                        bob,
                        callers[c],
                        abi.encodeWithSelector(
                            IRevenueDistributorRescue.RevenueDistributor_AssetManaged.selector,
                            address(asset)
                        )
                    );
                    _assertRDMatchingError(
                        asset,
                        address(asset),
                        address(kernel),
                        callers[c],
                        abi.encodeWithSelector(
                            IRevenueDistributorRescue
                                .RevenueDistributor_InvalidRescueDestination
                                .selector,
                            address(kernel)
                        )
                    );
                    assertTrue(
                        vm.revertToState(snapshot),
                        "restore managed-asset custody and listing state"
                    );
                }
    }

    function _assertRDMatchingError(
        MockERC20 tracker_,
        address asset_,
        address destination_,
        address caller_,
        bytes memory failure_
    ) internal {
        vm.expectRevert(failure_);
        distributor.previewRescue(asset_, destination_);
        _assertRDSurplusFailure(tracker_, asset_, destination_, caller_, failure_);
    }

    // Scenarios: TX-01.
    function test_givenNeverListedAsset_whenTransferReverts_reverts() public {
        _assertTransferFailure(false);
    }

    // Scenarios: TX-02.
    function test_givenNeverListedAsset_whenTransferReturnsFalse_reverts() public {
        _assertTransferFailure(true);
    }

    function _assertTransferFailure(bool returnsFalse_) internal {
        _createManagedRescueDebt();
        ReentrantPayoutToken asset = new ReentrantPayoutToken();
        asset.mint(address(distributor), _SURPLUS_CUSTODY);
        asset.mint(bob, _DESTINATION_BALANCE);
        assertEq(
            distributor.previewRescue(address(asset), bob),
            _SURPLUS_CUSTODY,
            "preview omits transfer dependency"
        );
        bytes memory failure;
        if (returnsFalse_) {
            vm.mockCall(
                address(asset),
                abi.encodeWithSelector(IERC20.transfer.selector, bob),
                abi.encode(false)
            );
            failure = abi.encodeWithSelector(
                SafeERC20.SafeERC20FailedOperation.selector,
                address(asset)
            );
        } else {
            asset.setTransferBlocked(bob, true);
            failure = abi.encodeWithSelector(ReentrantPayoutToken.TransferBlocked.selector, bob);
        }
        _assertRDSurplusFailure(asset, address(asset), bob, admin, failure);
        _assertRDSurplusFailure(asset, address(asset), bob, address(configTimelock), failure);
        vm.clearMockedCalls();
    }

    // Scenarios: CB-01.
    function test_givenSurplusRescueCallback_whenFailureIsCaught() public {
        for (
            uint256 differentToken;
            differentToken < (0 == uint256(NestedAction.Surplus) ? 2 : 1);
            ++differentToken
        )
            for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
                uint256 snapshot = vm.snapshotState();
                _createManagedRescueDebt();
                _callbackAsset = new ReentrantPayoutToken();
                _callbackAsset.mint(address(distributor), _SURPLUS_CUSTODY);
                MockERC20 nestedAsset = _callbackAsset;
                if (differentToken != 0) {
                    nestedAsset = new MockERC20("Other surplus", "OSUR", 18);
                    nestedAsset.mint(address(distributor), _ADDITIONAL_CUSTODY);
                }
                if (0 != uint256(NestedAction.Surplus)) nestedAsset = _managedAsset;
                vm.prank(admin);
                distributor.setConfigOperator(address(this));
                bytes32 nestedBefore = _rdRawRescueHash(address(nestedAsset));
                uint256 nestedCustody = nestedAsset.balanceOf(address(distributor));
                _callbackAsset.setCallbackFrom(
                    address(distributor),
                    address(this),
                    abi.encodeCall(
                        this.observeAndAttemptNestedAction,
                        (address(nestedAsset), NestedAction(0))
                    )
                );
                _callbackAsset.setBubbleCallbackFailure(false);
                address caller = operatorCaller == 0 ? admin : address(this);

                _assertRDSurplusPayment(_callbackAsset, bob, _SURPLUS_CUSTODY, caller);
                assertEq(
                    _callbackAsset.callbackRevertData(),
                    abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
                    "nested action reaches guard after callback reads"
                );

                assertEq(
                    _rdRawRescueHash(address(nestedAsset)),
                    nestedBefore,
                    "nested accounting and indexes preserved"
                );
                if (address(nestedAsset) != address(_callbackAsset))
                    assertEq(
                        nestedAsset.balanceOf(address(distributor)),
                        nestedCustody,
                        "other token custody unchanged"
                    );
                assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
            }
    }

    // Scenarios: CB-01.
    function test_givenSurplusRescueCallback_whenFailureIsPropagated() public {
        for (
            uint256 differentToken;
            differentToken < (0 == uint256(NestedAction.Surplus) ? 2 : 1);
            ++differentToken
        )
            for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
                uint256 snapshot = vm.snapshotState();
                _createManagedRescueDebt();
                _callbackAsset = new ReentrantPayoutToken();
                _callbackAsset.mint(address(distributor), _SURPLUS_CUSTODY);
                MockERC20 nestedAsset = _callbackAsset;
                if (differentToken != 0) {
                    nestedAsset = new MockERC20("Other surplus", "OSUR", 18);
                    nestedAsset.mint(address(distributor), _ADDITIONAL_CUSTODY);
                }
                if (0 != uint256(NestedAction.Surplus)) nestedAsset = _managedAsset;
                vm.prank(admin);
                distributor.setConfigOperator(address(this));
                bytes32 nestedBefore = _rdRawRescueHash(address(nestedAsset));
                uint256 nestedCustody = nestedAsset.balanceOf(address(distributor));
                _callbackAsset.setCallbackFrom(
                    address(distributor),
                    address(this),
                    abi.encodeCall(
                        this.observeAndAttemptNestedAction,
                        (address(nestedAsset), NestedAction(0))
                    )
                );
                _callbackAsset.setBubbleCallbackFailure(true);
                address caller = operatorCaller == 0 ? admin : address(this);

                _assertRDSurplusFailure(
                    _callbackAsset,
                    address(_callbackAsset),
                    bob,
                    caller,
                    abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector)
                );
                assertTrue(_callbackAsset.callbackEnabled(), "propagation restores callback state");

                assertEq(
                    _rdRawRescueHash(address(nestedAsset)),
                    nestedBefore,
                    "nested accounting and indexes preserved"
                );
                if (address(nestedAsset) != address(_callbackAsset))
                    assertEq(
                        nestedAsset.balanceOf(address(distributor)),
                        nestedCustody,
                        "other token custody unchanged"
                    );
                assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
            }
    }

    // Scenarios: CB-02.
    function test_givenPendingRescueCallback_whenFailureIsCaught() public {
        for (
            uint256 differentToken;
            differentToken < (1 == uint256(NestedAction.Surplus) ? 2 : 1);
            ++differentToken
        )
            for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
                uint256 snapshot = vm.snapshotState();
                _createManagedRescueDebt();
                _callbackAsset = new ReentrantPayoutToken();
                _callbackAsset.mint(address(distributor), _SURPLUS_CUSTODY);
                MockERC20 nestedAsset = _callbackAsset;
                if (differentToken != 0) {
                    nestedAsset = new MockERC20("Other surplus", "OSUR", 18);
                    nestedAsset.mint(address(distributor), _ADDITIONAL_CUSTODY);
                }
                if (1 != uint256(NestedAction.Surplus)) nestedAsset = _managedAsset;
                vm.prank(admin);
                distributor.setConfigOperator(address(this));
                bytes32 nestedBefore = _rdRawRescueHash(address(nestedAsset));
                uint256 nestedCustody = nestedAsset.balanceOf(address(distributor));
                _callbackAsset.setCallbackFrom(
                    address(distributor),
                    address(this),
                    abi.encodeCall(
                        this.observeAndAttemptNestedAction,
                        (address(nestedAsset), NestedAction(1))
                    )
                );
                _callbackAsset.setBubbleCallbackFailure(false);
                address caller = operatorCaller == 0 ? admin : address(this);

                _assertRDSurplusPayment(_callbackAsset, bob, _SURPLUS_CUSTODY, caller);
                assertEq(
                    _callbackAsset.callbackRevertData(),
                    abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
                    "nested action reaches guard after callback reads"
                );

                assertEq(
                    _rdRawRescueHash(address(nestedAsset)),
                    nestedBefore,
                    "nested accounting and indexes preserved"
                );
                if (address(nestedAsset) != address(_callbackAsset))
                    assertEq(
                        nestedAsset.balanceOf(address(distributor)),
                        nestedCustody,
                        "other token custody unchanged"
                    );
                assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
            }
    }

    // Scenarios: CB-02.
    function test_givenPendingRescueCallback_whenFailureIsPropagated() public {
        for (
            uint256 differentToken;
            differentToken < (1 == uint256(NestedAction.Surplus) ? 2 : 1);
            ++differentToken
        )
            for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
                uint256 snapshot = vm.snapshotState();
                _createManagedRescueDebt();
                _callbackAsset = new ReentrantPayoutToken();
                _callbackAsset.mint(address(distributor), _SURPLUS_CUSTODY);
                MockERC20 nestedAsset = _callbackAsset;
                if (differentToken != 0) {
                    nestedAsset = new MockERC20("Other surplus", "OSUR", 18);
                    nestedAsset.mint(address(distributor), _ADDITIONAL_CUSTODY);
                }
                if (1 != uint256(NestedAction.Surplus)) nestedAsset = _managedAsset;
                vm.prank(admin);
                distributor.setConfigOperator(address(this));
                bytes32 nestedBefore = _rdRawRescueHash(address(nestedAsset));
                uint256 nestedCustody = nestedAsset.balanceOf(address(distributor));
                _callbackAsset.setCallbackFrom(
                    address(distributor),
                    address(this),
                    abi.encodeCall(
                        this.observeAndAttemptNestedAction,
                        (address(nestedAsset), NestedAction(1))
                    )
                );
                _callbackAsset.setBubbleCallbackFailure(true);
                address caller = operatorCaller == 0 ? admin : address(this);

                _assertRDSurplusFailure(
                    _callbackAsset,
                    address(_callbackAsset),
                    bob,
                    caller,
                    abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector)
                );
                assertTrue(_callbackAsset.callbackEnabled(), "propagation restores callback state");

                assertEq(
                    _rdRawRescueHash(address(nestedAsset)),
                    nestedBefore,
                    "nested accounting and indexes preserved"
                );
                if (address(nestedAsset) != address(_callbackAsset))
                    assertEq(
                        nestedAsset.balanceOf(address(distributor)),
                        nestedCustody,
                        "other token custody unchanged"
                    );
                assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
            }
    }

    // Scenarios: CB-02.
    function test_givenPendingRetryCallback_whenFailureIsCaught() public {
        for (
            uint256 differentToken;
            differentToken < (2 == uint256(NestedAction.Surplus) ? 2 : 1);
            ++differentToken
        )
            for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
                uint256 snapshot = vm.snapshotState();
                _createManagedRescueDebt();
                _callbackAsset = new ReentrantPayoutToken();
                _callbackAsset.mint(address(distributor), _SURPLUS_CUSTODY);
                MockERC20 nestedAsset = _callbackAsset;
                if (differentToken != 0) {
                    nestedAsset = new MockERC20("Other surplus", "OSUR", 18);
                    nestedAsset.mint(address(distributor), _ADDITIONAL_CUSTODY);
                }
                if (2 != uint256(NestedAction.Surplus)) nestedAsset = _managedAsset;
                vm.prank(admin);
                distributor.setConfigOperator(address(this));
                bytes32 nestedBefore = _rdRawRescueHash(address(nestedAsset));
                uint256 nestedCustody = nestedAsset.balanceOf(address(distributor));
                _callbackAsset.setCallbackFrom(
                    address(distributor),
                    address(this),
                    abi.encodeCall(
                        this.observeAndAttemptNestedAction,
                        (address(nestedAsset), NestedAction(2))
                    )
                );
                _callbackAsset.setBubbleCallbackFailure(false);
                address caller = operatorCaller == 0 ? admin : address(this);

                _assertRDSurplusPayment(_callbackAsset, bob, _SURPLUS_CUSTODY, caller);
                assertEq(
                    _callbackAsset.callbackRevertData(),
                    abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
                    "nested action reaches guard after callback reads"
                );

                assertEq(
                    _rdRawRescueHash(address(nestedAsset)),
                    nestedBefore,
                    "nested accounting and indexes preserved"
                );
                if (address(nestedAsset) != address(_callbackAsset))
                    assertEq(
                        nestedAsset.balanceOf(address(distributor)),
                        nestedCustody,
                        "other token custody unchanged"
                    );
                assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
            }
    }

    // Scenarios: CB-02.
    function test_givenPendingRetryCallback_whenFailureIsPropagated() public {
        for (
            uint256 differentToken;
            differentToken < (2 == uint256(NestedAction.Surplus) ? 2 : 1);
            ++differentToken
        )
            for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
                uint256 snapshot = vm.snapshotState();
                _createManagedRescueDebt();
                _callbackAsset = new ReentrantPayoutToken();
                _callbackAsset.mint(address(distributor), _SURPLUS_CUSTODY);
                MockERC20 nestedAsset = _callbackAsset;
                if (differentToken != 0) {
                    nestedAsset = new MockERC20("Other surplus", "OSUR", 18);
                    nestedAsset.mint(address(distributor), _ADDITIONAL_CUSTODY);
                }
                if (2 != uint256(NestedAction.Surplus)) nestedAsset = _managedAsset;
                vm.prank(admin);
                distributor.setConfigOperator(address(this));
                bytes32 nestedBefore = _rdRawRescueHash(address(nestedAsset));
                uint256 nestedCustody = nestedAsset.balanceOf(address(distributor));
                _callbackAsset.setCallbackFrom(
                    address(distributor),
                    address(this),
                    abi.encodeCall(
                        this.observeAndAttemptNestedAction,
                        (address(nestedAsset), NestedAction(2))
                    )
                );
                _callbackAsset.setBubbleCallbackFailure(true);
                address caller = operatorCaller == 0 ? admin : address(this);

                _assertRDSurplusFailure(
                    _callbackAsset,
                    address(_callbackAsset),
                    bob,
                    caller,
                    abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector)
                );
                assertTrue(_callbackAsset.callbackEnabled(), "propagation restores callback state");

                assertEq(
                    _rdRawRescueHash(address(nestedAsset)),
                    nestedBefore,
                    "nested accounting and indexes preserved"
                );
                if (address(nestedAsset) != address(_callbackAsset))
                    assertEq(
                        nestedAsset.balanceOf(address(distributor)),
                        nestedCustody,
                        "other token custody unchanged"
                    );
                assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
            }
    }

    // Scenarios: CB-02.
    function test_givenDistributeCallback_whenFailureIsCaught() public {
        for (
            uint256 differentToken;
            differentToken < (3 == uint256(NestedAction.Surplus) ? 2 : 1);
            ++differentToken
        )
            for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
                uint256 snapshot = vm.snapshotState();
                _createManagedRescueDebt();
                _callbackAsset = new ReentrantPayoutToken();
                _callbackAsset.mint(address(distributor), _SURPLUS_CUSTODY);
                MockERC20 nestedAsset = _callbackAsset;
                if (differentToken != 0) {
                    nestedAsset = new MockERC20("Other surplus", "OSUR", 18);
                    nestedAsset.mint(address(distributor), _ADDITIONAL_CUSTODY);
                }
                if (3 != uint256(NestedAction.Surplus)) nestedAsset = _managedAsset;
                vm.prank(admin);
                distributor.setConfigOperator(address(this));
                bytes32 nestedBefore = _rdRawRescueHash(address(nestedAsset));
                uint256 nestedCustody = nestedAsset.balanceOf(address(distributor));
                _callbackAsset.setCallbackFrom(
                    address(distributor),
                    address(this),
                    abi.encodeCall(
                        this.observeAndAttemptNestedAction,
                        (address(nestedAsset), NestedAction(3))
                    )
                );
                _callbackAsset.setBubbleCallbackFailure(false);
                address caller = operatorCaller == 0 ? admin : address(this);

                _assertRDSurplusPayment(_callbackAsset, bob, _SURPLUS_CUSTODY, caller);
                assertEq(
                    _callbackAsset.callbackRevertData(),
                    abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
                    "nested action reaches guard after callback reads"
                );

                assertEq(
                    _rdRawRescueHash(address(nestedAsset)),
                    nestedBefore,
                    "nested accounting and indexes preserved"
                );
                if (address(nestedAsset) != address(_callbackAsset))
                    assertEq(
                        nestedAsset.balanceOf(address(distributor)),
                        nestedCustody,
                        "other token custody unchanged"
                    );
                assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
            }
    }

    // Scenarios: CB-02.
    function test_givenDistributeCallback_whenFailureIsPropagated() public {
        for (
            uint256 differentToken;
            differentToken < (3 == uint256(NestedAction.Surplus) ? 2 : 1);
            ++differentToken
        )
            for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
                uint256 snapshot = vm.snapshotState();
                _createManagedRescueDebt();
                _callbackAsset = new ReentrantPayoutToken();
                _callbackAsset.mint(address(distributor), _SURPLUS_CUSTODY);
                MockERC20 nestedAsset = _callbackAsset;
                if (differentToken != 0) {
                    nestedAsset = new MockERC20("Other surplus", "OSUR", 18);
                    nestedAsset.mint(address(distributor), _ADDITIONAL_CUSTODY);
                }
                if (3 != uint256(NestedAction.Surplus)) nestedAsset = _managedAsset;
                vm.prank(admin);
                distributor.setConfigOperator(address(this));
                bytes32 nestedBefore = _rdRawRescueHash(address(nestedAsset));
                uint256 nestedCustody = nestedAsset.balanceOf(address(distributor));
                _callbackAsset.setCallbackFrom(
                    address(distributor),
                    address(this),
                    abi.encodeCall(
                        this.observeAndAttemptNestedAction,
                        (address(nestedAsset), NestedAction(3))
                    )
                );
                _callbackAsset.setBubbleCallbackFailure(true);
                address caller = operatorCaller == 0 ? admin : address(this);

                _assertRDSurplusFailure(
                    _callbackAsset,
                    address(_callbackAsset),
                    bob,
                    caller,
                    abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector)
                );
                assertTrue(_callbackAsset.callbackEnabled(), "propagation restores callback state");

                assertEq(
                    _rdRawRescueHash(address(nestedAsset)),
                    nestedBefore,
                    "nested accounting and indexes preserved"
                );
                if (address(nestedAsset) != address(_callbackAsset))
                    assertEq(
                        nestedAsset.balanceOf(address(distributor)),
                        nestedCustody,
                        "other token custody unchanged"
                    );
                assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
            }
    }

    // Scenarios: CB-02.
    function test_givenConfigurationCallback_whenFailureIsCaught() public {
        for (
            uint256 differentToken;
            differentToken < (4 == uint256(NestedAction.Surplus) ? 2 : 1);
            ++differentToken
        )
            for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
                uint256 snapshot = vm.snapshotState();
                _createManagedRescueDebt();
                _callbackAsset = new ReentrantPayoutToken();
                _callbackAsset.mint(address(distributor), _SURPLUS_CUSTODY);
                MockERC20 nestedAsset = _callbackAsset;
                if (differentToken != 0) {
                    nestedAsset = new MockERC20("Other surplus", "OSUR", 18);
                    nestedAsset.mint(address(distributor), _ADDITIONAL_CUSTODY);
                }
                if (4 != uint256(NestedAction.Surplus)) nestedAsset = _managedAsset;
                vm.prank(admin);
                distributor.setConfigOperator(address(this));
                bytes32 nestedBefore = _rdRawRescueHash(address(nestedAsset));
                uint256 nestedCustody = nestedAsset.balanceOf(address(distributor));
                _callbackAsset.setCallbackFrom(
                    address(distributor),
                    address(this),
                    abi.encodeCall(
                        this.observeAndAttemptNestedAction,
                        (address(nestedAsset), NestedAction(4))
                    )
                );
                _callbackAsset.setBubbleCallbackFailure(false);
                address caller = operatorCaller == 0 ? admin : address(this);

                _assertRDSurplusPayment(_callbackAsset, bob, _SURPLUS_CUSTODY, caller);
                assertEq(
                    _callbackAsset.callbackRevertData(),
                    abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
                    "nested action reaches guard after callback reads"
                );

                assertEq(
                    _rdRawRescueHash(address(nestedAsset)),
                    nestedBefore,
                    "nested accounting and indexes preserved"
                );
                if (address(nestedAsset) != address(_callbackAsset))
                    assertEq(
                        nestedAsset.balanceOf(address(distributor)),
                        nestedCustody,
                        "other token custody unchanged"
                    );
                assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
            }
    }

    // Scenarios: CB-02.
    function test_givenConfigurationCallback_whenFailureIsPropagated() public {
        for (
            uint256 differentToken;
            differentToken < (4 == uint256(NestedAction.Surplus) ? 2 : 1);
            ++differentToken
        )
            for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
                uint256 snapshot = vm.snapshotState();
                _createManagedRescueDebt();
                _callbackAsset = new ReentrantPayoutToken();
                _callbackAsset.mint(address(distributor), _SURPLUS_CUSTODY);
                MockERC20 nestedAsset = _callbackAsset;
                if (differentToken != 0) {
                    nestedAsset = new MockERC20("Other surplus", "OSUR", 18);
                    nestedAsset.mint(address(distributor), _ADDITIONAL_CUSTODY);
                }
                if (4 != uint256(NestedAction.Surplus)) nestedAsset = _managedAsset;
                vm.prank(admin);
                distributor.setConfigOperator(address(this));
                bytes32 nestedBefore = _rdRawRescueHash(address(nestedAsset));
                uint256 nestedCustody = nestedAsset.balanceOf(address(distributor));
                _callbackAsset.setCallbackFrom(
                    address(distributor),
                    address(this),
                    abi.encodeCall(
                        this.observeAndAttemptNestedAction,
                        (address(nestedAsset), NestedAction(4))
                    )
                );
                _callbackAsset.setBubbleCallbackFailure(true);
                address caller = operatorCaller == 0 ? admin : address(this);

                _assertRDSurplusFailure(
                    _callbackAsset,
                    address(_callbackAsset),
                    bob,
                    caller,
                    abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector)
                );
                assertTrue(_callbackAsset.callbackEnabled(), "propagation restores callback state");

                assertEq(
                    _rdRawRescueHash(address(nestedAsset)),
                    nestedBefore,
                    "nested accounting and indexes preserved"
                );
                if (address(nestedAsset) != address(_callbackAsset))
                    assertEq(
                        nestedAsset.balanceOf(address(distributor)),
                        nestedCustody,
                        "other token custody unchanged"
                    );
                assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
            }
    }

    function observeAndAttemptNestedAction(address nestedAsset_, NestedAction action_) external {
        assertEq(msg.sender, address(_callbackAsset), "observer called by outer token");
        assertEq(
            distributor.previewRescue(address(_callbackAsset), bob),
            0,
            "callback observes consumed surplus"
        );
        assertEq(
            distributor.totalPendingForTest(address(_managedAsset)),
            _MANAGED_RESERVE,
            "callback observes unrelated liabilities intact"
        );
        if (action_ == NestedAction.Surplus) distributor.rescue(nestedAsset_, bob);
        else if (action_ == NestedAction.PendingPayout)
            distributor.rescuePendingPayout(nestedAsset_, alice, bob, 1);
        else if (action_ == NestedAction.Retry)
            distributor.transferPendingPayout(nestedAsset_, alice);
        else if (action_ == NestedAction.Distribute) distributor.distribute(nestedAsset_);
        else distributor.setYieldRecipient(distributor.yieldRecipient());
    }

    // Scenarios: L-01.
    function test_givenDistributorRestored_whenSurplusRescued() public {
        token.mint(address(distributor), _SURPLUS_CUSTODY);
        vm.startPrank(admin);
        distributor.disable("");
        distributor.reEnable();
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        kernel.executeAction(Actions.ActivatePolicy, address(distributor));
        vm.stopPrank();
        _assertRDSurplusPayment(token, bob, _SURPLUS_CUSTODY, admin);
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unused-return,unsafe-typecast)
