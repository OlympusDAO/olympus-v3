// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

/// @title Burner Loans Config Interface
/// @notice Opinionated administration surface for Burner Loans markets stored in FLOAN.
interface IBurnerLoansConfig is IBurnerLoans {
    /// @notice Thrown when the configured Burner Loans facility is not an active compatible policy.
    /// @param facility_ The invalid facility address.
    error BurnerLoansConfig_InvalidFacility(address facility_);

    function ohm() external view returns (address);

    function depositManager() external view returns (address);

    /// @notice Returns the Burner Loans facility whose FLOAN markets this policy configures.
    /// @return facility_ Bound Burner Loans facility.
    function facility() external view returns (address facility_);

    function configurator() external view returns (address);

    function isAssetConfigured(address) external view returns (bool);

    function getAssetConfig(address) external view returns (AssetConfig memory);

    function getAssetFeeConfig(address) external view returns (AssetFeeConfig memory);

    function marketId(address) external view returns (uint32);

    function validateAssetRiskConfig(AssetRiskConfigInput calldata) external pure;

    /// @notice Validates a complete fee curve.
    /// @dev A zero kink is valid only when both slope fields are zero.
    function validateFeeConfig(AssetFeeConfig calldata) external pure;

    function validateAssetDebtCap(address, uint128) external view;

    function setMarketFacility(uint32, address) external;

    function addAsset(
        address,
        uint128,
        AssetRiskConfigInput calldata,
        AssetFeeConfig calldata
    ) external;

    function setAssetDebtCap(address, uint128) external;

    function setConfigurator(address) external;

    function setAssetOriginationsEnabled(address, bool) external;

    function setAssetRiskConfig(address, AssetRiskConfigInput calldata) external;

    function setAssetFeeConfig(address, AssetFeeConfig calldata) external;
}
