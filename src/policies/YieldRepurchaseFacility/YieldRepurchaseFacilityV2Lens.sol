// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IBondAuctioneer} from "src/interfaces/IBondAuctioneer.sol";
import {IClearinghouseReserve} from "src/policies/interfaces/IClearinghouseReserve.sol";
import {IERC4626} from "@openzeppelin-5.3.0/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IGenericClearinghouse} from "src/policies/interfaces/IGenericClearinghouse.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2Lens} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Lens.sol";
import {IYieldRepurchaseFacilityV2View} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2View.sol";
import {IYieldRepurchaseRecipient} from "src/policies/interfaces/IYieldRepurchaseRecipient.sol";

// Libraries
import {Errors} from "src/libraries/Errors.sol";
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Constants.sol";
import {YieldRepurchaseFacilityV2MathLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2MathLib.sol";
import {YieldRepurchaseFacilityV2VaultLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2VaultLib.sol";

// Modules
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";

/// @title YieldRepurchaseFacilityV2Lens
/// @notice The derived read-only views of one YieldRepurchaseFacilityV2: the live yield
///         projection, the protocol reserve balance, the buyback pools and the daily
///         bid preview, the vault markets, the Clearinghouse component of the backing
///         yield, and the price gate.
/// @dev The lens holds no state. It reads the raw getters of the facility, the registered
///      vaults, the treasury, the Clearinghouse registry, the PRICE module, the backing
///      oracle, and the bond auctioneer, and computes through the internal libraries the
///      facility computes with: `YieldRepurchaseFacilityV2MathLib` and
///      `YieldRepurchaseFacilityV2VaultLib`. The Clearinghouse scan repeats the registry
///      loop of the facility through its offset and inclusion getters.
contract YieldRepurchaseFacilityV2Lens is IYieldRepurchaseFacilityV2Lens {
    /// @notice The facility the lens reads.
    IYieldRepurchaseFacilityV2View internal immutable _FACILITY;

    /// @notice Binds the lens to one facility.
    /// @dev Reverts if `facility_` is the zero address.
    /// @param facility_ The facility.
    constructor(address facility_) {
        if (facility_ == address(0)) revert Errors.BadInput("facility");
        _FACILITY = IYieldRepurchaseFacilityV2View(facility_);
    }

    // ============ VIEW FUNCTIONS ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2Lens
    function facility() external view override returns (address) {
        return address(_FACILITY);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Lens
    /// @dev The Clearinghouse interest is read only for the backing vault; the other
    ///      vaults do not credit it.
    function getNextYield(address vault_) external view override returns (uint256 yield) {
        IYieldRepurchaseFacilityV2.ReserveAsset memory config = _FACILITY.getAssetConfig(vault_);
        IYieldRepurchaseFacilityV2.Context memory context_ = _FACILITY.context();

        uint256 vaultYield = _vaultYield(config);
        uint256 clearinghouseYield = vault_ == context_.backingVault
            ? _clearinghouseYield(context_)
            : 0;
        yield = YieldRepurchaseFacilityV2MathLib.projectNextYield(
            vaultYield,
            clearinghouseYield,
            config.yieldBuybackShare
        );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Lens
    // The loop runs over the active Clearinghouses, activated only through the permissioned
    // CHREG module.
    // forge-lint: disable-next-item(calls-loop)
    function getReserveBalance(address vault_) external view override returns (uint256 balance) {
        IYieldRepurchaseFacilityV2.ReserveAsset memory config = _FACILITY.getAssetConfig(vault_);
        IYieldRepurchaseFacilityV2.Context memory context_ = _FACILITY.context();

        IERC20 shareToken = IERC20(config.shareToken);
        uint256 totalShares = shareToken.balanceOf(context_.trsry);

        if (vault_ == context_.backingVault) {
            CHREGv1 chreg = CHREGv1(context_.chreg);
            uint256 activeCount = chreg.activeCount();
            for (uint256 i; i < activeCount; ++i) {
                totalShares += shareToken.balanceOf(chreg.active(i));
            }
        }

        balance = YieldRepurchaseFacilityV2VaultLib.sharesToAssets(
            vault_,
            config.asyncRedeem,
            totalShares
        );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Lens
    function getClearinghouseYield() external view override returns (uint256 yield) {
        return _clearinghouseYield(_FACILITY.context());
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Lens
    // The loop runs over the CHREG registry, which grows only through permissioned activations
    // forge-lint: disable-next-item(calls-loop)
    function getClearinghouseBreakdown()
        external
        view
        override
        returns (ClearinghouseYield[] memory breakdown)
    {
        address backingReserve = _FACILITY.context().backingReserve;
        CHREGv1 chreg = CHREGv1(_FACILITY.context().chreg);

        uint256 len = chreg.registryCount();
        breakdown = new ClearinghouseYield[](len);
        for (uint256 i; i < len; ++i) {
            address ch = chreg.registry(i);
            bool counted = backingReserve != address(0) &&
                _countsTowardBackingYield(ch, backingReserve);
            uint256 receivables = _readPrincipalReceivables(ch);
            uint256 offset = _FACILITY.clearinghouseOffset(ch);
            breakdown[i] = ClearinghouseYield({
                clearinghouse: ch,
                counted: counted,
                receivables: receivables,
                offset: offset,
                interest: counted
                    ? YieldRepurchaseFacilityV2MathLib.clearinghouseInterest(receivables, offset)
                    : 0
            });
        }
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Lens
    function getBuybackPool(
        address vault_
    ) external view override returns (BuybackPool memory pool) {
        IYieldRepurchaseFacilityV2.ReserveAsset memory config = _FACILITY.getAssetConfig(vault_);

        pool.heldShares = _facilityBalance(config.shareToken);
        pool.heldReserve = _facilityBalance(config.reserve);
        pool.value =
            pool.heldReserve +
            YieldRepurchaseFacilityV2VaultLib.sharesToAssets(
                vault_,
                config.asyncRedeem,
                pool.heldShares
            );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Lens
    /// @dev The wrap of the idle reserve is counted as `previewDeposit` of the balance,
    ///      skipped when it previews to zero shares; the redeem for a deficit is counted
    ///      as `previewRedeem` of the smaller of `previewWithdraw(deficit)` and the held
    ///      shares. The daily cycle measures both as balance deltas, which the checked
    ///      self-calls require to be at least the previews.
    function previewDailyBid(
        address vault_
    ) external view override returns (uint256 capacity, uint256 daysRemaining) {
        IYieldRepurchaseFacilityV2.ReserveAsset memory config = _FACILITY.getAssetConfig(vault_);
        daysRemaining = _nextDaysRemaining();

        uint256 heldShares = _facilityBalance(config.shareToken);
        uint256 heldReserve = _facilityBalance(config.reserve);
        IERC4626 vault = IERC4626(vault_);

        if (config.sellShares) {
            if (heldReserve != 0) {
                uint256 minted = vault.previewDeposit(heldReserve);
                if (minted != 0) heldShares += minted;
            }

            uint256 bidAmount = YieldRepurchaseFacilityV2VaultLib.sharesToAssets(
                vault_,
                config.asyncRedeem,
                heldShares
            ) / daysRemaining;
            if (bidAmount == 0) return (0, daysRemaining);

            uint256 capacityShares = YieldRepurchaseFacilityV2VaultLib.assetsToShares(
                vault_,
                config.asyncRedeem,
                bidAmount
            );
            return (capacityShares < heldShares ? capacityShares : heldShares, daysRemaining);
        }

        uint256 bid = (heldReserve + vault.previewRedeem(heldShares)) / daysRemaining;
        if (bid == 0) return (0, daysRemaining);

        if (heldReserve < bid) {
            uint256 deficit = bid - heldReserve;
            uint256 sharesNeeded = vault.previewWithdraw(deficit);
            uint256 sharesToRedeem = sharesNeeded > heldShares ? heldShares : sharesNeeded;
            uint256 redeemed = sharesToRedeem == 0 ? 0 : vault.previewRedeem(sharesToRedeem);

            if (redeemed < deficit) bid = heldReserve + redeemed;
        }

        return (bid, daysRemaining);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Lens
    function getVaultMarket(
        address vault_
    ) external view override returns (bool tracked, uint256 marketId, bool live) {
        (tracked, marketId) = _FACILITY.trackedMarket(vault_);
        if (tracked) live = IBondAuctioneer(_FACILITY.bondAuctioneer()).isLive(marketId);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Lens
    /// @dev A market whose vault has been de-registered reports the zero address: the
    ///      route of the vault no longer exists.
    function marketReserve(uint256 marketId_) external view override returns (address reserve) {
        address vault = _FACILITY.marketVault(marketId_);
        if (vault == address(0)) return address(0);

        // A de-registered vault reverts the route read; the view then reports no reserve
        try IYieldRepurchaseRecipient(address(_FACILITY)).getVaultConfig(vault) returns (
            IYieldRepurchaseRecipient.VaultConfig memory route
        ) {
            return route.asset;
        } catch {
            return address(0);
        }
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Lens
    function priceGate()
        external
        view
        override
        returns (bool open, uint256 gatePrice, uint256 backing)
    {
        IYieldRepurchaseFacilityV2.Context memory context_ = _FACILITY.context();

        gatePrice = PRICEv2(context_.price).getPriceIn(context_.ohm, context_.backingReserve);
        backing = IBackingOracle(context_.backingOracle).backing();
        open = gatePrice != 0 && gatePrice >= backing;
    }

    // ============ HELPERS ============ //

    /// @notice Returns the vault yield accrued since the snapshots of a configuration,
    ///         in reserve units; with the rate snapshot unset the vault is not read.
    function _vaultYield(
        IYieldRepurchaseFacilityV2.ReserveAsset memory config_
    ) private view returns (uint256) {
        uint256 lastRate = config_.lastConversionRate;
        if (lastRate == 0) return 0;

        uint256 currentRate = YieldRepurchaseFacilityV2VaultLib.conversionRate(
            config_.vault,
            config_.asyncRedeem,
            config_.reserveDecimals
        );
        return
            YieldRepurchaseFacilityV2MathLib.vaultYield(
                config_.lastReserveBalance,
                lastRate,
                currentRate
            );
    }

    /// @notice Sums the weekly interest of every registry Clearinghouse that counts
    ///         toward the backing yield; zero when no backing vault is designated.
    // The loop runs over the CHREG registry, which grows only through permissioned activations
    // forge-lint: disable-next-item(calls-loop)
    function _clearinghouseYield(
        IYieldRepurchaseFacilityV2.Context memory context_
    ) private view returns (uint256 yield) {
        address backingReserve = context_.backingReserve;
        if (backingReserve == address(0)) return 0;

        CHREGv1 chreg = CHREGv1(context_.chreg);
        uint256 len = chreg.registryCount();
        for (uint256 i; i < len; ++i) {
            address ch = chreg.registry(i);
            if (!_countsTowardBackingYield(ch, backingReserve)) continue;
            yield += YieldRepurchaseFacilityV2MathLib.clearinghouseInterest(
                _readPrincipalReceivables(ch),
                _FACILITY.clearinghouseOffset(ch)
            );
        }
    }

    /// @notice Returns whether a Clearinghouse counts toward the backing yield: either
    ///         it is included, or its reserve matches the backing reserve.
    // Called once per entry of the governance-bounded registry scans
    // forge-lint: disable-next-item(calls-loop)
    function _countsTowardBackingYield(
        address clearinghouse_,
        address backingReserve_
    ) private view returns (bool) {
        return
            _FACILITY.isClearinghouseIncluded(clearinghouse_) ||
            _readClearinghouseReserve(clearinghouse_) == backingReserve_;
    }

    /// @notice Returns the number of daily cycles remaining in the week at the next daily
    ///         cycle, including that one.
    /// @dev The next daily cycle runs at the next epoch that is a multiple of three; the
    ///      21st epoch performs the weekly reset first, which wraps the counter to zero.
    function _nextDaysRemaining() private view returns (uint256) {
        uint48 epoch = _FACILITY.epoch();
        // The next multiple of three above the counter: the epoch of the next daily cycle
        uint48 nextDailyEpoch = epoch +
            (YieldRepurchaseFacilityV2Constants.EPOCHS_PER_DAY -
                (epoch % YieldRepurchaseFacilityV2Constants.EPOCHS_PER_DAY));
        if (nextDailyEpoch == YieldRepurchaseFacilityV2Constants.EPOCH_LENGTH) nextDailyEpoch = 0;

        return
            YieldRepurchaseFacilityV2Constants.DAYS_PER_WEEK -
            uint256(nextDailyEpoch / YieldRepurchaseFacilityV2Constants.EPOCHS_PER_DAY);
    }

    /// @notice Reads the Clearinghouse's `principalReceivables`, treating a revert as
    ///         zero.
    // Called once per entry of the governance-bounded registry scans
    // forge-lint: disable-next-item(calls-loop)
    function _readPrincipalReceivables(address clearinghouse_) private view returns (uint256) {
        try IGenericClearinghouse(clearinghouse_).principalReceivables() returns (
            uint256 receivables
        ) {
            return receivables;
        } catch {
            return 0;
        }
    }

    /// @notice Reads the Clearinghouse's reserve token, treating a revert as the zero
    ///         address.
    // Called once per entry of the governance-bounded registry scans
    // forge-lint: disable-next-item(calls-loop)
    function _readClearinghouseReserve(address clearinghouse_) private view returns (address) {
        try IClearinghouseReserve(clearinghouse_).reserve() returns (address reserve) {
            return reserve;
        } catch {
            return address(0);
        }
    }

    /// @notice Returns the facility's `token_` balance.
    function _facilityBalance(address token_) private view returns (uint256) {
        return IERC20(token_).balanceOf(address(_FACILITY));
    }
}
