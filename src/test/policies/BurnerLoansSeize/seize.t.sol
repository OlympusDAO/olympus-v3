// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansSeize} from "src/policies/interfaces/burnerloans/IBurnerLoansSeize.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {BL_LIQUIDATION_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansSeizeTestBase} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeTestBase.sol";

// Literals are independent expected values and boundary seeds.
// Fixture casts are bounded; seed loops intentionally call external contracts.
// The literal boolean is an expected ABI argument.
// forge-lint: disable-start(boolean-cst, calls-loop, literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansSeizeTest is BurnerLoansSeizeTestBase {
    // Scenarios: BLLIQ-SEIZE-D12.
    function test_givenDepositManagerInactive_whenSeizedOrPreviewed_reverts(
        address keeper_
    ) public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_depositManager));
        _expectRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_depositManager)
            ),
            _borrowers(),
            keeper_
        );
    }

    // Scenarios: BLLIQ-SEIZE-D11.
    function test_givenDepositPeriodDisabled_whenSeized_thenExitRemainsAvailable() public {
        _depositManager.disableAssetPeriod(IERC20(address(_asset)), 1, address(_core));
        _assertSingleSeizure();
    }

    // Scenarios: BLLIQ-SEIZE-D10.
    function test_givenDepositManagerPaused_whenSeizedOrPreviewed_reverts(address keeper_) public {
        _depositManager.disable("");
        _expectRejected(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager.selector,
                address(_depositManager)
            ),
            _borrowers(),
            keeper_
        );
    }

    // Scenarios: BLLIQ-SEIZE-A01, BLLIQ-SEIZE-L01.
    function test_whenPermissionlessKeeperSeizes_thenForwardsKeeperAndCoreResult(
        address keeper_,
        uint256 reward_,
        uint256 treasury_
    ) public {
        IBurnerLoansCore.PriceSnapshot memory snapshot = IBurnerLoansCore.PriceSnapshot(
            1e18,
            1e18,
            1e18
        );
        address[] memory borrowers = _borrowers();
        IBurnerLoansCore.SeizePreview memory result = IBurnerLoansCore.SeizePreview(
            100e9,
            2000e6,
            address(_asset),
            treasury_,
            reward_
        );
        bytes memory settlement = abi.encodeCall(
            IBurnerLoansCore.settleSeize,
            (address(_asset), borrowers, keeper_, snapshot)
        );
        bytes32 beforeState = _seizeDigest(keeper_);
        vm.prank(keeper_);
        IBurnerLoansCore.SeizePreview memory quote = _liquidation.previewSeizeFor(
            _recipient,
            address(_asset),
            borrowers
        );
        assertEq(
            quote.keeperReward,
            7,
            "Permissionless preview uses explicit actor, not view caller"
        );
        assertEq(
            _seizeDigest(keeper_),
            beforeState,
            "Permissionless preview preserves every ledger and custody component"
        );
        vm.mockCall(address(_core), settlement, abi.encode(result));
        vm.expectCall(address(_core), settlement, 1);
        vm.prank(keeper_);
        (address token, uint256 reward, uint256 treasury) = _liquidation.seize(
            address(_asset),
            borrowers
        );
        assertEq(token, address(_asset), "Return Core token unchanged");
        assertEq(reward, reward_, "Action never recalculates Core reward");
        assertEq(treasury, treasury_, "Action never recalculates Core Treasury allocation");
        assertEq(_position().principalDue, 100e9, "Mocked settlement owns mutations, not action");
    }

    // Scenarios: BLLIQ-SEIZE-P07, BLLIQ-SEIZE-P10, BLLIQ-SEIZE-P12.
    function test_givenUnhealthyDebt_whenSeized_thenDefaultAndPayoutConserveOutput() public {
        vm.expectCall(
            address(_risk),
            abi.encodeCall(
                IBurnerLoansRisk.keeperReward,
                (
                    IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18),
                    _core.marketId(address(_asset)),
                    uint256(100e9),
                    uint256(2000e6),
                    uint256(2000e6),
                    false
                )
            ),
            2
        );
        _assertSingleSeizure();
    }

    // Scenarios: BLLIQ-SEIZE-I01.
    function test_whenBatchEmpty_reverts(address caller_) public {
        _expectRejected(
            abi.encodeWithSelector(IBurnerLoansSeize.BurnerLoans_InvalidBatch.selector),
            new address[](0),
            caller_
        );
    }

    // Scenarios: BLLIQ-SEIZE-I02.
    function test_whenLargeBatchContainsZeroBorrower_reverts(
        uint256 length_,
        address caller_
    ) public {
        length_ = bound(length_, 51, 256);
        _expectRejected(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector),
            new address[](length_),
            caller_
        );
    }

    // Scenarios: BLLIQ-SEIZE-I03.
    function test_whenBorrowerZero_reverts(address caller_) public {
        _expectRejected(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector),
            new address[](1),
            caller_
        );
    }

    // Scenarios: BLLIQ-SEIZE-P01.
    function test_whenAdjacentDuplicate_reverts(address caller_) public {
        address[] memory borrowers = new address[](2);
        borrowers[0] = _borrower;
        borrowers[1] = _borrower;
        _expectRejected(
            abi.encodeWithSelector(
                IBurnerLoansSeize.BurnerLoans_DuplicateBorrower.selector,
                _borrower
            ),
            borrowers,
            caller_
        );
    }

    // Scenarios: BLLIQ-SEIZE-P02.
    function test_whenNonAdjacentDuplicate_reverts(address caller_) public {
        address[] memory borrowers = new address[](3);
        borrowers[0] = _borrower;
        borrowers[1] = _recipient;
        borrowers[2] = _borrower;
        _expectRejected(
            abi.encodeWithSelector(
                IBurnerLoansSeize.BurnerLoans_DuplicateBorrower.selector,
                _borrower
            ),
            borrowers,
            caller_
        );
    }

    // Scenarios: BLLIQ-SEIZE-P03.
    function test_whenBorrowerHasNoDebt_reverts(address caller_) public {
        address[] memory borrowers = new address[](2);
        borrowers[0] = _borrower;
        borrowers[1] = _recipient;
        _expectRejected(
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_NoDebt.selector),
            borrowers,
            caller_
        );
    }

    // Scenarios: BLLIQ-SEIZE-P04, BLLIQ-SEIZE-P05.
    function test_givenHealthyUnexpiredDebt_whenSeized_reverts(
        uint256 health_,
        address caller_
    ) public {
        health_ = bound(health_, 1e18, type(uint256).max);
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encode(health_)
        );
        _expectRejected(
            abi.encodeWithSelector(
                IBurnerLoansSeize.BurnerLoans_PositionNotSeizable.selector,
                _borrower
            ),
            _borrowers(),
            caller_
        );
    }

    // Scenarios: BLLIQ-SEIZE-P08.
    function test_givenExactlyExpiredHealthyDebt_whenSeized_thenAllowed() public {
        vm.warp(_position().maturity);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encodeWithSelector(DefaultFailed.selector)
        );
        _assertSingleSeizure();
    }

    // Scenarios: BLLIQ-SEIZE-P09.
    function test_givenExpiredHealthyDebt_whenSeized_thenAllowed(uint48 elapsed_) public {
        elapsed_ = uint48(bound(elapsed_, 1, type(uint48).max - _position().maturity));
        vm.warp(uint256(_position().maturity) + elapsed_);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encodeWithSelector(DefaultFailed.selector)
        );
        _assertSingleSeizure();
    }

    // Scenarios: BLLIQ-SEIZE-P06.
    function test_givenInsolventCustody_whenSeized_reverts() public {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature(
                "getOperatorAssets(address,address)",
                address(_asset),
                address(_core)
            ),
            abi.encode(uint256(2000e6), uint256(2000e6 - 1))
        );
        _expectRejected(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_Insolvent.selector,
                address(_asset),
                uint256(2000e6),
                uint256(2000e6 - 1),
                uint256(0)
            ),
            _borrowers(),
            _recipient
        );
    }

    // Scenarios: BLLIQ-SEIZE-I03.
    function test_givenZeroBorrowerAtAnyIndex_whenSeized_reverts(
        uint8 length_,
        uint8 index_,
        address caller_
    ) public {
        length_ = uint8(bound(length_, 1, 50));
        index_ = uint8(bound(index_, 0, uint256(length_) - 1));
        address[] memory borrowers = new address[](length_);
        for (uint256 i; i < length_; ++i) borrowers[i] = address(uint160(0x10000 + i));
        borrowers[index_] = address(0);
        _expectRejected(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector),
            borrowers,
            caller_
        );
    }

    // Scenarios: BLLIQ-SEIZE-P04, BLLIQ-SEIZE-P05.
    function test_whenHealthAtAndAboveThreshold_reverts() public {
        test_givenHealthyUnexpiredDebt_whenSeized_reverts(1e18, address(0));
        test_givenHealthyUnexpiredDebt_whenSeized_reverts(1e18 + 1, _borrower);
        test_givenHealthyUnexpiredDebt_whenSeized_reverts(type(uint256).max, address(this));
    }

    // Scenarios: BLLIQ-SEIZE-P07.
    function test_givenUnexpiredDebt_whenHealthBelowThreshold_thenSeizes(uint256 health_) public {
        health_ = bound(health_, 0, 1e18 - 1);
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encode(health_)
        );
        _assertSingleSeizure();
    }

    // Scenarios: BLLIQ-SEIZE-P07.
    function test_whenHealthOneUnitBelowThreshold_thenSeizes() public {
        test_givenUnexpiredDebt_whenHealthBelowThreshold_thenSeizes(1e18 - 1);
    }

    // Scenarios: BLLIQ-SEIZE-P07.
    function test_whenHealthZero_thenSeizes() public {
        test_givenUnexpiredDebt_whenHealthBelowThreshold_thenSeizes(0);
    }

    // Scenarios: BLLIQ-SEIZE-P09.
    function test_givenExpiredDebt_whenTimeIsMaximum_thenSeizes() public {
        test_givenExpiredHealthyDebt_whenSeized_thenAllowed(
            type(uint48).max - _position().maturity
        );
    }

    // Scenarios: BLLIQ-SEIZE-P09.
    function test_givenExpiredDebt_whenTimeJustAfterMaturity_thenSeizes() public {
        test_givenExpiredHealthyDebt_whenSeized_thenAllowed(1);
    }

    // Scenarios: BLLIQ-SEIZE-P04.
    function test_givenHealthyDebt_whenOneSecondBeforeMaturity_reverts() public {
        vm.warp(_position().maturity - 1);
        test_givenHealthyUnexpiredDebt_whenSeized_reverts(1e18, _recipient);
    }

    // Scenarios: BLLIQ-SEIZE-I02.
    function test_whenBatchFiftyOneContainsZeroBorrower_reverts() public {
        test_whenLargeBatchContainsZeroBorrower_reverts(51, _borrower);
    }

    // Scenarios: BLLIQ-SEIZE-I03.
    function test_whenZeroBorrowerAtFirstMiddleAndLast_reverts() public {
        test_givenZeroBorrowerAtAnyIndex_whenSeized_reverts(50, 0, address(0));
        test_givenZeroBorrowerAtAnyIndex_whenSeized_reverts(50, 25, _borrower);
        test_givenZeroBorrowerAtAnyIndex_whenSeized_reverts(50, 49, address(this));
    }

    // Scenarios: BLLIQ-SEIZE-A01, BLLIQ-SEIZE-L01.
    function test_whenCallerAndResultBoundarySeeds_thenForwardsUnchanged() public {
        test_whenPermissionlessKeeperSeizes_thenForwardsKeeperAndCoreResult(
            address(0),
            0,
            type(uint256).max
        );
        test_whenPermissionlessKeeperSeizes_thenForwardsKeeperAndCoreResult(
            _borrower,
            type(uint256).max,
            0
        );
        test_whenPermissionlessKeeperSeizes_thenForwardsKeeperAndCoreResult(address(this), 1, 1);
    }

    // Scenarios: BLLIQ-SEIZE-D04.
    function test_givenInventoryUnavailable_whenSeized_reverts(
        bool active_,
        bool enabled_,
        address caller_
    ) public {
        vm.assume(!active_ || !enabled_);
        _setPolicyState(_inventory, active_, enabled_);
        _expectRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_inventory)
            ),
            _borrowers(),
            caller_
        );
    }

    // Scenarios: BLLIQ-SEIZE-A02.
    function test_givenSettlementRoleRevoked_whenSeized_reverts(address caller_) public {
        _rolesAdmin.revokeRole(BL_LIQUIDATION_POLICY_ROLE, address(_liquidation));
        _expectRejected(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_LIQUIDATION_POLICY_ROLE),
            _borrowers(),
            caller_
        );
    }

    // Scenarios: BLLIQ-SEIZE-A03.
    function test_givenReportedKernelMismatch_whenSeized_thenGetterIsNotRead() public {
        vm.mockCall(
            address(_liquidation),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0x1234))
        );
        vm.expectCall(address(_liquidation), abi.encodeWithSignature("kernel()"), uint64(0));
        _assertSingleSeizure();
    }

    // Scenarios: BLLIQ-SEIZE-A03.
    function test_givenActionKernelGetterReverts_whenSeized_thenGetterIsNotRead() public {
        vm.mockCallRevert(
            address(_liquidation),
            abi.encodeWithSignature("kernel()"),
            hex"deadbeef"
        );
        vm.expectCall(address(_liquidation), abi.encodeWithSignature("kernel()"), uint64(0));
        _assertSingleSeizure();
    }

    // Scenarios: BLLIQ-SEIZE-A03.
    function test_givenReportedKernelMismatch_whenAnyKeeperSeizes(address caller_) public {
        vm.mockCall(
            address(_liquidation),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0x1234))
        );
        vm.expectCall(address(_liquidation), abi.encodeWithSignature("kernel()"), uint64(0));
        test_whenPermissionlessKeeperSeizes_thenForwardsKeeperAndCoreResult(
            caller_,
            7,
            1_999_999_993
        );
    }

    // Scenarios: BLLIQ-SEIZE-A03.
    function test_givenActionKernelGetterReverts_whenAnyKeeperSeizes(address caller_) public {
        vm.mockCallRevert(
            address(_liquidation),
            abi.encodeWithSignature("kernel()"),
            hex"deadbeef"
        );
        vm.expectCall(address(_liquidation), abi.encodeWithSignature("kernel()"), uint64(0));
        test_whenPermissionlessKeeperSeizes_thenForwardsKeeperAndCoreResult(
            caller_,
            7,
            1_999_999_993
        );
    }

    // Scenarios: BLLIQ-SEIZE-L06, BLLIQ-SEIZE-L07, BLLIQ-SEIZE-L08, BLLIQ-SEIZE-L09, BLLIQ-SEIZE-L10, BLLIQ-SEIZE-L11, BLLIQ-SEIZE-L12, BLLIQ-SEIZE-L13.
    function test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified(
        bool enabled_,
        bool coreActive_,
        bool coreEnabled_,
        address caller_
    ) public {
        _setPolicyState(_liquidation, true, enabled_);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_liquidation));
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _expectAdmissionRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_liquidation)
            ),
            caller_
        );
    }

    // Scenarios: BLLIQ-SEIZE-L02, BLLIQ-SEIZE-L03, BLLIQ-SEIZE-L04, BLLIQ-SEIZE-L05.
    function test_givenDisabledAction_whenSeized_thenLocalPauseWins(
        bool coreActive_,
        bool coreEnabled_,
        address caller_
    ) public {
        _liquidation.disable("");
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _expectAdmissionRejected(abi.encodeWithSelector(IEnabler.NotEnabled.selector), caller_);
    }

    // Scenarios: BLLIQ-SEIZE-D01, BLLIQ-SEIZE-D02, BLLIQ-SEIZE-D03.
    function test_givenCoreUnavailable_whenSeized_thenDependencyIdentified(
        bool active_,
        bool enabled_,
        address caller_
    ) public {
        vm.assume(!active_ || !enabled_);
        _setPolicyState(_core, active_, enabled_);
        _expectAdmissionRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            ),
            caller_
        );
    }

    // Scenarios: BLLIQ-SEIZE-D08.
    function test_givenPayoutReportsAnotherKernel_whenSeizedOrPreviewed_reverts(
        address caller_
    ) public {
        address reported = makeAddr("foreignPayoutKernel");
        vm.mockCall(address(_payout), abi.encodeWithSignature("kernel()"), abi.encode(reported));
        _expectRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_payout),
                address(_kernel),
                reported
            ),
            _borrowers(),
            caller_
        );
    }

    // Scenarios: BLLIQ-SEIZE-D05, BLLIQ-SEIZE-D06, BLLIQ-SEIZE-D07.
    function test_givenPayoutUnavailable_whenSeizedOrPreviewed_reverts(
        bool active_,
        bool enabled_,
        address caller_
    ) public {
        vm.assume(!active_ || !enabled_);
        _setPolicyState(_payout, active_, enabled_);
        _expectRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_payout)
            ),
            _borrowers(),
            caller_
        );
    }

    // Scenarios: BLLIQ-SEIZE-D05, BLLIQ-SEIZE-D06, BLLIQ-SEIZE-D07.
    function test_givenEachUnavailablePayoutState_whenSeized_thenDependencyIdentified() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPayoutUnavailable_whenSeizedOrPreviewed_reverts(true, false, address(0));
        assertTrue(vm.revertToState(checkpoint), "Restore Payout for inactive state");
        test_givenPayoutUnavailable_whenSeizedOrPreviewed_reverts(false, true, _borrower);
        assertTrue(vm.revertToState(checkpoint), "Restore Payout for both flags off");
        test_givenPayoutUnavailable_whenSeizedOrPreviewed_reverts(false, false, address(this));
    }

    // Scenarios: BLLIQ-SEIZE-L01.
    function test_givenActionReEnabled_whenSeized_thenDefaultSucceeds() public {
        _liquidation.disable("");
        _liquidation.reEnable();
        _assertSingleSeizure();
    }

    // Scenarios: BLLIQ-SEIZE-L01.
    function test_givenActionReactivated_whenSeized_thenDefaultSucceeds() public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_liquidation));
        _kernel.executeAction(Actions.ActivatePolicy, address(_liquidation));
        _assertSingleSeizure();
    }

    // Scenarios: BLLIQ-SEIZE-L02, BLLIQ-SEIZE-L03, BLLIQ-SEIZE-L04, BLLIQ-SEIZE-L05.
    function test_givenDisabledActionAndEveryCoreState_whenSeized_thenLocalPauseWins() public {
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                uint256 checkpoint = vm.snapshotState();
                test_givenDisabledAction_whenSeized_thenLocalPauseWins(
                    active != 0,
                    enabled != 0,
                    address(0)
                );
                assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for local pause seed");
            }
        }
    }

    // Scenarios: BLLIQ-SEIZE-L06, BLLIQ-SEIZE-L07, BLLIQ-SEIZE-L08, BLLIQ-SEIZE-L09, BLLIQ-SEIZE-L10, BLLIQ-SEIZE-L11, BLLIQ-SEIZE-L12, BLLIQ-SEIZE-L13.
    function test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified()
        public
    {
        for (uint256 localEnabled; localEnabled < 2; ++localEnabled) {
            for (uint256 active; active < 2; ++active) {
                for (uint256 enabled; enabled < 2; ++enabled) {
                    uint256 checkpoint = vm.snapshotState();
                    test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified(
                        localEnabled != 0,
                        active != 0,
                        enabled != 0,
                        _borrower
                    );
                    assertTrue(
                        vm.revertToState(checkpoint),
                        "Restore lifecycle for inactive action seed"
                    );
                }
            }
        }
    }

    // Scenarios: BLLIQ-SEIZE-D01, BLLIQ-SEIZE-D02, BLLIQ-SEIZE-D03.
    function test_givenEveryUnavailableCoreState_whenSeized_thenDependencyIdentified() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenCoreUnavailable_whenSeized_thenDependencyIdentified(true, false, address(0));
        assertTrue(vm.revertToState(checkpoint), "Restore Core for inactive seed");
        test_givenCoreUnavailable_whenSeized_thenDependencyIdentified(false, true, _borrower);
        assertTrue(vm.revertToState(checkpoint), "Restore Core for both flags off");
        test_givenCoreUnavailable_whenSeized_thenDependencyIdentified(false, false, address(this));
    }

    // Scenarios: BLLIQ-SEIZE-D04.
    function test_givenEachUnavailableInventoryState_whenSeized_thenDependencyIdentified() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenInventoryUnavailable_whenSeized_reverts(true, false, address(0));
        assertTrue(vm.revertToState(checkpoint), "Restore Inventory for inactive seed");
        test_givenInventoryUnavailable_whenSeized_reverts(false, true, _borrower);
        assertTrue(vm.revertToState(checkpoint), "Restore Inventory for both flags off");
        test_givenInventoryUnavailable_whenSeized_reverts(false, false, address(this));
    }
}

// forge-lint: disable-end(boolean-cst, calls-loop, literal-instead-of-constant, unsafe-typecast)
