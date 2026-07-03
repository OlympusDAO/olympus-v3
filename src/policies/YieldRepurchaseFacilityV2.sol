// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

// Interfaces
import {IBondCallback} from "src/interfaces/IBondCallback.sol";
import {IBondSDA} from "src/interfaces/IBondSDA.sol";
import {IBurnableERC20} from "src/interfaces/IBurnableERC20.sol";
import {IERC4626} from "@openzeppelin-5.3.0/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-5.3.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";
import {IClearinghouseReserve} from "src/policies/interfaces/IClearinghouseReserve.sol";
import {IGenericClearinghouse} from "src/policies/interfaces/IGenericClearinghouse.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/IYieldRepurchaseFacilityV2.sol";

// Libraries
import {Errors} from "src/libraries/Errors.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {Math} from "@openzeppelin-5.3.0/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin-5.3.0/token/ERC20/utils/SafeERC20.sol";

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
import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";
import {Rescueable} from "src/bases/Rescueable.sol";

// Constants
import {ADMIN_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title YieldRepurchaseFacilityV2
/// @notice Multi-asset Yield Repurchase Facility (YRF), version 2.
/// @dev The facility periodically withdraws yield earned on a whitelist of ERC4626 reserve
///      vaults and uses it, together with the backing value of OHM purchased on Bond Protocol
///      SDA markets, to buy more OHM. Purchased OHM is burned, and the recovered backing is
///      added to the primary `backingVault` budget.
///
///      Key properties:
///      - Yield is tracked independently per ERC4626 reserve vault.
///      - Each vault has its own buyback share, splitting yield between buybacks and
///        treasury retention.
///      - The OHM backing value is read from `IOlympusBackingOracle` rather than
///        being hardcoded.
///      - Purchased OHM is tracked via the `IBondCallback` accumulator rather than
///        `ohm.balanceOf(this)`, so direct OHM donations cannot inflate the backing
///        withdrawal.
///      - Every bond market is created with a non-zero `minPrice` (the inverse of the
///        undiscounted oracle price), so the SDA price decay never pays out more
///        reserve per OHM than the oracle price.
///      - Each Clearinghouse has a cumulative offset subtracted from its
///        `principalReceivables` when computing yield, so phantom default events
///        cannot inflate the buyback budget.
///      - Bond auctioneer and teller addresses are mutable through admin functions.
///      - The week's buyback budget is withdrawn from the treasury once at the weekly
///        reset (a prefund) and tracked per vault in explicit counters
///        (`prefundedShares` and `prefundedReserve`) rather than `balanceOf(this)`,
///        so direct donations cannot inflate the budget, the bid amounts, or the
///        reported reserve balance, and the unsold remainder of a bid is never
///        withdrawn from the treasury twice. At the weekly reset the carried budget
///        is re-marked upward to the pool value, so yield earned on the pool itself
///        is also committed to buybacks.
///      - Enabling re-baselines every registered vault: the projection and the weekly
///        budget are cleared and the snapshots are refreshed.
///      - Lifecycle uses `PolicyEnablerV2` and the periodic entry point is
///        `IPeriodicTask.execute()`.
contract YieldRepurchaseFacilityV2 is
    Policy,
    PolicyEnablerV2,
    Rescueable,
    ReentrancyGuardTransient,
    IBondCallback,
    IPeriodicTask,
    IVersioned,
    IYieldRepurchaseFacilityV2
{
    using SafeERC20 for IERC20;
    using FullMath for uint256;

    // ============ CONSTANTS ============ //

    /// @notice Number of epochs per week (3 per day x 7 days).
    uint48 private constant _EPOCH_LENGTH = 21;

    /// @notice Number of epochs per day.
    uint48 private constant _EPOCHS_PER_DAY = 3;

    /// @notice Number of days per week.
    uint256 private constant _DAYS_PER_WEEK = 7;

    /// @notice Precision denominator for the yield buyback share (`1e18` = 100%).
    uint256 private constant _ONE_HUNDRED_PERCENT = 1e18;

    /// @notice Maximum allowed `nextYield` increase per `adjustNextYield` call, scaled by `1e18`.
    /// @dev `1.1e18` corresponds to a 10% maximum increase.
    uint256 private constant _MAX_INCREASE_FACTOR = 11 * 1e17;

    /// @notice Expected length of the `enable` payload (`abi.encode(initialDiscount)`).
    /// @dev One 32-byte word: `initialDiscount`.
    uint256 private constant _ENABLE_PARAMS_LENGTH = 32;

    /// @notice Numerator of the Clearinghouse annual interest rate (0.5%).
    uint256 private constant _CH_RATE_NUMERATOR = 5;

    /// @notice Denominator of the Clearinghouse annual interest rate (`5 / 1000` = 0.5%).
    uint256 private constant _CH_RATE_DENOMINATOR = 1000;

    /// @notice Number of weeks per year used to amortize the Clearinghouse annual rate.
    uint256 private constant _WEEKS_PER_YEAR = 52;

    /// @notice Bond market debt buffer (`100_000` = 100%).
    uint32 private constant _BOND_DEBT_BUFFER = 100_000;

    /// @notice Bond market deposit interval (4 hours).
    uint32 private constant _BOND_DEPOSIT_INTERVAL = 4 hours;

    /// @notice Bond market duration (24 hours).
    uint48 private constant _BOND_MARKET_DURATION = 1 days;

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

    /// @notice Accumulated OHM purchased via bond markets, not yet processed.
    uint256 internal _ohmPurchased;

    /// @notice Per-vault configuration and state.
    mapping(address vault => ReserveAsset config) internal _assetConfigs;

    /// @notice Ordered list of registered vault addresses.
    address[] internal _vaults;

    /// @notice Cumulative offset applied to a Clearinghouse's `principalReceivables`.
    mapping(address clearinghouse => uint256 offset) internal _receivablesOffsets;

    /// @notice The vault that funds each open bond market created by this facility.
    /// @dev Set on market creation; a non-zero entry implicitly validates that the market
    ///      was created here.
    mapping(uint256 marketId => address vault) internal _marketVaults;

    /// @notice Cumulative input/output amounts per bond market.
    /// @dev `[0]` = OHM in (quote), `[1]` = reserve out (payout).
    mapping(uint256 marketId => uint256[2] amounts) internal _amountsPerMarket;

    // ============ SETUP ============ //

    /// @param kernel_ The Olympus Kernel.
    /// @param ohm_ The OHM token address.
    /// @param backingOracle_ The OHM backing oracle policy address.
    /// @param bondAuctioneer_ The Bond Protocol SDA auctioneer.
    /// @param teller_ The Bond Protocol teller.
    constructor(
        Kernel kernel_,
        address ohm_,
        address backingOracle_,
        address bondAuctioneer_,
        address teller_
    ) Policy(kernel_) {
        _requireNonzeroAddress(address(kernel_), "kernel");
        _requireNonzeroAddress(ohm_, "ohm");

        _OHM = IERC20(ohm_);
        _OHM_DECIMALS = IERC20Metadata(ohm_).decimals();

        _setBackingOracle(backingOracle_);
        _setBondContracts(bondAuctioneer_, teller_);

        // Disabled by default by PolicyEnablerV2.
    }

    /// @inheritdoc Policy
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
            revert IYieldRepurchaseFacilityV2_UnsupportedOracleDecimals(_oracleDecimals);

        return dependencies;
    }

    /// @inheritdoc Policy
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

    // ============ ENABLE / DISABLE ============ //

    /// @inheritdoc EnablerV2
    /// @dev Decodes the `initialDiscount` and primes the epoch counter so that the first
    ///      `execute()` call triggers a weekly reset.
    ///
    ///      Every registered vault is re-baselined: the projection (`nextYield`) and the
    ///      remaining weekly budget are cleared, and the balance and conversion rate snapshots
    ///      are refreshed. Yield accrued and budget committed before a preceding disable are
    ///      thereby retained by the treasury instead of being withdrawn at the first weekly
    ///      reset. To fund the first week, the admin can seed the projection via
    ///      the `adjustNextYield` after enabling.
    ///
    ///      Reverts if:
    ///      - The encoded payload length does not match one 32-byte word.
    ///      - `initialDiscount` is greater than or equal to `1e18` (100%).
    ///      - A registered vault reverts on `previewRedeem`.
    function _beforeEnable(bytes calldata data_) internal override {
        if (data_.length != _ENABLE_PARAMS_LENGTH)
            revert IYieldRepurchaseFacilityV2_InvalidEnableDataLength();

        uint256 initialDiscount_ = abi.decode(data_, (uint256));
        _setInitialDiscount(initialDiscount_);

        // Re-baseline every registered vault, so that stale snapshots kept across a disable
        // period cannot roll the yield of the whole period into the first projection.
        address[] storage vaults = _vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            address vault = vaults[i];
            ReserveAsset storage config = _assetConfigs[vault];

            config.nextYield = 0;
            config.weeklyBudgetRemaining = 0;
            _refreshSnapshots(vault, config);

            emit NextYieldSet(vault, 0);
        }

        _epoch = _EPOCH_LENGTH - 1;
    }

    /// @inheritdoc EnablerV2
    /// @dev On disable, burns the accumulated OHM, returns every held balance to TRSRY
    ///      (including the prefunded pool and any donations), clears the prefunded
    ///      counters, and resets the epoch counter. The payload is unused.
    ///
    ///      The per-vault budget, projection and snapshots are deliberately left in storage
    ///      for inspection while disabled.
    function _beforeDisable(bytes calldata) internal override {
        // Burn the accumulated purchased OHM. The accumulator is the source of truth.
        uint256 purchasedOhm = _ohmPurchased;
        if (purchasedOhm != 0) {
            _ohmPurchased = 0;
            IBurnableERC20(address(_OHM)).burn(purchasedOhm);
        }

        // Sweep any residual OHM (e.g. unexpected donations) to TRSRY.
        uint256 ohmBalance = _OHM.balanceOf(address(this));
        if (ohmBalance != 0) _OHM.safeTransfer(address(TRSRY), ohmBalance);

        // Return all vault shares and free reserve back to TRSRY.
        address[] storage vaults = _vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            address vault = vaults[i];
            ReserveAsset storage config = _assetConfigs[vault];

            _returnBalancesToTrsry(vault, config.reserve);

            // The prefunded balances have been returned, so clear the counters to keep
            // them consistent if the facility is later re-enabled.
            config.prefundedShares = 0;
            config.prefundedReserve = 0;
        }

        _epoch = 0;
    }

    // ============ PERIODIC TASK ============ //

    /// @inheritdoc IPeriodicTask
    /// @dev The function returns silently when the facility is disabled so that the
    ///      Heart loop is not interrupted. It is gated by `HEART_ROLE` and protected
    ///      by `nonReentrant`.
    function execute() external override nonReentrant onlyRole(HEART_ROLE) {
        if (!isEnabled) return;
        _epoch += 1;

        // Daily cycle runs once every three epochs.
        if (_epoch % _EPOCHS_PER_DAY != 0) return;

        // End-of-week reset.
        if (_epoch == _EPOCH_LENGTH) _weeklyReset();

        // Burn the accumulated purchased OHM and recycle the backing into the primary
        // vault's budget. Runs once per daily cycle, before per-vault market creation.
        _processOhmPurchases();

        // Snapshot the oracle and backing once per heartbeat. If the oracle price is
        // below the backing, each purchase would release more backing from the treasury
        // (on burn) than the reserve it spends, growing the budget on every cycle, so
        // market creation is skipped for every vault. The redeem step is also skipped
        // to avoid pulling reserve out of yield-earning vaults for a no-op cycle. The
        // unspent budget rolls into subsequent days automatically.
        uint256 oraclePrice = PRICE.getLastPrice();
        uint256 backing = IOlympusBackingOracle(backingOracle).backing();
        if (oraclePrice == 0 || oraclePrice < backing) return;

        // Number of days remaining in the current week, in the range `[1, 7]`.
        uint256 daysRemaining = _DAYS_PER_WEEK - uint256(_epoch / _EPOCHS_PER_DAY);

        address[] storage vaults = _vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            address vault = vaults[i];
            ReserveAsset storage config = _assetConfigs[vault];
            if (!config.isActive) continue;

            _executeDailyCycle(vault, config, daysRemaining, oraclePrice);
        }
    }

    /// @notice Performs the weekly reset for every active vault.
    /// @dev Re-marks the carried budget to the current prefunded pool value, rolls last
    ///      week's projected yield into the buyback budget, computes the projection for
    ///      the next week (state-changing variant, emits events on Clearinghouse
    ///      mismatches), prefunds the budget from the treasury, and snapshots the
    ///      conversion rate and reserve balance. After this call `_epoch` is reset to
    ///      zero so that the daily flow below sees a fresh week.
    function _weeklyReset() private {
        _epoch = 0;

        uint256 clearinghouseYield = _clearinghouseYield();
        _emitClearinghouseMismatches();

        address[] storage vaults = _vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            address vault = vaults[i];
            ReserveAsset storage config = _assetConfigs[vault];
            if (!config.isActive) continue;

            // Re-mark the carried budget upward to the current pool value, so the
            // appreciation earned on the facility-held pool is committed to buybacks
            // rather than reducing the upcoming treasury withdrawal. The re-mark never
            // decreases the budget, so an unfunded prefund shortfall is preserved and
            // retried by the prefund below.
            uint256 poolValue = IERC4626(vault).previewRedeem(config.prefundedShares) +
                config.prefundedReserve;
            if (poolValue > config.weeklyBudgetRemaining) {
                config.weeklyBudgetRemaining = poolValue;
            }

            // Roll last week's projection into the budget.
            config.weeklyBudgetRemaining += config.nextYield;

            // Compute the projection for the new week from the (still-stale) snapshots
            // so that the new `nextYield` reflects the appreciation since the previous
            // reset. This reads the stored snapshots, not the treasury balance, so it is
            // unaffected by the prefund below.
            uint256 newNextYield = _projectNextYield(config, clearinghouseYield);

            config.nextYield = newNextYield;
            emit NextYieldSet(vault, newNextYield);

            // Refresh the conversion rate snapshot (unaffected by the prefund) at the vault's
            // redeemable reserve value.
            config.lastConversionRate = _conversionRate(config);

            // Prefund the week's budget from the treasury.
            _prefundVault(vault, config);

            // Snapshot the protocol-owned reserve balance after the prefund, so it counts
            // only the reserves still held by the treasury and active Clearinghouses,
            // matching v1.
            config.lastReserveBalance = _getProtocolReserveBalance(vault);
        }
    }

    /// @notice Tops up the prefunded pool for `vault_` to cover its weekly budget.
    /// @dev Withdraws the share shortfall from the treasury so that the prefunded pool
    ///      (`prefundedReserve` plus `prefundedShares`) is worth at least
    ///      `weeklyBudgetRemaining` of reserve.
    ///      The withdrawal is capped by the treasury balance; in that case
    ///      `PrefundShortfall` is emitted, the week proceeds on the funded amount, and
    ///      the gap remains in `weeklyBudgetRemaining` to be retried at the next weekly
    ///      reset.
    function _prefundVault(address vault_, ReserveAsset storage config_) private {
        uint256 budget = config_.weeklyBudgetRemaining;
        if (budget == 0) return;

        // Net the raw reserve already redeemed and held for this vault, so the unsold
        // remainder of a previous bid is not funded again.
        uint256 heldReserve = config_.prefundedReserve;
        if (heldReserve >= budget) return;

        uint256 targetShares = IERC4626(vault_).previewWithdraw(budget - heldReserve);
        uint256 currentShares = config_.prefundedShares;
        if (targetShares <= currentShares) return;

        uint256 sharesToWithdraw = targetShares - currentShares;
        uint256 trsryBalance = IERC20(vault_).balanceOf(address(TRSRY));
        if (sharesToWithdraw > trsryBalance) {
            // The treasury cannot fund the full budget. Proceed on the smaller amount;
            // the unfunded gap stays in the budget and is retried at the next reset.
            emit PrefundShortfall(vault_, sharesToWithdraw, trsryBalance);
            sharesToWithdraw = trsryBalance;
        }
        if (sharesToWithdraw == 0) return;

        _withdrawShares(vault_, sharesToWithdraw);
        config_.prefundedShares = currentShares + sharesToWithdraw;
    }

    /// @notice Executes the daily cycle for a single active vault.
    /// @dev Computes the planned `bidAmount`, redeems the deficit from the vault into
    ///      reserve units, silently caps the bid at the funds actually held, and creates
    ///      a new SDA bond market. A gap between the planned bid and the held funds is a
    ///      treasury shortfall already reported by `PrefundShortfall` at the weekly reset,
    ///      or a failed redemption reported by `RedeemFailed`. The caller is responsible
    ///      for verifying that the oracle/backing precondition holds, so the redeem step
    ///      is never taken when the resulting market would be skipped.
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

        // A sell-shares vault delivers its shares as the bond payout instead of redeeming them to
        // the reserve. The capacity is the shares worth `bidAmount` of reserve, capped by the
        // prefunded shares the facility actually holds so the market can not owe more shares
        // than it can pay. The market is priced from the shares' redeemable reserve value in
        // `_createMarket`.
        if (config_.sellShares) {
            uint256 capacityShares = Math.min(
                IERC4626(vault_).previewWithdraw(bidAmount),
                config_.prefundedShares
            );
            if (capacityShares == 0) return;

            _createMarket(vault_, config_, capacityShares, oraclePrice_);
        } else {
            address reserve_ = config_.reserve;
            uint256 currentReserve = IERC20(reserve_).balanceOf(address(this));

            if (currentReserve < bidAmount) {
                uint256 deficit = bidAmount - currentReserve;
                uint256 redeemed = _redeemFromPrefunded(vault_, reserve_, deficit, config_);

                if (redeemed < deficit) {
                    // Reduce the planned bid so the bond market is never created with a
                    // capacity greater than the reserve actually held by the facility.
                    bidAmount = currentReserve + redeemed;
                }
            }

            if (bidAmount == 0) return;

            _createMarket(vault_, config_, bidAmount, oraclePrice_);
        }
    }

    /// @notice Redeems `shares_` from `vault_` into its reserve.
    /// @dev The redemption runs through the external `selfRedeemChecked` boundary inside a
    ///      `try/catch`: on a reverting vault, or on a vault that delivers less reserve than
    ///      its own `previewRedeem` promise, the whole redemption is undone, the function
    ///      reports `(0, 0)` and emits `RedeemFailed`, so the caller rolls the budget over
    ///      and retries next cycle.
    /// @return received The reserve received.
    /// @return used The number of shares redeemed: `shares_` on success, zero on failure.
    function _redeemShares(
        address vault_,
        address reserve_,
        uint256 shares_
    ) private returns (uint256 received, uint256 used) {
        if (shares_ == 0) return (0, 0);

        uint256 reserveBefore = IERC20(reserve_).balanceOf(address(this));
        try this.selfRedeemChecked(vault_, reserve_, shares_) returns (uint256 received_) {
            return (received_, shares_);
        } catch {
            // The redemption reverted or under-delivered. Report no redemption so the caller
            // treats it as a shortfall; the revert boundary restored all shares.
            emit RedeemFailed(vault_, shares_);
            return (0, 0);
        }
    }

    /// @notice Redeems `shares_` from `vault_` and reverts unless the vault delivers at least
    ///         its own `previewRedeem` promise for those shares.
    /// @dev Callable only by the facility itself. The external call creates a revert boundary
    ///      for `_redeemShares`.
    ///
    ///      Reverts if:
    ///      - The caller is not the facility itself.
    ///      - The vault redemption reverts.
    ///      - The delivered reserve is less than `previewRedeem(shares_)`.
    /// @return received The reserve received, measured as a balance delta.
    function selfRedeemChecked(
        address vault_,
        address reserve_,
        uint256 shares_
    ) external returns (uint256 received) {
        if (msg.sender != address(this))
            revert IYieldRepurchaseFacilityV2_InvalidCaller(msg.sender);

        uint256 expected = IERC4626(vault_).previewRedeem(shares_);
        uint256 reserveBefore = IERC20(reserve_).balanceOf(address(this));
        IERC4626(vault_).redeem(shares_, address(this), address(this));
        received = IERC20(reserve_).balanceOf(address(this)) - reserveBefore;

        if (received < expected)
            revert IYieldRepurchaseFacilityV2_InsufficientRedeem(vault_, expected, received);
    }

    /// @notice Redeems up to `deficit_` of reserve from the vault's prefunded share pool.
    /// @dev Only shares tracked by `prefundedShares` are eligible, so donated shares are
    ///      ignored. The received reserve is tracked in `prefundedReserve` until it is paid
    ///      out through a bond market, so the pool value is preserved across the conversion.
    ///      The redemption is capped by the available prefunded shares and reports zero on a
    ///      redeem failure, so the caller must handle a shortfall (the returned amount may be
    ///      less than `deficit_`).
    /// @return redeemed The reserve received.
    function _redeemFromPrefunded(
        address vault_,
        address reserve_,
        uint256 deficit_,
        ReserveAsset storage config_
    ) private returns (uint256 redeemed) {
        if (deficit_ == 0) return 0;

        uint256 sharesNeeded = IERC4626(vault_).previewWithdraw(deficit_);
        uint256 available = config_.prefundedShares;
        uint256 sharesToRedeem = sharesNeeded > available ? available : sharesNeeded;

        uint256 used;
        (redeemed, used) = _redeemShares(vault_, reserve_, sharesToRedeem);
        config_.prefundedShares = available - used;
        config_.prefundedReserve += redeemed;
    }

    /// @notice Withdraws `amount_` of reserve worth of vault shares fresh from the treasury
    ///         and redeems them into reserve.
    /// @dev The backing recycle is funded directly from the treasury rather than from the
    ///      buyback prefund pool, so it does not consume the week's buyback budget.
    ///      Any shares that cannot be redeemed this cycle are returned to the treasury,
    ///      so the same OHM backing is not withdrawn more than once across retries.
    ///      The withdrawal is capped by the treasury balance.
    /// @return received The reserve received.
    function _withdrawAndRedeemFresh(
        address vault_,
        address reserve_,
        uint256 amount_
    ) private returns (uint256 received) {
        if (amount_ == 0) return 0;

        uint256 shares = IERC4626(vault_).previewWithdraw(amount_);
        uint256 trsryBalance = IERC20(vault_).balanceOf(address(TRSRY));
        if (shares > trsryBalance) shares = trsryBalance;
        if (shares == 0) return 0;

        _withdrawShares(vault_, shares);

        uint256 used;
        (received, used) = _redeemShares(vault_, reserve_, shares);

        // Return any shares that could not be redeemed this cycle to the treasury, so the
        // backing recycle does not accumulate idle shares on the facility nor over-withdraws
        // across retries.
        if (shares > used) {
            IERC20(vault_).safeTransfer(address(TRSRY), shares - used);
        }
    }

    /// @notice Burns the purchased OHM proportionally to the recovered backing and
    ///         recycles that backing into the backing vault's weekly budget.
    /// @dev Reads the accumulator (not `ohm.balanceOf(this)`), redeems the backing
    ///      from the `backingVault`, then burns OHM in proportion to the actually
    ///      received backing. Any unprocessed remainder stays in `_ohmPurchased`
    ///      and is retried on the next cycle, so a temporarily under-funded TRSRY
    ///      or a failed redemption does not cause purchased OHM to be burned without
    ///      a corresponding backing recovery.
    ///
    ///      Returns silently when:
    ///      - The accumulator is empty.
    ///      - The `backingVault` is not configured.
    ///      - The backing amount rounds to zero.
    ///      - The vault redemption returns zero reserve.
    ///      In every case the accumulator is preserved and retried on the next cycle.
    function _processOhmPurchases() private {
        uint256 purchased = _ohmPurchased;
        if (purchased == 0) return;

        address backingVault_ = backingVault;
        if (backingVault_ == address(0)) return;

        ReserveAsset storage backingConfig = _assetConfigs[backingVault_];
        uint256 backingPerOhm = IOlympusBackingOracle(backingOracle).backing();

        // backingAmount18 = purchased (9 dec) * backingPerOhm (18 dec) / 10^9
        // backingAmount   = scaleFrom18(backingAmount18, reserveDecimals).
        uint256 backingAmount18 = purchased.mulDiv(backingPerOhm, 10 ** _OHM_DECIMALS);
        uint256 backingAmount = _scaleFrom18(backingAmount18, backingConfig.reserveDecimals);
        if (backingAmount == 0) return;

        // Recover the backing fresh from the treasury (a separate flow from the weekly
        // buyback prefund).
        uint256 received = _withdrawAndRedeemFresh(
            backingVault_,
            backingConfig.reserve,
            backingAmount
        );
        if (received == 0) return;

        // Burn OHM in proportion to the recovered backing. The full path uses the
        // explicit `purchased` branch to avoid any rounding loss when the redemption
        // delivered the full amount.
        uint256 ohmToBurn = received >= backingAmount
            ? purchased
            : purchased.mulDiv(received, backingAmount);

        _ohmPurchased = purchased - ohmToBurn;
        IBurnableERC20(address(_OHM)).burn(ohmToBurn);

        // The recycled reserve is held by the facility until sold, so the budget and the
        // tracked raw-reserve pool grow together.
        backingConfig.weeklyBudgetRemaining += received;
        backingConfig.prefundedReserve += received;

        emit OhmPurchasesProcessed(ohmToBurn, received);
    }

    /// @notice Creates a single SDA bond market for `vault_`.
    /// @dev The `minPrice` is set to the inverse of the undiscounted oracle price, so the
    ///      SDA decay never pays out more reserve per OHM than the oracle price. The
    ///      callback address is set to this contract so that every purchase mutates the
    ///      accumulator and the vault's budget. The caller (`execute`) is responsible for
    ///      the `oraclePrice >= backing` precondition, so this helper is never invoked in
    ///      the skipped regime.
    function _createMarket(
        address vault_,
        ReserveAsset storage config_,
        uint256 bidAmount_,
        uint256 oraclePrice_
    ) private {
        uint256 marketOraclePrice = oraclePrice_;
        address payoutToken = config_.reserve;

        // A sell-shares vault pays out its shares. Denominate the OHM oracle price in
        // vault shares, so the floor does not pay out more than OHM per share.
        // The payout token is the vault, not the reserve.
        if (config_.sellShares) {
            uint256 conversionRate = _conversionRate(config_);
            if (conversionRate == 0) {
                emit MarketCreationFailed(vault_, bidAmount_);
                return;
            }
            marketOraclePrice = oraclePrice_.mulDiv(10 ** config_.reserveDecimals, conversionRate);
            payoutToken = vault_;
        }

        (
            uint256 formattedInitialPrice,
            uint256 formattedMinimumPrice,
            int8 scaleAdjustment
        ) = _computeMarketPricing(marketOraclePrice, config_.reserveDecimals);

        (bool success, uint256 marketId) = _submitMarket(
            payoutToken,
            bidAmount_,
            formattedInitialPrice,
            formattedMinimumPrice,
            scaleAdjustment
        );

        // A reverting auctioneer must not brick the heartbeat. The reserve redeemed for this
        // bid stays on the contract and is reused next cycle, and the budget is untouched
        // (only the callback decrements it), so the market is retried.
        if (!success) {
            emit MarketCreationFailed(vault_, bidAmount_);
            return;
        }

        _marketVaults[marketId] = vault_;

        emit RepoMarket(vault_, marketId, bidAmount_);
    }

    /// @notice Computes the formatted initial price, minimum price, and scale adjustment
    ///         used by the bond protocol SDA market.
    /// @param oraclePrice_ The current OHM/reserve oracle price.
    /// @param reserveDecimals_ The decimals of the vault's reserve token.
    /// @return formattedInitialPrice The bond protocol initial price (scaled).
    /// @return formattedMinimumPrice The bond protocol minimum price (scaled).
    /// @return scaleAdjustment The bond protocol scale adjustment.
    function _computeMarketPricing(
        uint256 oraclePrice_,
        uint8 reserveDecimals_
    )
        private
        view
        returns (uint256 formattedInitialPrice, uint256 formattedMinimumPrice, int8 scaleAdjustment)
    {
        // discount = 1e18 - initialDiscount; e.g. 1e18 - 3e16 = 0.97e18.
        uint256 discountFactor = _ONE_HUNDRED_PERCENT - initialDiscount;
        uint256 effectivePrice = oraclePrice_.mulDiv(discountFactor, _ONE_HUNDRED_PERCENT);
        uint256 oracleSquare = 10 ** (uint256(_oracleDecimals) * 2);

        uint256 initialPrice = oracleSquare / effectivePrice;
        uint256 minPrice = oracleSquare / oraclePrice_;

        int8 priceDecimals = _getPriceDecimals(initialPrice);
        scaleAdjustment = int8(reserveDecimals_) - int8(_OHM_DECIMALS) + (priceDecimals / 2);

        uint256 oracleScale = 10 ** uint8(int8(_oracleDecimals) - priceDecimals);
        uint256 bondScale = 10 **
            uint8(
                36 + scaleAdjustment + int8(_OHM_DECIMALS) - int8(reserveDecimals_) - priceDecimals
            );

        formattedInitialPrice = initialPrice.mulDiv(bondScale, oracleScale);
        formattedMinimumPrice = minPrice.mulDiv(bondScale, oracleScale);
    }

    /// @notice Submits the bond market creation call to the auctioneer.
    /// @dev Extracted from `_createMarket` to keep the parent's stack within compiler limits.
    ///      The `createMarket` call is wrapped in `try/catch` so a reverting auctioneer does
    ///      not interrupt the heartbeat; the caller skips the market and retries next cycle.
    /// @return success True if the market was created.
    /// @return marketId The created market identifier (zero when `success` is false).
    function _submitMarket(
        address reserve_,
        uint256 bidAmount_,
        uint256 formattedInitialPrice_,
        uint256 formattedMinimumPrice_,
        int8 scaleAdjustment_
    ) private returns (bool success, uint256 marketId) {
        try
            IBondSDA(bondAuctioneer).createMarket(
                abi.encode(
                    IBondSDA.MarketParams({
                        payoutToken: SolmateERC20(reserve_),
                        quoteToken: SolmateERC20(address(_OHM)),
                        callbackAddr: address(this),
                        capacityInQuote: false,
                        capacity: bidAmount_,
                        formattedInitialPrice: formattedInitialPrice_,
                        formattedMinimumPrice: formattedMinimumPrice_,
                        debtBuffer: _BOND_DEBT_BUFFER,
                        vesting: uint48(0),
                        conclusion: uint48(block.timestamp + _BOND_MARKET_DURATION),
                        depositInterval: _BOND_DEPOSIT_INTERVAL,
                        scaleAdjustment: scaleAdjustment_
                    })
                )
            )
        returns (uint256 marketId_) {
            return (true, marketId_);
        } catch {
            return (false, 0);
        }
    }

    /// @notice Helper to calculate the relative number of price decimals.
    /// @dev Retained from the v1 implementation without modifications.
    /// @param price_ The price value being inspected.
    /// @return relativeDecimals The relative number of decimals.
    function _getPriceDecimals(uint256 price_) private view returns (int8 relativeDecimals) {
        int8 decimals;
        while (price_ >= 10) {
            price_ = price_ / 10;
            ++decimals;
        }
        return decimals - int8(_oracleDecimals);
    }

    // ============ BOND CALLBACK ============ //

    /// @inheritdoc IBondCallback
    /// @dev The OHM accumulator (`_ohmPurchased`) is the sole source of truth for
    ///      purchased OHM, so direct donations to the contract cannot inflate the
    ///      backing withdrawal. The bond protocol transfers the input (OHM) to this
    ///      contract before invoking the callback, and the callback transfers the
    ///      output (reserve) back to the teller.
    ///
    ///      Reverts if:
    ///      - The caller is not the configured teller.
    ///      - The facility is disabled.
    ///      - The market is not owned by this facility (`_marketVaults[id_]` is zero).
    ///      - The market's funding vault is inactive (deactivated or removed).
    function callback(
        uint256 id_,
        uint256 inputAmount_,
        uint256 outputAmount_
    ) external override nonReentrant {
        if (msg.sender != teller) revert IYieldRepurchaseFacilityV2_InvalidCaller(msg.sender);

        _requireEnabled();

        address vault = _marketVaults[id_];
        if (vault == address(0)) revert IYieldRepurchaseFacilityV2_UnknownMarket(id_);

        ReserveAsset storage config = _assetConfigs[vault];
        if (!config.isActive) revert IYieldRepurchaseFacilityV2_AssetInactive(vault);

        address reserve_ = config.reserve;

        // Accumulate OHM purchased and the per-market amounts.
        _ohmPurchased += inputAmount_;
        uint256[2] storage marketAmounts = _amountsPerMarket[id_];
        marketAmounts[0] += inputAmount_;
        marketAmounts[1] += outputAmount_;

        // Decrement the vault's remaining weekly budget and the tracked share/reserve pool by
        // the actual payout.
        _recordReserveOutflow(config, vault, outputAmount_);

        // Deliver the payout to the teller: the vault shares for a sell-shares vault, otherwise
        // the reserve.
        IERC20(config.sellShares ? vault : reserve_).safeTransfer(msg.sender, outputAmount_);
    }

    /// @notice Records the payout for `vault_`: decreases the remaining weekly budget and the
    ///         tracked pool by the payout, flooring at zero.
    /// @dev For a sell-shares vault the payout is in vault shares, so the budget is debited by the
    ///      shares' reserve value rounded up and the prefunded share pool by the
    ///      raw share count. Otherwise the payout is reserve and both the budget and the prefunded
    ///      reserve pool are debited by it. Floors at zero as a defensive measure for edge cases
    ///      where the payout exceeds the tracked amounts (e.g. when a part of the payout was funded
    ///      by donated reserve).
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
            // Debit the budget by the round-up reserve value of the sold shares. A round-down
            // debit leaves the budget richer than the share pool by up to a wei per purchase,
            // so the final bid of the week would request more shares than the pool holds and
            // the next prefund would re-withdraw the rounding dust from the treasury.
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
    /// @dev Reverts: this facility manages market lifecycle through `_createMarket` and
    ///      validates ownership via `_marketVaults`. External whitelisting is not used.
    function whitelist(address, uint256) external pure override {
        revert IYieldRepurchaseFacilityV2_NotSupported();
    }

    /// @inheritdoc IBondCallback
    /// @dev Reverts for the same reason as `whitelist`.
    function blacklist(address, uint256) external pure override {
        revert IYieldRepurchaseFacilityV2_NotSupported();
    }

    // ============ ADMIN FUNCTIONS ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reverts if:
    ///      - The caller does not hold the admin role.
    ///      - The vault address is the zero address.
    ///      - The vault is already registered.
    ///      - The vault reports the zero address as its underlying asset.
    ///      - The vault's underlying asset is already used by another registered vault.
    ///      - The vault's underlying asset decimals exceed 18.
    ///      - The vault is sell-shares and its share decimals do not match its reserve decimals.
    ///      - The share is greater than `1e18`.
    function addAsset(
        address vault_,
        uint256 yieldBuybackShare_,
        uint256 initialReserveBalance_,
        uint256 initialConversionRate_,
        bool sellShares_
    ) external override onlyAdminRole {
        _requireNonzeroAddress(vault_, "vault");
        _requireValidYieldBuybackShare(yieldBuybackShare_);
        if (_assetConfigs[vault_].vault != address(0))
            revert IYieldRepurchaseFacilityV2_AssetAlreadyRegistered(vault_);

        address reserve_ = IERC4626(vault_).asset();
        _requireNonzeroAddress(reserve_, "vault.asset");

        uint8 reserveDecimals = IERC20Metadata(reserve_).decimals();
        if (reserveDecimals > _MAX_RESERVE_DECIMALS)
            revert IYieldRepurchaseFacilityV2_UnsupportedDecimals(vault_, reserveDecimals);

        // A sell-shares vault delivers its shares as the bond payout, priced using the reserve
        // decimals, so the share decimals must equal the reserve decimals.
        if (sellShares_ && IERC20Metadata(vault_).decimals() != reserveDecimals)
            revert IYieldRepurchaseFacilityV2_SellSharesDecimalsMismatch(vault_);

        // Prevent registering two vaults that share the same reserve token. This keeps
        // the asset/reserve mapping single-valued, which simplifies the Clearinghouse
        // mismatch handling and the per-vault budget bookkeeping.
        address[] storage vaults = _vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            if (_assetConfigs[vaults[i]].reserve == reserve_)
                revert IYieldRepurchaseFacilityV2_DuplicateReserve(vault_, reserve_);
        }

        _assetConfigs[vault_] = ReserveAsset({
            vault: vault_,
            reserve: reserve_,
            reserveDecimals: reserveDecimals,
            sellShares: sellShares_,
            isActive: true,
            yieldBuybackShare: yieldBuybackShare_,
            lastReserveBalance: initialReserveBalance_,
            lastConversionRate: initialConversionRate_,
            nextYield: 0,
            weeklyBudgetRemaining: 0,
            prefundedShares: 0,
            prefundedReserve: 0
        });
        vaults.push(vault_);

        emit AssetAdded(vault_, reserve_, yieldBuybackShare_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reverts if:
    ///      - The caller does not hold the admin role.
    ///      - The vault is not registered.
    ///      - The vault is currently active.
    ///      - The vault is currently set as the `backingVault`.
    function removeAsset(address vault_) external override onlyAdminRole {
        ReserveAsset storage config = _requireRegistered(vault_);
        if (config.isActive) revert IYieldRepurchaseFacilityV2_AssetActive(vault_);
        if (vault_ == backingVault) revert IYieldRepurchaseFacilityV2_VaultIsBackingVault(vault_);

        // Return any residual vault shares and free reserve back to TRSRY.
        _returnBalancesToTrsry(vault_, config.reserve);

        // Remove from the vault list (swap-and-pop).
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
    /// @dev Reverts if the caller does not hold the admin role or the address is zero.
    function setBackingOracle(address backingOracle_) external override onlyAdminRole {
        _setBackingOracle(backingOracle_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reverts if:
    ///      - The caller does not hold the admin role.
    ///      - The vault is not registered or is currently inactive.
    function setBackingVault(address vault_) external override onlyAdminRole {
        ReserveAsset storage config = _requireRegistered(vault_);
        if (!config.isActive) revert IYieldRepurchaseFacilityV2_AssetInactive(vault_);
        if (config.sellShares)
            revert IYieldRepurchaseFacilityV2_BackingVaultCannotSellShares(vault_);

        backingVault = vault_;
        emit BackingVaultSet(vault_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reverts if:
    ///      - The caller does not hold the admin role.
    ///      - Either argument is the zero address.
    function setBondContracts(
        address bondAuctioneer_,
        address teller_
    ) external override onlyAdminRole {
        _setBondContracts(bondAuctioneer_, teller_);
    }

    /// @notice Validates and sets the backing oracle, then emits `BackingOracleSet`.
    /// @dev Reverts if the address is zero.
    function _setBackingOracle(address backingOracle_) internal {
        _requireNonzeroAddress(backingOracle_, "backingOracle");

        backingOracle = backingOracle_;
        emit BackingOracleSet(backingOracle_);
    }

    /// @notice Validates and sets the bond auctioneer and teller, then emits `BondContractsSet`.
    /// @dev Reverts if either address is zero.
    function _setBondContracts(address bondAuctioneer_, address teller_) internal {
        _requireNonzeroAddress(bondAuctioneer_, "bondAuctioneer");
        _requireNonzeroAddress(teller_, "teller");

        bondAuctioneer = bondAuctioneer_;
        teller = teller_;
        emit BondContractsSet(bondAuctioneer_, teller_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reverts if:
    ///      - The caller does not hold the admin role.
    ///      - The Clearinghouse is the zero address.
    ///      - The offset exceeds the current `principalReceivables` of the Clearinghouse.
    function setClearinghouseOffset(
        address clearinghouse_,
        uint256 offset_
    ) external override onlyAdminRole {
        _setClearinghouseOffset(clearinghouse_, offset_);
    }

    // ============ MANAGER FUNCTIONS ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reverts if:
    ///      - The caller does not hold the manager or admin role.
    ///      - The vault is not registered.
    ///      - The share is greater than `1e18`.
    function setYieldBuybackShare(
        address vault_,
        uint256 newShare_
    ) external override onlyManagerOrAdminRole {
        ReserveAsset storage config = _requireRegistered(vault_);
        _requireValidYieldBuybackShare(newShare_);

        config.yieldBuybackShare = newShare_;
        emit YieldBuybackShareSet(vault_, newShare_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reverts if:
    ///      - The caller does not hold the manager or admin role.
    ///      - The discount is greater than or equal to `1e18`.
    function setInitialDiscount(uint256 initialDiscount_) external override onlyManagerOrAdminRole {
        _setInitialDiscount(initialDiscount_);
    }

    /// @notice Validates and sets the initial discount, then emits `InitialDiscountSet`.
    /// @dev Reverts if the discount is greater than or equal to `1e18` (100%).
    function _setInitialDiscount(uint256 initialDiscount_) internal {
        if (initialDiscount_ >= _ONE_HUNDRED_PERCENT)
            revert IYieldRepurchaseFacilityV2_InitialDiscountTooHigh();

        initialDiscount = initialDiscount_;
        emit InitialDiscountSet(initialDiscount_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev The 10% cap only constrains the adjustment of an existing non-zero `nextYield`.
    ///      Seeding the projection from zero is unbounded, so it is restricted to the admin
    ///      role.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the manager or admin role.
    ///      - The current `nextYield` is zero and the caller does not hold the admin role.
    ///      - The vault is not registered.
    ///      - The new value increases an existing non-zero `nextYield` by more than 10%.
    function adjustNextYield(
        address vault_,
        uint256 newNextYield_
    ) external override onlyManagerOrAdminRole {
        ReserveAsset storage config = _requireRegistered(vault_);

        uint256 previous = config.nextYield;
        if (previous == 0) {
            _requireRole(msg.sender, ADMIN_ROLE);
        } else if (
            newNextYield_ > previous &&
            newNextYield_.mulDiv(_ONE_HUNDRED_PERCENT, previous) > _MAX_INCREASE_FACTOR
        ) {
            revert IYieldRepurchaseFacilityV2_TooMuchIncrease();
        }

        config.nextYield = newNextYield_;
        emit NextYieldAdjusted(vault_, previous, newNextYield_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reverts if:
    ///      - The caller does not hold the manager role.
    ///      - The Clearinghouse is the zero address.
    ///      - The resulting offset exceeds the current `principalReceivables`.
    function increaseClearinghouseOffset(
        address clearinghouse_,
        uint256 additionalOffset_
    ) external override onlyManagerRole {
        _setClearinghouseOffset(
            clearinghouse_,
            _receivablesOffsets[clearinghouse_] + additionalOffset_
        );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Refreshes the vault's balance and conversion rate snapshots, so the projection
    ///      computed at the next weekly reset covers only the period after reactivation and
    ///      the yield accrued while the vault was inactive is retained by the treasury.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the manager or admin role.
    ///      - The vault is not registered.
    ///      - The vault is already active.
    function activateAsset(address vault_) external override onlyManagerOrAdminRole {
        ReserveAsset storage config = _requireRegistered(vault_);
        if (config.isActive) revert IYieldRepurchaseFacilityV2_AssetActive(vault_);

        config.isActive = true;
        _refreshSnapshots(vault_, config);

        emit AssetActivated(vault_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reverts if:
    ///      - The caller does not hold the manager or admin role.
    ///      - The vault is not registered.
    ///      - The vault is already inactive.
    ///      - The vault is currently set as the `backingVault`.
    function deactivateAsset(address vault_) external override onlyManagerOrAdminRole {
        ReserveAsset storage config = _requireRegistered(vault_);
        if (!config.isActive) revert IYieldRepurchaseFacilityV2_AssetInactive(vault_);
        if (vault_ == backingVault) revert IYieldRepurchaseFacilityV2_VaultIsBackingVault(vault_);

        config.isActive = false;
        emit AssetDeactivated(vault_);
    }

    // ============ YIELD HELPERS ============ //

    /// @notice The vault's conversion rate: the reserve value of one whole share unit.
    function _conversionRate(ReserveAsset storage config_) private view returns (uint256) {
        return IERC4626(config_.vault).previewRedeem(10 ** config_.reserveDecimals);
    }

    /// @notice Refreshes the vault's conversion rate and protocol reserve balance snapshots
    ///         to their current values.
    function _refreshSnapshots(address vault_, ReserveAsset storage config_) private {
        config_.lastConversionRate = _conversionRate(config_);
        config_.lastReserveBalance = _getProtocolReserveBalance(vault_);
    }

    /// @notice Computes vault appreciation since the last weekly reset, in reserve units.
    /// @dev Floors at zero when the conversion rate has not been initialized or when the
    ///      rate has not increased (so the result never underflows).
    function _computeVaultYield(ReserveAsset storage config_) private view returns (uint256 yield) {
        uint256 lastRate = config_.lastConversionRate;
        if (lastRate == 0) return 0;

        // Re-read the conversion rate, matching the snapshot taken in the weekly reset.
        uint256 currentRate = _conversionRate(config_);
        if (currentRate <= lastRate) return 0;

        // yield = lastReserveBalance * (currentRate - lastRate) / lastRate.
        yield = config_.lastReserveBalance.mulDiv(currentRate - lastRate, lastRate);
    }

    /// @notice The buyback portion of the projected next-week yield for `config_`.
    /// @dev The caller supplies the global Clearinghouse yield (computed once per reset,
    ///      or read on demand in the view).
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

    /// @notice The reserve token of the backing vault, or the zero address if it is not set.
    function _backingReserve() private view returns (address) {
        address backingVault_ = backingVault;
        if (backingVault_ == address(0)) return address(0);
        return _assetConfigs[backingVault_].reserve;
    }

    /// @notice The weekly Clearinghouse interest on `receivables_` of `offset_`.
    function _clearinghouseInterest(
        uint256 receivables_,
        uint256 offset_
    ) private pure returns (uint256) {
        uint256 effective = Math.saturatingSub(receivables_, offset_);
        return (effective * _CH_RATE_NUMERATOR) / _CH_RATE_DENOMINATOR / _WEEKS_PER_YEAR;
    }

    /// @notice The global Clearinghouse receivables interest for the next week, in reserve units.
    function _clearinghouseYield() private view returns (uint256 yield) {
        address backingReserve = _backingReserve();
        if (backingReserve == address(0)) return 0;

        uint256 len = CHREG.registryCount();
        for (uint256 i = 0; i < len; ++i) {
            address ch = CHREG.registry(i);
            if (_readClearinghouseReserve(ch) != backingReserve) continue;
            yield += _clearinghouseInterest(
                _readClearinghousePrincipal(ch),
                _receivablesOffsets[ch]
            );
        }
    }

    function _emitClearinghouseMismatches() private {
        address backingReserve = _backingReserve();
        if (backingReserve == address(0)) return;

        uint256 len = CHREG.registryCount();
        for (uint256 i = 0; i < len; ++i) {
            address ch = CHREG.registry(i);
            if (_readClearinghouseReserve(ch) != backingReserve)
                emit ClearinghouseDebtTokenMismatch(ch);
        }
    }

    /// @notice Returns the protocol-owned reserve balance of a vault in reserve units.
    /// @dev For the `backingVault`, includes the TRSRY and every active Clearinghouse.
    ///      For other vaults, includes the TRSRY only.
    ///
    ///      Balances held by this facility (the prefunded pool and any donations) are
    ///      deliberately excluded.
    function _getProtocolReserveBalance(address vault_) private view returns (uint256 balance) {
        uint256 totalShares = IERC20(vault_).balanceOf(address(TRSRY));

        if (vault_ == backingVault) {
            uint256 activeCount = CHREG.activeCount();
            for (uint256 i = 0; i < activeCount; ++i) {
                totalShares += IERC20(vault_).balanceOf(CHREG.active(i));
            }
        }

        // Value the protocol-owned shares at their redeemable reserve value.
        balance = IERC4626(vault_).previewRedeem(totalShares);
    }

    /// @notice Reads `Clearinghouse.reserve()` through a `try/catch`.
    /// @dev Returns `address(0)` when the Clearinghouse does not expose `reserve()`,
    ///      so the heartbeat skips it instead of reverting.
    /// @return reserve The reserve token address, or `address(0)` on failure.
    function _readClearinghouseReserve(address clearinghouse_) private view returns (address) {
        try IClearinghouseReserve(clearinghouse_).reserve() returns (address reserve) {
            return reserve;
        } catch {
            return address(0);
        }
    }

    /// @notice Reads `Clearinghouse.principalReceivables()` through a `try/catch`.
    /// @dev Returns zero when the Clearinghouse does not expose the getter.
    /// @return receivables The reported principal receivables, or zero on failure.
    function _readClearinghousePrincipal(address clearinghouse_) private view returns (uint256) {
        try IGenericClearinghouse(clearinghouse_).principalReceivables() returns (
            uint256 receivables
        ) {
            return receivables;
        } catch {
            return 0;
        }
    }

    /// @notice Sets the receivables offset for a Clearinghouse to a specified value.
    /// @dev Reverts if:
    ///      - The Clearinghouse is the zero address.
    ///      - The offset exceeds the current `principalReceivables` of the Clearinghouse.
    function _setClearinghouseOffset(address clearinghouse_, uint256 offset_) internal {
        _requireNonzeroAddress(clearinghouse_, "clearinghouse");

        uint256 receivables = _readClearinghousePrincipal(clearinghouse_);
        if (offset_ > receivables)
            revert IYieldRepurchaseFacilityV2_OffsetExceedsReceivables(
                clearinghouse_,
                offset_,
                receivables
            );

        _receivablesOffsets[clearinghouse_] = offset_;
        emit ClearinghouseOffsetSet(clearinghouse_, offset_);
    }

    /// @notice Converts an 18-decimal value down to `targetDecimals_` decimals.
    /// @dev Rounds down. Reverts only if `targetDecimals_` exceeds 18, which is prevented
    ///      at registration time by `_MAX_RESERVE_DECIMALS`.
    function _scaleFrom18(uint256 value18_, uint8 targetDecimals_) private pure returns (uint256) {
        if (targetDecimals_ == 18) return value18_;
        return value18_ / (10 ** (18 - targetDecimals_));
    }

    /// @notice Returns the storage config for `vault_`, reverting if it is not registered.
    function _requireRegistered(
        address vault_
    ) private view returns (ReserveAsset storage config_) {
        config_ = _assetConfigs[vault_];
        if (config_.vault == address(0))
            revert IYieldRepurchaseFacilityV2_AssetNotRegistered(vault_);
    }

    /// @notice Reverts with `Errors.BadInput(parameter_)` if `value_` is the zero address.
    function _requireNonzeroAddress(address value_, string memory parameter_) private pure {
        if (value_ == address(0)) revert Errors.BadInput(parameter_);
    }

    /// @notice Reverts if `share_` exceeds `_ONE_HUNDRED_PERCENT`.
    function _requireValidYieldBuybackShare(uint256 share_) private pure {
        if (share_ > _ONE_HUNDRED_PERCENT)
            revert IYieldRepurchaseFacilityV2_YieldBuybackShareTooHigh();
    }

    /// @notice Returns any residual vault shares and free reserve held by the facility to the TRSRY.
    function _returnBalancesToTrsry(address vault_, address reserve_) private {
        uint256 vaultBalance = IERC20(vault_).balanceOf(address(this));
        if (vaultBalance != 0) IERC20(vault_).safeTransfer(address(TRSRY), vaultBalance);
        uint256 reserveBalance = IERC20(reserve_).balanceOf(address(this));
        if (reserveBalance != 0) IERC20(reserve_).safeTransfer(address(TRSRY), reserveBalance);
    }

    /// @notice Withdraws `shares_` of `vault_` from the treasury to the facility.
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
    /// @dev Reverts if the vault is not registered.
    function getAssetConfig(
        address vault_
    ) external view override returns (ReserveAsset memory config) {
        config = _requireRegistered(vault_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Returns the buyback portion of the projected next-week yield, i.e. the
    ///      amount that the projection roll would add to `weeklyBudgetRemaining` at the
    ///      next reset. The reset additionally re-marks the carried budget to the pool
    ///      value, which is not included here.
    ///
    ///      Reverts if the vault is not registered.
    function getNextYield(address vault_) external view override returns (uint256 yield) {
        ReserveAsset storage config = _requireRegistered(vault_);

        yield = _projectNextYield(config, _clearinghouseYield());
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reverts if the vault is not registered.
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
    function ohmPurchased() external view override returns (uint256) {
        return _ohmPurchased;
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    function epoch() external view override returns (uint48) {
        return _epoch;
    }

    // ============ RESCUE ============ //

    /// @inheritdoc Rescueable
    /// @dev The balances of OHM, registered vault shares and registered reserves are tracked
    ///      by the internal accounting, so sweeping them would desynchronise it. Use the
    ///      disable or removeAsset functions to return tracked assets to the TRSRY instead.
    ///
    ///      Reverts if:
    ///      - The token is OHM, a registered vault or a registered reserve.
    function rescue(address token_, address payable to_) public override {
        if (token_ == address(_OHM)) revert IYieldRepurchaseFacilityV2_CannotRescue(token_);

        address[] storage vaults = _vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            address vault = vaults[i];
            if (token_ == vault || token_ == _assetConfigs[vault].reserve)
                revert IYieldRepurchaseFacilityV2_CannotRescue(token_);
        }

        super.rescue(token_, to_);
    }

    function _authorizeRescue() internal view override {
        _requireAdminRole();
    }

    function _requireAdminRole() private view {
        _requireRole(msg.sender, ADMIN_ROLE);
    }

    // ============ ERC165 ============ //

    /// @inheritdoc EnablerV2
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(EnablerV2, Rescueable, IPeriodicTask) returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IYieldRepurchaseFacilityV2).interfaceId ||
            interfaceId_ == type(IBondCallback).interfaceId ||
            interfaceId_ == type(IPeriodicTask).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
