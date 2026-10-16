// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {StdInvariant} from "@forge-std-1.16.2/StdInvariant.sol";
import {Actions, Policy} from "src/Kernel.sol";
import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

// Stateful test actions assert effects through external fixtures over bounded collections.
// forge-lint: disable-start(calls-loop,unused-return,literal-instead-of-constant)

contract BurnerLoansYieldClaimerInvariantTest is StdInvariant, BurnerLoansYieldClaimerTest {
    uint256 internal constant _MAX_ASSET_COUNT = 8;

    function setUp() public override {
        super.setUp();
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = this.actionRegistry.selector;
        selectors[1] = this.actionSettings.selector;
        selectors[2] = this.actionCursor.selector;
        selectors[3] = this.actionLifecycle.selector;
        selectors[4] = this.actionExecute.selector;
        selectors[5] = this.actionUnauthorizedCursor.selector;
        targetContract(address(this));
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function actionRegistry(uint8 count_) external {
        uint256 count = bound(count_, 0, _MAX_ASSET_COUNT);
        address[] memory assets = new address[](count);
        for (uint256 i; i < count; ++i) {
            // Registry counts are bounded to eight, so every address conversion fits.
            // forge-lint: disable-next-line(unsafe-typecast)
            assets[i] = address(uint160(i + 1));
        }
        uint256 cursorBefore = claimer.nextAssetIndex();
        target.setAssets(assets);
        assertEq(claimer.nextAssetIndex(), cursorBefore, "registry edits preserve stored cursor");
    }

    function actionSettings(uint32 reserve_, uint32 threshold_, uint32 budget_) external {
        reserve_ = _boundUint32(reserve_, 100_000, 150_000);
        threshold_ = _boundUint32(threshold_, reserve_ + 1, 500_000);
        budget_ = _boundUint32(budget_, 1, 1_000_000);
        uint256 cursorBefore = claimer.nextAssetIndex();
        vm.startPrank(admin);
        // Raise the threshold first so either reserve direction is valid.
        claimer.setMinimumGasToAttempt(type(uint32).max);
        claimer.setGasReserve(reserve_);
        claimer.setMinimumGasToAttempt(threshold_);
        claimer.setExecutionGasLimit(budget_);
        vm.stopPrank();
        assertEq(claimer.nextAssetIndex(), cursorBefore, "gas settings preserve cursor");
    }

    function actionCursor(uint256 index_) external {
        uint256 count = target.getAssetCount();
        index_ = count == 0 ? 0 : bound(index_, 0, count - 1);
        vm.prank(admin);
        claimer.setNextAssetIndex(index_);
        assertEq(claimer.nextAssetIndex(), index_, "selected cursor matches input");
    }

    function actionLifecycle(bool active_, bool enabled_, bool targetEnabled_) external {
        uint256 cursorBefore = claimer.nextAssetIndex();
        bool activeBefore = kernel.isPolicyActive(Policy(address(claimer)));
        if (activeBefore != active_) {
            vm.prank(admin);
            kernel.executeAction(
                active_ ? Actions.ActivatePolicy : Actions.DeactivatePolicy,
                address(claimer)
            );
        }
        if (claimer.isEnabled() != enabled_) {
            vm.prank(enabled_ ? admin : _emergency);
            if (enabled_) claimer.enable("");
            else claimer.disable("");
        }
        if (targetEnabled_) target.enable("");
        else target.disable("");
        assertEq(claimer.nextAssetIndex(), cursorBefore, "lifecycle transitions preserve cursor");
    }

    function actionExecute() external {
        uint256 cursorBefore = claimer.nextAssetIndex();
        uint256 callsBefore = target.claimCalls();
        uint256 count = target.getAssetCount();
        bool shouldSkip = !kernel.isPolicyActive(Policy(address(claimer))) ||
            !claimer.isEnabled() ||
            !target.isEnabled() ||
            count == 0;

        vm.recordLogs();
        vm.prank(heart);
        claimer.execute();

        uint256 claimed = target.claimCalls() - callsBefore;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 failed;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(claimer) &&
                logs[i].topics[0] == IBurnerLoansYieldClaimer.YieldAssetClaimFailed.selector
            ) ++failed;
        }
        uint256 attempted = claimed + failed;
        assertLe(attempted, count, "one beat attempts at most the live asset count");
        if (shouldSkip || attempted == 0) {
            assertEq(attempted, 0, "skipped execution attempts no claims");
            assertEq(
                claimer.nextAssetIndex(),
                cursorBefore,
                "skipped or rolled-back execution preserves cursor"
            );
            return;
        }
        uint256 start = cursorBefore % count;
        if (failed == 0) {
            for (uint256 i; i < claimed; ++i) {
                assertEq(
                    target.claimedAssets(callsBefore + i),
                    target.getAssetAt((start + i) % count),
                    "successful claims follow circular registry order"
                );
            }
        }
        assertEq(
            claimer.nextAssetIndex(),
            (start + attempted) % count,
            "cursor follows every isolated attempt"
        );
    }

    function actionUnauthorizedCursor(address caller_, uint256 index_) external {
        if (caller_ == admin || caller_ == burnerLoansAdmin) return;
        uint256 cursorBefore = claimer.nextAssetIndex();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        claimer.setNextAssetIndex(index_);
        assertEq(
            claimer.nextAssetIndex(),
            cursorBefore,
            "unauthorized caller cannot change cursor"
        );
    }

    function invariant_gasSettingsRemainValid() public view {
        assertGt(claimer.executionGasLimit(), 0, "complete task budget is nonzero");
        assertGe(claimer.gasReserve(), 100_000, "cleanup reserve meets minimum");
        assertGt(
            claimer.minimumGasToAttempt(),
            claimer.gasReserve(),
            "attempt threshold exceeds reserve"
        );
    }

    function afterInvariant() public {
        uint256 count = target.getAssetCount();
        uint256 callsBefore = target.claimCalls();
        vm.startPrank(admin);
        if (!kernel.isPolicyActive(Policy(address(claimer)))) {
            kernel.executeAction(Actions.ActivatePolicy, address(claimer));
        }
        if (!claimer.isEnabled()) claimer.enable("");
        claimer.setMinimumGasToAttempt(250_000);
        claimer.setGasReserve(100_000);
        claimer.setExecutionGasLimit(2_000_000);
        vm.stopPrank();
        target.enable("");
        vm.prank(heart);
        claimer.execute();
        assertEq(
            target.claimCalls() - callsBefore,
            count,
            "recovered lifecycle and budget reach every live asset"
        );
        if (count > 0) assertLt(claimer.nextAssetIndex(), count, "recovered cursor is normalized");
    }
}

// forge-lint: disable-end(calls-loop,unused-return,literal-instead-of-constant)
