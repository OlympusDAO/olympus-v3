// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

/// @title Burner Loans Market Config
/// @notice Encodes and decodes the Burner Loans-specific portion of a FLOAN market.
library BurnerLoansMarketConfig {
    bytes16 internal constant CONFIG_ID = bytes16("Burner Loans v1");
    uint256 internal constant DATA_LENGTH = 6 * 32;

    struct Data {
        uint128 maxKeeperReward;
        uint16 backingMultiplierBps;
        uint16 keeperRewardBps;
        uint16 kinkBps;
        uint16 preKinkSlopeBps;
        uint16 postKinkSlopeBps;
    }

    /// @notice Resolves the unique FLOAN market for a facility and token pair.
    /// @dev Reverts when no matching market exists or the pair is ambiguous.
    /// @param floan_ FLOAN module to query.
    /// @param facility_ Facility servicing the market.
    /// @param collateralToken_ Market collateral token.
    /// @param debtToken_ Market debt token.
    /// @return marketId_ Unique matching FLOAN market identifier.
    function marketId(
        IFLOANv1 floan_,
        address facility_,
        address collateralToken_,
        address debtToken_
    ) internal view returns (uint32) {
        uint256[] memory marketIds = floan_.getMarketIds(facility_, collateralToken_, debtToken_);
        if (marketIds.length == 0) {
            revert IBurnerLoans.BurnerLoans_AssetNotConfigured(collateralToken_);
        }
        if (marketIds.length != 1) {
            revert IBurnerLoans.BurnerLoans_AmbiguousMarket(collateralToken_, marketIds.length);
        }
        return uint32(marketIds[0]);
    }

    /// @notice Returns whether FLOAN contains at least one market for a facility and token pair.
    /// @param floan_ FLOAN module to query.
    /// @param facility_ Facility servicing the market.
    /// @param collateralToken_ Market collateral token.
    /// @param debtToken_ Market debt token.
    /// @return exists True when at least one matching market exists.
    function hasMarket(
        IFLOANv1 floan_,
        address facility_,
        address collateralToken_,
        address debtToken_
    ) internal view returns (bool) {
        return floan_.getMarketIds(facility_, collateralToken_, debtToken_).length != 0;
    }

    /// @notice Validates and decodes Burner Loans-specific FLOAN market data.
    /// @dev Validates the market schema and exact static ABI length before decoding.
    /// @param marketId_ FLOAN market identifier.
    /// @param market_ FLOAN market definition associated with `data_`.
    /// @param data_ Encoded Burner Loans market data.
    /// @return data Decoded Burner Loans market data.
    function decode(
        uint32 marketId_,
        IFLOANv1.Market memory market_,
        bytes memory data_
    ) internal pure returns (Data memory data) {
        requireCompatibleConfig(marketId_, market_);
        if (data_.length != DATA_LENGTH) {
            revert IBurnerLoans.BurnerLoans_InvalidMarketConfigData(marketId_, data_.length);
        }
        return abi.decode(data_, (Data));
    }

    /// @notice Validates that a FLOAN market uses the Burner Loans configuration schema.
    /// @dev Reverts with `BurnerLoans_IncompatibleMarketConfig` when the schema differs.
    /// @param marketId_ FLOAN market identifier.
    /// @param market_ FLOAN market definition to validate.
    function requireCompatibleConfig(
        uint32 marketId_,
        IFLOANv1.Market memory market_
    ) internal pure {
        if (market_.configId != CONFIG_ID) {
            revert IBurnerLoans.BurnerLoans_IncompatibleMarketConfig(marketId_, market_.configId);
        }
    }

    /// @notice Encodes Burner Loans-specific market fields for FLOAN storage.
    /// @param assetConfig_ Asset configuration containing risk and keeper fields.
    /// @param feeConfig_ Utilization fee configuration.
    /// @return data Encoded Burner Loans market data.
    function encode(
        IBurnerLoans.AssetConfig memory assetConfig_,
        IBurnerLoans.AssetFeeConfig memory feeConfig_
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                Data({
                    maxKeeperReward: uint128(assetConfig_.maxKeeperReward),
                    backingMultiplierBps: assetConfig_.backingMultiplierBps,
                    keeperRewardBps: assetConfig_.keeperRewardBps,
                    kinkBps: feeConfig_.kinkBps,
                    preKinkSlopeBps: feeConfig_.preKinkSlopeBps,
                    postKinkSlopeBps: feeConfig_.postKinkSlopeBps
                })
            );
    }

    /// @notice Builds the complete Burner Loans asset configuration for a FLOAN market.
    /// @dev Validates the market config ID and encoded data length before decoding.
    /// @param marketId_ FLOAN market identifier.
    /// @param market_ FLOAN market definition.
    /// @param data_ Encoded Burner Loans market data.
    /// @return config Decoded asset configuration.
    function assetConfig(
        uint32 marketId_,
        IFLOANv1.Market memory market_,
        bytes memory data_
    ) internal pure returns (IBurnerLoans.AssetConfig memory) {
        Data memory data = decode(marketId_, market_, data_);
        return
            IBurnerLoans.AssetConfig({
                originationsEnabled: market_.originationsEnabled,
                collateralDecimals: market_.collateralDecimals,
                collateralFactorBps: market_.collateralFactorBps,
                minCollateralRatioBps: market_.minCollateralRatioBps,
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
    /// @return config Decoded fee configuration.
    function feeConfig(
        uint32 marketId_,
        IFLOANv1.Market memory market_,
        bytes memory data_
    ) internal pure returns (IBurnerLoans.AssetFeeConfig memory) {
        Data memory data = decode(marketId_, market_, data_);
        return
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: market_.baseFeeBps,
                kinkBps: data.kinkBps,
                preKinkSlopeBps: data.preKinkSlopeBps,
                postKinkSlopeBps: data.postKinkSlopeBps
            });
    }
}
