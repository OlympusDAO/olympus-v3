// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IBondAuctioneer} from "src/interfaces/IBondAuctioneer.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IYieldRepoV1} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepoV1.sol";
import {IYieldRepurchaseFacilityConfigTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityConfigTimelock.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

// Libraries
import {Owned} from "@solmate-6.2.0/auth/Owned.sol";

// Contracts
import {Kernel, Policy, toKeycode} from "src/Kernel.sol";

/// @title YieldRepurchaseFacilityV2Activator
/// @notice Single-use contract that migrates the Yield Repurchase Facility from the
///         deployed v1.2 to the multi-asset v2 stack in a single OCG proposal action:
///         it wires and enables the YieldRepurchaseFacilityConfigTimelock, the BackingOracle, and the
///         YieldRepurchaseFacilityV2, shuts down YRF v1.2, migrates its accounting into
///         the v2 seeds, registers sUSDe as a second yield asset, includes the Cooler
///         v1 Clearinghouses in the backing yield, seeds the running week, and swaps the
///         Heart periodic task from v1.2 to v2.
/// @dev Assumes:
///      - The owner is the OCG timelock, which calls `activate()` from the proposal.
///      - The `admin` role has been granted to this contract for the duration of the
///        activation (revoked by the proposal immediately after).
///      - The `loop_daddy` role has been granted to this contract for the duration of
///        the activation, so that reading the v1.2 seeds and sweeping its funds via
///        `shutdown` are atomic (revoked by the proposal immediately after).
///      - The DAO MS has already activated the BackingOracle, the YieldRepurchaseFacilityConfigTimelock, and the
///        YieldRepurchaseFacilityV2 policies in the Kernel.
///      - The Bond Protocol multisig has already authorized the v2 facility as a market
///        callback on the SDA auctioneer.
///      - The price_admin role holder has already registered USDe in the PRICE module
///        through the PriceConfig v2 policy, so that `PRICE.getPriceIn(OHM, USDe)`
///        resolves.
contract YieldRepurchaseFacilityV2Activator is Owned {
    // ========== EXISTING CONTRACTS ========== //

    /// @notice The Olympus V3 Kernel, used to resolve the TRSRY module.
    address public constant KERNEL = 0x2286d7f9639e8158FaD1169e76d1FbC38247f54b;

    /// @notice The Heart policy (v1.7) driving the periodic task pipeline.
    address public constant HEART = 0x5824850D8A6E46a473445a5AF214C7EbD46c5ECB;

    /// @notice The deployed YRF v1.2, shut down by the activation.
    address public constant YIELD_REPO_V1 = 0x271e35a8555a62F6bA76508E85dfD76D580B0692;

    /// @notice The Bond Protocol SDA auctioneer used by both YRF versions.
    address public constant BOND_AUCTIONEER = 0x007F7A1cb838A872515c8ebd16bE4b14Ef43a222;

    /// @notice The Bond Protocol fixed-term teller trusted to invoke the v2 callback.
    address public constant BOND_TELLER = 0x007F7735baF391e207E3aA380bb53c4Bd9a5Fed6;

    /// @notice The Cooler v1 Clearinghouse v1 (DAI-denominated), included in the backing
    ///         yield: its receivables accrue to USDS through the 1:1 DAI to USDS
    ///         migration.
    address public constant CLEARINGHOUSE_V1 = 0xD6A6E8d9e82534bD65821142fcCd91ec9cF31880;

    /// @notice The Cooler v1 Clearinghouse v1.1 (DAI-denominated), included in the
    ///         backing yield.
    address public constant CLEARINGHOUSE_V1_1 = 0xE6343ad0675C9b8D3f32679ae6aDbA0766A2ab4c;

    // ========== TOKENS ========== //

    /// @notice The OHM token, the asset side of the facility's price reads.
    address public constant OHM = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;

    /// @notice The USDS token, the backing reserve.
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    /// @notice The sUSDS vault, registered as the backing vault.
    address public constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;

    /// @notice The USDe token, the reserve of the sUSDe vault.
    address public constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;

    /// @notice The sUSDe vault, registered as a sell-shares yield asset.
    address public constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

    // ========== PARAMETERS ========== //

    /// @notice The initial backing value, in USDS per OHM (18 decimals).
    /// @dev 12.04e18 is the liquid backing per OHM selected for the v2 launch, replacing
    ///      the 11.33e18 value hardcoded in the deployed YRF v1.2.
    uint256 public constant BACKING = 12.04e18;

    /// @notice The initial bond market discount (`1e18` = 100%), equal to the discount
    ///         of the deployed YRF v1.2.
    uint256 public constant INITIAL_DISCOUNT = 3e16;

    /// @notice The bond market max price premium (`1e18` = 100%): the ceiling of a
    ///         market, measured from the oracle price.
    /// @dev A market opens at `INITIAL_DISCOUNT` below the oracle price and decays toward
    ///      its minimum price, so the facility pays at most
    ///      `oraclePrice * (1 + 10%)` = 1.1 times the oracle price captured when the
    ///      market opened. The premium does not compound with the discount, so the two
    ///      can be tuned independently. The deployed YRF v1.2 has no such bound: it sets
    ///      a market minimum price of zero.
    uint256 public constant MAX_PRICE_PREMIUM = 10e16;

    /// @notice The sUSDS yield buyback share (`1e18` = 100%).
    uint256 public constant SUSDS_BUYBACK_SHARE = 1e18;

    /// @notice The sUSDe yield buyback share (`1e18` = 100%).
    uint256 public constant SUSDE_BUYBACK_SHARE = 1e18;

    /// @notice The fixed next-yield seed of sUSDe (18 decimals): the budget of its first
    ///         full week, injected at the first weekly reset.
    /// @dev The estimate is one week of a 4% annualized rate on the treasury sUSDe holding:
    ///      previewRedeem(24,659,208.386952951521922260 shares)
    ///      = 30,606,111.521932362440850759 USDe at block 25,636,793.
    ///      30,606,111.521932362440850759 * 400 / 10_000 / 52
    ///      = 23,543.162709178740339115 USDe, rounding down at each division.
    uint256 public constant SUSDE_NEXT_YIELD_SEED = 23_543_162_709_178_740_339_115;

    /// @notice The Heart periodic task slot occupied by the YRF.
    uint256 public constant HEART_YRF_TASK_INDEX = 4;

    // ========== NEW CONTRACTS ========== //

    /// @notice The YieldRepurchaseFacilityV2 policy.
    address public immutable YIELD_REPO;

    /// @notice The YieldRepurchaseFacilityConfigTimelock policy.
    address public immutable CONFIG_TIMELOCK;

    /// @notice The BackingOracle policy.
    address public immutable BACKING_ORACLE;

    // ========== STATE ========== //

    /// @notice True if the activation has been performed.
    bool public isActivated;

    // ========== EVENTS ========== //

    /// @notice Emitted when the activation has been performed.
    /// @param caller The caller of `activate`.
    event Activated(address caller);

    // ========== ERRORS ========== //

    /// @notice Thrown when `activate` is invoked after the activation has been
    ///         performed.
    error AlreadyActivated();

    /// @notice Thrown when a constructor parameter is the zero address or does not
    ///         match the wiring reported by the facility.
    /// @param reason The parameter that failed the validation.
    error InvalidParams(string reason);

    /// @notice Thrown when a v2 stack policy is not active in the Kernel.
    /// @param policy The inactive policy.
    error PolicyNotActive(address policy);

    /// @notice Thrown when the facility's wired bond contracts do not match the
    ///         auctioneer and teller constants of this activator.
    /// @param bondAuctioneer The auctioneer reported by the facility.
    /// @param bondTeller The teller reported by the facility.
    error BondContractsMismatch(address bondAuctioneer, address bondTeller);

    /// @notice Thrown when the facility is not authorized as a market callback on the
    ///         SDA auctioneer.
    /// @param facility The unauthorized facility.
    error CallbackNotAuthorized(address facility);

    /// @notice Thrown when a reserve of the v2 assets does not resolve to a non-zero OHM
    ///         price through the PRICE module.
    /// @param reserve The reserve token that could not be priced.
    error ReserveNotPriceable(address reserve);

    /// @notice Thrown when a Heart periodic task slot does not hold the expected task.
    /// @param index The inspected task slot.
    /// @param expected The task expected in the slot.
    /// @param actual The task found in the slot.
    error UnexpectedHeartTask(uint256 index, address expected, address actual);

    /// @notice Thrown when the Heart periodic task count changes during the task swap.
    /// @param expected The task count before the swap.
    /// @param actual The task count after the swap.
    error HeartTaskCountChanged(uint256 expected, uint256 actual);

    // ========== CONSTRUCTOR ========== //

    /// @dev Reverts if:
    ///      - Any parameter is the zero address.
    ///      - `yieldRepo_` does not report `configTimelock_` as its timelock.
    ///      - `yieldRepo_` does not report `backingOracle_` as its backing oracle.
    /// @param owner_ The OCG timelock address.
    /// @param yieldRepo_ The YieldRepurchaseFacilityV2 policy address.
    /// @param configTimelock_ The YieldRepurchaseFacilityConfigTimelock policy address.
    /// @param backingOracle_ The BackingOracle policy address.
    constructor(
        address owner_,
        address yieldRepo_,
        address configTimelock_,
        address backingOracle_
    ) Owned(owner_) {
        if (owner_ == address(0)) revert InvalidParams("owner");
        if (yieldRepo_ == address(0)) revert InvalidParams("yieldRepo");
        if (configTimelock_ == address(0)) revert InvalidParams("configTimelock");
        if (backingOracle_ == address(0)) revert InvalidParams("backingOracle");

        // Sanity-check the wiring of the deployed v2 stack: the facility pins both the
        // timelock and the backing oracle.
        if (IYieldRepurchaseFacilityV2(yieldRepo_).timelock() != configTimelock_)
            revert InvalidParams("configTimelock mismatch");
        if (IYieldRepurchaseFacilityV2(yieldRepo_).backingOracle() != backingOracle_)
            revert InvalidParams("backingOracle mismatch");

        YIELD_REPO = yieldRepo_;
        CONFIG_TIMELOCK = configTimelock_;
        BACKING_ORACLE = backingOracle_;
    }

    // ========== ACTIVATION ========== //

    /// @notice Performs the YRF v1.2 to v2 migration.
    /// @dev This function assumes:
    ///      - The `admin` and `loop_daddy` roles have been granted to this contract.
    ///      - The BackingOracle, YieldRepurchaseFacilityConfigTimelock, and YieldRepurchaseFacilityV2 policies have
    ///        been activated in the Kernel by the DAO MS.
    ///      - The v2 facility has been callback-authorized on the SDA auctioneer by the
    ///        Bond Protocol multisig.
    ///      - USDe has been registered in the PRICE module through the PriceConfig v2
    ///        policy by the price_admin role holder.
    ///
    ///      This function reverts if:
    ///      - The caller is not the owner.
    ///      - The activation has already been performed.
    ///      - A v2 stack policy is not active in the Kernel.
    ///      - The facility's wired bond contracts do not match the auctioneer and teller
    ///        constants of this activator.
    ///      - The facility is not authorized as a market callback on the SDA auctioneer.
    ///      - USDS or USDe does not resolve to a non-zero OHM price through
    ///        `PRICE.getPriceIn`.
    ///      - The Heart task slot does not hold YRF v1.2 before the swap, does not hold
    ///        the v2 facility after the swap, or the task count changes.
    ///      - Any of the configuration calls reverts.
    function activate() external onlyOwner {
        if (isActivated) revert AlreadyActivated();

        // 1. Preconditions
        _checkPreconditions();

        // 2.-4. Wire and enable the v2 stack
        _enableV2Stack();

        // 5. Read the v1.2 accounting before the shutdown wipes its balances. The
        //    residual is the unspent weekly budget still held by v1.2 (raw USDS plus the
        //    redeemable value of its sUSDS), which the shutdown sweeps to the treasury.
        IYieldRepoV1 yieldRepoV1 = IYieldRepoV1(YIELD_REPO_V1);
        uint48 v1Epoch = yieldRepoV1.epoch();
        uint256 susdsSeedYield = yieldRepoV1.nextYield();
        uint256 susdsSeedBalance = yieldRepoV1.lastReserveBalance();
        uint256 susdsSeedRate = yieldRepoV1.lastConversionRate();
        uint256 v1Residual = IERC20(USDS).balanceOf(YIELD_REPO_V1) +
            IERC4626(SUSDS).previewRedeem(IERC4626(SUSDS).balanceOf(YIELD_REPO_V1));

        // 6. Shut down v1.2
        _shutdownV1();

        // 7.-8. Register the v2 assets
        _registerAssets(susdsSeedBalance, susdsSeedRate, susdsSeedYield);

        // 9. Include the Cooler v1 Clearinghouses in the backing yield
        _configureClearinghouses();

        // 10. Resume the interrupted v1.2 week
        _seedCycle(v1Epoch, v1Residual);

        // 11. Swap the Heart periodic task
        _swapHeartTask();

        isActivated = true;
        emit Activated(msg.sender);
    }

    // ========== INTERNAL ========== //

    /// @dev Validates the external preconditions of the activation.
    function _checkPreconditions() internal view {
        // The Kernel activation of the v2 policies is performed by the DAO MS before the
        // proposal is queued (`Policy.isActive` is the Kernel activation flag, not the
        // enabler flag).
        if (!Policy(YIELD_REPO).isActive()) revert PolicyNotActive(YIELD_REPO);
        if (!Policy(BACKING_ORACLE).isActive()) revert PolicyNotActive(BACKING_ORACLE);
        if (!Policy(CONFIG_TIMELOCK).isActive()) revert PolicyNotActive(CONFIG_TIMELOCK);

        // The callback authorization below is meaningful only on the auctioneer the
        // facility submits its markets to, so the facility's bond wiring must match the
        // constants the check runs against.
        IYieldRepurchaseFacilityV2 yieldRepo = IYieldRepurchaseFacilityV2(YIELD_REPO);
        if (yieldRepo.bondAuctioneer() != BOND_AUCTIONEER || yieldRepo.bondTeller() != BOND_TELLER)
            revert BondContractsMismatch(yieldRepo.bondAuctioneer(), yieldRepo.bondTeller());

        // The callback authorization is granted by the Bond Protocol multisig before the
        // proposal is queued; the auctioneer rejects every market submission of an
        // unauthorized callback.
        if (!IBondAuctioneer(BOND_AUCTIONEER).callbackAuthorized(YIELD_REPO))
            revert CallbackNotAuthorized(YIELD_REPO);

        // The facility prices each asset through `PRICE.getPriceIn(OHM, reserve)` and
        // its `addAsset` probes the resolution, so both reserves must resolve in the
        // PRICE module. The USDe registration is performed by the price_admin role
        // holder through the PriceConfig v2 policy before the proposal is queued.
        address priceModule = address(Kernel(KERNEL).getModuleForKeycode(toKeycode("PRICE")));
        _requireReservePriceable(priceModule, USDS);
        _requireReservePriceable(priceModule, USDE);

        // YRF v1.2 must occupy its Heart slot, so that the swap below replaces the
        // intended task.
        (address task, ) = IPeriodicTaskManager(HEART).getPeriodicTaskAtIndex(HEART_YRF_TASK_INDEX);
        if (task != YIELD_REPO_V1)
            revert UnexpectedHeartTask(HEART_YRF_TASK_INDEX, YIELD_REPO_V1, task);
    }

    /// @dev Reverts with `ReserveNotPriceable` when `PRICE.getPriceIn(OHM, reserve_)`
    ///      reverts or returns zero.
    function _requireReservePriceable(address priceModule_, address reserve_) internal view {
        try IPRICEv2(priceModule_).getPriceIn(OHM, reserve_) returns (uint256 reservePrice) {
            if (reservePrice != 0) return;
        } catch {} // solhint-disable-line no-empty-blocks
        revert ReserveNotPriceable(reserve_);
    }

    /// @dev Wires the config timelock to the facility and enables the timelock, the backing
    ///      oracle, and the facility.
    function _enableV2Stack() internal {
        // 2. Wire and enable the config timelock
        IYieldRepurchaseFacilityConfigTimelock(CONFIG_TIMELOCK).setFacility(YIELD_REPO);
        IEnabler(CONFIG_TIMELOCK).enable("");

        // 3. Enable the backing oracle before the facility, so that the facility's
        //    price gate never sees a zero backing.
        IEnabler(BACKING_ORACLE).enable(abi.encode(BACKING));

        // 4. Enable the facility with an empty seed array. The ordering is load-bearing:
        //    `enable` performs a full cycle reset that zeroes the next yields and
        //    refreshes the snapshots of the registered enabled assets, so it runs
        //    strictly before the `addAsset` seeding.
        IEnabler(YIELD_REPO).enable(
            abi.encode(
                INITIAL_DISCOUNT,
                MAX_PRICE_PREMIUM,
                new IYieldRepurchaseFacilityV2.NextYieldSeed[](0)
            )
        );
    }

    /// @dev Shuts down YRF v1.2: burns its OHM balance and sweeps its USDS and sUSDS to
    ///      the treasury. Requires the `loop_daddy` role, granted to this contract by the
    ///      proposal for the duration of the activation.
    function _shutdownV1() internal {
        address[] memory tokensToTransfer = new address[](2);
        tokensToTransfer[0] = USDS;
        tokensToTransfer[1] = SUSDS;
        IYieldRepoV1(YIELD_REPO_V1).shutdown(tokensToTransfer);
    }

    /// @dev Registers sUSDS (the backing vault, continuing the v1.2 accounting) and
    ///      sUSDe (a sell-shares yield asset).
    /// @param susdsSeedBalance_ The sUSDS reserve balance snapshot, read from v1.2.
    /// @param susdsSeedRate_ The sUSDS conversion rate snapshot, read from v1.2.
    /// @param susdsSeedYield_ The sUSDS next yield, read from v1.2.
    function _registerAssets(
        uint256 susdsSeedBalance_,
        uint256 susdsSeedRate_,
        uint256 susdsSeedYield_
    ) internal {
        IYieldRepurchaseFacilityV2 yieldRepo = IYieldRepurchaseFacilityV2(YIELD_REPO);

        // 7. sUSDS continues the v1.2 accounting: the snapshots are carried over
        //    verbatim, so the first v2 weekly reset projects the yield accrued since the
        //    last v1.2 weekly reset, and the projected v1.2 `nextYield` is seeded as the
        //    v2 next yield.
        yieldRepo.addAsset(
            SUSDS,
            SUSDS_BUYBACK_SHARE,
            susdsSeedBalance_,
            susdsSeedRate_,
            susdsSeedYield_,
            false, // sellShares
            true // setAsBackingVault
        );

        // 8. sUSDe has no v1 history: the snapshots must start at the live values (they
        //    are the accounting baseline of the yield projections), while the next-yield
        //    seed is the fixed governance estimate `SUSDE_NEXT_YIELD_SEED`. The asset
        //    sells shares because the sUSDe redeem reverts while the Ethena cooldown is
        //    active.
        address trsry = address(Kernel(KERNEL).getModuleForKeycode(toKeycode("TRSRY")));
        uint256 susdeSeedBalance = IERC4626(SUSDE).previewRedeem(IERC4626(SUSDE).balanceOf(trsry));
        uint256 susdeSeedRate = IERC4626(SUSDE).previewRedeem(1e18);

        yieldRepo.addAsset(
            SUSDE,
            SUSDE_BUYBACK_SHARE,
            susdeSeedBalance,
            susdeSeedRate,
            SUSDE_NEXT_YIELD_SEED,
            true, // sellShares
            false // setAsBackingVault
        );
    }

    /// @dev Includes the Cooler v1 Clearinghouses (v1 and v1.1, DAI-denominated) in the
    ///      backing yield: their receivables accrue to USDS through the 1:1 DAI to USDS
    ///      migration.
    function _configureClearinghouses() internal {
        IYieldRepurchaseFacilityV2 yieldRepo = IYieldRepurchaseFacilityV2(YIELD_REPO);

        yieldRepo.includeClearinghouse(CLEARINGHOUSE_V1);
        yieldRepo.includeClearinghouse(CLEARINGHOUSE_V1_1);
    }

    /// @dev Continues the v1.2 week: the epoch counter is set to the v1.2 value, and
    ///      the unspent v1.2 weekly budget (swept to the treasury by the shutdown) is
    ///      credited to the sUSDS weekly budget and covered by a treasury withdrawal.
    /// @param epoch_ The epoch counter read from v1.2.
    /// @param residual_ The unspent v1.2 weekly budget, in USDS (18 decimals).
    function _seedCycle(uint48 epoch_, uint256 residual_) internal {
        // A zero-amount seed reverts in the facility, so the residual seed is added only
        // when it is non-zero.
        uint256 seedCount = residual_ > 0 ? 1 : 0;
        IYieldRepurchaseFacilityV2.WeeklyBudgetSeed[]
            memory seeds = new IYieldRepurchaseFacilityV2.WeeklyBudgetSeed[](seedCount);
        if (seedCount != 0) {
            seeds[0] = IYieldRepurchaseFacilityV2.WeeklyBudgetSeed({
                vault: SUSDS,
                weeklyBudget: residual_
            });
        }

        IYieldRepurchaseFacilityV2(YIELD_REPO).seedCycle(epoch_, seeds);
    }

    /// @dev Replaces YRF v1.2 with the v2 facility in the Heart periodic task slot. The
    ///      v1.2 task is registered with the custom `endEpoch` selector; the v2 facility
    ///      implements `IPeriodicTask` and is registered with the default selector
    ///      (`bytes4(0)`), which makes the Heart verify the interface through ERC165.
    function _swapHeartTask() internal {
        IPeriodicTaskManager heart = IPeriodicTaskManager(HEART);
        uint256 taskCountBefore = heart.getPeriodicTaskCount();

        heart.removePeriodicTaskAtIndex(HEART_YRF_TASK_INDEX);
        heart.addPeriodicTaskAtIndex(YIELD_REPO, bytes4(0), HEART_YRF_TASK_INDEX);

        // Post-conditions: the slot holds the v2 facility and the pipeline length is
        // unchanged.
        (address task, ) = heart.getPeriodicTaskAtIndex(HEART_YRF_TASK_INDEX);
        if (task != YIELD_REPO) revert UnexpectedHeartTask(HEART_YRF_TASK_INDEX, YIELD_REPO, task);

        uint256 taskCountAfter = heart.getPeriodicTaskCount();
        if (taskCountAfter != taskCountBefore)
            revert HeartTaskCountChanged(taskCountBefore, taskCountAfter);
    }
}
