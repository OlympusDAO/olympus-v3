// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

// The literals are scenario amounts and the arguments of the registration calls.
// The loops run over recorded logs and over the gas probes of one call.
// The probes call the facility with an explicit gas amount, capture the short error data of
// protocol contracts, and read the error words in assembly.
// The token calls target WETH and the fixture, whose transfers revert on failure.
// The literal flags are the `sellShares` and `setAsBackingVault` arguments of `addAsset`.
// The setup steps assert their effects directly, so return values are unused.
// forge-lint: disable-start(literal-instead-of-constant,calls-loop,low-level-calls,return-bomb,inline-assembly,erc20-unchecked-transfer,boolean-cst,unsafe-typecast,unused-return)

import {YieldRepurchaseFacilityV2ForkTestBase} from "./YieldRepurchaseFacilityV2ForkTestBase.sol";
import {MockGasBurnerVault} from "./mocks/MockYRFGasBurnerVault.sol";

import {console2} from "@forge-std-1.16.2/console2.sol";
import {StdStorage, stdStorage} from "@forge-std-1.16.2/StdStorage.sol";
import {Vm} from "@forge-std-1.16.2/Vm.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2Write} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Write.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Constants.sol";

import {Actions} from "src/Kernel.sol";
import {YieldRepurchaseFacilityV2} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2.sol";
import {YieldRepurchaseFacilityV2Config} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Config.sol";
import {ERC20 as SolmateERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

/// @title YieldRepurchaseFacilityV2ForkTests_StepGasLimit
/// @notice Mainnet-fork tests of the gas limit of the isolated steps of the YRF v2.
///         A vault fixture that consumes all the gas it is handed wraps WETH, which the PRICE
///         module prices on the pinned block, and is registered next to the sUSDS and sUSDe
///         assets of the base setup.
/// @dev The tests drive `execute` directly with the heart role and without a time warp, so the
///      live feeds of the pinned block stay fresh and the mirror model of the base is not used.
contract YieldRepurchaseFacilityV2ForkTests_StepGasLimit is YieldRepurchaseFacilityV2ForkTestBase {
    using stdStorage for StdStorage;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @notice One whole WETH, and one whole share of the 18-decimal fixture.
    uint256 internal constant ONE = 1e18;

    /// @notice The margin the facility requires on top of the forwarded and the kept-back gas.
    uint256 internal constant MARGIN = YieldRepurchaseFacilityV2Constants.STEP_GAS_MARGIN;

    /// @notice The gas the calling frame keeps back when it forwards the step gas limit.
    // 2_000_000 / 63 = 31_746 (floor).
    uint256 internal constant RETAINED_GAS =
        STEP_GAS_LIMIT / YieldRepurchaseFacilityV2Constants.STEP_GAS_RETENTION_DIVISOR;

    /// @notice The gas the facility requires before a step at the step gas limit of the setup.
    // 2_000_000 + 31_746 + 15_000 = 2_046_746.
    uint256 internal constant REQUIRED_GAS = STEP_GAS_LIMIT + RETAINED_GAS + MARGIN;

    MockGasBurnerVault internal burner;

    function setUp() public override {
        super.setUp();
        vm.label(WETH, "WETH");

        burner = new MockGasBurnerVault(SolmateERC20(WETH), 18);
        vm.label(address(burner), "GasBurnerVault");
    }

    // ============ HELPERS ============ //

    /// @notice Registers the fixture through the config policy as the admin, with zero snapshots
    ///         and a zero next yield.
    /// @param beforeSusde_ When set, the sUSDe asset is removed and registered again after the
    ///        fixture, so the vault order becomes sUSDS, fixture, sUSDe; otherwise the fixture
    ///        is the last vault.
    function _registerBurner(bool beforeSusde_) internal {
        _registerBurner(beforeSusde_, 0);
    }

    /// @notice Registers the fixture through the config policy as the admin, with zero snapshots.
    /// @param beforeSusde_ When set, the sUSDe asset is removed and registered again after the
    ///        fixture, so the vault order becomes sUSDS, fixture, sUSDe; otherwise the fixture
    ///        is the last vault.
    /// @param nextYield_ The stored next yield of the fixture: the funding target of its first
    ///        weekly reset, in WETH units.
    function _registerBurner(bool beforeSusde_, uint256 nextYield_) internal {
        vm.startPrank(TIMELOCK);
        if (beforeSusde_) {
            yieldRepoConfig.disableAsset(SUSDE);
            yieldRepoConfig.removeAsset(SUSDE);
        }
        yieldRepoConfig.addAsset(_burnerParams(nextYield_));
        if (beforeSusde_) {
            yieldRepoConfig.addAsset(
                IYieldRepurchaseFacilityV2.AddAssetParams({
                    vault: SUSDE,
                    yieldBuybackShare: SUSDE_BUYBACK_SHARE,
                    initialReserveBalance: susdeSeedBalance,
                    initialConversionRate: susdeSeedRate,
                    nextYield: susdeSeedYield,
                    sellShares: true,
                    setAsBackingVault: false
                })
            );
        }
        vm.stopPrank();
    }

    /// @notice The registration inputs of the fixture: a full buyback share, zero snapshots
    ///         except a one-to-one conversion rate, the reserve mode, and no designation.
    function _burnerParams(
        uint256 nextYield_
    ) internal view returns (IYieldRepurchaseFacilityV2.AddAssetParams memory params) {
        return
            IYieldRepurchaseFacilityV2.AddAssetParams({
                vault: address(burner),
                yieldBuybackShare: 1e18,
                initialReserveBalance: 0,
                initialConversionRate: ONE,
                nextYield: nextYield_,
                sellShares: false,
                setAsBackingVault: false
            });
    }

    /// @notice Deposits WETH into the fixture for `receiver_`.
    function _mintBurnerShares(address receiver_, uint256 amount_) internal {
        deal(WETH, address(this), amount_);
        IERC20(WETH).approve(address(burner), amount_);
        burner.deposit(amount_, receiver_);
    }

    function _disableFacility() internal {
        vm.prank(TIMELOCK);
        yieldRepo.disable("");
    }

    /// @notice Calls `target_` as `caller_` with exactly `gas_` gas.
    /// @return success Whether the call succeeded.
    /// @return required The required gas reported by the step gas error of a failed call.
    /// @return available The available gas reported by the step gas error of a failed call.
    function _probe(
        address target_,
        address caller_,
        bytes memory callData_,
        uint256 gas_
    ) internal returns (bool success, uint256 required, uint256 available) {
        vm.prank(caller_);
        bytes memory returned;
        (success, returned) = target_.call{gas: gas_}(callData_);
        if (success) return (true, 0, 0);

        assertEq(
            bytes4(returned),
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_InsufficientStepGas.selector,
            "the call reverts with the step gas error"
        );
        // The error data is the selector followed by the two words
        assembly {
            required := mload(add(returned, 0x24))
            available := mload(add(returned, 0x44))
        }
    }

    /// @notice Returns the smallest gas amount of a facility call with which the gas check of
    ///         the step `stepIndex_` (zero-based, in execution order) passes.
    /// @dev The gas a call holds at a check grows one for one with the gas of the call, so
    ///      adding the reported shortfall of a failed check makes that check pass exactly, and
    ///      the following probe fails at the next check.
    function _gasForStep(
        address caller_,
        bytes memory callData_,
        uint256 stepIndex_
    ) internal returns (uint256 gas_) {
        // Below the requirement of any step, so the first probe fails at the first check
        gas_ = STEP_GAS_LIMIT;
        for (uint256 i; i <= stepIndex_; ++i) {
            (bool success, uint256 required, uint256 available) = _probe(
                address(yieldRepo),
                caller_,
                callData_,
                gas_
            );
            assertFalse(success, "a probe below the threshold fails");
            gas_ += required - available;
        }
    }

    /// @notice Returns whether the logs hold the facility event `topic0_` whose first indexed
    ///         argument is the vault, and the data of the first such event.
    function _findVaultEvent(
        Vm.Log[] memory logs_,
        bytes32 topic0_,
        address vault_
    ) internal view returns (bool found, bytes memory data) {
        for (uint256 i; i < logs_.length; ++i) {
            if (
                logs_[i].emitter == address(yieldRepo) &&
                logs_[i].topics[0] == topic0_ &&
                address(uint160(uint256(logs_[i].topics[1]))) == vault_
            ) return (true, logs_[i].data);
        }
    }

    function _hasVaultEvent(
        Vm.Log[] memory logs_,
        bytes32 topic0_,
        address vault_
    ) internal view returns (bool found) {
        (found, ) = _findVaultEvent(logs_, topic0_, vault_);
    }

    /// @notice Asserts that the logs hold the skip event `topic0_` of the vault with an empty
    ///         reason, the shape of a step that ran out of gas.
    function _assertSkippedOutOfGas(
        Vm.Log[] memory logs_,
        bytes32 topic0_,
        address vault_,
        string memory label_
    ) internal view {
        (bool found, bytes memory data) = _findVaultEvent(logs_, topic0_, vault_);
        assertTrue(found, string.concat(label_, ": skip event"));
        assertEq(abi.decode(data, (bytes)).length, 0, string.concat(label_, ": empty reason"));
    }

    // ============ ISOLATION OF A GAS-BURNING VAULT ============ //

    function test_execute_gasBurningVault_losesOnlyItsSteps() public {
        // The vault order is sUSDS, fixture, sUSDe: a healthy vault follows the fixture in both
        // the weekly and the daily loop
        _registerBurner(true);
        burner.setConvertMode(MockGasBurnerVault.FailMode.BurnGas);

        vm.recordLogs();
        vm.prank(HEART);
        yieldRepo.execute();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // The fixture loses its weekly reset and its daily cycle
        _assertSkippedOutOfGas(
            logs,
            IYieldRepurchaseFacilityV2.WeeklyResetSkipped.selector,
            address(burner),
            "fixture weekly reset"
        );
        _assertSkippedOutOfGas(
            logs,
            IYieldRepurchaseFacilityV2.DailyCycleSkipped.selector,
            address(burner),
            "fixture daily cycle"
        );

        // The other vaults are not skipped and open their markets, which requires both their
        // weekly funding and their daily cycle
        address[2] memory healthy = [SUSDS, SUSDE];
        for (uint256 i; i < healthy.length; ++i) {
            assertFalse(
                _hasVaultEvent(
                    logs,
                    IYieldRepurchaseFacilityV2.WeeklyResetSkipped.selector,
                    healthy[i]
                ),
                "healthy vault: weekly reset not skipped"
            );
            assertFalse(
                _hasVaultEvent(
                    logs,
                    IYieldRepurchaseFacilityV2.DailyCycleSkipped.selector,
                    healthy[i]
                ),
                "healthy vault: daily cycle not skipped"
            );
            assertTrue(
                _hasVaultEvent(logs, IYieldRepurchaseFacilityV2.RepoMarket.selector, healthy[i]),
                "healthy vault: market created"
            );
        }

        // The restart epoch 20 advanced to 21, which the weekly reset wraps to zero
        assertEq(yieldRepo.epoch(), 0, "epoch advanced");
    }

    // ============ STEP GAS ON THE LIVE PRICE FEEDS ============ //

    /// @notice Writes the step gas limit to storage directly, below the bounds of the setter.
    function _writeStepGasLimit(uint256 limit_) internal {
        stdstore
            .enable_packed_slots()
            .target(address(yieldRepo))
            .sig("stepGasLimit()")
            .checked_write(limit_);
    }

    /// @notice Runs the next `execute` beat with the step gas limit `limit_` on a state
    ///         snapshot and returns a hash of the events the facility emitted.
    /// @param vault_ When zero, the hash covers the topics and the data of every event. When
    ///        non-zero, it covers the kinds of the events whose first indexed argument is the
    ///        vault (its market, and its skip and failure events), without their data: the
    ///        market id of a vault depends on the markets of the vaults before it.
    function _beatFingerprint(
        uint256 limit_,
        address vault_
    ) internal returns (bytes32 fingerprint) {
        uint256 snapshotId = vm.snapshotState();

        _writeStepGasLimit(limit_);
        vm.recordLogs();
        vm.prank(HEART);
        yieldRepo.execute();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(yieldRepo)) continue;
            if (vault_ == address(0)) {
                fingerprint = keccak256(abi.encode(fingerprint, logs[i].topics, logs[i].data));
            } else if (
                logs[i].topics.length > 1 && address(uint160(uint256(logs[i].topics[1]))) == vault_
            ) {
                fingerprint = keccak256(abi.encode(fingerprint, logs[i].topics[0]));
            }
        }

        assertTrue(vm.revertToStateAndDelete(snapshotId), "snapshot revert failed");
    }

    /// @notice Returns the smallest step gas limit, to a resolution of 1_000 gas, with which the
    ///         next `execute` beat emits the same facility events as with the upper bound of
    ///         the limit.
    /// @dev A step that is short of gas changes the events: a skip event replaces its effects,
    ///      or a failure event of a nested call (the wrap, the redeem, the close or the
    ///      creation of a market) replaces a market.
    function _minimalStepGasLimit(address vault_) internal returns (uint256 limit_) {
        bytes32 expected = _beatFingerprint(
            YieldRepurchaseFacilityV2Constants.MAX_STEP_GAS_LIMIT,
            vault_
        );
        assertTrue(_beatFingerprint(0, vault_) != expected, "a zero limit changes the events");

        uint256 low;
        limit_ = YieldRepurchaseFacilityV2Constants.MAX_STEP_GAS_LIMIT;
        while (limit_ - low > 1_000) {
            uint256 middle = (low + limit_) / 2;
            if (_beatFingerprint(middle, vault_) == expected) limit_ = middle;
            else low = middle;
        }
    }

    /// @notice Runs one `execute` beat of the facility and returns its logs.
    function _executeAndRecord() internal returns (Vm.Log[] memory logs) {
        vm.recordLogs();
        vm.prank(HEART);
        yieldRepo.execute();
        return vm.getRecordedLogs();
    }

    /// @notice Returns the market the facility created for the vault, read from `RepoMarket`.
    function _createdMarket(
        Vm.Log[] memory logs_,
        address vault_
    ) internal view returns (uint256 marketId) {
        for (uint256 i; i < logs_.length; ++i) {
            if (
                logs_[i].emitter == address(yieldRepo) &&
                logs_[i].topics[0] == IYieldRepurchaseFacilityV2.RepoMarket.selector &&
                address(uint160(uint256(logs_[i].topics[1]))) == vault_
            ) return uint256(logs_[i].topics[2]);
        }
        assertTrue(false, "market not created");
    }

    /// @notice Buys half of the amount the market accepts, with freshly minted OHM.
    function _purchase(uint256 marketId_) internal {
        uint256 amountIn = auctioneer.maxAmountAccepted(marketId_, address(0)) / 2;

        vm.prank(MINTR_MODULE);
        ohm.mint(buyer, amountIn);

        vm.startPrank(buyer);
        ohm.approve(BOND_TELLER, amountIn);
        teller.purchase(buyer, address(0), marketId_, amountIn, 0);
        vm.stopPrank();
    }

    /// @notice Asserts that the beat skipped no step, failed no nested call, and created a
    ///         market for both vaults.
    function _assertCleanBeat(Vm.Log[] memory logs_) internal view {
        bytes32[7] memory failures = [
            IYieldRepurchaseFacilityV2.WeeklyResetSkipped.selector,
            IYieldRepurchaseFacilityV2.DailyCycleSkipped.selector,
            IYieldRepurchaseFacilityV2.OhmPurchasesProcessingSkipped.selector,
            IYieldRepurchaseFacilityV2.RedeemFailed.selector,
            IYieldRepurchaseFacilityV2.ReserveWrapFailed.selector,
            IYieldRepurchaseFacilityV2.MarketCloseFailed.selector,
            IYieldRepurchaseFacilityV2.MarketCreationFailed.selector
        ];
        for (uint256 i; i < logs_.length; ++i) {
            if (logs_[i].emitter != address(yieldRepo)) continue;
            for (uint256 j; j < failures.length; ++j) {
                assertTrue(logs_[i].topics[0] != failures[j], "no skip or failure event");
            }
        }
        _createdMarket(logs_, SUSDS);
        _createdMarket(logs_, SUSDE);
    }

    function test_stepGas_liveFeeds_firstBeat() public {
        // Without the feed mocks of the base the PRICE module resolves the OHM price through
        // its live feeds, which the daily cycle of each vault pays for inside its step. The
        // beat is the first after the restart: the weekly resets, and daily cycles that have
        // no market to close, no purchased OHM to burn, and no idle reserve to wrap.
        vm.clearMockedCalls();

        console2.log("first beat: minimal limit, sUSDS", _minimalStepGasLimit(SUSDS));
        console2.log("first beat: minimal limit, sUSDe", _minimalStepGasLimit(SUSDE));
        uint256 minimalLimit = _minimalStepGasLimit(address(0));
        console2.log("first beat: minimal limit, whole beat", minimalLimit);

        // The step gas limit of the setup covers the beat
        assertLe(minimalLimit, STEP_GAS_LIMIT, "the setup limit covers the beat");
        _assertCleanBeat(_executeAndRecord());
        assertEq(yieldRepo.epoch(), 0, "epoch advanced");
    }

    function test_stepGas_liveFeeds_costliestDailyCycle() public {
        vm.clearMockedCalls();

        // The first beat opens a market per vault
        Vm.Log[] memory logs = _executeAndRecord();
        uint256 susdsMarket = _createdMarket(logs, SUSDS);
        uint256 susdeMarket = _createdMarket(logs, SUSDE);

        // Purchases on both markets leave OHM to burn, and a delivery of the underlying
        // leaves the sUSDe asset an idle reserve to wrap
        _purchase(susdsMarket);
        _purchase(susdeMarket);
        deal(USDE, address(yieldRepo), 1_000e18);
        assertGt(yieldRepo.ohmPurchased(), 0, "OHM purchased");

        // Two beats without a daily cycle; the third runs the costliest paths: the burn of
        // the purchased OHM against a treasury withdrawal, and per vault the close of the
        // live market, the redeem (sUSDS) or the wrap (sUSDe), and a market
        vm.startPrank(HEART);
        yieldRepo.execute();
        yieldRepo.execute();
        vm.stopPrank();

        console2.log("costliest daily cycle: minimal limit, sUSDS", _minimalStepGasLimit(SUSDS));
        console2.log("costliest daily cycle: minimal limit, sUSDe", _minimalStepGasLimit(SUSDE));
        uint256 minimalLimit = _minimalStepGasLimit(address(0));
        console2.log("costliest daily cycle: minimal limit, whole beat", minimalLimit);

        // The step gas limit of the setup covers the beat
        assertLe(minimalLimit, STEP_GAS_LIMIT, "the setup limit covers the beat");

        logs = _executeAndRecord();
        _assertCleanBeat(logs);
        // The costliest paths ran
        assertEq(yieldRepo.ohmPurchased(), 0, "purchased OHM burned");
        assertEq(usde.balanceOf(address(yieldRepo)), 0, "idle USDe wrapped");
        assertFalse(auctioneer.isLive(susdsMarket), "previous sUSDS market closed");
        assertFalse(auctioneer.isLive(susdeMarket), "previous sUSDe market closed");
    }

    function test_stepGas_liveFeeds_costliestDailyCycle_coldBondContracts() public {
        vm.clearMockedCalls();

        // The first beat opens a market per vault
        Vm.Log[] memory logs = _executeAndRecord();
        uint256 susdeMarket = _createdMarket(logs, SUSDE);

        // The sUSDS pool is emptied, so its daily cycle sizes a zero bid and returns before
        // it reaches the bond contracts: the sUSDe cycle is the first to access them in the
        // beat. A delivery of the underlying leaves the sUSDe asset an idle reserve to wrap.
        uint256 susdsPool = susds.balanceOf(address(yieldRepo));
        uint256 usdsPool = usds.balanceOf(address(yieldRepo));
        vm.startPrank(address(yieldRepo));
        susds.transfer(address(treasury), susdsPool);
        usds.transfer(address(treasury), usdsPool);
        vm.stopPrank();
        deal(USDE, address(yieldRepo), 1_000e18);

        vm.startPrank(HEART);
        yieldRepo.execute();
        yieldRepo.execute();
        vm.stopPrank();

        uint256 minimalLimit = _minimalStepGasLimit(SUSDE);
        console2.log("cold bond contracts: minimal limit, sUSDe", minimalLimit);

        // The step gas limit of the setup covers the cycle
        assertLe(minimalLimit, STEP_GAS_LIMIT, "the setup limit covers the cycle");

        logs = _executeAndRecord();
        _createdMarket(logs, SUSDE);
        assertFalse(
            _hasVaultEvent(logs, IYieldRepurchaseFacilityV2.RepoMarket.selector, SUSDS),
            "no sUSDS market"
        );
        assertEq(usde.balanceOf(address(yieldRepo)), 0, "idle USDe wrapped");
        assertFalse(auctioneer.isLive(susdeMarket), "previous sUSDe market closed");
    }

    function test_stepGas_liveFeeds_heartBeat() public {
        // The beat runs through the Heart on the live feeds of the pinned block: the tasks
        // before the facility read the PRICE module first
        vm.clearMockedCalls();
        vm.prank(TIMELOCK);
        heart.resetBeat();
        bytes memory callData = abi.encodeCall(heart.beat, ());

        // The smallest gas of the call with which the beat succeeds, to a resolution of 1_000
        uint256 low;
        uint256 minimalGas = 30_000_000;
        while (minimalGas - low > 1_000) {
            uint256 middle = (low + minimalGas) / 2;
            uint256 snapshotId = vm.snapshotState();
            vm.prank(keeper);
            (bool success, ) = address(heart).call{gas: middle}(callData);
            assertTrue(vm.revertToStateAndDelete(snapshotId), "snapshot revert failed");
            if (success) minimalGas = middle;
            else low = middle;
        }

        vm.recordLogs();
        vm.prank(keeper);
        heart.beat();
        uint256 gasUsed = vm.lastCallGas().gasTotalUsed;
        Vm.Log[] memory logs = vm.getRecordedLogs();

        console2.log("heart beat: gas used", gasUsed);
        console2.log("heart beat: minimal gas of the call", minimalGas);

        _assertCleanBeat(logs);
        assertEq(yieldRepo.epoch(), 0, "epoch advanced");
        // The beat needs more gas than it uses: the last step requires its whole limit
        assertGt(minimalGas, gasUsed, "the beat requires more gas than it uses");
    }

    // ============ SHORTAGE OF GAS OF THE CALLER ============ //

    function test_execute_reverts_whenGasDoesNotCoverNextStep() public {
        bytes memory callData = abi.encodeCall(IPeriodicTask.execute, ());

        // Exactly enough gas for the first step, the weekly reset of sUSDS
        uint256 gas_ = _gasForStep(HEART, callData, 0);

        // The sUSDS reset runs, and the check before the sUSDe reset fails
        (bool success, uint256 required, uint256 available) = _probe(
            address(yieldRepo),
            HEART,
            callData,
            gas_
        );
        assertFalse(success, "the beat reverts");
        // required = 2_000_000 + 2_000_000 / 63 + 15_000 = 2_046_746.
        assertEq(required, REQUIRED_GAS, "required gas");
        assertLt(available, required, "available gas below the requirement");

        // Nothing of the reverted beat persists: no epoch advance and no funding
        assertEq(yieldRepo.epoch(), RESTART_EPOCH, "epoch unchanged");
        assertTrue(yieldRepo.isCycleSeedable(), "seeding window unchanged");
        assertEq(susds.balanceOf(address(yieldRepo)), 0, "no sUSDS funding");
        assertEq(
            yieldRepo.getAssetConfig(SUSDS).nextYield,
            susdsSeedYield,
            "sUSDS next yield unchanged"
        );

        // The same beat succeeds with more gas
        vm.prank(HEART);
        yieldRepo.execute();
        assertEq(yieldRepo.epoch(), 0, "epoch advanced");
        assertGt(susds.balanceOf(address(yieldRepo)), 0, "sUSDS funded");
    }

    function test_heartBeat_reverts_whenGasDoesNotCoverStep() public {
        vm.warp(heart.lastBeat() + heart.frequency());
        _updateOracles();

        uint48 lastBeat = heart.lastBeat();
        bytes memory callData = abi.encodeCall(heart.beat, ());

        // The gas is raised in increments below the step requirement until the beat reaches the
        // facility: a smaller amount runs out in the tasks before it
        bool reachedFacility;
        uint256 required;
        for (uint256 gas_ = STEP_GAS_LIMIT; gas_ <= 10 * STEP_GAS_LIMIT; gas_ += 250_000) {
            vm.prank(keeper);
            (bool success, bytes memory returned) = address(heart).call{gas: gas_}(callData);
            assertFalse(success, "a beat short of gas reverts");
            if (
                bytes4(returned) !=
                IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_InsufficientStepGas.selector
            ) continue;

            assembly {
                required := mload(add(returned, 0x24))
            }
            reachedFacility = true;
            break;
        }

        // The Heart does not catch the error of the task, so the whole beat reverts with it
        assertTrue(reachedFacility, "the beat reverts with the step gas error");
        assertEq(required, REQUIRED_GAS, "required gas");
        assertEq(heart.lastBeat(), lastBeat, "last beat unchanged");
        assertEq(yieldRepo.epoch(), RESTART_EPOCH, "epoch unchanged");

        // The same beat succeeds with more gas
        vm.prank(keeper);
        heart.beat();
        assertEq(yieldRepo.epoch(), 0, "epoch advanced");
    }

    // ============ SWEEP ============ //

    function test_returnFundsToTreasury_gasBurningVault_losesOnlyItsSweep() public {
        // The vault order is sUSDS, fixture, sUSDe
        _registerBurner(true);
        _mintBurnerShares(address(yieldRepo), 5e18);
        deal(USDS, address(yieldRepo), 100e18);
        deal(USDE, address(yieldRepo), 200e18);
        burner.setTransferMode(MockGasBurnerVault.FailMode.BurnGas);
        _disableFacility();

        uint256 trsryUsds = usds.balanceOf(address(treasury));
        uint256 trsryUsde = usde.balanceOf(address(treasury));
        bytes memory callData = abi.encodeCall(
            IYieldRepurchaseFacilityV2Write.returnFundsToTreasury,
            ()
        );

        // A call whose gas does not cover the first sweep reverts and sweeps nothing
        (bool success, uint256 required, ) = _probe(
            address(yieldRepo),
            TIMELOCK,
            callData,
            STEP_GAS_LIMIT
        );
        assertFalse(success, "the sweep reverts");
        assertEq(required, REQUIRED_GAS, "required gas");
        assertEq(usds.balanceOf(address(yieldRepo)), 100e18, "USDS kept by the reverted sweep");

        vm.recordLogs();
        vm.prank(TIMELOCK);
        yieldRepo.returnFundsToTreasury();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // The fixture loses its sweep and keeps its balance
        _assertSkippedOutOfGas(
            logs,
            IYieldRepurchaseFacilityV2.FundsReturnSkipped.selector,
            address(burner),
            "fixture sweep"
        );
        assertEq(burner.balanceOf(address(yieldRepo)), 5e18, "fixture shares kept");

        // The vaults before and after the fixture are swept
        assertFalse(
            _hasVaultEvent(logs, IYieldRepurchaseFacilityV2.FundsReturnSkipped.selector, SUSDS),
            "sUSDS sweep not skipped"
        );
        assertFalse(
            _hasVaultEvent(logs, IYieldRepurchaseFacilityV2.FundsReturnSkipped.selector, SUSDE),
            "sUSDe sweep not skipped"
        );
        assertEq(usds.balanceOf(address(yieldRepo)), 0, "USDS swept");
        assertEq(usde.balanceOf(address(yieldRepo)), 0, "USDe swept");
        assertEq(usds.balanceOf(address(treasury)), trsryUsds + 100e18, "USDS in the treasury");
        assertEq(usde.balanceOf(address(treasury)), trsryUsde + 200e18, "USDe in the treasury");
    }

    function test_returnFundsToTreasury_beforeFirstEnable() public {
        // A second facility with its own config policy, activated and never enabled
        YieldRepurchaseFacilityV2Config config = new YieldRepurchaseFacilityV2Config(
            kernel,
            GRACE_PERIOD
        );
        vm.label(address(config), "YieldRepoV2ConfigFresh");
        YieldRepurchaseFacilityV2 facility = new YieldRepurchaseFacilityV2(
            kernel,
            OHM,
            address(backingOracle),
            BOND_AUCTIONEER,
            GRACE_PERIOD,
            STEP_GAS_LIMIT
        );
        vm.label(address(facility), "YieldRepoV2Fresh");

        vm.startPrank(DAO_MS);
        kernel.executeAction(Actions.ActivatePolicy, address(config));
        kernel.executeAction(Actions.ActivatePolicy, address(facility));
        vm.stopPrank();

        vm.startPrank(TIMELOCK);
        config.setFacility(address(facility));
        facility.setConfigurator(address(config));
        config.enable("");
        config.addAsset(_burnerParams(0));
        vm.stopPrank();

        assertFalse(facility.isEnabled(), "never enabled");
        // The limit is set by the constructor
        assertEq(facility.stepGasLimit(), STEP_GAS_LIMIT, "step gas limit");

        _mintBurnerShares(address(facility), 5e18);
        uint256 trsryShares = burner.balanceOf(address(treasury));
        bytes memory callData = abi.encodeCall(
            IYieldRepurchaseFacilityV2Write.returnFundsToTreasury,
            ()
        );

        // A call whose gas does not cover the sweep reverts
        (bool success, uint256 required, ) = _probe(
            address(facility),
            TIMELOCK,
            callData,
            STEP_GAS_LIMIT
        );
        assertFalse(success, "the sweep reverts");
        // required = 2_000_000 + 2_000_000 / 63 + 15_000 = 2_046_746.
        assertEq(required, REQUIRED_GAS, "required gas");

        // A vault that consumes its gas limit is skipped
        burner.setTransferMode(MockGasBurnerVault.FailMode.BurnGas);
        vm.expectEmit(address(facility));
        emit IYieldRepurchaseFacilityV2.FundsReturnSkipped(address(burner), "");
        vm.prank(TIMELOCK);
        facility.returnFundsToTreasury();
        assertEq(burner.balanceOf(address(facility)), 5e18, "shares kept");

        // A healthy vault is swept
        burner.setTransferMode(MockGasBurnerVault.FailMode.None);
        vm.prank(TIMELOCK);
        facility.returnFundsToTreasury();
        assertEq(burner.balanceOf(address(facility)), 0, "shares swept");
        assertEq(burner.balanceOf(address(treasury)), trsryShares + 5e18, "shares in the treasury");
    }

    // ============ SETTER AND CONSTRUCTOR ============ //

    function test_setStepGasLimit_rolesAndBounds() public {
        uint32 minLimit = YieldRepurchaseFacilityV2Constants.MIN_STEP_GAS_LIMIT;
        uint32 maxLimit = YieldRepurchaseFacilityV2Constants.MAX_STEP_GAS_LIMIT;
        assertEq(minLimit, 1_100_000, "lower bound");
        assertEq(maxLimit, 5_000_000, "upper bound");
        assertEq(yieldRepo.stepGasLimit(), STEP_GAS_LIMIT, "initial limit");

        // The yrf_admin sets the upper bound
        vm.expectEmit(address(yieldRepo));
        emit IYieldRepurchaseFacilityV2.StepGasLimitSet(maxLimit);
        vm.prank(yrfAdmin);
        yieldRepo.setStepGasLimit(maxLimit);
        assertEq(yieldRepo.stepGasLimit(), maxLimit, "limit set by the yrf_admin");

        // The limit applies to the next step.
        // required = 5_000_000 + 5_000_000 / 63 + 15_000 = 5_094_365.
        (bool success, uint256 required, ) = _probe(
            address(yieldRepo),
            HEART,
            abi.encodeCall(IPeriodicTask.execute, ()),
            STEP_GAS_LIMIT
        );
        assertFalse(success, "the beat reverts");
        assertEq(required, 5_000_000 + 79_365 + MARGIN, "required gas at the upper bound");

        // The admin sets the lower bound
        vm.expectEmit(address(yieldRepo));
        emit IYieldRepurchaseFacilityV2.StepGasLimitSet(minLimit);
        vm.prank(TIMELOCK);
        yieldRepo.setStepGasLimit(minLimit);
        assertEq(yieldRepo.stepGasLimit(), minLimit, "limit set by the admin");

        // The values outside the bounds are rejected
        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_StepGasLimitOutOfBounds.selector
        );
        vm.prank(yrfAdmin);
        yieldRepo.setStepGasLimit(minLimit - 1);

        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_StepGasLimitOutOfBounds.selector
        );
        vm.prank(yrfAdmin);
        yieldRepo.setStepGasLimit(maxLimit + 1);

        // Any other caller is rejected, the heart and the emergency role holder included
        address[3] memory others = [makeAddr("stranger"), HEART, EMERGENCY_MS];
        for (uint256 i; i < others.length; ++i) {
            vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
            vm.prank(others[i]);
            yieldRepo.setStepGasLimit(maxLimit);
        }

        // The setter does not depend on the enabled state
        _disableFacility();
        vm.prank(yrfAdmin);
        yieldRepo.setStepGasLimit(maxLimit);
        assertEq(yieldRepo.stepGasLimit(), maxLimit, "limit set while disabled");
    }

    function test_constructor_reverts_whenStepGasLimitOutOfBounds() public {
        uint32 minLimit = YieldRepurchaseFacilityV2Constants.MIN_STEP_GAS_LIMIT;
        uint32 maxLimit = YieldRepurchaseFacilityV2Constants.MAX_STEP_GAS_LIMIT;

        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_StepGasLimitOutOfBounds.selector
        );
        new YieldRepurchaseFacilityV2(
            kernel,
            OHM,
            address(backingOracle),
            BOND_AUCTIONEER,
            GRACE_PERIOD,
            minLimit - 1
        );

        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_StepGasLimitOutOfBounds.selector
        );
        new YieldRepurchaseFacilityV2(
            kernel,
            OHM,
            address(backingOracle),
            BOND_AUCTIONEER,
            GRACE_PERIOD,
            maxLimit + 1
        );

        // The bounds themselves are accepted
        YieldRepurchaseFacilityV2 facility = new YieldRepurchaseFacilityV2(
            kernel,
            OHM,
            address(backingOracle),
            BOND_AUCTIONEER,
            GRACE_PERIOD,
            maxLimit
        );
        vm.label(address(facility), "YieldRepoV2AtUpperBound");
        assertEq(facility.stepGasLimit(), maxLimit, "limit at the upper bound");
    }

    // ============ MARGIN ============ //

    function test_margin_execute_reachesNextCheck_afterStepOutOfGas() public {
        // The vault order is sUSDS, fixture, sUSDe. The weekly reset of the fixture, the
        // second step of the beat, runs out of gas in the frame of the step, so it consumes
        // its whole limit: the fixture carries a next yield, so the step sizes the treasury
        // withdrawal with a `previewWithdraw` it calls directly, and the revert data of that
        // call runs the step out of gas. (The projection before it reaches the vault through
        // the yield library, whose frame would absorb a bomb instead.) The advance to the
        // following check then reads the next vault and its enabled flag from storage slots
        // the beat has not touched.
        _registerBurner(true, 1);
        burner.setWithdrawMode(MockGasBurnerVault.FailMode.RevertBomb);
        bytes memory callData = abi.encodeCall(IPeriodicTask.execute, ());

        uint256 gas_ = _gasForStep(HEART, callData, 1);

        // One gas unit less fails the check of the fixture's step by exactly one unit, so
        // `gas_` is the exact threshold of that check
        (bool success, uint256 required, uint256 available) = _probe(
            address(yieldRepo),
            HEART,
            callData,
            gas_ - 1
        );
        assertFalse(success, "below the threshold: the beat reverts");
        assertEq(available, required - 1, "below the threshold: one unit short");

        // At the threshold the fixture's step is handed its full limit and consumes it. The
        // beat then reverts at the check of the following step, not by running out of gas:
        // the skip event and the advance to that check fit into the gas left to the caller.
        (success, required, available) = _probe(address(yieldRepo), HEART, callData, gas_);
        assertFalse(success, "at the threshold: the beat reverts at the next check");
        assertEq(required, REQUIRED_GAS, "required gas");

        // The check held REQUIRED_GAS = limit + limit / 63 + margin, and the step consumed the
        // limit, so the next check holds limit / 63 + margin - spent, where `spent` is the gas
        // between the first check and its call plus the gas between the return of the call and
        // the next check.
        // spent = 2_000_000 / 63 + 15_000 - available = 46_746 - available.
        uint256 spent = RETAINED_GAS + MARGIN - available;
        console2.log("execute, step out of gas: gas spent around the step", spent);
        console2.log("execute, step out of gas: gas left at the next check", available);

        // The margin alone covers the spent gas, without the gas the caller keeps back
        assertLe(spent, MARGIN, "the margin covers the gas spent around the step");
    }

    function test_margin_returnFundsToTreasury_emitsSkip_afterLastStepOutOfGas() public {
        // The fixture is the last vault, and its sweep runs out of gas in the frame of the
        // step, so it consumes its whole limit
        _registerBurner(false);
        _mintBurnerShares(address(yieldRepo), 5e18);
        burner.setTransferMode(MockGasBurnerVault.FailMode.RevertBomb);
        _disableFacility();
        bytes memory callData = abi.encodeCall(
            IYieldRepurchaseFacilityV2Write.returnFundsToTreasury,
            ()
        );

        // The exact threshold of the check of the last sweep (sUSDS, sUSDe, fixture)
        uint256 gas_ = _gasForStep(TIMELOCK, callData, 2);

        (bool success, uint256 required, uint256 available) = _probe(
            address(yieldRepo),
            TIMELOCK,
            callData,
            gas_ - 1
        );
        assertFalse(success, "below the threshold: the sweep reverts");
        assertEq(available, required - 1, "below the threshold: one unit short");

        // At the threshold the sweep of the fixture is handed its full limit and consumes it,
        // and the call still completes: the skip event and the closing event are emitted
        vm.recordLogs();
        (success, , ) = _probe(address(yieldRepo), TIMELOCK, callData, gas_);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(success, "at the threshold: the sweep completes");
        _assertSkippedOutOfGas(
            logs,
            IYieldRepurchaseFacilityV2.FundsReturnSkipped.selector,
            address(burner),
            "fixture sweep"
        );
        bool closingEvent;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(yieldRepo) &&
                logs[i].topics[0] == IYieldRepurchaseFacilityV2.FundsReturnedToTreasury.selector
            ) closingEvent = true;
        }
        assertTrue(closingEvent, "closing event");
        assertEq(burner.balanceOf(address(yieldRepo)), 5e18, "fixture shares kept");
    }

    function test_margin_execute_longRevertData() public {
        // The fixture reverts its weekly reset with more data than the facility captures, so
        // the skip event carries the largest reason, 256 bytes
        _registerBurner(true);
        burner.setConvertMode(MockGasBurnerVault.FailMode.RevertLong);
        bytes memory callData = abi.encodeCall(IPeriodicTask.execute, ());

        uint256 gas_ = _gasForStep(HEART, callData, 1);
        (bool success, uint256 required, uint256 available) = _probe(
            address(yieldRepo),
            HEART,
            callData,
            gas_
        );
        assertFalse(success, "at the threshold: the beat reverts at the next check");

        // The gas between the two checks is the gas spent around the step plus the gas the
        // reverting step consumed, which the call trace of this test reports
        console2.log("execute, long revert data: gas between the checks", required - available);
    }
}
// forge-lint: disable-end(literal-instead-of-constant,calls-loop,low-level-calls,return-bomb,inline-assembly,erc20-unchecked-transfer,boolean-cst,unsafe-typecast,unused-return)
