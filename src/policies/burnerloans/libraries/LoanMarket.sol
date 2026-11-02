// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

/// @title Burner Loans Market Config
/// @notice Encodes and decodes the Burner Loans-specific portion of a FLOAN market.
/// @dev Shared asset configuration belongs to Core. Reads use Core and FLOAN directly, so servicing
///      policies do not import or call the Config policy.
library LoanMarket {
    /// @notice Reads canonical FLOAN configuration without widening the permanent Core API.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param core_ Permanent accounting and DepositManager operator contract.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @return market Canonical FLOAN market ID.
    /// @return cfg Decoded risk, custody-output and origination parameters.
    /// @return fee Decoded utilization fee curve.
    function configuration(
        IBurnerLoansCore core_,
        address asset_
    )
        internal
        view
        returns (
            uint32 market,
            IBurnerLoansCore.AssetConfig memory cfg,
            IBurnerLoansRisk.AssetFeeConfig memory fee
        )
    {
        market = core_.marketId(asset_);
        IFLOANv1 loan = IFLOANv1(core_.floan());
        IFLOANv1.Market memory stored = loan.getMarket(market);
        bytes memory data = loan.getMarketConfigData(market);
        cfg = assetConfig(market, stored, data);
        fee = feeConfig(market, stored, data);
    }

    /// @notice FLOAN configuration schema identifier for Burner Loans v1.
    // The 15-byte literal fits in bytes16; the fixed-width conversion cannot truncate it.
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes16 internal constant CONFIG_ID = bytes16("Burner Loans v1");

    /// @dev Exact ABI-encoded length of `Data`.
    uint256 internal constant DATA_LENGTH = 7 * 32;

    /// @notice Burner Loans-specific fields encoded into a FLOAN market's configuration data.
    struct Data {
        bool withdrawAsShares;
        uint128 maxKeeperReward;
        uint16 backingMultiplierBps;
        uint16 keeperRewardBps;
        uint16 kinkBps;
        uint16 preKinkSlopeBps;
        uint16 postKinkSlopeBps;
    }

    /// @notice Validates and decodes Burner Loans-specific FLOAN market data.
    /// @dev Validates the market schema and exact static ABI length before decoding.
    /// @param marketId_ FLOAN market identifier.
    /// @param market_ FLOAN market definition associated with `data_`.
    /// @param data_ Encoded Burner Loans market data.
    /// @return Data Decoded Burner Loans market data.
    function decode(
        uint32 marketId_,
        IFLOANv1.Market memory market_,
        bytes memory data_
    ) internal pure returns (Data memory) {
        // The tag and exact payload length define the Burner Loans schema. Check both before
        // decoding so a market managed by another product is never interpreted using this layout.
        requireCompatibleConfig(marketId_, market_);
        if (data_.length != DATA_LENGTH) {
            revert IBurnerLoansErrors.BurnerLoans_InvalidMarketConfigData(marketId_, data_.length);
        }
        return abi.decode(data_, (Data));
    }

    /// @notice Validates that a FLOAN market uses the Burner Loans configuration schema.
    /// @dev Reverts if:
    ///      - The schema differs (BurnerLoans_IncompatibleMarketConfig).
    /// @param marketId_ FLOAN market identifier.
    /// @param market_ FLOAN market definition to validate.
    function requireCompatibleConfig(
        uint32 marketId_,
        IFLOANv1.Market memory market_
    ) internal pure {
        if (market_.configId != CONFIG_ID) {
            revert IBurnerLoansErrors.BurnerLoans_IncompatibleMarketConfig(
                marketId_,
                market_.configId
            );
        }
    }

    /// @notice Builds the complete Burner Loans asset configuration for a FLOAN market.
    /// @dev Validates the market config ID and encoded data length before decoding.
    /// @param marketId_ FLOAN market identifier.
    /// @param market_ FLOAN market definition.
    /// @param data_ Encoded Burner Loans market data.
    /// @return IBurnerLoansCore.AssetConfig config Decoded asset configuration.
    function assetConfig(
        uint32 marketId_,
        IFLOANv1.Market memory market_,
        bytes memory data_
    ) internal pure returns (IBurnerLoansCore.AssetConfig memory) {
        Data memory data = decode(marketId_, market_, data_);
        return
            IBurnerLoansCore.AssetConfig({
                originationsEnabled: market_.originationsEnabled,
                withdrawAsShares: data.withdrawAsShares,
                collateralDecimals: market_.collateralDecimals,
                maxLtvBps: market_.maxLtvBps,
                backingMultiplierBps: data.backingMultiplierBps,
                keeperRewardBps: data.keeperRewardBps,
                termLength: market_.termLength,
                maxMaturityHorizon: market_.maxMaturityHorizon,
                debtCap: market_.principalCap,
                maxKeeperReward: data.maxKeeperReward
            });
    }

    /// @notice Builds the complete Burner Loans fee configuration for a FLOAN market.
    /// @dev Validates the market config ID and encoded data length before decoding.
    /// @param marketId_ FLOAN market identifier.
    /// @param market_ FLOAN market definition.
    /// @param data_ Encoded Burner Loans market data.
    /// @return IBurnerLoansRisk.AssetFeeConfig config Decoded fee configuration.
    function feeConfig(
        uint32 marketId_,
        IFLOANv1.Market memory market_,
        bytes memory data_
    ) internal pure returns (IBurnerLoansRisk.AssetFeeConfig memory) {
        Data memory data = decode(marketId_, market_, data_);
        return
            IBurnerLoansRisk.AssetFeeConfig({
                baseFeeBps: market_.baseFeeBps,
                kinkBps: data.kinkBps,
                preKinkSlopeBps: data.preKinkSlopeBps,
                postKinkSlopeBps: data.postKinkSlopeBps
            });
    }
}
