// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBondAuctioneer} from "src/interfaces/IBondAuctioneer.sol";
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
import {CappedCall} from "src/libraries/CappedCall.sol";
import {Errors} from "src/libraries/Errors.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {Math} from "@openzeppelin-5.3.0/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin-5.3.0/token/ERC20/utils/SafeERC20.sol";
import {YRFBondMarketLib} from "src/policies/YieldRepurchaseFacility/YRFBondMarketLib.sol";
import {YRFClearinghouseLib} from "src/policies/YieldRepurchaseFacility/YRFClearinghouseLib.sol";

// Modules
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";
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
///      with the reserves, and the 21st epoch first runs the weekly reset, which
///      withdraws the projected yield from the treasury into the per-vault buyback
///      pools. Each vault's market is priced by the live OHM price denominated in its
///      reserve token (`PRICE.getPriceIn`). The purchased OHM is burned against a
///      treasury withdrawal priced by the backing oracle. Markets are not opened while
///      the OHM price in the backing reserve is below the backing.
///
///      The reserve-side accounting is balance-based: the facility's balances of a
///      vault's shares and of its reserve token are the vault's buyback pool, and the
///      daily bids are sized from those balances. A plain transfer of either token to
///      the facility joins the pool. The treasury is drawn only through three paths,
///      none of which reads the facility's balances: the weekly withdrawal of the
///      stored `nextYield` (plus the carried `unfundedYield`), the backing withdrawal
///      for purchased-and-burned OHM tracked by the `ohmPurchased` counter, and the
///      admin-supplied seeds.
///
///      Lifecycle:
///      - `enable` (admin) performs a full restart: the yields and unfunded carries of
///        the enabled assets are zeroed, their yield snapshots are refreshed, and the
///        epoch counter is set so that the next `execute` performs a weekly reset. The
///        payload may seed the per-vault `nextYield` values (an empty seed array
///        restarts with zero yields). Funds held for the enabled assets stay in their
///        buyback pools and continue to be spent by the daily cycles.
///      - `disable` (emergency or admin) closes the live bond markets (best-effort) and
///        halts `execute` and `callback`; the funds and the accounting state are left in
///        place.
///      - `reEnable` (yrf_admin) resumes the interrupted week in place, and is only
///        available within the grace window after the disable.
///      - `returnFundsToTreasury` (emergency or admin) burns the purchased OHM and returns
///        the held balances to the treasury while the facility is disabled, sweeping each
///        vault independently.
///      - `seedCycle` (admin, once per `enable` restart, before its first beat) sets the
///        epoch counter and seeds the running week's buyback pools with treasury
///        withdrawals.
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

    /// @notice Decimals of the backing value, and therefore the decimals both the
    ///         `PRICE` module and the backing oracle must report so that the oracle
    ///         price can be compared against the backing.
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
    PRICEv2 internal PRICE;
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

    /// @notice Whether the restart performed by the latest `enable` is still seedable.
    /// @dev Armed by the `enable` restart and consumed by `seedCycle` or by the weekly
    ///      reset; the first `execute` beat of a restart always performs the weekly
    ///      reset, because the restart pins the epoch counter to 20. The seeding window
    ///      is therefore exactly one seeding between an `enable` and its first beat.
    ///      While the flag is set, the epoch counter holds the restart value of 20: only
    ///      `enable` (which arms the flag), `seedCycle`, and `execute` (which both
    ///      consume it) write the counter.
    bool internal _cycleSeedable;

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

    /// @notice The vault that funds each open bond market created by this facility, keyed
    ///         by the auctioneer the market was created on.
    /// @dev Set on market creation; a non-zero entry implicitly validates that the market
    ///      was created here. Market ids are unique only within one bond Aggregator, so
    ///      the records are scoped to the creating auctioneer: after a bond-contract
    ///      change, a colliding id on the new contracts cannot reach a stale record.
    mapping(address auctioneer => mapping(uint256 marketId => address vault))
        internal _marketVaults;

    /// @notice Cumulative input/output amounts per bond market, keyed by the auctioneer
    ///         the market was created on.
    /// @dev `[0]` = OHM in (quote), `[1]` = reserve out (payout).
    mapping(address auctioneer => mapping(uint256 marketId => uint256[2] amounts))
        internal _amountsPerMarket;

    /// @notice The market id of the vault's latest bond market plus one, or zero when
    ///         none is tracked.
    /// @dev The offset encodes "none" as zero while the market id zero stays a valid id.
    ///      The entry always refers to a market of the current `bondAuctioneer`: it is
    ///      cleared whenever the market is closed, and `setBondContracts` closes every
    ///      tracked market before the auctioneer changes.
    mapping(address vault => uint256 marketIdPlusOne) internal _liveMarketIds;

    // ============ SETUP ============ //

    /// @dev The teller is resolved from the auctioneer (`getTeller`), so the pair is
    ///      consistent by construction.
    ///
    ///      Reverts if:
    ///      - `kernel_`, `ohm_`, `timelock_`, `backingOracle_`, or `bondAuctioneer_` is
    ///        the zero address.
    ///      - The backing oracle does not report the 18 decimals of the backing value.
    ///      - The auctioneer reports the zero address as its teller.
    ///      - `gracePeriod_` is zero or not less than `MAX_GRACE_PERIOD`.
    /// @param kernel_ The Olympus Kernel.
    /// @param ohm_ The OHM token address.
    /// @param backingOracle_ The OHM backing oracle policy address.
    /// @param bondAuctioneer_ The Bond Protocol SDA auctioneer.
    /// @param timelock_ The YRF timelock policy authorized for the operational functions.
    /// @param gracePeriod_ The initial re-enable grace window, in seconds.
    constructor(
        Kernel kernel_,
        address ohm_,
        address backingOracle_,
        address bondAuctioneer_,
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
        _setBondContracts(bondAuctioneer_);

        // Disabled by default by EnablerV2
    }

    /// @inheritdoc Policy
    /// @dev Reverts if:
    ///      - Any of the TRSRY, PRICE, CHREG, or ROLES modules does not report major
    ///        version 1.
    ///      - The PRICE module reports a minor version below 2. The facility prices the
    ///        assets through `PRICE.getPriceIn`, which the PRICE surface provides from
    ///        version 1.2.
    ///      - `PRICE.decimals()` is not 18, the decimals of the backing value.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = _KEYCODE_TRSRY;
        dependencies[1] = _KEYCODE_PRICE;
        dependencies[2] = _KEYCODE_CHREG;
        dependencies[3] = _KEYCODE_ROLES;

        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        PRICE = PRICEv2(getModuleAddress(dependencies[1]));
        CHREG = CHREGv1(getModuleAddress(dependencies[2]));
        ROLES = ROLESv1(getModuleAddress(dependencies[3]));

        (uint8 trsryMajor, ) = TRSRY.VERSION();
        (uint8 priceMajor, uint8 priceMinor) = PRICE.VERSION();
        (uint8 chregMajor, ) = CHREG.VERSION();
        (uint8 rolesMajor, ) = ROLES.VERSION();
        if (trsryMajor != 1 || priceMajor != 1 || chregMajor != 1 || rolesMajor != 1)
            revert Policy_WrongModuleVersion(abi.encode([1, 1, 1, 1]));

        // The `getPriceIn` surface is provided by the PRICE module from version 1.2
        if (priceMinor < 2) revert Policy_WrongModuleVersion(abi.encode([1, 2]));

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
    /// @dev Performs a full restart of the epoch cycle: the yields and unfunded carries
    ///      of the enabled assets are zeroed, their yield snapshots are refreshed, and
    ///      the epoch counter is set so that the next `execute` performs a weekly reset.
    ///      Disabled assets are left untouched; `enableAsset` resets them when they are
    ///      enabled. The payload may seed the next yield of enabled vaults; with an
    ///      empty seed array every enabled vault restarts with a zero yield. Funds held
    ///      for the enabled assets stay in their buyback pools and continue to be spent
    ///      by the daily cycles. For resuming an interrupted week after a disable, see
    ///      `reEnable`.
    ///
    ///      Reverts if:
    ///      - The payload is shorter than the minimum `abi.encode(uint256, NextYieldSeed[])`.
    ///      - The payload does not `abi.decode` as `(uint256, NextYieldSeed[])`.
    ///      - The facility is not authorized as a market callback on the bond
    ///        auctioneer.
    ///      - The initial discount is not less than 100% (`1e18`).
    ///      - A seed references an unregistered or disabled vault.
    ///      - An enabled vault reverts on `previewRedeem` or `balanceOf`.
    function _beforeEnable(bytes calldata data_) internal override {
        if (data_.length < _MIN_ENABLE_PARAMS_LENGTH)
            revert IYieldRepurchaseFacilityV2_InvalidEnableDataLength();

        _requireCallbackAuthorized();

        (uint256 initialDiscount_, NextYieldSeed[] memory nextYieldSeeds) = abi.decode(
            data_,
            (uint256, NextYieldSeed[])
        );
        _setInitialDiscount(initialDiscount_);

        _resetCycle(nextYieldSeeds);
    }

    /// @notice Restarts the weekly cycle: zeroes the yields and unfunded carries of the
    ///         enabled assets, applies the supplied next-yield seeds, refreshes their
    ///         yield snapshots, rewinds the epoch counter so that the next `execute`
    ///         performs a weekly reset, and opens the seeding window of `seedCycle`.
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
            config.unfundedYield = 0;
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
        // The restart opens the seeding window of `seedCycle`, closed by the first beat
        _cycleSeedable = true;
    }

    /// @inheritdoc EnablerV2
    /// @dev Closes the tracked live bond markets, best-effort, so no purchasable market
    ///      outlives the disable; the funds and the accounting state are left in place so
    ///      that `reEnable` can resume the interrupted week. Use `returnFundsToTreasury`
    ///      to sweep the funds after a disable when holding them on the facility is a
    ///      concern. The auctioneer is external, so a revert there is absorbed and never
    ///      blocks the disable.
    function _beforeDisable(bytes calldata) internal override {
        _closeAllVaultMarkets();
    }

    /// @notice Closes the tracked live bond market of every registered vault,
    ///         best-effort.
    function _closeAllVaultMarkets() private {
        address[] storage vaults = _vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            _closeVaultMarket(vaults[i]);
        }
    }

    /// @notice Closes the vault's tracked live bond market on the current auctioneer,
    ///         best-effort.
    /// @dev The tracked id is cleared unconditionally. The close call is external: a
    ///      revert of the auctioneer (for example an already-closed market) is absorbed
    ///      with a `MarketCloseFailed` event carrying the truncated revert reason, and
    ///      the market is left to expire on its own; purchases on a market whose asset
    ///      is disabled or whose record is unreachable revert in `callback`.
    function _closeVaultMarket(address vault_) private {
        uint256 marketIdPlusOne = _liveMarketIds[vault_];
        if (marketIdPlusOne == 0) return;
        _liveMarketIds[vault_] = 0;

        uint256 marketId = marketIdPlusOne - 1;
        (bool success, bytes memory reason) = CappedCall.tryCall(
            bondAuctioneer,
            abi.encodeCall(IBondAuctioneer.closeMarket, (marketId))
        );
        if (!success) emit MarketCloseFailed(vault_, marketId, reason);
    }

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
    /// @dev Resumes the interrupted epoch cycle in place: the epoch counter, the buyback
    ///      pools, and the yield snapshots are intentionally left untouched, so the
    ///      facility continues the week where it stopped. Epochs advance only while the
    ///      facility is enabled, so the week is stretched by the downtime; the vault
    ///      yield accrued during the downtime is captured by the next weekly reset, and
    ///      `nextYield` is withdrawn into the buyback pool exactly once per reset
    ///      regardless of the downtime. The grace-window check runs through `super`. The
    ///      callback authorization is not re-checked: a missing authorization degrades
    ///      to market submissions the auctioneer rejects.
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
    ///      per-vault `nextYield` and `unfundedYield` are intentionally preserved, so a
    ///      later `reEnable` or `enable` refunds the facility from the treasury at the
    ///      next weekly reset.
    ///
    ///      The sweep of each vault is isolated through a self-call: a vault whose sweep
    ///      reverts is skipped with a `FundsReturnSkipped` event, keeping its balances in
    ///      place, and is retried by the next call. The OHM burn and transfer are not
    ///      isolated: OHM is a protocol-owned token whose balance always covers the
    ///      tracked purchased amount.
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
            (bool success, bytes memory reason) = CappedCall.tryCall(
                address(this),
                abi.encodeCall(this.selfReturnVaultFunds, (vault))
            );
            if (!success) emit FundsReturnSkipped(vault, reason);
        }

        emit FundsReturnedToTreasury(purchasedOhm);
    }

    /// @notice Returns a vault's share and reserve balances to the treasury.
    /// @dev External only for the self-call isolation in `returnFundsToTreasury`.
    ///
    ///      Reverts if the caller is not the facility itself.
    /// @param vault_ The vault to sweep.
    function selfReturnVaultFunds(address vault_) external {
        _requireCaller(address(this));

        _returnBalancesToTrsry(vault_, _assetConfigs[vault_].reserve);
    }

    // ============ PERIODIC TASK ============ //

    /// @inheritdoc IPeriodicTask
    /// @dev The beat must survive a misbehaving vault: the processing of each vault and the
    ///      processing of the purchased OHM are isolated through self-calls, so a revert
    ///      skips the affected step with an event and the remaining steps and the heartbeat
    ///      continue. Skipped work is retried on the following beats.
    ///
    ///      Market pricing is per asset: each vault's daily cycle reads
    ///      `PRICE.getPriceIn(OHM, reserve)`, a live resolution through which the PRICE
    ///      module enforces the freshness thresholds of the configured feeds, reverting
    ///      on a stale feed or an unregistered reserve. The read runs inside the vault's
    ///      isolated self-call, so a price failure of one reserve skips only that
    ///      vault's daily cycle.
    ///
    ///      The price gate compares the OHM price denominated in the backing reserve
    ///      against the backing value. The gate read and the backing oracle read are
    ///      deliberately not isolated: both are protocol-owned dependencies of the
    ///      backing accounting, and a failure there is a configuration error that should
    ///      surface loudly.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the heart role.
    ///      - The `PRICE.getPriceIn` read of the backing reserve reverts, including when
    ///        no backing vault is designated (the PRICE module rejects the zero address).
    ///      - The backing oracle `backing()` read reverts.
    function execute() external override nonReentrant onlyRole(HEART_ROLE) {
        if (!isEnabled) return;
        _epoch += 1;

        if (_epoch % _EPOCHS_PER_DAY != 0) return;

        if (_epoch == _EPOCH_LENGTH) _weeklyReset();

        // The purchased OHM is processed before the price gate, so the burn continues
        // while markets are skipped.
        {
            (bool success, bytes memory reason) = CappedCall.tryCall(
                address(this),
                abi.encodeCall(this.selfProcessOhmPurchases, ())
            );
            if (!success) emit OhmPurchasesProcessingSkipped(reason);
        }

        // Below the backing, each purchase would release more backing on the burn than
        // the reserve it spends, growing the pool on every cycle, so market creation
        // is skipped for every vault. Skipping before any redeem also keeps the reserve
        // in the yield-earning vaults; the unspent pool rolls into the following days.
        // The gate compares like for like: the backing value and the gate price are
        // both denominated in the backing reserve.
        uint256 gatePrice = _reservePrice(_backingReserve());
        uint256 backing = _backing();
        if (gatePrice == 0 || gatePrice < backing) return;

        // In the range [1, 7]: the weekly reset has wrapped the epoch to zero
        uint256 daysRemaining = _DAYS_PER_WEEK - uint256(_epoch / _EPOCHS_PER_DAY);

        address[] storage vaults = _vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            address vault = vaults[i];
            if (!_assetConfigs[vault].isAssetEnabled) continue;

            (bool success, bytes memory reason) = CappedCall.tryCall(
                address(this),
                abi.encodeCall(this.selfProcessVaultDaily, (vault, daysRemaining))
            );
            if (!success) emit DailyCycleSkipped(vault, reason);
        }
    }

    /// @notice Runs the daily cycle of a single vault, priced by the live OHM price
    ///         denominated in the vault's reserve.
    /// @dev External only for the self-call isolation in `execute`. The function is
    ///      intentionally not `nonReentrant`: it executes within the guard held by
    ///      `execute`.
    ///
    ///      Reverts if:
    ///      - The caller is not the facility itself.
    ///      - The `PRICE.getPriceIn` read of the vault's reserve reverts.
    /// @param vault_ The vault to process.
    /// @param daysRemaining_ The number of daily cycles remaining in the week, including
    ///        this one.
    function selfProcessVaultDaily(address vault_, uint256 daysRemaining_) external {
        _requireCaller(address(this));

        ReserveAsset storage config = _assetConfigs[vault_];
        _executeDailyCycle(vault_, config, daysRemaining_, _reservePrice(config.reserve));
    }

    /// @notice Performs the weekly reset: projects the yield of the coming week,
    ///         refreshes the yield snapshots, and withdraws the previously stored
    ///         projection from the treasury into the buyback pool.
    /// @dev Every unit of yield enters the buyback pool exactly once: the yield on the
    ///      treasury-held shares through the `nextYield` projection withdrawn here, and the
    ///      appreciation of the facility-held shares directly through the balance-based daily
    ///      bids. The projection reads only treasury-side snapshots, so the facility's balances
    ///      never influence the withdrawal.
    ///
    ///      The processing of each vault is isolated through a self-call: a vault whose processing
    ///      reverts is skipped for the week with a `WeeklyResetSkipped` event and retried at the
    ///      following reset. The stored `nextYield` of a skipped vault stays in place and is
    ///      withdrawn once, at the first reset that succeeds. A skipped reset of the backing vault
    ///      forfeits that week's Clearinghouse interest: the following reset projects the interest
    ///      anew, for one week only.
    function _weeklyReset() private {
        _epoch = 0;
        // Closes the seeding window of `seedCycle`: the first beat of an `enable`
        // restart always performs the weekly reset, because the restart pins the epoch
        // counter to 20. The write shares the slot of the epoch counter.
        _cycleSeedable = false;

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

            (bool success, bytes memory reason) = CappedCall.tryCall(
                address(this),
                abi.encodeCall(this.selfProcessVaultReset, (vault, clearinghouseYield))
            );
            if (!success) emit WeeklyResetSkipped(vault, reason);
        }
    }

    /// @notice Runs the weekly reset of a single vault: projects the yield of the coming
    ///         week, refreshes the yield snapshots, and withdraws the previously stored
    ///         projection from the treasury into the buyback pool.
    /// @dev External only for the self-call isolation in `_weeklyReset`. The function is
    ///      intentionally not `nonReentrant`: it executes within the guard held by
    ///      `execute`.
    ///
    ///      The funding target is the stored `nextYield` plus the `unfundedYield` carried
    ///      from earlier shortfalls; it does not depend on the facility's balances. The
    ///      remainder the treasury balance cannot cover is stored back into
    ///      `unfundedYield` and retried at the following reset.
    ///
    ///      Reverts if the caller is not the facility itself.
    /// @param vault_ The vault to reset.
    /// @param clearinghouseYield_ The weekly Clearinghouse interest credited to the
    ///        backing vault, in backing reserve units.
    function selfProcessVaultReset(address vault_, uint256 clearinghouseYield_) external {
        _requireCaller(address(this));

        ReserveAsset storage config = _assetConfigs[vault_];

        uint256 fundingTarget = config.nextYield + config.unfundedYield;

        // The projection reads the stored snapshots against the current rate, so it must
        // run before the snapshots are refreshed below.
        uint256 newNextYield = _projectNextYield(config, clearinghouseYield_);

        _setNextYield(config, newNextYield);

        config.lastConversionRate = _conversionRate(config);

        uint256 funded = _fundFromTreasury(vault_, fundingTarget);
        config.unfundedYield = Math.saturatingSub(fundingTarget, funded);

        // The balance snapshot is taken after the funding withdrawal, so it excludes the
        // shares moved to the facility.
        config.lastReserveBalance = _getProtocolReserveBalance(vault_);
    }

    /// @notice Withdraws vault shares worth `amount_` (in reserve units) from the
    ///         treasury into the buyback pool.
    /// @dev The share amount is `previewWithdraw(amount_)` (rounded up by the vault),
    ///      capped at the treasury balance with a `PrefundShortfall` event on the cap.
    ///      The funded value is the redeemable value of the withdrawn shares (floor).
    /// @return funded The funded value, in reserve units.
    function _fundFromTreasury(address vault_, uint256 amount_) private returns (uint256 funded) {
        if (amount_ == 0) return 0;

        uint256 shares = _previewWithdraw(vault_, amount_);
        uint256 trsryBalance = _trsryBalance(vault_);
        if (shares > trsryBalance) {
            // The unfunded remainder is carried by the caller and retried at the next
            // reset.
            emit PrefundShortfall(vault_, shares, trsryBalance);
            shares = trsryBalance;
        }
        if (shares == 0) return 0;

        _withdrawShares(vault_, shares);
        funded = _previewRedeem(vault_, shares);
    }

    /// @notice Opens the daily bond market of a vault, sized from the facility's
    ///         balances.
    /// @dev The bid is the pool value divided by `daysRemaining_` (floor). For a
    ///      sell-shares asset the idle reserve balance is wrapped into vault shares
    ///      first, the pool value is the redeemable value of the held shares, and the
    ///      market capacity is the smaller of `previewWithdraw(bid)` and the held
    ///      shares, denominated in shares. Otherwise the pool value is the held reserve
    ///      plus the redeemable value of the held shares, the reserve shortfall of the
    ///      bid is redeemed from the held shares, and the bid is clamped to the reserve
    ///      actually held when the redeem falls short. A zero bid or capacity skips the
    ///      market.
    function _executeDailyCycle(
        address vault_,
        ReserveAsset storage config_,
        uint256 daysRemaining_,
        uint256 oraclePrice_
    ) private {
        address reserve_ = config_.reserve;

        if (config_.sellShares) {
            _wrapIdleReserve(vault_, reserve_);

            uint256 heldShares = _selfBalance(vault_);
            uint256 bidAmount = _previewRedeem(vault_, heldShares) / daysRemaining_;
            if (bidAmount == 0) return;

            uint256 capacityShares = Math.min(_previewWithdraw(vault_, bidAmount), heldShares);
            if (capacityShares == 0) return;

            _createMarket(vault_, config_, capacityShares, oraclePrice_);
        } else {
            uint256 currentReserve = _selfBalance(reserve_);
            uint256 heldShares = _selfBalance(vault_);

            uint256 bidAmount = (currentReserve + _previewRedeem(vault_, heldShares)) /
                daysRemaining_;
            if (bidAmount == 0) return;

            if (currentReserve < bidAmount) {
                uint256 deficit = bidAmount - currentReserve;
                uint256 redeemed = _redeemForDeficit(vault_, reserve_, deficit, heldShares);

                if (redeemed < deficit) {
                    bidAmount = currentReserve + redeemed;
                }
            }

            if (bidAmount == 0) return;

            _createMarket(vault_, config_, bidAmount, oraclePrice_);
        }
    }

    /// @notice Wraps the facility's idle reserve balance into vault shares through the
    ///         checked self-call.
    /// @dev On a failed wrap the reserve is kept, `ReserveWrapFailed` is emitted, and
    ///      the wrap is retried at the following daily cycle. A dust balance that
    ///      previews to zero shares is skipped without an event and stays on the
    ///      facility until the balance grows past the vault's rounding threshold.
    function _wrapIdleReserve(address vault_, address reserve_) private {
        uint256 idleReserve = _selfBalance(reserve_);
        if (idleReserve == 0) return;
        if (IERC4626(vault_).previewDeposit(idleReserve) == 0) return;

        (bool success, bytes memory reason) = CappedCall.tryCall(
            address(this),
            abi.encodeCall(this.selfWrapReserve, (vault_, reserve_, idleReserve))
        );
        // The failed self-call rolled back the deposit, so the reserve is still held
        if (!success) emit ReserveWrapFailed(vault_, idleReserve, reason);
    }

    /// @notice Deposits the reserve into the vault and verifies the minted shares
    ///         against the preview.
    /// @dev External only for the self-call isolation in `_wrapIdleReserve`. The
    ///      function is intentionally not `nonReentrant`: it executes within the guard
    ///      held by `execute`. The received amount is measured as the share balance
    ///      delta.
    ///
    ///      Reverts if:
    ///      - The caller is not the facility itself.
    ///      - The received shares are below `previewDeposit(amount_)`.
    /// @param vault_ The vault to deposit into.
    /// @param reserve_ The vault's reserve token.
    /// @param amount_ The reserve amount to deposit.
    function selfWrapReserve(address vault_, address reserve_, uint256 amount_) external {
        _requireCaller(address(this));

        uint256 expected = IERC4626(vault_).previewDeposit(amount_);
        uint256 sharesBefore = _selfBalance(vault_);
        IERC20(reserve_).forceApprove(vault_, amount_);
        IERC4626(vault_).deposit(amount_, address(this));
        uint256 received = _selfBalance(vault_) - sharesBefore;

        if (received < expected)
            revert IYieldRepurchaseFacilityV2_InsufficientDeposit(vault_, expected, received);
    }

    /// @notice Redeems vault shares through the checked self-call.
    /// @dev On a failed redeem the shares are kept, `RedeemFailed` is emitted, and zero
    ///      is reported as the received amount.
    /// @return received The reserve amount received.
    function _redeemShares(
        address vault_,
        address reserve_,
        uint256 shares_
    ) private returns (uint256 received) {
        if (shares_ == 0) return 0;

        (bool success, bytes memory data) = CappedCall.tryCall(
            address(this),
            abi.encodeCall(this.selfRedeemChecked, (vault_, reserve_, shares_))
        );
        if (!success) {
            // The failed self-call rolled back the redeem, so all shares are still held
            emit RedeemFailed(vault_, shares_, data);
            return 0;
        }
        // The success returndata is the one-word return of `selfRedeemChecked`, well
        // below the `CappedCall` truncation
        return abi.decode(data, (uint256));
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

    /// @notice Redeems held shares to cover a reserve deficit of the daily bid.
    /// @dev The share amount is `previewWithdraw(deficit_)` (rounded up by the vault),
    ///      capped at the held shares.
    function _redeemForDeficit(
        address vault_,
        address reserve_,
        uint256 deficit_,
        uint256 heldShares_
    ) private returns (uint256 redeemed) {
        uint256 sharesNeeded = _previewWithdraw(vault_, deficit_);
        uint256 sharesToRedeem = sharesNeeded > heldShares_ ? heldShares_ : sharesNeeded;

        redeemed = _redeemShares(vault_, reserve_, sharesToRedeem);
    }

    /// @notice Burns the purchased OHM against a backing withdrawal; the withdrawn
    ///         backing vault shares join the backing vault's buyback pool.
    /// @dev External only for the self-call isolation in `execute`. The function is
    ///      intentionally not `nonReentrant`: it executes within the guard held by
    ///      `execute`. Without a backing vault, or when the scaled backing amount, the
    ///      withdrawable share amount, or the pro-rated burn amount is zero, the
    ///      accumulated OHM is kept for later processing and nothing is withdrawn. When
    ///      the treasury balance caps the withdrawal below the backing amount, the burn
    ///      is pro-rated down (floor) and the remainder stays accumulated, so the
    ///      withdrawal never exceeds the backing of the burned OHM by more than the
    ///      pro-rating rounding.
    ///
    ///      Reverts if the caller is not the facility itself.
    function selfProcessOhmPurchases() external {
        _requireCaller(address(this));

        uint256 purchased = _ohmPurchased;
        if (purchased == 0) return;

        address backingVault_ = backingVault;
        if (backingVault_ == address(0)) return;

        uint256 backingPerOhm = _backing();

        // backingAmount18 = purchased (9 dec) * backingPerOhm (18 dec) / 10^9
        // backingAmount   = scaleFrom18(backingAmount18, reserveDecimals).
        uint256 backingAmount18 = purchased.mulDiv(backingPerOhm, 10 ** _OHM_DECIMALS);
        uint256 backingAmount = _scaleFrom18(
            backingAmount18,
            _assetConfigs[backingVault_].reserveDecimals
        );
        if (backingAmount == 0) return;

        uint256 shares = _previewWithdraw(backingVault_, backingAmount);
        uint256 trsryBalance = _trsryBalance(backingVault_);
        if (shares > trsryBalance) shares = trsryBalance;
        if (shares == 0) return;

        // The burn amount is derived from the withdrawable value before the withdrawal,
        // so nothing is withdrawn unless OHM is burned for it. The explicit full branch
        // avoids the mulDiv rounding when the treasury covers the backing in full.
        uint256 funded = _previewRedeem(backingVault_, shares);
        uint256 ohmToBurn = funded >= backingAmount
            ? purchased
            : purchased.mulDiv(funded, backingAmount);
        if (ohmToBurn == 0) return;

        _withdrawShares(backingVault_, shares);

        _ohmPurchased = purchased - ohmToBurn;
        IBurnableERC20(address(_OHM)).burn(ohmToBurn);

        emit OhmPurchasesProcessed(ohmToBurn, funded);
    }

    /// @notice Creates a bond market that sells the vault's payout token for OHM.
    /// @dev The pricing and the submission are performed by the linked `YRFBondMarketLib`
    ///      through a delegatecall, so the facility is the market owner and callback.
    ///      `oraclePrice_` is the OHM price denominated in the vault's reserve token. For
    ///      a sell-shares asset the payout token is the vault share and the reserve price
    ///      is converted to a per-share price through the conversion rate (floor): one
    ///      share is worth the conversion rate in reserve units.
    ///      The vault's previous tracked market is closed first, best-effort, so at most
    ///      one purchasable market per vault exists at a time even when missed beats
    ///      stretch the daily schedule.
    ///      Failures are absorbed: a zero conversion rate or a rejected market submission
    ///      emits `MarketCreationFailed` and keeps the funds with the facility. A created
    ///      market is recorded in `_marketVaults` under the creating auctioneer, which
    ///      authorizes its callback, and its id is tracked for the later close.
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
                emit MarketCreationFailed(vault_, bidAmount_, "");
                return;
            }
            marketOraclePrice = oraclePrice_.mulDiv(10 ** config_.reserveDecimals, conversionRate);
            payoutToken = vault_;
        }

        _closeVaultMarket(vault_);

        address auctioneer = bondAuctioneer;
        (bool success, uint256 marketId, bytes memory reason) = YRFBondMarketLib.createMarket(
            YRFBondMarketLib.MarketConfig({
                auctioneer: IBondSDA(auctioneer),
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

        // The funds stay in the buyback pool, so the following cycle retries the market
        if (!success) {
            emit MarketCreationFailed(vault_, bidAmount_, reason);
            return;
        }

        _marketVaults[auctioneer][marketId] = vault_;
        _liveMarketIds[vault_] = marketId + 1;

        emit RepoMarket(vault_, marketId, payoutToken, bidAmount_);
    }

    // ============ BOND CALLBACK ============ //

    /// @inheritdoc IBondCallback
    /// @dev The teller transfers the quote OHM before invoking the callback; the received
    ///      amount is checked against the tracked accounting, which enforces the burn
    ///      invariant `_OHM.balanceOf(this) >= _ohmPurchased`. OHM donated to the facility
    ///      counts toward the balance, so it can cover a missing quote transfer up to the
    ///      donated amount.
    ///
    ///      The market record is looked up under the current `bondAuctioneer`, so after a
    ///      bond-contract change an id colliding with a market of the outgoing contracts
    ///      cannot reach the stale record.
    ///
    ///      `outputAmount_` is teller-computed and not validated here: the payout is
    ///      bounded only by the payout-token balance held by the facility, whose transfer
    ///      reverts on an insufficient balance.
    ///
    ///      Reverts if:
    ///      - The caller is not the teller.
    ///      - The contract is disabled.
    ///      - The market was not created by this facility on the current auctioneer.
    ///      - The market's asset is disabled.
    ///      - The OHM balance is below `_ohmPurchased + inputAmount_`.
    ///      - The payout-token balance is below `outputAmount_`.
    function callback(
        uint256 id_,
        uint256 inputAmount_,
        uint256 outputAmount_
    ) external override nonReentrant {
        _requireCaller(teller);

        _requireEnabled();

        address auctioneer = bondAuctioneer;
        address vault = _marketVaults[auctioneer][id_];
        if (vault == address(0)) revert IYieldRepurchaseFacilityV2_UnknownMarket();

        ReserveAsset storage config = _assetConfigs[vault];
        _requireAssetEnabled(config);

        if (_selfBalance(address(_OHM)) < _ohmPurchased + inputAmount_)
            revert IYieldRepurchaseFacilityV2_QuoteNotReceived();

        _ohmPurchased += inputAmount_;
        uint256[2] storage marketAmounts = _amountsPerMarket[auctioneer][id_];
        marketAmounts[0] += inputAmount_;
        marketAmounts[1] += outputAmount_;

        IERC20(config.sellShares ? vault : config.reserve).safeTransfer(msg.sender, outputAmount_);
    }

    /// @inheritdoc IBondCallback
    /// @dev The amounts are scoped to the markets created on the current
    ///      `bondAuctioneer`.
    function amountsForMarket(
        uint256 id_
    ) external view override returns (uint256 in_, uint256 out_) {
        uint256[2] storage marketAmounts = _amountsPerMarket[bondAuctioneer][id_];
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
    ///      - The vault or its reserve token is OHM, the vault equals its own reserve,
    ///        or the vault or the reserve collides with the vault or the reserve of a
    ///        registered asset.
    ///      - The vault's underlying asset decimals exceed 18.
    ///      - The vault's share decimals do not match its reserve decimals (a vault with a
    ///        decimals offset is not supported).
    ///      - The `PRICE.getPriceIn(OHM, reserve)` probe reverts (for example when the
    ///        reserve is not registered in the PRICE module) or returns zero.
    ///      - The yield buyback share exceeds 100% (`1e18`).
    ///      - `setAsBackingVault_` is set together with `sellShares_`.
    ///      - `setAsBackingVault_` is set while a backing vault is already designated.
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

        // Every token balance held by the facility belongs to exactly one pool: the OHM
        // balance backs the purchased-OHM counter, and each registered vault or reserve
        // balance backs its own asset, so any collision between them is rejected.
        if (vault_ == address(_OHM) || reserve_ == address(_OHM))
            revert IYieldRepurchaseFacilityV2_TokenPoolConflict(address(_OHM));
        if (vault_ == reserve_) revert IYieldRepurchaseFacilityV2_TokenPoolConflict(vault_);

        address[] storage vaults = _vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            address registeredVault = vaults[i];
            address registeredReserve = _assetConfigs[registeredVault].reserve;
            if (registeredReserve == reserve_ || registeredVault == reserve_)
                revert IYieldRepurchaseFacilityV2_TokenPoolConflict(reserve_);
            if (registeredReserve == vault_)
                revert IYieldRepurchaseFacilityV2_TokenPoolConflict(vault_);
        }

        // The daily cycles price the vault's markets through `PRICE.getPriceIn`, so the
        // reserve must resolve against OHM at registration; a PRICE revert (for example
        // an unregistered reserve) bubbles up.
        if (_reservePrice(reserve_) == 0)
            revert IYieldRepurchaseFacilityV2_ReserveNotPriceable(reserve_);

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
            unfundedYield: 0
        });
        vaults.push(vault_);

        emit AssetAdded(vault_, reserve_, yieldBuybackShare_);
        _setNextYield(_assetConfigs[vault_], nextYield_);

        if (setAsBackingVault_) {
            // The registration path only designates the first backing vault; an existing
            // designation is replaced only through the explicit `setBackingVault`.
            if (backingVault != address(0))
                revert IYieldRepurchaseFacilityV2_BackingVaultAlreadySet();
            _setBackingVault(vault_, _assetConfigs[vault_]);
        }
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev The admin role is expected to be held only by the OCG timelock, so the
    ///      function is de-facto timelocked.
    ///
    ///      The seedable flag is armed by every `enable` restart and consumed here
    ///      before any external interaction, or by the first `execute` beat of the
    ///      restart, whichever comes first. The window is therefore hermetic: at most
    ///      one seeding per restart, and never after a beat has advanced the counter.
    ///      While the flag is armed the epoch counter holds the restart value of 20, so
    ///      no separate epoch check is needed.
    ///
    ///      Per seed, `WeeklyBudgetSeeded` is emitted before the funding withdrawal
    ///      runs, so the event precedes a `PrefundShortfall` it may cause. The remainder
    ///      the treasury balance cannot cover is added to the vault's `unfundedYield`
    ///      and retried at the following weekly reset.
    ///
    ///      The function reverts if:
    ///      - The contract is disabled.
    ///      - The caller does not hold the admin role.
    ///      - The seeding window is closed: the restart has already been seeded, or a
    ///        beat has run since the `enable`.
    ///      - `epoch_` is not below the weekly epoch count of 21.
    ///      - A seed references an unregistered or disabled vault.
    ///      - A seeded amount is zero.
    ///      - The treasury withdrawal or a preview of a seeded vault reverts.
    function seedCycle(
        uint48 epoch_,
        WeeklyBudgetSeed[] calldata budgetSeeds_
    ) external override nonReentrant givenEnabled onlyAdminRole {
        if (!_cycleSeedable) revert IYieldRepurchaseFacilityV2_CycleNotSeedable();
        _cycleSeedable = false;

        if (epoch_ >= _EPOCH_LENGTH) revert IYieldRepurchaseFacilityV2_EpochSeedTooHigh();
        _epoch = epoch_;

        uint256 seedsLength = budgetSeeds_.length;
        for (uint256 i = 0; i < seedsLength; ++i) {
            WeeklyBudgetSeed calldata seed = budgetSeeds_[i];
            ReserveAsset storage config = _requireRegistered(seed.vault);
            _requireAssetEnabled(config);
            _requireNonzeroAmount(seed.weeklyBudget);

            emit WeeklyBudgetSeeded(seed.vault, seed.weeklyBudget, epoch_);

            uint256 funded = _fundFromTreasury(seed.vault, seed.weeklyBudget);
            config.unfundedYield += Math.saturatingSub(seed.weeklyBudget, funded);
        }
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev The admin role is expected to be held only by the OCG timelock, so the
    ///      function is de-facto timelocked.
    ///
    ///      The vault's tracked live bond market, if any is left, is closed best-effort:
    ///      a revert of the auctioneer is absorbed and the market is left to expire, its
    ///      purchases reverting in `callback` for the de-registered asset.
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

        _closeVaultMarket(vault_);
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
    ///
    ///      Reverts if:
    ///      - The caller does not hold the admin role.
    ///      - `backingOracle_` is the zero address.
    ///      - The oracle does not report the 18 decimals of the backing value.
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
    ///
    ///      The tracked live markets are closed on the outgoing auctioneer before the
    ///      swap, best-effort: a revert of the auctioneer is absorbed and the affected
    ///      market is left to expire, unpurchasable (its callback is pinned to the
    ///      outgoing teller).
    ///
    ///      Reverts if:
    ///      - The caller does not hold the admin role.
    ///      - `bondAuctioneer_` is the zero address, or it reports the zero address as
    ///        its teller.
    ///      - The facility is enabled and is not authorized as a market callback on the
    ///        supplied auctioneer.
    function setBondContracts(address bondAuctioneer_) external override onlyAdminRole {
        _closeAllVaultMarkets();
        _setBondContracts(bondAuctioneer_);
    }

    /// @notice Sets the backing oracle.
    /// @dev Reverts if:
    ///      - `backingOracle_` is the zero address.
    ///      - The oracle does not report the 18 decimals of the backing value.
    function _setBackingOracle(address backingOracle_) internal {
        _requireNonzeroAddress(backingOracle_, "backingOracle");

        // The backing value is compared against the 18-decimal oracle prices and scaled
        // by the 18-decimal convention in the burn pricing, so an oracle with any other
        // scale is rejected.
        if (IBackingOracle(backingOracle_).decimals() != _BACKING_DECIMALS)
            revert IYieldRepurchaseFacilityV2_UnsupportedOracleDecimals();

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

    /// @notice Sets the bond auctioneer and caches the teller it reports.
    /// @dev The teller is resolved through `getTeller()` of the supplied auctioneer, so
    ///      the pair is consistent by construction; the auctioneer's teller is immutable,
    ///      so the cached value cannot go stale. The constructor configures the contracts
    ///      before the callback authorization can exist, so the authorization check
    ///      applies only while the facility is enabled; `_beforeEnable` covers the
    ///      disabled-to-enabled transition.
    ///
    ///      Reverts if:
    ///      - `bondAuctioneer_` is the zero address, or it reports the zero address as
    ///        its teller.
    ///      - The facility is enabled and is not authorized as a market callback on the
    ///        supplied auctioneer.
    function _setBondContracts(address bondAuctioneer_) internal {
        _requireNonzeroAddress(bondAuctioneer_, "bondAuctioneer");
        address teller_ = address(IBondAuctioneer(bondAuctioneer_).getTeller());
        _requireNonzeroAddress(teller_, "teller");

        bondAuctioneer = bondAuctioneer_;
        teller = teller_;

        if (isEnabled) _requireCallbackAuthorized();

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
    ///      projection: the following weekly funding then overstates the yield by one week
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
    ///      The next yield and the unfunded carry are reset to zero and the yield
    ///      snapshots are refreshed, so a value left over from before the asset was
    ///      disabled does not enter the funding target of the weekly reset; the yield
    ///      projection resumes at the following weekly reset.
    ///
    ///      Reverts if:
    ///      - The caller is neither the YRF timelock nor the admin.
    ///      - The vault is not registered.
    ///      - The vault is already enabled.
    function enableAsset(address vault_) external override onlyTimelockOrAdminRole {
        ReserveAsset storage config = _requireRegistered(vault_);
        _requireAssetDisabled(config);

        config.isAssetEnabled = true;
        config.unfundedYield = 0;
        _refreshSnapshots(vault_, config);

        emit AssetEnabled(vault_);
        _setNextYield(config, 0);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    /// @dev Reachable through the YRF timelock or directly by the admin, so a
    ///      per-asset halt is de-facto timelocked. An immediate halt of the whole
    ///      facility remains available to the emergency role through `disable`.
    ///
    ///      The vault's tracked live bond market is closed, best-effort: a revert of the
    ///      auctioneer is absorbed and the market is left to expire, its purchases
    ///      reverting in `callback` for the disabled asset.
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
        _closeVaultMarket(vault_);
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

    /// @notice Reverts unless the facility is authorized as a market callback on the
    ///         bond auctioneer.
    function _requireCallbackAuthorized() private view {
        if (!IBondAuctioneer(bondAuctioneer).callbackAuthorized(address(this)))
            revert IYieldRepurchaseFacilityV2_CallbackNotAuthorized();
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

    /// @notice Returns the live OHM price denominated in `reserve_`, in oracle decimals.
    /// @dev The `PRICE.getPriceIn` resolution is live: the PRICE module enforces the
    ///      freshness thresholds of the configured feeds, and reverts when the price of
    ///      either side of the pair cannot be determined.
    function _reservePrice(address reserve_) private view returns (uint256) {
        return PRICE.getPriceIn(address(_OHM), reserve_);
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
    /// @dev The lookup is scoped to the markets created on the current `bondAuctioneer`.
    function marketReserves(uint256 marketId_) external view override returns (address reserve) {
        address vault = _marketVaults[bondAuctioneer][marketId_];
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
    function isCycleSeedable() external view override returns (bool) {
        return _cycleSeedable;
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2
    function timelock() external view override returns (address) {
        return _TIMELOCK;
    }

    // ============ RESCUE ============ //

    /// @inheritdoc IBasicRescueable
    /// @dev Sweeps the rescuable balance of `token_` held by the facility to the TRSRY.
    ///
    ///      Only the OHM excess and unregistered tokens are rescuable:
    ///      - OHM is capped at the balance above the purchased-OHM accumulator.
    ///      - The share and reserve tokens of registered assets are their buyback pools
    ///        and are rejected.
    ///      - Any other token is swept in full.
    ///
    ///      Reverts if:
    ///      - The caller holds neither the yrf_admin role nor the admin role.
    ///      - `token_` is the share or the reserve token of a registered asset.
    function rescue(address token_) external override onlyYrfAdminOrAdminRole {
        uint256 rescuable;
        if (token_ == address(_OHM)) {
            // The purchased OHM backs the burn accounting and must stay on the facility
            rescuable = Math.saturatingSub(_selfBalance(token_), _ohmPurchased);
        } else {
            address[] storage vaults = _vaults;
            uint256 vaultsLength = vaults.length;
            for (uint256 i = 0; i < vaultsLength; ++i) {
                address vault = vaults[i];
                if (token_ == vault || token_ == _assetConfigs[vault].reserve)
                    revert IYieldRepurchaseFacilityV2_TokenNotRescuable(token_);
            }
            rescuable = _selfBalance(token_);
        }

        _transferToTrsry(token_, rescuable);
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
