// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

/// @title IRescuable
/// @notice Interface for contracts that allow privileged rescue of accidentally-sent assets.
/// @dev Implementations sweep the entire balance of the specified asset to a recipient.
///      The native token (ETH) is identified using the EIP-7528 sentinel address.
interface IRescuable {
    // ========= ERRORS ========= //

    /// @notice Thrown when the rescue recipient is the zero address.
    error Rescuable_InvalidRecipient();

    // ========= EVENTS ========= //

    /// @notice Emitted when assets are rescued from the contract.
    /// @param token The rescued token address. Equals `NATIVE_TOKEN` for the native token (ETH).
    /// @param to The recipient address.
    /// @param amount The amount rescued.
    event Rescued(address indexed token, address indexed to, uint256 amount);

    // ========= FUNCTIONS ========= //

    /// @notice Rescues assets accidentally sent to this contract.
    /// @dev Authentication of the caller is enforced by the implementation.
    ///      Sweeps the entire balance of the specified asset to the provided recipient.
    ///      Pass `NATIVE_TOKEN` (the EIP-7528 sentinel) as `token_` to rescue the native token.
    ///
    ///      Reverts if:
    ///      - The caller is not authorised by the implementation.
    ///      - `to_` is the zero address.
    ///
    /// @param token_ The token to rescue, or `NATIVE_TOKEN` for the native token.
    /// @param to_ The recipient of the rescued assets.
    function rescue(address token_, address payable to_) external;

    /// @notice The EIP-7528 sentinel address used to represent the native token.
    /// @return The native-token sentinel (`0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`).
    // solhint-disable-next-line func-name-mixedcase
    function NATIVE_TOKEN() external pure returns (address);
}
