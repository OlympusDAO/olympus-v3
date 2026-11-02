// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";

import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";

import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansLensScanTest} from "./fixtures/BurnerLoansLensScanTest.sol";

// Explicit boundary values, role-classification booleans and casts are test expectations.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return,boolean-cst)

contract BurnerLoansLensGetSeizableBorrowersTest is BurnerLoansLensScanTest {
    // Scenarios: BLLENS-SEIZABLE-L01.
    function test_givenActiveEnabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(true, true);
        _canonicalScan();
        _prepareReward(40e9, 400e6, 77, false, 17);
        _assumeOrdinary(caller_);
        _assertScan(caller_, 0, 4, _two(_ALICE, _CAROL), 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-L02.
    function test_givenActiveDisabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(true, false);
        _canonicalScan();
        _prepareReward(40e9, 400e6, 77, false, 17);
        _assumeOrdinary(caller_);
        _assertScan(caller_, 0, 4, _two(_ALICE, _CAROL), 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-L03.
    function test_givenInactiveEnabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(false, true);
        _canonicalScan();
        _prepareReward(40e9, 400e6, 77, false, 17);
        _assumeOrdinary(caller_);
        _assertScan(caller_, 0, 4, _two(_ALICE, _CAROL), 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-L04.
    function test_givenInactiveDisabledCore_whenQueried(address caller_) public {
        _setCoreLifecycle(false, false);
        _canonicalScan();
        _prepareReward(40e9, 400e6, 77, false, 17);
        _assumeOrdinary(caller_);
        _assertScan(caller_, 0, 4, _two(_ALICE, _CAROL), 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-I01.
    function test_whenUnknownAsset_revertsBeforeBounds(
        address caller_,
        uint256 start_,
        uint256 count_
    ) public {
        address asset = makeAddr("unregistered");
        _expectNoRiskReads();
        vm.expectCall(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.getActiveBorrowerCount.selector),
            uint64(0)
        );
        _assertScanRevert(
            caller_,
            asset,
            start_,
            count_,
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset
            )
        );
    }

    // Scenarios: BLLENS-SEIZABLE-I02.
    function test_whenZeroAsset_reverts(address caller_) public {
        _assertScanRevert(
            caller_,
            address(0),
            0,
            1,
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                address(0)
            )
        );
    }

    // Scenarios: BLLENS-SEIZABLE-I03.
    function test_givenNonemptyPopulation_whenStartIsOutOfRange_reverts(
        address caller_,
        uint256 population_,
        uint256 start_,
        uint256 count_
    ) public {
        population_ = bound(population_, 1, type(uint256).max);
        start_ = bound(start_, population_, type(uint256).max);
        _mockCount(population_);
        _expectNoScanWork();
        bytes memory failure = abi.encodeWithSelector(
            IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
            start_,
            population_
        );
        _assertScanRevert(caller_, address(_asset), start_, count_, failure);
        _assertScanRevert(caller_, address(_asset), start_, 0, failure);
        _assertScanRevert(caller_, address(_asset), start_, 1, failure);
        _assertScanRevert(caller_, address(_asset), start_, type(uint256).max, failure);
        _assertInvalidStartCounts(caller_, population_, population_);
        _assertInvalidStartCounts(caller_, type(uint256).max, population_);
        if (population_ != type(uint256).max)
            _assertInvalidStartCounts(caller_, population_ + 1, population_);
    }

    // Scenarios: BLLENS-SEIZABLE-I03.
    function test_givenEqualCount_whenInvalidStartSeeded_reverts(address caller_) public {
        _mockCount(4);
        _expectNoScanWork();
        _assertInvalidStartCounts(caller_, 4, 4);
    }

    // Scenarios: BLLENS-SEIZABLE-I03.
    function test_givenAboveCount_whenInvalidStartSeeded_reverts(address caller_) public {
        _mockCount(4);
        _expectNoScanWork();
        _assertInvalidStartCounts(caller_, 5, 4);
    }

    // Scenarios: BLLENS-SEIZABLE-I03.
    function test_givenMaximumStart_whenInvalidStartSeeded_reverts(address caller_) public {
        _mockCount(4);
        _expectNoScanWork();
        _assertInvalidStartCounts(caller_, type(uint256).max, 4);
    }

    // Scenarios: BLLENS-SEIZABLE-I03.
    function test_givenMaximumPopulation_whenInvalidStartSeeded_reverts(address caller_) public {
        _mockCount(type(uint256).max);
        _expectNoScanWork();
        _assertInvalidStartCounts(caller_, type(uint256).max, type(uint256).max);
    }

    // Scenarios: BLLENS-SEIZABLE-I03.
    function test_givenOneBorrower_whenInvalidStartSeeded_reverts(address caller_) public {
        _mockCount(1);
        _expectNoScanWork();
        _assertInvalidStartCounts(caller_, 1, 1);
    }

    // Scenarios: BLLENS-SEIZABLE-I04.
    function test_givenEmptyPopulation_whenStartIsNonzero_reverts(
        address caller_,
        uint256 start_,
        uint256 count_
    ) public {
        start_ = bound(start_, 1, type(uint256).max);
        _expectNoScanWork();
        bytes memory failure = abi.encodeWithSelector(
            IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
            start_,
            uint256(0)
        );
        _assertScanRevert(caller_, address(_asset), start_, count_, failure);
        _assertScanRevert(caller_, address(_asset), start_, 0, failure);
        _assertScanRevert(caller_, address(_asset), start_, 1, failure);
        _assertScanRevert(caller_, address(_asset), start_, type(uint256).max, failure);
    }

    // Scenarios: BLLENS-SEIZABLE-I04.
    function test_givenEmptyPopulation_whenOneStartSeeded_reverts(address caller_) public {
        _expectNoScanWork();
        _assertInvalidStartCounts(caller_, 1, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-I04.
    function test_givenEmptyPopulation_whenMaximumStartSeeded_reverts(address caller_) public {
        _expectNoScanWork();
        _assertInvalidStartCounts(caller_, type(uint256).max, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-P03.
    function test_givenEmptyMarket_whenQueried(address caller_, uint256 count_) public {
        _expectNoScanWork();
        _assertScan(caller_, 0, count_, new address[](0), 0, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-P03.
    function test_givenEmptyMarket_whenCount0Seeded(address caller_) public {
        _expectNoScanWork();
        _assertScan(caller_, 0, 0, new address[](0), 0, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-P03.
    function test_givenEmptyMarket_whenCount1Seeded(address caller_) public {
        _expectNoScanWork();
        _assertScan(caller_, 0, 1, new address[](0), 0, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-P03.
    function test_givenEmptyMarket_whenCountMaximumSeeded(address caller_) public {
        _expectNoScanWork();
        _assertScan(caller_, 0, type(uint256).max, new address[](0), 0, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-N02.
    function test_givenZeroCount_whenStartIsValid(
        address caller_,
        uint256 population_,
        uint256 start_
    ) public {
        population_ = bound(population_, 1, type(uint256).max);
        start_ = bound(start_, 0, population_ - 1);
        _mockCount(population_);
        _expectNoScanWork();
        _assertScan(caller_, start_, 0, new address[](0), start_, 0);
        _assertScan(caller_, 0, 0, new address[](0), 0, 0);
        _assertScan(caller_, population_ - 1, 0, new address[](0), population_ - 1, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-N02.
    function test_givenZeroCount_whenFirstOfOneSeeded(address caller_) public {
        _mockCount(1);
        _expectNoScanWork();
        _assertScan(caller_, 0, 0, new address[](0), 0, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-N02.
    function test_givenZeroCount_whenLastOfFourSeeded(address caller_) public {
        _mockCount(4);
        _expectNoScanWork();
        _assertScan(caller_, 3, 0, new address[](0), 3, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-N02.
    function test_givenZeroCount_whenLastOfMaximumSeeded(address caller_) public {
        _mockCount(type(uint256).max);
        _expectNoScanWork();
        _assertScan(caller_, type(uint256).max - 1, 0, new address[](0), type(uint256).max - 1, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-N04.
    function test_givenCanonicalList_whenFirstBorrowerScanned(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        _prepareReward(10e9, 100e6, 77, false, 17);
        _expectCanonicalVisits(0, 1);
        _assertScan(caller_, 0, 1, _one(_ALICE), 1, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-N05.
    function test_givenCanonicalList_whenHealthyConsumesBudgetScanned(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        _prepareReward(10e9, 100e6, 77, false, 17);
        _expectCanonicalVisits(0, 2);
        _assertScan(caller_, 0, 2, _one(_ALICE), 2, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-N06.
    function test_givenCanonicalList_whenFirstThreeScanned(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        _prepareReward(40e9, 400e6, 77, false, 17);
        _expectCanonicalVisits(0, 3);
        _assertScan(caller_, 0, 3, _two(_ALICE, _CAROL), 3, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-N07.
    function test_givenCanonicalList_whenFinalTwoScanned(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        _prepareReward(30e9, 300e6, 77, false, 17);
        _expectCanonicalVisits(2, 2);
        _assertScan(caller_, 2, 2, _one(_CAROL), 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-N08.
    function test_givenCanonicalList_whenHealthyFinalBorrowerScanned(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.keeperReward.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_depositManager),
            abi.encodeWithSignature("previewWithdraw(address,uint256,bool)"),
            uint64(0)
        );
        _expectCanonicalVisits(3, 1);
        _assertScan(caller_, 3, 3, new address[](0), 0, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-N12.
    function test_givenCanonicalList_whenStartExceedsCountScanned(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.keeperReward.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_depositManager),
            abi.encodeWithSignature("previewWithdraw(address,uint256,bool)"),
            uint64(0)
        );
        _expectCanonicalVisits(3, 1);
        _assertScan(caller_, 3, 1, new address[](0), 0, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-N11.
    function test_givenCanonicalList_whenMaximumSuffixCountScanned(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        _prepareReward(30e9, 300e6, 77, false, 17);
        _expectCanonicalVisits(1, 3);
        _assertScan(caller_, 1, type(uint256).max, _one(_CAROL), 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-N03.
    function test_givenCanonicalList_whenExactPopulationCountScanned(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        _prepareReward(40e9, 400e6, 77, false, 17);
        _expectCanonicalVisits(0, 4);
        _assertScan(caller_, 0, 4, _two(_ALICE, _CAROL), 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-N03.
    function test_givenCanonicalList_whenAbovePopulationCountScanned(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        _prepareReward(40e9, 400e6, 77, false, 17);
        _expectCanonicalVisits(0, 4);
        _assertScan(caller_, 0, 5, _two(_ALICE, _CAROL), 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-N03.
    function test_givenCanonicalList_whenMaximumPopulationCountScanned(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        _prepareReward(40e9, 400e6, 77, false, 17);
        _expectCanonicalVisits(0, 4);
        _assertScan(caller_, 0, type(uint256).max, _two(_ALICE, _CAROL), 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-N03.
    function test_givenCanonicalList_whenLargeCountFuzzed(address caller_, uint256 count_) public {
        count_ = bound(count_, 4, type(uint256).max);
        _canonicalScan();
        _assumeOrdinary(caller_);
        _prepareReward(40e9, 400e6, 77, false, 17);
        _expectCanonicalVisits(0, 4);
        _assertScan(caller_, 0, count_, _two(_ALICE, _CAROL), 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-P04.
    function test_givenFiftyOneExpiredBorrowers_whenScanned(address caller_) public {
        address[] memory borrowers = new address[](51);
        for (uint256 i; i < borrowers.length; ++i) {
            borrowers[i] = address(uint160(1000 + i));
            _mockPosition(borrowers[i], 10e6, 1e9, uint48(block.timestamp), 1);
        }
        _mockBorrowers(borrowers);
        _mockRisk(2e18);
        _assumeOrdinary(caller_);
        _prepareReward(51e9, 510e6, 77, false, 17);
        _assertScan(caller_, 0, 51, borrowers, 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-P05.
    function test_givenOneHealthyBorrower_whenScanned(address caller_) public {
        _mockBorrowers(_one(_BOB));
        _mockPosition(_BOB, 100e6, 1e9, uint48(block.timestamp + 1), 1);
        _mockRisk(2e18);
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.keeperReward.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_depositManager),
            abi.encodeWithSignature("previewWithdraw(address,uint256,bool)"),
            uint64(0)
        );
        _assertScan(caller_, 0, 1, new address[](0), 0, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-P07.
    function test_givenStaleZeroDebtCandidate_whenScanned(address caller_) public {
        _canonicalScan();
        _mockPosition(_CAROL, 300e6, 0, uint48(block.timestamp + 1), 1);
        _assumeOrdinary(caller_);
        _prepareReward(10e9, 100e6, 77, false, 17);
        _assertScan(caller_, 0, 4, _one(_ALICE), 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-P01.
    function test_givenOrdinary_whenRewardQuoted(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        _prepareReward(40e9, 400e6, 77, false, 17);
        _assertScan(caller_, 0, 4, _two(_ALICE, _CAROL), 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-P13.
    function test_givenUnderlying_whenRewardQuoted(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        IDepositManager.AssetConfiguration memory cfg = _depositManager.getAssetConfiguration(
            IERC20(address(_asset))
        );
        cfg.vault = address(_ohm);
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("getAssetConfiguration(address)", address(_asset)),
            abi.encode(cfg)
        );
        _prepareReward(40e9, 400e6, 41, false, 13);
        _assertScan(caller_, 0, 4, _two(_ALICE, _CAROL), 0, 13);
    }

    // Scenarios: BLLENS-SEIZABLE-P14.
    function test_givenShares_whenRewardQuoted(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        IDepositManager.AssetConfiguration memory cfg = _depositManager.getAssetConfiguration(
            IERC20(address(_asset))
        );
        cfg.vault = address(_ohm);
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("getAssetConfiguration(address)", address(_asset)),
            abi.encode(cfg)
        );
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("previewWithdraw(address,uint256,bool)", address(_asset)),
            abi.encode(IERC20(address(_ohm)), uint256(7))
        );
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature(
                "validateAssetWithdrawAsShares(address,bool)",
                address(_asset),
                true
            ),
            bytes("")
        );
        _config.setAssetWithdrawAsShares(address(_asset), true);
        vm.expectCall(
            address(_depositManager),
            abi.encodeWithSignature(
                "previewWithdraw(address,uint256,bool)",
                address(_asset),
                uint256(400e6),
                true
            ),
            uint64(2)
        );
        _prepareReward(40e9, 400e6, 7, false, 2);
        _assertScan(caller_, 0, 4, _two(_ALICE, _CAROL), 0, 2);
    }

    // Scenarios: BLLENS-SEIZABLE-P15.
    function test_givenOneUnitReward_whenRewardQuoted(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        _prepareReward(40e9, 400e6, 77, false, 1);
        _assertScan(caller_, 0, 4, _two(_ALICE, _CAROL), 0, 1);
    }

    // Scenarios: BLLENS-SEIZABLE-P16.
    function test_givenZeroReward_whenRewardQuoted(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        _prepareReward(40e9, 400e6, 77, false, 0);
        _assertScan(caller_, 0, 4, _two(_ALICE, _CAROL), 0, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-P06.
    function test_givenOneExpiredBorrower_whenRewardIsZero(address caller_) public {
        _mockBorrowers(_one(_ALICE));
        _mockPosition(_ALICE, 100e6, 10e9, uint48(block.timestamp), 1);
        _mockRisk(2e18);
        _assumeOrdinary(caller_);
        _prepareReward(10e9, 100e6, 77, false, 0);
        _assertScan(caller_, 0, 1, _one(_ALICE), 0, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-P10.
    function test_givenHeart_whenRewardQuoted(address caller_) public {
        _canonicalScan();
        _rolesAdmin.grantRole(HEART_ROLE, caller_);
        _mockWithdrawal(400e6, 77);
        vm.expectCall(
            address(_risk),
            abi.encodeCall(
                IBurnerLoansRisk.keeperReward,
                (
                    _snapshot(),
                    _core.marketId(address(_asset)),
                    uint256(40e9),
                    uint256(400e6),
                    uint256(77),
                    true
                )
            ),
            uint64(2)
        );
        _assertScan(caller_, 0, 4, _two(_ALICE, _CAROL), 0, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-P11.
    function test_givenSeizer_whenRewardQuoted(address caller_) public {
        _canonicalScan();
        _rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, caller_);
        _mockWithdrawal(400e6, 77);
        vm.expectCall(
            address(_risk),
            abi.encodeCall(
                IBurnerLoansRisk.keeperReward,
                (
                    _snapshot(),
                    _core.marketId(address(_asset)),
                    uint256(40e9),
                    uint256(400e6),
                    uint256(77),
                    true
                )
            ),
            uint64(2)
        );
        _assertScan(caller_, 0, 4, _two(_ALICE, _CAROL), 0, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-P12.
    function test_givenBothRoles_whenRewardQuoted(address caller_) public {
        _canonicalScan();
        _rolesAdmin.grantRole(HEART_ROLE, caller_);
        _rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, caller_);
        _mockWithdrawal(400e6, 77);
        vm.expectCall(
            address(_risk),
            abi.encodeCall(
                IBurnerLoansRisk.keeperReward,
                (
                    _snapshot(),
                    _core.marketId(address(_asset)),
                    uint256(40e9),
                    uint256(400e6),
                    uint256(77),
                    true
                )
            ),
            uint64(2)
        );
        _assertScan(caller_, 0, 4, _two(_ALICE, _CAROL), 0, 0);
    }

    // Scenarios: BLLENS-SEIZABLE-A02.
    function test_givenTestContractHasHeartRole_whenOrdinaryActorQuoted(address caller_) public {
        _canonicalScan();
        vm.assume(caller_ != address(this));
        _rolesAdmin.grantRole(HEART_ROLE, address(this));
        _assumeOrdinary(caller_);
        _prepareReward(40e9, 400e6, 77, false, 17);
        _assertScan(caller_, 0, 4, _two(_ALICE, _CAROL), 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-A03.
    function test_whenZeroActorQuoted() public {
        _canonicalScan();
        _prepareReward(40e9, 400e6, 77, false, 17);
        _assertScan(address(0), 0, 4, _two(_ALICE, _CAROL), 0, 17);
    }

    // Scenarios: BLLENS-SEIZABLE-P02.
    function test_givenSnapshotFailure_whenScanned_reverts(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.snapshot, (address(_asset))),
            abi.encodeWithSelector(SnapshotReadFailed.selector)
        );
        _assertScanRevert(
            caller_,
            address(_asset),
            0,
            4,
            abi.encodeWithSelector(SnapshotReadFailed.selector)
        );
    }

    // Scenarios: BLLENS-SEIZABLE-T01.
    function test_givenWithdrawalFailure_whenScanned_reverts(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        vm.mockCallRevert(
            address(_depositManager),
            abi.encodeWithSignature(
                "previewWithdraw(address,uint256,bool)",
                address(_asset),
                uint256(400e6),
                false
            ),
            abi.encodeWithSelector(WithdrawalPreviewFailed.selector)
        );
        _assertScanRevert(
            caller_,
            address(_asset),
            0,
            4,
            abi.encodeWithSelector(WithdrawalPreviewFailed.selector)
        );
    }

    // Scenarios: BLLENS-SEIZABLE-T02.
    function test_givenRewardFailure_whenScanned_reverts(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.keeperReward.selector),
            abi.encodeWithSelector(RewardQuoteFailed.selector)
        );
        _assertScanRevert(
            caller_,
            address(_asset),
            0,
            4,
            abi.encodeWithSelector(RewardQuoteFailed.selector)
        );
    }

    // Scenarios: BLLENS-SEIZABLE-T03.
    function test_givenHealthFailure_whenScanned_reverts(address caller_) public {
        _canonicalScan();
        _assumeOrdinary(caller_);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(
                IBurnerLoansRisk.health,
                (_snapshot(), _core.marketId(address(_asset)), uint256(200e6), uint256(20e9))
            ),
            abi.encodeWithSelector(RiskHealthFailed.selector)
        );
        _assertScanRevert(
            caller_,
            address(_asset),
            0,
            4,
            abi.encodeWithSelector(RiskHealthFailed.selector)
        );
    }

    // Scenarios: BLLENS-SEIZABLE-P02.
    function test_givenExpiredOnlyList_whenSnapshotFails_reverts(address caller_) public {
        _mockBorrowers(_one(_ALICE));
        _mockPosition(_ALICE, 100e6, 10e9, uint48(block.timestamp), 1);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.snapshot, (address(_asset))),
            abi.encodeWithSelector(SnapshotReadFailed.selector)
        );
        _assertScanRevert(
            caller_,
            address(_asset),
            0,
            1,
            abi.encodeWithSelector(SnapshotReadFailed.selector)
        );
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return,boolean-cst)
