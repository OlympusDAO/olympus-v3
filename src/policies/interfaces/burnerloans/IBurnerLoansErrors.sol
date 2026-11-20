// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @notice Shared admission, configuration and recovery errors for Burner Loans policies, independent of Core's settlement API.
interface IBurnerLoansErrors {
    /// @notice The rescue asset is not a deployed token contract.
    error BurnerLoans_InvalidAsset(address token);

    /// @notice The destination cannot receive this rescue.
    error BurnerLoans_InvalidRescueDestination(address destination);

    /// @notice The resolved FLOAN market does not use the Burner Loans configuration schema.
    /// @param marketId Incompatible FLOAN market identifier.
    /// @param configId Actual configuration schema identifier stored by the market.
    error BurnerLoans_IncompatibleMarketConfig(uint32 marketId, bytes16 configId);

    /// @notice A Burner Loans market's encoded product data has an invalid length.
    /// @param marketId FLOAN market containing the invalid data.
    /// @param length Actual encoded data length.
    error BurnerLoans_InvalidMarketConfigData(uint32 marketId, uint256 length);

    /// @notice A required address is zero.
    error BurnerLoans_ZeroAddress();

    /// @notice A required Kernel module uses an unsupported major version.
    error BurnerLoans_InvalidModuleVersion();

    /// @notice The policy handling this operation is inactive in its Kernel.
    /// @param policy Inactive subject policy; dependency failures identify the dependency separately.
    error BurnerLoans_PolicyNotActive(address policy);

    /// @notice Enable/disable data must be empty for a Burner Loans policy that does not consume it.
    error BurnerLoans_InvalidEnablerData();

    /// @notice A supplied configuration parameter violates its required bounds.
    error BurnerLoans_InvalidParam();

    /// @notice The recipient cannot receive this operation's payout.
    /// @param recipient Invalid recipient.
    error BurnerLoans_InvalidRecipient(address recipient);

    /// @notice A debt cap is invalid for the requested operation.
    error BurnerLoans_InvalidCap();

    /// @notice Contract selection already points to this address.
    /// @param candidate Unchanged contract address.
    error BurnerLoans_UnchangedAddress(address candidate);
}
