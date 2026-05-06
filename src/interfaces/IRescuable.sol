// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

/// @title IRescuable
/// @notice Interface for contracts that allow privileged rescue of accidentally-sent assets.
/// @dev The native token is identified using the EIP-7528 sentinel address
///      (`ERC7528Constants.NATIVE_TOKEN`).
interface IRescuable {
    // ========= ERRORS ========= //

    /// @notice Thrown when the rescue recipient is the zero address.
    error Rescuable_InvalidRecipient();

    // ========= EVENTS ========= //

    /// @notice Emitted when assets are rescued from the contract.
    /// @param token The rescued token address. Equals `NATIVE_TOKEN` for the native token.
    /// @param to The recipient address.
    /// @param amount The amount rescued.
    event Rescued(address indexed token, address indexed to, uint256 amount);

    // ========= FUNCTIONS ========= //

    /// @notice Rescues assets accidentally sent to this contract.
    ///
    /// @param token_ The token to rescue, or `NATIVE_TOKEN` for the native token.
    /// @param to_ The recipient of the rescued assets.
    function rescue(address token_, address payable to_) external;

    /// @notice The EIP-7528 sentinel address used to represent the native token.
    // solhint-disable-next-line func-name-mixedcase
    function NATIVE_TOKEN() external pure returns (address);
}
