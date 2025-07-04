// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

/// @title IConvertibleDeposit
/// @notice Defines an interface for a convertible deposit token that records the owner and an ERC4626 vault (in addition to the standard ERC20 interface).
/// @dev    This interface does not inherit from IERC20, as it is intended to be used as a mixin.
interface IConvertibleDeposit {
    // ===== ERRORS ===== //

    /// @notice Thrown when the caller is not the owner
    error OnlyOwner();

    // ===== VIEW FUNCTIONS ===== //

    /// @notice The owner of the token
    ///
    /// @return _owner The owner address
    function owner() external view returns (address _owner);

    /// @notice The underlying asset
    ///
    /// @return _asset The asset address
    function asset() external view returns (IERC20 _asset);

    /// @notice The vault that holds the underlying asset
    ///
    /// @return _vault The vault address
    function vault() external view returns (IERC4626 _vault);

    /// @notice The period of the deposit token (in months)
    ///
    /// @return _periodMonths The period months
    function periodMonths() external view returns (uint8 _periodMonths);

    // ===== MINT/BURN ===== //

    /// @notice Mint tokens to the specified address
    /// @dev    This is owner-only, as the underlying token is custodied by the owner.
    ///         Minting should be performed through the owner contract.
    ///
    /// @param to_ The address to mint tokens to
    /// @param amount_ The amount of tokens to mint
    function mintFor(address to_, uint256 amount_) external;

    /// @notice Burn tokens from the specified address
    /// @dev    This is gated to the owner, as burning is controlled.
    ///         Burning should be performed through the owner contract.
    ///
    /// @dev    This function reverts if:
    ///         - The amount is greater than the allowance
    ///
    /// @param from_ The address to burn tokens from
    /// @param amount_ The amount of tokens to burn
    function burnFrom(address from_, uint256 amount_) external;
}
