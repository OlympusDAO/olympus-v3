pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansRescue} from "src/policies/interfaces/IBurnerLoansRescue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";

// Contracts
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions} from "src/Kernel.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {ReentrantPayoutToken} from "src/test/mocks/ReentrantPayoutToken.sol";
import {BurnerLoansSurplusRescueTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansSurplusRescueTest.sol";

// Finite scenario seeds use base-unit quantities; expected-revert previews have no result.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unused-return,unsafe-typecast)
contract BurnerLoansRescueTest is BurnerLoansSurplusRescueTestBase {
    uint256 internal constant _UNRESERVED_CUSTODY = 19;
    uint256 internal constant _RECOVERY_SURPLUS = 7;

    enum NestedAction {
        Surplus,
        PendingPayout,
        Retry
    }
    ReentrantPayoutToken internal _callbackAsset;

    /// @notice Each subset retains its exact 10/20/30 debts; owner overlap does not affect surplus.
    // Scenarios: P-02, P-06, P-07, P-08, P-09, P-10, P-11, TX-03.
    function test_givenBucketSubset_whenSurplusRescued(
        uint8 bucketMask_,
        bool disabled_,
        bool separateFeeRecipient_
    ) public {
        _caseFixedBuckets(
            uint8(bound(bucketMask_, 1, _ALL_BUCKETS)),
            disabled_,
            separateFeeRecipient_
        );
    }

    // Scenarios: P-02, P-06, P-07, P-08, P-09, P-10, P-11, TX-03.
    function test_givenBucketSubsets_whenEachIsSeeded() public {
        for (uint8 mask = 1; mask <= _ALL_BUCKETS; ++mask) {
            uint256 snapshot = vm.snapshotState();
            _caseFixedBuckets(mask, false, false);
            assertTrue(vm.revertToState(snapshot), "restore exact bucket subset");
        }
        _caseFixedBuckets(_ALL_BUCKETS, true, true);
    }

    function _caseFixedBuckets(uint8 mask_, bool disabled_, bool separateFeeRecipient_) internal {
        ReentrantPayoutToken asset = new ReentrantPayoutToken();
        if (separateFeeRecipient_) {
            _installFeeDistributorForTest(address(asset));
        }
        _recordRescueDebts(
            asset,
            mask_ & _REWARD_BUCKET != 0 ? _REWARD_AMOUNT : 0,
            mask_ & _FEE_BUCKET != 0 ? _FEE_AMOUNT : 0,
            mask_ & _SEIZURE_BUCKET != 0 ? _SEIZURE_AMOUNT : 0
        );
        asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
        asset.mint(_destination, _DESTINATION_BALANCE);
        _disableBurnerLoansIf(disabled_);
        _assertSurplusPayment(asset, _destination, _SURPLUS_AMOUNT, address(burnerLoansConfig));
    }

    /// @notice Fuzz custody and permitted destination; MAX gets a zero starting balance so total supply fits.
    // Scenarios: P-01.
    function test_givenUnconfiguredToken_whenFullBalanceRescued(
        uint256 balance_,
        address destination_
    ) public {
        vm.assume(
            destination_ != address(0) &&
                destination_ != address(burnerLoans) &&
                destination_ != address(burnerLoansConfig) &&
                destination_ != address(kernel)
        );
        MockERC20 asset = new MockERC20("Surplus", "SUR", 18);
        vm.assume(destination_ != address(asset));
        _caseUnreserved(asset, bound(balance_, 1, type(uint256).max), destination_);
    }

    // Scenarios: P-01.
    function test_givenUnconfiguredToken_whenBalanceBoundariesAreSeeded() public {
        uint256[3] memory balances = [uint256(1), type(uint256).max - 1, type(uint256).max];
        for (uint256 i; i < balances.length; ++i) {
            uint256 snapshot = vm.snapshotState();
            _caseUnreserved(new MockERC20("Surplus", "SUR", 18), balances[i], _destination);
            assertTrue(vm.revertToState(snapshot), "restore full-balance boundary");
        }
    }

    function _caseUnreserved(MockERC20 asset_, uint256 balance_, address destination_) internal {
        asset_.mint(address(burnerLoans), balance_);
        uint256 supplyBudget = type(uint256).max - balance_;
        asset_.mint(
            destination_,
            supplyBudget < _DESTINATION_BALANCE ? supplyBudget : _DESTINATION_BALANCE
        );
        _assertSurplusPayment(asset_, destination_, balance_, address(burnerLoansConfig));
    }

    /// @notice Independent quantity fuzzing is confined to this numerical test; ordinary fixtures stay fixed.
    // Scenarios: P-13.
    function test_givenVariableReserve_whenSurplusRescued(
        uint8 bucketMask_,
        uint256 reserve_,
        uint256 rewardShare_,
        uint256 feeShare_,
        uint256 surplus_
    ) public {
        uint8 mask = uint8(bound(bucketMask_, 1, _ALL_BUCKETS));
        uint256 bucketCount = (mask & _REWARD_BUCKET != 0 ? 1 : 0) +
            (mask & _FEE_BUCKET != 0 ? 1 : 0) +
            (mask & _SEIZURE_BUCKET != 0 ? 1 : 0);
        reserve_ = bound(reserve_, bucketCount, type(uint256).max - 1);
        _caseNumericalReserve(
            mask,
            reserve_,
            rewardShare_,
            feeShare_,
            bound(surplus_, 1, type(uint256).max - reserve_)
        );
    }

    // Scenarios: P-13.
    function test_givenVariableReserve_whenMaximumBoundariesAreSeeded() public {
        for (uint8 mask = 1; mask <= _ALL_BUCKETS; ++mask) {
            uint256 count = (mask & _REWARD_BUCKET != 0 ? 1 : 0) +
                (mask & _FEE_BUCKET != 0 ? 1 : 0) +
                (mask & _SEIZURE_BUCKET != 0 ? 1 : 0);
            uint256[2] memory reserves = [count, type(uint256).max - 1];
            for (uint256 r; r < reserves.length; ++r) {
                for (uint256 maximumSurplus; maximumSurplus < 2; ++maximumSurplus) {
                    uint256 snapshot = vm.snapshotState();
                    _caseNumericalReserve(
                        mask,
                        reserves[r],
                        1,
                        1,
                        maximumSurplus == 0 ? 1 : type(uint256).max - reserves[r]
                    );
                    assertTrue(vm.revertToState(snapshot), "restore numerical reserve boundary");
                }
            }
        }
    }

    /// @dev Split a known reserve among the chosen positive buckets; the test expectation stays B-R.
    function _caseNumericalReserve(
        uint8 mask_,
        uint256 reserve_,
        uint256 rewardShare_,
        uint256 feeShare_,
        uint256 surplus_
    ) internal {
        uint256 reward;
        uint256 fee;
        uint256 seizure;
        if (mask_ == _REWARD_BUCKET) reward = reserve_;
        else if (mask_ == _FEE_BUCKET) fee = reserve_;
        else if (mask_ == _SEIZURE_BUCKET) seizure = reserve_;
        else {
            if (mask_ & _REWARD_BUCKET != 0)
                reward = bound(rewardShare_, 1, reserve_ - (mask_ == _ALL_BUCKETS ? 2 : 1));
            if (mask_ & _FEE_BUCKET != 0)
                fee = mask_ & _SEIZURE_BUCKET == 0
                    ? reserve_ - reward
                    : bound(feeShare_, 1, reserve_ - reward - 1);
            if (mask_ & _SEIZURE_BUCKET != 0) seizure = reserve_ - reward - fee;
        }
        ReentrantPayoutToken asset = new ReentrantPayoutToken();
        _recordRescueDebts(asset, reward, fee, seizure);
        asset.mint(address(burnerLoans), surplus_);
        _assertSurplusPayment(asset, _destination, surplus_, address(burnerLoansConfig));
    }

    // Scenarios: P-03, P-04.
    function test_givenReserve_whenCustodyAtOrBelowReserve(
        uint256 reserve_,
        uint256 custody_
    ) public {
        reserve_ = bound(reserve_, 1, type(uint256).max);
        _caseNoSurplus(reserve_, bound(custody_, 0, reserve_));
    }

    // Scenarios: P-03, P-04.
    function test_givenReserve_whenCustodyBoundariesAreSeeded() public {
        uint256[4] memory reserves = [uint256(0), 1, _PENDING_RESERVE, type(uint256).max];
        for (uint256 r; r < reserves.length; ++r) {
            uint256[3] memory custody = [
                uint256(0),
                reserves[r] == 0 ? 0 : reserves[r] - 1,
                reserves[r]
            ];
            for (uint256 b; b < custody.length; ++b) {
                uint256 snapshot = vm.snapshotState();
                _caseNoSurplus(reserves[r], custody[b]);
                assertTrue(vm.revertToState(snapshot), "restore no-surplus boundary");
            }
        }
    }

    function _caseNoSurplus(uint256 reserve_, uint256 custody_) internal {
        ReentrantPayoutToken asset = new ReentrantPayoutToken();
        _recordRescueDebts(asset, reserve_, 0, 0);
        asset.burn(address(burnerLoans), reserve_ - custody_);
        _assertSurplusPayment(asset, _destination, 0, address(burnerLoansConfig));
    }

    // Scenarios: P-05, P-12.
    function test_givenConfiguredToken_whenSurplusRescued() public {
        _addDefaultUsdsAsset();
        for (uint256 debt; debt < 2; ++debt) {
            uint256 snapshot = vm.snapshotState();
            if (debt != 0) _recordRescueDebts(usds, _REWARD_AMOUNT, _FEE_AMOUNT, _SEIZURE_AMOUNT);
            usds.mint(address(burnerLoans), debt == 0 ? _UNRESERVED_CUSTODY : _SURPLUS_AMOUNT);
            _assertSurplusPayment(
                usds,
                _destination,
                debt == 0 ? _UNRESERVED_CUSTODY : _SURPLUS_AMOUNT,
                address(burnerLoansConfig)
            );
            assertTrue(vm.revertToState(snapshot), "restore configured collateral");
        }
    }

    // Scenarios: ISO-01.
    function test_givenUnrelatedDebts_whenOwedOrUnrelatedDestinationRescued() public {
        ReentrantPayoutToken other = _createUnrelatedRescueDebt();
        address[3] memory destinations = [_keeper, address(trsry), _destination];
        for (uint256 d; d < destinations.length; ++d) {
            uint256 snapshot = vm.snapshotState();
            ReentrantPayoutToken asset = _createFixedRescueToken(_ALL_BUCKETS);
            asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
            bytes32 otherBefore = _surplusAccountingHash(address(other));
            _assertSurplusPayment(
                asset,
                destinations[d],
                _SURPLUS_AMOUNT,
                address(burnerLoansConfig)
            );
            assertEq(
                _surplusAccountingHash(address(other)),
                otherBefore,
                "other token debts and indexes preserved"
            );
            assertEq(
                other.balanceOf(address(burnerLoans)),
                _FULL_CUSTODY,
                "other token custody preserved"
            );
            assertTrue(vm.revertToState(snapshot), "restore destination identity");
        }
    }

    // Scenarios: L-01.
    function test_givenFacilityEnabled_whenConfiguratorRescues() public {
        ReentrantPayoutToken asset = _createFixedRescueToken(_ALL_BUCKETS);
        asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);

        assertEq(
            burnerLoans.previewRescue(address(asset), _destination),
            _SURPLUS_AMOUNT,
            "preview ignores facility lifecycle"
        );
        _assertSurplusPayment(asset, _destination, _SURPLUS_AMOUNT, address(burnerLoansConfig));
    }

    // Scenarios: L-02.
    function test_givenFacilityDisabled_whenConfiguratorRescues() public {
        ReentrantPayoutToken asset = _createFixedRescueToken(_ALL_BUCKETS);
        asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);

        vm.startPrank(admin);
        burnerLoans.disable("");

        vm.stopPrank();
        assertEq(
            burnerLoans.previewRescue(address(asset), _destination),
            _SURPLUS_AMOUNT,
            "preview ignores facility lifecycle"
        );
        _assertSurplusPayment(asset, _destination, _SURPLUS_AMOUNT, address(burnerLoansConfig));
    }

    // Scenarios: L-03.
    function test_givenFacilityInactive_whenConfiguratorRescues_reverts() public {
        ReentrantPayoutToken asset = _createFixedRescueToken(_ALL_BUCKETS);
        asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
        for (uint256 disabled; disabled < 2; ++disabled) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            if (disabled != 0) burnerLoans.disable("");
            kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_PolicyInactive.selector
            );
            // Activity precedes address validation; previews remain permissionless.
            vm.expectRevert(failure);
            burnerLoans.previewRescue(address(asset), _destination);
            vm.expectRevert(failure);
            burnerLoans.previewRescue(address(0), _destination);
            vm.expectRevert(failure);
            burnerLoans.previewRescue(address(asset), address(0));
            _assertSurplusFailure(
                asset,
                address(asset),
                _destination,
                address(burnerLoansConfig),
                abi.encodeWithSelector(IBurnerLoans.BurnerLoans_PolicyInactive.selector)
            );
            _assertSurplusFailure(
                asset,
                address(0),
                address(0),
                address(burnerLoansConfig),
                abi.encodeWithSelector(IBurnerLoans.BurnerLoans_PolicyInactive.selector)
            );

            assertTrue(vm.revertToState(snapshot), "restore caller and lifecycle combination");
        }
    }

    // Scenarios: L-06.
    function test_givenFacilityEnabled_whenAdminRescues() public {
        ReentrantPayoutToken asset = _createFixedRescueToken(_ALL_BUCKETS);
        asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);

        assertEq(
            burnerLoans.previewRescue(address(asset), _destination),
            _SURPLUS_AMOUNT,
            "preview ignores facility lifecycle"
        );
        _assertSurplusPayment(asset, _destination, _SURPLUS_AMOUNT, admin);
    }

    // Scenarios: L-06.
    function test_givenFacilityDisabled_whenAdminRescues() public {
        ReentrantPayoutToken asset = _createFixedRescueToken(_ALL_BUCKETS);
        asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);

        vm.startPrank(admin);
        burnerLoans.disable("");

        vm.stopPrank();
        assertEq(
            burnerLoans.previewRescue(address(asset), _destination),
            _SURPLUS_AMOUNT,
            "preview ignores facility lifecycle"
        );
        _assertSurplusPayment(asset, _destination, _SURPLUS_AMOUNT, admin);
    }

    // Scenarios: L-05.
    function test_givenFacilityInactive_whenAdminRescues_reverts() public {
        ReentrantPayoutToken asset = _createFixedRescueToken(_ALL_BUCKETS);
        asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
        for (uint256 disabled; disabled < 2; ++disabled) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            if (disabled != 0) burnerLoans.disable("");
            kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_PolicyInactive.selector
            );
            // Activity precedes address validation; previews remain permissionless.
            vm.expectRevert(failure);
            burnerLoans.previewRescue(address(asset), _destination);
            vm.expectRevert(failure);
            burnerLoans.previewRescue(address(0), _destination);
            vm.expectRevert(failure);
            burnerLoans.previewRescue(address(asset), address(0));
            _assertSurplusFailure(
                asset,
                address(asset),
                _destination,
                admin,
                abi.encodeWithSelector(IBurnerLoans.BurnerLoans_PolicyInactive.selector)
            );
            _assertSurplusFailure(
                asset,
                address(0),
                address(0),
                admin,
                abi.encodeWithSelector(IBurnerLoans.BurnerLoans_PolicyInactive.selector)
            );

            assertTrue(vm.revertToState(snapshot), "restore caller and lifecycle combination");
        }
    }

    // Scenarios: L-01, L-06.
    function test_givenFacilityRestored_whenEachPermittedCallerRescues() public {
        ReentrantPayoutToken asset = _createFixedRescueToken(_ALL_BUCKETS);
        asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
        vm.startPrank(admin);
        burnerLoans.disable("");
        burnerLoans.reEnable();
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
        kernel.executeAction(Actions.ActivatePolicy, address(burnerLoans));
        vm.stopPrank();
        uint256 snapshot = vm.snapshotState();
        _assertSurplusPayment(asset, _destination, _SURPLUS_AMOUNT, address(burnerLoansConfig));
        assertTrue(vm.revertToState(snapshot), "restore recovered facility for admin");
        _assertSurplusPayment(asset, _destination, _SURPLUS_AMOUNT, admin);
    }

    // Scenarios: L-04.
    function test_givenFacilityLifecycle_whenCallerIsUnauthorized_reverts(
        address caller_,
        bool disabled_,
        bool inactive_
    ) public {
        vm.assume(caller_ != admin && caller_ != address(burnerLoansConfig));
        ReentrantPayoutToken asset = _createFixedRescueToken(_ALL_BUCKETS);
        asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
        vm.startPrank(admin);
        if (disabled_) burnerLoans.disable("");
        if (inactive_) kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
        vm.stopPrank();
        bytes memory failure = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        _assertSurplusFailure(asset, address(asset), _destination, caller_, failure);
        _assertSurplusFailure(asset, address(0), address(0), caller_, failure);
    }

    // Scenarios: L-01, L-02, L-04, L-06.
    // Caller identity never restricts a preview while BL remains Kernel-active.
    function test_givenActiveFacility_whenAnyCallerPreviews(
        address caller_,
        bool disabled_
    ) public {
        ReentrantPayoutToken asset = _createFixedRescueToken(_ALL_BUCKETS);
        asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
        _disableBurnerLoansIf(disabled_);
        vm.prank(caller_);
        assertEq(
            burnerLoans.previewRescue(address(asset), _destination),
            _SURPLUS_AMOUNT,
            "active preview is permissionless and ignores local enablement"
        );
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRescue.BurnerLoans_InvalidAsset.selector, address(0))
        );
        vm.prank(caller_);
        burnerLoans.previewRescue(address(0), _destination);
    }

    // Scenarios: L-04.
    function test_givenUnauthorizedIdentities_whenSeeded_reverts() public {
        address[3] memory callers = [address(0), emergency, burnerLoansAdmin];
        for (uint256 c; c < callers.length; ++c)
            for (uint256 disabled; disabled < 2; ++disabled)
                for (uint256 inactive; inactive < 2; ++inactive) {
                    uint256 snapshot = vm.snapshotState();
                    test_givenFacilityLifecycle_whenCallerIsUnauthorized_reverts(
                        callers[c],
                        disabled != 0,
                        inactive != 0
                    );
                    assertTrue(
                        vm.revertToState(snapshot),
                        "restore explicit unauthorized identity"
                    );
                }
        ReentrantPayoutToken asset = _createFixedRescueToken(_ALL_BUCKETS);
        address replacement = address(_activateReplacementConfigurator());
        vm.startPrank(admin);
        burnerLoans.disable("");
        burnerLoans.setConfigurator(replacement);
        vm.stopPrank();
        _assertSurplusFailure(
            asset,
            address(asset),
            _destination,
            address(burnerLoansConfig),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: A-01.
    function test_givenConfigAndTimelockUnavailable_whenAdminRescuesDirectly() public {
        for (uint256 configInactive; configInactive < 2; ++configInactive)
            for (uint256 timelockInactive; timelockInactive < 2; ++timelockInactive)
                for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
                    uint256 snapshot = vm.snapshotState();
                    ReentrantPayoutToken asset = _createFixedRescueToken(_ALL_BUCKETS);
                    asset.mint(address(burnerLoans), _RECOVERY_SURPLUS);
                    vm.startPrank(admin);
                    burnerLoansConfig.disable("");
                    if (configInactive != 0)
                        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoansConfig));
                    if (timelockInactive != 0)
                        kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
                    if (disabledBL != 0) burnerLoans.disable("");
                    vm.stopPrank();
                    assertFalse(configTimelock.isEnabled(), "upstream timelock is disabled");
                    uint64 counter = configTimelock.nextActionId();
                    _assertSurplusPayment(asset, _destination, _RECOVERY_SURPLUS, admin);
                    assertEq(
                        configTimelock.nextActionId(),
                        counter,
                        "direct recovery queues no action"
                    );
                    assertTrue(vm.revertToState(snapshot), "restore direct recovery state");
                }
    }

    /// @notice Every invalid address is rejected before custody/reserve-dependent behavior.
    // Scenarios: I-01.
    function test_givenBucketAndCustodyStates_whenTokenHasNoCode_reverts() public {
        for (uint8 mask; mask <= _ALL_BUCKETS; ++mask)
            for (uint256 disabled; disabled < 2; ++disabled) {
                uint256 snapshot = vm.snapshotState();
                ReentrantPayoutToken asset = _createFixedRescueToken(mask);
                _disableBurnerLoansIf(disabled != 0);
                uint256 reserve = burnerLoans.totalPendingForTest(address(asset));
                for (uint256 custodyState; custodyState < 3; ++custodyState) {
                    uint256 custodySnapshot = vm.snapshotState();
                    if (custodyState == 0 && reserve != 0) asset.burn(address(burnerLoans), 1);
                    if (custodyState == 2) asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
                    address[2] memory invalidAssets = [
                        address(0),
                        makeAddr("no-code rescue asset")
                    ];
                    for (uint256 a; a < invalidAssets.length; ++a) {
                        bytes memory failure = abi.encodeWithSelector(
                            IBurnerLoansRescue.BurnerLoans_InvalidAsset.selector,
                            invalidAssets[a]
                        );
                        _assertMatchingInputError(asset, invalidAssets[a], _destination, failure);
                        // Combining faults also proves asset validation precedes destination validation.
                        _assertMatchingInputError(asset, invalidAssets[a], address(0), failure);
                    }

                    assertTrue(
                        vm.revertToState(custodySnapshot),
                        "restore invalid-input custody state"
                    );
                }
                assertTrue(vm.revertToState(snapshot), "restore invalid-input bucket state");
            }
    }

    // Scenarios: I-02, I-03.
    function test_givenBucketAndCustodyStates_whenDestinationIsForbidden_reverts() public {
        for (uint8 mask; mask <= _ALL_BUCKETS; ++mask)
            for (uint256 disabled; disabled < 2; ++disabled) {
                uint256 snapshot = vm.snapshotState();
                ReentrantPayoutToken asset = _createFixedRescueToken(mask);
                _disableBurnerLoansIf(disabled != 0);
                uint256 reserve = burnerLoans.totalPendingForTest(address(asset));
                for (uint256 custodyState; custodyState < 3; ++custodyState) {
                    uint256 custodySnapshot = vm.snapshotState();
                    if (custodyState == 0 && reserve != 0) asset.burn(address(burnerLoans), 1);
                    if (custodyState == 2) asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);

                    address[_SURPLUS_AMOUNT] memory forbidden = [
                        address(0),
                        address(burnerLoans),
                        address(asset),
                        address(burnerLoansConfig),
                        address(kernel)
                    ];
                    for (uint256 d; d < forbidden.length; ++d)
                        _assertMatchingInputError(
                            asset,
                            address(asset),
                            forbidden[d],
                            abi.encodeWithSelector(
                                IBurnerLoansRescue.BurnerLoans_InvalidRescueDestination.selector,
                                forbidden[d]
                            )
                        );

                    assertTrue(
                        vm.revertToState(custodySnapshot),
                        "restore invalid-input custody state"
                    );
                }
                assertTrue(vm.revertToState(snapshot), "restore invalid-input bucket state");
            }
    }

    // Scenarios: I-04.
    function test_givenBucketAndCustodyStates_whenBalanceQueryReverts_reverts() public {
        for (uint8 mask; mask <= _ALL_BUCKETS; ++mask)
            for (uint256 disabled; disabled < 2; ++disabled) {
                uint256 snapshot = vm.snapshotState();
                ReentrantPayoutToken asset = _createFixedRescueToken(mask);
                _disableBurnerLoansIf(disabled != 0);
                uint256 reserve = burnerLoans.totalPendingForTest(address(asset));
                for (uint256 custodyState; custodyState < 3; ++custodyState) {
                    uint256 custodySnapshot = vm.snapshotState();
                    if (custodyState == 0 && reserve != 0) asset.burn(address(burnerLoans), 1);
                    if (custodyState == 2) asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);

                    _assertBalanceQueryFailure(asset, address(burnerLoansConfig));
                    assertTrue(
                        vm.revertToState(custodySnapshot),
                        "restore invalid-input custody state"
                    );
                }
                assertTrue(vm.revertToState(snapshot), "restore invalid-input bucket state");
            }
    }

    function _assertMatchingInputError(
        MockERC20 tracker_,
        address asset_,
        address destination_,
        bytes memory failure_
    ) internal {
        vm.expectRevert(failure_);
        burnerLoans.previewRescue(asset_, destination_);
        _assertSurplusFailure(tracker_, asset_, destination_, address(burnerLoansConfig), failure_);
    }

    // Scenarios: TX-01.
    function test_givenPendingReserve_whenTransferReverts_reverts() public {
        _assertTransferFailure(false);
    }

    // Scenarios: TX-02.
    function test_givenPendingReserve_whenTransferReturnsFalse_reverts() public {
        _assertTransferFailure(true);
    }

    function _assertTransferFailure(bool returnsFalse_) internal {
        ReentrantPayoutToken asset = _createFixedRescueToken(_ALL_BUCKETS);
        ReentrantPayoutToken other = _createUnrelatedRescueDebt();
        bytes32 otherBefore = _surplusAccountingHash(address(other));
        asset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
        asset.mint(_destination, _DESTINATION_BALANCE);
        assertEq(
            burnerLoans.previewRescue(address(asset), _destination),
            _SURPLUS_AMOUNT,
            "transfer failure does not affect preview"
        );
        bytes memory failure;
        if (returnsFalse_) {
            vm.mockCall(
                address(asset),
                abi.encodeWithSelector(IERC20.transfer.selector, _destination),
                abi.encode(false)
            );
            failure = abi.encodeWithSelector(
                SafeERC20.SafeERC20FailedOperation.selector,
                address(asset)
            );
        } else {
            asset.setTransferBlocked(_destination, true);
            failure = abi.encodeWithSelector(
                ReentrantPayoutToken.TransferBlocked.selector,
                _destination
            );
        }
        _assertSurplusFailure(
            asset,
            address(asset),
            _destination,
            address(burnerLoansConfig),
            failure
        );
        vm.clearMockedCalls();
        assertEq(
            _surplusAccountingHash(address(other)),
            otherBefore,
            "transfer failure preserves unrelated raw state"
        );
    }

    /// @notice Authorized callbacks try surplus, pending rescue and retry for the same/other token.
    // Scenarios: CB-01.
    function test_givenSurplusRescueCallback_whenFailureIsCaught() public {
        for (uint256 differentToken; differentToken < 2; ++differentToken) {
            uint256 snapshot = vm.snapshotState();
            _callbackAsset = _createFixedRescueToken(_ALL_BUCKETS);
            _callbackAsset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
            ReentrantPayoutToken nested = differentToken == 0
                ? _callbackAsset
                : _createFixedRescueToken(_ALL_BUCKETS);
            if (differentToken != 0) nested.mint(address(burnerLoans), _SURPLUS_AMOUNT);
            vm.prank(admin);
            burnerLoansConfig.setConfigOperator(address(this));
            bytes32 nestedBefore = _surplusAccountingHash(address(nested));
            _callbackAsset.setCallbackFrom(
                address(burnerLoans),
                address(this),
                abi.encodeCall(
                    this.observeAndAttemptNestedAction,
                    (address(nested), NestedAction(0))
                )
            );
            _callbackAsset.setBubbleCallbackFailure(false);

            _assertSurplusPayment(
                _callbackAsset,
                _destination,
                _SURPLUS_AMOUNT,
                address(burnerLoansConfig)
            );
            assertEq(
                _callbackAsset.callbackRevertData(),
                abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
                "nested action reaches shared guard after callback reads"
            );

            // Capture after authorization setup, whose operator change is intentionally outside rescue.
            assertEq(
                burnerLoans.totalPendingForTest(address(nested)),
                _PENDING_RESERVE,
                "callback never pays nested obligations"
            );
            if (differentToken != 0)
                assertEq(
                    nested.balanceOf(address(burnerLoans)),
                    _FULL_CUSTODY,
                    "callback preserves other custody"
                );
            assertEq(
                _surplusAccountingHash(address(nested)),
                nestedBefore,
                "callback preserves every nested debt, index and configuration"
            );
            assertTrue(vm.revertToState(snapshot), "restore callback action and outcome");
        }
    }

    // Scenarios: CB-01.
    function test_givenSurplusRescueCallback_whenFailureIsPropagated() public {
        for (uint256 differentToken; differentToken < 2; ++differentToken) {
            uint256 snapshot = vm.snapshotState();
            _callbackAsset = _createFixedRescueToken(_ALL_BUCKETS);
            _callbackAsset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
            ReentrantPayoutToken nested = differentToken == 0
                ? _callbackAsset
                : _createFixedRescueToken(_ALL_BUCKETS);
            if (differentToken != 0) nested.mint(address(burnerLoans), _SURPLUS_AMOUNT);
            vm.prank(admin);
            burnerLoansConfig.setConfigOperator(address(this));
            bytes32 nestedBefore = _surplusAccountingHash(address(nested));
            _callbackAsset.setCallbackFrom(
                address(burnerLoans),
                address(this),
                abi.encodeCall(
                    this.observeAndAttemptNestedAction,
                    (address(nested), NestedAction(0))
                )
            );
            _callbackAsset.setBubbleCallbackFailure(true);

            _assertSurplusFailure(
                _callbackAsset,
                address(_callbackAsset),
                _destination,
                address(burnerLoansConfig),
                abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector)
            );
            assertTrue(
                _callbackAsset.callbackEnabled(),
                "propagated failure rolls back callback state"
            );

            // Capture after authorization setup, whose operator change is intentionally outside rescue.
            assertEq(
                burnerLoans.totalPendingForTest(address(nested)),
                _PENDING_RESERVE,
                "callback never pays nested obligations"
            );
            if (differentToken != 0)
                assertEq(
                    nested.balanceOf(address(burnerLoans)),
                    _FULL_CUSTODY,
                    "callback preserves other custody"
                );
            assertEq(
                _surplusAccountingHash(address(nested)),
                nestedBefore,
                "callback preserves every nested debt, index and configuration"
            );
            assertTrue(vm.revertToState(snapshot), "restore callback action and outcome");
        }
    }

    // Scenarios: CB-02.
    function test_givenPendingRescueCallback_whenFailureIsCaught() public {
        for (uint256 differentToken; differentToken < 2; ++differentToken) {
            uint256 snapshot = vm.snapshotState();
            _callbackAsset = _createFixedRescueToken(_ALL_BUCKETS);
            _callbackAsset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
            ReentrantPayoutToken nested = differentToken == 0
                ? _callbackAsset
                : _createFixedRescueToken(_ALL_BUCKETS);
            if (differentToken != 0) nested.mint(address(burnerLoans), _SURPLUS_AMOUNT);
            vm.prank(admin);
            burnerLoansConfig.setConfigOperator(address(this));
            bytes32 nestedBefore = _surplusAccountingHash(address(nested));
            _callbackAsset.setCallbackFrom(
                address(burnerLoans),
                address(this),
                abi.encodeCall(
                    this.observeAndAttemptNestedAction,
                    (address(nested), NestedAction(1))
                )
            );
            _callbackAsset.setBubbleCallbackFailure(false);

            _assertSurplusPayment(
                _callbackAsset,
                _destination,
                _SURPLUS_AMOUNT,
                address(burnerLoansConfig)
            );
            assertEq(
                _callbackAsset.callbackRevertData(),
                abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
                "nested action reaches shared guard after callback reads"
            );

            // Capture after authorization setup, whose operator change is intentionally outside rescue.
            assertEq(
                burnerLoans.totalPendingForTest(address(nested)),
                _PENDING_RESERVE,
                "callback never pays nested obligations"
            );
            if (differentToken != 0)
                assertEq(
                    nested.balanceOf(address(burnerLoans)),
                    _FULL_CUSTODY,
                    "callback preserves other custody"
                );
            assertEq(
                _surplusAccountingHash(address(nested)),
                nestedBefore,
                "callback preserves every nested debt, index and configuration"
            );
            assertTrue(vm.revertToState(snapshot), "restore callback action and outcome");
        }
    }

    // Scenarios: CB-02.
    function test_givenPendingRescueCallback_whenFailureIsPropagated() public {
        for (uint256 differentToken; differentToken < 2; ++differentToken) {
            uint256 snapshot = vm.snapshotState();
            _callbackAsset = _createFixedRescueToken(_ALL_BUCKETS);
            _callbackAsset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
            ReentrantPayoutToken nested = differentToken == 0
                ? _callbackAsset
                : _createFixedRescueToken(_ALL_BUCKETS);
            if (differentToken != 0) nested.mint(address(burnerLoans), _SURPLUS_AMOUNT);
            vm.prank(admin);
            burnerLoansConfig.setConfigOperator(address(this));
            bytes32 nestedBefore = _surplusAccountingHash(address(nested));
            _callbackAsset.setCallbackFrom(
                address(burnerLoans),
                address(this),
                abi.encodeCall(
                    this.observeAndAttemptNestedAction,
                    (address(nested), NestedAction(1))
                )
            );
            _callbackAsset.setBubbleCallbackFailure(true);

            _assertSurplusFailure(
                _callbackAsset,
                address(_callbackAsset),
                _destination,
                address(burnerLoansConfig),
                abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector)
            );
            assertTrue(
                _callbackAsset.callbackEnabled(),
                "propagated failure rolls back callback state"
            );

            // Capture after authorization setup, whose operator change is intentionally outside rescue.
            assertEq(
                burnerLoans.totalPendingForTest(address(nested)),
                _PENDING_RESERVE,
                "callback never pays nested obligations"
            );
            if (differentToken != 0)
                assertEq(
                    nested.balanceOf(address(burnerLoans)),
                    _FULL_CUSTODY,
                    "callback preserves other custody"
                );
            assertEq(
                _surplusAccountingHash(address(nested)),
                nestedBefore,
                "callback preserves every nested debt, index and configuration"
            );
            assertTrue(vm.revertToState(snapshot), "restore callback action and outcome");
        }
    }

    // Scenarios: CB-02.
    function test_givenPendingRetryCallback_whenFailureIsCaught() public {
        for (uint256 differentToken; differentToken < 2; ++differentToken) {
            uint256 snapshot = vm.snapshotState();
            _callbackAsset = _createFixedRescueToken(_ALL_BUCKETS);
            _callbackAsset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
            ReentrantPayoutToken nested = differentToken == 0
                ? _callbackAsset
                : _createFixedRescueToken(_ALL_BUCKETS);
            if (differentToken != 0) nested.mint(address(burnerLoans), _SURPLUS_AMOUNT);
            vm.prank(admin);
            burnerLoansConfig.setConfigOperator(address(this));
            bytes32 nestedBefore = _surplusAccountingHash(address(nested));
            _callbackAsset.setCallbackFrom(
                address(burnerLoans),
                address(this),
                abi.encodeCall(
                    this.observeAndAttemptNestedAction,
                    (address(nested), NestedAction(2))
                )
            );
            _callbackAsset.setBubbleCallbackFailure(false);

            _assertSurplusPayment(
                _callbackAsset,
                _destination,
                _SURPLUS_AMOUNT,
                address(burnerLoansConfig)
            );
            assertEq(
                _callbackAsset.callbackRevertData(),
                abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
                "nested action reaches shared guard after callback reads"
            );

            // Capture after authorization setup, whose operator change is intentionally outside rescue.
            assertEq(
                burnerLoans.totalPendingForTest(address(nested)),
                _PENDING_RESERVE,
                "callback never pays nested obligations"
            );
            if (differentToken != 0)
                assertEq(
                    nested.balanceOf(address(burnerLoans)),
                    _FULL_CUSTODY,
                    "callback preserves other custody"
                );
            assertEq(
                _surplusAccountingHash(address(nested)),
                nestedBefore,
                "callback preserves every nested debt, index and configuration"
            );
            assertTrue(vm.revertToState(snapshot), "restore callback action and outcome");
        }
    }

    // Scenarios: CB-02.
    function test_givenPendingRetryCallback_whenFailureIsPropagated() public {
        for (uint256 differentToken; differentToken < 2; ++differentToken) {
            uint256 snapshot = vm.snapshotState();
            _callbackAsset = _createFixedRescueToken(_ALL_BUCKETS);
            _callbackAsset.mint(address(burnerLoans), _SURPLUS_AMOUNT);
            ReentrantPayoutToken nested = differentToken == 0
                ? _callbackAsset
                : _createFixedRescueToken(_ALL_BUCKETS);
            if (differentToken != 0) nested.mint(address(burnerLoans), _SURPLUS_AMOUNT);
            vm.prank(admin);
            burnerLoansConfig.setConfigOperator(address(this));
            bytes32 nestedBefore = _surplusAccountingHash(address(nested));
            _callbackAsset.setCallbackFrom(
                address(burnerLoans),
                address(this),
                abi.encodeCall(
                    this.observeAndAttemptNestedAction,
                    (address(nested), NestedAction(2))
                )
            );
            _callbackAsset.setBubbleCallbackFailure(true);

            _assertSurplusFailure(
                _callbackAsset,
                address(_callbackAsset),
                _destination,
                address(burnerLoansConfig),
                abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector)
            );
            assertTrue(
                _callbackAsset.callbackEnabled(),
                "propagated failure rolls back callback state"
            );

            // Capture after authorization setup, whose operator change is intentionally outside rescue.
            assertEq(
                burnerLoans.totalPendingForTest(address(nested)),
                _PENDING_RESERVE,
                "callback never pays nested obligations"
            );
            if (differentToken != 0)
                assertEq(
                    nested.balanceOf(address(burnerLoans)),
                    _FULL_CUSTODY,
                    "callback preserves other custody"
                );
            assertEq(
                _surplusAccountingHash(address(nested)),
                nestedBefore,
                "callback preserves every nested debt, index and configuration"
            );
            assertTrue(vm.revertToState(snapshot), "restore callback action and outcome");
        }
    }

    /// @dev Called after the transfer: balances reflect payment while every obligation remains owed.
    function observeAndAttemptNestedAction(address nestedAsset_, NestedAction action_) external {
        assertEq(msg.sender, address(_callbackAsset), "callback originates from outer token");
        assertEq(
            burnerLoans.previewRescue(address(_callbackAsset), _destination),
            0,
            "callback sees consumed surplus"
        );
        assertEq(
            burnerLoans.pendingPayout(address(_callbackAsset), _keeper),
            _REWARD_AMOUNT,
            "callback sees keeper obligation retained"
        );
        if (action_ == NestedAction.Surplus) burnerLoansConfig.rescue(nestedAsset_, _destination);
        else if (action_ == NestedAction.PendingPayout)
            burnerLoansConfig.rescuePendingPayout(nestedAsset_, _keeper, _destination, 1);
        else burnerLoans.transferPendingPayout(nestedAsset_, _keeper);
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unused-return,unsafe-typecast)
