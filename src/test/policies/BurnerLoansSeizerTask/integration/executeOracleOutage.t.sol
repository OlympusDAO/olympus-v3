// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansSeize} from "src/policies/interfaces/burnerloans/IBurnerLoansSeize.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IDiscoveryPrice, IDiscoveryWithdrawal} from "src/test/policies/BurnerLoansSeizerTask/fixtures/IDiscoveryDependencies.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {MockPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockPeriodicTask.sol";
import {MockPeriodicTaskManager} from "src/test/bases/PeriodicTaskManager/MockPeriodicTaskManager.sol";
import {MockBackingOracle} from "src/test/mocks/MockBackingOracle.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {BurnerLoansSeizerTaskProgressTest} from "src/test/policies/BurnerLoansSeizerTask/fixtures/BurnerLoansSeizerTaskProgressTest.sol";

// Raw token units, tiny populations and exact timestamps are regression boundaries.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
contract BurnerLoansSeizerTaskExecuteOracleOutageTest is BurnerLoansSeizerTaskProgressTest {
    enum OracleFault {
        PriceReverts,
        BackingReverts,
        BackingPaused,
        PriceStale,
        CacheReverts
    }
    error OracleUnavailable();
    error OracleObservationInvalid(address feed, int256 answer);
    error CanonicalReadFailed();
    error CustodyFailed();
    error ConfigurationFailed();

    // Scenarios: BLSEIZ-EXECUTE-F607.
    function test_givenUnhealthyDebt_givenEmptyRefreshRevert_whenTaskExecuted() public {
        _seedThreeUnhealthyBorrowers();
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(_risk.refreshSnapshot, (address(_asset))),
            bytes("")
        );
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureFailed(
            address(_asset),
            IBurnerLoansSeize.BurnerLoans_PriceSnapshotUnavailable.selector
        );
        _task.execute();
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            1,
            "Empty pricing revert retains pending offset"
        );
        assertEq(_inventory.activePrincipalOhm(), 3e9, "Pricing failure settles no debt");
    }

    // Scenarios: BLSEIZ-EXECUTE-F606.
    function test_givenUnhealthyDebt_givenEmptySettlementRevert_whenTaskExecuted() public {
        _seedThreeUnhealthyBorrowers();
        vm.mockCallRevert(address(_core), abi.encodePacked(_core.settleSeize.selector), bytes(""));
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureFailed(address(_asset), bytes4(0));
        _task.execute();
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            2,
            "Same empty bytes from settlement advance one offset"
        );
        assertEq(_inventory.activePrincipalOhm(), 3e9, "Settlement failure rolls back all debt");
    }

    function _seedThreeUnhealthyBorrowers() private {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _seedDebt(_CAROL, 10e6, 1e9);
        _price.setPrice(address(_asset), 1e16);
        _task.setUnhealthyAssetCursor(address(_asset), 1);
    }

    // Scenarios: BLSEIZ-EXECUTE-F609.
    function test_givenExpiredPoisonedBook_givenNonzeroCursors_whenVisitsRepeat() public {
        _seedPoisonedBook();
        _mature();
        _assertGoodDebtDrainsAroundPoison();
    }

    // Scenarios: BLSEIZ-EXECUTE-F609.
    function test_givenUnhealthyPoisonedBook_givenNonzeroCursors_whenVisitsRepeat() public {
        _seedPoisonedBook();
        _price.setPrice(address(_asset), 1e16);
        _assertGoodDebtDrainsAroundPoison();
    }

    function _seedPoisonedBook() private {
        for (uint256 i; i < 8; ++i) _seedDebt(address(uint160(0x30000 + i)), 10e6, 1e9);
        (, uint64 poisonedId) = _floan.getPositionIdForMarketAndBorrowerAt(
            _core.marketId(address(_asset)),
            address(0x30003),
            0
        );
        vm.mockCallRevert(
            address(_floan),
            abi.encodeCall(_floan.defaultPosition, (poisonedId)),
            abi.encodeWithSelector(CanonicalReadFailed.selector)
        );
        _task.setScanLimits(3, 2);
        _task.setExpiredAssetCursor(address(_asset), 1);
        _task.setUnhealthyAssetCursor(address(_asset), 5);
    }

    function _assertGoodDebtDrainsAroundPoison() private {
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        uint256 now_ = vm.getBlockTimestamp();
        for (uint256 i; i < 64; ++i) _task.execute();
        assertEq(
            _inventory.activePrincipalOhm(),
            2e9,
            "A rejected tail can keep one good loan in a failing batch"
        );
        // Cursor setters and a one-result limit recover good debt without hidden retries.
        _task.setScanLimits(3, 1);
        _task.setExpiredAssetCursor(address(_asset), 0);
        _task.setUnhealthyAssetCursor(address(_asset), 0);
        for (uint256 i; i < 64 && _inventory.activePrincipalOhm() > 1e9; ++i) _task.execute();
        assertEq(vm.getBlockTimestamp(), now_, "Drain cannot rely on further maturation");
        for (uint256 i; i < 8; ++i) {
            assertEq(
                _lens.getPosition(address(_asset), address(uint160(0x30000 + i))).debtOhm,
                i == 3 ? 1e9 : 0,
                "Every good borrower before and after poisoned debt remains reachable"
            );
        }
        uint32 market = _core.marketId(address(_asset));
        assertEq(_floan.getActiveBorrowerCount(market), 1, "Only poisoned borrower stays active");
        assertEq(_floan.getMarketPrincipalDue(market), 1e9, "Poisoned debt remains due");
        assertEq(_floan.getMarketPrincipalDefaulted(market), 7e9, "Seven good loans default once");
        assertEq(_inventory.activePrincipalOhm(), 1e9, "Inventory retains only poisoned principal");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            10e6,
            "Only poisoned collateral remains in custody"
        );
        // Seven 10e6 collateral positions settle with protocol reward zero.
        assertEq(
            _asset.balanceOf(_payout.treasury()) - treasuryBefore,
            70e6,
            "Exact Treasury proceeds"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-F601.
    function test_givenPersistentExpiredRejection_givenUnhealthyDebt_whenAssetVisitedAgain()
        public
    {
        _mixedDebt();
        _markMixedDebtUnderwater();
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(_core.settleSeize, (address(_asset), _one(_BOB), address(_task))),
            abi.encodeWithSelector(CustodyFailed.selector)
        );
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        _task.execute();
        assertEq(
            _inventory.activePrincipalOhm(),
            3e9,
            "Rejected expiry attempt settles no principal"
        );
        _task.execute();
        _task.execute();
        assertEq(
            _lens.getPosition(address(_asset), _BOB).debtOhm,
            1e9,
            "Rejected expired debt remains pending"
        );
        assertEq(
            _lens.getPosition(address(_asset), _CAROL).debtOhm,
            0,
            "Unhealthy Carol receives a turn despite expired rejection"
        );
        assertEq(
            _lens.getPosition(address(_asset), _DAVE).debtOhm,
            0,
            "Unhealthy Dave receives a turn despite expired rejection"
        );
        assertEq(_inventory.activePrincipalOhm(), 1e9, "Only the unseizable expired debt remains");
        assertEq(
            _floan.getMarketPrincipalDefaulted(_core.marketId(address(_asset))),
            2e9,
            "Only the two unhealthy loans default"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()) - treasuryBefore,
            20e6,
            "Unhealthy settlement delivers actual collateral"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-F602.
    function test_givenExpiredBacklog_givenUnhealthyDebt_whenAssetVisitedAgain() public {
        address thirdExpired = makeAddr("third expired borrower");
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _seedDebt(thirdExpired, 10e6, 1e9);
        _mature();
        _seedDebt(_CAROL, 10e6, 1e9);
        _seedDebt(_DAVE, 10e6, 1e9);
        _markMixedDebtUnderwater();
        _task.setScanLimits(500, 1);
        _task.execute();
        _task.execute();
        _task.execute();
        assertEq(
            _lens.getPosition(address(_asset), _DAVE).debtOhm,
            0,
            "Unhealthy borrower settles before the expired backlog is exhausted"
        );
        assertEq(
            _lens.getPosition(address(_asset), _BOB).debtOhm,
            1e9,
            "Expired backlog is still nonempty"
        );
        assertEq(
            _lens.getPosition(address(_asset), thirdExpired).debtOhm,
            1e9,
            "A second expired borrower is still pending"
        );
        assertEq(_inventory.activePrincipalOhm(), 3e9, "Exactly one batch per visit settles");
    }

    // Scenarios: BLSEIZ-EXECUTE-F602.
    function test_givenExpiredPrefixAndTail_givenSingleCheckPages_whenVisitsRepeat() public {
        address fifthExpired = makeAddr("fifth expired");
        address sixthExpired = makeAddr("sixth expired");
        address unhealthy = makeAddr("unhealthy between expired entries");
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _seedDebt(_CAROL, 10e6, 1e9);
        _seedDebt(_DAVE, 10e6, 1e9);
        _seedDebt(fifthExpired, 10e6, 1e9);
        _seedDebt(sixthExpired, 10e6, 1e9);
        _mature();
        _seedDebt(unhealthy, 10e6, 1e9);
        _repay(_BOB, 1e9); // Swap the future borrower into index1, behind the expired prefix.
        _price.setPrice(address(_asset), 1e16);
        _task.setScanLimits(1, 1);
        for (uint256 i; i < 4; ++i) {
            _task.execute();
            _task.execute();
        }
        assertEq(
            _lens.getPosition(address(_asset), unhealthy).debtOhm,
            0,
            "Expired compaction cannot repeatedly erase unhealthy scan progress"
        );
        assertEq(
            _lens.getPosition(address(_asset), _CAROL).debtOhm,
            1e9,
            "Unhealthy loan settles while the expired backlog remains"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-F605.
    function test_givenExpiredBatchWithUnseizableTail_whenAdminRecoversCursor() public {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _mature();
        address[] memory batch = new address[](2);
        batch[0] = _ALICE;
        batch[1] = _BOB;
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(_core.settleSeize, (address(_asset), batch, address(_task))),
            abi.encodeWithSelector(CustodyFailed.selector)
        );
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(_core.settleSeize, (address(_asset), _one(_BOB), address(_task))),
            abi.encodeWithSelector(CustodyFailed.selector)
        );
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        _task.execute();
        assertEq(_inventory.activePrincipalOhm(), 2e9, "Rejected batch rolls back all principal");
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore,
            "Rejected batch transfers no collateral"
        );
        // Governance isolates the good prefix rather than adding an automatic retry.
        _task.setScanLimits(2, 1);
        _task.setExpiredAssetCursor(address(_asset), 0);
        _task.setNextAssetIndex(0);
        _task.execute();
        assertEq(
            _lens.getPosition(address(_asset), _ALICE).debtOhm,
            0,
            "Unseizable tail cannot roll back the good borrower's operator-selected singleton"
        );
        assertEq(
            _lens.getPosition(address(_asset), _BOB).debtOhm,
            1e9,
            "Rejected borrower's debt remains outstanding"
        );
        assertEq(_inventory.activePrincipalOhm(), 1e9, "Only the successful singleton defaults");
        assertEq(
            _floan.getMarketPrincipalDefaulted(_core.marketId(address(_asset))),
            1e9,
            "Default accounting applies exactly once"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()) - treasuryBefore,
            10e6,
            "Only settled collateral reaches Treasury"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-F606.
    function test_givenExpiredBatchWithUnseizablePrefix_whenAssetVisitedAgain() public {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _mature();
        address[] memory batch = new address[](2);
        batch[0] = _ALICE;
        batch[1] = _BOB;
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(_core.settleSeize, (address(_asset), batch, address(_task))),
            abi.encodeWithSelector(CustodyFailed.selector)
        );
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(_core.settleSeize, (address(_asset), _one(_ALICE), address(_task))),
            abi.encodeWithSelector(CustodyFailed.selector)
        );
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Rejected first position advances one"
        );
        _task.execute();
        _task.execute();
        assertEq(
            _lens.getPosition(address(_asset), _BOB).debtOhm,
            0,
            "Subsequent eligible borrower remains reachable"
        );
        assertEq(
            _lens.getPosition(address(_asset), _ALICE).debtOhm,
            1e9,
            "Unseizable debt is retained for a later lap"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            1e9,
            "Failed prefix does not prevent exact successful settlement"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-F604, BLSEIZ-EXECUTE-F606.
    function test_givenUnhealthyBatchWithUnseizablePrefix_whenAssetVisitedAgain() public {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _price.setPrice(address(_asset), 1e16);
        address[] memory batch = new address[](2);
        batch[0] = _ALICE;
        batch[1] = _BOB;
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(_core.settleSeize, (address(_asset), batch, address(_task))),
            abi.encodeWithSelector(CustodyFailed.selector)
        );
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(_core.settleSeize, (address(_asset), _one(_ALICE), address(_task))),
            abi.encodeWithSelector(CustodyFailed.selector)
        );
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        _task.execute();
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            1,
            "Rejected unhealthy singleton advances one offset"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            2e9,
            "Rejected batch and singleton settle no debt"
        );
        _task.execute();
        _task.execute();
        assertEq(
            _lens.getPosition(address(_asset), _BOB).debtOhm,
            0,
            "Unhealthy borrower behind the rejected position remains reachable"
        );
        assertEq(
            _lens.getPosition(address(_asset), _ALICE).debtOhm,
            1e9,
            "Failed unhealthy debt remains pending"
        );
        assertEq(_inventory.activePrincipalOhm(), 1e9, "Only one unhealthy position settles");
        assertEq(
            _asset.balanceOf(_payout.treasury()) - treasuryBefore,
            10e6,
            "Successful unhealthy position delivers its collateral"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-F605.
    function test_givenUnhealthyBatchWithUnseizableTail_whenAdminRecoversCursor() public {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _price.setPrice(address(_asset), 1e16);
        address[] memory batch = new address[](2);
        batch[0] = _ALICE;
        batch[1] = _BOB;
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(_core.settleSeize, (address(_asset), batch, address(_task))),
            abi.encodeWithSelector(CustodyFailed.selector)
        );
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(_core.settleSeize, (address(_asset), _one(_BOB), address(_task))),
            abi.encodeWithSelector(CustodyFailed.selector)
        );
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        _task.execute();
        assertEq(_inventory.activePrincipalOhm(), 2e9, "Rejected batch rolls back all principal");
        assertEq(
            _asset.balanceOf(_payout.treasury()),
            treasuryBefore,
            "Rejected batch transfers no collateral"
        );
        // Governance isolates the good prefix rather than adding an automatic retry.
        _task.setScanLimits(2, 1);
        _task.setUnhealthyAssetCursor(address(_asset), 0);
        _task.setNextAssetIndex(0);
        _task.execute();
        assertEq(
            _lens.getPosition(address(_asset), _ALICE).debtOhm,
            0,
            "Good unhealthy prefix settles through singleton operator-selected singleton"
        );
        assertEq(
            _lens.getPosition(address(_asset), _BOB).debtOhm,
            1e9,
            "Failed atomic batch does not settle its tail"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            1e9,
            "Operator-selected singleton defaults one unhealthy loan exactly once"
        );
        assertEq(
            _floan.getMarketPrincipalDefaulted(_core.marketId(address(_asset))),
            1e9,
            "Default ledger matches the operator-selected singleton loan"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()) - treasuryBefore,
            10e6,
            "Operator-selected singleton pays only one loan's collateral"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-F607.
    function test_givenUnhealthyDebt_givenRefreshRevertsWithArguments_whenSeized_reverts() public {
        _seedDebt(_ALICE, 10e6, 1e9);
        _price.setPrice(address(_asset), 1e16);
        bytes memory reason = abi.encodeWithSelector(
            OracleObservationInvalid.selector,
            address(_price),
            int256(-1)
        );
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(_risk.refreshSnapshot, (address(_asset))),
            reason
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeize.BurnerLoans_PriceSnapshotUnavailable.selector,
                reason
            )
        );
        vm.prank(address(_task));
        _liquidation.seize(address(_asset), _one(_ALICE));
    }

    // Scenarios: BLSEIZ-EXECUTE-F607.
    function test_givenUnhealthyDebt_givenRefreshOnlyOutage_whenSeized_reverts() public {
        _seedDebt(_ALICE, 10e6, 1e9);
        _price.setPrice(address(_asset), 1e16);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(_risk.refreshSnapshot, (address(_asset))),
            abi.encodeWithSelector(OracleUnavailable.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeize.BurnerLoans_PriceSnapshotUnavailable.selector,
                abi.encodeWithSelector(OracleUnavailable.selector)
            )
        );
        vm.prank(address(_task));
        _liquidation.seize(address(_asset), _one(_ALICE));
    }

    // Scenarios: BLSEIZ-EXECUTE-F607.
    function test_givenUnhealthyDebt_givenRefreshOnlyOutage_whenTaskExecuted() public {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _price.setPrice(address(_asset), 1e16);
        _task.setUnhealthyAssetCursor(address(_asset), 1);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(_risk.refreshSnapshot, (address(_asset))),
            abi.encodeWithSelector(OracleUnavailable.selector)
        );
        _task.execute();
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            1,
            "View pricing succeeded but execution pricing failure cannot skip Bob"
        );
        assertEq(_inventory.activePrincipalOhm(), 2e9, "Refresh failure settles no debt");
        vm.clearMockedCalls();
        _task.execute();
        _task.execute();
        assertEq(
            _lens.getPosition(address(_asset), _BOB).debtOhm,
            0,
            "Recovery revisits the preserved unhealthy position"
        );
    }

    function setUp() public override {
        super.setUp();
        _task.addAsset(address(_asset));
        _task.addAsset(address(_otherAsset));
    }

    // Scenarios: BLSEIZ-EXECUTE-D01, BLSEIZ-EXECUTE-P13.
    function test_givenMixedMaturity_givenOutage_whenHeartBeatsRepeat(uint8 fault_) public {
        _mixedDebt();
        bytes memory reason = _outage(
            OracleFault(bound(fault_, 0, uint256(OracleFault.CacheReverts)))
        );
        _task.setScanLimits(1, 1);
        _expectScanFailure(reason);
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Unexpired prefix consumes a bounded check during outage"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        _task.execute(); // Other asset keeps its turn.
        assertEq(_task.nextAssetIndex(), 0, "Asset rotation wraps before the second A visit");
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Successful deletion rewinds the first unexamined index"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        _assertSettledExpired();
        _task.execute();
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            0,
            "All-unexpired suffix wraps on the next visit"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-D01.
    function test_givenMixedMaturity_givenOutage_whenSinglePageScanned(uint8 fault_) public {
        _mixedDebt();
        _outage(OracleFault(bound(fault_, 0, uint256(OracleFault.CacheReverts))));
        _expectNoPricedScan();
        _task.execute();
        _assertSettledExpired();
        assertEq(_task.expiredAssetCursor(address(_asset)), 0, "Mixed suffix reaches wraparound");
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-D02.
    function test_givenAllExpired_givenOutage_whenExecuted(uint8 fault_) public {
        _seedDebt(_ALICE, 10e6, 1e9);
        vm.warp(_position(_ALICE).maturity); // Equality is eligible.
        _price.setTimestamp(uint48(block.timestamp));
        _outage(OracleFault(bound(fault_, 0, uint256(OracleFault.CacheReverts))));
        _expectNoPricedScan();
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        _task.execute();
        assertEq(_inventory.activePrincipalOhm(), 0, "Expired principal settled without prices");
        assertEq(
            _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
            0,
            "Canonical membership removed"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()) - treasuryBefore,
            10e6,
            "All actual collateral delivered to Treasury"
        );
        assertEq(_asset.balanceOf(address(_task)), 0, "Protocol task receives zero reward");
    }

    // Scenarios: BLSEIZ-EXECUTE-D10.
    function test_givenAllUnexpired_givenOutage_whenExecuted(uint8 fault_) public {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _price.setTimestamp(uint48(block.timestamp));
        bytes memory reason = _outage(
            OracleFault(bound(fault_, 0, uint256(OracleFault.CacheReverts)))
        );
        _task.setScanLimits(1, 1);
        _expectScanFailure(reason);
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Empty expiry selection advances through unexpired debt"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        _task.execute();
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            0,
            "All-unexpired page wraps after bounded visits"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            2e9,
            "No debt classified or settled without prices"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-P13.
    function test_givenExpiredPopulation_givenOutage_whenBatchesCompact() public {
        for (uint256 i; i < 5; ++i) _seedDebt(address(uint160(0x1000 + i)), 10e6, 1e9);
        _mature();
        _outage(OracleFault.PriceReverts);
        _task.setScanLimits(3, 1);
        for (uint256 i; i < 5; ++i) {
            _task.execute();
            assertEq(
                _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
                4 - i,
                "One canonical member removed per A visit"
            );
            assertEq(
                _inventory.activePrincipalOhm(),
                (4 - i) * 1e9,
                "FLOAN and Inventory principal agree after each batch"
            );
            _task.execute();
        }
        assertEq(
            _floan.getMarketCollateral(_core.marketId(address(_asset))),
            0,
            "All collateral records settled after swap-and-pop"
        );
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            0,
            "Empty population cursor remains zero"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-P13, BLSEIZ-SELF-EXECUTE-P05.
    function test_givenStaleCursor_givenOutage_whenExecuted() public {
        _mixedDebt();
        _setBothBorrowerCursors(address(_asset), 2);
        _repay(_CAROL, 1e9);
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            2,
            "Saved cursor is stale before recovery"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            2,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(
            _lens.getActiveBorrowerCount(address(_asset)),
            2,
            "Stale cursor equals live count"
        );
        _outage(OracleFault.PriceReverts);
        _task.execute();
        assertEq(
            _lens.getPosition(address(_asset), _BOB).debtOhm,
            0,
            "Stale start repaired and expired debt settled in the same visit"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            1e9,
            "Only unexpired Dave remains after repayment and default"
        );
        assertEq(_task.expiredAssetCursor(address(_asset)), 0, "Repaired cursor remains canonical");
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-D09, BLSEIZ-SELF-EXECUTE-D06.
    function test_givenStaleCursor_givenServiceFailure_whenExecuted(bool settlement_) public {
        _mixedDebt();
        _setBothBorrowerCursors(address(_asset), 2);
        _repay(_CAROL, 1e9);
        _expectPricedScans(1);
        if (settlement_) {
            _liquidation.disable("");
            vm.expectEmit(true, false, false, true, address(_task));
            emit IBurnerLoansSeizerTask.SeizureFailed(
                address(_asset),
                IEnabler.NotEnabled.selector
            );
        } else {
            _risk.disable("");
            _expectScanFailure(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        }
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            settlement_ ? 1 : 0,
            "Repair survives scan failure; rejected singleton advances one"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            2e9,
            "Failed service preserves remaining principal"
        );
        assertEq(_task.nextAssetIndex(), 1, "Service failure still rotates the asset");
        if (settlement_) _liquidation.reEnable();
        else _risk.reEnable();
        _task.execute(); // B keeps its turn.
        _task.execute();
        assertEq(
            _lens.getPosition(address(_asset), _BOB).debtOhm,
            0,
            "Restored service settles expired debt from repaired zero cursor"
        );
        assertEq(_inventory.activePrincipalOhm(), 1e9, "Only unexpired debt remains after retry");
    }

    // Scenarios: BLSEIZ-EXECUTE-P16.
    function test_givenExpiryEmptySuffix_givenOutage_whenHeartBeatsRepeat() public {
        _mixedDebt();
        _task.setScanLimits(1, 1);
        _setBothBorrowerCursors(address(_asset), 2);
        _outage(OracleFault.PriceReverts);
        _expectScanFailure(abi.encodeWithSelector(OracleUnavailable.selector));
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            0,
            "Canonical end wraps despite empty filtered results"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            2,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            3e9,
            "An expiry-empty suffix makes no health classification"
        );
        _task.execute();
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Canonical first entry advances to expired suffix borrower"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            2,
            "Expected independent unhealthy scan or retry offset"
        );
        _task.execute();
        _task.execute();
        _assertSettledExpired();
    }

    // Scenarios: BLSEIZ-EXECUTE-D03.
    function test_givenExpiryCanonicalFailure_whenExecuted() public {
        _mixedDebt();
        _setBothBorrowerCursors(address(_asset), 1);
        _outage(OracleFault.PriceReverts);
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.getPosition.selector),
            abi.encodeWithSelector(CanonicalReadFailed.selector)
        );
        _expectNoPricedScan();
        _expectScanFailure(abi.encodeWithSelector(CanonicalReadFailed.selector));
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Failed expiry scan preserves nonzero cursor"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            1,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(_task.nextAssetIndex(), 1, "Expiry read error remains isolated to this asset");
        assertEq(
            _inventory.activePrincipalOhm(),
            3e9,
            "No partial default on canonical read error"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-D04.
    function test_givenCustodyFailure_givenOutage_whenExecuted() public {
        _mixedDebt();
        _setBothBorrowerCursors(address(_asset), 1);
        _outage(OracleFault.PriceReverts);
        uint256 custodyBefore = _asset.balanceOf(address(_depositManager));
        uint256 liabilitiesBefore = _depositManager.getOperatorLiabilities(
            IERC20(address(_asset)),
            address(_core)
        );
        vm.mockCallRevert(
            address(_depositManager),
            abi.encodeWithSelector(IDiscoveryWithdrawal.withdraw.selector),
            abi.encodeWithSelector(CustodyFailed.selector)
        );
        _expectPricedScans(1);
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureFailed(address(_asset), CustodyFailed.selector);
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            2,
            "Failed redemption advances one saved offset"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            1,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(_inventory.activePrincipalOhm(), 3e9, "Redemption failure rolls back defaults");
        assertEq(
            _lens.getPosition(address(_asset), _BOB).debtOhm,
            1e9,
            "Expired debt retained for retry"
        );
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            custodyBefore,
            "Failed redemption preserves actual custody"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            liabilitiesBefore,
            "Failed redemption preserves operator liabilities"
        );
        vm.clearMockedCalls();
        _outage(OracleFault.PriceReverts);
        _task.execute();
        _task.execute();
        _task.execute();
        _task.execute();
        _assertSettledExpired();
    }

    // Scenarios: BLSEIZ-EXECUTE-D11, BLSEIZ-EXECUTE-D12.
    function test_givenRiskUnavailable_whenExecuted(bool active_) public {
        _mixedDebt();
        if (active_) _risk.disable("");
        else _kernel.executeAction(Actions.DeactivatePolicy, address(_risk));
        bytes memory reason = active_
            ? abi.encodeWithSelector(IEnabler.NotEnabled.selector)
            : abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_risk)
            );
        _expectScanFailure(reason);
        _expectPricedScans(1);
        // Only the successful retry below may reach Seize; failed quotes must not call it.
        vm.expectCall(
            address(_liquidation),
            abi.encodeWithSelector(_liquidation.seize.selector),
            uint64(1)
        );
        _task.execute();
        assertEq(
            _inventory.activePrincipalOhm(),
            3e9,
            "Risk lifecycle failure cannot bypass settlement admission"
        );
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            0,
            "Rejected settlement retains cursor"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        if (active_) _risk.reEnable();
        else _kernel.executeAction(Actions.ActivatePolicy, address(_risk));
        _task.execute();
        _task.execute();
        _assertSettledExpired();
    }

    // Scenarios: BLSEIZ-EXECUTE-D13.
    function test_givenSeizePaused_givenOutage_whenExecuted() public {
        _mixedDebt();
        _outage(OracleFault.PriceReverts);
        _liquidation.disable("");
        _expectPricedScans(1);
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureFailed(address(_asset), IEnabler.NotEnabled.selector);
        _task.execute();
        assertEq(_inventory.activePrincipalOhm(), 3e9, "Paused Seize retains all debt");
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Rejected singleton advances without settling debt"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        _liquidation.reEnable();
        _task.execute();
        _task.execute();
        _assertSettledExpired();
    }

    // Scenarios: BLSEIZ-EXECUTE-D14.
    function test_givenCoreUnavailable_givenOutage_whenExecuted(bool active_) public {
        _mixedDebt();
        _outage(OracleFault.PriceReverts);
        if (active_) _core.disable("");
        else _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        _expectPricedScans(1);
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureFailed(
            address(_asset),
            PolicyDependency.PolicyDependency_NotActive.selector
        );
        _task.execute();
        assertEq(
            _inventory.activePrincipalOhm(),
            3e9,
            "Core admission failure preserves debt despite expiry discovery"
        );
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Non-price admission failure advances one offset"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        if (active_) _core.reEnable();
        else _kernel.executeAction(Actions.ActivatePolicy, address(_core));
        _task.execute();
        _task.execute();
        _assertSettledExpired();
    }

    // Scenarios: BLSEIZ-EXECUTE-D05.
    function test_givenHealthConfigurationFailure_whenExecuted() public {
        _mixedDebt();
        _task.setScanLimits(1, 1);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encodeWithSelector(ConfigurationFailed.selector)
        );
        _expectScanFailure(abi.encodeWithSelector(ConfigurationFailed.selector));
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Failed priced prefix advances by the empty expiry scan"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        _task.execute(); // B keeps its turn.
        _task.execute(); // The expired suffix needs no health read.
        _assertSettledExpired();
    }

    // Scenarios: BLSEIZ-EXECUTE-D06.
    function test_givenWithdrawalQuoteFailure_whenExecuted() public {
        _mixedDebt();
        // Expiry discovery itself requires a valid aggregate custody/reward quote.
        vm.mockCallRevert(
            address(_depositManager),
            abi.encodeWithSelector(IDepositManagerV1_1.previewWithdraw.selector),
            abi.encodeWithSelector(CustodyFailed.selector)
        );
        _expectScanFailure(abi.encodeWithSelector(CustodyFailed.selector));
        _expectPricedScans(1);
        // Only the successful retry below may reach Seize; failed quotes must not call it.
        vm.expectCall(
            address(_liquidation),
            abi.encodeWithSelector(_liquidation.seize.selector),
            uint64(1)
        );
        _task.execute();
        assertEq(
            _inventory.activePrincipalOhm(),
            3e9,
            "An unavailable expiry quote preserves debt"
        );
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            0,
            "An unavailable expiry quote preserves cursor"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        vm.clearMockedCalls();
        _task.execute();
        _task.execute();
        _assertSettledExpired();
    }

    // Scenarios: BLSEIZ-EXECUTE-P14.
    function test_givenPricesAvailable_whenMixedUnhealthyPageScanned() public {
        _mixedDebt();
        _price.setPrice(address(_asset), 1e16);
        vm.expectCall(
            address(_lens),
            abi.encodeWithSelector(
                IBurnerLoansLens.getUnhealthyBorrowersBoundedFor.selector,
                address(_task),
                address(_asset)
            ),
            uint64(1)
        );
        _task.execute();
        _assertSettledExpired();
        _task.execute(); // B keeps its turn.
        _task.execute(); // An expiry-empty page now permits priced unhealthy discovery.
        assertEq(
            _inventory.activePrincipalOhm(),
            0,
            "Priced discovery retains unexpired unhealthy liquidation"
        );
        assertEq(
            _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
            0,
            "Later priced scan settles the remaining unhealthy borrowers"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-P15.
    function test_givenExpiredDebt_givenPriceConsumesGas_whenHeartRunsTasks() public {
        _mixedDebt();
        (MockPeriodicTaskManager manager, MockPeriodicTask later) = _managerWithLaterTask();
        // INVALID consumes all gas forwarded to PRICE; expiry selection and settlement must avoid it.
        vm.etch(address(_price), hex"fe");
        _expectNoPricedScan();
        vm.expectCall(
            address(_price),
            abi.encodeWithSelector(IDiscoveryPrice.getPrice.selector),
            uint64(0)
        );
        manager.executeAllTasks{gas: 5_000_000}();
        _assertSettledExpired();
        assertEq(
            later.count(),
            1,
            "Price service cannot block expired settlement or later Heart work"
        );
        assertEq(_task.nextAssetIndex(), 1, "Expired settlement rotates the asset");
    }

    // Scenarios: BLSEIZ-EXECUTE-D08.
    function test_givenUnexpiredPrefix_givenPriceConsumesGas_whenHeartRunsTasks() public {
        _mixedDebt();
        _task.setScanLimits(1, 1);
        _task.setExecutionGasLimit(200_000);
        (MockPeriodicTaskManager manager, MockPeriodicTask later) = _managerWithLaterTask();
        vm.etch(address(_price), hex"fe");
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ScanFailed(address(_asset), bytes4(0));
        manager.executeAllTasks{gas: 1_000_000}();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Caught price exhaustion preserves completed expiry progress"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Gas-consuming prices retain pending unhealthy work"
        );
        assertEq(_inventory.activePrincipalOhm(), 3e9, "Gas exhaustion leaves all debt unchanged");
        assertEq(_task.nextAssetIndex(), 1, "Outer reserve still rotates the asset");
        assertEq(later.count(), 1, "Optional priced work cannot prevent later Heart tasks");
    }

    // Scenarios: BLLENS-EXPIRED-D02.
    function test_givenZeroRewardConfig_givenOutage_whenOrdinaryExpiredQuoteRequested(
        bool zeroBps_
    ) public {
        _mixedDebt();
        _outage(OracleFault.PriceReverts);
        vm.expectRevert(OracleUnavailable.selector);
        _lens.getExpiredBorrowersBoundedFor(_BOB, address(_asset), 0, 3, 3);
        _config.setAssetRiskConfig(
            address(_asset),
            IBurnerLoansRisk.AssetRiskConfigInput(
                8500,
                12500,
                zeroBps_ ? 0 : 100,
                30 days,
                90 days,
                zeroBps_ ? 1000e6 : 0
            )
        );
        assertEq(
            _risk.keeperReward(_core.marketId(address(_asset)), 1e9, 10e6, 10e6, false),
            0,
            "Zero reward configuration needs no reward prices"
        );
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getExpiredBorrowersBoundedFor(_BOB, address(_asset), 0, 3, 3);
        assertEq(borrowers, _one(_BOB), "Ordinary quote selects only expired debt");
        assertEq(cursor, 0, "Ordinary expiry selection reaches canonical end");
        assertEq(reward, 0, "Lens preserves Risk's valid zero quote during outage");
        vm.expectRevert(OracleUnavailable.selector);
        _liquidation.previewSeizeFor(_BOB, address(_asset), borrowers);
        (borrowers, , reward) = _lens.getExpiredBorrowersBoundedFor(
            address(_task),
            address(_asset),
            0,
            3,
            3
        );
        assertEq(borrowers, _one(_BOB), "Protocol actor retains expiry discovery during outage");
        assertEq(reward, 0, "Protocol expiry quote needs no prices");
    }

    // Scenarios: BLLENS-EXPIRED-A03.
    function test_givenPricesAvailable_whenOrdinaryExpiredQuoteSettled() public {
        _seedDebt(_ALICE, 100e6, 1e9);
        _mature();
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getExpiredBorrowersBoundedFor(
                _BOB,
                address(_asset),
                0,
                type(uint256).max,
                type(uint256).max
            );
        IBurnerLoansCore.SeizePreview memory quote = _liquidation.previewSeizeFor(
            _BOB,
            address(_asset),
            borrowers
        );
        assertEq(borrowers, _one(_ALICE), "Real quote selects expired borrower");
        assertEq(cursor, 0, "Real quote reaches canonical end");
        assertGt(reward, 0, "Ordinary expired keeper receives a priced reward");
        assertEq(reward, quote.keeperReward, "Lens and Seize quote the same aggregate reward");
        uint256 keeperBefore = _asset.balanceOf(_BOB);
        vm.prank(_BOB);
        _liquidation.seize(address(_asset), borrowers);
        assertEq(
            _asset.balanceOf(_BOB) - keeperBefore,
            reward,
            "Actor receives the quoted output tokens"
        );
        assertEq(_inventory.activePrincipalOhm(), 0, "Quoted expiry batch fully settles principal");
    }

    // Scenarios: BLSEIZ-EXECUTE-D01.
    function test_givenMixedMaturity_givenPriceReverts_whenExecuted() public {
        test_givenMixedMaturity_givenOutage_whenSinglePageScanned(uint8(OracleFault.PriceReverts));
    }

    // Scenarios: BLSEIZ-EXECUTE-D01.
    function test_givenMixedMaturity_givenBackingReverts_whenExecuted() public {
        test_givenMixedMaturity_givenOutage_whenSinglePageScanned(
            uint8(OracleFault.BackingReverts)
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-D01.
    function test_givenMixedMaturity_givenBackingPaused_whenExecuted() public {
        test_givenMixedMaturity_givenOutage_whenSinglePageScanned(uint8(OracleFault.BackingPaused));
    }

    // Scenarios: BLSEIZ-EXECUTE-D01.
    function test_givenMixedMaturity_givenPriceStale_whenExecuted() public {
        test_givenMixedMaturity_givenOutage_whenSinglePageScanned(uint8(OracleFault.PriceStale));
    }

    // Scenarios: BLSEIZ-EXECUTE-D01.
    function test_givenMixedMaturity_givenCacheReverts_whenExecuted() public {
        test_givenMixedMaturity_givenOutage_whenSinglePageScanned(uint8(OracleFault.CacheReverts));
    }

    // Scenarios: BLSEIZ-EXECUTE-D02.
    function test_givenAllExpired_givenPriceReverts_whenExecuted() public {
        test_givenAllExpired_givenOutage_whenExecuted(uint8(OracleFault.PriceReverts));
    }

    // Scenarios: BLSEIZ-EXECUTE-D02.
    function test_givenAllExpired_givenBackingReverts_whenExecuted() public {
        test_givenAllExpired_givenOutage_whenExecuted(uint8(OracleFault.BackingReverts));
    }

    // Scenarios: BLSEIZ-EXECUTE-D02.
    function test_givenAllExpired_givenBackingPaused_whenExecuted() public {
        test_givenAllExpired_givenOutage_whenExecuted(uint8(OracleFault.BackingPaused));
    }

    // Scenarios: BLSEIZ-EXECUTE-D02.
    function test_givenAllExpired_givenPriceStale_whenExecuted() public {
        test_givenAllExpired_givenOutage_whenExecuted(uint8(OracleFault.PriceStale));
    }

    // Scenarios: BLSEIZ-EXECUTE-D02.
    function test_givenAllExpired_givenCacheReverts_whenExecuted() public {
        test_givenAllExpired_givenOutage_whenExecuted(uint8(OracleFault.CacheReverts));
    }

    // Scenarios: BLSEIZ-EXECUTE-D10.
    function test_givenAllUnexpired_givenPriceReverts_whenExecuted() public {
        test_givenAllUnexpired_givenOutage_whenExecuted(uint8(OracleFault.PriceReverts));
    }

    // Scenarios: BLSEIZ-EXECUTE-D10.
    function test_givenAllUnexpired_givenBackingReverts_whenExecuted() public {
        test_givenAllUnexpired_givenOutage_whenExecuted(uint8(OracleFault.BackingReverts));
    }

    // Scenarios: BLSEIZ-EXECUTE-D10.
    function test_givenAllUnexpired_givenBackingPaused_whenExecuted() public {
        test_givenAllUnexpired_givenOutage_whenExecuted(uint8(OracleFault.BackingPaused));
    }

    // Scenarios: BLSEIZ-EXECUTE-D10.
    function test_givenAllUnexpired_givenPriceStale_whenExecuted() public {
        test_givenAllUnexpired_givenOutage_whenExecuted(uint8(OracleFault.PriceStale));
    }

    // Scenarios: BLSEIZ-EXECUTE-D10.
    function test_givenAllUnexpired_givenCacheReverts_whenExecuted() public {
        test_givenAllUnexpired_givenOutage_whenExecuted(uint8(OracleFault.CacheReverts));
    }

    // Scenarios: BLSEIZ-EXECUTE-D15.
    function test_givenSeizeInactive_givenOutage_whenExecuted(bool enabled_) public {
        _mixedDebt();
        _outage(OracleFault.PriceReverts);
        if (!enabled_) _liquidation.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_liquidation));
        _expectPricedScans(1);
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureFailed(
            address(_asset),
            IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector
        );
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Inactive Seize rejection advances one saved offset"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(_inventory.activePrincipalOhm(), 3e9, "Inactive Seize preserves principal");
        assertEq(_task.nextAssetIndex(), 1, "Inactive Seize still rotates assets");
        _kernel.executeAction(Actions.ActivatePolicy, address(_liquidation));
        if (!enabled_) _liquidation.reEnable();
        _task.execute();
        _task.execute();
        _assertSettledExpired();
    }

    // Scenarios: BLSEIZ-EXECUTE-D16.
    function test_givenExpiryEmptyPage_givenRiskPaused_whenExecuted() public {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _task.setScanLimits(1, 1);
        _risk.disable("");
        _expectScanFailure(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        _expectNoSettlement();
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Priced pause advances proven-empty expiry page"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(_inventory.activePrincipalOhm(), 2e9, "No classification while Risk is paused");
    }

    // Scenarios: BLSEIZ-EXECUTE-D17.
    function test_givenExpiryEmptyPage_givenRiskInactive_whenExecuted(bool enabled_) public {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _task.setScanLimits(1, 1);
        if (!enabled_) _risk.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_risk));
        _expectScanFailure(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_risk)
            )
        );
        _expectNoSettlement();
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Inactive Risk advances proven-empty expiry page"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            2e9,
            "Inactive Risk cannot classify or settle debt"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-D18.
    function test_givenUnexpiredUnhealthyDebt_givenPricedCustodyQuoteFails_whenExecuted() public {
        _unexpiredUnhealthyDebt();
        vm.mockCallRevert(
            address(_depositManager),
            abi.encodeWithSelector(IDepositManagerV1_1.previewWithdraw.selector),
            abi.encodeWithSelector(CustodyFailed.selector)
        );
        _expectScanFailure(abi.encodeWithSelector(CustodyFailed.selector));
        _expectNoSettlement();
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Priced custody failure advances expiry-empty page"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            2e9,
            "Priced custody failure leaves principal unchanged"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-D19.
    function test_givenUnexpiredUnhealthyDebt_givenPricedRewardQuoteFails_whenExecuted() public {
        _unexpiredUnhealthyDebt();
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.keeperReward.selector),
            abi.encodeWithSelector(ConfigurationFailed.selector)
        );
        _expectScanFailure(abi.encodeWithSelector(ConfigurationFailed.selector));
        _expectNoSettlement();
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Priced reward failure advances expiry-empty page"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            2e9,
            "Priced reward failure leaves principal unchanged"
        );
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-N03.
    function test_givenMaximumLimits_givenOneUnexpiredBorrower_whenExecuted() public {
        _seedDebt(_ALICE, 10e6, 1e9);
        _task.setScanLimits(type(uint16).max, type(uint8).max);
        vm.expectCall(
            address(_lens),
            abi.encodeCall(
                IBurnerLoansLens.getExpiredBorrowersBoundedFor,
                (
                    address(_task),
                    address(_asset),
                    uint256(0),
                    uint256(type(uint16).max),
                    uint256(type(uint8).max)
                )
            ),
            uint64(1)
        );
        vm.expectCall(address(_lens), _boundedScan(address(_asset), 0), uint64(1));
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            uint64(1)
        );
        _expectNoSettlement();
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            0,
            "One borrower wraps under maximum limits"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(_inventory.activePrincipalOhm(), 1e9, "Healthy borrower is not settled");
    }

    // Scenarios: BLSEIZ-EXECUTE-P21.
    function test_givenHeartOnlyCaller_givenTaskSeizerOnly_givenOutage_whenExecuted(
        address caller_
    ) public {
        vm.assume(caller_ != address(0) && !_roles.hasRole(caller_, BURNER_LOANS_SEIZER_ROLE));
        _mixedDebt();
        _outage(OracleFault.PriceReverts);
        if (!_roles.hasRole(caller_, HEART_ROLE)) _rolesAdmin.grantRole(HEART_ROLE, caller_);
        assertFalse(_roles.hasRole(address(_task), HEART_ROLE), "Task has only seizer role");
        _expectNoPricedScan();
        vm.expectCall(
            address(_lens),
            abi.encodeCall(
                IBurnerLoansLens.getExpiredBorrowersBoundedFor,
                (address(_task), address(_asset), uint256(0), uint256(500), uint256(25))
            ),
            uint64(1)
        );
        vm.prank(caller_);
        _task.execute();
        _assertSettledExpired();
    }

    // Scenarios: BLSEIZ-EXECUTE-P30.
    function test_givenUnderwaterPrefix_givenOutage_whenPricesRecover_thenFirstPricedBatchResumesPrefix()
        public
    {
        _mixedDebt();
        _markMixedDebtUnderwater();
        _task.setScanLimits(1, 1);
        _outage(OracleFault.PriceReverts);
        _task.execute();
        _task.execute();
        _task.execute();
        _task.execute();
        _assertSettledExpired();
        _restoreOracleReads();
        _task.execute();
        assertEq(
            _lens.getPosition(address(_asset), _DAVE).debtOhm,
            0,
            "First recovered priced batch resumes underwater Dave at the prefix"
        );
        assertEq(
            _lens.getPosition(address(_asset), _CAROL).debtOhm,
            1e9,
            "Priced scan does not jump ahead to the suffix"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-P23.
    function test_givenMixedUnderwaterDebt_givenOutage_whenPricesRecover(
        uint16 checks_,
        uint8 results_,
        uint8 start_,
        uint8 fault_
    ) public {
        _mixedDebt();
        _markMixedDebtUnderwater();
        uint16 checks = uint16(bound(checks_, 1, type(uint16).max));
        uint8 results = uint8(
            bound(results_, 1, checks < type(uint8).max ? checks : type(uint8).max)
        );
        _task.setScanLimits(checks, results);
        bytes memory reason = _outage(
            OracleFault(bound(fault_, 0, uint8(OracleFault.CacheReverts)))
        );
        _setBothBorrowerCursors(address(_asset), bound(start_, 0, 2));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeize.BurnerLoans_PriceSnapshotUnavailable.selector,
                reason
            )
        );
        vm.prank(address(_task));
        _liquidation.seize(address(_asset), _one(_DAVE));
        _settleExpiredWithoutSeizingUnderwater();
        _restoreOracleReads();
        _drainRecoveredUnderwater(3e9);
    }

    // Scenarios: BLSEIZ-EXECUTE-P23.
    function test_givenMixedUnderwaterDebt_whenOutageCursorAndLimitBoundariesSeeded() public {
        for (uint8 fault; fault <= uint8(OracleFault.CacheReverts); ++fault) {
            for (uint8 start; start < 3; ++start) {
                uint256 state = vm.snapshotState();
                test_givenMixedUnderwaterDebt_givenOutage_whenPricesRecover(1, 1, start, fault);
                assertTrue(vm.revertToStateAndDelete(state), "Restore narrow-page recovery seed");
                state = vm.snapshotState();
                test_givenMixedUnderwaterDebt_givenOutage_whenPricesRecover(
                    type(uint16).max,
                    type(uint8).max,
                    start,
                    fault
                );
                assertTrue(vm.revertToStateAndDelete(state), "Restore maximum-limit recovery seed");
            }
        }
    }

    // Scenarios: BLSEIZ-EXECUTE-P24.
    function test_givenExpiredPrefix_givenUnderwaterSuffix_givenBackingOutage_whenPricesRecover()
        public
    {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _mature();
        _seedDebt(_CAROL, 10e6, 1e9);
        _seedDebt(_DAVE, 10e6, 1e9);
        _markMixedDebtUnderwater();
        _task.setScanLimits(3, 1);
        _outage(OracleFault.BackingReverts);
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        _task.execute();
        _task.execute(); // B retains its turn.
        _task.execute();
        _task.execute();
        assertEq(
            _lens.getPosition(address(_asset), _ALICE).debtOhm,
            0,
            "First expired borrower settles during backing outage"
        );
        _assertSettledExpired();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Expiry compaction leaves a nonzero cursor ahead of underwater Dave"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()) - treasuryBefore,
            20e6,
            "Only the two expired collateral positions reach Treasury"
        );
        _restoreOracleReads();
        _drainRecoveredUnderwater(4e9);
    }

    // Scenarios: BLSEIZ-EXECUTE-P25.
    function test_givenExternalCompaction_givenCursorStillValid_whenPricesRecover() public {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _mature();
        _seedDebt(_CAROL, 10e6, 1e9);
        _seedDebt(_DAVE, 10e6, 1e9);
        _setBothBorrowerCursors(address(_asset), 2);
        _repay(_ALICE, 1e9); // Dave moves from index3 to index0, behind the still-valid cursor2.
        assertEq(
            _lens.getActiveBorrowerCount(address(_asset)),
            3,
            "External compaction keeps cursor2 in range"
        );
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            2,
            "External repayment does not reset a valid cursor"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            2,
            "Expected independent unhealthy scan or retry offset"
        );
        _markMixedDebtUnderwater();
        _task.setScanLimits(1, 1);
        _outage(OracleFault.PriceReverts);
        _settleExpiredWithoutSeizingUnderwater();
        _restoreOracleReads();
        _drainRecoveredUnderwater(3e9);
    }

    // Scenarios: BLSEIZ-EXECUTE-P26.
    function test_givenStaleCursor_givenUnderwaterDebt_givenBackingOutage_whenPricesRecover()
        public
    {
        _mixedDebt();
        _setBothBorrowerCursors(address(_asset), 2);
        _repay(_CAROL, 1e9);
        _price.setPrice(address(_asset), 1e16);
        _assertUnexpiredUnderwater(_DAVE);
        _task.setScanLimits(1, 1);
        _outage(OracleFault.BackingReverts);
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            2,
            "Saved cursor is stale at the population boundary"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            2,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(
            _lens.getActiveBorrowerCount(address(_asset)),
            2,
            "Repayment shrank the population to the saved offset"
        );
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Repair starts at zero and advances past unpriced underwater debt"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        _task.execute();
        _task.execute();
        assertEq(
            _lens.getPosition(address(_asset), _BOB).debtOhm,
            0,
            "Expired debt remains reachable after repair"
        );
        assertEq(
            _lens.getPosition(address(_asset), _DAVE).debtOhm,
            1e9,
            "Underwater unexpired debt waits for prices"
        );
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            0,
            "Expiry deletion wraps to the remaining underwater borrower"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        _restoreOracleReads();
        _assertUnexpiredUnderwater(_DAVE);
        _task.execute(); // B turn.
        _task.execute();
        assertEq(
            _lens.getPosition(address(_asset), _DAVE).debtOhm,
            0,
            "Recovery revisits underwater debt without an admin reset"
        );
        assertEq(_inventory.activePrincipalOhm(), 0, "Repaid and seized debt fully reconciles");
        assertEq(
            _floan.getMarketPrincipalDefaulted(_core.marketId(address(_asset))),
            2e9,
            "Only Bob and Dave default once each"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-P27.
    function test_givenFailedExpiredBatch_givenUnderwaterDebt_whenServicesRecover() public {
        _mixedDebt();
        _markMixedDebtUnderwater();
        _task.setScanLimits(1, 1);
        _setBothBorrowerCursors(address(_asset), 1);
        _outage(OracleFault.PriceReverts);
        vm.mockCallRevert(
            address(_liquidation),
            abi.encodeCall(_liquidation.seize, (address(_asset), _one(_BOB))),
            abi.encodeWithSelector(CustodyFailed.selector)
        );
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureFailed(address(_asset), CustodyFailed.selector);
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            2,
            "Rejected expiry position advances one offset"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            1,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(_inventory.activePrincipalOhm(), 3e9, "Rejected expiry batch settles no debt");
        _restoreOracleReads();
        _assertUnexpiredUnderwater(_CAROL);
        _assertUnexpiredUnderwater(_DAVE);
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        for (uint256 i; i < 5; ++i) {
            _task.execute();
            _task.execute();
        }
        assertEq(
            _lens.getPosition(address(_asset), _BOB).debtOhm,
            0,
            "Expired debt remains reachable"
        );
        assertEq(_lens.getPosition(address(_asset), _CAROL).debtOhm, 0, "Carol is not starved");
        assertEq(_lens.getPosition(address(_asset), _DAVE).debtOhm, 0, "Dave is not skipped");
        assertEq(_inventory.activePrincipalOhm(), 0, "Both lanes drain eligible principal");
        assertEq(
            _floan.getMarketPrincipalDefaulted(_core.marketId(address(_asset))),
            3e9,
            "Every default occurs once"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()) - treasuryBefore,
            30e6,
            "Recovered collateral reaches Treasury"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-P28.
    function test_givenOnlyUnderwaterDebt_givenPriceOutage_whenPricesRecover() public {
        _seedDebt(_CAROL, 10e6, 1e9);
        _seedDebt(_DAVE, 10e6, 1e9);
        _markMixedDebtUnderwater();
        _task.setScanLimits(1, 1);
        _outage(OracleFault.PriceReverts);
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "First underwater-only page advances while unpriced"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        _task.execute();
        _task.execute();
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            0,
            "Second underwater-only page wraps during outage"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            2e9,
            "Outage cannot classify either unexpired borrower"
        );
        _restoreOracleReads();
        _drainRecoveredUnderwater(2e9);
    }

    // Scenarios: BLSEIZ-EXECUTE-P29.
    function test_givenHealthyAndUnderwaterDebt_givenOutage_whenPricesRecover() public {
        address healthy = makeAddr("healthy borrower");
        _mixedDebt();
        _seedDebt(healthy, 1000e6, 1e9);
        _markMixedDebtUnderwater();
        // 1000 collateral * $0.01 = $10; required $1.25; health=8e18.
        assertEq(
            _lens.positionHealthFactor(address(_asset), 1000e6, 1e9),
            8e18,
            "Healthy borrower remains above liquidation threshold"
        );
        _task.setScanLimits(1, 1);
        _setBothBorrowerCursors(address(_asset), 3);
        _outage(OracleFault.PriceReverts);
        for (uint256 i; i < 3; ++i) {
            _task.execute();
            _task.execute();
        }
        assertEq(
            _lens.getPosition(address(_asset), _BOB).debtOhm,
            0,
            "Expired middle position settles during outage"
        );
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Healthy tail swaps into the expired slot at the saved cursor"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            3,
            "Settlement preserves the saved unhealthy offset until next visit's repair"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            3e9,
            "Only the expired principal defaults during outage"
        );
        _restoreOracleReads();
        for (uint256 i; i < 3; ++i) {
            _task.execute();
            _task.execute();
        }
        assertEq(
            _lens.getPosition(address(_asset), _CAROL).debtOhm,
            0,
            "Recovery scans beyond healthy debt to underwater Carol"
        );
        assertEq(
            _lens.getPosition(address(_asset), _DAVE).debtOhm,
            0,
            "Recovery wraps to underwater Dave behind the cursor"
        );
        assertEq(
            _lens.getPosition(address(_asset), healthy).debtOhm,
            1e9,
            "Healthy debt is never seized"
        );
        assertEq(
            _lens.getPosition(address(_asset), healthy).depositedCollateral,
            1000e6,
            "Healthy collateral remains intact"
        );
        assertEq(_inventory.activePrincipalOhm(), 1e9, "Only healthy principal remains");
        assertEq(
            _lens.getActiveBorrowers(address(_asset)),
            _one(healthy),
            "No underwater borrower remains stranded in the active list"
        );
    }

    function _markMixedDebtUnderwater() private {
        _price.setPrice(address(_asset), 1e16);
        _assertUnexpiredUnderwater(_CAROL);
        _assertUnexpiredUnderwater(_DAVE);
    }

    // Scenarios: BLSEIZ-EXPIRED-CURSOR-I02, BLSEIZ-UNHEALTHY-CURSOR-I02.
    function test_givenRealLoans_givenOutage_whenInvalidBorrowerCursorSelected_reverts() public {
        _mixedDebt();
        _setBothBorrowerCursors(address(_asset), 1);
        _outage(OracleFault.PriceReverts);
        _assertBothCursorSettersReject(3);
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Population-boundary rejection preserves the saved cursor"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            1,
            "Expected independent unhealthy scan or retry offset"
        );
        _assertBothCursorSettersReject(type(uint256).max);
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "MAX256 rejection preserves the saved cursor during outage"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            1,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            3e9,
            "Failed cursor validation changes no principal"
        );
    }

    function _assertUnexpiredUnderwater(address borrower_) private view {
        IBurnerLoansCore.Position memory position = _lens.getPosition(address(_asset), borrower_);
        assertLt(
            vm.getBlockTimestamp(),
            position.maturity,
            "Recovery proof must not depend on unexpired debt maturing"
        );
        // 10e6 collateral (6 decimals) * 1e16 price / 1e6 = 1e17 USD (18 decimals).
        // 1e9 debt (9 decimals) needs max($1 / 0.85, $1 backing * 1.25) = 1.25e18 USD.
        // Health=1e17 * 1e18 / 1.25e18 = 8e16, strictly below 1e18.
        assertEq(
            _lens.positionHealthFactor(
                address(_asset),
                position.depositedCollateral,
                position.debtOhm
            ),
            8e16,
            "Skipped unexpired debt is genuinely underwater"
        );
    }

    function _settleExpiredWithoutSeizingUnderwater() private {
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        // Three entries and check>=1: at most one complete forward sweep reaches expired Bob.
        for (uint256 i; i < 3 && _lens.getPosition(address(_asset), _BOB).debtOhm != 0; ++i) {
            _task.execute();
            _task.execute(); // Preserve the other asset's normal turn.
            assertEq(
                _lens.getPosition(address(_asset), _CAROL).debtOhm,
                1e9,
                "Outage leaves underwater Carol outstanding"
            );
            assertEq(
                _lens.getPosition(address(_asset), _DAVE).debtOhm,
                1e9,
                "Outage leaves underwater Dave outstanding"
            );
        }
        _assertSettledExpired();
        assertEq(
            _asset.balanceOf(_payout.treasury()) - treasuryBefore,
            10e6,
            "Only expired collateral reaches Treasury during outage"
        );
    }

    function _restoreOracleReads() private {
        vm.clearMockedCalls();
        MockBackingOracle(_risk.backingOracle()).setEnabled(true);
        _price.setTimestamp(uint48(vm.getBlockTimestamp()));
        if (_risk.priceCache() != address(0)) _risk.setPriceCache(address(0));
    }

    function _drainRecoveredUnderwater(uint256 expectedDefaults_) private {
        _assertUnexpiredUnderwater(_CAROL);
        _assertUnexpiredUnderwater(_DAVE);
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        // Both remaining positions are underwater: each A visit can settle at least one.
        for (uint256 i; i < 2; ++i) {
            _task.execute();
            _task.execute();
        }
        assertEq(
            _lens.getPosition(address(_asset), _CAROL).debtOhm,
            0,
            "Recovery eventually settles underwater Carol"
        );
        assertEq(
            _lens.getPosition(address(_asset), _DAVE).debtOhm,
            0,
            "Recovery eventually settles underwater Dave even behind the cursor"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            0,
            "All eligible principal settles after recovery"
        );
        assertEq(
            _lens.getActiveBorrowerCount(address(_asset)),
            0,
            "Every eligible borrower leaves the active list"
        );
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            0,
            "Complete settlement leaves a zero borrower cursor"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(
            _floan.getMarketPrincipalDefaulted(_core.marketId(address(_asset))),
            expectedDefaults_,
            "No borrower is skipped or defaulted twice"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()) - treasuryBefore,
            20e6,
            "Both recovered underwater collateral positions reach Treasury"
        );
    }

    function _unexpiredUnhealthyDebt() private {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _task.setScanLimits(1, 1);
        _price.setPrice(address(_asset), 1e16);
    }

    // Scenarios: BLSEIZ-EXECUTE-D11.
    function test_givenRiskPaused_whenLifecycleBoundarySeeded() public {
        test_givenRiskUnavailable_whenExecuted(true);
    }

    // Scenarios: BLSEIZ-EXECUTE-D12.
    function test_givenRiskInactiveEnabled_whenLifecycleBoundarySeeded() public {
        test_givenRiskUnavailable_whenExecuted(false);
    }

    // Scenarios: BLSEIZ-EXECUTE-D12.
    function test_givenRiskInactivePaused_whenExecuted() public {
        _mixedDebt();
        _risk.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_risk));
        _expectPricedScans(1);
        _expectScanFailure(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_risk)
            )
        );
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            0,
            "Inactive paused Risk retains retry start"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(_inventory.activePrincipalOhm(), 3e9, "Inactive paused Risk retains all debt");
        _kernel.executeAction(Actions.ActivatePolicy, address(_risk));
        _risk.reEnable();
        _task.execute();
        _task.execute();
        _assertSettledExpired();
    }

    // Scenarios: BLSEIZ-EXECUTE-D14.
    function test_givenCorePaused_whenLifecycleBoundarySeeded() public {
        test_givenCoreUnavailable_givenOutage_whenExecuted(true);
    }

    // Scenarios: BLSEIZ-EXECUTE-D14.
    function test_givenCoreInactiveEnabled_whenLifecycleBoundarySeeded() public {
        test_givenCoreUnavailable_givenOutage_whenExecuted(false);
    }

    // Scenarios: BLSEIZ-EXECUTE-D14.
    function test_givenCoreInactivePaused_givenOutage_whenExecuted() public {
        _mixedDebt();
        _outage(OracleFault.PriceReverts);
        _core.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        _expectPricedScans(1);
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureFailed(
            address(_asset),
            PolicyDependency.PolicyDependency_NotActive.selector
        );
        _task.execute();
        assertEq(
            _task.expiredAssetCursor(address(_asset)),
            1,
            "Inactive Core rejection advances one offset"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(_inventory.activePrincipalOhm(), 3e9, "Inactive paused Core retains debt");
        _kernel.executeAction(Actions.ActivatePolicy, address(_core));
        _core.reEnable();
        _task.execute();
        _task.execute();
        _assertSettledExpired();
    }

    // Scenarios: BLSEIZ-EXECUTE-P19.
    function test_givenHealthyDebtAtMaturityMinusOne_whenExecuted() public {
        _seedDebt(_ALICE, 10e6, 1e9);
        vm.warp(_position(_ALICE).maturity - 1);
        _price.setTimestamp(uint48(block.timestamp));
        vm.expectCall(address(_lens), _boundedScan(address(_asset), 0), uint64(1));
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            uint64(1)
        );
        _expectNoSettlement();
        _task.execute();
        assertEq(
            _inventory.activePrincipalOhm(),
            1e9,
            "Pre-maturity healthy debt remains outstanding"
        );
        assertEq(_task.expiredAssetCursor(address(_asset)), 0, "One-position page reaches its end");
        assertEq(
            _task.unhealthyAssetCursor(address(_asset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
        assertEq(_task.nextAssetIndex(), 1, "Pre-maturity page rotates once");
    }

    // Scenarios: BLSEIZ-EXECUTE-P20.
    function test_givenExpiredDebtAtMaturityPlusOne_givenOutage_whenExecuted() public {
        _seedDebt(_ALICE, 10e6, 1e9);
        vm.warp(_position(_ALICE).maturity + 1);
        _outage(OracleFault.PriceReverts);
        _expectNoPricedScan();
        uint256 treasuryBefore = _asset.balanceOf(_payout.treasury());
        _task.execute();
        uint32 market = _core.marketId(address(_asset));
        assertEq(_inventory.activePrincipalOhm(), 0, "Post-maturity debt settles without prices");
        assertEq(
            _floan.getMarketPrincipalDefaulted(market),
            1e9,
            "Default accounting records principal once"
        );
        assertEq(
            _floan.getMarketCollateral(market),
            0,
            "Expired collateral leaves FLOAN custody ledger"
        );
        assertEq(
            _asset.balanceOf(_payout.treasury()) - treasuryBefore,
            10e6,
            "Treasury receives the full expired collateral"
        );
        assertEq(_task.nextAssetIndex(), 1, "Post-maturity settlement rotates once");
    }

    // Scenarios: BLSEIZ-EXECUTE-C01.
    function test_givenCollateralCallback_whenNestedExecuteCaught_thenOuterBatchSettlesOnce()
        public
    {
        ReentrantFeeToken token = _callbackDebt();
        token.setCallbackFrom(
            address(_depositManager),
            address(_task),
            abi.encodeCall(_task.execute, ())
        );
        uint256 treasuryBefore = token.balanceOf(_payout.treasury());
        _task.execute();
        assertEq(
            token.callbackRevertData(),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, HEART_ROLE),
            "Callback without HEART is rejected before nested progress"
        );
        _assertCallbackSettlement(token, treasuryBefore);
    }

    // Scenarios: BLSEIZ-EXECUTE-C02.
    function test_givenCollateralCallback_whenNestedSelfCallCaught_thenOuterBatchSettlesOnce()
        public
    {
        ReentrantFeeToken token = _callbackDebt();
        token.setCallbackFrom(
            address(_depositManager),
            address(_task),
            abi.encodeCall(_task.selfExecuteTask, ())
        );
        uint256 treasuryBefore = token.balanceOf(_payout.treasury());
        _task.execute();
        assertEq(
            token.callbackRevertData(),
            abi.encodeWithSelector(IBurnerLoansSeizerTask.BurnerLoansSeizer_OnlySelf.selector),
            "Callback cannot enter the self-only body"
        );
        _assertCallbackSettlement(token, treasuryBefore);
    }

    function _callbackDebt() private returns (ReentrantFeeToken token) {
        token = new ReentrantFeeToken();
        _price.setPrice(address(token), 1e18);
        _admit(address(token));
        token.mint(_ALICE, 20e18);
        vm.startPrank(_ALICE);
        token.approve(address(_core), type(uint256).max);
        _collateral.depositCollateral(address(token), 10e18, _ALICE);
        _debt.borrow(address(token), 1e9, _ALICE, _ALICE, type(uint256).max, address(0));
        vm.stopPrank();
        _mature();
        _task.removeAsset(address(_asset));
        _task.removeAsset(address(_otherAsset));
        _task.addAsset(address(token));
        _task.addAsset(address(_otherAsset));
    }

    function _assertCallbackSettlement(
        ReentrantFeeToken token_,
        uint256 treasuryBefore_
    ) private view {
        assertFalse(token_.callbackEnabled(), "The transfer callback was invoked");
        assertFalse(token_.callbackSucceeded(), "Nested task entry was rejected");
        assertEq(_inventory.activePrincipalOhm(), 0, "Only the outer principal defaults");
        uint32 market = _core.marketId(address(token_));
        assertEq(
            _floan.getMarketPrincipalDefaulted(market),
            1e9,
            "Principal defaults exactly once"
        );
        assertEq(
            _floan.getActiveBorrowerCount(market),
            0,
            "Settled borrower leaves the active list"
        );
        // 10e18 collateral (18 decimals), zero protocol reward: Treasury receives exactly 10e18.
        assertEq(
            token_.balanceOf(_payout.treasury()) - treasuryBefore_,
            10e18,
            "Outer custody reaches Treasury once"
        );
        assertEq(token_.balanceOf(address(_depositManager)), 0, "Outer collateral leaves custody");
        assertEq(token_.balanceOf(address(_task)), 0, "Task retains no callback collateral");
        assertEq(_task.nextAssetIndex(), 1, "Rejected callback cannot consume a second asset turn");
        assertEq(
            _task.expiredAssetCursor(address(_otherAsset)),
            0,
            "Other asset borrower cursor remains untouched"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_otherAsset)),
            0,
            "Expected independent unhealthy scan or retry offset"
        );
    }

    function _expectNoSettlement() private {
        vm.expectCall(
            address(_liquidation),
            abi.encodeWithSelector(_liquidation.seize.selector),
            uint64(0)
        );
    }

    function _expectNoPricedScan() internal {
        _expectPricedScans(0);
    }

    function _expectPricedScans(uint64 calls_) private {
        vm.expectCall(
            address(_lens),
            abi.encodeWithSelector(
                IBurnerLoansLens.getUnhealthyBorrowersBoundedFor.selector,
                address(_task),
                address(_asset)
            ),
            calls_
        );
    }

    function _managerWithLaterTask()
        internal
        returns (MockPeriodicTaskManager manager, MockPeriodicTask later)
    {
        manager = new MockPeriodicTaskManager(_kernel);
        _kernel.executeAction(Actions.ActivatePolicy, address(manager));
        _rolesAdmin.grantRole(HEART_ROLE, address(manager));
        later = new MockPeriodicTask();
        manager.addPeriodicTask(address(_task));
        manager.addPeriodicTask(address(later));
    }

    function _mixedDebt() internal {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _mature();
        _seedDebt(_CAROL, 10e6, 1e9);
        _seedDebt(_DAVE, 10e6, 1e9);
        _repay(_ALICE, 1e9); // Dave swaps ahead of expired Bob; Carol remains unexpired.
        assertEq(
            _floan.getActiveBorrowerAt(_core.marketId(address(_asset)), 0),
            _DAVE,
            "Canonical unexpired prefix established"
        );
    }

    function _assertSettledExpired() internal view {
        assertEq(
            _lens.getPosition(address(_asset), _BOB).debtOhm,
            0,
            "Expired suffix borrower settled"
        );
        assertEq(
            _lens.getPosition(address(_asset), _CAROL).debtOhm,
            1e9,
            "Unexpired Carol untouched"
        );
        assertEq(
            _lens.getPosition(address(_asset), _DAVE).debtOhm,
            1e9,
            "Unexpired Dave untouched"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            2e9,
            "Inventory principal matches remaining debt"
        );
        assertEq(
            _floan.getMarketPrincipalDue(_core.marketId(address(_asset))),
            2e9,
            "Canonical aggregate principal agrees"
        );
        assertEq(
            _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
            2,
            "Canonical membership contains only unexpired debt"
        );
        assertEq(
            _lens.getActiveBorrowers(address(_asset)),
            _two(_DAVE, _CAROL),
            "Swap-and-pop retains each unexpired canonical member once"
        );
        assertEq(_asset.balanceOf(address(_task)), 0, "Task receives no reward");
    }

    function _expectScanFailure(bytes memory reason_) internal {
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ScanFailed(address(_asset), bytes4(reason_));
    }

    function _outage(OracleFault fault_) internal returns (bytes memory reason) {
        reason = abi.encodeWithSelector(OracleUnavailable.selector);
        if (fault_ == OracleFault.PriceReverts) {
            vm.mockCallRevert(
                address(_price),
                abi.encodeWithSelector(IDiscoveryPrice.getPrice.selector),
                reason
            );
        } else if (fault_ == OracleFault.BackingReverts)
            vm.mockCallRevert(
                _risk.backingOracle(),
                abi.encodeWithSelector(IBackingOracle.backing.selector),
                reason
            );
        else if (fault_ == OracleFault.BackingPaused) {
            MockBackingOracle(_risk.backingOracle()).setEnabled(false);
            reason = abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                _risk.backingOracle()
            );
        } else if (fault_ == OracleFault.PriceStale) {
            _price.setTimestamp(uint48(vm.getBlockTimestamp() - _price.observationFrequency() - 1));
            reason = abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        } else {
            PriceCache cache = new PriceCache(_kernel, 18, "USD");
            _kernel.executeAction(Actions.ActivatePolicy, address(cache));
            cache.enable("");
            _risk.setPriceCache(address(cache));
            vm.mockCallRevert(
                address(cache),
                abi.encodeWithSelector(IPriceCache.getCachedPrice.selector),
                reason
            );
            // Seize execution refreshes rather than calling the cache's external view getter.
            // An unavailable-cache fixture must reject that route too.
            vm.mockCallRevert(
                address(cache),
                abi.encodeWithSelector(IPriceCache.cachePriceIfNecessary.selector),
                reason
            );
        }
    }

    function _assertBothCursorSettersReject(uint256 index_) private {
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
            index_,
            uint256(3)
        );
        vm.expectRevert(error);
        _task.setExpiredAssetCursor(address(_asset), index_);
        vm.expectRevert(error);
        _task.setUnhealthyAssetCursor(address(_asset), index_);
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop,unused-return)
