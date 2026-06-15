// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

// Interfaces
import {IERC4626} from "@openzeppelin-5.3.0/interfaces/IERC4626.sol";

/// @title  IOlympusSUSDe
/// @notice Interface for the Olympus Staked USDe wrapper (osUSDe).
interface IOlympusSUSDe is IERC4626 {
    // ========== EVENTS ========== //

    /// @notice Emitted when the swapper is set.
    /// @param swapper The new swapper.
    event SwapperSet(address indexed swapper);

    /// @notice Emitted when the slippage cap is set.
    /// @param slippageCap The new slippage cap (`1e18` = 100%).
    event SlippageCapSet(uint256 slippageCap);

    /// @notice Emitted when shares are redeemed for the underlying sUSDe one-to-one.
    /// @param caller The address that initiated the call.
    /// @param receiver The address that received the sUSDe.
    /// @param owner The address whose osUSDe shares were burned.
    /// @param shares The number of osUSDe shares burned, equal to the sUSDe shares sent.
    event WithdrawnAsShares(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 shares
    );

    // ========== ERRORS ========== //

    /// @notice Thrown by `withdraw`, which is disabled. Use `redeem` instead.
    /// @dev A swap delivers a variable amount of at least the floor, not exactly `assets`,
    ///      so the ERC4626 `withdraw` exact-output contract cannot be honored.
    error IOlympusSUSDe_UseRedeem();

    /// @notice Thrown by `redeem` when the swapper is not set.
    error IOlympusSUSDe_SwapperNotSet();

    /// @notice Thrown when the sUSDe or USDe token does not report 18 decimals.
    error IOlympusSUSDe_UnsupportedDecimals();

    // ========== STRUCTS ========== //

    /// @notice The decoded payload passed to `enable(bytes)`.
    /// @dev The swapper and slippage cap are set on every `enable`, overwriting any previous
    ///      values. `disable` does not clear them, so `redeem` keeps working while disabled.
    /// @param swapper The swapper used for swap exits.
    /// @param slippageCap The slippage cap applied to swap exits (`1e18` = 100%).
    struct EnableParams {
        address swapper;
        uint256 slippageCap;
    }

    // ========== EXIT ========== //

    /// @notice Redeems `shares` of osUSDe for the underlying sUSDe one-to-one, sending the
    ///         sUSDe to `receiver`.
    /// @dev This is the lossless exit. No swap is performed, so it is independent of the
    ///      swapper and of pool conditions, and it is available even while the wrapper is
    ///      disabled. The receiver can then exit to USDe through the Ethena cooldown.
    ///
    ///      Reverts if:
    ///      - `shares` is zero.
    ///      - `receiver` is the zero address.
    ///      - The caller is not `owner` and lacks sufficient allowance.
    /// @param shares The number of osUSDe shares to burn.
    /// @param receiver The address that receives the sUSDe.
    /// @param owner The address whose osUSDe shares are burned.
    /// @return susdeShares The number of sUSDe shares sent, equal to `shares`.
    function redeemAsShares(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 susdeShares);

    /// @notice Returns the sUSDe shares received for redeeming `shares` osUSDe through
    ///         `redeemAsShares`.
    /// @dev Always one-to-one (returns `shares`), since osUSDe is backed one-to-one by sUSDe.
    /// @param shares The osUSDe shares to redeem.
    /// @return susdeShares The sUSDe shares that would be returned.
    function previewRedeemAsShares(uint256 shares) external pure returns (uint256 susdeShares);

    /// @notice Returns the maximum osUSDe shares `owner` can redeem through `redeemAsShares`.
    /// @dev Equal to the owner's balance, and to the sUSDe returned one-to-one. Available while
    ///      the wrapper is disabled, so it does not depend on the enabled state.
    /// @param owner The holder.
    /// @return maxShares The maximum osUSDe shares redeemable as sUSDe.
    function maxRedeemAsShares(address owner) external view returns (uint256 maxShares);

    // ========== ADMIN ========== //

    /// @notice Sets the swapper used by `redeem` to sell sUSDe for USDe.
    /// @dev Revokes the sUSDe approval of the previous swapper and grants a maximum sUSDe
    ///      approval to the new one.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the admin role.
    ///      - `swapper_` is the zero address.
    ///      - `swapper_` does not reference the wrapper's sUSDe and USDe.
    /// @param  swapper_ The new swapper.
    function setSwapper(address swapper_) external;

    /// @notice Sets the slippage cap applied to swap exits.
    /// @dev Reverts if:
    ///      - The caller does not hold the admin role.
    ///      - `slippageCap_` is zero or exceeds the maximum.
    /// @param  slippageCap_ The new slippage cap (`1e18` = 100%).
    function setSlippageCap(uint256 slippageCap_) external;

    // ========== VIEWS ========== //

    /// @notice The sUSDe vault backing the wrapper.
    function susde() external view returns (address);

    /// @notice The swapper used to sell sUSDe for USDe on a swap exit.
    function swapper() external view returns (address);

    /// @notice The slippage cap applied to swap exits (`1e18` = 100%).
    function slippageCap() external view returns (uint256);
}
