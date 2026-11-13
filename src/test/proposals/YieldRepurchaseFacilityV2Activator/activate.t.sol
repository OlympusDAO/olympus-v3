// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Test
import {VmSafe} from "@forge-std-1.16.2/Vm.sol";

// Interfaces
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";
import {IYieldRepoV1} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepoV1.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2Config} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Config.sol";
import {IYieldRepurchaseFacilityV2Write} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Write.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IYieldRepurchaseFacilityV2Activator} from "src/proposals/interfaces/IYieldRepurchaseFacilityV2Activator.sol";

// Contracts
import {YieldRepurchaseFacilityV2ActivatorTest} from "./YieldRepurchaseFacilityV2ActivatorTest.sol";

/// @notice `activate`: the caller, the one-use flag, the cap of the sUSDe next yield, the roles
///         of the activator, the rollback of a failed launch, and the state each step leaves.
contract YieldRepurchaseFacilityV2ActivatorTests_activate is
    YieldRepurchaseFacilityV2ActivatorTest
{
    /// @notice The largest next yield the activator accepts for the sUSDe vault, in USDe (18
    ///         decimals).
    uint256 internal constant MAX_SUSDE_NEXT_YIELD = 100_000e18;

    /// @notice The state of v1.2 and of the treasury read before the launch.
    struct Before {
        uint48 epoch;
        uint256 nextYield;
        uint256 lastReserveBalance;
        uint256 lastConversionRate;
        uint256 v1Usds;
        uint256 v1SUsdsShares;
        uint256 v1Ohm;
        uint256 poolSeed;
        uint256 treasuryUsds;
        uint256 treasurySUsdsShares;
        uint256 treasurySUsdeShares;
        uint256 ohmSupply;
    }

    // ========== HELPERS ========== //

    function _before() internal view returns (Before memory b) {
        b.epoch = yieldRepoV1.epoch();
        b.nextYield = yieldRepoV1.nextYield();
        b.lastReserveBalance = yieldRepoV1.lastReserveBalance();
        b.lastConversionRate = yieldRepoV1.lastConversionRate();
        b.v1Usds = usds.balanceOf(address(yieldRepoV1));
        b.v1SUsdsShares = sUsds.balanceOf(address(yieldRepoV1));
        b.v1Ohm = ohm.balanceOf(address(yieldRepoV1));
        // USDS (18 decimals) + USDS value of the sUSDS shares (18 decimals, rounded down by the
        // vault) -> USDS (18 decimals)
        b.poolSeed = b.v1Usds + sUsds.previewRedeem(b.v1SUsdsShares);
        b.treasuryUsds = usds.balanceOf(address(treasury));
        b.treasurySUsdsShares = sUsds.balanceOf(address(treasury));
        b.treasurySUsdeShares = sUsde.balanceOf(address(treasury));
        b.ohmSupply = ohm.totalSupply();
    }

    /// @notice Runs the launch and returns the account accesses it makes, in order.
    function _recordActivation() internal returns (VmSafe.AccountAccess[] memory accesses) {
        vm.startStateDiffRecording();
        _activate(SUSDE_NEXT_YIELD);
        return vm.stopAndReturnStateDiff();
    }

    /// @notice Returns whether `data_` begins with `prefix_`.
    function _beginsWith(bytes memory data_, bytes memory prefix_) internal pure returns (bool) {
        if (data_.length < prefix_.length) return false;
        for (uint256 i = 0; i < prefix_.length; ++i) {
            if (data_[i] != prefix_[i]) return false;
        }
        return true;
    }

    /// @notice Asserts the registration of the sUSDS vault against the state of v1.2 read
    ///         before the launch.
    function _assertSUsdsAsset(Before memory b) internal view {
        IYieldRepurchaseFacilityV2.ReserveAsset memory asset = facility.getAssetConfig(
            address(sUsds)
        );
        assertEq(asset.reserve, address(usds), "sUSDS: the reserve should be USDS");
        assertTrue(asset.isAssetEnabled, "sUSDS: the asset should be enabled");
        assertFalse(asset.sellShares, "sUSDS: the markets should pay out the reserve");
        assertEq(asset.yieldBuybackShare, SUSDS_YIELD_BUYBACK_SHARE, "sUSDS: yieldBuybackShare");
        assertEq(asset.nextYield, b.nextYield, "sUSDS: nextYield should be the one of v1.2");
        assertEq(
            asset.lastReserveBalance,
            b.lastReserveBalance,
            "sUSDS: lastReserveBalance should be the one of v1.2"
        );
        assertEq(
            asset.lastConversionRate,
            b.lastConversionRate,
            "sUSDS: lastConversionRate should be the one of v1.2"
        );
        assertEq(facility.backingVault(), address(sUsds), "sUSDS should be the backing vault");
    }

    /// @notice Asserts the registration of the sUSDe vault with the next yield of the call and
    ///         the snapshots the vault reports.
    function _assertSUsdeAsset(Before memory b, uint256 nextYield_) internal view {
        IYieldRepurchaseFacilityV2.ReserveAsset memory asset = facility.getAssetConfig(
            address(sUsde)
        );
        assertEq(asset.reserve, address(usde), "sUSDe: the reserve should be USDe");
        assertTrue(asset.isAssetEnabled, "sUSDe: the asset should be enabled");
        assertTrue(asset.sellShares, "sUSDe: the markets should pay out the shares");
        assertEq(asset.yieldBuybackShare, SUSDE_YIELD_BUYBACK_SHARE, "sUSDe: yieldBuybackShare");
        assertEq(asset.nextYield, nextYield_, "sUSDe: nextYield should be the argument");
        // 5,000,000 shares (18 decimals) at 1.2 USDe per share = 6,000,000 USDe (18 decimals).
        // The vault holds 6,000,000 USDe against 5,000,000 shares, so the division is exact.
        assertEq(b.treasurySUsdeShares, TREASURY_USDE, "sUSDe: treasury shares of the rig");
        assertEq(
            asset.lastReserveBalance,
            6_000_000e18,
            "sUSDe: lastReserveBalance should be the reserve value of the treasury shares"
        );
        // One whole share (1e18) * 6,000,000e18 / 5,000,000e18 = 1.2e18 (18 decimals), exact
        assertEq(
            asset.lastConversionRate,
            1.2e18,
            "sUSDe: lastConversionRate should be the reserve value of one whole share"
        );
    }

    // ========== ERROR CONDITIONS ========== //

    // when the caller is not the timelock
    //   [X] it reverts with NotTimelock naming the caller

    function test_whenCallerIsNotTimelock_reverts(address caller_) public {
        vm.assume(caller_ != ocgTimelock);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_NotTimelock
                    .selector,
                caller_
            )
        );
        vm.prank(caller_);
        activator.activate(SUSDE_NEXT_YIELD);

        _assertNotLaunched();
    }

    // given the launch has completed
    //   [X] it reverts with AlreadyActivated

    function test_givenActivated_reverts() public {
        _activate(SUSDE_NEXT_YIELD);

        vm.expectRevert(
            IYieldRepurchaseFacilityV2Activator
                .YieldRepurchaseFacilityV2Activator_AlreadyActivated
                .selector
        );
        _activate(SUSDE_NEXT_YIELD);
    }

    // when the sUSDe next yield is one unit above the maximum
    //   [X] it reverts with NextYieldTooHigh naming the value and the maximum

    function test_whenNextYieldIsOneAboveMaximum_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_NextYieldTooHigh
                    .selector,
                MAX_SUSDE_NEXT_YIELD + 1,
                MAX_SUSDE_NEXT_YIELD
            )
        );
        _activate(MAX_SUSDE_NEXT_YIELD + 1);

        _assertNotLaunched();
    }

    // when the sUSDe next yield is above the maximum
    //   [X] it reverts with NextYieldTooHigh naming the value and the maximum

    function test_whenNextYieldIsAboveMaximum_reverts(uint256 nextYield_) public {
        // Every value above the maximum: [maximum + 1, type(uint256).max]
        uint256 nextYield = bound(nextYield_, MAX_SUSDE_NEXT_YIELD + 1, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_NextYieldTooHigh
                    .selector,
                nextYield,
                MAX_SUSDE_NEXT_YIELD
            )
        );
        _activate(nextYield);
    }

    // when the sUSDe next yield is the largest representable value
    //   [X] it reverts with NextYieldTooHigh

    function test_whenNextYieldIsMaxUint_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_NextYieldTooHigh
                    .selector,
                type(uint256).max,
                MAX_SUSDE_NEXT_YIELD
            )
        );
        _activate(type(uint256).max);
    }

    // given the activator does not hold admin
    //   [X] it reverts with MissingRole naming admin

    function test_givenActivatorWithoutAdmin_reverts() public {
        rolesAdmin.revokeRole(ADMIN_ROLE, address(activator));

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_MissingRole
                    .selector,
                ADMIN_ROLE
            )
        );
        _activate(SUSDE_NEXT_YIELD);

        _assertNotLaunched();
    }

    // given the activator does not hold loop_daddy
    //   [X] it reverts with MissingRole naming loop_daddy

    function test_givenActivatorWithoutLoopDaddy_reverts() public {
        rolesAdmin.revokeRole(LOOP_DADDY_ROLE, address(activator));

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_MissingRole
                    .selector,
                LOOP_DADDY_ROLE
            )
        );
        _activate(SUSDE_NEXT_YIELD);

        _assertNotLaunched();
    }

    // given a precondition of the launch does not hold
    //   [X] it reverts with the error of the precondition
    //   [X] the one-use flag stays unset

    function test_givenPreconditionNotMet_reverts() public {
        vm.prank(bondGuardian);
        bondAuctioneer.setCallbackAuthStatus(address(facility), false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_CallbackNotAuthorized
                    .selector,
                address(bondAuctioneer)
            )
        );
        _activate(SUSDE_NEXT_YIELD);

        _assertNotLaunched();
    }

    // given the last step of the launch reverts
    //   [X] it reverts with the revert data of that step
    //   [X] nothing of the launch stays: the flag, the policies, v1.2, the periodic task and USDe

    function test_givenLastStepReverts_reverts() public {
        vm.mockCallRevert(
            address(heart),
            abi.encodeWithSelector(IPeriodicTaskManager.addPeriodicTaskAtIndex.selector),
            "late failure"
        );

        vm.expectRevert(bytes("late failure"));
        _activate(SUSDE_NEXT_YIELD);

        _assertNotLaunched();
    }

    // ========== SUCCESS CONDITIONS ========== //

    // given the prepared stack
    //   when the timelock activates
    //     [X] it emits Activated with the epoch, the next yield and the funds of v1.2 and the sUSDe next yield
    //     [X] the activator is activated

    function test_givenPreparedStack_emitsActivated() public {
        Before memory b = _before();

        vm.expectEmit(address(activator));
        emit IYieldRepurchaseFacilityV2Activator.Activated(
            b.epoch,
            b.nextYield,
            b.poolSeed,
            SUSDE_NEXT_YIELD
        );
        _activate(SUSDE_NEXT_YIELD);

        assertTrue(activator.isActivated(), "the activator should be activated");
    }

    // given the prepared stack
    //   when the timelock activates
    //     [X] USDe is registered in the PRICE module and OHM is priced in it
    //     [X] the five policies are enabled and bound to each other
    //     [X] the oracle holds the backing, and the facility the discount and the premium

    function test_givenPreparedStack_enablesAndBindsTheStack() public {
        _activate(SUSDE_NEXT_YIELD);

        assertTrue(price.isAssetApproved(address(usde)), "USDe should be registered");
        // OHM at 20 USD / USDe at 0.9995 USD = 20.0100050025... USDe per OHM (18 decimals)
        assertGt(price.getPriceIn(address(ohm), address(usde)), 20e18, "OHM priced in USDe");

        assertTrue(backingOracle.isEnabled(), "the oracle should be enabled");
        assertTrue(
            backingOracleConfigTimelock.isEnabled(),
            "the oracle timelock should be enabled"
        );
        assertTrue(config.isEnabled(), "the configuration policy should be enabled");
        assertTrue(configTimelock.isEnabled(), "the config timelock should be enabled");
        assertTrue(facility.isEnabled(), "the facility should be enabled");

        assertEq(
            backingOracle.configOperator(),
            address(backingOracleConfigTimelock),
            "the oracle timelock should be the config operator of the oracle"
        );
        assertEq(config.facility(), address(facility), "the configuration policy should be bound");
        assertEq(facility.configurator(), address(config), "the facility should name the policy");
        assertEq(
            config.configOperator(),
            address(configTimelock),
            "the config timelock should be the config operator of the policy"
        );

        assertEq(backingOracle.backing(), BACKING, "the oracle should hold the launch backing");
        assertEq(facility.initialDiscount(), INITIAL_DISCOUNT, "initialDiscount");
        assertEq(facility.maxPricePremium(), MAX_PRICE_PREMIUM, "maxPricePremium");
    }

    // given the prepared stack
    //   when the timelock activates
    //     [X] v1.2 is shut down, its USDS and sUSDS are in the treasury and its OHM is burned
    //     [X] the sUSDS vault is the backing vault with the next yield and the snapshots of v1.2
    //     [X] the sUSDe vault carries the next yield of the call and the snapshots the vault reports
    //     [X] the facility resumes at the epoch of v1.2 with the funds of v1.2 in its buyback pool

    function test_givenPreparedStack_migratesTheWeeklyCycle() public {
        // The rig leaves v1.2 at epoch 8 with the yield of its weekly reset unspent: 70,000 USDS
        // withdrawn as sUSDS at 1.05 USDS per share, of which the three daily cycles redeemed
        // 70,000 / 5 = 14,000 USDS for their markets.
        Before memory b = _before();
        assertEq(b.epoch, V1_EPOCH, "rig: the epoch of v1.2");
        assertGt(b.v1Usds, 0, "rig: v1.2 should hold USDS");
        assertGt(b.v1SUsdsShares, 0, "rig: v1.2 should hold sUSDS");
        // A purchase of the running day, which v1.2 has not burned against a withdrawal yet
        ohm.mint(address(yieldRepoV1), 50e9);
        b = _before();

        _activate(SUSDE_NEXT_YIELD);

        // v1.2
        assertTrue(yieldRepoV1.isShutdown(), "v1.2 should be shut down");
        assertEq(usds.balanceOf(address(yieldRepoV1)), 0, "v1.2 should hold no USDS");
        assertEq(sUsds.balanceOf(address(yieldRepoV1)), 0, "v1.2 should hold no sUSDS");
        assertEq(ohm.balanceOf(address(yieldRepoV1)), 0, "v1.2 should hold no OHM");
        // The OHM of v1.2 (9 decimals) is burned
        assertEq(ohm.totalSupply(), b.ohmSupply - b.v1Ohm, "the OHM of v1.2 should be burned");

        // Assets
        address[] memory vaults = facility.getVaults();
        assertEq(vaults.length, 2, "the facility should register two vaults");
        _assertSUsdsAsset(b);
        _assertSUsdeAsset(b, SUSDE_NEXT_YIELD);

        // Cycle
        assertEq(facility.epoch(), b.epoch, "the facility should resume at the epoch of v1.2");
        assertFalse(facility.isCycleSeedable(), "the seeding window should be closed");

        // Funds. The seed withdraws the shares that cover poolSeed, rounded up by the vault:
        // shares = previewWithdraw(poolSeed) (18 decimals).
        uint256 seedShares = sUsds.previewWithdraw(b.poolSeed);
        assertEq(
            sUsds.balanceOf(address(facility)),
            seedShares,
            "the facility should hold the shares that cover the funds of v1.2"
        );
        assertEq(usds.balanceOf(address(facility)), 0, "the facility should hold no USDS");
        assertEq(
            facility.getAssetConfig(address(sUsds)).unfundedYield,
            0,
            "the treasury should cover the whole seed"
        );
        // treasury USDS = before + USDS of v1.2 (18 decimals)
        assertEq(
            usds.balanceOf(address(treasury)),
            b.treasuryUsds + b.v1Usds,
            "the treasury should receive the USDS of v1.2"
        );
        // treasury sUSDS = before + shares of v1.2 - shares of the seed (18 decimals). No
        // share is withdrawn for the OHM v1.2 held: its backing stays in the treasury.
        assertEq(
            sUsds.balanceOf(address(treasury)),
            b.treasurySUsdsShares + b.v1SUsdsShares - seedShares,
            "the treasury should give up only the shares of the seed"
        );
        assertEq(
            sUsde.balanceOf(address(treasury)),
            b.treasurySUsdeShares,
            "the treasury sUSDe should not move"
        );
        assertEq(sUsde.balanceOf(address(facility)), 0, "the facility should hold no sUSDe");
        assertEq(usds.balanceOf(address(activator)), 0, "the activator should hold no USDS");
        assertEq(sUsds.balanceOf(address(activator)), 0, "the activator should hold no sUSDS");
    }

    // given the prepared stack
    //   when the timelock activates
    //     [X] each Clearinghouse listed as included is included, and each non-zero offset is set

    function test_givenPreparedStack_configuresTheClearinghouses() public {
        _activate(SUSDE_NEXT_YIELD);

        assertTrue(
            facility.isClearinghouseIncluded(address(clearinghouseOne)),
            "the first Clearinghouse should be included"
        );
        assertEq(facility.clearinghouseOffset(address(clearinghouseOne)), 0, "first offset");
        assertTrue(
            facility.isClearinghouseIncluded(address(clearinghouseTwo)),
            "the second Clearinghouse should be included"
        );
        assertEq(
            facility.clearinghouseOffset(address(clearinghouseTwo)),
            CLEARINGHOUSE_TWO_OFFSET,
            "second offset"
        );
        assertFalse(
            facility.isClearinghouseIncluded(address(clearinghouseThree)),
            "the third Clearinghouse should not be included"
        );
        assertEq(facility.clearinghouseOffset(address(clearinghouseThree)), 0, "third offset");
    }

    // given the prepared stack
    //   when the timelock activates
    //     [X] the facility takes the periodic task slot of v1.2 without a custom selector
    //     [X] the other periodic tasks keep their slots

    function test_givenPreparedStack_replacesThePeriodicTask() public {
        _activate(SUSDE_NEXT_YIELD);

        assertEq(heart.getPeriodicTaskCount(), TASK_COUNT, "the task count should not change");
        assertFalse(heart.hasPeriodicTask(address(yieldRepoV1)), "v1.2 should not be a task");
        (address task, bytes4 selector) = heart.getPeriodicTaskAtIndex(V1_TASK_INDEX);
        assertEq(task, address(facility), "the facility should take the slot of v1.2");
        assertEq(selector, bytes4(0), "the facility should be called through execute()");
        (address before, ) = heart.getPeriodicTaskAtIndex(V1_TASK_INDEX - 1);
        assertEq(before, address(taskBefore), "the task before should keep its slot");
        (address afterTask, ) = heart.getPeriodicTaskAtIndex(V1_TASK_INDEX + 1);
        assertEq(afterTask, address(taskAfter), "the task after should keep its slot");
    }

    // given the prepared stack
    //   when the timelock activates
    //     [X] the activator makes its state-changing calls in the order of the launch: the
    //         registration of USDe, the oracle, the binding and enabling of the configuration
    //         policy, its timelock and the facility, the shutdown of v1.2, the two vaults, the
    //         Clearinghouses, the seed of the cycle and the periodic task

    function test_givenPreparedStack_callsTheStepsInOrder() public {
        // The calls of the launch: the target and the calldata the call begins with
        address[19] memory targets = [
            address(priceConfig),
            address(backingOracle),
            address(backingOracleConfigTimelock),
            address(backingOracle),
            address(config),
            address(facility),
            address(config),
            address(config),
            address(configTimelock),
            address(facility),
            address(yieldRepoV1),
            address(config),
            address(config),
            address(config),
            address(config),
            address(config),
            address(facility),
            address(heart),
            address(heart)
        ];
        bytes[19] memory calls = [
            abi.encodeWithSelector(IPriceConfigv2.addAsset.selector, address(usde)),
            abi.encodeCall(
                IConfigOperator.setConfigOperator,
                (address(backingOracleConfigTimelock))
            ),
            abi.encodeCall(IEnabler.enable, ("")),
            abi.encodeCall(IEnabler.enable, (abi.encode(BACKING))),
            abi.encodeCall(IYieldRepurchaseFacilityV2Config.setFacility, (address(facility))),
            abi.encodeCall(IYieldRepurchaseFacilityV2Write.setConfigurator, (address(config))),
            abi.encodeCall(IEnabler.enable, ("")),
            abi.encodeCall(IConfigOperator.setConfigOperator, (address(configTimelock))),
            abi.encodeCall(IEnabler.enable, ("")),
            abi.encodeWithSelector(IEnabler.enable.selector),
            abi.encodeWithSelector(IYieldRepoV1.shutdown.selector),
            // The first member of the registration is the vault
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Config.addAsset.selector,
                address(sUsds)
            ),
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Config.addAsset.selector,
                address(sUsde)
            ),
            abi.encodeCall(
                IYieldRepurchaseFacilityV2Config.includeClearinghouse,
                (address(clearinghouseOne))
            ),
            abi.encodeCall(
                IYieldRepurchaseFacilityV2Config.includeClearinghouse,
                (address(clearinghouseTwo))
            ),
            abi.encodeCall(
                IYieldRepurchaseFacilityV2Config.setClearinghouseOffset,
                (address(clearinghouseTwo), CLEARINGHOUSE_TWO_OFFSET)
            ),
            abi.encodeWithSelector(IYieldRepurchaseFacilityV2Write.seedCycle.selector, V1_EPOCH),
            abi.encodeCall(IPeriodicTaskManager.removePeriodicTaskAtIndex, (V1_TASK_INDEX)),
            abi.encodeCall(
                IPeriodicTaskManager.addPeriodicTaskAtIndex,
                (address(facility), bytes4(0), V1_TASK_INDEX)
            )
        ];

        VmSafe.AccountAccess[] memory accesses = _recordActivation();

        // The reads of the launch are static calls, so its calls are the state-changing ones
        uint256 step = 0;
        for (uint256 i = 0; i < accesses.length; ++i) {
            if (accesses[i].accessor != address(activator)) continue;
            if (accesses[i].kind != VmSafe.AccountAccessKind.Call) continue;
            assertLt(step, targets.length, "the activator should make no call after the last step");
            assertEq(
                accesses[i].account,
                targets[step],
                string.concat("the target of step ", vm.toString(step + 1))
            );
            assertTrue(
                _beginsWith(accesses[i].data, calls[step]),
                string.concat("the call of step ", vm.toString(step + 1))
            );
            ++step;
        }
        assertEq(step, targets.length, "the activator should make every call of the launch");
    }

    // given the prepared stack
    //   when the timelock activates
    //     [X] the one-use flag is written before the first external call of the activator

    function test_givenPreparedStack_setsTheFlagBeforeTheFirstExternalCall() public {
        VmSafe.AccountAccess[] memory accesses = _recordActivation();

        // The recording splits the storage accesses of a call at its external calls: the
        // accesses up to the first one belong to the entry of the call itself, and the ones
        // after an external call returns belong to an entry of the kind Resume
        uint256 entry = type(uint256).max;
        bool resumedWithStorage = false;
        for (uint256 i = 0; i < accesses.length; ++i) {
            if (accesses[i].account != address(activator)) continue;
            if (entry == type(uint256).max && accesses[i].kind == VmSafe.AccountAccessKind.Call) {
                entry = i;
            }
            if (
                accesses[i].kind == VmSafe.AccountAccessKind.Resume &&
                accesses[i].storageAccesses.length != 0
            ) resumedWithStorage = true;
        }
        assertLt(entry, accesses.length, "the recording should hold the call of activate");
        assertEq(accesses[entry].accessor, ocgTimelock, "the timelock should call activate");
        assertTrue(
            resumedWithStorage,
            "rig: the storage the activator reads after its external calls should be recorded apart"
        );

        // The flag: the only storage write of the activator, from false to true
        uint256 writes = 0;
        VmSafe.StorageAccess[] memory storageAccesses = accesses[entry].storageAccesses;
        for (uint256 i = 0; i < storageAccesses.length; ++i) {
            if (!storageAccesses[i].isWrite) continue;
            assertEq(storageAccesses[i].account, address(activator), "the written contract");
            assertEq(storageAccesses[i].previousValue, bytes32(0), "the flag should be unset");
            assertEq(storageAccesses[i].newValue, bytes32(uint256(1)), "the flag should be set");
            ++writes;
        }
        assertEq(writes, 1, "the flag should be written before the first external call");

        // No later part of the call writes the storage of the activator
        for (uint256 i = entry + 1; i < accesses.length; ++i) {
            if (accesses[i].account != address(activator)) continue;
            for (uint256 j = 0; j < accesses[i].storageAccesses.length; ++j) {
                assertFalse(
                    accesses[i].storageAccesses[j].isWrite,
                    "the activator should write nothing after its first external call"
                );
            }
        }
    }

    // given the launch has completed
    //   when the Heart runs its periodic tasks
    //     [X] the facility advances its epoch and opens the market of the day from the funds of v1.2
    //     [X] v1.2 is not called

    function test_givenActivated_whenHeartBeats() public {
        _activate(SUSDE_NEXT_YIELD);
        uint256 poolValue = sUsds.previewRedeem(sUsds.balanceOf(address(facility)));

        heart.executeAllTasks();

        // Epoch 8 -> 9, a multiple of three: a daily cycle
        assertEq(facility.epoch(), V1_EPOCH + 1, "the facility should advance its epoch");
        assertEq(yieldRepoV1.epoch(), V1_EPOCH, "v1.2 should not be called");
        (bool tracked, uint256 marketId) = facility.trackedMarket(address(sUsds));
        assertTrue(tracked, "the facility should open the sUSDS market of the day");
        // Three days of the week are gone at epoch 9, so four remain:
        // capacity = pool value (USDS, 18 decimals) / 4, rounded down
        assertEq(
            bondAuctioneer.currentCapacity(marketId),
            poolValue / 4,
            "the market should offer a quarter of the pool"
        );
        assertEq(taskBefore.count(), 1, "the task before should run");
        assertEq(taskAfter.count(), 1, "the task after should run");
    }

    // when the sUSDe next yield is the maximum
    //   [X] it registers the vault with that next yield

    function test_whenNextYieldIsMaximum() public {
        Before memory b = _before();

        _activate(MAX_SUSDE_NEXT_YIELD);

        _assertSUsdeAsset(b, MAX_SUSDE_NEXT_YIELD);
    }

    // when the sUSDe next yield is zero
    //   [X] it registers the vault with a zero next yield

    function test_whenNextYieldIsZero() public {
        Before memory b = _before();

        _activate(0);

        _assertSUsdeAsset(b, 0);
    }

    // when the sUSDe next yield is at most the maximum
    //   [X] it registers the vault with that next yield

    function test_whenNextYieldIsWithinMaximum(uint256 nextYield_) public {
        // Every accepted value: [0, maximum]
        uint256 nextYield = bound(nextYield_, 0, MAX_SUSDE_NEXT_YIELD);
        Before memory b = _before();

        _activate(nextYield);

        _assertSUsdeAsset(b, nextYield);
        assertTrue(activator.isActivated(), "the activator should be activated");
    }

    // given USDe is registered in the PRICE module
    //   when the timelock activates
    //     [X] it does not register USDe again
    //     [X] it launches while PriceConfig is disabled

    function test_givenUsdeRegistered() public givenUsdeRegistered {
        priceConfig.disable("");

        vm.expectCall(
            address(priceConfig),
            abi.encodeWithSelector(IPriceConfigv2.addAsset.selector),
            0
        );
        _activate(SUSDE_NEXT_YIELD);

        assertTrue(activator.isActivated(), "the activator should be activated");
        assertTrue(facility.isEnabled(), "the facility should be enabled");
    }

    // given v1.2 has not run a cycle since its initialization and holds no funds
    //   when the timelock activates
    //     [X] the facility resumes at the initial epoch of v1.2 with an empty buyback pool

    function test_givenV1HoldsNoFunds() public {
        uint256 reserveBalance = yieldRepoV1.lastReserveBalance();
        uint256 conversionRate = yieldRepoV1.lastConversionRate();
        address[] memory tokens = new address[](2);
        tokens[0] = address(usds);
        tokens[1] = address(sUsds);
        // A shutdown returns the funds, and the initialization that follows restarts v1.2 at
        // its initial epoch
        vm.startPrank(daoMS);
        (bool ok, ) = address(yieldRepoV1).call(
            abi.encodeWithSignature("shutdown(address[])", tokens)
        );
        yieldRepoV1.initialize(reserveBalance, conversionRate, V1_INITIAL_YIELD);
        vm.stopPrank();
        assertTrue(ok, "rig: the shutdown of v1.2 should succeed");
        Before memory b = _before();
        assertEq(b.poolSeed, 0, "rig: v1.2 should hold no funds");
        // initialize() sets the epoch counter to 20
        assertEq(b.epoch, 20, "rig: v1.2 should be at its initial epoch");

        vm.expectEmit(address(activator));
        emit IYieldRepurchaseFacilityV2Activator.Activated(
            20,
            V1_INITIAL_YIELD,
            0,
            SUSDE_NEXT_YIELD
        );
        _activate(SUSDE_NEXT_YIELD);

        assertEq(facility.epoch(), 20, "the facility should resume at the epoch of v1.2");
        assertFalse(facility.isCycleSeedable(), "the seeding window should be closed");
        assertEq(sUsds.balanceOf(address(facility)), 0, "the buyback pool should be empty");
        assertEq(
            sUsds.balanceOf(address(treasury)),
            b.treasurySUsdsShares,
            "the treasury sUSDS should not move"
        );
        _assertSUsdsAsset(b);
    }

    // given a holder of loop_daddy has initialized v1.2 again with a zero reserve balance
    //   when the timelock activates
    //     [X] the sUSDS vault is registered with a zero reserve balance snapshot

    function test_givenV1ReserveBalanceSnapshotIsZero() public {
        uint256 conversionRate = yieldRepoV1.lastConversionRate();
        vm.prank(daoMS);
        yieldRepoV1.initialize(0, conversionRate, V1_INITIAL_YIELD);
        Before memory b = _before();
        assertEq(b.lastReserveBalance, 0, "rig: the reserve balance snapshot should be zero");

        _activate(SUSDE_NEXT_YIELD);

        _assertSUsdsAsset(b);
        assertEq(
            facility.getAssetConfig(address(sUsds)).lastReserveBalance,
            0,
            "sUSDS: the reserve balance snapshot should be zero"
        );
        assertTrue(activator.isActivated(), "the activator should be activated");
    }

    // given a third party has transferred USDS and sUSDS to v1.2
    //   when the timelock activates
    //     [X] the transferred funds join the buyback pool of the facility

    function test_givenTokensTransferredToV1() public {
        Before memory b = _before();
        // 1,000 USDS and 2,000 USDS deposited into sUSDS
        usds.mint(address(yieldRepoV1), 1_000e18);
        _depositFor(usds, sUsds, address(yieldRepoV1), 2_000e18);
        Before memory donated = _before();
        assertGt(donated.poolSeed, b.poolSeed, "rig: the transfers should raise the funds of v1.2");

        vm.expectEmit(address(activator));
        emit IYieldRepurchaseFacilityV2Activator.Activated(
            donated.epoch,
            donated.nextYield,
            donated.poolSeed,
            SUSDE_NEXT_YIELD
        );
        _activate(SUSDE_NEXT_YIELD);

        assertEq(
            sUsds.balanceOf(address(facility)),
            sUsds.previewWithdraw(donated.poolSeed),
            "the facility should hold the shares that cover every fund of v1.2"
        );
    }

    // given the treasury sUSDS does not cover the funds of v1.2
    //   when the timelock activates
    //     [X] it launches, and the facility carries the uncovered part as unfunded yield

    function test_givenTreasuryDoesNotCoverTheSeed() public {
        // The treasury gives its sUSDS away, so after the shutdown it holds only the shares of
        // v1.2, which cover the funds of v1.2 less its USDS
        address sink = makeAddr("sink");
        uint256 treasuryShares = sUsds.balanceOf(address(treasury));
        vm.prank(address(treasury));
        sUsds.transfer(sink, treasuryShares);
        Before memory b = _before();

        _activate(SUSDE_NEXT_YIELD);

        assertEq(
            sUsds.balanceOf(address(facility)),
            b.v1SUsdsShares,
            "the facility should receive every share the treasury holds"
        );
        // unfunded = seed - value of the withdrawn shares (USDS, 18 decimals):
        // (v1 USDS + previewRedeem(v1 shares)) - previewRedeem(v1 shares) = v1 USDS
        assertEq(
            facility.getAssetConfig(address(sUsds)).unfundedYield,
            b.v1Usds,
            "the uncovered part of the seed should be carried"
        );
        assertTrue(activator.isActivated(), "the activator should be activated");
    }

    // given a Clearinghouse is offset without being included
    //   when the timelock activates
    //     [X] the offset is set and the Clearinghouse is not included

    function test_givenClearinghouseOffsetWithoutInclusion() public {
        IYieldRepurchaseFacilityV2Activator.LaunchParameters
            memory parameters = _launchParameters();
        parameters.clearinghouses[2].offset = CLEARINGHOUSE_THREE_RECEIVABLES;
        _replaceActivator(parameters);

        _activate(SUSDE_NEXT_YIELD);

        assertFalse(
            facility.isClearinghouseIncluded(address(clearinghouseThree)),
            "the third Clearinghouse should not be included"
        );
        assertEq(
            facility.clearinghouseOffset(address(clearinghouseThree)),
            CLEARINGHOUSE_THREE_RECEIVABLES,
            "the offset should equal the receivables"
        );
    }
}
