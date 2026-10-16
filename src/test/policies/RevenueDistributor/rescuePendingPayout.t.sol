// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin-5.7.0/interfaces/draft-IERC6093.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorRescue} from "src/policies/interfaces/IRevenueDistributorRescue.sol";

// Libraries
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {ReentrantPayoutToken} from "src/test/mocks/ReentrantPayoutToken.sol";
import {RevenueDistributorPendingRescueTest, RevenueDistributorRescueObserver} from "src/test/policies/RevenueDistributor/fixtures/RevenueDistributorPendingRescueTest.sol";

// Fixed token base units, explicit enum domains and checked fixture casts make these literals safe.
// forge-lint: disable-start(literal-instead-of-constant,unused-return,unsafe-typecast,calls-loop)
/// @dev Allocation partitions supply exact expected debits; numerical tests vary funded quantities separately.
contract RevenueDistributorRescuePendingPayoutTest is RevenueDistributorPendingRescueTest {
    enum Allocation {
        Route,
        Repurchase,
        Treasury,
        RouteRepurchase,
        RouteTreasury,
        RepurchaseTreasury,
        All
    }
    struct RescueRequest {
        address asset;
        address recipient;
        address destination;
        uint256 amount;
    }
    address internal constant _NO_CODE_ASSET = address(0xC0DE);
    uint256 internal constant _INVALID_SELECTION_COUNT = (uint256(Layout.All) + 1) * 8 * 4;
    uint8 internal constant _LIFECYCLE_STATE_COUNT = 8;
    uint256 internal constant _INVALID_CASE_OTHER_ASSET_DEBT = 9;
    uint256 internal constant _INVALID_CASE_SURPLUS = 5;

    struct Selection {
        Layout layoutId;
        uint8 mask;
        uint8 owner;
    }
    uint8 internal constant _DISABLED = 1;
    uint8 internal constant _RETIRED = 2;
    uint8 internal constant _OPERATOR = 4;
    uint8 internal constant _OTHER_ROUTE = 1;
    uint8 internal constant _OTHER_ASSET = 2;
    uint8 internal constant _SURPLUS = 4;

    /// @notice Admin recovery on RD remains available with its timelock disabled or Kernel-inactive.
    /// @dev RD itself stays Kernel-active; vary its local enabled state independently and use the normal payout assertions.
    // Scenarios: RD-A01.
    function test_givenTimelockUnavailable_whenAdminRescuesPendingPayout() public {
        for (uint256 inactiveTimelock; inactiveTimelock < 2; ++inactiveTimelock) {
            for (uint256 disabledRD; disabledRD < 2; ++disabledRD) {
                uint256 snapshot = vm.snapshotState();
                Ledger memory l = _configureLayout(
                    Layout.Distinct,
                    new MockRevertingTransferToken(18)
                );
                l.route = 10;
                _fundLedger(l, false, disabledRD != 0);
                vm.prank(admin);
                if (inactiveTimelock == 0) configTimelock.disable("");
                else kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
                _assertSuccess(l, admin, l.routeOwner, bob, 4, [uint256(4), 0, 0]);
                assertEq(
                    configTimelock.nextActionId(),
                    1,
                    "direct rescue creates no timelock action"
                );
                assertTrue(vm.revertToState(snapshot), "restore direct admin recovery");
            }
        }
    }

    /// @notice Request stays within the first eligible asset-route interval.
    // Scenarios: RD-P01.
    function test_allocation_givenRoute_whenAmountIsWithinInterval(
        uint256 choice_,
        uint256 amount_,
        uint8 state_,
        uint8 isolation_
    ) public {
        _allocationFuzz(Allocation.Route, choice_, amount_, state_, isolation_);
    }

    /// @notice No eligible route debt; request stays within the repurchase interval.
    // Scenarios: RD-P06.
    function test_allocation_givenRepurchase_whenAmountIsWithinInterval(
        uint256 choice_,
        uint256 amount_,
        uint8 state_,
        uint8 isolation_
    ) public {
        _allocationFuzz(Allocation.Repurchase, choice_, amount_, state_, isolation_);
    }

    /// @notice Only Treasury is eligible before the requested amount is exhausted.
    // Scenarios: RD-P07.
    function test_allocation_givenTreasury_whenAmountIsWithinInterval(
        uint256 choice_,
        uint256 amount_,
        uint8 state_,
        uint8 isolation_
    ) public {
        _allocationFuzz(Allocation.Treasury, choice_, amount_, state_, isolation_);
    }

    /// @notice Clear the eligible route and partially or fully debit repurchase.
    // Scenarios: RD-P08.
    function test_allocation_givenRouteAndRepurchase_whenAmountSpansBoth(
        uint256 choice_,
        uint256 amount_,
        uint8 state_,
        uint8 isolation_
    ) public {
        _allocationFuzz(Allocation.RouteRepurchase, choice_, amount_, state_, isolation_);
    }

    /// @notice Clear route and debit Treasury with no eligible repurchase share.
    // Scenarios: RD-P09.
    function test_allocation_givenRouteAndTreasury_whenAmountSpansBoth(
        uint256 choice_,
        uint256 amount_,
        uint8 state_,
        uint8 isolation_
    ) public {
        _allocationFuzz(Allocation.RouteTreasury, choice_, amount_, state_, isolation_);
    }

    /// @notice Clear repurchase and debit Treasury with no eligible route share.
    // Scenarios: RD-P10.
    function test_allocation_givenRepurchaseAndTreasury_whenAmountSpansBoth(
        uint256 choice_,
        uint256 amount_,
        uint8 state_,
        uint8 isolation_
    ) public {
        _allocationFuzz(Allocation.RepurchaseTreasury, choice_, amount_, state_, isolation_);
    }

    /// @notice Route and repurchase drain before the remainder reaches Treasury.
    // Scenarios: RD-P11.
    function test_allocation_givenAllBuckets_whenAmountSpansAll(
        uint256 amount_,
        uint8 state_,
        uint8 isolation_
    ) public {
        _allocationFuzz(Allocation.All, 0, amount_, state_, isolation_);
    }

    /// @notice Deterministically execute every compatible identity/presence, lifecycle and isolation combination.
    // Scenarios: RD-P01, RD-P02.
    function test_allocation_givenRoute_whenBoundariesAreSeeded() public {
        _allocationSeeds(Allocation.Route);
    }

    /// @notice Guarantee the repurchase interval endpoints and adjacent interior values.
    // Scenarios: RD-P06, RD-P02.
    function test_allocation_givenRepurchase_whenBoundariesAreSeeded() public {
        _allocationSeeds(Allocation.Repurchase);
    }

    /// @notice Guarantee the Treasury interval endpoints and adjacent interior values.
    // Scenarios: RD-P07, RD-P02.
    function test_allocation_givenTreasury_whenBoundariesAreSeeded() public {
        _allocationSeeds(Allocation.Treasury);
    }

    /// @notice Guarantee boundaries crossing route into repurchase.
    // Scenarios: RD-P08, RD-P02.
    function test_allocation_givenRouteAndRepurchase_whenBoundariesAreSeeded() public {
        _allocationSeeds(Allocation.RouteRepurchase);
    }

    /// @notice Guarantee boundaries crossing route into Treasury.
    // Scenarios: RD-P09, RD-P02.
    function test_allocation_givenRouteAndTreasury_whenBoundariesAreSeeded() public {
        _allocationSeeds(Allocation.RouteTreasury);
    }

    /// @notice Guarantee boundaries crossing repurchase into Treasury.
    // Scenarios: RD-P10, RD-P02.
    function test_allocation_givenRepurchaseAndTreasury_whenBoundariesAreSeeded() public {
        _allocationSeeds(Allocation.RepurchaseTreasury);
    }

    /// @notice Guarantee the final three-bucket interval endpoints, including exact full drain.
    // Scenarios: RD-P11, RD-P02.
    function test_allocation_givenAllBuckets_whenBoundariesAreSeeded() public {
        _allocationSeeds(Allocation.All);
    }

    /// @notice A zero asset fails before destination, recipient and amount checks.
    // Scenarios: RD-I01.
    function test_invalidInputs_whenAssetIsZero_reverts(
        uint256 choice_,
        uint256 amount_,
        uint8 state_
    ) public {
        uint256 snapshot = vm.snapshotState();
        uint8 state = uint8(bound(state_, 0, _LIFECYCLE_STATE_COUNT - 1));
        Selection memory selection = _invalidSelection(
            bound(choice_, 0, _INVALID_SELECTION_COUNT - 1)
        );
        Ledger memory l = _createInvalidInputLedger(selection);
        _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);

        bytes memory failure = abi.encodeWithSelector(
            IRevenueDistributor.RevenueDistributor_InvalidAsset.selector,
            address(0)
        );
        _assertInvalidRescueRequest(
            l,
            _caller(state),
            RescueRequest({
                asset: address(0),
                recipient: _recipient(l, selection.owner),
                destination: bob,
                amount: amount_
            }),
            failure,
            failure
        );
        assertTrue(vm.revertToState(snapshot), "restore invalid input fixture");
    }

    /// @notice Nonzero no-code assets use the same invalid-asset error.
    // Scenarios: RD-I01.
    function test_invalidInputs_whenAssetHasNoCode_reverts(
        uint256 choice_,
        uint256 amount_,
        uint8 state_
    ) public {
        assertEq(_NO_CODE_ASSET.code.length, 0, "invalid asset has no token code");
        uint256 snapshot = vm.snapshotState();
        uint8 state = uint8(bound(state_, 0, _LIFECYCLE_STATE_COUNT - 1));
        Selection memory selection = _invalidSelection(
            bound(choice_, 0, _INVALID_SELECTION_COUNT - 1)
        );
        Ledger memory l = _createInvalidInputLedger(selection);
        _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);

        bytes memory failure = abi.encodeWithSelector(
            IRevenueDistributor.RevenueDistributor_InvalidAsset.selector,
            _NO_CODE_ASSET
        );
        _assertInvalidRescueRequest(
            l,
            _caller(state),
            RescueRequest({
                asset: _NO_CODE_ASSET,
                recipient: _recipient(l, selection.owner),
                destination: bob,
                amount: amount_
            }),
            failure,
            failure
        );
        assertTrue(vm.revertToState(snapshot), "restore invalid input fixture");
    }

    /// @notice Zero destination wins over recipient/amount errors over the full uint256 amount domain.
    // Scenarios: RD-I02.
    function test_invalidInputs_whenDestinationIsZero_reverts(
        uint256 choice_,
        uint256 amount_,
        uint8 state_
    ) public {
        uint256 snapshot = vm.snapshotState();
        uint8 state = uint8(bound(state_, 0, _LIFECYCLE_STATE_COUNT - 1));
        Selection memory selection = _invalidSelection(
            bound(choice_, 0, _INVALID_SELECTION_COUNT - 1)
        );
        Ledger memory l = _createInvalidInputLedger(selection);
        _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);

        bytes memory failure = abi.encodeWithSelector(
            IRevenueDistributorRescue.RevenueDistributor_InvalidRescueDestination.selector,
            address(0)
        );
        _assertInvalidRescueRequest(
            l,
            _caller(state),
            RescueRequest({
                asset: address(l.asset),
                recipient: _recipient(l, selection.owner),
                destination: address(0),
                amount: amount_
            }),
            failure,
            failure
        );
        assertTrue(vm.revertToState(snapshot), "restore invalid input fixture");
    }

    /// @notice Kernel, self and token destinations use the same error as zero, before amount checks.
    // Scenarios: RD-I06.
    function test_invalidInputs_whenDestinationIsForbidden_reverts(
        uint256 choice_,
        uint256 amount_,
        uint8 state_
    ) public {
        uint256 snapshot = vm.snapshotState();
        uint8 state = uint8(bound(state_, 0, _LIFECYCLE_STATE_COUNT - 1));
        Selection memory selection = _invalidSelection(
            bound(choice_, 0, _INVALID_SELECTION_COUNT - 1)
        );
        Ledger memory l = _createInvalidInputLedger(selection);
        _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);

        address[3] memory destinations = [address(kernel), address(distributor), address(l.asset)];
        for (uint256 d; d < destinations.length; ++d) {
            address destination = destinations[d];
            bytes memory failure = abi.encodeWithSelector(
                IRevenueDistributorRescue.RevenueDistributor_InvalidRescueDestination.selector,
                destination
            );
            _assertInvalidRescueRequest(
                l,
                _caller(state),
                RescueRequest({
                    asset: address(l.asset),
                    recipient: _recipient(l, selection.owner),
                    destination: destination,
                    amount: amount_
                }),
                failure,
                failure
            );
        }
        assertTrue(vm.revertToState(snapshot), "restore invalid input fixture");
    }

    /// @notice A zero original recipient cannot access any globally recorded role entitlement.
    // Scenarios: RD-I03.
    function test_invalidInputs_whenRecipientIsZero_reverts(
        uint256 choice_,
        uint256 amount_,
        uint8 state_
    ) public {
        uint256 snapshot = vm.snapshotState();
        uint8 state = uint8(bound(state_, 0, _LIFECYCLE_STATE_COUNT - 1));
        Selection memory selection = _invalidSelection(
            bound(choice_, 0, _INVALID_SELECTION_COUNT - 1)
        );
        Ledger memory l = _createInvalidInputLedger(selection);
        _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);

        bytes memory failure = abi.encodeWithSelector(
            IRevenueDistributor.RevenueDistributor_InvalidRecipient.selector,
            address(0)
        );
        _assertInvalidRescueRequest(
            l,
            _caller(state),
            RescueRequest({
                asset: address(l.asset),
                recipient: address(0),
                destination: bob,
                amount: amount_
            }),
            failure,
            failure
        );
        assertTrue(vm.revertToState(snapshot), "restore invalid input fixture");
    }

    /// @notice Zero amount rejects empty and populated entitlement alike.
    // Scenarios: RD-I04.
    function test_invalidInputs_whenAmountIsZero_reverts(uint256 choice_, uint8 state_) public {
        uint256 snapshot = vm.snapshotState();
        uint8 state = uint8(bound(state_, 0, _LIFECYCLE_STATE_COUNT - 1));
        Selection memory selection = _invalidSelection(
            bound(choice_, 0, _INVALID_SELECTION_COUNT - 1)
        );
        Ledger memory l = _createInvalidInputLedger(selection);
        _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);

        bytes memory failure = abi.encodeWithSelector(
            IRevenueDistributorRescue.RevenueDistributor_InvalidRescueAmount.selector
        );
        _assertInvalidRescueRequest(
            l,
            _caller(state),
            RescueRequest({
                asset: address(l.asset),
                recipient: _recipient(l, selection.owner),
                destination: bob,
                amount: 0
            }),
            failure,
            failure
        );
        assertTrue(vm.revertToState(snapshot), "restore invalid input fixture");
    }

    /// @notice Fuzz exactly entitlement+1..MAX, including globally populated but ineligible buckets.
    // Scenarios: RD-I05.
    function test_invalidInputs_whenAmountExceedsEntitlement_reverts(
        uint256 choice_,
        uint256 amount_,
        uint8 state_
    ) public {
        uint256 snapshot = vm.snapshotState();
        uint8 state = uint8(bound(state_, 0, _LIFECYCLE_STATE_COUNT - 1));
        Selection memory selection = _invalidSelection(
            bound(choice_, 0, _INVALID_SELECTION_COUNT - 1)
        );
        Ledger memory l = _createInvalidInputLedger(selection);
        _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);
        uint256[3] memory eligible = _eligible(l, _recipient(l, selection.owner));
        uint256 entitlement = eligible[0] + eligible[1] + eligible[2];
        uint256 amount = bound(amount_, entitlement + 1, type(uint256).max);
        bytes memory failure = _insufficient(address(l.asset), amount, entitlement);
        _assertInvalidRescueRequest(
            l,
            _caller(state),
            RescueRequest({
                asset: address(l.asset),
                recipient: _recipient(l, selection.owner),
                destination: bob,
                amount: amount
            }),
            failure,
            failure
        );
        assertTrue(vm.revertToState(snapshot), "restore invalid input fixture");
    }

    // The combined invalid-input seed driver exceeded Foundry's EVM memory limit.
    // Separate fault drivers preserve every deterministic tuple without increasing that limit.
    /// @notice Guarantee all identity/presence and lifecycle combinations for this invalid input.
    // Scenarios: RD-I01.
    function test_invalidInputs_whenAssetIsZero_whenBoundariesAreSeeded() public {
        for (uint256 choice; choice < _INVALID_SELECTION_COUNT; ++choice)
            for (uint8 state; state < _LIFECYCLE_STATE_COUNT; ++state) {
                uint256[3] memory amounts = [uint256(0), 1, type(uint256).max];
                // Each external case has fresh EVM memory and exercises its named fuzz test.
                for (uint256 a; a < amounts.length; ++a)
                    this.test_invalidInputs_whenAssetIsZero_reverts(choice, amounts[a], state);
            }
    }

    /// @notice Guarantee all identity/presence and lifecycle combinations for this invalid input.
    // Scenarios: RD-I01.
    function test_invalidInputs_whenAssetHasNoCode_whenBoundariesAreSeeded() public {
        for (uint256 choice; choice < _INVALID_SELECTION_COUNT; ++choice)
            for (uint8 state; state < _LIFECYCLE_STATE_COUNT; ++state) {
                uint256[3] memory amounts = [uint256(0), 1, type(uint256).max];
                // Each external case has fresh EVM memory and exercises its named fuzz test.
                for (uint256 a; a < amounts.length; ++a)
                    this.test_invalidInputs_whenAssetHasNoCode_reverts(choice, amounts[a], state);
            }
    }

    /// @notice Guarantee all identity/presence and lifecycle combinations for this invalid input.
    // Scenarios: RD-I02.
    function test_invalidInputs_whenDestinationIsZero_whenBoundariesAreSeeded() public {
        for (uint256 choice; choice < _INVALID_SELECTION_COUNT; ++choice)
            for (uint8 state; state < _LIFECYCLE_STATE_COUNT; ++state) {
                uint256[3] memory amounts = [uint256(0), 1, type(uint256).max];
                // Each external case has fresh EVM memory and exercises its named fuzz test.
                for (uint256 a; a < amounts.length; ++a)
                    this.test_invalidInputs_whenDestinationIsZero_reverts(
                        choice,
                        amounts[a],
                        state
                    );
            }
    }

    /// @notice Guarantee all identity/presence and lifecycle combinations for this invalid input.
    // Scenarios: RD-I06.
    function test_invalidInputs_whenDestinationIsForbidden_whenBoundariesAreSeeded() public {
        for (uint256 choice; choice < _INVALID_SELECTION_COUNT; ++choice)
            for (uint8 state; state < _LIFECYCLE_STATE_COUNT; ++state) {
                uint256[3] memory amounts = [uint256(0), 1, type(uint256).max];
                // Each external case has fresh EVM memory and exercises its named fuzz test.
                for (uint256 a; a < amounts.length; ++a)
                    this.test_invalidInputs_whenDestinationIsForbidden_reverts(
                        choice,
                        amounts[a],
                        state
                    );
            }
    }

    /// @notice Guarantee all identity/presence and lifecycle combinations for this invalid input.
    // Scenarios: RD-I03.
    function test_invalidInputs_whenRecipientIsZero_whenBoundariesAreSeeded() public {
        for (uint256 choice; choice < _INVALID_SELECTION_COUNT; ++choice)
            for (uint8 state; state < _LIFECYCLE_STATE_COUNT; ++state) {
                uint256[3] memory amounts = [uint256(0), 1, type(uint256).max];
                // Each external case has fresh EVM memory and exercises its named fuzz test.
                for (uint256 a; a < amounts.length; ++a)
                    this.test_invalidInputs_whenRecipientIsZero_reverts(choice, amounts[a], state);
            }
    }

    /// @notice Guarantee all identity/presence and lifecycle combinations for this invalid input.
    // Scenarios: RD-I04.
    function test_invalidInputs_whenAmountIsZero_whenBoundariesAreSeeded() public {
        for (uint256 choice; choice < _INVALID_SELECTION_COUNT; ++choice)
            for (uint8 state; state < _LIFECYCLE_STATE_COUNT; ++state) {
                this.test_invalidInputs_whenAmountIsZero_reverts(choice, state);
            }
    }

    /// @notice Guarantee all identity/presence and lifecycle combinations for this invalid input.
    // Scenarios: RD-I05.
    function test_invalidInputs_whenAmountExceedsEntitlement_whenBoundariesAreSeeded() public {
        for (uint256 choice; choice < _INVALID_SELECTION_COUNT; ++choice)
            for (uint8 state; state < _LIFECYCLE_STATE_COUNT; ++state) {
                Selection memory selection = _invalidSelection(choice);
                uint256[3] memory eligible = _eligibleAt(
                    selection.layoutId,
                    selection.mask,
                    selection.owner
                );
                uint256[2] memory amounts = [
                    eligible[0] + eligible[1] + eligible[2] + 1,
                    type(uint256).max
                ];
                // Each external case has fresh EVM memory and exercises its named fuzz test.
                for (uint256 a; a < amounts.length; ++a)
                    this.test_invalidInputs_whenAmountExceedsEntitlement_reverts(
                        choice,
                        amounts[a],
                        state
                    );
            }
    }

    /// @notice Invalid destinations win over zero recipient and invalid amount, with distinct errors.
    // Scenarios: RD-I08.
    function test_invalidInputs_whenInvalidDestinationAndZeroRecipientCompete_reverts() public {
        uint256[3] memory amounts = [uint256(0), 1, type(uint256).max];
        for (uint8 state; state < 8; ++state) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.All, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);
            address[4] memory destinations = [
                address(0),
                address(kernel),
                address(distributor),
                address(l.asset)
            ];
            for (uint256 d; d < destinations.length; ++d)
                for (uint256 a; a < amounts.length; ++a) {
                    bytes memory failure = abi.encodeWithSelector(
                        IRevenueDistributorRescue
                            .RevenueDistributor_InvalidRescueDestination
                            .selector,
                        destinations[d]
                    );
                    _assertInvalidRescueRequest(
                        l,
                        _caller(state),
                        RescueRequest({
                            asset: address(l.asset),
                            recipient: address(0),
                            destination: destinations[d],
                            amount: amounts[a]
                        }),
                        failure,
                        failure
                    );
                }
            assertTrue(vm.revertToState(snapshot), "restore competing input faults");
        }
    }

    /// @notice Authorized calls and permissionless previews cross local, Kernel, listing and input gates.
    // Scenarios: RD-L01.
    function test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls() public {
        for (uint256 retired; retired < 2; ++retired) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, retired != 0, false);
            _assertSuccess(l, admin, l.routeOwner, bob, 1, [uint256(1), 0, 0]);
            assertTrue(vm.revertToState(snapshot), "restore asset listing fixture");
        }
    }

    // Scenarios: RD-L01.
    function test_authorization_givenEnabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts()
        public
    {
        for (uint256 retired; retired < 2; ++retired) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, retired != 0, false);
            _assertAuthorizedInputFailures(l, admin);
            assertTrue(vm.revertToState(snapshot), "restore asset listing fixture");
        }
    }

    // Scenarios: RD-L03.
    function test_authorization_givenEnabled_givenPolicyInactive_whenAdminCalls_reverts() public {
        for (uint256 retired; retired < 2; ++retired) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, retired != 0, false);
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
            _assertInactiveRequests(
                l,
                admin,
                abi.encodeWithSelector(
                    IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
                )
            );
            assertTrue(vm.revertToState(snapshot), "restore asset listing fixture");
        }
    }

    // Scenarios: RD-L06.
    function test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls() public {
        for (uint256 retired; retired < 2; ++retired) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, retired != 0, true);
            _assertSuccess(l, admin, l.routeOwner, bob, 1, [uint256(1), 0, 0]);
            assertTrue(vm.revertToState(snapshot), "restore asset listing fixture");
        }
    }

    // Scenarios: RD-L06.
    function test_authorization_givenDisabled_givenPolicyActive_whenAdminCalls_whenInputsInvalid_reverts()
        public
    {
        for (uint256 retired; retired < 2; ++retired) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, retired != 0, true);
            _assertAuthorizedInputFailures(l, admin);
            assertTrue(vm.revertToState(snapshot), "restore asset listing fixture");
        }
    }

    // Scenarios: RD-L07.
    function test_authorization_givenDisabled_givenPolicyInactive_whenAdminCalls_reverts() public {
        for (uint256 retired; retired < 2; ++retired) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, retired != 0, true);
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
            _assertInactiveRequests(
                l,
                admin,
                abi.encodeWithSelector(
                    IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
                )
            );
            assertTrue(vm.revertToState(snapshot), "restore asset listing fixture");
        }
    }

    // Scenarios: RD-L01.
    function test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls() public {
        for (uint256 retired; retired < 2; ++retired) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, retired != 0, false);
            _assertSuccess(l, address(configTimelock), l.routeOwner, bob, 1, [uint256(1), 0, 0]);
            assertTrue(vm.revertToState(snapshot), "restore asset listing fixture");
        }
    }

    // Scenarios: RD-L01.
    function test_authorization_givenEnabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts()
        public
    {
        for (uint256 retired; retired < 2; ++retired) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, retired != 0, false);
            _assertAuthorizedInputFailures(l, address(configTimelock));
            assertTrue(vm.revertToState(snapshot), "restore asset listing fixture");
        }
    }

    // Scenarios: RD-L03.
    function test_authorization_givenEnabled_givenPolicyInactive_whenOperatorCalls_reverts()
        public
    {
        for (uint256 retired; retired < 2; ++retired) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, retired != 0, false);
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
            _assertInactiveRequests(
                l,
                address(configTimelock),
                abi.encodeWithSelector(
                    IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
                )
            );
            assertTrue(vm.revertToState(snapshot), "restore asset listing fixture");
        }
    }

    // Scenarios: RD-L06.
    function test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls() public {
        for (uint256 retired; retired < 2; ++retired) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, retired != 0, true);
            _assertSuccess(l, address(configTimelock), l.routeOwner, bob, 1, [uint256(1), 0, 0]);
            assertTrue(vm.revertToState(snapshot), "restore asset listing fixture");
        }
    }

    // Scenarios: RD-L06.
    function test_authorization_givenDisabled_givenPolicyActive_whenOperatorCalls_whenInputsInvalid_reverts()
        public
    {
        for (uint256 retired; retired < 2; ++retired) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, retired != 0, true);
            _assertAuthorizedInputFailures(l, address(configTimelock));
            assertTrue(vm.revertToState(snapshot), "restore asset listing fixture");
        }
    }

    // Scenarios: RD-L07.
    function test_authorization_givenDisabled_givenPolicyInactive_whenOperatorCalls_reverts()
        public
    {
        for (uint256 retired; retired < 2; ++retired) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, retired != 0, true);
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
            _assertInactiveRequests(
                l,
                address(configTimelock),
                abi.encodeWithSelector(
                    IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
                )
            );
            assertTrue(vm.revertToState(snapshot), "restore asset listing fixture");
        }
    }

    /// @notice Unauthorized execution fails before policy/input checks; preview uses the same fuzzed caller.
    // Scenarios: RD-L02.
    function test_authorization_whenCallerIsUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != admin && caller_ != address(configTimelock));
        _assertUnauthorizedAcrossLifecycle(caller_);
    }

    /// @notice Guarantee role-only, emergency-only, former-operator, payout-owner and zero caller classes.
    // Scenarios: RD-L02.
    function test_authorization_whenUnauthorizedIdentitiesAreSeeded_reverts() public {
        address roleOnly = makeAddr("revenue admin only");
        address former = makeAddr("former config operator");
        vm.startPrank(admin);
        rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, roleOnly);
        distributor.setConfigOperator(former);
        distributor.setConfigOperator(address(configTimelock));
        vm.stopPrank();
        address[5] memory callers = [roleOnly, emergency, former, alice, address(0)];
        for (uint256 c; c < callers.length; ++c) _assertUnauthorizedAcrossLifecycle(callers[c]);
    }

    /// @notice NeverListed custody is surplus, not entitlement, for both callers and local states.
    // Scenarios: RD-I07.
    function test_givenNeverListedAsset_whenPendingPayoutRequested_reverts(uint256 amount_) public {
        amount_ = bound(amount_, 1, type(uint256).max);
        uint256[3] memory amounts = [uint256(1), amount_, type(uint256).max];
        for (uint256 disabled; disabled < 2; ++disabled) {
            for (uint256 surplus; surplus < 2; ++surplus) {
                uint256 snapshot = vm.snapshotState();
                if (surplus != 0) token.mint(address(distributor), 5);
                if (disabled != 0) {
                    vm.prank(admin);
                    distributor.disable("");
                }
                address[2] memory callers = [admin, address(configTimelock)];
                for (uint256 c; c < callers.length; ++c) {
                    for (uint256 a; a < amounts.length; ++a) {
                        bytes memory failure = _insufficient(address(token), amounts[a], 0);
                        vm.expectRevert(failure);
                        vm.prank(callers[c]);
                        distributor.previewRescuePendingPayout(
                            address(token),
                            alice,
                            bob,
                            amounts[a]
                        );
                        vm.expectRevert(failure);
                        vm.prank(callers[c]);
                        distributor.rescuePendingPayout(address(token), alice, bob, amounts[a]);
                        assertEq(
                            token.balanceOf(address(distributor)),
                            surplus == 0 ? 0 : 5,
                            "never-listed custody unchanged"
                        );
                        assertEq(token.balanceOf(bob), 0, "never-listed request pays nothing");
                        assertEq(
                            distributor.totalPendingForTest(address(token)),
                            0,
                            "never-listed token has no debt"
                        );
                        assertFalse(
                            distributor.pendingAssetMemberForTest(address(token)),
                            "never-listed token absent from pending index"
                        );
                    }
                }
                assertTrue(vm.revertToState(snapshot), "restore never-listed state");
            }
        }
    }

    /// @notice Every compatible eligible split can fund and rescue the exact uint256 maximum.
    // Scenarios: RD-P03.
    // Explicit finite partitions keep the expected allocation visible in this action test.
    // forge-lint: disable-next-line(cyclomatic-complexity)
    function test_numericExtremes_whenMaximumIsRescued() public {
        for (uint256 layoutId; layoutId <= uint256(Layout.All); ++layoutId) {
            for (uint8 mask = 1; mask < 8; ++mask) {
                for (uint8 owner; owner < 3; ++owner) {
                    uint256[3] memory eligible = _eligibleAt(Layout(layoutId), mask, owner);
                    uint256 globallyOwed = (mask & _ROUTE == 0 ? 0 : 10) +
                        (mask & _REPURCHASE == 0 ? 0 : 20) +
                        (mask & _TREASURY == 0 ? 0 : 30);
                    if (eligible[0] + eligible[1] + eligible[2] != globallyOwed) continue; // MAX cannot coexist with positive ineligible debt in the same token.
                    for (uint8 state; state < 8; ++state) {
                        uint256 snapshot = vm.snapshotState();
                        Ledger memory l = _configureLayout(
                            Layout(layoutId),
                            new MockRevertingTransferToken(18)
                        );
                        uint256 count = (eligible[0] == 0 ? 0 : 1) +
                            (eligible[1] == 0 ? 0 : 1) +
                            (eligible[2] == 0 ? 0 : 1);
                        uint256 remaining = type(uint256).max;
                        uint256[3] memory paid;
                        for (uint256 b; b < 3; ++b)
                            if (eligible[b] != 0) {
                                paid[b] = count == 1 ? remaining : 1;
                                remaining -= paid[b];
                                --count;
                            }
                        l.route = paid[0];
                        l.repurchase = paid[1];
                        l.treasuryDebt = paid[2];
                        _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);
                        _assertSuccess(
                            l,
                            _caller(state),
                            _recipient(l, owner),
                            bob,
                            type(uint256).max,
                            paid
                        );
                        assertTrue(vm.revertToState(snapshot), "restore maximum split");
                    }
                }
            }
        }
    }

    /// @notice Vary positive quantities while keeping the aggregate solvent and representable.
    // Scenarios: RD-N02.
    function test_numericExtremes_givenAllRolesOverlap_whenQuantitiesVary(
        uint256 route_,
        uint256 repurchase_,
        uint256 treasury_,
        uint256 amount_,
        uint8 state_
    ) public {
        route_ = bound(route_, 1, type(uint256).max - 2);
        repurchase_ = bound(repurchase_, 1, type(uint256).max - route_ - 1);
        treasury_ = bound(treasury_, 1, type(uint256).max - route_ - repurchase_);
        _numericCase(route_, repurchase_, treasury_, amount_, uint8(bound(state_, 0, 7)));
    }

    /// @notice Guarantee cumulative caps/adjacent values for tiny and maximum funded splits.
    // Scenarios: RD-N02.
    function test_numericExtremes_whenQuantityBoundariesAreSeeded() public {
        for (uint8 state; state < 8; ++state) {
            uint256[2] memory routes = [uint256(1), type(uint256).max - 2];
            for (uint256 r; r < routes.length; ++r) {
                uint256[5] memory amounts = [
                    uint256(1),
                    routes[r],
                    routes[r] + 1,
                    routes[r] + 2,
                    routes[r] > 1 ? routes[r] - 1 : 1
                ];
                for (uint256 a; a < amounts.length; ++a)
                    _numericCase(routes[r], 1, 1, amounts[a], state);
            }
        }
    }

    /// @notice A zero amount is invalid even with MAX entitlement.
    // Scenarios: RD-N03.
    function test_numericExtremes_givenEntitlementBoundaries_whenAmountIsZero_reverts() public {
        uint256[4] memory entitlements = [uint256(0), 1, type(uint256).max - 1, type(uint256).max];
        for (uint8 state; state < 8; ++state)
            for (uint256 e; e < entitlements.length; ++e) {
                uint256 snapshot = vm.snapshotState();
                Ledger memory l = _configureLayout(
                    Layout.Distinct,
                    new MockRevertingTransferToken(18)
                );
                l.route = entitlements[e];
                _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);
                bytes memory failure = abi.encodeWithSelector(
                    IRevenueDistributorRescue.RevenueDistributor_InvalidRescueAmount.selector
                );
                _assertFailure(l, _caller(state), l.routeOwner, bob, 0, failure, failure);
                assertTrue(vm.revertToState(snapshot), "restore zero-amount boundary fixture");
            }
    }

    // Scenarios: RD-N03.
    // Positive entitlements 1/MAX-1/MAX; rescue 1 or E with route-only allocation.
    function test_numericExtremes_givenEntitlementBoundaries_whenValidAmountIsRescued() public {
        uint256[3] memory entitlements = [uint256(1), type(uint256).max - 1, type(uint256).max];
        for (uint8 state; state < 8; ++state)
            for (uint256 e; e < entitlements.length; ++e) {
                uint256[2] memory amounts = [uint256(1), entitlements[e]];
                for (uint256 a; a < amounts.length; ++a) {
                    uint256 snapshot = vm.snapshotState();
                    Ledger memory l = _configureLayout(
                        Layout.Distinct,
                        new MockRevertingTransferToken(18)
                    );
                    l.route = entitlements[e];
                    _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);
                    _assertSuccess(
                        l,
                        _caller(state),
                        l.routeOwner,
                        bob,
                        amounts[a],
                        [amounts[a], uint256(0), 0]
                    );
                    assertTrue(vm.revertToState(snapshot), "restore valid amount boundary fixture");
                }
            }
    }

    // Scenarios: RD-N03.
    // Entitlements 0/1/MAX-1; amounts E+1 and MAX always exceed the selected debt.
    function test_numericExtremes_givenEntitlementBoundaries_whenAmountExceedsEntitlement_reverts()
        public
    {
        uint256[3] memory entitlements = [uint256(0), 1, type(uint256).max - 1];
        for (uint8 state; state < 8; ++state)
            for (uint256 e; e < entitlements.length; ++e) {
                uint256[2] memory amounts = [entitlements[e] + 1, type(uint256).max];
                for (uint256 a; a < amounts.length; ++a) {
                    uint256 snapshot = vm.snapshotState();
                    Ledger memory l = _configureLayout(
                        Layout.Distinct,
                        new MockRevertingTransferToken(18)
                    );
                    l.route = entitlements[e];
                    _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);
                    bytes memory failure = _insufficient(
                        address(l.asset),
                        amounts[a],
                        entitlements[e]
                    );
                    _assertFailure(
                        l,
                        _caller(state),
                        l.routeOwner,
                        bob,
                        amounts[a],
                        failure,
                        failure
                    );
                    assertTrue(
                        vm.revertToState(snapshot),
                        "restore excessive amount boundary fixture"
                    );
                }
            }
    }

    /// @notice Destination classes never change whose debt is debited, including other owed recipients.
    // Scenarios: RD-P05.
    function test_whenPermittedDestinationsAreSeeded() public {
        for (uint256 layoutId; layoutId <= uint256(Layout.All); ++layoutId) {
            for (uint8 state; state < 8; ++state) {
                for (uint8 destination; destination < 8; ++destination) {
                    uint256 snapshot = vm.snapshotState();
                    Ledger memory l = _ordinaryQuantities(
                        _configureLayout(Layout(layoutId), new MockRevertingTransferToken(18)),
                        7
                    );
                    l.otherRoute = 7;
                    l.otherAssetDebt = 9;
                    l.surplus = 5;
                    _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);
                    address[8] memory destinations = [
                        l.routeOwner,
                        l.otherOwner,
                        admin,
                        address(configTimelock),
                        l.yieldOwner,
                        l.treasuryOwner,
                        bob,
                        address(l.otherAsset)
                    ];
                    _assertSuccess(
                        l,
                        _caller(state),
                        l.routeOwner,
                        destinations[destination],
                        4,
                        [uint256(4), 0, 0]
                    );
                    assertTrue(vm.revertToState(snapshot), "restore destination classification");
                }
            }
        }
    }

    /// @notice A forbidden destination classification must not exclude the same address as an original owner.
    // Scenarios: RD-P05, RD-I06.
    function test_givenTokenOwnsDebt_whenRescued() public {
        uint256 snapshot = vm.snapshotState();
        Ledger memory l = _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18));
        l.routeOwner = address(l.asset);
        _setSingleRoute(address(l.asset), l.routeOwner);
        l.route = 10;
        _fundLedger(l, false, false);
        _assertSuccess(l, admin, l.routeOwner, bob, 4, [uint256(4), 0, 0]);
        assertTrue(vm.revertToState(snapshot), "restore owner classification");
    }

    // Scenarios: RD-P05, RD-I06.
    function test_givenAdminOwnsDebt_whenRescued() public {
        uint256 snapshot = vm.snapshotState();
        Ledger memory l = _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18));
        l.routeOwner = admin;
        _setSingleRoute(address(l.asset), l.routeOwner);
        l.route = 10;
        _fundLedger(l, false, false);
        _assertSuccess(l, admin, l.routeOwner, bob, 4, [uint256(4), 0, 0]);
        assertTrue(vm.revertToState(snapshot), "restore owner classification");
    }

    // Scenarios: RD-P05, RD-I06.
    function test_givenOperatorOwnsDebt_whenRescued() public {
        uint256 snapshot = vm.snapshotState();
        Ledger memory l = _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18));
        l.routeOwner = address(configTimelock);
        _setSingleRoute(address(l.asset), l.routeOwner);
        l.route = 10;
        _fundLedger(l, false, false);
        _assertSuccess(l, admin, l.routeOwner, bob, 4, [uint256(4), 0, 0]);
        assertTrue(vm.revertToState(snapshot), "restore owner classification");
    }

    /// @notice A representative delivery failure and insufficient custody preserve debts/indexes/config.
    // Scenarios: RD-X01.
    function test_givenValidPreview_whenTokenRejectsTransfer_reverts() public {
        for (uint8 state; state < 8; ++state) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.All, new MockRevertingTransferToken(18)),
                7
            );
            l.otherRoute = 7;
            l.otherAssetDebt = 9;
            l.surplus = 5;
            _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);
            bytes memory failure;

            MockRevertingTransferToken(address(l.asset)).setTransferReverts(bob, true);
            failure = abi.encodeWithSelector(
                MockRevertingTransferToken.TransferReverted.selector,
                bob
            );

            _assertFailure(l, _caller(state), l.routeOwner, bob, 35, "", failure);
            assertTrue(vm.revertToState(snapshot), "restore failed transfer");
        }
    }

    // Scenarios: RD-X01.
    function test_givenValidPreview_whenCustodyIsInsufficient_reverts() public {
        for (uint8 state; state < 8; ++state) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.All, new MockRevertingTransferToken(18)),
                7
            );
            l.otherRoute = 7;
            l.otherAssetDebt = 9;
            l.surplus = 5;
            _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);
            bytes memory failure;

            l.asset.burn(address(distributor), l.asset.balanceOf(address(distributor)));
            failure = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(distributor),
                0,
                35
            );

            _assertFailure(l, _caller(state), l.routeOwner, bob, 35, "", failure);
            assertTrue(vm.revertToState(snapshot), "restore failed transfer");
        }
    }

    /// @notice Rotation and clearing revoke prior operators while preserving direct admin authority.
    // Scenarios: RD-L04.
    function test_givenOperatorRotated_whenFormerOperatorRescues_reverts() public {
        address replacement = makeAddr("replacement operator");
        for (uint256 disabled; disabled < 2; ++disabled) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, false, false);
            vm.startPrank(admin);
            distributor.setConfigOperator(replacement);

            if (disabled != 0) distributor.disable("");
            vm.stopPrank();
            bytes memory unauthorized = abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                address(configTimelock)
            );
            _assertFailure(l, address(configTimelock), l.routeOwner, bob, 4, "", unauthorized);

            assertTrue(vm.revertToState(snapshot), "restore former operator fixture");
        }
    }

    // Scenarios: RD-L04.
    function test_givenOperatorRotated_whenCurrentAuthorityRescues() public {
        address replacement = makeAddr("replacement operator");
        for (uint256 disabled; disabled < 2; ++disabled) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, false, false);
            vm.startPrank(admin);
            distributor.setConfigOperator(replacement);

            if (disabled != 0) distributor.disable("");
            vm.stopPrank();
            address[2] memory callers = [admin, replacement];
            for (uint256 c; c < callers.length; ++c) {
                uint256 paymentSnapshot = vm.snapshotState();
                _assertSuccess(l, callers[c], l.routeOwner, bob, 4, [uint256(4), 0, 0]);
                assertTrue(vm.revertToState(paymentSnapshot), "restore independent payment");
            }
            assertTrue(vm.revertToState(snapshot), "restore current authority fixture");
        }
    }

    // Scenarios: RD-L04.
    function test_givenOperatorRevoked_whenFormerOperatorRescues_reverts() public {
        address replacement = makeAddr("replacement operator");
        for (uint256 disabled; disabled < 2; ++disabled) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, false, false);
            vm.startPrank(admin);
            distributor.setConfigOperator(replacement);
            distributor.setConfigOperator(address(0));
            if (disabled != 0) distributor.disable("");
            vm.stopPrank();
            bytes memory unauthorized = abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                address(configTimelock)
            );
            _assertFailure(l, address(configTimelock), l.routeOwner, bob, 4, "", unauthorized);
            _assertFailure(
                l,
                replacement,
                l.routeOwner,
                bob,
                4,
                "",
                abi.encodeWithSelector(
                    IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                    replacement
                )
            );
            assertTrue(vm.revertToState(snapshot), "restore former operator fixture");
        }
    }

    // Scenarios: RD-L04.
    function test_givenOperatorRevoked_whenAdminRescues() public {
        address replacement = makeAddr("replacement operator");
        for (uint256 disabled; disabled < 2; ++disabled) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, false, false);
            vm.startPrank(admin);
            distributor.setConfigOperator(replacement);
            distributor.setConfigOperator(address(0));
            if (disabled != 0) distributor.disable("");
            vm.stopPrank();
            _assertSuccess(l, admin, l.routeOwner, bob, 4, [uint256(4), 0, 0]);
            assertTrue(vm.revertToState(snapshot), "restore current authority fixture");
        }
    }

    /// @notice Fixed debt survives route removal; role debt follows rotation, fallback and Treasury upgrade.
    // Scenarios: RD-P04.
    function test_givenRouteRemoved_whenHistoricalAndCurrentEntitlementsAreRescued() public {
        for (uint8 state; state < 8; ++state) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, false, false);
            vm.startPrank(admin);
            distributor.setAssetRoutes(
                address(l.asset),
                0,
                new IRevenueDistributor.AssetRoute[](0)
            );
            if (state & _RETIRED != 0) distributor.disableAssetRoutes(address(l.asset));
            if (state & _DISABLED != 0) distributor.disable("");
            vm.stopPrank();
            _assertLedger(l, 10, 20, 30);

            // Fixed-address historical debt is always retained, independently of role transitions.
            uint256 paymentSnapshot = vm.snapshotState();
            _assertSuccess(l, _caller(state), l.routeOwner, bob, 4, [uint256(4), 0, 0]);
            assertTrue(vm.revertToState(paymentSnapshot), "restore historical payment");

            assertTrue(vm.revertToState(snapshot), "restore recipient transition");
        }
    }

    // Scenarios: RD-P04.
    function test_givenYieldRecipientRotated_whenFormerRoleRecipientRescues_reverts() public {
        for (uint8 state; state < 8; ++state) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, false, false);
            address oldOwner = l.yieldOwner;
            address nextYield = address(_newYieldRecipient(address(l.asset)));
            vm.startPrank(admin);
            distributor.setYieldRecipient(nextYield);
            l.yieldOwner = nextYield;

            if (state & _RETIRED != 0) distributor.disableAssetRoutes(address(l.asset));
            if (state & _DISABLED != 0) distributor.disable("");
            vm.stopPrank();
            _assertLedger(l, 10, 20, 30);

            bytes memory failure = _insufficient(address(l.asset), 1, 0);
            _assertFailure(l, _caller(state), oldOwner, bob, 1, failure, failure);

            assertTrue(vm.revertToState(snapshot), "restore independent recipient transition");
        }
    }

    // Scenarios: RD-P04.
    function test_givenYieldRecipientRotated_whenHistoricalRouteRecipientRescues() public {
        for (uint8 state; state < 8; ++state) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, false, false);
            address nextYield = address(_newYieldRecipient(address(l.asset)));
            vm.startPrank(admin);
            distributor.setYieldRecipient(nextYield);
            l.yieldOwner = nextYield;

            if (state & _RETIRED != 0) distributor.disableAssetRoutes(address(l.asset));
            if (state & _DISABLED != 0) distributor.disable("");
            vm.stopPrank();
            _assertLedger(l, 10, 20, 30);

            _assertSuccess(l, _caller(state), l.routeOwner, bob, 4, [uint256(4), 0, 0]);
            assertTrue(vm.revertToState(snapshot), "restore independent recipient transition");
        }
    }

    // Scenarios: RD-P04.
    function test_givenYieldRecipientRotated_whenCurrentRoleRecipientRescues() public {
        for (uint8 state; state < 8; ++state) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, false, false);
            address nextYield = address(_newYieldRecipient(address(l.asset)));
            vm.startPrank(admin);
            distributor.setYieldRecipient(nextYield);
            l.yieldOwner = nextYield;

            if (state & _RETIRED != 0) distributor.disableAssetRoutes(address(l.asset));
            if (state & _DISABLED != 0) distributor.disable("");
            vm.stopPrank();
            _assertLedger(l, 10, 20, 30);

            _assertSuccess(l, _caller(state), l.yieldOwner, bob, 4, [uint256(0), 4, 0]);
            assertTrue(vm.revertToState(snapshot), "restore independent recipient transition");
        }
    }

    // Scenarios: RD-P04.
    function test_givenYieldRecipientCleared_whenFormerRoleRecipientRescues_reverts() public {
        for (uint8 state; state < 8; ++state) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, false, false);
            address oldOwner = l.yieldOwner;
            vm.startPrank(admin);

            distributor.setYieldRecipient(address(0));
            l.yieldOwner = l.treasuryOwner;

            if (state & _RETIRED != 0) distributor.disableAssetRoutes(address(l.asset));
            if (state & _DISABLED != 0) distributor.disable("");
            vm.stopPrank();
            _assertLedger(l, 10, 20, 30);

            bytes memory failure = _insufficient(address(l.asset), 1, 0);
            _assertFailure(l, _caller(state), oldOwner, bob, 1, failure, failure);

            assertTrue(vm.revertToState(snapshot), "restore independent recipient transition");
        }
    }

    // Scenarios: RD-P04.
    function test_givenYieldRecipientCleared_whenHistoricalRouteRecipientRescues() public {
        for (uint8 state; state < 8; ++state) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, false, false);
            vm.startPrank(admin);

            distributor.setYieldRecipient(address(0));
            l.yieldOwner = l.treasuryOwner;

            if (state & _RETIRED != 0) distributor.disableAssetRoutes(address(l.asset));
            if (state & _DISABLED != 0) distributor.disable("");
            vm.stopPrank();
            _assertLedger(l, 10, 20, 30);

            _assertSuccess(l, _caller(state), l.routeOwner, bob, 4, [uint256(4), 0, 0]);
            assertTrue(vm.revertToState(snapshot), "restore independent recipient transition");
        }
    }

    // Scenarios: RD-P04.
    function test_givenYieldRecipientCleared_whenCurrentRoleRecipientRescues() public {
        for (uint8 state; state < 8; ++state) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, false, false);
            vm.startPrank(admin);

            distributor.setYieldRecipient(address(0));
            l.yieldOwner = l.treasuryOwner;

            if (state & _RETIRED != 0) distributor.disableAssetRoutes(address(l.asset));
            if (state & _DISABLED != 0) distributor.disable("");
            vm.stopPrank();
            _assertLedger(l, 10, 20, 30);

            _assertSuccess(l, _caller(state), l.yieldOwner, bob, 4, [uint256(0), 4, 0]);
            assertTrue(vm.revertToState(snapshot), "restore independent recipient transition");
        }
    }

    // Scenarios: RD-P04.
    function test_givenTreasuryUpgraded_whenFormerRoleRecipientRescues_reverts() public {
        for (uint8 state; state < 8; ++state) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, false, false);
            address oldOwner = l.treasuryOwner;
            vm.startPrank(admin);

            OlympusTreasury nextTreasury = new OlympusTreasury(kernel);
            kernel.executeAction(Actions.UpgradeModule, address(nextTreasury));
            l.treasuryOwner = address(nextTreasury);

            if (state & _RETIRED != 0) distributor.disableAssetRoutes(address(l.asset));
            if (state & _DISABLED != 0) distributor.disable("");
            vm.stopPrank();
            _assertLedger(l, 10, 20, 30);

            bytes memory failure = _insufficient(address(l.asset), 1, 0);
            _assertFailure(l, _caller(state), oldOwner, bob, 1, failure, failure);

            assertTrue(vm.revertToState(snapshot), "restore independent recipient transition");
        }
    }

    // Scenarios: RD-P04.
    function test_givenTreasuryUpgraded_whenHistoricalRouteRecipientRescues() public {
        for (uint8 state; state < 8; ++state) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, false, false);
            vm.startPrank(admin);

            OlympusTreasury nextTreasury = new OlympusTreasury(kernel);
            kernel.executeAction(Actions.UpgradeModule, address(nextTreasury));
            l.treasuryOwner = address(nextTreasury);

            if (state & _RETIRED != 0) distributor.disableAssetRoutes(address(l.asset));
            if (state & _DISABLED != 0) distributor.disable("");
            vm.stopPrank();
            _assertLedger(l, 10, 20, 30);

            _assertSuccess(l, _caller(state), l.routeOwner, bob, 4, [uint256(4), 0, 0]);
            assertTrue(vm.revertToState(snapshot), "restore independent recipient transition");
        }
    }

    // Scenarios: RD-P04.
    function test_givenTreasuryUpgraded_whenCurrentRoleRecipientRescues() public {
        for (uint8 state; state < 8; ++state) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _ordinaryQuantities(
                _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                7
            );
            _fundLedger(l, false, false);
            vm.startPrank(admin);

            OlympusTreasury nextTreasury = new OlympusTreasury(kernel);
            kernel.executeAction(Actions.UpgradeModule, address(nextTreasury));
            l.treasuryOwner = address(nextTreasury);

            if (state & _RETIRED != 0) distributor.disableAssetRoutes(address(l.asset));
            if (state & _DISABLED != 0) distributor.disable("");
            vm.stopPrank();
            _assertLedger(l, 10, 20, 30);

            _assertSuccess(l, _caller(state), l.treasuryOwner, bob, 4, [uint256(0), 0, 4]);
            assertTrue(vm.revertToState(snapshot), "restore independent recipient transition");
        }
    }

    /// @notice Authorized nested writes hit the guard for independent asset/recipient choices.
    // Scenarios: RD-X02.
    function test_givenPendingRescueCallback_whenFailureIsCaught() public {
        uint256[2] memory amounts = [uint256(35), 60];
        for (uint8 state; state < 8; ++state)
            for (uint256 relation; relation < 4; ++relation)
                for (uint256 a; a < amounts.length; ++a)
                    _assertCaughtWriteCallback(state, 0, relation, amounts[a]);
    }

    // Scenarios: RD-X02.
    function test_givenPendingRescueCallback_whenFailureIsPropagated() public {
        uint256[2] memory amounts = [uint256(35), 60];
        for (uint8 state; state < 8; ++state)
            for (uint256 relation; relation < 4; ++relation)
                for (uint256 a; a < amounts.length; ++a)
                    _assertPropagatedWriteCallback(state, 0, relation, amounts[a]);
    }

    // Scenarios: RD-X02.
    function test_givenSurplusRescueCallback_whenFailureIsCaught() public {
        uint256[2] memory amounts = [uint256(35), 60];
        for (uint8 state; state < 8; ++state)
            for (uint256 relation; relation < 4; ++relation)
                for (uint256 a; a < amounts.length; ++a)
                    _assertCaughtWriteCallback(state, 1, relation, amounts[a]);
    }

    // Scenarios: RD-X02.
    function test_givenSurplusRescueCallback_whenFailureIsPropagated() public {
        uint256[2] memory amounts = [uint256(35), 60];
        for (uint8 state; state < 8; ++state)
            for (uint256 relation; relation < 4; ++relation)
                for (uint256 a; a < amounts.length; ++a)
                    _assertPropagatedWriteCallback(state, 1, relation, amounts[a]);
    }

    // Scenarios: RD-X02.
    function test_givenDistributeCallback_whenFailureIsCaught() public {
        uint256[2] memory amounts = [uint256(35), 60];
        for (uint8 state; state < 8; ++state)
            for (uint256 relation; relation < 4; ++relation)
                for (uint256 a; a < amounts.length; ++a)
                    _assertCaughtWriteCallback(state, 2, relation, amounts[a]);
    }

    // Scenarios: RD-X02.
    function test_givenDistributeCallback_whenFailureIsPropagated() public {
        uint256[2] memory amounts = [uint256(35), 60];
        for (uint8 state; state < 8; ++state)
            for (uint256 relation; relation < 4; ++relation)
                for (uint256 a; a < amounts.length; ++a)
                    _assertPropagatedWriteCallback(state, 2, relation, amounts[a]);
    }

    // Scenarios: RD-X02.
    function test_givenPendingRetryCallback_whenFailureIsCaught() public {
        uint256[2] memory amounts = [uint256(35), 60];
        for (uint8 state; state < 8; ++state)
            for (uint256 relation; relation < 4; ++relation)
                for (uint256 a; a < amounts.length; ++a)
                    _assertCaughtWriteCallback(state, 3, relation, amounts[a]);
    }

    // Scenarios: RD-X02.
    function test_givenPendingRetryCallback_whenFailureIsPropagated() public {
        uint256[2] memory amounts = [uint256(35), 60];
        for (uint8 state; state < 8; ++state)
            for (uint256 relation; relation < 4; ++relation)
                for (uint256 a; a < amounts.length; ++a)
                    _assertPropagatedWriteCallback(state, 3, relation, amounts[a]);
    }

    /// @notice Fuzz the partial outer amount independently of nested action/asset/recipient and failure handling.
    // Scenarios: RD-X02.
    function test_givenWriteCallback_whenFailureIsCaught(
        uint256 amount_,
        uint8 state_,
        uint8 action_,
        uint8 relation_
    ) public {
        _assertCaughtWriteCallback(
            uint8(bound(state_, 0, 7)),
            bound(action_, 0, 3),
            bound(relation_, 0, 3),
            bound(amount_, 1, 59)
        );
    }

    // Scenarios: RD-X02.
    function test_givenWriteCallback_whenFailureIsPropagated(
        uint256 amount_,
        uint8 state_,
        uint8 action_,
        uint8 relation_
    ) public {
        _assertPropagatedWriteCallback(
            uint8(bound(state_, 0, 7)),
            bound(action_, 0, 3),
            bound(relation_, 0, 3),
            bound(amount_, 1, 59)
        );
    }

    /// @notice Callback reads observe post-debit accounting/indexes and the single completed payment.
    // Scenarios: RD-X03.
    function test_givenReadCallback_whenPartialPayoutStateIsRead(uint256 amount_) public {
        amount_ = bound(amount_, 1, 59);

        for (uint8 state; state < 8; ++state) {
            uint256 snapshot = vm.snapshotState();
            ReentrantPayoutToken asset = new ReentrantPayoutToken();
            Ledger memory l = _ordinaryQuantities(_configureLayout(Layout.All, asset), 7);
            l.otherRoute = 7;
            l.otherAssetDebt = 9;
            l.surplus = 5;
            vm.prank(admin);
            distributor.setConfigOperator(address(asset));
            _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);
            RevenueDistributorRescueObserver observer = new RevenueDistributorRescueObserver();
            asset.setCallbackFrom(
                address(distributor),
                address(observer),
                abi.encodeCall(
                    observer.observe,
                    (distributor, IERC20(address(asset)), l.routeOwner, bob)
                )
            );
            _assertSuccess(
                l,
                state & _OPERATOR == 0 ? admin : address(asset),
                l.routeOwner,
                bob,
                amount_,
                _ordinaryOverlapDebits(amount_)
            );
            assertTrue(asset.callbackSucceeded(), "read-only callback succeeds");
            assertEq(observer.entitlement(), 60 - amount_, "callback reads post-debit entitlement");
            assertEq(
                observer.state(),
                observer.observation(distributor, IERC20(address(asset)), l.routeOwner, bob),
                "callback sees final raw/index/config/custody state"
            );
            assertEq(observer.preview(), 60 - amount_, "partial callback preview agrees");
            assertEq(observer.failure().length, 0, "partial preview succeeds");
            assertTrue(vm.revertToState(snapshot), "restore callback reads");
        }
    }

    // Scenarios: RD-X03.
    function test_givenReadCallback_whenOneUnitPayoutStateIsRead() public {
        for (uint8 state; state < 8; ++state) {
            uint256 snapshot = vm.snapshotState();
            ReentrantPayoutToken asset = new ReentrantPayoutToken();
            Ledger memory l = _ordinaryQuantities(_configureLayout(Layout.All, asset), 7);
            l.otherRoute = 7;
            l.otherAssetDebt = 9;
            l.surplus = 5;
            vm.prank(admin);
            distributor.setConfigOperator(address(asset));
            _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);
            RevenueDistributorRescueObserver observer = new RevenueDistributorRescueObserver();
            asset.setCallbackFrom(
                address(distributor),
                address(observer),
                abi.encodeCall(
                    observer.observe,
                    (distributor, IERC20(address(asset)), l.routeOwner, bob)
                )
            );
            _assertSuccess(
                l,
                state & _OPERATOR == 0 ? admin : address(asset),
                l.routeOwner,
                bob,
                uint256(1),
                _ordinaryOverlapDebits(uint256(1))
            );
            assertTrue(asset.callbackSucceeded(), "read-only callback succeeds");
            assertEq(observer.entitlement(), 59, "callback reads post-debit entitlement");
            assertEq(
                observer.state(),
                observer.observation(distributor, IERC20(address(asset)), l.routeOwner, bob),
                "callback sees final raw/index/config/custody state"
            );

            assertEq(observer.preview(), 59, "partial callback preview agrees");
            assertEq(observer.failure().length, 0, "partial preview succeeds");

            assertTrue(vm.revertToState(snapshot), "restore callback reads");
        }
    }

    // Scenarios: RD-CB04.
    function test_givenReadCallback_whenFullPayoutStateIsRead() public {
        for (uint8 state; state < 8; ++state) {
            uint256 snapshot = vm.snapshotState();
            ReentrantPayoutToken asset = new ReentrantPayoutToken();
            Ledger memory l = _ordinaryQuantities(_configureLayout(Layout.All, asset), 7);
            l.otherRoute = 7;
            l.otherAssetDebt = 9;
            l.surplus = 5;
            vm.prank(admin);
            distributor.setConfigOperator(address(asset));
            _fundLedger(l, state & _RETIRED != 0, state & _DISABLED != 0);
            RevenueDistributorRescueObserver observer = new RevenueDistributorRescueObserver();
            asset.setCallbackFrom(
                address(distributor),
                address(observer),
                abi.encodeCall(
                    observer.observe,
                    (distributor, IERC20(address(asset)), l.routeOwner, bob)
                )
            );
            _assertSuccess(
                l,
                state & _OPERATOR == 0 ? admin : address(asset),
                l.routeOwner,
                bob,
                60,
                _ordinaryOverlapDebits(60)
            );
            assertTrue(asset.callbackSucceeded(), "read-only callback succeeds");
            assertEq(observer.entitlement(), 0, "callback reads post-debit entitlement");
            assertEq(
                observer.state(),
                observer.observation(distributor, IERC20(address(asset)), l.routeOwner, bob),
                "callback sees final raw/index/config/custody state"
            );
            assertEq(
                observer.failure(),
                _insufficient(address(asset), 1, 0),
                "full drain callback catches exact preview error"
            );
            assertTrue(vm.revertToState(snapshot), "restore callback reads");
        }
    }

    /// @dev Outcome bits select independent partial/full (bit 0) and caught/propagated (bit 1) behavior.
    ///      Relation bits select nested other asset (bit 0) and other recipient (bit 1) independently.
    function _assertCaughtWriteCallback(
        uint8 state_,
        uint256 action_,
        uint256 relation_,
        uint256 amount_
    ) internal {
        uint256 snapshot = vm.snapshotState();
        ReentrantPayoutToken asset = new ReentrantPayoutToken();
        Ledger memory l = _ordinaryQuantities(_configureLayout(Layout.All, asset), 7);
        l.otherRoute = 7;
        l.otherAssetDebt = 9;
        l.surplus = 5;
        vm.prank(admin);
        distributor.setConfigOperator(address(asset));
        _fundLedger(l, state_ & _RETIRED != 0, state_ & _DISABLED != 0);
        address nestedAsset = relation_ & 1 == 0 ? address(asset) : address(l.otherAsset);
        address nestedRecipient = relation_ & 2 == 0 ? l.routeOwner : l.otherOwner;
        bytes memory callData;
        if (action_ == 0)
            callData = abi.encodeCall(
                distributor.rescuePendingPayout,
                (nestedAsset, nestedRecipient, emergency, 1)
            );
        else if (action_ == 1)
            callData = abi.encodeCall(distributor.rescue, (nestedAsset, emergency));
        else if (action_ == 2) callData = abi.encodeCall(distributor.distribute, (nestedAsset));
        else
            callData = abi.encodeCall(
                distributor.transferPendingPayout,
                (nestedAsset, nestedRecipient)
            );
        asset.setCallbackFrom(address(distributor), address(distributor), callData);

        asset.setBubbleCallbackFailure(false);
        uint256 amount = amount_;
        address caller = state_ & _OPERATOR == 0 ? admin : address(asset);

        _assertSuccess(l, caller, l.routeOwner, bob, amount, _ordinaryOverlapDebits(amount));
        assertFalse(asset.callbackEnabled(), "caught callback runs exactly once");
        assertFalse(asset.callbackSucceeded(), "nested write fails");
        assertEq(
            asset.callbackRevertData(),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
            "authorized nested call reaches exact guard"
        );

        assertEq(asset.balanceOf(emergency), 0, "nested action makes no payment");
        assertTrue(vm.revertToState(snapshot), "restore guarded callback");
    }

    function _assertPropagatedWriteCallback(
        uint8 state_,
        uint256 action_,
        uint256 relation_,
        uint256 amount_
    ) internal {
        uint256 snapshot = vm.snapshotState();
        ReentrantPayoutToken asset = new ReentrantPayoutToken();
        Ledger memory l = _ordinaryQuantities(_configureLayout(Layout.All, asset), 7);
        l.otherRoute = 7;
        l.otherAssetDebt = 9;
        l.surplus = 5;
        vm.prank(admin);
        distributor.setConfigOperator(address(asset));
        _fundLedger(l, state_ & _RETIRED != 0, state_ & _DISABLED != 0);
        address nestedAsset = relation_ & 1 == 0 ? address(asset) : address(l.otherAsset);
        address nestedRecipient = relation_ & 2 == 0 ? l.routeOwner : l.otherOwner;
        bytes memory callData;
        if (action_ == 0)
            callData = abi.encodeCall(
                distributor.rescuePendingPayout,
                (nestedAsset, nestedRecipient, emergency, 1)
            );
        else if (action_ == 1)
            callData = abi.encodeCall(distributor.rescue, (nestedAsset, emergency));
        else if (action_ == 2) callData = abi.encodeCall(distributor.distribute, (nestedAsset));
        else
            callData = abi.encodeCall(
                distributor.transferPendingPayout,
                (nestedAsset, nestedRecipient)
            );
        asset.setCallbackFrom(address(distributor), address(distributor), callData);

        asset.setBubbleCallbackFailure(true);
        uint256 amount = amount_;
        address caller = state_ & _OPERATOR == 0 ? admin : address(asset);

        _assertFailure(
            l,
            caller,
            l.routeOwner,
            bob,
            amount,
            "",
            abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector)
        );
        assertTrue(asset.callbackEnabled(), "propagated failure restores armed callback");
        assertFalse(asset.callbackSucceeded(), "propagated failure restores result");
        assertEq(asset.callbackRevertData().length, 0, "propagated failure restores callback data");

        assertEq(asset.balanceOf(emergency), 0, "nested action makes no payment");
        assertTrue(vm.revertToState(snapshot), "restore guarded callback");
    }

    /// @dev Explicit 10/20/30 fixture intervals; input is always 1..60, with no scaling or rounding.
    function _ordinaryOverlapDebits(
        uint256 amount_
    ) internal pure returns (uint256[3] memory paid) {
        if (amount_ <= 10) return [amount_, uint256(0), 0];
        if (amount_ <= 30) return [uint256(10), amount_ - 10, 0];
        return [uint256(10), 20, amount_ - 30];
    }

    /// @dev Select from explicitly compatible layoutId/mask/owner tuples; no incompatible fuzz case returns early.
    function _allocationFuzz(
        Allocation kind_,
        uint256 choice_,
        uint256 amount_,
        uint8 state_,
        uint8 isolation_
    ) internal {
        (Selection[] memory choices, uint256 count) = _allocationDomain(kind_);
        _allocationCase(
            kind_,
            choices[bound(choice_, 0, count - 1)],
            amount_,
            uint8(bound(state_, 0, 7)),
            uint8(bound(isolation_, 0, 7))
        );
    }

    /// @dev Exhaust every discrete compatible tuple, then exact interval endpoints and adjacent interior values.
    function _allocationSeeds(Allocation kind_) internal {
        (Selection[] memory choices, uint256 count) = _allocationDomain(kind_);
        for (uint256 c; c < count; ++c) {
            (uint256 minimum, uint256 maximum) = _bounds(
                kind_,
                _eligibleAt(choices[c].layoutId, choices[c].mask, choices[c].owner)
            );
            uint256[4] memory amounts = [
                minimum,
                maximum,
                minimum < maximum ? minimum + 1 : minimum,
                maximum > minimum ? maximum - 1 : maximum
            ];
            for (uint8 state; state < 8; ++state) {
                for (uint8 isolation; isolation < 8; ++isolation) {
                    for (uint256 a; a < amounts.length; ++a) {
                        bool duplicate;
                        for (uint256 prior; prior < a; ++prior)
                            if (amounts[prior] == amounts[a]) duplicate = true;
                        if (!duplicate)
                            _allocationCase(kind_, choices[c], amounts[a], state, isolation);
                    }
                }
            }
        }
    }

    /// @dev The raw ledger is immutable across a snapshot; expected paid values come from the named partition.
    function _allocationCase(
        Allocation kind_,
        Selection memory s,
        uint256 amountSeed_,
        uint8 state_,
        uint8 isolation_
    ) internal {
        uint256 snapshot = vm.snapshotState();
        Ledger memory l = _ordinaryQuantities(
            _configureLayout(s.layoutId, new MockRevertingTransferToken(18)),
            s.mask
        );
        l.otherRoute = isolation_ & _OTHER_ROUTE == 0 ? 0 : 7;
        l.otherAssetDebt = isolation_ & _OTHER_ASSET == 0 ? 0 : 9;
        l.surplus = isolation_ & _SURPLUS == 0 ? 0 : 5;
        _fundLedger(l, state_ & _RETIRED != 0, state_ & _DISABLED != 0);
        address recipient = _recipient(l, s.owner);
        uint256[3] memory e = _eligible(l, recipient);
        (uint256 minimum, uint256 maximum) = _bounds(kind_, e);
        uint256 amount = bound(amountSeed_, minimum, maximum);
        uint256[3] memory paid;
        if (kind_ == Allocation.Route) paid[0] = amount;
        else if (kind_ == Allocation.Repurchase) paid[1] = amount;
        else if (kind_ == Allocation.Treasury) paid[2] = amount;
        else if (kind_ == Allocation.RouteRepurchase) paid = [e[0], amount - e[0], uint256(0)];
        else if (kind_ == Allocation.RouteTreasury) paid = [e[0], uint256(0), amount - e[0]];
        else if (kind_ == Allocation.RepurchaseTreasury) paid = [uint256(0), e[1], amount - e[1]];
        else paid = [e[0], e[1], amount - e[0] - e[1]];
        _assertSuccess(l, _caller(state_), recipient, bob, amount, paid);
        if (amount == e[0] + e[1] + e[2]) {
            bytes memory failure = _insufficient(address(l.asset), 1, 0);
            vm.expectRevert(failure);
            distributor.previewRescuePendingPayout(address(l.asset), recipient, bob, 1);
            vm.expectRevert(failure);
            vm.prank(_caller(state_));
            distributor.rescuePendingPayout(address(l.asset), recipient, bob, 1);
        }
        assertTrue(vm.revertToState(snapshot), "restore allocation case");
    }

    /// @dev Bounds describe eligible allocation intervals only; zero denotes an incompatible tuple.
    function _bounds(
        Allocation kind_,
        uint256[3] memory e
    ) internal pure returns (uint256 minimum, uint256 maximum) {
        if (kind_ == Allocation.Route && e[0] != 0) return (1, e[0]);
        if (kind_ == Allocation.Repurchase && e[0] == 0 && e[1] != 0) return (1, e[1]);
        if (kind_ == Allocation.Treasury && e[0] == 0 && e[1] == 0 && e[2] != 0) return (1, e[2]);
        if (kind_ == Allocation.RouteRepurchase && e[0] != 0 && e[1] != 0)
            return (e[0] + 1, e[0] + e[1]);
        if (kind_ == Allocation.RouteTreasury && e[0] != 0 && e[1] == 0 && e[2] != 0)
            return (e[0] + 1, e[0] + e[2]);
        if (kind_ == Allocation.RepurchaseTreasury && e[0] == 0 && e[1] != 0 && e[2] != 0)
            return (e[1] + 1, e[1] + e[2]);
        if (kind_ == Allocation.All && e[0] != 0 && e[1] != 0 && e[2] != 0)
            return (e[0] + e[1] + 1, e[0] + e[1] + e[2]);
    }

    /// @dev Enumerate compatible semantic tuples once; duplicate owners represent identical constructed requests.
    function _allocationDomain(
        Allocation kind_
    ) internal pure returns (Selection[] memory choices, uint256 count) {
        choices = new Selection[](120);
        for (uint8 layoutId; layoutId <= uint8(Layout.All); ++layoutId) {
            for (uint8 mask; mask < 8; ++mask) {
                for (uint8 owner; owner < 3; ++owner) {
                    if (
                        (owner == 1 &&
                            (Layout(layoutId) == Layout.RouteYield ||
                                Layout(layoutId) == Layout.All)) ||
                        (owner == 2 &&
                            (Layout(layoutId) == Layout.RouteTreasury ||
                                Layout(layoutId) == Layout.YieldTreasury ||
                                Layout(layoutId) == Layout.All))
                    ) continue;
                    (uint256 minimum, ) = _bounds(
                        kind_,
                        _eligibleAt(Layout(layoutId), mask, owner)
                    );
                    if (minimum != 0)
                        choices[count++] = Selection({
                            layoutId: Layout(layoutId),
                            mask: mask,
                            owner: owner
                        });
                }
            }
        }
        assert(count != 0);
    }

    /// @dev Pure eligibility table for the documented five identity partitions and 10/20/30 globallyOwed buckets.
    function _eligibleAt(
        Layout layout_,
        uint8 mask_,
        uint8 owner_
    ) internal pure returns (uint256[3] memory e) {
        bool route = owner_ == 0 ||
            (owner_ == 1 && (layout_ == Layout.RouteYield || layout_ == Layout.All)) ||
            (owner_ == 2 && (layout_ == Layout.RouteTreasury || layout_ == Layout.All));
        bool repurchase = owner_ == 1 ||
            (owner_ == 0 && (layout_ == Layout.RouteYield || layout_ == Layout.All)) ||
            (owner_ == 2 && (layout_ == Layout.YieldTreasury || layout_ == Layout.All));
        bool treasuryDebt = owner_ == 2 ||
            (owner_ == 0 && (layout_ == Layout.RouteTreasury || layout_ == Layout.All)) ||
            (owner_ == 1 && (layout_ == Layout.YieldTreasury || layout_ == Layout.All));
        if (route && mask_ & _ROUTE != 0) e[0] = 10;
        if (repurchase && mask_ & _REPURCHASE != 0) e[1] = 20;
        if (treasuryDebt && mask_ & _TREASURY != 0) e[2] = 30;
    }

    /// @dev Invalid cases include all five layouts, eight globallyOwed masks and all role/unrelated owners.
    function _invalidSelection(uint256 choice_) internal pure returns (Selection memory) {
        return
            Selection({
                layoutId: Layout(choice_ / 32),
                mask: uint8((choice_ / 4) % 8),
                owner: uint8(choice_ % 4)
            });
    }

    /// @dev Fuzz the full numeric domain for address failures and the exact excess interval for amount failure.
    /// @dev Build the selected layout and bucket subset plus unrelated debt and surplus. The test applies lifecycle and chooses the caller.
    function _createInvalidInputLedger(
        Selection memory selection_
    ) internal returns (Ledger memory l) {
        l = _ordinaryQuantities(
            _configureLayout(selection_.layoutId, new MockRevertingTransferToken(18)),
            selection_.mask
        );
        l.otherAssetDebt = _INVALID_CASE_OTHER_ASSET_DEBT;
        l.surplus = _INVALID_CASE_SURPLUS;
    }

    /// @dev Observe the funded ledger even when the requested asset has no code. The test supplies both expected errors.
    function _assertInvalidRescueRequest(
        Ledger memory l,
        address caller_,
        RescueRequest memory request_,
        bytes memory previewError_,
        bytes memory executionError_
    ) internal {
        bytes32 beforeState = _stateHash(l, request_.destination);
        vm.expectRevert(previewError_);
        vm.prank(caller_);
        distributor.previewRescuePendingPayout(
            request_.asset,
            request_.recipient,
            request_.destination,
            request_.amount
        );
        vm.expectRevert(executionError_);
        vm.prank(caller_);
        distributor.rescuePendingPayout(
            request_.asset,
            request_.recipient,
            request_.destination,
            request_.amount
        );
        assertEq(
            _stateHash(l, request_.destination),
            beforeState,
            "invalid request preserves all ledger state"
        );
    }

    /// @dev Explicit requests and paired input errors for authorization/lifecycle check order. This catalogue does not select an outcome.
    function _authorizationInvalidRequests(
        Ledger memory l
    ) internal view returns (RescueRequest[10] memory requests, bytes[10] memory errors) {
        address asset = address(l.asset);
        address recipient = l.routeOwner;
        uint256[3] memory eligible = _eligible(l, recipient);
        uint256 entitlement = eligible[0] + eligible[1] + eligible[2];
        requests = [
            RescueRequest({asset: address(0), recipient: recipient, destination: bob, amount: 0}),
            RescueRequest({
                asset: _NO_CODE_ASSET,
                recipient: recipient,
                destination: bob,
                amount: 0
            }),
            RescueRequest({asset: asset, recipient: address(0), destination: bob, amount: 0}),
            RescueRequest({asset: asset, recipient: recipient, destination: address(0), amount: 0}),
            RescueRequest({
                asset: asset,
                recipient: recipient,
                destination: address(kernel),
                amount: 0
            }),
            RescueRequest({
                asset: asset,
                recipient: recipient,
                destination: address(distributor),
                amount: 0
            }),
            RescueRequest({asset: asset, recipient: recipient, destination: asset, amount: 0}),
            RescueRequest({asset: asset, recipient: recipient, destination: bob, amount: 0}),
            RescueRequest({
                asset: asset,
                recipient: recipient,
                destination: bob,
                amount: entitlement + 1
            }),
            RescueRequest({
                asset: address(0),
                recipient: address(0),
                destination: address(0),
                amount: 0
            })
        ];
        errors[0] = abi.encodeWithSelector(
            IRevenueDistributor.RevenueDistributor_InvalidAsset.selector,
            address(0)
        );
        errors[1] = abi.encodeWithSelector(
            IRevenueDistributor.RevenueDistributor_InvalidAsset.selector,
            _NO_CODE_ASSET
        );
        errors[2] = abi.encodeWithSelector(
            IRevenueDistributor.RevenueDistributor_InvalidRecipient.selector,
            address(0)
        );
        errors[3] = abi.encodeWithSelector(
            IRevenueDistributorRescue.RevenueDistributor_InvalidRescueDestination.selector,
            address(0)
        );
        errors[4] = abi.encodeWithSelector(
            IRevenueDistributorRescue.RevenueDistributor_InvalidRescueDestination.selector,
            address(kernel)
        );
        errors[5] = abi.encodeWithSelector(
            IRevenueDistributorRescue.RevenueDistributor_InvalidRescueDestination.selector,
            address(distributor)
        );
        errors[6] = abi.encodeWithSelector(
            IRevenueDistributorRescue.RevenueDistributor_InvalidRescueDestination.selector,
            asset
        );
        errors[7] = abi.encodeWithSelector(
            IRevenueDistributorRescue.RevenueDistributor_InvalidRescueAmount.selector
        );
        errors[8] = _insufficient(asset, entitlement + 1, entitlement);
        errors[9] = errors[0];
    }

    /// @dev Each caller sees eight independent local/Kernel/listing combinations and every input fault.
    function _assertAuthorizedInputFailures(Ledger memory l, address caller_) internal {
        (
            RescueRequest[10] memory requests,
            bytes[10] memory errors
        ) = _authorizationInvalidRequests(l);
        for (uint256 i; i < requests.length; ++i)
            _assertInvalidRescueRequest(l, caller_, requests[i], errors[i], errors[i]);
    }

    function _assertInactiveRequests(
        Ledger memory l,
        address caller_,
        bytes memory executionError_
    ) internal {
        bytes memory policyInactive = abi.encodeWithSelector(
            IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
        );
        _assertFailure(l, caller_, l.routeOwner, bob, 1, policyInactive, executionError_);
        (RescueRequest[10] memory requests, ) = _authorizationInvalidRequests(l);
        for (uint256 i; i < requests.length; ++i)
            _assertInvalidRescueRequest(l, caller_, requests[i], policyInactive, executionError_);
    }

    /// @dev Active previews validate inputs; unauthorized execution rejects every request at the caller check.
    function _assertActiveUnauthorizedRequests(
        Ledger memory l,
        address caller_,
        bytes memory unauthorized_
    ) internal {
        _assertFailure(l, caller_, l.routeOwner, bob, 1, "", unauthorized_);
        (
            RescueRequest[10] memory requests,
            bytes[10] memory errors
        ) = _authorizationInvalidRequests(l);
        for (uint256 i; i < requests.length; ++i)
            _assertInvalidRescueRequest(l, caller_, requests[i], errors[i], unauthorized_);
    }

    function _assertUnauthorizedAcrossLifecycle(address caller_) internal {
        bytes memory unauthorized = abi.encodeWithSelector(
            IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
            caller_
        );
        for (uint256 retired; retired < 2; ++retired)
            for (uint256 disabled; disabled < 2; ++disabled)
                for (uint256 inactive; inactive < 2; ++inactive) {
                    uint256 snapshot = vm.snapshotState();
                    Ledger memory l = _ordinaryQuantities(
                        _configureLayout(Layout.Distinct, new MockRevertingTransferToken(18)),
                        7
                    );
                    _fundLedger(l, retired != 0, disabled != 0);
                    if (inactive != 0) {
                        vm.prank(admin);
                        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
                    }
                    if (inactive != 0) _assertInactiveRequests(l, caller_, unauthorized);
                    else _assertActiveUnauthorizedRequests(l, caller_, unauthorized);
                    assertTrue(vm.revertToState(snapshot), "restore unauthorized lifecycle");
                }
    }

    /// @dev The caller bit selects a real permitted class; it never changes fixture ownership.
    function _caller(uint8 state_) internal view returns (address) {
        return state_ & _OPERATOR == 0 ? admin : address(configTimelock);
    }

    /// @dev Variable-quantity allocation uses cumulative intervals checked against seeded small/MAX examples.
    // Explicit finite partitions keep the expected allocation visible in this action test.
    // forge-lint: disable-next-line(cyclomatic-complexity)
    function _numericCase(
        uint256 route_,
        uint256 repurchase_,
        uint256 treasury_,
        uint256 amount_,
        uint8 state_
    ) internal {
        uint256 snapshot = vm.snapshotState();
        Ledger memory l = _configureLayout(Layout.All, new MockRevertingTransferToken(18));
        l.route = route_;
        l.repurchase = repurchase_;
        l.treasuryDebt = treasury_;
        _fundLedger(l, state_ & _RETIRED != 0, state_ & _DISABLED != 0);
        uint256 total = route_ + repurchase_ + treasury_;
        amount_ = bound(amount_, 1, total);
        uint256[3] memory paid;
        // Three intervals supply explicit expected debits; token base units require no scaling/rounding.
        if (amount_ <= route_) paid[0] = amount_;
        else if (amount_ <= route_ + repurchase_) paid = [route_, amount_ - route_, uint256(0)];
        else paid = [route_, repurchase_, amount_ - route_ - repurchase_];
        _assertSuccess(l, _caller(state_), l.routeOwner, bob, amount_, paid);
        assertTrue(vm.revertToState(snapshot), "restore variable quantities");
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unused-return,unsafe-typecast,calls-loop)
