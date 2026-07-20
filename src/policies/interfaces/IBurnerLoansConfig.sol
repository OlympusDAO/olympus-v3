// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

/// @title Burner Loans Config Interface
/// @notice Opinionated administration surface for Burner Loans markets stored in FLOAN.
interface IBurnerLoansConfig is IBurnerLoans {
    function ohm() external view returns (address);

    function depositManager() external view returns (address);

    function configurator() external view returns (address);

    function isAssetConfigured(address, address) external view returns (bool);

    function getAssetConfig(address, address) external view returns (AssetConfig memory);

    function getAssetFeeConfig(address, address) external view returns (AssetFeeConfig memory);

    function marketId(address, address) external view returns (uint32);

    function validateAssetRiskConfig(AssetConfig calldata) external pure;

    function validateFeeConfig(AssetFeeConfig calldata) external pure;

    function validateAssetDebtCap(address, address, uint128) external view;

    function setMarketFacility(uint32, address) external;

    function addAsset(
        address,
        address,
        uint128,
        AssetRiskConfigInput calldata,
        AssetFeeConfig calldata
    ) external;

    function setAssetDebtCap(address, address, uint128) external;

    function setConfigurator(address) external;

    function enableAsset(address, address) external;

    function disableAsset(address, address) external;

    function setAssetRiskConfig(address, address, AssetRiskConfigInput calldata) external;

    function setAssetFeeConfig(address, address, AssetFeeConfig calldata) external;
}
