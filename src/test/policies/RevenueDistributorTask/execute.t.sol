// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Bounded loops assert every asset in traversal fixtures; the second contract is a file-local gas mock.
// forge-lint: disable-start(calls-loop,multi-contract-file)

import {Vm} from "@forge-std-1.16.2/Vm.sol";

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {GasBurningRevenueToken} from "src/test/mocks/GasBurningRevenueToken.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

/// @dev Substitute only the indexed getter. Its second lookup burns gas but returns normally.
///      Keeping a gas remainder avoids tying the test to exact compiler opcode costs.
contract GasCostlyAssetLookup {
    error InvalidLookupAssets();

    uint256 internal constant GAS_LEFT_TO_RETURN = 30_000;
    address internal immutable _FIRST;
    address internal immutable _SECOND;
    bool internal immutable _BURN_GAS;

    constructor(address first_, address second_, bool burnGas_) {
        if (first_ == address(0) || second_ == address(0)) revert InvalidLookupAssets();
        _FIRST = first_;
        _SECOND = second_;
        _BURN_GAS = burnGas_;
    }

    function getActiveAssetAt(uint256 index_) external view returns (address) {
        if (index_ == 0) return _FIRST;
        if (_BURN_GAS) {
            while (gasleft() > GAS_LEFT_TO_RETURN) {}
        }
        return _SECOND;
    }
}

contract RevenueDistributorTaskExecuteTest is RevenueDistributorTaskTest {
    error MockDistributionFailure(uint256 code);
    error MockGetterFailure();

    uint32 internal constant LIMITED_EXECUTION_GAS = 1_000_000;
    uint8 internal constant THREE_ASSET_COUNT = 3;
    uint256 internal constant DEFAULT_RECEIPT = 11;
    uint256 internal constant TRAVERSAL_RECEIPT = 10;
    uint256 internal constant MANY_ASSET_COUNT = 13;
    uint256 internal constant FAILED_RECEIPT = 13;
    uint256 internal constant LATER_RECEIPT = 19;
    uint8 internal constant TOKEN_DECIMALS = 18;

    // Scenarios: TASK-A01.
    function test_whenCallerLacksHeartRole_revertsBeforeLifecycleChecks(
        address caller_,
        bool taskActive_,
        bool taskEnabled_,
        bool distributorActive_,
        bool distributorEnabled_
    ) public {
        vm.prank(admin);
        rolesAdmin.grantRole(HEART_ROLE, bob);
        vm.assume(caller_ != alice);
        vm.assume(caller_ != bob);
        _setTaskLifecycle(taskActive_, taskEnabled_);
        _setDistributorLifecycle(distributorActive_, distributorEnabled_);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, HEART_ROLE));
        vm.prank(caller_);
        task.execute();

        assertEq(task.nextAssetIndex(), 0, "unauthorized call preserves cursor");
    }

    // Scenarios: TASK-P01.
    function test_givenTaskDisabled_executeDoesNotQueryDistributor(
        bool distributorActive_,
        bool distributorEnabled_,
        uint8 assetCount_,
        uint8 receipt_
    ) public {
        assetCount_ = _boundUint8(assetCount_, 0, 2);
        MockERC20[] memory assets = _configureAssets(assetCount_, receipt_);
        if (assetCount_ == 2) {
            vm.prank(admin);
            task.setNextAssetIndex(1);
        }
        _disableTask("");
        _setDistributorLifecycle(distributorActive_, distributorEnabled_);
        vm.mockCallRevert(
            address(distributor),
            abi.encodeCall(IRevenueDistributor.getActiveAssetCount, ()),
            abi.encodeWithSelector(MockGetterFailure.selector)
        );
        vm.recordLogs();

        vm.prank(alice);
        task.execute();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "disabled execute emits no events");
        assertEq(
            task.nextAssetIndex(),
            assetCount_ == 2 ? 1 : 0,
            "disabled execute preserves cursor"
        );
        for (uint256 i; i < assets.length; ++i) {
            assertEq(assets[i].balanceOf(address(distributor)), receipt_, "receipt retained");
        }
    }

    // Scenarios: TASK-P02, TASK-P07, TASK-P13.
    function test_givenDistributorUnavailable_whenHeartExecutes(
        bool distributorActive_,
        bool distributorEnabled_,
        uint8 assetCount_
    ) public {
        vm.assume(!distributorActive_ || !distributorEnabled_);
        assetCount_ = _boundUint8(assetCount_, 1, THREE_ASSET_COUNT);
        MockERC20[] memory assets = _configureAssets(assetCount_, DEFAULT_RECEIPT);
        if (assetCount_ > 1) {
            vm.prank(admin);
            task.setNextAssetIndex(1);
        }
        _setDistributorLifecycle(distributorActive_, distributorEnabled_);
        vm.mockCallRevert(
            address(distributor),
            abi.encodeCall(IRevenueDistributor.getActiveAssetCount, ()),
            abi.encodeWithSelector(MockGetterFailure.selector)
        );
        vm.recordLogs();
        vm.prank(alice);
        task.execute();

        assertEq(vm.getRecordedLogs().length, 0, "unavailable distributor emits no events");
        assertEq(
            task.nextAssetIndex(),
            assetCount_ > 1 ? 1 : 0,
            "unavailable distributor preserves cursor"
        );
        for (uint256 i; i < assets.length; ++i) {
            assertEq(
                assets[i].balanceOf(address(distributor)),
                DEFAULT_RECEIPT,
                "receipt retained"
            );
        }
    }

    // Scenarios: TASK-P08.
    function test_givenNoActiveAssets_executeIsSilentAndPreservesCursor() public {
        MockERC20[] memory assets = _configureAssets(2, 0);
        vm.prank(admin);
        task.setNextAssetIndex(1);
        vm.startPrank(address(configTimelock));
        distributor.disableAssetRoutes(address(assets[0]));
        distributor.disableAssetRoutes(address(assets[1]));
        vm.stopPrank();
        vm.recordLogs();

        vm.prank(alice);
        task.execute();

        assertEq(vm.getRecordedLogs().length, 0, "empty execute emits no events");
        assertEq(task.nextAssetIndex(), 1, "empty execute preserves cursor");
    }

    // Scenarios: TASK-P03.
    function test_givenTaskInactive_executeDoesNotQueryDistributor(bool disabled_) public {
        _configureAsset(token, DEFAULT_RECEIPT);
        _setTaskDisabled(disabled_);
        _deactivateTask();
        vm.mockCallRevert(
            address(distributor),
            abi.encodeCall(IRevenueDistributor.getActiveAssetCount, ()),
            "distributor must not be queried"
        );
        vm.recordLogs();

        vm.prank(alice);
        task.execute();

        assertEq(vm.getRecordedLogs().length, 0, "inactive execute emits no events");
        assertEq(
            token.balanceOf(address(distributor)),
            DEFAULT_RECEIPT,
            "receipt remains in custody"
        );
        assertEq(task.nextAssetIndex(), 0, "cursor unchanged");
    }

    // Scenarios: TASK-P04.
    function test_givenOneActiveAsset_executeVisitsItOnce() public {
        _configureAsset(token, DEFAULT_RECEIPT);

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(token), address(treasury), DEFAULT_RECEIPT);
        vm.prank(alice);
        task.execute();

        assertEq(token.balanceOf(address(treasury)), DEFAULT_RECEIPT, "Treasury receives receipt");
        assertEq(task.nextAssetIndex(), 0, "single-asset cursor wraps");
    }

    // Scenarios: TASK-P09.
    function test_givenTwoActiveAssets_executeVisitsEachInOrder() public {
        MockERC20[] memory assets = _configureAssets(2, DEFAULT_RECEIPT);

        _expectTreasuryDistribution(assets[0], DEFAULT_RECEIPT);
        _expectTreasuryDistribution(assets[1], DEFAULT_RECEIPT);
        vm.prank(alice);
        task.execute();

        assertEq(assets[0].balanceOf(address(treasury)), DEFAULT_RECEIPT, "first asset settled");
        assertEq(assets[1].balanceOf(address(treasury)), DEFAULT_RECEIPT, "second asset settled");
        assertEq(task.nextAssetIndex(), 0, "cursor wraps");
    }

    // Scenarios: TASK-P10, TASK-P11.
    function test_givenThirteenActiveAssets_executeVisitsCircularOrder(uint256 cursor_) public {
        MockERC20[] memory assets = _configureAssets(MANY_ASSET_COUNT, TRAVERSAL_RECEIPT);
        cursor_ = bound(cursor_, 1, assets.length - 1);
        vm.prank(admin);
        task.setNextAssetIndex(cursor_);

        for (uint256 i; i < assets.length; ++i) {
            uint256 index = (cursor_ + i) % assets.length;
            vm.expectCall(
                address(distributor),
                abi.encodeCall(IRevenueDistributor.getActiveAssetAt, (index)),
                1
            );
            _expectTreasuryDistribution(assets[index], TRAVERSAL_RECEIPT);
        }
        vm.prank(alice);
        task.execute();

        for (uint256 i; i < assets.length; ++i) {
            assertEq(
                assets[i].balanceOf(address(treasury)),
                TRAVERSAL_RECEIPT,
                "asset settled once"
            );
        }
        assertEq(task.nextAssetIndex(), cursor_, "full traversal returns to starting cursor");
    }

    // Scenarios: TASK-P12.
    function test_givenCursorOutOfRangeAfterRetirement_executeNormalizesTraversal() public {
        MockERC20[] memory assets = _configureAssets(THREE_ASSET_COUNT, TRAVERSAL_RECEIPT);
        vm.prank(admin);
        task.setNextAssetIndex(2);
        vm.prank(address(configTimelock));
        distributor.disableAssetRoutes(address(assets[2]));

        _expectTreasuryDistribution(assets[0], TRAVERSAL_RECEIPT);
        _expectTreasuryDistribution(assets[1], TRAVERSAL_RECEIPT);
        vm.prank(alice);
        task.execute();

        assertEq(task.nextAssetIndex(), 0, "normalized traversal wraps");
        assertEq(
            assets[0].balanceOf(address(treasury)),
            TRAVERSAL_RECEIPT,
            "first remaining asset settled"
        );
        assertEq(
            assets[1].balanceOf(address(treasury)),
            TRAVERSAL_RECEIPT,
            "second remaining asset settled"
        );
        assertEq(
            assets[2].balanceOf(address(distributor)),
            TRAVERSAL_RECEIPT,
            "retired asset retained"
        );
    }

    // Scenarios: TASK-P05.
    function test_givenLimitedExecutionGas_repeatedBeatsSettleEveryAsset(uint256 cursor_) public {
        MockERC20[] memory assets = _configureAssets(8, TRAVERSAL_RECEIPT);
        cursor_ = bound(cursor_, 0, assets.length - 1);
        vm.startPrank(admin);
        task.setNextAssetIndex(cursor_);
        task.setExecutionGasLimit(900_000);
        vm.stopPrank();

        vm.prank(alice);
        task.execute();
        uint256 firstCursor = task.nextAssetIndex();
        assertTrue(firstCursor != cursor_, "first beat advances cursor");

        for (uint256 beat; beat < assets.length; ++beat) {
            vm.prank(alice);
            task.execute();
        }
        for (uint256 i; i < assets.length; ++i) {
            assertEq(
                assets[i].balanceOf(address(treasury)),
                TRAVERSAL_RECEIPT,
                "every asset settles"
            );
        }
    }

    // Scenarios: TASK-G01.
    function test_givenAttemptThresholdConsumesBudget_executeStopsBeforeLookup() public {
        _configureAsset(token, DEFAULT_RECEIPT);
        vm.prank(admin);
        task.setMinimumGasToAttempt(type(uint32).max);

        vm.prank(alice);
        task.execute();

        assertEq(task.nextAssetIndex(), 0, "cursor does not advance without an attempt");
        assertEq(
            token.balanceOf(address(distributor)),
            DEFAULT_RECEIPT,
            "receipt remains unattempted"
        );

        vm.prank(admin);
        task.setMinimumGasToAttempt(250_000);
        vm.prank(alice);
        task.execute();
        assertEq(token.balanceOf(address(treasury)), DEFAULT_RECEIPT, "later beat settles receipt");
    }

    // Scenarios: TASK-G02.
    function test_givenIndexedLookupConsumesReserve_executePausesThenResumes() public {
        MockERC20[] memory assets = _configureAssets(2, DEFAULT_RECEIPT);
        GasCostlyAssetLookup costlyLookup = new GasCostlyAssetLookup(
            address(assets[0]),
            address(assets[1]),
            true
        );
        vm.mockFunction(
            address(distributor),
            address(costlyLookup),
            abi.encodeWithSelector(IRevenueDistributor.getActiveAssetAt.selector)
        );
        vm.prank(admin);
        task.setExecutionGasLimit(LIMITED_EXECUTION_GAS);
        // Reverting if distribution is attempted distinguishes the post-lookup cutoff from
        // a caught distribution failure; the first asset must still commit its settlement.
        vm.mockCallRevert(
            address(distributor),
            abi.encodeCall(IRevenueDistributor.distribute, (address(assets[1]))),
            abi.encodeWithSelector(MockDistributionFailure.selector, 1)
        );
        vm.expectCall(
            address(costlyLookup),
            abi.encodeCall(IRevenueDistributor.getActiveAssetAt, (uint256(1))),
            1
        );
        vm.recordLogs();
        vm.prank(alice);
        task.execute();

        assertEq(
            assets[0].balanceOf(address(treasury)),
            DEFAULT_RECEIPT,
            "earlier settlement remains committed"
        );
        assertEq(
            assets[1].balanceOf(address(distributor)),
            DEFAULT_RECEIPT,
            "unattempted receipt stays in custody"
        );
        assertEq(
            distributor.totalPendingForTest(address(assets[1])),
            0,
            "no debt created without an attempt"
        );
        assertEq(task.nextAssetIndex(), 1, "cursor stays at unattempted asset");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "only the earlier token transfer and distribution event commit");
        assertEq(
            logs[1].topics[0],
            keccak256("Distributed(address,address,uint256)"),
            "no task or asset failure event"
        );

        vm.clearMockedCalls();
        // Explicitly replace the function redirect too, so the continuation uses a cheap getter.
        GasCostlyAssetLookup cheapLookup = new GasCostlyAssetLookup(
            address(assets[0]),
            address(assets[1]),
            false
        );
        vm.mockFunction(
            address(distributor),
            address(cheapLookup),
            abi.encodeWithSelector(IRevenueDistributor.getActiveAssetAt.selector)
        );
        vm.prank(alice);
        task.execute();
        assertEq(
            assets[1].balanceOf(address(treasury)),
            DEFAULT_RECEIPT,
            "next beat settles paused asset"
        );
        assertEq(assets[1].balanceOf(address(distributor)), 0, "next beat clears paused custody");
        assertEq(
            assets[0].balanceOf(address(treasury)),
            DEFAULT_RECEIPT,
            "earlier receipt is not paid twice"
        );
    }

    // Scenarios: TASK-T03.
    function test_givenFirstAssetBurnsGas_nextBeatSettlesLaterAsset() public {
        GasBurningRevenueToken badToken = new GasBurningRevenueToken();
        MockERC20 laterAsset = new MockERC20("Later", "LATER", TOKEN_DECIMALS);
        _configureRevenueAsset(address(badToken));
        _configureAsset(laterAsset, LATER_RECEIPT);
        badToken.mint(address(distributor), FAILED_RECEIPT);
        vm.prank(admin);
        task.setExecutionGasLimit(LIMITED_EXECUTION_GAS);

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.DistributionDeferred(
            address(badToken),
            address(treasury),
            FAILED_RECEIPT
        );
        vm.prank(alice);
        task.execute();

        assertEq(
            badToken.balanceOf(address(distributor)),
            FAILED_RECEIPT,
            "failed receipt retained"
        );
        _assertPendingPayouts(address(badToken), address(0), 0, 0, FAILED_RECEIPT);
        assertEq(laterAsset.balanceOf(address(treasury)), 0, "later asset waits");
        assertEq(task.nextAssetIndex(), 1, "cursor advances past failed asset");

        vm.prank(alice);
        task.execute();
        assertEq(
            laterAsset.balanceOf(address(treasury)),
            LATER_RECEIPT,
            "later asset settles next beat"
        );
    }

    // Scenarios: TASK-T01.
    function test_givenTokenTransferFails_taskDefersShareAndContinues(bool returnsFalse_) public {
        MockRevertingTransferToken badToken = new MockRevertingTransferToken(TOKEN_DECIMALS);
        MockERC20 laterAsset = new MockERC20("Later", "LATER", TOKEN_DECIMALS);
        _configureRevenueAsset(address(badToken));
        _configureAsset(laterAsset, LATER_RECEIPT);
        badToken.mint(address(distributor), FAILED_RECEIPT);
        if (returnsFalse_) {
            vm.mockCall(
                address(badToken),
                abi.encodeWithSelector(
                    badToken.transfer.selector,
                    address(treasury),
                    FAILED_RECEIPT
                ),
                abi.encode(false)
            );
        } else {
            badToken.setTransferReverts(address(treasury), true);
        }

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.DistributionDeferred(
            address(badToken),
            address(treasury),
            FAILED_RECEIPT
        );
        _expectTreasuryDistribution(laterAsset, LATER_RECEIPT);
        vm.prank(alice);
        task.execute();

        _assertPendingPayouts(address(badToken), address(0), 0, 0, FAILED_RECEIPT);
        assertEq(laterAsset.balanceOf(address(treasury)), LATER_RECEIPT, "later asset settles");

        vm.clearMockedCalls();
        badToken.setTransferReverts(address(treasury), false);
        distributor.transferPendingPayout(address(badToken), address(treasury));
        _assertPendingPayouts(address(badToken), address(0), 0, 0, 0);
        assertEq(
            badToken.balanceOf(address(treasury)),
            FAILED_RECEIPT,
            "deferred share later settles"
        );
    }

    // Scenarios: TASK-T02.
    function test_givenDistributionRevertsWithSelector_taskEmitsSelectorAndContinues() public {
        _assertDistributionFailure(abi.encodeWithSelector(MockDistributionFailure.selector, 7));
    }

    // Scenarios: TASK-T05.
    function test_givenDistributionRevertsWithoutData_taskEmitsZeroAndContinues() public {
        _assertDistributionFailure("");
    }

    // Scenarios: TASK-T06.
    function test_givenDistributionRevertsWithLongData_taskEmitsFirstFourBytes() public {
        _assertDistributionFailure(
            abi.encodeWithSelector(MockDistributionFailure.selector, type(uint256).max)
        );
    }

    // Scenarios: TASK-T04.
    function test_givenInsufficientSelfCallGas_executeEmitsFailureAndRollsBack() public {
        MockERC20[] memory assets = _configureAssets(2, DEFAULT_RECEIPT);
        vm.prank(admin);
        task.setNextAssetIndex(1);
        vm.prank(admin);
        task.setExecutionGasLimit(1);

        vm.expectEmit(false, false, false, true, address(task));
        emit IRevenueDistributorTask.ExecutionFailed(bytes4(0));
        vm.prank(alice);
        task.execute();

        assertEq(task.nextAssetIndex(), 1, "failed self-call preserves cursor");
        assertEq(
            assets[0].balanceOf(address(distributor)),
            DEFAULT_RECEIPT,
            "first receipt retained"
        );
        assertEq(
            assets[1].balanceOf(address(distributor)),
            DEFAULT_RECEIPT,
            "second receipt retained"
        );
    }

    // Scenarios: TASK-T07.
    function test_givenAssetCountGetterReverts_executeEmitsFailure() public {
        _configureAsset(token, DEFAULT_RECEIPT);
        vm.mockCallRevert(
            address(distributor),
            abi.encodeCall(IRevenueDistributor.getActiveAssetCount, ()),
            abi.encodeWithSelector(MockGetterFailure.selector)
        );

        vm.expectEmit(false, false, false, true, address(task));
        emit IRevenueDistributorTask.ExecutionFailed(MockGetterFailure.selector);
        vm.prank(alice);
        task.execute();

        assertEq(task.nextAssetIndex(), 0, "cursor unchanged");
        assertEq(token.balanceOf(address(distributor)), DEFAULT_RECEIPT, "receipt retained");
    }

    // Scenarios: TASK-T08.
    function test_givenLaterAssetGetterReverts_executeRollsBackEarlierSettlement() public {
        MockERC20[] memory assets = _configureAssets(2, DEFAULT_RECEIPT);
        vm.mockCallRevert(
            address(distributor),
            abi.encodeCall(IRevenueDistributor.getActiveAssetAt, (1)),
            abi.encodeWithSelector(MockGetterFailure.selector)
        );

        vm.expectEmit(false, false, false, true, address(task));
        emit IRevenueDistributorTask.ExecutionFailed(MockGetterFailure.selector);
        vm.prank(alice);
        task.execute();

        assertEq(task.nextAssetIndex(), 0, "cursor rollback is complete");
        assertEq(
            assets[0].balanceOf(address(distributor)),
            DEFAULT_RECEIPT,
            "earlier receipt rolled back"
        );
        assertEq(
            assets[1].balanceOf(address(distributor)),
            DEFAULT_RECEIPT,
            "later receipt retained"
        );
        assertEq(assets[0].balanceOf(address(treasury)), 0, "earlier payout rolled back");
    }

    function _assertDistributionFailure(bytes memory reason_) internal {
        MockERC20[] memory assets = _configureAssets(2, DEFAULT_RECEIPT);
        vm.mockCallRevert(
            address(distributor),
            abi.encodeCall(IRevenueDistributor.distribute, (address(assets[0]))),
            reason_
        );
        // The nonzero branch is reached only when reason_ contains at least four bytes.
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes4 selector = reason_.length < 4 ? bytes4(0) : bytes4(reason_);

        vm.expectEmit(true, false, false, true, address(task));
        emit IRevenueDistributorTask.AssetDistributionFailed(address(assets[0]), selector);
        _expectTreasuryDistribution(assets[1], DEFAULT_RECEIPT);
        vm.prank(alice);
        task.execute();

        assertEq(
            assets[0].balanceOf(address(distributor)),
            DEFAULT_RECEIPT,
            "failed receipt retained"
        );
        assertEq(assets[1].balanceOf(address(treasury)), DEFAULT_RECEIPT, "later receipt settles");
        assertEq(task.nextAssetIndex(), 0, "cursor wraps after both attempts");
    }

    function _configureRevenueAsset(address asset_) internal {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(asset_, 0, routes);
    }

    function _expectTreasuryDistribution(MockERC20 asset_, uint256 amount_) internal {
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(asset_), address(treasury), amount_);
    }
}

// forge-lint: disable-end(calls-loop,multi-contract-file)
