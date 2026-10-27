// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IBondCallback} from "src/interfaces/IBondCallback.sol";
import {IBurnableERC20} from "src/interfaces/IBurnableERC20.sol";
import {IERC4626} from "@openzeppelin-5.3.0/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-5.3.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IBasicRescueable} from "src/interfaces/IBasicRescueable.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IYieldRepurchaseFacilityV2Steps} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Steps.sol";
import {IYieldRepurchaseFacilityV2View} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2View.sol";
import {IYieldRepurchaseFacilityV2Write} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Write.sol";
import {IYieldRepurchaseRecipient} from "src/policies/interfaces/IYieldRepurchaseRecipient.sol";

// Libraries
import {SafeCall} from "src/libraries/SafeCall.sol";
import {SafeERC20} from "@openzeppelin-5.3.0/token/ERC20/utils/SafeERC20.sol";
import {YieldRepurchaseFacilityV2AssetRegistryLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2AssetRegistryLib.sol";
import {YieldRepurchaseFacilityV2BondMarketLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2BondMarketLib.sol";
import {YieldRepurchaseFacilityV2BuybackPoolLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2BuybackPoolLib.sol";
import {YieldRepurchaseFacilityV2ClearinghouseLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2ClearinghouseLib.sol";
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Constants.sol";
import {YieldRepurchaseFacilityV2DependenciesLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2DependenciesLib.sol";
import {YieldRepurchaseFacilityV2MathLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2MathLib.sol";
import {YieldRepurchaseFacilityV2ValidationLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2ValidationLib.sol";
import {YieldRepurchaseFacilityV2VaultLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2VaultLib.sol";
import {YieldRepurchaseFacilityV2YieldLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2YieldLib.sol";

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
///      The facility is a recipient of protocol yield: a sender delivers the reserve
///      token or the vault shares of a registered asset with a plain transfer, and
///      discovers the registered vaults through the `IYieldRepurchaseRecipient`
///      surface.
///
///      A registered vault is called through its ERC4626 functions, and its shares are
///      held and transferred as its share token: the vault itself, or the token an
///      ERC7575 vault names through `share()`. The shares are valued through the
///      vault's previews; an asset whose vault redeems asynchronously (ERC7540) is
///      flagged `asyncRedeem`, sells shares, and is valued through `convertToAssets`
///      and `convertToShares` (see `YieldRepurchaseFacilityV2VaultLib`).
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
///      The configuration setters are callable only by the configurator, the
///      configuration policy bound through `setConfigurator`. The gas limit of the
///      isolated steps is set on the facility itself, through `setStepGasLimit`
///      (yrf_admin or admin).
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
    IYieldRepurchaseFacilityV2Write,
    IYieldRepurchaseFacilityV2View,
    IYieldRepurchaseFacilityV2Steps,
    IYieldRepurchaseRecipient
{
    using SafeERC20 for IERC20;
    using YieldRepurchaseFacilityV2AssetRegistryLib for YieldRepurchaseFacilityV2AssetRegistryLib.Registry;
    using YieldRepurchaseFacilityV2ClearinghouseLib for YieldRepurchaseFacilityV2ClearinghouseLib.Clearinghouses;
    using YieldRepurchaseFacilityV2BondMarketLib for YieldRepurchaseFacilityV2BondMarketLib.Markets;

    // ============ CONSTANTS ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    uint32 public constant override MAX_GRACE_PERIOD =
        YieldRepurchaseFacilityV2Constants.MAX_GRACE_PERIOD;

    /// @notice Minimum length of the `enable` payload.
    /// @dev Four 32-byte words: `initialDiscount`, `maxPricePremium`, the seed array
    ///      offset, and the seed array length.
    uint256 private constant _MIN_ENABLE_PARAMS_LENGTH = 128;

    // ============ IMMUTABLES ============ //

    /// @notice The OHM token.
    IERC20 private immutable _OHM;

    /// @notice The cached OHM decimals (9 on mainnet).
    uint8 private immutable _OHM_DECIMALS;

    // ============ MODULES ============ //

    TRSRYv1 internal TRSRY;
    PRICEv2 internal PRICE;
    CHREGv1 internal CHREG;

    /// @notice Cached `PRICE.decimals()`.
    uint8 internal _oracleDecimals;

    // ============ STATE ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    address public override configurator;

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    address public override backingOracle;

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    address public override bondTeller;

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    address public override bondAuctioneer;

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    uint256 public override initialDiscount;

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    uint256 public override maxPricePremium;

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    /// @dev Initialized by the constructor and changed through `setStepGasLimit`; the
    ///      value does not depend on `enable`. It shares the storage slot of the epoch
    ///      counter.
    uint32 public override stepGasLimit;

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

    /// @notice The asset registry: the per-vault configurations and accounting, the vault
    ///         list, the reserve lookup, and the backing vault designation.
    YieldRepurchaseFacilityV2AssetRegistryLib.Registry internal _registry;

    /// @notice The Clearinghouse configuration: the receivables offsets and the
    ///         inclusions.
    YieldRepurchaseFacilityV2ClearinghouseLib.Clearinghouses internal _clearinghouses;

    /// @notice The bond market records: the funding vault and the amounts of each market
    ///         created on an auctioneer, and the tracked live market of each vault.
    YieldRepurchaseFacilityV2BondMarketLib.Markets internal _markets;

    // ============ SETUP ============ //

    /// @dev The teller is resolved from the auctioneer (`getTeller`), so the pair is
    ///      consistent by construction.
    ///
    ///      Reverts if:
    ///      - `kernel_` or `ohm_` is the zero address
    ///        (`IYieldRepurchaseFacilityV2_ZeroAddress`).
    ///      - `backingOracle_` is the zero address or does not report `kernel_` as its
    ///        kernel (`IYieldRepurchaseFacilityV2_InvalidBackingOracle`).
    ///      - The backing oracle does not report the 18 decimals of the backing value.
    ///      - `bondAuctioneer_` is the zero address or reports the zero address as its
    ///        teller (`IYieldRepurchaseFacilityV2_InvalidBondAuctioneer`).
    ///      - `gracePeriod_` is zero or not less than `MAX_GRACE_PERIOD`.
    ///      - `stepGasLimit_` is below `1_100_000` or above `5_000_000`.
    /// @param kernel_ The Olympus Kernel.
    /// @param ohm_ The OHM token address.
    /// @param backingOracle_ The OHM backing oracle policy address.
    /// @param bondAuctioneer_ The Bond Protocol SDA auctioneer.
    /// @param gracePeriod_ The initial re-enable grace window, in seconds.
    /// @param stepGasLimit_ The initial gas limit of one isolated step, in gas units.
    constructor(
        Kernel kernel_,
        address ohm_,
        address backingOracle_,
        address bondAuctioneer_,
        uint32 gracePeriod_,
        uint32 stepGasLimit_
    ) Policy(kernel_) ReEnablerGracePeriod(gracePeriod_) {
        _requireNonzeroAddress(address(kernel_));
        _requireNonzeroAddress(ohm_);
        _requireValidGracePeriod(gracePeriod_);

        _OHM = IERC20(ohm_);
        _OHM_DECIMALS = IERC20Metadata(ohm_).decimals();

        // The deployment is not activated in the Kernel yet, so the registry activation of
        // the oracle is not required here
        _setBackingOracle(backingOracle_, false);
        _setBondContracts(bondAuctioneer_);
        _setStepGasLimit(stepGasLimit_);

        // Disabled by default by EnablerV2
    }

    /// @inheritdoc Policy
    /// @dev The modules are resolved and their versions validated by the linked
    ///      `YieldRepurchaseFacilityV2DependenciesLib`.
    ///
    ///      Reverts if:
    ///      - Any of the TRSRY, PRICE, CHREG, or ROLES modules does not report major
    ///        version 1.
    ///      - The PRICE module reports a minor version below 2. The facility prices the
    ///        assets through `PRICE.getPriceIn`, which the PRICE surface provides from
    ///        version 1.2.
    ///      - `PRICE.decimals()` is not 18, the decimals of the backing value.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        YieldRepurchaseFacilityV2DependenciesLib.Modules memory modules;
        (dependencies, modules) = YieldRepurchaseFacilityV2DependenciesLib.configureDependencies(
            kernel
        );

        TRSRY = TRSRYv1(modules.trsry);
        PRICE = PRICEv2(modules.price);
        CHREG = CHREGv1(modules.chreg);
        ROLES = ROLESv1(modules.roles);
        _oracleDecimals = modules.oracleDecimals;
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
        return YieldRepurchaseFacilityV2DependenciesLib.permissions();
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

    /// @notice Reverts unless the caller is the configurator and the reentrancy guard is not
    ///         held.
    modifier onlyConfigurator() {
        _requireConfigurator();
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
    ///      - The payload is shorter than the minimum
    ///        `abi.encode(uint256, uint256, NextYieldSeed[])`.
    ///      - The payload does not `abi.decode` as `(uint256, uint256, NextYieldSeed[])`.
    ///      - The configurator is unset, is not an active policy of the facility's
    ///        kernel, does not report the facility's kernel as its own, does not
    ///        advertise `IYieldRepurchaseFacilityV2Config`, or does not report this
    ///        facility as its `facility()`.
    ///      - The facility is not authorized as a market callback on the bond
    ///        auctioneer.
    ///      - The initial discount is not less than 100% (`1e18`).
    ///      - The max price premium is above 1,000% (`10e18`).
    ///      - A seed references an unregistered or disabled vault.
    ///      - The share valuation of an enabled vault (`previewRedeem`, or
    ///        `convertToAssets` for an asset with asynchronous redemption) or a
    ///        `balanceOf` read of its share token reverts.
    function _beforeEnable(bytes calldata data_) internal override {
        if (data_.length < _MIN_ENABLE_PARAMS_LENGTH)
            revert IYieldRepurchaseFacilityV2_InvalidEnableDataLength();

        YieldRepurchaseFacilityV2DependenciesLib.validateConfigurator(kernel, configurator);
        YieldRepurchaseFacilityV2DependenciesLib.requireCallbackAuthorized(bondAuctioneer);

        (
            uint256 initialDiscount_,
            uint256 maxPricePremium_,
            NextYieldSeed[] memory nextYieldSeeds
        ) = abi.decode(data_, (uint256, uint256, NextYieldSeed[]));
        _setInitialDiscount(initialDiscount_);
        _setMaxPricePremium(maxPricePremium_);

        _resetCycle(nextYieldSeeds);
    }

    /// @notice Restarts the weekly cycle: zeroes the yields and unfunded carries of the
    ///         enabled assets, applies the supplied next-yield seeds, refreshes their
    ///         yield snapshots, rewinds the epoch counter so that the next `execute`
    ///         performs a weekly reset, and opens the seeding window of `seedCycle`.
    /// @dev The restart of the per-asset accounting is performed by the linked
    ///      `YieldRepurchaseFacilityV2YieldLib`. Disabled assets are not touched and are
    ///      not seedable: a
    ///      seed for a disabled vault would be erased by the reset `enableAsset`
    ///      performs, so it is rejected instead. A single `NextYieldSet` event with the
    ///      resulting value is emitted per enabled vault; when the seed array contains
    ///      duplicates, the last entry wins.
    ///
    ///      Reverts if a seed references an unregistered or disabled vault.
    /// @param nextYieldSeeds_ The per-vault `nextYield` values to apply after the reset.
    function _resetCycle(NextYieldSeed[] memory nextYieldSeeds_) private {
        YieldRepurchaseFacilityV2YieldLib.restart(_registry, nextYieldSeeds_, _context());

        _epoch = YieldRepurchaseFacilityV2Constants.EPOCH_LENGTH - 1;
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
        _markets.closeAllVaultMarkets(_context(), _registry.vaults);
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
    ///      to market submissions the auctioneer rejects. The configurator binding is
    ///      re-checked with the conditions of `setConfigurator`.
    ///
    ///      Reverts if:
    ///      - The grace window since the disable has elapsed.
    ///      - The configurator is unset, is not an active policy of the facility's
    ///        kernel, does not report the facility's kernel as its own, does not
    ///        advertise `IYieldRepurchaseFacilityV2Config`, or does not report this
    ///        facility as its `facility()`.
    function _beforeReEnable() internal override(ReEnabler, ReEnablerGracePeriod) {
        super._beforeReEnable();
        YieldRepurchaseFacilityV2DependenciesLib.validateConfigurator(kernel, configurator);
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

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev The function complements the `disable`, which only halts operation
    ///      and leaves the funds in place so that `reEnable` can resume the interrupted
    ///      week. Call this function after a disable when the facility is not expected to
    ///      be re-enabled soon, or when holding funds on the facility is a concern. The
    ///      per-vault `nextYield` and `unfundedYield` are intentionally preserved, so a
    ///      later `reEnable` or `enable` refunds the facility from the treasury at the
    ///      next weekly reset.
    ///
    ///      The sweep of each vault is isolated through a self-call that runs with
    ///      `stepGasLimit` gas (see `_callStep`): a vault whose sweep reverts or runs out
    ///      of that gas is skipped with a `FundsReturnSkipped` event, keeping its
    ///      balances in place, and is retried by the next call. The OHM burn and
    ///      transfer are not isolated: OHM is a protocol-owned token whose balance
    ///      always covers the tracked purchased amount.
    ///
    ///      Reverts if:
    ///      - The contract is enabled.
    ///      - The caller holds neither the emergency role nor the admin role.
    ///      - The gas remaining before the sweep of a vault is below the step
    ///        requirement (`IYieldRepurchaseFacilityV2_InsufficientStepGas`). No vault is
    ///        skipped for a shortage of gas of the caller: the whole call reverts and
    ///        succeeds when repeated with more gas.
    function returnFundsToTreasury() external override givenDisabled onlyEmergencyOrAdminRole {
        uint256 purchasedOhm = _ohmPurchased;
        if (purchasedOhm != 0) {
            _ohmPurchased = 0;
            IBurnableERC20(address(_OHM)).burn(purchasedOhm);
        }

        // The OHM remaining after the burn is untracked (donated) balance
        _sweepToTrsry(address(_OHM));

        address[] storage vaults = _registry.vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i; i < vaultsLength; ++i) {
            address vault = vaults[i];
            (bool success, bytes memory reason) = _callStep(
                abi.encodeCall(this.selfReturnVaultFunds, (vault))
            );
            if (!success) emit FundsReturnSkipped(vault, reason);
        }

        emit FundsReturnedToTreasury(purchasedOhm);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Steps
    /// @dev External only for the self-call isolation in `returnFundsToTreasury`.
    ///
    ///      Reverts if the caller is not the facility itself.
    function selfReturnVaultFunds(address vault_) external override {
        _requireCaller(address(this));

        ReserveAsset storage config = _registry.configs[vault_];
        _returnBalancesToTrsry(config.shareToken, config.reserve);
    }

    // ============ PERIODIC TASK ============ //

    /// @inheritdoc IPeriodicTask
    /// @dev The beat must survive a misbehaving vault: the processing of each vault and the
    ///      processing of the purchased OHM are isolated through self-calls, so a revert
    ///      skips the affected step with an event and the remaining steps and the heartbeat
    ///      continue. Skipped work is retried on the following beats.
    ///
    ///      Each isolated step (the weekly reset of a vault, the processing of the
    ///      purchased OHM, and the daily cycle of a vault) runs with `stepGasLimit` gas
    ///      (see `_callStep`), so a step that consumes its whole limit is skipped like
    ///      a reverting one, and a beat consumes at most about
    ///      `(2 * N + 1) * stepGasLimit` gas in the steps of `N` enabled vaults. The
    ///      calls nested in a daily cycle (the reserve wrap, the redeem, and the close
    ///      and the creation of a market) run on the gas remaining in that step.
    ///
    ///      `IPeriodicTask` asks an implementation to avoid reverting. A shortage of gas
    ///      of the caller is the exception: a step that cannot be handed its full
    ///      `stepGasLimit` is not skipped, the whole call reverts, and the beat succeeds
    ///      when repeated with more gas.
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
    ///      - The gas remaining before an isolated step is below the step requirement
    ///        (`IYieldRepurchaseFacilityV2_InsufficientStepGas`).
    function execute() external override nonReentrant onlyRole(HEART_ROLE) {
        if (!isEnabled) return;
        _epoch += 1;

        if (_epoch % YieldRepurchaseFacilityV2Constants.EPOCHS_PER_DAY != 0) return;

        if (_epoch == YieldRepurchaseFacilityV2Constants.EPOCH_LENGTH) _weeklyReset();

        // The purchased OHM is processed before the price gate, so the burn continues
        // while markets are skipped.
        {
            (bool success, bytes memory reason) = _callStep(
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
        uint256 daysRemaining = YieldRepurchaseFacilityV2Constants.DAYS_PER_WEEK -
            uint256(_epoch / YieldRepurchaseFacilityV2Constants.EPOCHS_PER_DAY);

        address[] storage vaults = _registry.vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i; i < vaultsLength; ++i) {
            address vault = vaults[i];
            if (!_registry.configs[vault].isAssetEnabled) continue;

            (bool success, bytes memory reason) = _callStep(
                abi.encodeCall(this.selfProcessVaultDaily, (vault, daysRemaining))
            );
            if (!success) emit DailyCycleSkipped(vault, reason);
        }
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Steps
    /// @dev External only for the self-call isolation in `execute`. The function is
    ///      intentionally not `nonReentrant`: it executes within the guard held by
    ///      `execute`. The price is read first; the bid is then sized from the facility's
    ///      balances by the linked `YieldRepurchaseFacilityV2BuybackPoolLib`, which wraps
    ///      the idle reserve of a sell-shares asset and redeems the shares covering the
    ///      reserve shortfall of the bid through the checked self-calls, and the market
    ///      is opened by the linked `YieldRepurchaseFacilityV2BondMarketLib`. A zero bid
    ///      or capacity opens no market.
    ///
    ///      Reverts if:
    ///      - The caller is not the facility itself.
    ///      - The `PRICE.getPriceIn` read of the vault's reserve reverts.
    function selfProcessVaultDaily(address vault_, uint256 daysRemaining_) external override {
        _requireCaller(address(this));

        ReserveAsset storage config = _registry.configs[vault_];
        uint256 oraclePrice = _reservePrice(config.reserve);

        uint256 capacity = YieldRepurchaseFacilityV2BuybackPoolLib.dailyBid(config, daysRemaining_);
        if (capacity == 0) return;

        _markets.openMarket(_context(), config, capacity, oraclePrice);
    }

    /// @notice Performs the weekly reset: projects the yield of the coming week,
    ///         refreshes the yield snapshots, and withdraws the previously stored
    ///         projection from the treasury into the buyback pool.
    /// @dev The yield enters the buyback pool through two channels: the stored `nextYield`
    ///      projection, withdrawn from the treasury here, and the appreciation of the shares
    ///      held by the facility, included in the balance-based daily bids. The projection does
    ///      not read the facility's balances, so they never influence the withdrawal.
    ///
    ///      The projection credits the rate change on the stored balance snapshot (see
    ///      `_computeVaultYield`), so the channels overlap for the shares that move from the
    ///      treasury to the facility after the snapshot, such as the backing withdrawn for the
    ///      burned OHM: those shares stay in the basis of the following projection, and their
    ///      appreciation also enters the daily bids while the facility holds them.
    ///
    ///      The processing of each vault is isolated through a self-call that runs with
    ///      `stepGasLimit` gas (see `_callStep`): a vault whose processing reverts or runs out of
    ///      that gas is skipped for the week with a `WeeklyResetSkipped` event and retried at the
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

        Context memory context_ = _context();
        uint256 clearinghouseYield = _clearinghouses.clearinghouseYield(context_);
        _clearinghouses.emitClearinghouseMismatches(context_);

        address[] storage vaults = _registry.vaults;
        uint256 vaultsLength = vaults.length;
        for (uint256 i; i < vaultsLength; ++i) {
            address vault = vaults[i];
            if (!_registry.configs[vault].isAssetEnabled) continue;

            (bool success, bytes memory reason) = _callStep(
                abi.encodeCall(this.selfProcessVaultReset, (vault, clearinghouseYield))
            );
            if (!success) emit WeeklyResetSkipped(vault, reason);
        }
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Steps
    /// @dev External only for the self-call isolation in `_weeklyReset`. The function is
    ///      intentionally not `nonReentrant`: it executes within the guard held by
    ///      `execute`.
    ///
    ///      The projection and the snapshots are performed by the linked
    ///      `YieldRepurchaseFacilityV2YieldLib` around the treasury withdrawal, which
    ///      stays here. The funding target is the stored `nextYield` plus the
    ///      `unfundedYield` carried from earlier shortfalls; it does not depend on the
    ///      facility's balances. The remainder the treasury balance cannot cover is
    ///      stored back into `unfundedYield` and retried at the following reset.
    ///
    ///      Reverts if the caller is not the facility itself.
    function selfProcessVaultReset(address vault_, uint256 clearinghouseYield_) external override {
        _requireCaller(address(this));

        ReserveAsset storage config = _registry.configs[vault_];
        Context memory context_ = _context();

        uint256 fundingTarget = YieldRepurchaseFacilityV2YieldLib.beginWeeklyReset(
            config,
            context_,
            clearinghouseYield_
        );

        uint256 funded = _fundFromTreasury(config, fundingTarget);

        YieldRepurchaseFacilityV2YieldLib.finishWeeklyReset(
            config,
            context_,
            fundingTarget,
            funded
        );
    }

    /// @notice Withdraws vault shares worth `amount_` (in reserve units) from the
    ///         treasury into the buyback pool.
    /// @dev The share amount covers `amount_` rounded up (`previewWithdraw`, or the
    ///      raised `convertToShares` of an asset with asynchronous redemption, see
    ///      `YieldRepurchaseFacilityV2VaultLib.assetsToShares`), capped at the treasury balance
    ///      of the share
    ///      token with a `FundingShortfall` event on the cap. The funded value is the
    ///      value of the withdrawn shares (floor; `previewRedeem`, or `convertToAssets`
    ///      for asynchronous redemption).
    /// @return funded The funded value, in reserve units.
    function _fundFromTreasury(
        ReserveAsset storage config_,
        uint256 amount_
    ) private returns (uint256 funded) {
        if (amount_ == 0) return 0;

        address vault_ = config_.vault;
        address shareToken = config_.shareToken;

        uint256 shares = YieldRepurchaseFacilityV2VaultLib.assetsToShares(
            vault_,
            config_.asyncRedeem,
            amount_
        );
        uint256 trsryBalance = _trsryBalance(shareToken);
        if (shares > trsryBalance) {
            // The unfunded remainder is carried by the caller and retried at the next
            // reset.
            emit FundingShortfall(vault_, shares, trsryBalance);
            shares = trsryBalance;
        }
        if (shares == 0) return 0;

        _withdrawShares(shareToken, shares);
        funded = YieldRepurchaseFacilityV2VaultLib.sharesToAssets(
            vault_,
            config_.asyncRedeem,
            shares
        );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Steps
    /// @dev External only for the self-call isolation of the wrap of the daily cycle:
    ///      the daily cycle of the linked `YieldRepurchaseFacilityV2BuybackPoolLib`
    ///      reaches this function through a call to the facility, and the wrap itself
    ///      (`wrapReserve`) runs in that library. The function is intentionally not
    ///      `nonReentrant`: it executes within the guard held by `execute`. The received
    ///      amount is measured as the balance delta of the share token.
    ///
    ///      Reverts if:
    ///      - The caller is not the facility itself.
    ///      - The received shares are below `previewDeposit(amount_)`.
    function selfWrapReserve(address vault_, uint256 amount_) external override {
        _requireCaller(address(this));

        YieldRepurchaseFacilityV2BuybackPoolLib.wrapReserve(_registry.configs[vault_], amount_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Steps
    /// @dev External only for the self-call isolation of the redeem of the daily cycle:
    ///      the daily cycle of the linked `YieldRepurchaseFacilityV2BuybackPoolLib`
    ///      reaches this function through a call to the facility, and the redeem itself
    ///      (`redeemChecked`) runs in that library. The function is intentionally not
    ///      `nonReentrant`: it executes within the guard held by the external entry
    ///      point. The received amount is measured as the reserve balance delta.
    ///
    ///      Reverts if:
    ///      - The caller is not the facility itself.
    ///      - The redeem reverts.
    ///      - The received reserve is below `previewRedeem(shares_)`.
    function selfRedeemChecked(
        address vault_,
        uint256 shares_
    ) external override returns (uint256 received) {
        _requireCaller(address(this));

        return
            YieldRepurchaseFacilityV2BuybackPoolLib.redeemChecked(
                _registry.configs[vault_],
                shares_
            );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Steps
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
    function selfProcessOhmPurchases() external override {
        _requireCaller(address(this));

        uint256 purchased = _ohmPurchased;
        if (purchased == 0) return;

        address backingVault_ = _registry.backingVault;
        if (backingVault_ == address(0)) return;

        uint256 backingPerOhm = _backing();

        // backingAmount18 = purchased (9 dec) * backingPerOhm (18 dec) / 10^9
        // backingAmount   = scaleBackingAmount(backingAmount18, reserveDecimals).
        uint256 backingAmount18 = YieldRepurchaseFacilityV2MathLib.backingAmount(
            purchased,
            backingPerOhm,
            _OHM_DECIMALS
        );
        ReserveAsset storage backingConfig = _registry.configs[backingVault_];
        uint256 backingAmount = YieldRepurchaseFacilityV2MathLib.scaleBackingAmount(
            backingAmount18,
            backingConfig.reserveDecimals
        );
        if (backingAmount == 0) return;

        address backingShareToken = backingConfig.shareToken;
        uint256 shares = _previewWithdraw(backingVault_, backingAmount);
        uint256 trsryBalance = _trsryBalance(backingShareToken);
        if (shares > trsryBalance) shares = trsryBalance;
        if (shares == 0) return;

        // The burn amount is derived from the withdrawable value before the withdrawal,
        // so nothing is withdrawn unless OHM is burned for it.
        uint256 funded = _previewRedeem(backingVault_, shares);
        uint256 ohmToBurn = YieldRepurchaseFacilityV2MathLib.ohmToBurn(
            purchased,
            funded,
            backingAmount
        );
        if (ohmToBurn == 0) return;

        _ohmPurchased = purchased - ohmToBurn;

        _withdrawShares(backingShareToken, shares);
        IBurnableERC20(address(_OHM)).burn(ohmToBurn);

        emit OhmPurchasesProcessed(ohmToBurn, funded);
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
    ///      cannot reach the stale record. Only the tracked live market of the vault is
    ///      purchasable: a market that has been superseded or whose close was attempted
    ///      is rejected even when it is still live on the auctioneer.
    ///
    ///      `outputAmount_` is teller-computed and not validated here: the payout is
    ///      bounded only by the payout-token balance held by the facility, whose transfer
    ///      reverts on an insufficient balance.
    ///
    ///      Reverts if:
    ///      - The caller is not the teller.
    ///      - The contract is disabled.
    ///      - The market was not created by this facility on the current auctioneer.
    ///      - The market is not the tracked live market of its vault.
    ///      - The market's asset is disabled.
    ///      - The OHM balance is below `_ohmPurchased + inputAmount_`.
    ///      - The payout-token balance is below `outputAmount_`.
    function callback(
        uint256 id_,
        uint256 inputAmount_,
        uint256 outputAmount_
    ) external override nonReentrant {
        _requireCaller(bondTeller);

        _requireEnabled();

        address auctioneer = bondAuctioneer;
        address vault = _markets.marketVaults[auctioneer][id_];
        if (vault == address(0)) revert IYieldRepurchaseFacilityV2_UnknownMarket();
        if (_markets.liveMarketIds[vault] != id_ + 1)
            revert IYieldRepurchaseFacilityV2_MarketNotCurrent();

        ReserveAsset storage config = _registry.configs[vault];
        _requireAssetEnabled(config);

        if (_selfBalance(address(_OHM)) < _ohmPurchased + inputAmount_)
            revert IYieldRepurchaseFacilityV2_QuoteNotReceived();

        _ohmPurchased += inputAmount_;
        uint256[2] storage marketAmounts = _markets.amounts[auctioneer][id_];
        marketAmounts[0] += inputAmount_;
        marketAmounts[1] += outputAmount_;

        IERC20(config.sellShares ? config.shareToken : config.reserve).safeTransfer(
            msg.sender,
            outputAmount_
        );
    }

    /// @inheritdoc IBondCallback
    /// @dev The amounts are scoped to the markets created on the current
    ///      `bondAuctioneer`.
    function amountsForMarket(
        uint256 id_
    ) external view override returns (uint256 in_, uint256 out_) {
        uint256[2] storage marketAmounts = _markets.amounts[bondAuctioneer][id_];
        return (marketAmounts[0], marketAmounts[1]);
    }

    /// @inheritdoc IBondCallback
    /// @dev Not supported: the facility serves only its own markets, authorized through
    ///      the market records. Always reverts.
    function whitelist(address, uint256) external pure override {
        revert IYieldRepurchaseFacilityV2_NotSupported();
    }

    /// @inheritdoc IBondCallback
    /// @dev Not supported: the facility serves only its own markets, authorized through
    ///      the market records. Always reverts.
    function blacklist(address, uint256) external pure override {
        revert IYieldRepurchaseFacilityV2_NotSupported();
    }

    // ============ ADMIN FUNCTIONS ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev Callable only by the configurator.
    ///
    ///      The asset is registered in the enabled state. The validation, the
    ///      registration, and the backing vault designation are performed by the linked
    ///      `YieldRepurchaseFacilityV2AssetRegistryLib`.
    ///
    ///      Reverts if:
    ///      - The caller is not the configurator.
    ///      - The reentrancy guard is held by `execute`, `callback`, or `seedCycle`.
    ///      - The vault address is the zero address
    ///        (`IYieldRepurchaseFacilityV2_ZeroAddress`).
    ///      - The vault is already registered.
    ///      - The vault reports the zero address as its underlying asset
    ///        (`IYieldRepurchaseFacilityV2_VaultProbeZeroResult`).
    ///      - The vault's underlying asset decimals exceed 18.
    ///      - The vault advertises asynchronous deposits (`IERC7540Deposit`) through
    ///        ERC165.
    ///      - The vault advertises asynchronous redemption (`IERC7540Redeem`) through
    ///        ERC165 without advertising ERC7575, or while `sellShares` is unset.
    ///      - The vault advertises ERC7575 through ERC165 and reports the zero address
    ///        as its `share()` (`IYieldRepurchaseFacilityV2_VaultProbeZeroResult`).
    ///      - The share token decimals do not match the reserve decimals (a vault with a
    ///        decimals offset is not supported).
    ///      - The vault, its share token, or its reserve token is OHM, the vault or the
    ///        share token equals the reserve, or any of the three collides with the
    ///        vault, the share token, or the reserve of a registered asset.
    ///      - A probe of the vault with one whole share or one whole reserve unit
    ///        (`previewRedeem`, `previewWithdraw`, and `previewDeposit`; for a vault with
    ///        asynchronous redemption `convertToAssets`, `convertToShares`, and
    ///        `previewDeposit`) reverts, returns less than one word, or returns zero.
    ///      - The `PRICE.getPriceIn(OHM, reserve)` probe reverts (for example when the
    ///        reserve is not registered in the PRICE module) or returns zero.
    ///      - The yield buyback share exceeds 100% (`1e18`).
    ///      - `setAsBackingVault` is set together with `sellShares`.
    ///      - `setAsBackingVault` is set while a backing vault is already designated.
    function addAsset(AddAssetParams calldata params_) external override onlyConfigurator {
        _registry.addAsset(_context(), params_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
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
    ///      Per seed, `BuybackPoolSeeded` is emitted before the funding withdrawal
    ///      runs, so the event precedes a `FundingShortfall` it may cause. The remainder
    ///      the treasury balance cannot cover is added to the vault's `unfundedYield`
    ///      and retried at the following weekly reset.
    ///
    ///      Reverts if:
    ///      - The contract is disabled.
    ///      - The caller does not hold the admin role.
    ///      - The seeding window is closed: the restart has already been seeded, or a
    ///        beat has run since the `enable`.
    ///      - `epoch_` is not below the weekly epoch count of 21.
    ///      - A seed references an unregistered or disabled vault.
    ///      - A seeded amount is zero (`IYieldRepurchaseFacilityV2_ZeroAmount`).
    ///      - The treasury withdrawal or a share valuation of a seeded vault reverts.
    function seedCycle(
        uint48 epoch_,
        BuybackPoolSeed[] calldata poolSeeds_
    ) external override nonReentrant givenEnabled onlyAdminRole {
        if (!_cycleSeedable) revert IYieldRepurchaseFacilityV2_CycleNotSeedable();
        _cycleSeedable = false;

        if (epoch_ >= YieldRepurchaseFacilityV2Constants.EPOCH_LENGTH)
            revert IYieldRepurchaseFacilityV2_EpochSeedTooHigh();
        _epoch = epoch_;

        uint256 seedsLength = poolSeeds_.length;
        for (uint256 i; i < seedsLength; ++i) {
            BuybackPoolSeed calldata seed = poolSeeds_[i];
            ReserveAsset storage config = _requireRegistered(seed.vault);
            _requireAssetEnabled(config);
            _requireNonzeroAmount(seed.amount);

            emit BuybackPoolSeeded(seed.vault, seed.amount, epoch_);

            uint256 funded = _fundFromTreasury(config, seed.amount);
            config.unfundedYield += YieldRepurchaseFacilityV2MathLib.unfundedRemainder(
                seed.amount,
                funded
            );
        }
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev Callable only by the configurator.
    ///
    ///      The removal is validated and performed by the linked
    ///      `YieldRepurchaseFacilityV2AssetRegistryLib`. The vault's tracked live bond
    ///      market, if any is left, is closed best-effort: a revert of the auctioneer is
    ///      absorbed and the market is left to expire, its purchases reverting in
    ///      `callback` for the de-registered asset. The balances are returned to the
    ///      treasury here, before the de-registration.
    ///
    ///      Reverts if:
    ///      - The caller is not the configurator.
    ///      - The reentrancy guard is held by `execute`, `callback`, or `seedCycle`.
    ///      - The vault is not registered.
    ///      - The vault is currently enabled.
    ///      - The vault is currently set as the `backingVault`.
    function removeAsset(address vault_) external override onlyConfigurator {
        _registry.validateRemove(vault_);

        _markets.closeVaultMarket(_context(), vault_);
        ReserveAsset storage config = _registry.configs[vault_];
        _returnBalancesToTrsry(config.shareToken, config.reserve);

        _registry.remove(vault_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev The admin role is expected to be held only by the OCG timelock, so the
    ///      function is de-facto timelocked.
    ///
    ///      The setter additionally requires the oracle to be an active policy of the
    ///      kernel: a rotation runs after the deployment is activated, unlike the
    ///      constructor wiring.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the admin role.
    ///      - `backingOracle_` is the zero address, is not an active policy of the
    ///        kernel, or does not report the facility's kernel as its own
    ///        (`IYieldRepurchaseFacilityV2_InvalidBackingOracle`).
    ///      - The oracle does not report the 18 decimals of the backing value.
    function setBackingOracle(address backingOracle_) external override onlyAdminRole {
        _setBackingOracle(backingOracle_, true);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev The admin role is expected to be held only by the OCG timelock, so the
    ///      function is de-facto timelocked. The binding is revalidated by `enable` and
    ///      `reEnable`.
    ///
    ///      Reverts if:
    ///      - The contract is enabled.
    ///      - The caller does not hold the admin role.
    ///      - `configurator_` is the zero address, is not an active policy of the
    ///        facility's kernel, does not report the facility's kernel as its own, does
    ///        not advertise `IYieldRepurchaseFacilityV2Config`, or does not report this
    ///        facility as its `facility()`.
    // forge-lint: disable-next-item(missing-zero-check)
    function setConfigurator(address configurator_) external override givenDisabled onlyAdminRole {
        YieldRepurchaseFacilityV2DependenciesLib.validateConfigurator(kernel, configurator_);

        configurator = configurator_;
        emit ConfiguratorSet(configurator_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev Callable only by the configurator. The change is validated and stored by the
    ///      linked `YieldRepurchaseFacilityV2AssetRegistryLib`.
    ///
    ///      The vault's tracked live bond market is closed before the change; the
    ///      close is not isolated, so a revert of the auctioneer reverts the change.
    ///      The per-vault accounting (the yield projection, the snapshots, and the
    ///      carries) is denominated in reserve units in both modes and is left
    ///      untouched; the held share and reserve balances are spent by the following
    ///      daily cycles under the new mode. The reserve mode requires a redeemable
    ///      vault: with `sellShares_` unset the daily cycles redeem the held shares for
    ///      the bids, so on a vault whose redeem reverts the redeem is skipped with
    ///      `RedeemFailed`, the bid is clamped to the held reserve balance, and a zero
    ///      bid opens no market.
    ///
    ///      Reverts if:
    ///      - The caller is not the configurator.
    ///      - The reentrancy guard is held by `execute`, `callback`, or `seedCycle`.
    ///      - The vault is not registered.
    ///      - The stored mode already equals `sellShares_`.
    ///      - `sellShares_` is set while the vault is the backing vault.
    ///      - `sellShares_` is unset while the asset is flagged `asyncRedeem`: the reserve
    ///        mode redeems the held shares synchronously.
    ///      - The close of the vault's tracked live bond market reverts.
    function setSellShares(address vault_, bool sellShares_) external override onlyConfigurator {
        _registry.validateSellShares(vault_, sellShares_);
        _markets.closeVaultMarketStrict(_context(), vault_);

        _registry.setSellShares(vault_, sellShares_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev Callable only by the configurator. The refresh is performed by the linked
    ///      `YieldRepurchaseFacilityV2AssetRegistryLib`.
    ///
    ///      The flag is re-read from the vault's ERC165 advertisement of
    ///      `IERC7540Redeem`; a vault that does not implement ERC165 reads as
    ///      synchronous. The share token, the yield snapshots, and the tracked live bond
    ///      market are left untouched. Raising the flag for an asset that does not sell
    ///      shares requires `setSellShares` first, which the backing vault cannot
    ///      satisfy.
    ///
    ///      While the stored flag is unset for a vault that has switched to asynchronous
    ///      redemption, the valuation calls `previewRedeem` and `previewWithdraw`, which
    ///      such a vault reverts: the weekly reset and the daily cycle of the asset are
    ///      skipped with `WeeklyResetSkipped` and `DailyCycleSkipped`, and `enable`
    ///      (while the asset is enabled), `enableAsset`, and a `seedCycle` seed of the
    ///      asset revert.
    ///
    ///      Reverts if:
    ///      - The caller is not the configurator.
    ///      - The reentrancy guard is held by `execute`, `callback`, or `seedCycle`.
    ///      - The vault is not registered.
    ///      - The mode the vault advertises equals the stored flag.
    ///      - The vault advertises asynchronous redemption while the asset does not sell
    ///        shares.
    function refreshAsyncRedeem(address vault_) external override onlyConfigurator {
        _registry.refreshAsyncRedeem(vault_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev Reverts if:
    ///      - The caller is not the configurator.
    ///      - The reentrancy guard is held by `execute`, `callback`, or `seedCycle`.
    ///      - The vault is not registered.
    ///      - The asset is disabled.
    ///      - The asset sells vault shares.
    function setBackingVault(address vault_) external override onlyConfigurator {
        _registry.setBackingVault(vault_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
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
    ///        its teller (`IYieldRepurchaseFacilityV2_InvalidBondAuctioneer`).
    ///      - The facility is enabled and is not authorized as a market callback on the
    ///        supplied auctioneer.
    function setBondContracts(address bondAuctioneer_) external override onlyAdminRole {
        // The context carries the outgoing auctioneer, on which the markets were created; the
        // function is gated to the admin role
        // forge-lint: disable-next-line(reentrancy-no-eth)
        _markets.closeAllVaultMarkets(_context(), _registry.vaults);
        _setBondContracts(bondAuctioneer_);
    }

    /// @notice Sets the backing oracle after the validation of the linked
    ///         `YieldRepurchaseFacilityV2DependenciesLib`.
    /// @dev Reverts if:
    ///      - `backingOracle_` is the zero address
    ///        (`IYieldRepurchaseFacilityV2_InvalidBackingOracle`).
    ///      - `requireActive_` is set and the oracle is not an active policy of the kernel.
    ///      - The oracle does not report the facility's kernel as its own.
    ///      - The oracle does not report the 18 decimals of the backing value.
    function _setBackingOracle(address backingOracle_, bool requireActive_) private {
        YieldRepurchaseFacilityV2DependenciesLib.validateBackingOracle(
            kernel,
            backingOracle_,
            requireActive_
        );

        backingOracle = backingOracle_;
        emit BackingOracleSet(backingOracle_);
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
    ///        its teller (`IYieldRepurchaseFacilityV2_InvalidBondAuctioneer`).
    ///      - The facility is enabled and is not authorized as a market callback on the
    ///        supplied auctioneer.
    function _setBondContracts(address bondAuctioneer_) private {
        address bondTeller_ = YieldRepurchaseFacilityV2DependenciesLib.resolveBondContracts(
            bondAuctioneer_,
            isEnabled
        );

        bondAuctioneer = bondAuctioneer_;
        bondTeller = bondTeller_;

        emit BondContractsSet(bondAuctioneer_, bondTeller_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev The setter does not depend on the enabled state: the limit also applies to
    ///      the sweep of `returnFundsToTreasury`, which runs only while the facility is
    ///      disabled.
    ///
    ///      Reverts if:
    ///      - The caller holds neither the yrf_admin role nor the admin role.
    ///      - `stepGasLimit_` is below `1_100_000` or above `5_000_000`.
    function setStepGasLimit(uint32 stepGasLimit_) external override onlyYrfAdminOrAdminRole {
        _setStepGasLimit(stepGasLimit_);
    }

    /// @notice Sets the gas limit of an isolated step.
    /// @dev Reverts if `stepGasLimit_` is below `1_100_000` or above `5_000_000`.
    function _setStepGasLimit(uint32 stepGasLimit_) private {
        if (
            stepGasLimit_ < YieldRepurchaseFacilityV2Constants.MIN_STEP_GAS_LIMIT ||
            stepGasLimit_ > YieldRepurchaseFacilityV2Constants.MAX_STEP_GAS_LIMIT
        ) revert IYieldRepurchaseFacilityV2_StepGasLimitOutOfBounds();

        stepGasLimit = stepGasLimit_;
        emit StepGasLimitSet(stepGasLimit_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev Callable only by the configurator.
    ///
    ///      The offset is subtracted from the Clearinghouse's principal receivables when
    ///      the weekly reset projects the next yield, so it is expected that a correction
    ///      made at any point before the reset keeps the excess receivables out of
    ///      the projected yield.
    ///
    ///      Reverts if:
    ///      - The caller is not the configurator.
    ///      - The reentrancy guard is held by `execute`, `callback`, or `seedCycle`.
    ///      - The Clearinghouse is the zero address
    ///        (`IYieldRepurchaseFacilityV2_ZeroAddress`).
    ///      - The offset exceeds the current `principalReceivables` of the Clearinghouse.
    function setClearinghouseOffset(
        address clearinghouse_,
        uint256 offset_
    ) external override onlyConfigurator {
        _clearinghouses.setOffset(clearinghouse_, offset_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev The change is validated and stored by the linked
    ///      `YieldRepurchaseFacilityV2AssetRegistryLib`.
    ///
    ///      Reverts if:
    ///      - The caller is not the configurator.
    ///      - The reentrancy guard is held by `execute`, `callback`, or `seedCycle`.
    ///      - The vault is not registered.
    ///      - The share exceeds 100% (`1e18`).
    function setYieldBuybackShare(
        address vault_,
        uint256 newShare_
    ) external override onlyConfigurator {
        _registry.setYieldBuybackShare(vault_, newShare_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev The only enforced bound is below 100% (`1e18`). A discount large enough to
    ///      overflow the market scale computation degrades to skipped markets
    ///      (`DailyCycleSkipped` or `MarketCreationFailed`) and does not block the beat.
    ///
    ///      Reverts if:
    ///      - The caller is not the configurator.
    ///      - The reentrancy guard is held by `execute`, `callback`, or `seedCycle`.
    ///      - The initial discount is not less than 100% (`1e18`).
    function setInitialDiscount(uint256 initialDiscount_) external override onlyConfigurator {
        _setInitialDiscount(initialDiscount_);
    }

    /// @notice Sets the initial discount.
    /// @dev Reverts if `initialDiscount_` is not less than 100% (`1e18`).
    function _setInitialDiscount(uint256 initialDiscount_) internal {
        YieldRepurchaseFacilityV2ValidationLib.requireValidInitialDiscount(initialDiscount_);

        initialDiscount = initialDiscount_;
        emit InitialDiscountSet(initialDiscount_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev The only enforced bound is at or below 1,000% (`10e18`). The premium widens
    ///      the decay band of the markets created after the change; the markets already
    ///      live keep the band they were created with.
    ///
    ///      Reverts if:
    ///      - The caller is not the configurator.
    ///      - The reentrancy guard is held by `execute`, `callback`, or `seedCycle`.
    ///      - The max price premium is above 1,000% (`10e18`).
    function setMaxPricePremium(uint256 maxPricePremium_) external override onlyConfigurator {
        _setMaxPricePremium(maxPricePremium_);
    }

    /// @notice Sets the max price premium.
    /// @dev Reverts if `maxPricePremium_` is above 1,000% (`10e18`).
    function _setMaxPricePremium(uint256 maxPricePremium_) internal {
        YieldRepurchaseFacilityV2ValidationLib.requireValidMaxPricePremium(maxPricePremium_);

        maxPricePremium = maxPricePremium_;
        emit MaxPricePremiumSet(maxPricePremium_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev The offset is read live by the weekly reset projection, so an increase
    ///      applied only after a reset misses that projection: the following weekly
    ///      funding then overstates the yield by one week of interest on the missing
    ///      offset. When that matters, the emergency role can `disable` the facility
    ///      before the reset beat (the cycle freezes in place), the increase can be
    ///      applied while the facility is disabled, and the yrf_admin can `reEnable`; the
    ///      reset then runs with the offset applied.
    ///
    ///      The function only increases the offset, which reduces the projected yield;
    ///      the offset is lowered through `setClearinghouseOffset`.
    ///
    ///      Reverts if:
    ///      - The caller is not the configurator.
    ///      - The reentrancy guard is held by `execute`, `callback`, or `seedCycle`.
    ///      - The Clearinghouse is the zero address
    ///        (`IYieldRepurchaseFacilityV2_ZeroAddress`).
    ///      - The resulting offset exceeds the current `principalReceivables`.
    function increaseClearinghouseOffset(
        address clearinghouse_,
        uint256 additionalOffset_
    ) external override onlyConfigurator {
        _clearinghouses.setOffset(
            clearinghouse_,
            _clearinghouses.offsets[clearinghouse_] + additionalOffset_
        );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev The function corrects a stored projection
    ///      that is known to overstate the yield, for example when a receivables offset
    ///      executed only after the weekly reset that made the projection. The stored
    ///      value is consumed by the following weekly reset, so the correction can be
    ///      applied at any point of the running week. The compare-and-set guard makes a
    ///      correction that outlives its target harmless: once a weekly reset has
    ///      replaced the stored value with a fresh projection, the stale correction
    ///      reverts instead of cutting the fresh value. The correction is validated and
    ///      stored by the linked `YieldRepurchaseFacilityV2YieldLib`.
    ///
    ///      Reverts if:
    ///      - The caller is not the configurator.
    ///      - The reentrancy guard is held by `execute`, `callback`, or `seedCycle`.
    ///      - The vault is not registered.
    ///      - The stored next yield does not equal `expectedNextYield_`.
    ///      - `newNextYield_` is not lower than the stored value.
    function decreaseNextYield(
        address vault_,
        uint256 expectedNextYield_,
        uint256 newNextYield_
    ) external override onlyConfigurator {
        YieldRepurchaseFacilityV2YieldLib.decreaseNextYield(
            _registry,
            vault_,
            expectedNextYield_,
            newNextYield_
        );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev Callable only by the configurator.
    ///
    ///      By default only Clearinghouses whose reserve matches the backing reserve are
    ///      counted. Inclusion is meant for Clearinghouses whose receivables accrue to the
    ///      backing reserve, so the receivables must be denominated in a token with the same
    ///      decimals as the backing reserve. The receivables offset of the Clearinghouse
    ///      applies as usual. A Clearinghouse whose `reserve()` read reverts (for
    ///      example when the function is not exposed) never matches the backing
    ///      reserve, so it is counted only while included.
    ///
    ///      The inclusion is validated: the address must be present in the CHREG
    ///      registry (the registry is append-only, so an included Clearinghouse stays
    ///      iterable), and its `principalReceivables()` must be readable (a zero value
    ///      is valid). The weekly reset still treats a receivables read that reverts
    ///      later as zero, so a Clearinghouse that breaks after the inclusion degrades
    ///      to a zero contribution instead of blocking the reset.
    ///
    ///      Reverts if:
    ///      - The caller is not the configurator.
    ///      - The reentrancy guard is held by `execute`, `callback`, or `seedCycle`.
    ///      - The Clearinghouse is already included.
    ///      - `clearinghouse_` is not present in the CHREG registry.
    ///      - The `principalReceivables()` read reverts.
    function includeClearinghouse(address clearinghouse_) external override onlyConfigurator {
        _clearinghouses.include(_context(), clearinghouse_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev The immediate defensive lever against a misbehaving Clearinghouse is the
    ///      emergency `disable` of the facility, which freezes the cycle in place until
    ///      the exclusion is applied.
    ///
    ///      Reverts if:
    ///      - The caller is not the configurator.
    ///      - The reentrancy guard is held by `execute`, `callback`, or `seedCycle`.
    ///      - The Clearinghouse is not included.
    function excludeClearinghouse(address clearinghouse_) external override onlyConfigurator {
        _clearinghouses.exclude(clearinghouse_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev The change is validated and performed by the linked
    ///      `YieldRepurchaseFacilityV2YieldLib`: the asset is enabled, and its next yield
    ///      and unfunded carry are reset to zero and its yield snapshots refreshed, so a
    ///      value left over from before the asset was disabled does not enter the funding
    ///      target of the weekly reset; the yield projection resumes at the following
    ///      weekly reset.
    ///
    ///      Reverts if:
    ///      - The caller is not the configurator.
    ///      - The reentrancy guard is held by `execute`, `callback`, or `seedCycle`.
    ///      - The vault is not registered.
    ///      - The vault is already enabled.
    function enableAsset(address vault_) external override onlyConfigurator {
        YieldRepurchaseFacilityV2YieldLib.enableAsset(_registry, vault_, _context());
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Write
    /// @dev An immediate halt of the whole facility is available to the emergency role
    ///      through `disable`.
    ///
    ///      The change is validated and stored by the linked
    ///      `YieldRepurchaseFacilityV2AssetRegistryLib`. The vault's tracked live bond
    ///      market is then closed, best-effort: a revert of the auctioneer is absorbed and
    ///      the market is left to expire, its purchases reverting in `callback` for the
    ///      disabled asset.
    ///
    ///      Reverts if:
    ///      - The caller is not the configurator.
    ///      - The reentrancy guard is held by `execute`, `callback`, or `seedCycle`.
    ///      - The vault is not registered.
    ///      - The vault is already disabled.
    ///      - The vault is the backing vault.
    function disableAsset(address vault_) external override onlyConfigurator {
        _registry.disable(vault_);
        _markets.closeVaultMarket(_context(), vault_);
        emit AssetDisabled(vault_);
    }

    // ============ HELPERS ============ //

    /// @notice Returns the reserve token of the backing vault, or the zero address when
    ///         no backing vault is designated.
    function _backingReserve() private view returns (address) {
        address backingVault_ = _registry.backingVault;
        if (backingVault_ == address(0)) return address(0);
        return _registry.configs[backingVault_].reserve;
    }

    /// @notice Returns the config of a registered vault, reverting with
    ///         `IYieldRepurchaseFacilityV2_AssetNotRegistered` for an unregistered one.
    // Called from the `seedCycle` loop, where an invalid seed must reject the whole seeding
    // forge-lint: disable-next-item(require-revert-in-loop)
    function _requireRegistered(
        address vault_
    ) private view returns (ReserveAsset storage config_) {
        config_ = _registry.configs[vault_];
        if (config_.vault == address(0))
            revert IYieldRepurchaseFacilityV2_AssetNotRegistered(vault_);
    }

    /// @notice Reverts with `IYieldRepurchaseFacilityV2_ZeroAddress` when `value_` is the
    ///         zero address.
    function _requireNonzeroAddress(address value_) private pure {
        if (value_ == address(0)) revert IYieldRepurchaseFacilityV2_ZeroAddress();
    }

    /// @notice Reverts with `IYieldRepurchaseFacilityV2_ZeroAmount` when the amount is zero.
    // Called from the `seedCycle` loop, where an invalid seed must reject the whole seeding
    // forge-lint: disable-next-item(require-revert-in-loop)
    function _requireNonzeroAmount(uint256 amount_) private pure {
        if (amount_ == 0) revert IYieldRepurchaseFacilityV2_ZeroAmount();
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

    /// @notice Reverts unless the asset is enabled.
    // Called from the `seedCycle` loop, where an invalid seed must reject the whole seeding
    // forge-lint: disable-next-item(require-revert-in-loop)
    function _requireAssetEnabled(ReserveAsset storage config_) private view {
        YieldRepurchaseFacilityV2ValidationLib.requireAssetEnabled(config_.isAssetEnabled);
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
    // Reached from the `seedCycle` loop over the admin-supplied seeds; the other loops reach it
    // only through the isolating self-calls.
    // forge-lint: disable-next-item(calls-loop)
    function _balanceOf(address token_, address account_) private view returns (uint256) {
        return IERC20(token_).balanceOf(account_);
    }

    /// @notice Reverts unless the caller is the configurator and the reentrancy guard is not
    ///         held.
    /// @dev The guard is held by `execute`, `callback`, and `seedCycle`, so a configurator
    ///      call made during one of them reverts with `ReentrancyGuardReentrantCall`.
    function _requireConfigurator() private view {
        if (msg.sender != configurator)
            revert IYieldRepurchaseFacilityV2_OnlyConfigurator(msg.sender);
        if (_reentrancyGuardEntered()) revert ReentrancyGuardReentrantCall();
    }

    /// @notice Performs an isolated self-call that runs one step with exactly
    ///         `stepGasLimit` gas and no value, and captures the returndata truncated to
    ///         `MAX_RETURNDATA_LENGTH` bytes.
    /// @dev A call forwards at most 63/64 of the gas available to the calling frame
    ///      (EIP-150), so the step is handed its full limit only when the frame holds
    ///      `stepGasLimit + stepGasLimit / 63` gas at the call. The check runs
    ///      immediately before the call and adds `STEP_GAS_MARGIN`, which covers the gas
    ///      spent between the check and the call and the work that follows a step that
    ///      consumed its whole limit: the skip event and the advance to the next check.
    ///
    ///      A step therefore fails only on its own account, by reverting or by
    ///      consuming its limit, and never because the caller supplied too little gas.
    ///
    ///      Reverts if the remaining gas is below
    ///      `stepGasLimit + stepGasLimit / 63 + STEP_GAS_MARGIN`.
    /// @param callData_ The calldata of the self-call.
    /// @return success Whether the step succeeded.
    /// @return data The captured returndata, truncated to `MAX_RETURNDATA_LENGTH` bytes;
    ///         empty when the step ran out of gas.
    // Called from the per-vault loops, where a shortage of gas of the caller must revert the
    // whole call instead of skipping a step.
    // forge-lint: disable-next-item(require-revert-in-loop)
    function _callStep(bytes memory callData_) private returns (bool success, bytes memory data) {
        uint256 gasLimit = stepGasLimit;

        // required = gasLimit + gasLimit / 63 (floor) + margin, all in gas units
        uint256 required = gasLimit +
            gasLimit /
            YieldRepurchaseFacilityV2Constants.STEP_GAS_RETENTION_DIVISOR +
            YieldRepurchaseFacilityV2Constants.STEP_GAS_MARGIN;
        uint256 available = gasleft();
        if (available < required)
            revert IYieldRepurchaseFacilityV2_InsufficientStepGas(required, available);

        return
            SafeCall.safeCall(
                address(this),
                gasLimit,
                0,
                YieldRepurchaseFacilityV2Constants.MAX_RETURNDATA_LENGTH,
                callData_
            );
    }

    /// @notice Reverts unless the caller is `caller_`.
    function _requireCaller(address caller_) private view {
        if (msg.sender != caller_) revert IYieldRepurchaseFacilityV2_InvalidCaller();
    }

    /// @notice Reverts unless the grace window is strictly shorter than `MAX_GRACE_PERIOD`.
    function _requireValidGracePeriod(uint32 period_) private pure {
        if (period_ >= MAX_GRACE_PERIOD) revert IYieldRepurchaseFacilityV2_GracePeriodTooLong();
    }

    /// @notice Transfers the facility's balances of the share token and the reserve to
    ///         the treasury.
    function _returnBalancesToTrsry(address shareToken_, address reserve_) private {
        _sweepToTrsry(shareToken_);
        _sweepToTrsry(reserve_);
    }

    /// @notice Withdraws vault shares from the treasury under a just-in-time approval.
    // Reached from the `seedCycle` loop over the admin-supplied seeds; the other loops reach it
    // only through the isolating self-calls.
    // forge-lint: disable-next-item(calls-loop)
    function _withdrawShares(address shareToken_, uint256 shares_) private {
        TRSRY.increaseWithdrawApproval(address(this), SolmateERC20(shareToken_), shares_);
        TRSRY.withdrawReserves(address(this), SolmateERC20(shareToken_), shares_);
    }

    // ============ VIEW FUNCTIONS ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    /// @dev The function also implements `IYieldRepurchaseRecipient.getVaults`.
    function getVaults()
        external
        view
        override(IYieldRepurchaseFacilityV2View, IYieldRepurchaseRecipient)
        returns (address[] memory)
    {
        return _registry.vaults;
    }

    /// @inheritdoc IYieldRepurchaseRecipient
    /// @dev `enabled` reports the per-asset `isAssetEnabled` flag only; the enabled state
    ///      of the facility is available through `isEnabled`.
    ///
    ///      Reverts if:
    ///      - The vault is not registered
    ///        (`YieldRepurchaseRecipient_VaultNotRegistered`).
    function getVaultConfig(
        address vault_
    ) external view override returns (VaultConfig memory config) {
        ReserveAsset storage assetConfig = _registry.configs[vault_];
        if (assetConfig.vault == address(0))
            revert YieldRepurchaseRecipient_VaultNotRegistered(vault_);

        config = VaultConfig({
            vault: vault_,
            shareToken: assetConfig.shareToken,
            asset: assetConfig.reserve,
            enabled: assetConfig.isAssetEnabled
        });
    }

    /// @inheritdoc IYieldRepurchaseRecipient
    /// @dev The underlying asset of the interface is the reserve token of a registered
    ///      asset. The lookup is kept by `addAsset` and `removeAsset`, and does not
    ///      depend on the enabled state of the asset or of the facility.
    function getAssetVault(address asset_) external view override returns (address vault) {
        return _registry.reserveVaults[asset_];
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    function getAssetConfig(
        address vault_
    ) external view override returns (ReserveAsset memory config) {
        config = _requireRegistered(vault_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    /// @dev The lookup is scoped to the markets created on the current `bondAuctioneer`.
    function marketVault(uint256 marketId_) external view override returns (address vault) {
        return _markets.marketVaults[bondAuctioneer][marketId_];
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    function trackedMarket(
        address vault_
    ) external view override returns (bool tracked, uint256 marketId) {
        uint256 marketIdPlusOne = _markets.liveMarketIds[vault_];
        tracked = marketIdPlusOne != 0;
        if (tracked) marketId = marketIdPlusOne - 1;
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    function backingVault() external view override returns (address) {
        return _registry.backingVault;
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    function clearinghouseOffset(address clearinghouse_) external view override returns (uint256) {
        return _clearinghouses.offsets[clearinghouse_];
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    function isClearinghouseIncluded(address clearinghouse_) external view override returns (bool) {
        return _clearinghouses.included[clearinghouse_];
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    function ohmPurchased() external view override returns (uint256) {
        return _ohmPurchased;
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    function epoch() external view override returns (uint48) {
        return _epoch;
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    function isCycleSeedable() external view override returns (bool) {
        return _cycleSeedable;
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2View
    function context() external view override returns (Context memory) {
        return _context();
    }

    /// @notice Assembles the dependencies of the facility for the linked libraries.
    /// @dev The structure is built once per entry point and passed to the libraries,
    ///      which cannot read the immutable bindings of the facility through a
    ///      `DELEGATECALL`.
    function _context() private view returns (Context memory context_) {
        address backingVault_ = _registry.backingVault;
        context_ = Context({
            trsry: address(TRSRY),
            price: address(PRICE),
            chreg: address(CHREG),
            ohm: address(_OHM),
            ohmDecimals: _OHM_DECIMALS,
            oracleDecimals: _oracleDecimals,
            backingOracle: backingOracle,
            backingVault: backingVault_,
            backingReserve: backingVault_ == address(0)
                ? address(0)
                : _registry.configs[backingVault_].reserve,
            bondAuctioneer: bondAuctioneer,
            bondTeller: bondTeller,
            initialDiscount: initialDiscount,
            maxPricePremium: maxPricePremium
        });
    }

    // ============ RESCUE ============ //

    /// @inheritdoc IBasicRescueable
    /// @dev Sweeps the rescuable balance of `token_` held by the facility to the TRSRY.
    ///
    ///      Only the OHM excess and unregistered tokens are rescuable:
    ///      - OHM is capped at the balance above the purchased-OHM accumulator.
    ///      - The vault, the share token, and the reserve token of a registered asset
    ///        are rejected: the share and reserve balances are the asset's buyback pool.
    ///      - Any other token is swept in full.
    ///
    ///      Reverts if:
    ///      - The caller holds neither the yrf_admin role nor the admin role.
    ///      - `token_` is the vault, the share token, or the reserve token of a
    ///        registered asset.
    function rescue(address token_) external override onlyYrfAdminOrAdminRole {
        _transferToTrsry(token_, _registry.rescuableAmount(token_, address(_OHM), _ohmPurchased));
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
            interfaceId_ == type(IYieldRepurchaseFacilityV2Write).interfaceId ||
            interfaceId_ == type(IYieldRepurchaseFacilityV2View).interfaceId ||
            interfaceId_ == type(IYieldRepurchaseRecipient).interfaceId ||
            interfaceId_ == type(IBondCallback).interfaceId ||
            interfaceId_ == type(IPeriodicTask).interfaceId ||
            interfaceId_ == type(IBasicRescueable).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
