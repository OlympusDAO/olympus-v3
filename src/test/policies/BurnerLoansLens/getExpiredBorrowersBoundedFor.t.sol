// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Libraries
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansLensTest} from "./BurnerLoansLensTest.sol";

// Small canonical populations and raw token units are intentional boundary fixtures.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
contract BurnerLoansLensGetExpiredBorrowersBoundedForTest is BurnerLoansLensTest {
    function setUp() public override {
        super.setUp();
        _rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, address(this));
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSelector(IDepositManagerV1_1.previewWithdraw.selector),
            abi.encode(IERC20(address(_asset)), uint256(77))
        );
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.keeperReward.selector),
            abi.encode(uint256(0))
        );
    }

    // Scenarios: BLLENS-EXPIRED-I01.
    function test_givenInvalidStart_whenQueried_reverts(uint256 start_, bool empty_) public {
        uint256 population = empty_ ? 0 : 4;
        _mockCount(population);
        start_ = bound(start_, population == 0 ? 1 : population, type(uint256).max);
        _assertInvalidStart(start_, population);
    }

    // Scenarios: BLLENS-EXPIRED-I01.
    function test_givenInvalidStart_whenBoundarySeedsQueried_reverts() public {
        _mockCount(4);
        _assertInvalidStart(4, 4);
        _assertInvalidStart(type(uint256).max, 4);
        _mockCount(0);
        _assertInvalidStart(1, 0);
        _assertInvalidStart(type(uint256).max, 0);
    }

    // Scenarios: BLLENS-EXPIRED-I02.
    function test_givenUnregisteredAsset_whenQueried_reverts(address asset_) public {
        vm.assume(!_core.isAssetRegistered(asset_));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset_
            )
        );
        _lens.getExpiredBorrowersBoundedFor(address(this), asset_, 0, 0, 0);
    }

    // Scenarios: BLLENS-EXPIRED-D01.
    function test_givenCountFailure_whenQueried_reverts() public {
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.getActiveBorrowerCount.selector),
            abi.encodeWithSelector(FloanReadFailed.selector)
        );
        vm.expectRevert(FloanReadFailed.selector);
        _lens.getExpiredBorrowersBoundedFor(address(this), address(_asset), 0, 0, 0);
    }

    // Scenarios: BLLENS-EXPIRED-D01.
    function test_givenIndexFailure_whenQueried_reverts() public {
        _mockCount(1);
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.getActiveBorrowerAt.selector),
            abi.encodeWithSelector(FloanReadFailed.selector)
        );
        vm.expectRevert(FloanReadFailed.selector);
        _lens.getExpiredBorrowersBoundedFor(address(this), address(_asset), 0, 1, 1);
    }

    // Scenarios: BLLENS-EXPIRED-D01.
    function test_givenPositionFailure_whenQueried_reverts() public {
        _mixed();
        vm.mockCallRevert(
            address(_floan),
            abi.encodeCall(IFLOANv1.getPosition, (uint64(uint160(_ALICE)))),
            abi.encodeWithSelector(FloanReadFailed.selector)
        );
        vm.expectRevert(FloanReadFailed.selector);
        _lens.getExpiredBorrowersBoundedFor(address(this), address(_asset), 0, 1, 1);
    }

    // Scenarios: BLLENS-EXPIRED-P01, BLLENS-EXPIRED-N01.
    function test_givenMixedPage_whenQueried(address caller_) public {
        _mixed();
        _expectNoSelectionPricing();
        vm.recordLogs();
        vm.prank(caller_);
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getExpiredBorrowersBoundedFor(
                address(this),
                address(_asset),
                0,
                type(uint256).max,
                type(uint256).max
            );
        assertEq(
            borrowers,
            _two(_BOB, _DAVE),
            "Only positive expired principal selected after unexpired prefix"
        );
        assertEq(cursor, 0, "Final suffix wraps next visit");
        assertEq(reward, 0, "Protocol actor quote is zero");
        assertEq(vm.getRecordedLogs().length, 0, "Discovery emits no logs");
    }

    // Scenarios: BLLENS-EXPIRED-P01.
    function test_givenMissingPosition_whenQueried() public {
        _mixed();
        vm.mockCall(
            address(_floan),
            abi.encodeCall(
                IFLOANv1.getPositionIdForMarketAndBorrowerAt,
                (_core.marketId(address(_asset)), _BOB, uint256(0))
            ),
            abi.encode(false, uint64(0))
        );
        _expectNoSelectionPricing();
        _assertPage(0, 4, 4, _one(_DAVE), 0);
    }

    // Scenarios: BLLENS-EXPIRED-N02.
    function test_givenResultCapReached_whenQueried() public {
        _mixed();
        vm.expectCall(
            address(_floan),
            abi.encodeCall(
                IFLOANv1.getActiveBorrowerAt,
                (_core.marketId(address(_asset)), uint256(2))
            ),
            uint64(0)
        );
        _assertPage(0, type(uint256).max, 1, _one(_BOB), 2);
    }

    // Scenarios: BLLENS-EXPIRED-I02.
    function test_whenZeroAssetQueried_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                address(0)
            )
        );
        _lens.getExpiredBorrowersBoundedFor(address(this), address(0), 0, 0, 0);
    }

    // Scenarios: BLLENS-EXPIRED-P02.
    function test_givenAllExpired_whenQueried() public {
        _mockBorrowers(_two(_ALICE, _BOB));
        _mockPosition(_ALICE, 1, 1, uint48(block.timestamp), 1);
        _mockPosition(_BOB, 1, type(uint128).max, uint48(block.timestamp - 1), 1);
        _expectNoSelectionPricing();
        _assertPage(0, type(uint256).max, type(uint256).max, _two(_ALICE, _BOB), 0);
    }

    // Scenarios: BLLENS-EXPIRED-P02, BLLENS-EXPIRED-N01.
    function test_givenAllUnexpired_whenQueried() public {
        _mockBorrowers(_two(_ALICE, _BOB));
        _mockPosition(_ALICE, 1, 1, uint48(block.timestamp + 1), 1);
        _mockPosition(_BOB, 1, type(uint128).max, type(uint48).max, 1);
        _expectNoEconomicReads();
        _assertPage(0, type(uint256).max, type(uint256).max, new address[](0), 0);
    }

    // Scenarios: BLLENS-EXPIRED-N02.
    function test_givenMixedPage_whenLimitsFuzzed(
        address caller_,
        uint256 start_,
        uint256 count_,
        uint256 limit_
    ) public {
        _mixed();
        start_ = bound(start_, 0, 3);
        _expectNoSelectionPricing();
        // Independent model: fixed eligible indexes 1 and 3 in a four-entry list.
        uint256 end = start_ + (count_ < 4 - start_ ? count_ : 4 - start_);
        address[] memory expected = new address[](2);
        uint256 returned;
        uint256 next = start_;
        while (next < end && returned < limit_) {
            if (next == 1) expected[returned++] = _BOB;
            if (next == 3) expected[returned++] = _DAVE;
            ++next;
        }
        address[] memory clipped = new address[](returned);
        for (uint256 i; i < returned; ++i) clipped[i] = expected[i];
        if (next == 4) next = 0;
        vm.prank(caller_);
        _assertPage(start_, count_, limit_, clipped, next);
    }

    // Scenarios: BLLENS-EXPIRED-N02.
    function test_givenMixedPage_whenLimitBoundariesSeeded() public {
        _mixed();
        _expectNoSelectionPricing();
        _assertPage(1, 0, type(uint256).max, new address[](0), 1);
        _assertPage(1, type(uint256).max, 0, new address[](0), 1);
        _assertPage(0, 1, 1, new address[](0), 1);
        _assertPage(0, 2, 1, _one(_BOB), 2);
        _assertPage(0, 4, 1, _one(_BOB), 2);
        _assertPage(0, 4, 2, _two(_BOB, _DAVE), 0);
        _assertPage(0, 5, 4, _two(_BOB, _DAVE), 0);
        _assertPage(2, type(uint256).max, type(uint256).max, _one(_DAVE), 0);
        _assertPage(3, 1, 1, _one(_DAVE), 0);
    }

    // Scenarios: BLLENS-EXPIRED-N03.
    function test_givenEmptyMarket_whenQueried(uint256 count_, uint256 limit_) public {
        _mockCount(0);
        _expectNoEconomicReads();
        vm.expectCall(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.getActiveBorrowerAt.selector),
            uint64(0)
        );
        _assertPage(0, count_, limit_, new address[](0), 0);
        _assertPage(0, 0, 0, new address[](0), 0);
        _assertPage(0, 1, 1, new address[](0), 0);
        _assertPage(0, type(uint256).max, type(uint256).max, new address[](0), 0);
    }

    // Scenarios: BLLENS-EXPIRED-L01.
    function test_givenCoreLifecycle_whenQueried(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _mixed();
        _setCoreLifecycle(active_, enabled_);
        vm.prank(caller_);
        _assertPage(0, 4, 4, _two(_BOB, _DAVE), 0);
        if (!active_) _kernel.executeAction(Actions.ActivatePolicy, address(_core));
        if (!enabled_) _core.reEnable();
        _assertPage(0, 4, 4, _two(_BOB, _DAVE), 0);
    }

    // Scenarios: BLLENS-EXPIRED-A01.
    function test_givenProtocolActorRoles_givenSnapshotFailure_whenQueried(address caller_) public {
        _mixed();
        _failSnapshot();
        _expectNoSelectionPricing();
        vm.expectCall(
            address(_risk),
            abi.encodeCall(
                IBurnerLoansRisk.keeperReward,
                (
                    _core.marketId(address(_asset)),
                    uint256(type(uint128).max) + 1,
                    uint256(2),
                    uint256(77),
                    true
                )
            ),
            uint64(3)
        );
        vm.prank(caller_);
        _assertPage(0, 4, 4, _two(_BOB, _DAVE), 0);
        _rolesAdmin.grantRole(HEART_ROLE, address(this));
        vm.prank(caller_);
        _assertPage(0, 4, 4, _two(_BOB, _DAVE), 0);
        _rolesAdmin.revokeRole(BURNER_LOANS_SEIZER_ROLE, address(this));
        vm.prank(caller_);
        _assertPage(0, 4, 4, _two(_BOB, _DAVE), 0);
    }

    // Scenarios: BLLENS-EXPIRED-A02.
    function test_givenOrdinaryActor_whenQuoted(address caller_, address actor_) public {
        vm.assume(
            !_roles.hasRole(actor_, HEART_ROLE) && !_roles.hasRole(actor_, BURNER_LOANS_SEIZER_ROLE)
        );
        _mixed();
        _ordinaryQuote(caller_, actor_);
    }

    // Scenarios: BLLENS-EXPIRED-A02.
    function test_givenProtocolCaller_whenZeroOrdinaryActorQuoted() public {
        _mixed();
        _ordinaryQuote(address(this), address(0));
    }

    // Scenarios: BLLENS-EXPIRED-D02.
    function test_givenZeroRewardQuote_givenOrdinaryActor_givenSnapshotFailure_whenQueried(
        address actor_
    ) public {
        vm.assume(
            !_roles.hasRole(actor_, HEART_ROLE) && !_roles.hasRole(actor_, BURNER_LOANS_SEIZER_ROLE)
        );
        _mixed();
        _failSnapshot();
        _expectNoSelectionPricing();
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getExpiredBorrowersBoundedFor(actor_, address(_asset), 0, 4, 4);
        assertEq(
            borrowers,
            _two(_BOB, _DAVE),
            "Maturity selection does not impose reward-price reads"
        );
        assertEq(cursor, 0, "Zero reward quote reaches canonical end");
        assertEq(reward, 0, "Lens forwards Risk's zero quote without a separate price check");
    }

    // Scenarios: BLLENS-EXPIRED-D03.
    function test_givenWithdrawalQuoteFailure_whenQueried_reverts() public {
        _mixed();
        vm.mockCallRevert(
            address(_depositManager),
            abi.encodeWithSelector(IDepositManagerV1_1.previewWithdraw.selector),
            abi.encodeWithSelector(WithdrawalPreviewFailed.selector)
        );
        vm.expectRevert(WithdrawalPreviewFailed.selector);
        _lens.getExpiredBorrowersBoundedFor(address(this), address(_asset), 0, 4, 4);
    }

    // Scenarios: BLLENS-EXPIRED-D04.
    function test_givenRewardQuoteFailure_whenQueried_reverts() public {
        _mixed();
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.keeperReward.selector),
            abi.encodeWithSelector(RewardQuoteFailed.selector)
        );
        vm.expectRevert(RewardQuoteFailed.selector);
        _lens.getExpiredBorrowersBoundedFor(address(this), address(_asset), 0, 4, 4);
    }

    function _ordinaryQuote(address caller_, address actor_) internal {
        vm.expectCall(
            address(_depositManager),
            abi.encodeCall(
                IDepositManagerV1_1.previewWithdraw,
                (IERC20(address(_asset)), uint256(2), false)
            ),
            uint64(1)
        );
        bytes memory quote = abi.encodeCall(
            IBurnerLoansRisk.keeperReward,
            (
                _core.marketId(address(_asset)),
                uint256(type(uint128).max) + 1,
                uint256(2),
                uint256(77),
                false
            )
        );
        vm.mockCall(address(_risk), quote, abi.encode(uint256(7)));
        vm.expectCall(address(_risk), quote, uint64(1));
        vm.expectCall(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.snapshot, (address(_asset))),
            uint64(0)
        );
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            uint64(0)
        );
        vm.prank(caller_);
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getExpiredBorrowersBoundedFor(actor_, address(_asset), 0, 4, 4);
        assertEq(borrowers, _two(_BOB, _DAVE), "Actor quote uses only expired debt");
        assertEq(cursor, 0, "Quoted expiry suffix ends at wrap");
        assertEq(reward, 7, "Aggregate quote belongs to actor independently of caller roles");
    }

    function _failSnapshot() internal {
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.snapshot, (address(_asset))),
            abi.encodeWithSelector(SnapshotReadFailed.selector)
        );
    }

    function _expectNoSelectionPricing() internal {
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            uint64(0)
        );
    }

    function _mixed() internal {
        _canonicalScan();
        _mockPosition(_ALICE, 1, 1, uint48(block.timestamp + 1), 1);
        _mockPosition(_BOB, 1, 1, uint48(block.timestamp), 1);
        _mockPosition(_CAROL, 1, 0, uint48(block.timestamp - 1), 1);
        _mockPosition(_DAVE, 1, type(uint128).max, uint48(block.timestamp - 1), 1);
    }

    function _expectNoEconomicReads() internal {
        _expectNoRiskReads();
        vm.expectCall(address(_depositManager), bytes(""), uint64(0));
        vm.expectCall(address(_roles), bytes(""), uint64(0));
    }

    function _assertPage(
        uint256 start_,
        uint256 count_,
        uint256 limit_,
        address[] memory expected_,
        uint256 cursor_
    ) internal view {
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getExpiredBorrowersBoundedFor(address(this), address(_asset), start_, count_, limit_);
        assertEq(borrowers, expected_, "Exact canonical expired selection");
        assertEq(cursor, cursor_, "Exact first unexamined cursor");
        assertEq(reward, 0, "Protocol actor quote is zero");
    }

    function _assertInvalidStart(uint256 start_, uint256 population_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
                start_,
                population_
            )
        );
        _lens.getExpiredBorrowersBoundedFor(address(this), address(_asset), start_, 0, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
                start_,
                population_
            )
        );
        _lens.getExpiredBorrowersBoundedFor(
            address(this),
            address(_asset),
            start_,
            type(uint256).max,
            type(uint256).max
        );
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
