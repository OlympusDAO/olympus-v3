// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

/// @title Burner Loans Market Config
/// @notice Encodes and decodes the Burner Loans-specific portion of a FLOAN market.
library BurnerLoansMarketConfig {
    bytes16 internal constant CONFIG_ID = bytes16("Burner Loans v1");

    struct Data {
        uint128 maxKeeperReward;
        uint16 backingMultiplierBps;
        uint16 keeperRewardBps;
        uint16 kinkBps;
        uint16 preKinkSlopeBps;
        uint16 postKinkSlopeBps;
    }

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

    function hasMarket(
        IFLOANv1 floan_,
        address facility_,
        address collateralToken_,
        address debtToken_
    ) internal view returns (bool) {
        return floan_.getMarketIds(facility_, collateralToken_, debtToken_).length != 0;
    }

    function decode(bytes memory data_) internal pure returns (Data memory) {
        return abi.decode(data_, (Data));
    }

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

    function assetConfig(
        IFLOANv1.Market memory market_,
        bytes memory data_
    ) internal pure returns (IBurnerLoans.AssetConfig memory) {
        Data memory data = decode(data_);
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

    function feeConfig(
        IFLOANv1.Market memory market_,
        bytes memory data_
    ) internal pure returns (IBurnerLoans.AssetFeeConfig memory) {
        Data memory data = decode(data_);
        return
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: market_.baseFeeBps,
                kinkBps: data.kinkBps,
                preKinkSlopeBps: data.preKinkSlopeBps,
                postKinkSlopeBps: data.postKinkSlopeBps
            });
    }
}
