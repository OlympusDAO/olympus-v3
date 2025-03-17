// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {CloneERC20} from "../../external/clones/CloneERC20.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

/// @title  ConvertibleDepositTokenClone
/// @notice Convertible deposit token implementation that is deployed as a clone
///         with immutable arguments for each supported input token.
contract ConvertibleDepositTokenClone is CloneERC20 {
    error OnlyOwner();

    // ========== IMMUTABLE ARGS ========== //

    // Storage layout:
    // 0x00 - name, 32 bytes
    // 0x20 - symbol, 32 bytes
    // 0x40 - decimals, 1 byte
    // 0x41 - owner, 20 bytes
    // 0x55 - asset, 20 bytes
    // 0x69 - vault, 20 bytes

    // TODO check max length of name and symbol

    /// @notice The owner of the clone
    /// @return _owner The owner address stored in immutable args
    function owner() public pure returns (address _owner) {
        _owner = _getArgAddress(0x41);
    }

    /// @notice The underlying asset
    /// @return _asset The asset address stored in immutable args
    function asset() public pure returns (IERC20 _asset) {
        _asset = IERC20(_getArgAddress(0x55));
    }

    /// @notice The vault that holds the underlying asset
    /// @return _vault The vault address stored in immutable args
    function vault() public pure returns (IERC4626 _vault) {
        _vault = IERC4626(_getArgAddress(0x69));
    }

    // ========== OWNER-ONLY FUNCTIONS ========== //

    /// @notice Only the owner can call this function
    modifier onlyOwner() {
        if (msg.sender != owner()) revert OnlyOwner();
        _;
    }

    /// @notice Mint tokens to the specified address
    /// @dev    This is owner-only, as the underlying token is custodied by the owner.
    ///
    /// @param to_ The address to mint tokens to
    /// @param amount_ The amount of tokens to mint
    function mintFor(address to_, uint256 amount_) external onlyOwner {
        _mint(to_, amount_);
    }

    /// @notice Burn tokens from the specified address
    /// @dev    This is gated to the owner, as burning is controlled.
    ///
    /// @param from_ The address to burn tokens from
    /// @param amount_ The amount of tokens to burn
    function burnFrom(address from_, uint256 amount_) external onlyOwner {
        // TODO allowance
        _burn(from_, amount_);
    }
}
