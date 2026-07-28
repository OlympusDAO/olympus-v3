// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBondCallback} from "src/interfaces/IBondCallback.sol";
import {IBondSDA} from "src/interfaces/IBondSDA.sol";
import {IBurnableERC20} from "src/interfaces/IBurnableERC20.sol";
import {IERC4626} from "@openzeppelin-5.3.0/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-5.3.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IBasicRescueable} from "src/interfaces/IBasicRescueable.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

// Libraries
import {Errors} from "src/libraries/Errors.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {Math} from "@openzeppelin-5.3.0/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin-5.3.0/token/ERC20/utils/SafeERC20.sol";
import {YRFBondMarketLib} from "src/policies/YieldRepurchaseFacility/YRFBondMarketLib.sol";
import {YRFClearinghouseLib} from "src/policies/YieldRepurchaseFacility/YRFClearinghouseLib.sol";

// Modules
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {PRICEv1} from "src/modules/PRICE/PRICE.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ERC20 as SolmateERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {ReEnabler} from "src/bases/ReEnabler.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";

// Constants
import {HEART_ROLE, YRF_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title YieldRepurchaseFacilityV2
/// @notice Multi-asset Yield Repurchase Facility (YRF), version 2.
/// @dev The facility runs on the heart beat: each `execute` advances the epoch counter,
///      every third epoch runs a daily cycle that opens 24-hour bond markets buying OHM
///      with the reserves, and the 21st epoch first runs the weekly reset, which injects
///      the projected yield into the per-vault budgets and prefunds them from the
///      treasury. The purchased OHM is burned against a treasury withdrawal priced by
///      the backing oracle. Markets are not opened while the oracle price is below the
///      backing.
///
///      Lifecycle:
///      - `enable` (admin) performs a full restart: the budgets and yields of the enabled
///        assets are zeroed, their yield snapshots are refreshed, and the epoch counter
///        is set so that the next `execute` performs a weekly reset. The payload may seed
///        the per-vault `nextYield` values (an empty seed array restarts with zero
///        yields). Funds held for the enabled assets are re-absorbed into the budget by
///        the pool-value sync of that reset.
///      - `disable` (emergency or admin) only halts `execute` and `callback`; the funds and
///        the accounting state are left in place.
///      - `reEnable` (yrf_admin) resumes the interrupted week in place, and is only
///        available within the grace window after the disable.
///      - `returnFundsToTreasury` (emergency or admin) burns the purchased OHM and returns
///        the held balances to the treasury while the facility is disabled, sweeping each
///        vault independently.
///      - `seedCycle` (admin, one-shot) sets the epoch counter and seeds the running
///        week's budgets, covering them with treasury withdrawals.
///
///      The admin role is expected to be held only by the OCG timelock, so every
///      admin-gated function of this contract is de-facto timelocked.
contract YieldRepurchaseFacilityV2 is
    Policy,
    ReEnabler,
    PolicyEnablerV2,
    ReEnablerGracePeriod,
    ReentrancyGuardTransient,
    IBondCallback,
    IPeriodicTask,
    IBasicRescueable,
    IVersioned,
    IYieldRepurchaseFacilityV2
{
    using SafeERC20 for IERC20;
    using FullMath for uint256;

    // ============ CONSTANTS ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2
    uint32 public constant override MAX_GRACE_PERIOD = 7 days;

    /// @notice Number of epochs per week (3 per day * 7 days).
    uint48 private constant _EPOCH_LENGTH = 21;

    /// @notice Number of epochs per day.
    uint48 private constant _EPOCHS_PER_DAY = 3;

    /// @notice Number of days per week.
    uint256 private constant _DAYS_PER_WEEK = 7;

    /// @notice Precision denominator for the yield buyback share (`1e18` = 100%).
    uint256 private constant _ONE_HUNDRED_PERCENT = 1e18;

    /// @notice Minimum length of the `enable` payload.
    /// @dev Three 32-byte words: `initialDiscount`, the seed array offset, and the seed
    ///      array length.
    uint256 private constant _MIN_ENABLE_PARAMS_LENGTH = 96;

    /// @notice Maximum reserve token decimals supported when adding a vault.
    uint8 private constant _MAX_RESERVE_DECIMALS = 18;

    /// @notice Decimals of the backing value, and therefore the decimals the `PRICE` oracle
    ///         must report so that the oracle price can be compared against the backing.
    uint8 private constant _BACKING_DECIMALS = 18;

    /// @notice Keycode for the TRSRY module dependency.
    /// @dev Pre-computed to avoid the runtime cost of `toKeycode("TRSRY")`.
    Keycode internal constant _KEYCODE_TRSRY = Keycode.wrap(0x5452535259); // toKeycode("TRSRY")

    /// @notice Keycode for the PRICE module dependency.
    /// @dev Pre-computed to avoid the runtime cost of `toKeycode("PRICE")`.
    Keycode internal constant _KEYCODE_PRICE = Keycode.wrap(0x5052494345); // toKeycode("PRICE")

    /// @notice Keycode for the CHREG module dependency.
    /// @dev Pre-computed to avoid the runtime cost of `toKeycode("CHREG")`.
    Keycode internal constant _KEYCODE_CHREG = Keycode.wrap(0x4348524547); // toKeycode("CHREG")

    /// @notice Keycode for the ROLES module dependency.
    /// @dev Pre-computed to avoid the runtime cost of `toKeycode("ROLES")`.
    Keycode internal constant _KEYCODE_ROLES = Keycode.wrap(0x524f4c4553); // toKeycode("ROLES")

    // ============ IMMUTABLES ============ //

    /// @notice The OHM token.
    IERC20 private immutable _OHM;

    /// @notice The cached OHM decimals (9 on mainnet).
    uint8 private immutable _OHM_DECIMALS;

    /// @notice The YRF timelock authorized for the timelocked operational functions.
    /// @dev The functions `setYieldBuybackShare`, `setInitialDiscount`, `enableAsset`,
    ///      `disableAsset`, `excludeClearinghouse`, `increaseClearinghouseOffset`, and
    ///      `decreaseNextYield` trust only this address for the timelocked path, so the
    ///      yrf_admin reaches them through the timelock's queue.
    ///      The admin (expected to be held only by the OCG timelock) keeps a direct path to them.
    address private immutable _TIMELOCK;

    // ============ MODULES ============ //

    TRSRYv1 internal TRSRY;
    PRICEv1 internal PRICE;
    CHREGv1 internal CHREG;

    /// @notice Cached `PRICE.decimals()`.
    uint8 internal _oracleDecimals;

    // ============ STATE ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2
    address public override backingOracle;

    /// @inheritdoc IYieldRepurchaseFacilityV2
    address public override teller;

    /// @inheritdoc IYieldRepurchaseFacilityV2
    address public override bondAuctioneer;

    /// @inheritdoc IYieldRepurchaseFacilityV2
    address public override backingVault;

    /// @inheritdoc IYieldRepurchaseFacilityV2
    uint256 public override initialDiscount;

    /// @notice Running epoch counter, in the range `[0, 21)`.
    uint48 internal _epoch;

    /// @notice Whether the one-shot `seedCycle` has been consumed.
    /// @dev The flag is never reset, including by an `enable` restart.
    bool internal _cycleSeeded;

    /// @notice Accumulated OHM purchased via bond markets, not yet processed.
    /// @dev The OHM balance always covers this amount: `callback` verifies the quote
    ///      transfer against it before accounting.
    uint256 internal _ohmPurchased;

    /// @notice Per-vault configuration and state.
    mapping(address vault => ReserveAsset config) internal _assetConfigs;

    /// @notice Ordered list of registered vault addresses.
    address[] internal _vaults;

    /// @notice Cumulative offset applied to a Clearinghouse's `principalReceivables`.
    mapping(address clearinghouse => uint256 offset) internal _receivablesOffsets;

    /// @notice Clearinghouses counted toward the backing yield regardless of their reserve
    ///         token.
    mapping(address clearinghouse => bool included) internal _includedClearinghouses;

    /// @notice The vault that funds each open bond market created by this facility.
    /// @dev Set on market creation; a non-zero entry implicitly validates that the market
    ///      was created here.
    mapping(uint256 marketId => address vault) internal _marketVaults;

    /// @notice Cumulative input/output amounts per bond market.
    /// @dev `[0]` = OHM in (quote), `[1]` = reserve out (payout).
    mapping(uint256 marketId => uint256[2] amounts) internal _amountsPerMarket;

    // ============ SETUP ============ //

    /// @dev Reverts if:
    ///      - `kernel_`, `ohm_`, `timelock_`, `backingOracle_`, `bondAuctioneer_`, or
    ///        `teller_` is the zero address.
    ///      - `gracePeriod_` is zero or not less than `MAX_GRACE_PERIOD`.
    /// @param kernel_ The Olympus Kernel.
    /// @param ohm_ The OHM token address.
    /// @param backingOracle_ The OHM backing oracle policy address.
    /// @param bondAuctioneer_ The Bond Protocol SDA auctioneer.
    /// @param teller_ The Bond Protocol teller.
    /// @param timelock_ The YRF timelock policy authorized for the operational functions.
    /// @param gracePeriod_ The initial re-enable grace window, in seconds.
    constructor(
        Kernel kernel_,
        address ohm_,
        address backingOracle_,
        address bondAuctioneer_,
        address teller_,
        address timelock_,
        uint32 gracePeriod_
    ) Policy(kernel_) ReEnablerGracePeriod(gracePeriod_) {
        _requireNonzeroAddress(address(kernel_), "kernel");
        _requireNonzeroAddress(ohm_, "ohm");
        _requireNonzeroAddress(timelock_, "timelock");
        _requireValidGracePeriod(gracePeriod_);

        _OHM = IERC20(ohm_);
        _OHM_DECIMALS = IERC20Metadata(ohm_).decimals();
        _TIMELOCK = timelock_;

        _setBackingOracle(backingOracle_);
        _setBondContracts(bondAuctioneer_, teller_);

        // Disabled by default by EnablerV2
    }

    /// @inheritdoc Policy
    /// @dev Reverts if:
    ///      - Any of the TRSRY, PRICE, CHREG, or ROLES modules does not report major
    ///        version 1.
    ///      - `PRICE.decimals()` is not 18, the decimals of the backing value.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = _KEYCODE_TRSRY;
        dependencies[1] = _KEYCODE_PRICE;
        dependencies[2] = _KEYCODE_CHREG;
        dependencies[3] = _KEYCODE_ROLES;

        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        PRICE = PRICEv1(getModuleAddress(dependencies[1]));
        CHREG = CHREGv1(getModuleAddress(dependencies[2]));
        ROLES = ROLESv1(getModuleAddress(dependencies[3]));

        (uint8 trsryMajor, ) = TRSRY.VERSION();
        (uint8 priceMajor, ) = PRICE.VERSION();
        (uint8 chregMajor, ) = CHREG.VERSION();
        (uint8 rolesMajor, ) = ROLES.VERSION();
        if (trsryMajor != 1 || priceMajor != 1 || chregMajor != 1 || rolesMajor != 1)
            revert Policy_WrongModuleVersion(abi.encode([1, 1, 1, 1]));

        // The oracle price is compared against the 18-decimal backing value, so the
        // oracle must report 18 decimals.
        _oracleDecimals = PRICE.decimals();
        if (_oracleDecimals != _BACKING_DECIMALS)
            revert IYieldRepurchaseFacilityV2_UnsupportedOracleDecimals();

        return dependencies;
    }

    /// @inheritdoc Policy
    /// @dev The facility requests only the TRSRY withdrawal permissions
    ///      (`withdrawReserves` and `increaseWithdrawApproval`).
    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](2);
        permissions[0] = Permissions({
            keycode: _KEYCODE_TRSRY,
            funcSelector: TRSRYv1.withdrawReserves.selector
        });
        permissions[1] = Permissions({
            keycode: _KEYCODE_TRSRY,
            funcSelector: TRSRYv1.increaseWithdrawApproval.selector
        });
        return permissions;
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (2, 0);
    }

    // ============ ROLE GATES ============ //

    /// @notice Reverts unless the caller holds the yrf_admin role or the admin role.
    modifier onlyYrfAdminOrAdminRole() {
        _requireAuthorized(!_hasRole(msg.sender, YRF_ADMIN_ROLE) && !_isAdmin(msg.sender));
        _;
    }

    /// @notice Reverts unless the caller is the YRF timelock or holds the admin role.
    modifier onlyTimelockOrAdminRole() {
        _requireAuthorized(msg.sender != _TIMELOCK && !_isAdmin(msg.sender));
        _;
    }

    // ============ ENABLE / DISABLE ============ //

    /// @inheritdoc EnablerV2
    /// @dev Performs a full restart of the epoch cycle: the budgets and yields of the
    ///      enabled assets are zeroed, their yield snapshots are refreshed, and the epoch
    ///      counter is set so that the next `execute` performs a weekly reset. Disabled
    ///      assets are left untouched; `enableAsset` resets them when they are enabled.
    ///      The payload may seed the next yield of enabled vaults; with an empty seed
    ///      array every enabled vault restarts with a zero yield. Funds held for the
    ///      enabled assets are re-absorbed into the budget by the pool-value sync of the
    ///      first weekly reset. For resuming an interrupted week after a disable, see
    ///      `reEnable`.
    ///
    ///      Reverts if:
    ///      - The payload is shorter than the minimum `abi.encode(uint256, NextYieldSeed[])`.
    ///      - The payload does not `abi.decode` as `(uint256, NextYieldSeed[])`.
    ///      - The initial discount is not less than 100% (`1e18`).
    ///      - A seed references an unregistered or disabled vault.
    ///      - An enabled vault reverts on `previewRedeem` or `balanceOf`.
    function _beforeEnable(bytes calldata data_) internal override {
        if (data_.length < _MIN_ENABLE_PARAMS_LENGTH)
            revert IYieldRepurchaseFacilityV2_InvalidEnableDataLength();

        (uint256 initialDiscount_, NextYieldSeed[] memory nextYieldSeeds) = abi.decode(
            data_,
            (uint256, NextYieldSeed[])
        );
        _setInitialDiscount(initialDiscount_);

        _resetCycle(nextYieldSeeds);
    }

    /// @notice Restarts the weekly cycle: zeroes the budgets and yields of the enabled
    ///         assets, applies the supplied next-yield seeds, refreshes their yield
    ///         snapshots, and rewinds the epoch counter so that the next `execute`
    ///         performs a weekly reset.
    /// @dev Disabled assets are not touched and are not seedable: a seed for a disabled
    ///      vault would be erased by the reset `enableAsset` performs, so it is rejected
    ///      instead. A single `NextYieldSet` event with the resulting value is emitted
    ///      per enabled vault; when the seed array contains duplicates, the last entry
    ///      wins.
    ///
    ///      Reverts if a seed references an unregistered or disabled vault.
    /// @param nextYieldSeeds_ The per-vault `nextYield` values to apply after the reset.
    function _resetCycle(NextYieldSeed[] memory nextYieldSeeds_) private {
        address[] storage vaults = _vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            address vault = vaults[i];
            ReserveAsset storage config = _assetConfigs[vault];
            if (!config.isAssetEnabled) continue;

            config.nextYield = 0;
            config.weeklyBudgetRemaining = 0;
            _refreshSnapshots(vault, config);
        }

        uint256 seedsLength = nextYieldSeeds_.length;
        for (uint256 i = 0; i < seedsLength; ++i) {
            NextYieldSeed memory seed = nextYieldSeeds_[i];
            ReserveAsset storage config = _requireRegistered(seed.vault);
            _requireAssetEnabled(config);
            config.nextYield = seed.nextYield;
        }

        for (uint256 i = 0; i < vaultsLength; ++i) {
            ReserveAsset storage config = _assetConfigs[vaults[i]];
            if (!config.isAssetEnabled) continue;
            _setNextYield(config, config.nextYield);
        }

        _epoch = _EPOCH_LENGTH - 1;
    }

    // `_beforeDisable` is deliberately not overridden: disabling only halts `execute` and
    // `callback`, leaving the funds and the accounting state in place so that `reEnable`
    // can resume the interrupted week. Use `returnFundsToTreasury` to sweep the funds
    // after a disable when holding them on the facility is a concern.

    /// @inheritdoc ReEnabler
    /// @dev The re-enable is restricted to the yrf_admin, the operational role of the
    ///      facility; the admin restarts through `enable` instead.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the yrf_admin role.
    function _authorizeReEnable() internal view override {
        _requireRole(msg.sender, YRF_ADMIN_ROLE);
    }

    /// @inheritdoc ReEnabler
    /// @dev Resumes the interrupted epoch cycle in place: the epoch counter, the per-vault
    ///      budgets, the prefunded balances, and the yield snapshots are intentionally left
    ///      untouched, so the facility continues the week where it stopped. Epochs advance
    ///      only while the facility is enabled, so the week is stretched by the downtime;
    ///      the vault yield accrued during the downtime is captured by the next weekly
    ///      reset, and `nextYield` is injected into the weekly budget exactly once per
    ///      reset regardless of the downtime. The grace-window check runs through
    ///      `super`.
    function _beforeReEnable() internal override(ReEnabler, ReEnablerGracePeriod) {
        super._beforeReEnable();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev The admin role is expected to be held only by the OCG timelock, so the grace
    ///      window is de-facto timelocked.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the admin role.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Bounds the window: the grace period must be strictly shorter than one weekly
    ///      cycle (`MAX_GRACE_PERIOD`).
    ///
    ///      Reverts if:
    ///      - The contract is disabled.
    ///      - The caller does not hold the admin role.
    ///      - `period_` is zero.
    ///      - `period_` is not less than `MAX_GRACE_PERIOD`.
    function setGracePeriod(uint32 period_) public override givenEnabled {
        _requireValidGracePeriod(period_);
        super.setGracePeriod(period_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev The function complements the `disable`, which only halts operation
    ///      and leaves the funds in place so that `reEnable` can resume the interrupted
    ///      week. Call this function after a disable when the facility is not expected to
    ///      be re-enabled soon, or when holding funds on the facility is a concern. The
    ///      per-vault `nextYield` is intentionally preserved, so a later `reEnable` or
    ///      `enable` refunds the facility from the treasury at the next weekly reset.
    ///
    ///      The sweep of each vault is isolated through a self-call: a vault whose sweep
    ///      reverts is skipped with a `FundsReturnSkipped` event, keeping its balances and
    ///      accounting in place, and is retried by the next call. The OHM burn and
    ///      transfer are not isolated: OHM is a protocol-owned token whose balance always
    ///      covers the tracked purchased amount.
    ///
    ///      The function reverts if:
    ///      - The contract is enabled.
    ///      - The caller holds neither the emergency role nor the admin role.
    function returnFundsToTreasury() external override givenDisabled onlyEmergencyOrAdminRole {
        uint256 purchasedOhm = _ohmPurchased;
        if (purchasedOhm != 0) {
            _ohmPurchased = 0;
            IBurnableERC20(address(_OHM)).burn(purchasedOhm);
        }

        // The OHM remaining after the burn is untracked (donated) balance
        _sweepToTrsry(address(_OHM));

        address[] storage vaults = _vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            address vault = vaults[i];
            try this.selfReturnVaultFunds(vault) {} catch {
                emit FundsReturnSkipped(vault);
            }
        }

        emit FundsReturnedToTreasury(purchasedOhm);
    }

    /// @notice Returns a vault's share and reserve balances to the treasury and zeroes
    ///         the vault's holdings accounting and weekly budget.
    /// @dev External only for the self-call isolation in `returnFundsToTreasury`.
    ///
    ///      Reverts if the caller is not the facility itself.
    /// @param vault_ The vault to sweep.
    function selfReturnVaultFunds(address vault_) external {
        _requireCaller(address(this));

        ReserveAsset storage config = _assetConfigs[vault_];

        _returnBalancesToTrsry(vault_, config.reserve);

        config.prefundedShares = 0;
        config.prefundedReserve = 0;
        config.weeklyBudgetRemaining = 0;
    }

    // ============ PERIODIC TASK ============ //

    /// @inheritdoc IPeriodicTask
    /// @dev The beat must survive a misbehaving vault: the processing of each vault and the
    ///      processing of the purchased OHM are isolated through self-calls, so a revert
    ///      skips the affected step with an event and the remaining steps and the heartbeat
    ///      continue. Skipped work is retried on the following beats. The `PRICE` and
    ///      backing oracle reads are deliberately not isolated: both are protocol-owned
    ///      dependencies, and a failure there is a configuration error that should surface
    ///      loudly.
    ///
    ///      Market pricing reads `PRICE.getLastPrice()`, the stored observation, without a
    ///      freshness check: `Heart.beat()` refreshes it through `PRICE.updateMovingAverage()`
    ///      in the same transaction before the periodic tasks run, and reverts on a stale
    ///      Chainlink feed. A caller that invokes `execute` outside the beat therefore
    ///      prices markets with the observation of the last beat, so the heart role should
    ///      be granted only to the Heart contract.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the heart role.
    ///      - The `PRICE.getLastPrice()` or the backing oracle `backing()` read reverts.
    function execute() external override nonReentrant onlyRole(HEART_ROLE) {
        if (!isEnabled) return;
        _epoch += 1;

        if (_epoch % _EPOCHS_PER_DAY != 0) return;

        if (_epoch == _EPOCH_LENGTH) _weeklyReset();

        // The purchased OHM is processed before the price gate, so the burn continues
        // while markets are skipped.
        try this.selfProcessOhmPurchases() {} catch {
            emit OhmPurchasesProcessingSkipped();
        }

        // Below the backing, each purchase would release more backing on the burn than
        // the reserve it spends, growing the budget on every cycle, so market creation
        // is skipped for every vault. Skipping before any redeem also keeps the reserve
        // in the yield-earning vaults; the unspent budget rolls into the following days.
        uint256 oraclePrice = PRICE.getLastPrice();
        uint256 backing = _backing();
        if (oraclePrice == 0 || oraclePrice < backing) return;

        // In the range [1, 7]: the weekly reset has wrapped the epoch to zero
        uint256 daysRemaining = _DAYS_PER_WEEK - uint256(_epoch / _EPOCHS_PER_DAY);

        address[] storage vaults = _vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            address vault = vaults[i];
            if (!_assetConfigs[vault].isAssetEnabled) continue;

            try this.selfProcessVaultDaily(vault, daysRemaining, oraclePrice) {} catch {
                emit DailyCycleSkipped(vault);
            }
        }
    }

    /// @notice Runs the daily cycle of a single vault.
    /// @dev External only for the self-call isolation in `execute`. The function is
    ///      intentionally not `nonReentrant`: it executes within the guard held by
    ///      `execute`.
    ///
    ///      Reverts if the caller is not the facility itself.
    /// @param vault_ The vault to process.
    /// @param daysRemaining_ The number of daily cycles remaining in the week, including
    ///        this one.
    /// @param oraclePrice_ The oracle price used for the market pricing, in oracle
    ///        decimals.
    function selfProcessVaultDaily(
        address vault_,
        uint256 daysRemaining_,
        uint256 oraclePrice_
    ) external {
        _requireCaller(address(this));

        _executeDailyCycle(vault_, _assetConfigs[vault_], daysRemaining_, oraclePrice_);
    }

    /// @notice Performs the weekly reset: re-absorbs the funds held by the facility into
    ///         the weekly budget, injects the projected yield, refreshes the yield
    ///         snapshots, and prefunds the budget from the treasury.
    /// @dev Every unit of vault yield enters the budget exactly once, at the first weekly reset
    ///      after it accrues: the yield on the treasury-held shares through the `nextYield`
    ///      projection, and the yield on the shares held by the facility through the pool-value
    ///      sync (`budget = max(budget, poolValue)`). The daily bids deliberately spend the fixed
    ///      budget counter, so the intra-week appreciation of the prefunded shares is not spent
    ///      within the running week; it is captured by the sync of the following reset.
    ///
    ///      The processing of each vault is isolated through a self-call: a vault whose processing
    ///      reverts is skipped for the week with a `WeeklyResetSkipped` event and retried at the
    ///      following reset. The stored `nextYield` of a skipped vault stays in place and is
    ///      injected once, at the first reset that succeeds. A skipped reset of the backing vault
    ///      forfeits that week's Clearinghouse interest: the following reset projects the interest
    ///      anew, for one week only.
    function _weeklyReset() private {
        _epoch = 0;

        address backingReserve = _backingReserve();
        uint256 clearinghouseYield = YRFClearinghouseLib.clearinghouseYield(
            CHREG,
            backingReserve,
            _receivablesOffsets,
            _includedClearinghouses
        );
        YRFClearinghouseLib.emitClearinghouseMismatches(
            CHREG,
            backingReserve,
            _includedClearinghouses
        );

        address[] storage vaults = _vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            address vault = vaults[i];
            if (!_assetConfigs[vault].isAssetEnabled) continue;

            try this.selfProcessVaultReset(vault, clearinghouseYield) {} catch {
                emit WeeklyResetSkipped(vault);
            }
        }
    }

    /// @notice Runs the weekly reset of a single vault: re-absorbs the funds held by the
    ///         facility into the weekly budget, injects the projected yield, refreshes the
    ///         yield snapshots, and prefunds the budget from the treasury.
    /// @dev External only for the self-call isolation in `_weeklyReset`. The function is
    ///      intentionally not `nonReentrant`: it executes within the guard held by
    ///      `execute`.
    ///
    ///      Reverts if the caller is not the facility itself.
    /// @param vault_ The vault to reset.
    /// @param clearinghouseYield_ The weekly Clearinghouse interest credited to the
    ///        backing vault, in backing reserve units.
    function selfProcessVaultReset(address vault_, uint256 clearinghouseYield_) external {
        _requireCaller(address(this));

        ReserveAsset storage config = _assetConfigs[vault_];

        // The re-mark commits the appreciation of the facility-held pool to buybacks. It
        // never lowers the budget, so an unfunded prefund shortfall is preserved and
        // retried by the prefund below.
        uint256 poolValue = _previewRedeem(vault_, config.prefundedShares) +
            config.prefundedReserve;
        if (poolValue > config.weeklyBudgetRemaining) {
            config.weeklyBudgetRemaining = poolValue;
        }

        config.weeklyBudgetRemaining += config.nextYield;

        // The projection reads the stored snapshots against the current rate, so it must
        // run before the snapshots are refreshed below.
        uint256 newNextYield = _projectNextYield(config, clearinghouseYield_);

        _setNextYield(config, newNextYield);

        config.lastConversionRate = _conversionRate(config);

        _prefundVault(vault_, config);

        // The balance snapshot is taken after the prefund, so it excludes the shares
        // moved to the facility.
        config.lastReserveBalance = _getProtocolReserveBalance(vault_);
    }

    /// @notice Withdraws vault shares from the treasury so that the facility's tracked
    ///         holdings cover the weekly budget.
    /// @dev The target is `previewWithdraw(budget - prefundedReserve)` shares (rounded up
    ///      by the vault), reduced by the shares already held. The withdrawal is capped
    ///      at the treasury balance, with a `PrefundShortfall` event on the cap.
    function _prefundVault(address vault_, ReserveAsset storage config_) private {
        uint256 budget = config_.weeklyBudgetRemaining;
        if (budget == 0) return;

        // The held reserve already covers part of the budget, so the unsold remainder
        // of a previous bid is not funded again.
        uint256 heldReserve = config_.prefundedReserve;
        if (heldReserve >= budget) return;

        uint256 targetShares = _previewWithdraw(vault_, budget - heldReserve);
        uint256 currentShares = config_.prefundedShares;
        if (targetShares <= currentShares) return;

        uint256 sharesToWithdraw = targetShares - currentShares;
        uint256 trsryBalance = _trsryBalance(vault_);
        if (sharesToWithdraw > trsryBalance) {
            // The unfunded gap stays in the budget and is retried at the next reset
            emit PrefundShortfall(vault_, sharesToWithdraw, trsryBalance);
            sharesToWithdraw = trsryBalance;
        }
        if (sharesToWithdraw == 0) return;

        _withdrawShares(vault_, sharesToWithdraw);
        config_.prefundedShares = currentShares + sharesToWithdraw;
    }

    /// @notice Opens the daily bond market of a vault.
    /// @dev The bid is `weeklyBudgetRemaining / daysRemaining_` (floor). For a
    ///      sell-shares asset the market capacity is the smaller of
    ///      `previewWithdraw(bid)` and the prefunded shares, denominated in shares.
    ///      Otherwise the reserve shortfall is redeemed from the prefunded shares first,
    ///      and the bid is clamped to the reserve actually held when the redeem falls
    ///      short. A zero budget, bid, or capacity skips the market.
    function _executeDailyCycle(
        address vault_,
        ReserveAsset storage config_,
        uint256 daysRemaining_,
        uint256 oraclePrice_
    ) private {
        uint256 weeklyBudgetRemaining = config_.weeklyBudgetRemaining;
        if (weeklyBudgetRemaining == 0) return;

        uint256 bidAmount = weeklyBudgetRemaining / daysRemaining_;
        if (bidAmount == 0) return;

        if (config_.sellShares) {
            uint256 capacityShares = Math.min(
                _previewWithdraw(vault_, bidAmount),
                config_.prefundedShares
            );
            if (capacityShares == 0) return;

            _createMarket(vault_, config_, capacityShares, oraclePrice_);
        } else {
            address reserve_ = config_.reserve;
            uint256 currentReserve = _selfBalance(reserve_);

            if (currentReserve < bidAmount) {
                uint256 deficit = bidAmount - currentReserve;
                uint256 redeemed = _redeemFromPrefunded(vault_, reserve_, deficit, config_);

                if (redeemed < deficit) {
                    bidAmount = currentReserve + redeemed;
                }
            }

            if (bidAmount == 0) return;

            _createMarket(vault_, config_, bidAmount, oraclePrice_);
        }
    }

    /// @notice Redeems vault shares through the checked self-call.
    /// @dev On a failed redeem the shares are kept, `RedeemFailed` is emitted, and zero
    ///      is reported as both the received and the used amount.
    /// @return received The reserve amount received.
    /// @return used The share amount consumed by the redeem.
    function _redeemShares(
        address vault_,
        address reserve_,
        uint256 shares_
    ) private returns (uint256 received, uint256 used) {
        if (shares_ == 0) return (0, 0);

        try this.selfRedeemChecked(vault_, reserve_, shares_) returns (uint256 received_) {
            return (received_, shares_);
        } catch {
            // The failed self-call rolled back the redeem, so all shares are still held
            emit RedeemFailed(vault_, shares_);
            return (0, 0);
        }
    }

    /// @notice Redeems vault shares and verifies the received reserve against the
    ///         preview.
    /// @dev External only for the self-call isolation in `_redeemShares`. The function is
    ///      intentionally not `nonReentrant`: it executes within the guard held by the
    ///      external entry point. The received amount is measured as the reserve balance
    ///      delta.
    ///
    ///      Reverts if:
    ///      - The caller is not the facility itself.
    ///      - The received reserve is below `previewRedeem(shares_)`.
    /// @param vault_ The vault to redeem from.
    /// @param reserve_ The vault's reserve token.
    /// @param shares_ The share amount to redeem.
    /// @return received The reserve amount received.
    function selfRedeemChecked(
        address vault_,
        address reserve_,
        uint256 shares_
    ) external returns (uint256 received) {
        _requireCaller(address(this));

        uint256 expected = _previewRedeem(vault_, shares_);
        uint256 reserveBefore = _selfBalance(reserve_);
        IERC4626(vault_).redeem(shares_, address(this), address(this));
        received = _selfBalance(reserve_) - reserveBefore;

        if (received < expected)
            revert IYieldRepurchaseFacilityV2_InsufficientRedeem(vault_, expected, received);
    }

    /// @notice Redeems prefunded shares to cover a reserve deficit.
    /// @dev The share amount is `previewWithdraw(deficit_)` (rounded up by the vault),
    ///      capped at the prefunded shares. The consumed shares and the received reserve
    ///      are moved between the tracked counters.
    function _redeemFromPrefunded(
        address vault_,
        address reserve_,
        uint256 deficit_,
        ReserveAsset storage config_
    ) private returns (uint256 redeemed) {
        if (deficit_ == 0) return 0;

        uint256 sharesNeeded = _previewWithdraw(vault_, deficit_);
        uint256 available = config_.prefundedShares;
        uint256 sharesToRedeem = sharesNeeded > available ? available : sharesNeeded;

        uint256 used;
        (redeemed, used) = _redeemShares(vault_, reserve_, sharesToRedeem);
        config_.prefundedShares = available - used;
        config_.prefundedReserve += redeemed;
    }

    /// @notice Withdraws vault shares from the treasury and redeems them for the reserve.
    /// @dev The share amount is `previewWithdraw(amount_)` (rounded up by the vault),
    ///      capped at the treasury balance. Shares that fail to redeem are returned to
    ///      the treasury.
    function _withdrawAndRedeemFresh(
        address vault_,
        address reserve_,
        uint256 amount_
    ) private returns (uint256 received) {
        if (amount_ == 0) return 0;

        uint256 shares = _previewWithdraw(vault_, amount_);
        uint256 trsryBalance = _trsryBalance(vault_);
        if (shares > trsryBalance) shares = trsryBalance;
        if (shares == 0) return 0;

        _withdrawShares(vault_, shares);

        uint256 used;
        (received, used) = _redeemShares(vault_, reserve_, shares);

        // Unredeemed shares would sit untracked on the facility, so they go back to the
        // treasury.
        _transferToTrsry(vault_, shares - used);
    }

    /// @notice Burns the purchased OHM against a fresh backing withdrawal and credits the
    ///         proceeds to the backing vault's budget.
    /// @dev External only for the self-call isolation in `execute`. The function is
    ///      intentionally not `nonReentrant`: it executes within the guard held by
    ///      `execute`. Without a backing vault, or when the scaled backing amount or the
    ///      withdrawal proceeds are zero, the accumulated OHM is kept for later
    ///      processing. When the proceeds fall short of the backing amount, the burn is
    ///      pro-rated down (floor) and the remainder stays accumulated.
    ///
    ///      Reverts if the caller is not the facility itself.
    function selfProcessOhmPurchases() external {
        _requireCaller(address(this));

        uint256 purchased = _ohmPurchased;
        if (purchased == 0) return;

        address backingVault_ = backingVault;
        if (backingVault_ == address(0)) return;

        ReserveAsset storage backingConfig = _assetConfigs[backingVault_];
        uint256 backingPerOhm = _backing();

        // backingAmount18 = purchased (9 dec) * backingPerOhm (18 dec) / 10^9
        // backingAmount   = scaleFrom18(backingAmount18, reserveDecimals).
        uint256 backingAmount18 = purchased.mulDiv(backingPerOhm, 10 ** _OHM_DECIMALS);
        uint256 backingAmount = _scaleFrom18(backingAmount18, backingConfig.reserveDecimals);
        if (backingAmount == 0) return;

        uint256 received = _withdrawAndRedeemFresh(
            backingVault_,
            backingConfig.reserve,
            backingAmount
        );
        if (received == 0) return;

        // The explicit full branch avoids the mulDiv rounding when the withdrawal
        // delivered in full.
        uint256 ohmToBurn = received >= backingAmount
            ? purchased
            : purchased.mulDiv(received, backingAmount);

        _ohmPurchased = purchased - ohmToBurn;
        IBurnableERC20(address(_OHM)).burn(ohmToBurn);

        // The proceeds are held by the facility, so the budget and the tracked reserve
        // grow together.
        backingConfig.weeklyBudgetRemaining += received;
        backingConfig.prefundedReserve += received;

        emit OhmPurchasesProcessed(ohmToBurn, received);
    }

    /// @notice Creates a bond market that sells the vault's payout token for OHM.
    /// @dev The pricing and the submission are performed by the linked `YRFBondMarketLib`
    ///      through a delegatecall, so the facility is the market owner and callback.
    ///      For a sell-shares asset the payout token is the vault share and the oracle
    ///      price is converted to a per-share price through the conversion rate (floor).
    ///      Failures are absorbed: a zero conversion rate or a rejected market submission
    ///      emits `MarketCreationFailed` and keeps the funds with the facility. A created
    ///      market is recorded in `_marketVaults`, which authorizes its callback.
    function _createMarket(
        address vault_,
        ReserveAsset storage config_,
        uint256 bidAmount_,
        uint256 oraclePrice_
    ) private {
        uint256 marketOraclePrice = oraclePrice_;
        address payoutToken = config_.reserve;

        if (config_.sellShares) {
            uint256 conversionRate = _conversionRate(config_);
            if (conversionRate == 0) {
                emit MarketCreationFailed(vault_, bidAmount_);
                return;
            }
            marketOraclePrice = oraclePrice_.mulDiv(10 ** config_.reserveDecimals, conversionRate);
            payoutToken = vault_;
        }

        (bool success, uint256 marketId) = YRFBondMarketLib.createMarket(
            YRFBondMarketLib.MarketConfig({
                auctioneer: IBondSDA(bondAuctioneer),
                payoutToken: payoutToken,
                quoteToken: address(_OHM),
                capacity: bidAmount_,
                oraclePrice: marketOraclePrice,
                initialDiscount: initialDiscount,
                oracleDecimals: _oracleDecimals,
                quoteDecimals: _OHM_DECIMALS,
                payoutDecimals: config_.reserveDecimals
            })
        );

        // The funds stay with the facility and the budget is untouched (only the
        // callback decrements it), so the following cycle retries the market.
        if (!success) {
            emit MarketCreationFailed(vault_, bidAmount_);
            return;
        }

        _marketVaults[marketId] = vault_;

        emit RepoMarket(vault_, marketId, payoutToken, bidAmount_);
    }

    // ============ CONTRIBUTIONS ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev The contribution is measured through balance deltas. A reserve contribution
    ///      is wrapped into vault shares through the vault's `deposit`. The tracked
    ///      holdings grow by the added shares, and the weekly budget grows by their
    ///      redeemable value (floor), so the budget does not exceed the value of the held
    ///      pool and the weekly reset's pool-value sync cannot inject the contribution a
    ///      second time.
    ///
    ///      Reverts if:
    ///      - The contract is disabled.
    ///      - The vault is not registered.
    ///      - The vault's asset is disabled.
    ///      - `amount_` is zero, or the contribution adds zero shares.
    ///      - The token transfer or the vault deposit reverts.
    function contribute(
        address vault_,
        uint256 amount_,
        bool inShares_
    ) external override nonReentrant {
        _requireEnabled();
        ReserveAsset storage config = _requireRegistered(vault_);
        _requireAssetEnabled(config);
        _requireNonzeroAmount(amount_);

        uint256 sharesAdded;
        if (inShares_) {
            uint256 sharesBefore = _selfBalance(vault_);
            IERC20(vault_).safeTransferFrom(msg.sender, address(this), amount_);
            sharesAdded = _selfBalance(vault_) - sharesBefore;
        } else {
            address reserve_ = config.reserve;
            uint256 reserveBefore = _selfBalance(reserve_);
            IERC20(reserve_).safeTransferFrom(msg.sender, address(this), amount_);
            uint256 received = _selfBalance(reserve_) - reserveBefore;

            uint256 sharesBefore = _selfBalance(vault_);
            IERC20(reserve_).forceApprove(vault_, received);
            IERC4626(vault_).deposit(received, address(this));
            sharesAdded = _selfBalance(vault_) - sharesBefore;
        }
        _requireNonzeroAmount(sharesAdded);

        uint256 budgetAdded = _previewRedeem(vault_, sharesAdded);
        config.prefundedShares += sharesAdded;
        config.weeklyBudgetRemaining += budgetAdded;

        emit Contributed(vault_, msg.sender, sharesAdded, budgetAdded);
    }

    // ============ BOND CALLBACK ============ //

    /// @inheritdoc IBondCallback
    /// @dev The teller transfers the quote OHM before invoking the callback; the received
    ///      amount is checked against the tracked accounting, which enforces the burn
    ///      invariant `_OHM.balanceOf(this) >= _ohmPurchased`. OHM donated to the facility
    ///      counts toward the balance, so it can cover a missing quote transfer up to the
    ///      donated amount.
    ///
    ///      `outputAmount_` is teller-computed and not validated here: the payout is
    ///      bounded only by the payout-token balance held by the facility, and the tracked
    ///      counters are reduced with saturating subtraction (`_recordReserveOutflow`).
    ///
    ///      Reverts if:
    ///      - The caller is not the teller.
    ///      - The contract is disabled.
    ///      - The market was not created by this facility.
    ///      - The market's asset is disabled.
    ///      - The OHM balance is below `_ohmPurchased + inputAmount_`.
    function callback(
        uint256 id_,
        uint256 inputAmount_,
        uint256 outputAmount_
    ) external override nonReentrant {
        _requireCaller(teller);

        _requireEnabled();

        address vault = _marketVaults[id_];
        if (vault == address(0)) revert IYieldRepurchaseFacilityV2_UnknownMarket();

        ReserveAsset storage config = _assetConfigs[vault];
        _requireAssetEnabled(config);

        if (_selfBalance(address(_OHM)) < _ohmPurchased + inputAmount_)
            revert IYieldRepurchaseFacilityV2_QuoteNotReceived();

        address reserve_ = config.reserve;

        _ohmPurchased += inputAmount_;
        uint256[2] storage marketAmounts = _amountsPerMarket[id_];
        marketAmounts[0] += inputAmount_;
        marketAmounts[1] += outputAmount_;

        _recordReserveOutflow(config, vault, outputAmount_);

        IERC20(config.sellShares ? vault : reserve_).safeTransfer(msg.sender, outputAmount_);
    }

    /// @notice Reduces the budget and holdings counters by a market payout.
    /// @dev The subtractions saturate at zero. For a sell-shares asset the budget is
    ///      reduced by `previewMint(outputAmount_)` (rounded up by the vault), the
    ///      reserve value of the paid shares.
    function _recordReserveOutflow(
        ReserveAsset storage config_,
        address vault_,
        uint256 outputAmount_
    ) private {
        if (!config_.sellShares) {
            config_.weeklyBudgetRemaining = Math.saturatingSub(
                config_.weeklyBudgetRemaining,
                outputAmount_
            );
            config_.prefundedReserve = Math.saturatingSub(config_.prefundedReserve, outputAmount_);
        } else {
            // The round-up debit keeps the budget from exceeding the value of the
            // remaining share pool, so the prefund does not re-withdraw the rounding
            // dust from the treasury.
            uint256 reserveValue = IERC4626(vault_).previewMint(outputAmount_);
            config_.weeklyBudgetRemaining = Math.saturatingSub(
                config_.weeklyBudgetRemaining,
                reserveValue
            );
            config_.prefundedShares = Math.saturatingSub(config_.prefundedShares, outputAmount_);
        }
    }

    /// @inheritdoc IBondCallback
    function amountsForMarket(
        uint256 id_
    ) external view override returns (uint256 in_, uint256 out_) {
        uint256[2] storage marketAmounts = _amountsPerMarket[id_];
        return (marketAmounts[0], marketAmounts[1]);
    }

    /// @inheritdoc IBondCallback
    /// @dev Not supported: the facility serves only its own markets, authorized through
    ///      `_marketVaults`. Always reverts.
    function whitelist(address, uint256) external pure override {
        revert IYieldRepurchaseFacilityV2_NotSupported();
    }

    /// @inheritdoc IBondCallback
    /// @dev Not supported: the facility serves only its own markets, authorized through
    ///      `_marketVaults`. Always reverts.
    function blacklist(address, uint256) external pure override {
        revert IYieldRepurchaseFacilityV2_NotSupported();
    }

    // ============ ADMIN FUNCTIONS ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev The admin role is expected to be held only by the OCG timelock, so the
    ///      function is de-facto timelocked.
    ///
    ///      The asset is registered in the enabled state.
    ///
    ///      The function reverts if:
    ///      - The caller does not hold the admin role.
    ///      - The vault address is the zero address.
    ///      - The vault is already registered.
    ///      - The vault reports the zero address as its underlying asset.
    ///      - Another registered vault uses the same reserve token.
    ///      - The vault's underlying asset decimals exceed 18.
    ///      - The vault's share decimals do not match its reserve decimals (a vault with a
    ///        decimals offset is not supported).
    ///      - The yield buyback share exceeds 100% (`1e18`).
    ///      - `setAsBackingVault_` is set together with `sellShares_`.
    function addAsset(
        address vault_,
        uint256 yieldBuybackShare_,
        uint256 initialReserveBalance_,
        uint256 initialConversionRate_,
        uint256 nextYield_,
        bool sellShares_,
        bool setAsBackingVault_
    ) external override onlyAdminRole {
        _requireNonzeroAddress(vault_, "vault");
        _requireValidYieldBuybackShare(yieldBuybackShare_);
        if (_assetConfigs[vault_].vault != address(0))
            revert IYieldRepurchaseFacilityV2_AssetAlreadyRegistered();

        address reserve_ = IERC4626(vault_).asset();
        _requireNonzeroAddress(reserve_, "vault.asset");

        uint8 reserveDecimals = IERC20Metadata(reserve_).decimals();
        if (reserveDecimals > _MAX_RESERVE_DECIMALS)
            revert IYieldRepurchaseFacilityV2_UnsupportedDecimals();

        // The conversion rate probe and the sell-shares market pricing both treat
        // `10 ** reserveDecimals` as one whole share.
        if (IERC20Metadata(vault_).decimals() != reserveDecimals)
            revert IYieldRepurchaseFacilityV2_VaultDecimalsMismatch();

        // The facility pools the raw reserve balance per token, so two vaults over the
        // same reserve would share holdings.
        address[] storage vaults = _vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            if (_assetConfigs[vaults[i]].reserve == reserve_)
                revert IYieldRepurchaseFacilityV2_DuplicateReserve();
        }

        _assetConfigs[vault_] = ReserveAsset({
            vault: vault_,
            reserve: reserve_,
            reserveDecimals: reserveDecimals,
            sellShares: sellShares_,
            isAssetEnabled: true,
            yieldBuybackShare: yieldBuybackShare_,
            lastReserveBalance: initialReserveBalance_,
            lastConversionRate: initialConversionRate_,
            nextYield: nextYield_,
            weeklyBudgetRemaining: 0,
            prefundedShares: 0,
            prefundedReserve: 0
        });
        vaults.push(vault_);

        emit AssetAdded(vault_, reserve_, yieldBuybackShare_);
        _setNextYield(_assetConfigs[vault_], nextYield_);

        if (setAsBackingVault_) _setBackingVault(vault_, _assetConfigs[vault_]);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev The admin role is expected to be held only by the OCG timelock, so the
    ///      function is de-facto timelocked.
    ///
    ///      The one-shot flag is consumed before any external interaction and is never
    ///      re-armed, so the epoch counter is written only by `execute`, by the restart
    ///      in `enable`, and by at most one seeding.
    ///
    ///      The epoch pin (`_epoch == _EPOCH_LENGTH - 1`) rejects a seeding after a
    ///      heart beat has advanced the counter past the `enable` restart. The counter
    ///      also holds this value on the last epoch of every week, so the pin alone
    ///      does not prove that no beat has run.
    ///
    ///      Per seed, the budget is credited and `WeeklyBudgetSeeded` is emitted before
    ///      the prefund runs, so the event precedes a `PrefundShortfall` it may cause.
    ///
    ///      The function reverts if:
    ///      - The contract is disabled.
    ///      - The caller does not hold the admin role.
    ///      - The cycle has already been seeded.
    ///      - The epoch counter is not at the restart value set by `enable`.
    ///      - `epoch_` is not below the weekly epoch count of 21.
    ///      - A seed references an unregistered or disabled vault.
    ///      - A seeded amount is zero.
    ///      - The treasury withdrawal of a prefund or a preview of a seeded vault
    ///        reverts.
    function seedCycle(
        uint48 epoch_,
        WeeklyBudgetSeed[] calldata budgetSeeds_
    ) external override nonReentrant givenEnabled onlyAdminRole {
        if (_cycleSeeded) revert IYieldRepurchaseFacilityV2_CycleAlreadySeeded();
        _cycleSeeded = true;

        if (_epoch != _EPOCH_LENGTH - 1) revert IYieldRepurchaseFacilityV2_CycleAlreadyStarted();

        if (epoch_ >= _EPOCH_LENGTH) revert IYieldRepurchaseFacilityV2_EpochSeedTooHigh();
        _epoch = epoch_;

        uint256 seedsLength = budgetSeeds_.length;
        for (uint256 i = 0; i < seedsLength; ++i) {
            WeeklyBudgetSeed calldata seed = budgetSeeds_[i];
            ReserveAsset storage config = _requireRegistered(seed.vault);
            _requireAssetEnabled(config);
            _requireNonzeroAmount(seed.weeklyBudget);

            config.weeklyBudgetRemaining += seed.weeklyBudget;
            emit WeeklyBudgetSeeded(seed.vault, seed.weeklyBudget, epoch_);

            _prefundVault(seed.vault, config);
        }
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev The admin role is expected to be held only by the OCG timelock, so the
    ///      function is de-facto timelocked.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the admin role.
    ///      - The vault is not registered.
    ///      - The vault is currently enabled.
    ///      - The vault is currently set as the `backingVault`.
    function removeAsset(address vault_) external override onlyAdminRole {
        ReserveAsset storage config = _requireRegistered(vault_);
        _requireAssetDisabled(config);
        _requireNotBackingVault(vault_);

        _returnBalancesToTrsry(vault_, config.reserve);

        address[] storage vaults = _vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            if (vaults[i] == vault_) {
                vaults[i] = vaults[vaultsLength - 1];
                vaults.pop();
                break;
            }
        }

        delete _assetConfigs[vault_];

        emit AssetRemoved(vault_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev The admin role is expected to be held only by the OCG timelock, so the
    ///      function is de-facto timelocked.
    function setBackingOracle(address backingOracle_) external override onlyAdminRole {
        _setBackingOracle(backingOracle_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev The admin role is expected to be held only by the OCG timelock, so the
    ///      function is de-facto timelocked.
    function setBackingVault(address vault_) external override onlyAdminRole {
        _setBackingVault(vault_, _requireRegistered(vault_));
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev The admin role is expected to be held only by the OCG timelock, so the
    ///      function is de-facto timelocked.
    function setBondContracts(
        address bondAuctioneer_,
        address teller_
    ) external override onlyAdminRole {
        _setBondContracts(bondAuctioneer_, teller_);
    }

    /// @notice Sets the backing oracle.
    /// @dev Reverts if `backingOracle_` is the zero address.
    function _setBackingOracle(address backingOracle_) internal {
        _requireNonzeroAddress(backingOracle_, "backingOracle");

        backingOracle = backingOracle_;
        emit BackingOracleSet(backingOracle_);
    }

    /// @notice Makes a registered vault the backing vault.
    /// @dev Reverts if:
    ///      - The asset is disabled.
    ///      - The asset sells vault shares.
    function _setBackingVault(address vault_, ReserveAsset storage config_) private {
        _requireAssetEnabled(config_);
        if (config_.sellShares) revert IYieldRepurchaseFacilityV2_BackingVaultCannotSellShares();

        backingVault = vault_;
        emit BackingVaultSet(vault_);
    }

    /// @notice Sets the bond auctioneer and the teller.
    /// @dev Reverts if either address is the zero address.
    function _setBondContracts(address bondAuctioneer_, address teller_) internal {
        _requireNonzeroAddress(bondAuctioneer_, "bondAuctioneer");
        _requireNonzeroAddress(teller_, "teller");

        bondAuctioneer = bondAuctioneer_;
        teller = teller_;
        emit BondContractsSet(bondAuctioneer_, teller_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev The admin role is expected to be held only by the OCG timelock, so the
    ///      function is de-facto timelocked.
    ///
    ///      The offset is subtracted from the Clearinghouse's principal receivables when
    ///      the weekly reset projects the next yield, so it is expected that a correction
    ///      made at any point before the reset keeps the excess receivables out of
    ///      the projected yield.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the admin role.
    ///      - The Clearinghouse is the zero address.
    ///      - The offset exceeds the current `principalReceivables` of the Clearinghouse.
    function setClearinghouseOffset(
        address clearinghouse_,
        uint256 offset_
    ) external override onlyAdminRole {
        _setClearinghouseOffset(clearinghouse_, offset_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reachable through the YRF timelock or directly by the admin, so a change is
    ///      de-facto timelocked.
    ///
    ///      Reverts if:
    ///      - The caller is neither the YRF timelock nor the admin.
    ///      - The vault is not registered.
    ///      - The share exceeds 100% (`1e18`).
    function setYieldBuybackShare(
        address vault_,
        uint256 newShare_
    ) external override onlyTimelockOrAdminRole {
        ReserveAsset storage config = _requireRegistered(vault_);
        _requireValidYieldBuybackShare(newShare_);

        config.yieldBuybackShare = newShare_;
        emit YieldBuybackShareSet(vault_, newShare_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reachable through the YRF timelock or directly by the admin, so a change is
    ///      de-facto timelocked.
    ///
    ///      The only enforced bound is below 100% (`1e18`). A discount large enough to
    ///      overflow the market scale computation degrades to skipped markets
    ///      (`DailyCycleSkipped` or `MarketCreationFailed`) and does not block the beat.
    ///
    ///      Reverts if:
    ///      - The caller is neither the YRF timelock nor the admin.
    ///      - The initial discount is not less than 100% (`1e18`).
    function setInitialDiscount(
        uint256 initialDiscount_
    ) external override onlyTimelockOrAdminRole {
        _setInitialDiscount(initialDiscount_);
    }

    /// @notice Sets the initial discount.
    /// @dev Reverts if `initialDiscount_` is not less than 100% (`1e18`).
    function _setInitialDiscount(uint256 initialDiscount_) internal {
        if (initialDiscount_ >= _ONE_HUNDRED_PERCENT)
            revert IYieldRepurchaseFacilityV2_InitialDiscountTooHigh();

        initialDiscount = initialDiscount_;
        emit InitialDiscountSet(initialDiscount_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reachable through the YRF timelock or directly by the admin, so an
    ///      increase is de-facto timelocked. The offset is read live by the weekly reset
    ///      projection, so an increase that executes only after a reset misses that
    ///      projection: the following weekly budget then overstates the yield by one week
    ///      of interest on the missing offset. When that matters, the emergency role can
    ///      `disable` the facility before the reset beat (the cycle freezes in place),
    ///      let the queued increase execute, and have the yrf_admin `reEnable`; the reset
    ///      then runs with the offset applied.
    ///
    ///      The caller can only increase the offset, which reduces the projected yield;
    ///      lowering the offset requires the admin, via `setClearinghouseOffset`.
    ///
    ///      Reverts if:
    ///      - The caller is neither the YRF timelock nor the admin.
    ///      - The Clearinghouse is the zero address.
    ///      - The resulting offset exceeds the current `principalReceivables`.
    function increaseClearinghouseOffset(
        address clearinghouse_,
        uint256 additionalOffset_
    ) external override onlyTimelockOrAdminRole {
        _setClearinghouseOffset(
            clearinghouse_,
            _receivablesOffsets[clearinghouse_] + additionalOffset_
        );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reachable through the YRF timelock or directly by the admin, so a
    ///      correction is de-facto timelocked. The function corrects a stored projection
    ///      that is known to overstate the yield, for example when a receivables offset
    ///      executed only after the weekly reset that made the projection. The stored
    ///      value is consumed by the following weekly reset, so the correction can be
    ///      applied at any point of the running week. The compare-and-set guard makes a
    ///      correction that outlives its target harmless: once a weekly reset has
    ///      replaced the stored value with a fresh projection, the stale correction
    ///      reverts instead of cutting the fresh value.
    ///
    ///      Reverts if:
    ///      - The caller is neither the YRF timelock nor the admin.
    ///      - The vault is not registered.
    ///      - The stored next yield does not equal `expectedNextYield_`.
    ///      - `newNextYield_` is not lower than the stored value.
    function decreaseNextYield(
        address vault_,
        uint256 expectedNextYield_,
        uint256 newNextYield_
    ) external override onlyTimelockOrAdminRole {
        ReserveAsset storage config = _requireRegistered(vault_);

        uint256 currentNextYield = config.nextYield;
        if (currentNextYield != expectedNextYield_)
            revert IYieldRepurchaseFacilityV2_NextYieldMismatch(
                vault_,
                expectedNextYield_,
                currentNextYield
            );
        if (newNextYield_ >= currentNextYield)
            revert IYieldRepurchaseFacilityV2_NextYieldNotDecreased(
                vault_,
                newNextYield_,
                currentNextYield
            );

        _setNextYield(config, newNextYield_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev The admin role is expected to be held only by the OCG timelock, so the
    ///      function is de-facto timelocked.
    ///
    ///      By default only Clearinghouses whose reserve matches the backing reserve are
    ///      counted. Inclusion is meant for Clearinghouses whose receivables accrue to the
    ///      backing reserve, so the receivables must be denominated in a token with the same
    ///      decimals as the backing reserve. The receivables offset of the Clearinghouse
    ///      applies as usual. Only Clearinghouses present in the CHREG registry are iterated,
    ///      so including any other address has no effect.
    ///
    ///      The function reverts if:
    ///      - The caller does not hold the admin role.
    ///      - `clearinghouse_` is the zero address.
    ///      - The Clearinghouse is already included.
    function includeClearinghouse(address clearinghouse_) external override onlyAdminRole {
        _requireNonzeroAddress(clearinghouse_, "clearinghouse");
        if (_includedClearinghouses[clearinghouse_])
            revert IYieldRepurchaseFacilityV2_ClearinghouseIncluded();

        _includedClearinghouses[clearinghouse_] = true;
        emit ClearinghouseIncluded(clearinghouse_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reachable through the YRF timelock or directly by the admin, so an
    ///      exclusion is de-facto timelocked. The immediate defensive lever against a
    ///      misbehaving Clearinghouse is the emergency `disable` of the facility, which
    ///      freezes the cycle in place until the queued correction executes.
    ///
    ///      Reverts if:
    ///      - The caller is neither the YRF timelock nor the admin.
    ///      - The Clearinghouse is not included.
    function excludeClearinghouse(
        address clearinghouse_
    ) external override onlyTimelockOrAdminRole {
        if (!_includedClearinghouses[clearinghouse_])
            revert IYieldRepurchaseFacilityV2_ClearinghouseNotIncluded();

        _includedClearinghouses[clearinghouse_] = false;
        emit ClearinghouseExcluded(clearinghouse_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reachable through the YRF timelock or directly by the admin, so a re-enable is
    ///      de-facto timelocked.
    ///
    ///      The next yield is reset to zero and the yield snapshots are refreshed, so a
    ///      value left over from before the asset was disabled does not enter the weekly
    ///      budget; the yield projection resumes at the following weekly reset.
    ///
    ///      Reverts if:
    ///      - The caller is neither the YRF timelock nor the admin.
    ///      - The vault is not registered.
    ///      - The vault is already enabled.
    function enableAsset(address vault_) external override onlyTimelockOrAdminRole {
        ReserveAsset storage config = _requireRegistered(vault_);
        _requireAssetDisabled(config);

        config.isAssetEnabled = true;
        _refreshSnapshots(vault_, config);

        emit AssetEnabled(vault_);
        _setNextYield(config, 0);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reachable through the YRF timelock or directly by the admin, so a
    ///      per-asset halt is de-facto timelocked. An immediate halt of the whole
    ///      facility remains available to the emergency role through `disable`.
    ///
    ///      Reverts if:
    ///      - The caller is neither the YRF timelock nor the admin.
    ///      - The vault is not registered.
    ///      - The vault is already disabled.
    ///      - The vault is the backing vault.
    function disableAsset(address vault_) external override onlyTimelockOrAdminRole {
        ReserveAsset storage config = _requireRegistered(vault_);
        _requireAssetEnabled(config);
        _requireNotBackingVault(vault_);

        config.isAssetEnabled = false;
        emit AssetDisabled(vault_);
    }

    // ============ HELPERS ============ //

    /// @notice Returns the vault's conversion rate: the reserve amount redeemable for one
    ///         whole share.
    /// @dev The probe amount `10 ** reserveDecimals` is one whole share because `addAsset`
    ///      requires the vault's share decimals to equal its reserve decimals.
    function _conversionRate(ReserveAsset storage config_) private view returns (uint256) {
        return _previewRedeem(config_.vault, 10 ** config_.reserveDecimals);
    }

    /// @notice Refreshes the vault's conversion-rate and reserve-balance snapshots.
    function _refreshSnapshots(address vault_, ReserveAsset storage config_) private {
        config_.lastConversionRate = _conversionRate(config_);
        config_.lastReserveBalance = _getProtocolReserveBalance(vault_);
    }

    /// @notice Returns the vault yield accrued since the snapshots, in reserve units.
    /// @dev `lastReserveBalance * (currentRate - lastRate) / lastRate`, floored. Zero
    ///      when the rate has not increased or the rate snapshot is unset.
    function _computeVaultYield(ReserveAsset storage config_) private view returns (uint256 yield) {
        uint256 lastRate = config_.lastConversionRate;
        if (lastRate == 0) return 0;

        uint256 currentRate = _conversionRate(config_);
        if (currentRate <= lastRate) return 0;

        yield = config_.lastReserveBalance.mulDiv(currentRate - lastRate, lastRate);
    }

    /// @notice Projects the next yield of a vault, in reserve units.
    /// @dev The Clearinghouse interest is credited only to the backing vault. The total
    ///      is multiplied by the vault's buyback share (floor).
    function _projectNextYield(
        ReserveAsset storage config_,
        uint256 clearinghouseYield_
    ) private view returns (uint256) {
        uint256 vaultYield = _computeVaultYield(config_);
        uint256 totalYield = config_.vault == backingVault
            ? vaultYield + clearinghouseYield_
            : vaultYield;
        return totalYield.mulDiv(config_.yieldBuybackShare, _ONE_HUNDRED_PERCENT);
    }

    /// @notice Returns the reserve token of the backing vault, or the zero address when
    ///         no backing vault is designated.
    function _backingReserve() private view returns (address) {
        address backingVault_ = backingVault;
        if (backingVault_ == address(0)) return address(0);
        return _assetConfigs[backingVault_].reserve;
    }

    /// @notice Returns the reserve value of the protocol-held shares of a vault.
    /// @dev Counts the treasury balance, and for the backing vault also the balances of
    ///      the active Clearinghouses, valued through `previewRedeem` (floor).
    function _getProtocolReserveBalance(address vault_) private view returns (uint256 balance) {
        uint256 totalShares = _trsryBalance(vault_);

        if (vault_ == backingVault) {
            uint256 activeCount = CHREG.activeCount();
            for (uint256 i = 0; i < activeCount; ++i) {
                totalShares += _balanceOf(vault_, CHREG.active(i));
            }
        }

        balance = _previewRedeem(vault_, totalShares);
    }

    /// @notice Sets the cumulative receivables offset of a Clearinghouse.
    /// @dev Reverts if:
    ///      - `clearinghouse_` is the zero address.
    ///      - `offset_` exceeds the current `principalReceivables`.
    function _setClearinghouseOffset(address clearinghouse_, uint256 offset_) internal {
        _requireNonzeroAddress(clearinghouse_, "clearinghouse");

        uint256 receivables = YRFClearinghouseLib.readPrincipalReceivables(clearinghouse_);
        if (offset_ > receivables)
            revert IYieldRepurchaseFacilityV2_OffsetExceedsReceivables(
                clearinghouse_,
                offset_,
                receivables
            );

        _receivablesOffsets[clearinghouse_] = offset_;
        emit ClearinghouseOffsetSet(clearinghouse_, offset_);
    }

    /// @notice Scales an 18-decimal value down to the target decimals, flooring.
    function _scaleFrom18(uint256 value18_, uint8 targetDecimals_) private pure returns (uint256) {
        if (targetDecimals_ == 18) return value18_;
        return value18_ / (10 ** (18 - targetDecimals_));
    }

    /// @notice Returns the config of a registered vault, reverting with
    ///         `IYieldRepurchaseFacilityV2_AssetNotRegistered` for an unregistered one.
    function _requireRegistered(
        address vault_
    ) private view returns (ReserveAsset storage config_) {
        config_ = _assetConfigs[vault_];
        if (config_.vault == address(0))
            revert IYieldRepurchaseFacilityV2_AssetNotRegistered(vault_);
    }

    /// @notice Reverts with `Errors.BadInput` when `value_` is the zero address.
    function _requireNonzeroAddress(address value_, string memory parameter_) private pure {
        if (value_ == address(0)) revert Errors.BadInput(parameter_);
    }

    /// @notice Reverts with `Errors.BadInput` when the amount is zero.
    function _requireNonzeroAmount(uint256 amount_) private pure {
        if (amount_ == 0) revert Errors.BadInput("amount");
    }

    /// @notice Returns the vault's share amount for an exact `assets_` withdrawal
    ///         (rounded up by the vault).
    function _previewWithdraw(address vault_, uint256 assets_) private view returns (uint256) {
        return IERC4626(vault_).previewWithdraw(assets_);
    }

    /// @notice Returns the vault's reserve amount for a `shares_` redemption (rounded
    ///         down by the vault).
    function _previewRedeem(address vault_, uint256 shares_) private view returns (uint256) {
        return IERC4626(vault_).previewRedeem(shares_);
    }

    /// @notice Returns the facility's own `token_` balance.
    function _selfBalance(address token_) private view returns (uint256) {
        return _balanceOf(token_, address(this));
    }

    /// @notice Returns the treasury's `token_` balance.
    function _trsryBalance(address token_) private view returns (uint256) {
        return _balanceOf(token_, address(TRSRY));
    }

    /// @notice Transfers `amount_` of `token_` to the treasury; a no-op for a zero
    ///         amount.
    function _transferToTrsry(address token_, uint256 amount_) private {
        if (amount_ != 0) IERC20(token_).safeTransfer(address(TRSRY), amount_);
    }

    /// @notice Transfers the facility's full `token_` balance to the treasury.
    function _sweepToTrsry(address token_) private {
        _transferToTrsry(token_, _selfBalance(token_));
    }

    /// @notice Stores the vault's next yield and emits `NextYieldSet`.
    function _setNextYield(ReserveAsset storage config_, uint256 nextYield_) private {
        config_.nextYield = nextYield_;
        emit NextYieldSet(config_.reserve, nextYield_);
    }

    /// @notice Reverts unless the asset is enabled.
    function _requireAssetEnabled(ReserveAsset storage config_) private view {
        if (!config_.isAssetEnabled) revert IYieldRepurchaseFacilityV2_AssetDisabled();
    }

    /// @notice Reverts unless the asset is disabled.
    function _requireAssetDisabled(ReserveAsset storage config_) private view {
        if (config_.isAssetEnabled) revert IYieldRepurchaseFacilityV2_AssetEnabled();
    }

    /// @notice Reverts when the vault is the backing vault.
    function _requireNotBackingVault(address vault_) private view {
        if (vault_ == backingVault) revert IYieldRepurchaseFacilityV2_VaultIsBackingVault();
    }

    /// @notice Reads the backing value from the backing oracle, in 18 decimals.
    function _backing() private view returns (uint256) {
        return IBackingOracle(backingOracle).backing();
    }

    /// @notice Returns the `token_` balance of `account_`.
    function _balanceOf(address token_, address account_) private view returns (uint256) {
        return IERC20(token_).balanceOf(account_);
    }

    /// @notice Reverts unless the caller is `caller_`.
    function _requireCaller(address caller_) private view {
        if (msg.sender != caller_) revert IYieldRepurchaseFacilityV2_InvalidCaller();
    }

    /// @notice Reverts unless the share is at most 100% (`1e18`).
    function _requireValidYieldBuybackShare(uint256 share_) private pure {
        if (share_ > _ONE_HUNDRED_PERCENT)
            revert IYieldRepurchaseFacilityV2_YieldBuybackShareTooHigh();
    }

    /// @notice Reverts unless the grace window is strictly shorter than `MAX_GRACE_PERIOD`.
    function _requireValidGracePeriod(uint32 period_) private pure {
        if (period_ >= MAX_GRACE_PERIOD) revert IYieldRepurchaseFacilityV2_GracePeriodTooLong();
    }

    /// @notice Transfers the facility's balances of the vault shares and the reserve to
    ///         the treasury.
    function _returnBalancesToTrsry(address vault_, address reserve_) private {
        _sweepToTrsry(vault_);
        _sweepToTrsry(reserve_);
    }

    /// @notice Withdraws vault shares from the treasury under a just-in-time approval.
    function _withdrawShares(address vault_, uint256 shares_) private {
        TRSRY.increaseWithdrawApproval(address(this), SolmateERC20(vault_), shares_);
        TRSRY.withdrawReserves(address(this), SolmateERC20(vault_), shares_);
    }

    // ============ VIEW FUNCTIONS ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2
    function getVaults() external view override returns (address[] memory) {
        return _vaults;
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    function getAssetConfig(
        address vault_
    ) external view override returns (ReserveAsset memory config) {
        config = _requireRegistered(vault_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    function getNextYield(address vault_) external view override returns (uint256 yield) {
        ReserveAsset storage config = _requireRegistered(vault_);

        yield = _projectNextYield(
            config,
            YRFClearinghouseLib.clearinghouseYield(
                CHREG,
                _backingReserve(),
                _receivablesOffsets,
                _includedClearinghouses
            )
        );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    function getReserveBalance(address vault_) external view override returns (uint256 balance) {
        _requireRegistered(vault_);
        return _getProtocolReserveBalance(vault_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    function marketReserves(uint256 marketId_) external view override returns (address reserve) {
        address vault = _marketVaults[marketId_];
        if (vault == address(0)) return address(0);
        return _assetConfigs[vault].reserve;
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    function clearinghouseOffset(address clearinghouse_) external view override returns (uint256) {
        return _receivablesOffsets[clearinghouse_];
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    function isClearinghouseIncluded(address clearinghouse_) external view override returns (bool) {
        return _includedClearinghouses[clearinghouse_];
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    function ohmPurchased() external view override returns (uint256) {
        return _ohmPurchased;
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    function epoch() external view override returns (uint48) {
        return _epoch;
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    function isCycleSeeded() external view override returns (bool) {
        return _cycleSeeded;
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    function timelock() external view override returns (address) {
        return _TIMELOCK;
    }

    // ============ RESCUE ============ //

    /// @inheritdoc IBasicRescueable
    /// @dev Sweeps the rescuable balance of `token_` held by the facility to the TRSRY.
    ///
    ///      For tokens tracked by the internal accounting, the rescue is capped at the excess
    ///      of the balance over the tracked amount:
    ///      - OHM is capped at the balance above the purchased-OHM accumulator.
    ///      - A registered vault is capped at the share balance above `prefundedShares`.
    ///      - A registered reserve is capped at the balance above `prefundedReserve`.
    ///
    ///      Warning. Rescuing the excess of a registered reserve, or of a sell-shares vault,
    ///      can defund an open bond market whose capacity counted the donated balance.
    ///      Purchases on such a market revert until the next daily cycle creates a market sized
    ///      to the funds actually held.
    ///
    ///      Reverts if the caller holds neither the yrf_admin role nor the admin role.
    function rescue(address token_) external override onlyYrfAdminOrAdminRole {
        // The tracked amount backs the internal accounting and must stay on the facility
        uint256 tracked;
        if (token_ == address(_OHM)) tracked = _ohmPurchased;

        address[] storage vaults = _vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            address vault = vaults[i];
            ReserveAsset storage config = _assetConfigs[vault];
            if (token_ == vault) tracked += config.prefundedShares;
            if (token_ == config.reserve) tracked += config.prefundedReserve;
        }

        _transferToTrsry(token_, Math.saturatingSub(_selfBalance(token_), tracked));
    }

    // ============ ERC165 ============ //

    /// @inheritdoc EnablerV2
    /// @dev The override resolves the diamond between the enabler mix-ins and adds the
    ///      identifiers of the interfaces implemented by the facility itself. The
    ///      `IReEnabler` and `IGracePeriod` identifiers are advertised by the base chain.
    function supportsInterface(
        bytes4 interfaceId_
    )
        public
        view
        virtual
        override(EnablerV2, ReEnabler, ReEnablerGracePeriod, IPeriodicTask)
        returns (bool)
    {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IYieldRepurchaseFacilityV2).interfaceId ||
            interfaceId_ == type(IBondCallback).interfaceId ||
            interfaceId_ == type(IPeriodicTask).interfaceId ||
            interfaceId_ == type(IBasicRescueable).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
