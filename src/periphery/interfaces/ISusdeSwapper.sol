// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ISusdeSwapper
/// @notice Interface for a contract that swaps sUSDe for USDe synchronously.
interface ISusdeSwapper {
    // ========== ERRORS ========== //

    /// @notice Thrown when a zero input amount is supplied.
    error SusdeSwapper_ZeroAmount();

    /// @notice Thrown when a required address argument is the zero address.
    error SusdeSwapper_ZeroAddress();

    /// @notice Thrown when a configured pool does not contain the expected coin pair.
    /// @param pool The pool that failed validation.
    error SusdeSwapper_InvalidPool(address pool);

    /// @notice Thrown when the realized USDe output is below the caller-supplied floor.
    /// @param actualOut The USDe amount the swap produced.
    /// @param minOut The minimum USDe amount required by the caller.
    error SusdeSwapper_SlippageExceeded(uint256 actualOut, uint256 minOut);

    // ========== EVENTS ========== //

    /// @notice Emitted when a swap completes.
    /// @param caller The address that initiated the swap.
    /// @param receiver The address that received the USDe.
    /// @param susdeIn The sUSDe amount swapped.
    /// @param usdeOut The USDe amount delivered.
    event Swapped(
        address indexed caller,
        address indexed receiver,
        uint256 susdeIn,
        uint256 usdeOut
    );

    // ========== SWAP ========== //

    /// @notice Swaps `susdeIn` of sUSDe for USDe and sends the USDe to `receiver`.
    /// @param susdeIn The sUSDe amount to swap.
    /// @param minUsdeOut The minimum acceptable USDe output (the slippage floor).
    /// @param receiver The address that receives the USDe.
    /// @return usdeOut The USDe amount delivered to `receiver`.
    function swap(
        uint256 susdeIn,
        uint256 minUsdeOut,
        address receiver
    ) external returns (uint256 usdeOut);

    /// @notice Estimates the USDe output for a given sUSDe input.
    /// @param susdeIn The sUSDe amount to quote.
    /// @return usdeOut The estimated USDe output.
    function previewSwap(uint256 susdeIn) external view returns (uint256 usdeOut);

    // ========== VIEWS ========== //

    /// @notice The sUSDe token consumed by the swapper.
    function susde() external view returns (address);

    /// @notice The USDe token produced by the swapper.
    function usde() external view returns (address);
}
