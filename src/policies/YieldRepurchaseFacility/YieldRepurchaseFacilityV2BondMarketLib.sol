// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IBondAuctioneer} from "src/interfaces/IBondAuctioneer.sol";
import {IBondSDA} from "src/interfaces/IBondSDA.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";
import {SafeCall} from "src/libraries/SafeCall.sol";
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Constants.sol";
import {YieldRepurchaseFacilityV2MathLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2MathLib.sol";
import {YieldRepurchaseFacilityV2VaultLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2VaultLib.sol";

// Contracts
import {ERC20 as SolmateERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

/// @title YieldRepurchaseFacilityV2BondMarketLib
/// @notice An external library that owns the bond market records of the
///         YieldRepurchaseFacilityV2 and opens and closes its Bond Protocol SDA markets.
/// @dev The library is deployed separately and reached through `DELEGATECALL`, so the
///      storage parameters reference the calling facility's storage, the emitted events
///      belong to the facility interface, and the market submission originates from the
///      facility: the facility is the market owner and the market callback, and the
///      auctioneer's callback authorization applies to the facility address. The bond
///      callback itself stays with the facility, which reads and writes the records
///      directly. The pricing is that of `YieldRepurchaseFacilityV2MathLib`.
library YieldRepurchaseFacilityV2BondMarketLib {
    using FullMath for uint256;

    /// @notice Bond market debt buffer (`100_000` = 100%).
    uint32 internal constant BOND_DEBT_BUFFER = 100_000;

    /// @notice Bond market deposit interval (4 hours).
    uint32 internal constant BOND_DEPOSIT_INTERVAL = 4 hours;

    /// @notice Bond market duration (24 hours).
    uint48 internal constant BOND_MARKET_DURATION = 1 days;

    /// @notice The bond market records of the facility.
    /// @param marketVaults The vault that funds each bond market created by the facility,
    ///        keyed by the auctioneer the market was created on. Set on market creation;
    ///        a non-zero entry implicitly validates that the market was created by the
    ///        facility. Market ids are unique only within one bond Aggregator, so the
    ///        records are scoped to the creating auctioneer: after a bond-contract change,
    ///        a colliding id on the new contracts cannot reach a stale record.
    /// @param amounts The cumulative input and output amounts per bond market, keyed by
    ///        the auctioneer the market was created on: `[0]` is the OHM in (quote), `[1]`
    ///        the payout token out.
    /// @param liveMarketIds The market id of each vault's latest bond market plus one, or
    ///        zero when none is tracked. The offset encodes "none" as zero while the
    ///        market id zero stays a valid id. The entry refers to a market of the current
    ///        auctioneer: it is cleared whenever a close of the market is attempted, and a
    ///        bond-contract change closes every tracked market before the auctioneer
    ///        changes. Only the tracked market of a vault is purchasable: the callback of
    ///        the facility rejects every other market, so a market that outlives a failed
    ///        best-effort close is unpurchasable.
    struct Markets {
        mapping(address auctioneer => mapping(uint256 marketId => address vault)) marketVaults;
        mapping(address auctioneer => mapping(uint256 marketId => uint256[2] amounts)) amounts;
        mapping(address vault => uint256 marketIdPlusOne) liveMarketIds;
    }

    /// @notice The inputs of a market submission.
    /// @param auctioneer The SDA auctioneer the market is submitted to.
    /// @param payoutToken The token the market pays out.
    /// @param quoteToken The quote token (OHM).
    /// @param capacity The market capacity, in payout token units.
    /// @param oraclePrice The price of one quote token (OHM) unit, denominated in the
    ///        payout token, in oracle decimals.
    /// @param initialDiscount The discount applied to the oracle price for the initial
    ///        market price (`1e18` = 100%).
    /// @param maxPricePremium The premium over the oracle price at which the market
    ///        floor is set (`1e18` = 100%), capping the payout per quote token. A zero
    ///        premium caps the payout at the oracle price.
    /// @param oracleDecimals The decimals of `oraclePrice`.
    /// @param quoteDecimals The quote token (OHM) decimals.
    /// @param payoutDecimals The payout token decimals.
    struct MarketConfig {
        IBondSDA auctioneer;
        address payoutToken;
        address quoteToken;
        uint256 capacity;
        uint256 oraclePrice;
        uint256 initialDiscount;
        uint256 maxPricePremium;
        uint8 oracleDecimals;
        uint8 quoteDecimals;
        uint8 payoutDecimals;
    }

    /// @notice Opens the daily bond market of a vault: closes the vault's previous
    ///         tracked market best-effort, prices and submits a market that sells the
    ///         vault's payout token for OHM, and records the created market.
    /// @dev `oraclePrice_` is the OHM price denominated in the vault's reserve token. For
    ///      a sell-shares asset the payout token is the share token and the reserve price
    ///      is converted to a per-share price through the conversion rate (floor): one
    ///      share is worth the conversion rate in reserve units. The vault's previous
    ///      tracked market is closed first, best-effort, so at most one purchasable
    ///      market per vault exists at a time even when missed beats stretch the daily
    ///      schedule. Failures are absorbed: a zero conversion rate (before any close), a
    ///      rejected market submission, or an auctioneer that holds no code emits
    ///      `MarketCreationFailed` and keeps the funds with the facility. A created market
    ///      is recorded under the creating auctioneer, which authorizes its callback, its
    ///      id is tracked for the later close, and `RepoMarket` is emitted.
    /// @param state_ The facility's bond market records storage.
    /// @param context_ The dependencies of the facility: the auctioneer, OHM, the oracle
    ///        decimals, the initial discount, and the max price premium.
    /// @param config_ The configuration storage of the vault whose market is opened.
    /// @param capacity_ The market capacity, in payout token units: the reserve amount,
    ///        or the share amount for a sell-shares asset.
    /// @param oraclePrice_ The OHM price denominated in the vault's reserve token, in
    ///        oracle decimals.
    function openMarket(
        Markets storage state_,
        IYieldRepurchaseFacilityV2.Context memory context_,
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        uint256 capacity_,
        uint256 oraclePrice_
    ) external {
        address vault_ = config_.vault;
        uint256 marketOraclePrice = oraclePrice_;
        address payoutToken = config_.reserve;

        if (config_.sellShares) {
            // One whole share: `addAsset` requires the share decimals to equal the reserve
            // decimals
            uint256 oneShare = YieldRepurchaseFacilityV2Constants.DECIMAL_BASE **
                config_.reserveDecimals;
            uint256 conversionRate = YieldRepurchaseFacilityV2VaultLib.sharesToAssets(
                vault_,
                config_.asyncRedeem,
                oneShare
            );
            if (conversionRate == 0) {
                emit IYieldRepurchaseFacilityV2.MarketCreationFailed(vault_, capacity_, "");
                return;
            }
            // marketOraclePrice = oraclePrice (oracle decimals, per reserve unit) * oneShare
            // / conversionRate (reserve units per share) -> oracle decimals per share (floor).
            marketOraclePrice = oraclePrice_.mulDiv(oneShare, conversionRate);
            payoutToken = config_.shareToken;
        }

        closeVaultMarket(state_, context_, vault_);

        address auctioneer = context_.bondAuctioneer;
        MarketConfig memory marketConfig;
        marketConfig.auctioneer = IBondSDA(auctioneer);
        marketConfig.payoutToken = payoutToken;
        marketConfig.quoteToken = context_.ohm;
        marketConfig.capacity = capacity_;
        marketConfig.oraclePrice = marketOraclePrice;
        marketConfig.initialDiscount = context_.initialDiscount;
        marketConfig.maxPricePremium = context_.maxPricePremium;
        marketConfig.oracleDecimals = context_.oracleDecimals;
        marketConfig.quoteDecimals = context_.ohmDecimals;
        marketConfig.payoutDecimals = config_.reserveDecimals;

        (bool success, uint256 marketId, bytes memory reason) = _submitMarket(marketConfig);

        // The funds stay in the buyback pool, so the following cycle retries the market
        if (!success) {
            emit IYieldRepurchaseFacilityV2.MarketCreationFailed(vault_, capacity_, reason);
            return;
        }

        state_.marketVaults[auctioneer][marketId] = vault_;
        state_.liveMarketIds[vault_] = marketId + 1;

        emit IYieldRepurchaseFacilityV2.RepoMarket(vault_, marketId, payoutToken, capacity_);
    }

    /// @notice Closes the vault's tracked live bond market on the current auctioneer,
    ///         best-effort.
    /// @dev The tracked id is cleared unconditionally. The close call is external and its
    ///      returndata capture is capped: a revert of the auctioneer is absorbed with a
    ///      `MarketCloseFailed` event carrying the truncated revert reason, an auctioneer
    ///      that holds no code is absorbed with the same event carrying an empty reason,
    ///      and the market is left to expire on its own, unpurchasable: the callback of
    ///      the facility only serves the tracked market.
    /// @param state_ The facility's bond market records storage.
    /// @param context_ The dependencies of the facility: the auctioneer.
    /// @param vault_ The vault whose tracked market is closed.
    function closeVaultMarket(
        Markets storage state_,
        IYieldRepurchaseFacilityV2.Context memory context_,
        address vault_
    ) public {
        uint256 marketIdPlusOne = state_.liveMarketIds[vault_];
        if (marketIdPlusOne == 0) return;
        state_.liveMarketIds[vault_] = 0;

        uint256 marketId = marketIdPlusOne - 1;
        (bool success, bytes memory reason) = SafeCall.safeCall(
            context_.bondAuctioneer,
            gasleft(),
            0,
            YieldRepurchaseFacilityV2Constants.MAX_RETURNDATA_LENGTH,
            abi.encodeCall(IBondAuctioneer.closeMarket, (marketId))
        );
        if (!success) emit IYieldRepurchaseFacilityV2.MarketCloseFailed(vault_, marketId, reason);
    }

    /// @notice Closes the tracked live bond market of every registered vault,
    ///         best-effort.
    /// @param state_ The facility's bond market records storage.
    /// @param context_ The dependencies of the facility: the auctioneer.
    /// @param vaults_ The facility's registered vault list storage.
    function closeAllVaultMarkets(
        Markets storage state_,
        IYieldRepurchaseFacilityV2.Context memory context_,
        address[] storage vaults_
    ) external {
        uint256 vaultsLength = vaults_.length;
        for (uint256 i; i < vaultsLength; ++i) {
            closeVaultMarket(state_, context_, vaults_[i]);
        }
    }

    /// @notice Closes the vault's tracked live bond market on the current auctioneer,
    ///         strictly: a revert of the auctioneer reverts the caller.
    /// @dev A no-op when no market is tracked. The tracked id is cleared before the call.
    /// @param state_ The facility's bond market records storage.
    /// @param context_ The dependencies of the facility: the auctioneer.
    /// @param vault_ The vault whose tracked market is closed.
    function closeVaultMarketStrict(
        Markets storage state_,
        IYieldRepurchaseFacilityV2.Context memory context_,
        address vault_
    ) external {
        uint256 marketIdPlusOne = state_.liveMarketIds[vault_];
        if (marketIdPlusOne == 0) return;
        state_.liveMarketIds[vault_] = 0;

        IBondAuctioneer(context_.bondAuctioneer).closeMarket(marketIdPlusOne - 1);
    }

    /// @notice Prices and submits a bond market that sells the payout token for OHM.
    /// @dev The market runs for `BOND_MARKET_DURATION` with instant vesting, a
    ///      `BOND_DEPOSIT_INTERVAL` deposit interval, a `BOND_DEBT_BUFFER` debt buffer,
    ///      and the capacity denominated in the payout token; the caller is the market
    ///      callback. A revert of the auctioneer is reported as a failure with the
    ///      captured revert data instead of bubbling, and an auctioneer that holds no
    ///      code is reported as a failure with empty data; a revert of the pricing (a
    ///      checked cast on an extreme price) bubbles to the caller.
    /// @param config_ The market submission inputs.
    /// @return success Whether the auctioneer accepted the market.
    /// @return marketId The market ID assigned by the auctioneer, or zero on a failure.
    /// @return reason The raw revert data of a rejected submission, truncated to
    ///         `MAX_RETURNDATA_LENGTH` bytes; empty on a success.
    function _submitMarket(
        MarketConfig memory config_
    ) private returns (bool success, uint256 marketId, bytes memory reason) {
        (
            uint256 formattedInitialPrice,
            uint256 formattedMinimumPrice,
            int8 scaleAdjustment
        ) = YieldRepurchaseFacilityV2MathLib.marketPricing(
                YieldRepurchaseFacilityV2MathLib.MarketPricing({
                    oraclePrice: config_.oraclePrice,
                    initialDiscount: config_.initialDiscount,
                    maxPricePremium: config_.maxPricePremium,
                    oracleDecimals: config_.oracleDecimals,
                    quoteDecimals: config_.quoteDecimals,
                    payoutDecimals: config_.payoutDecimals
                })
            );

        bytes memory callData = abi.encodeCall(
            IBondAuctioneer.createMarket,
            (
                abi.encode(
                    IBondSDA.MarketParams({
                        payoutToken: SolmateERC20(config_.payoutToken),
                        quoteToken: SolmateERC20(config_.quoteToken),
                        callbackAddr: address(this),
                        capacityInQuote: false,
                        capacity: config_.capacity,
                        formattedInitialPrice: formattedInitialPrice,
                        formattedMinimumPrice: formattedMinimumPrice,
                        debtBuffer: BOND_DEBT_BUFFER,
                        vesting: uint48(0),
                        // One day past block.timestamp fits in uint48 for about 8.9 million years
                        // forge-lint: disable-next-line(unsafe-typecast)
                        conclusion: uint48(block.timestamp + BOND_MARKET_DURATION),
                        depositInterval: BOND_DEPOSIT_INTERVAL,
                        scaleAdjustment: scaleAdjustment
                    })
                )
            )
        );

        // The capped capture keeps a reverting auctioneer from inflating the memory
        // cost of the calling facility; the success returndata is one word (the id)
        bytes memory returned;
        (success, returned) = SafeCall.safeCall(
            address(config_.auctioneer),
            gasleft(),
            0,
            YieldRepurchaseFacilityV2Constants.MAX_RETURNDATA_LENGTH,
            callData
        );

        // The literals make the failure and the success return shapes explicit
        // forge-lint: disable-start(boolean-cst)
        if (!success) return (false, 0, returned);
        return (true, abi.decode(returned, (uint256)), "");
        // forge-lint: disable-end(boolean-cst)
    }
}
