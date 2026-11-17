// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Libraries
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansLensTest} from "./BurnerLoansLensTest.sol";
import {Actions} from "src/Kernel.sol";

// Raw units, tiny populations and numeric maxima are explicit test boundaries.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
contract BurnerLoansLensGetUnhealthyBorrowersBoundedForTest is BurnerLoansLensTest {
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

    // Scenarios: BLLENS-UNHEALTHY-P01.
    function test_givenMixedPage_whenQueried_thenExpiredDebtIsExcluded(address caller_) public {
        _canonicalScan();
        vm.prank(caller_);
        (address[] memory borrowers, uint256 cursor, uint256 reward) = IBurnerLoansLens(
            address(_lens)
        ).getUnhealthyBorrowersBoundedFor(
                address(this),
                address(_asset),
                0,
                type(uint256).max,
                type(uint256).max
            );
        assertEq(borrowers, _one(_CAROL), "Only the unexpired underwater borrower is selected");
        assertEq(cursor, 0, "Full page ends at the active-list sentinel");
        assertEq(reward, 0, "Protocol actor quote is zero");
    }

    // Scenarios: BLLENS-UNHEALTHY-P01, BLLENS-UNHEALTHY-N01.
    function test_givenMixedDebtAndMaturityBoundaries_whenQueried() public {
        _mixed();
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            uint64(2)
        );
        vm.recordLogs();
        _assertPage(0, type(uint256).max, type(uint256).max, _two(_ALICE, _DAVE), 0);
        assertEq(vm.getRecordedLogs().length, 0, "Static discovery emits no logs");
    }

    // Scenarios: BLLENS-UNHEALTHY-P01.
    function test_givenMissingPosition_whenQueried() public {
        _mixed();
        vm.mockCall(
            address(_floan),
            abi.encodeCall(
                IFLOANv1.getPositionIdForMarketAndBorrowerAt,
                (_core.marketId(address(_asset)), _DAVE, uint256(0))
            ),
            abi.encode(false, uint64(0))
        );
        _assertPage(0, 4, 4, _one(_ALICE), 0);
    }

    // Scenarios: BLLENS-UNHEALTHY-N01.
    function test_givenUnhealthyPositions_whenHealthBelowOne(uint256 health_) public {
        _mixed();
        _mockRisk(bound(health_, 0, 1e18 - 1));
        _assertPage(0, 4, 4, _two(_ALICE, _DAVE), 0);
    }

    // Scenarios: BLLENS-UNHEALTHY-N01.
    function test_givenHealthyPositions_whenHealthAtOrAboveOne(uint256 health_) public {
        _mixed();
        _mockRisk(bound(health_, 1e18, type(uint256).max));
        _assertPage(0, 4, 4, new address[](0), 0);
    }

    // Scenarios: BLLENS-UNHEALTHY-N01.
    function test_whenHealthBoundarySeedsQueried() public {
        test_givenUnhealthyPositions_whenHealthBelowOne(0);
        test_givenUnhealthyPositions_whenHealthBelowOne(1e18 - 1);
        test_givenHealthyPositions_whenHealthAtOrAboveOne(1e18);
        test_givenHealthyPositions_whenHealthAtOrAboveOne(1e18 + 1);
        test_givenHealthyPositions_whenHealthAtOrAboveOne(type(uint256).max);
    }

    // Scenarios: BLLENS-UNHEALTHY-N02.
    function test_givenMixedPage_whenLimitsFuzzed(
        address caller_,
        uint256 start_,
        uint256 count_,
        uint256 limit_
    ) public {
        _mixed();
        start_ = bound(start_, 0, 3);
        uint256 end = start_ + (count_ < 4 - start_ ? count_ : 4 - start_);
        address[] memory expected = new address[](2);
        uint256 returned;
        uint256 next = start_;
        // The independently fixed eligible indexes are0 and3; indexes1/2 are expired/debt-free.
        while (next < end && returned < limit_) {
            if (next == 0) expected[returned++] = _ALICE;
            if (next == 3) expected[returned++] = _DAVE;
            ++next;
        }
        address[] memory clipped = new address[](returned);
        for (uint256 i; i < returned; ++i) clipped[i] = expected[i];
        vm.prank(caller_);
        _assertPage(start_, count_, limit_, clipped, next == 4 ? 0 : next);
    }

    // Scenarios: BLLENS-UNHEALTHY-N02.
    function test_givenMixedPage_whenLimitBoundarySeedsQueried() public {
        _mixed();
        _assertPage(1, 0, type(uint256).max, new address[](0), 1);
        _assertPage(1, type(uint256).max, 0, new address[](0), 1);
        _assertPage(0, 1, 1, _one(_ALICE), 1);
        _assertPage(0, 4, 1, _one(_ALICE), 1);
        _assertPage(1, 2, 4, new address[](0), 3);
        _assertPage(1, 3, 1, _one(_DAVE), 0);
        _assertPage(0, 4, 2, _two(_ALICE, _DAVE), 0);
        _assertPage(0, 5, 4, _two(_ALICE, _DAVE), 0);
        _assertPage(3, type(uint256).max, type(uint256).max, _one(_DAVE), 0);
    }

    // Scenarios: BLLENS-UNHEALTHY-N03.
    function test_givenEmptyMarket_whenQueried(uint256 count_, uint256 limit_) public {
        _mockCount(0);
        _expectNoRiskReads();
        _assertPage(0, count_, limit_, new address[](0), 0);
        _assertPage(0, type(uint256).max, type(uint256).max, new address[](0), 0);
    }

    // Scenarios: BLLENS-UNHEALTHY-N03.
    function test_givenZeroLimit_whenQueried(bool zeroCount_) public {
        _mixed();
        _expectNoRiskReads();
        _assertPage(
            1,
            zeroCount_ ? 0 : type(uint256).max,
            zeroCount_ ? type(uint256).max : 0,
            new address[](0),
            1
        );
    }

    // Scenarios: BLLENS-UNHEALTHY-I01.
    function test_givenInvalidStart_whenQueried_reverts(uint256 start_, bool empty_) public {
        uint256 population = empty_ ? 0 : 4;
        _mockCount(population);
        start_ = bound(start_, population == 0 ? 1 : population, type(uint256).max);
        _assertInvalidStart(start_, population);
    }

    // Scenarios: BLLENS-UNHEALTHY-I01.
    function test_givenInvalidStart_whenBoundariesSeeded_reverts() public {
        _mockCount(4);
        _assertInvalidStart(4, 4);
        _assertInvalidStart(type(uint256).max, 4);
        _mockCount(0);
        _assertInvalidStart(1, 0);
        _assertInvalidStart(type(uint256).max, 0);
    }

    // Scenarios: BLLENS-UNHEALTHY-I02.
    function test_givenUnregisteredAsset_whenQueried_reverts(address asset_) public {
        vm.assume(!_core.isAssetRegistered(asset_));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset_
            )
        );
        _lens.getUnhealthyBorrowersBoundedFor(address(this), asset_, 0, 0, 0);
    }

    // Scenarios: BLLENS-UNHEALTHY-I02.
    function test_whenZeroAssetQueried_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                address(0)
            )
        );
        _lens.getUnhealthyBorrowersBoundedFor(address(this), address(0), 0, 0, 0);
    }

    // Scenarios: BLLENS-UNHEALTHY-D01.
    function test_givenCountFailure_whenQueried_reverts() public {
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.getActiveBorrowerCount.selector),
            abi.encodeWithSelector(FloanReadFailed.selector)
        );
        vm.expectRevert(FloanReadFailed.selector);
        _lens.getUnhealthyBorrowersBoundedFor(address(this), address(_asset), 0, 0, 0);
    }

    // Scenarios: BLLENS-UNHEALTHY-D01.
    function test_givenIndexFailure_whenQueried_reverts() public {
        _mixed();
        vm.mockCallRevert(
            address(_floan),
            abi.encodeCall(
                IFLOANv1.getActiveBorrowerAt,
                (_core.marketId(address(_asset)), uint256(0))
            ),
            abi.encodeWithSelector(FloanReadFailed.selector)
        );
        vm.expectRevert(FloanReadFailed.selector);
        _lens.getUnhealthyBorrowersBoundedFor(address(this), address(_asset), 0, 1, 1);
    }

    // Scenarios: BLLENS-UNHEALTHY-D01.
    function test_givenPositionFailure_whenQueried_reverts() public {
        _mixed();
        vm.mockCallRevert(
            address(_floan),
            abi.encodeCall(IFLOANv1.getPosition, (uint64(uint160(_ALICE)))),
            abi.encodeWithSelector(FloanReadFailed.selector)
        );
        vm.expectRevert(FloanReadFailed.selector);
        _lens.getUnhealthyBorrowersBoundedFor(address(this), address(_asset), 0, 1, 1);
    }

    // Scenarios: BLLENS-UNHEALTHY-D02.
    function test_givenSnapshotFailure_whenQueried_reverts(bool allExpired_) public {
        _mixed();
        if (allExpired_) {
            _mockPosition(_ALICE, 1, 1, uint48(vm.getBlockTimestamp()), 1);
            _mockPosition(_DAVE, 1, type(uint128).max, uint48(vm.getBlockTimestamp()), 1);
        }
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.snapshot, (address(_asset))),
            abi.encodeWithSelector(SnapshotReadFailed.selector)
        );
        vm.expectRevert(SnapshotReadFailed.selector);
        _lens.getUnhealthyBorrowersBoundedFor(address(this), address(_asset), 0, 4, 4);
    }

    // Scenarios: BLLENS-UNHEALTHY-P01, BLLENS-UNHEALTHY-N01.
    function test_givenAllExpired_givenHealthReadFails_whenQueried() public {
        _mixed();
        _mockPosition(_ALICE, 1, 1, uint48(vm.getBlockTimestamp()), 1);
        _mockPosition(_DAVE, 1, type(uint128).max, uint48(vm.getBlockTimestamp() - 1), 1);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encodeWithSelector(RiskHealthFailed.selector)
        );
        _assertPage(0, 4, 4, new address[](0), 0);
    }

    // Scenarios: BLLENS-UNHEALTHY-D02.
    function test_givenHealthFailure_whenQueried_reverts() public {
        _mixed();
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encodeWithSelector(RiskHealthFailed.selector)
        );
        vm.expectRevert(RiskHealthFailed.selector);
        _lens.getUnhealthyBorrowersBoundedFor(address(this), address(_asset), 0, 4, 4);
    }

    // Scenarios: BLLENS-UNHEALTHY-D03.
    function test_givenCustodyQuoteFailure_whenQueried_reverts() public {
        _mixed();
        vm.mockCallRevert(
            address(_depositManager),
            abi.encodeWithSelector(IDepositManagerV1_1.previewWithdraw.selector),
            abi.encodeWithSelector(WithdrawalPreviewFailed.selector)
        );
        vm.expectRevert(WithdrawalPreviewFailed.selector);
        _lens.getUnhealthyBorrowersBoundedFor(address(this), address(_asset), 0, 4, 4);
    }

    // Scenarios: BLLENS-UNHEALTHY-D03.
    function test_givenRewardQuoteFailure_whenQueried_reverts() public {
        _mixed();
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.keeperReward.selector),
            abi.encodeWithSelector(RewardQuoteFailed.selector)
        );
        vm.expectRevert(RewardQuoteFailed.selector);
        _lens.getUnhealthyBorrowersBoundedFor(address(this), address(_asset), 0, 4, 4);
    }

    // Scenarios: BLLENS-UNHEALTHY-A01.
    function test_givenOrdinaryActor_whenQuoted(address caller_, address actor_) public {
        vm.assume(
            !_roles.hasRole(actor_, HEART_ROLE) && !_roles.hasRole(actor_, BURNER_LOANS_SEIZER_ROLE)
        );
        _mixed();
        _assertActorQuote(caller_, actor_, false, 7);
    }

    // Scenarios: BLLENS-UNHEALTHY-A01.
    function test_givenProtocolCaller_whenZeroOrdinaryActorQuoted() public {
        _mixed();
        _assertActorQuote(address(this), address(0), false, 7);
    }

    // Scenarios: BLLENS-UNHEALTHY-A01.
    function test_givenProtocolActor_whenRoleClassesFuzzed(
        address caller_,
        address actor_,
        uint8 roleClass_
    ) public {
        vm.assume(
            actor_ != address(0) &&
                !_roles.hasRole(actor_, HEART_ROLE) &&
                !_roles.hasRole(actor_, BURNER_LOANS_SEIZER_ROLE)
        );
        roleClass_ = uint8(bound(roleClass_, 0, 2));
        if (roleClass_ != 1) _rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, actor_);
        if (roleClass_ != 0) _rolesAdmin.grantRole(HEART_ROLE, actor_);
        _mixed();
        _assertActorQuote(caller_, actor_, true, 0);
    }

    // Scenarios: BLLENS-UNHEALTHY-A01.
    function test_givenSeizerOnlyActor_whenQuoted() public {
        test_givenProtocolActor_whenRoleClassesFuzzed(address(0), _BOB, 0);
    }

    // Scenarios: BLLENS-UNHEALTHY-A01.
    function test_givenHeartOnlyActor_whenQuoted() public {
        test_givenProtocolActor_whenRoleClassesFuzzed(address(0), _BOB, 1);
    }

    // Scenarios: BLLENS-UNHEALTHY-A01.
    function test_givenBothProtocolRoles_whenQuoted() public {
        test_givenProtocolActor_whenRoleClassesFuzzed(address(0), _BOB, 2);
    }

    // Scenarios: BLLENS-UNHEALTHY-L01.
    function test_givenCoreLifecycle_whenQueried(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _mixed();
        _setCoreLifecycle(active_, enabled_);
        vm.prank(caller_);
        _assertPage(0, 4, 4, _two(_ALICE, _DAVE), 0);
        if (!active_) _kernel.executeAction(Actions.ActivatePolicy, address(_core));
        if (!enabled_) _core.reEnable();
        _assertPage(0, 4, 4, _two(_ALICE, _DAVE), 0);
    }

    function _mixed() private {
        address[] memory borrowers = new address[](4);
        borrowers[0] = _ALICE;
        borrowers[1] = _BOB;
        borrowers[2] = _CAROL;
        borrowers[3] = _DAVE;
        _mockBorrowers(borrowers);
        uint48 now_ = uint48(vm.getBlockTimestamp());
        _mockPosition(_ALICE, 1, 1, now_ + 1, 1);
        _mockPosition(_BOB, 1, type(uint128).max, now_, 1);
        _mockPosition(_CAROL, 1, 0, now_ + 1, 1);
        _mockPosition(_DAVE, 1, type(uint128).max, type(uint48).max, 1);
        _mockRisk(5e17);
    }

    function _assertPage(
        uint256 start_,
        uint256 count_,
        uint256 limit_,
        address[] memory expected_,
        uint256 next_
    ) private view {
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getUnhealthyBorrowersBoundedFor(
                address(this),
                address(_asset),
                start_,
                count_,
                limit_
            );
        assertEq(borrowers, expected_, "Exact unexpired unhealthy selection");
        assertEq(cursor, next_, "Exact first unexamined active-list index");
        assertEq(reward, 0, "Protocol actor quote remains zero");
    }

    function _assertInvalidStart(uint256 start_, uint256 population_) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
                start_,
                population_
            )
        );
        _lens.getUnhealthyBorrowersBoundedFor(address(this), address(_asset), start_, 0, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
                start_,
                population_
            )
        );
        _lens.getUnhealthyBorrowersBoundedFor(
            address(this),
            address(_asset),
            start_,
            type(uint256).max,
            type(uint256).max
        );
    }

    function _assertActorQuote(
        address caller_,
        address actor_,
        bool protocol_,
        uint256 reward_
    ) private {
        bytes memory quote = abi.encodeCall(
            IBurnerLoansRisk.keeperReward,
            (
                _core.marketId(address(_asset)),
                uint256(type(uint128).max) + 1,
                uint256(2),
                uint256(77),
                protocol_
            )
        );
        vm.mockCall(address(_risk), quote, abi.encode(reward_));
        vm.expectCall(address(_risk), quote, uint64(1));
        vm.expectCall(
            address(_depositManager),
            abi.encodeCall(
                IDepositManagerV1_1.previewWithdraw,
                (IERC20(address(_asset)), uint256(2), false)
            ),
            uint64(1)
        );
        vm.prank(caller_);
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getUnhealthyBorrowersBoundedFor(actor_, address(_asset), 0, 4, 4);
        assertEq(
            borrowers,
            _two(_ALICE, _DAVE),
            "Actor does not change maturity or health eligibility"
        );
        assertEq(cursor, 0, "Actor quote scans the complete page");
        assertEq(reward, reward_, "Aggregate reward belongs to actor independently of caller");
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
