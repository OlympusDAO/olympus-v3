// SPDX-License-Identifier: MIT
pragma solidity >=0.8.34;

/// @notice Exchanges ERC-20 tokens and delivers the output to the calling account.
/// @dev Implementations must advertise this interface through ERC-165.
interface IBurnerLoansSwapAdapter {
    /// @notice The configured router address has no code.
    error InvalidRouter(address router);

    /// @notice The token endpoints are invalid or identical.
    error InvalidTokenPair(address tokenIn, address tokenOut);

    /// @notice The request specifies a zero amount or limit.
    error InvalidAmount();

    /// @notice The swap deadline has passed.
    error DeadlineExpired(uint256 deadline);

    /// @notice The supplied route is invalid for the requested endpoints.
    error InvalidRoute();

    /// @notice The exchange delivered fewer raw output units than requested.
    error InsufficientOutput(uint256 minimum, uint256 actual);

    /// @notice The exchange spent more than the maximum input.
    error InputLimitExceeded(uint256 maximum, uint256 actual);

    /// @notice The adapter's final token balance differs from its protected starting balance.
    error UnsettledBalance(address token);

    /// @notice Parameters for an exact-input exchange. Amounts are in the respective token's raw units.
    /// @param tokenIn Token collected from the caller.
    /// @param tokenOut Token returned to the caller.
    /// @param amountIn Input amount funded by the caller. Unspent input is returned.
    /// @param minAmountOut Minimum actual output.
    /// @param deadline Last timestamp at which execution is accepted, inclusive.
    /// @param route Adapter-specific path bytes.
    struct ExactInputParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 deadline;
        bytes route;
    }

    /// @notice Exchanges funded input and returns all swap proceeds and unused route tokens to msg.sender.
    /// @param params Exact-input request and route.
    /// @return amountOut Output in tokenOut raw units.
    function swapExactInput(ExactInputParams calldata params) external returns (uint256 amountOut);

    /// @notice Parameters for an exact-output exchange. Amounts use each token's raw units.
    /// @param tokenIn Token spent by the caller.
    /// @param tokenOut Token returned to the caller.
    /// @param amountOut Required actual output.
    /// @param maxAmountIn Maximum input collected. Unused input is returned.
    /// @param deadline Last timestamp at which execution is accepted, inclusive.
    /// @param route Adapter-specific exact-output path bytes.
    struct ExactOutputParams {
        address tokenIn;
        address tokenOut;
        uint256 amountOut;
        uint256 maxAmountIn;
        uint256 deadline;
        bytes route;
    }

    /// @notice Buys an exact output within the input cap and returns unused route tokens to msg.sender.
    /// @param params Exact-output request and route.
    /// @return amountIn Actual spend in tokenIn raw units.
    function swapExactOutput(ExactOutputParams calldata params) external returns (uint256 amountIn);

    /// @notice Lists only the tokens between the first and last positions of the route.
    /// @dev A single-hop route returns an empty array. Repeated addresses in intermediate
    ///      positions are included. The result depends only on the route bytes.
    /// @param route Adapter-specific path bytes in either swap direction.
    /// @return tokens Intermediate tokens whose balances may be returned during the swap.
    function intermediateTokens(
        bytes calldata route
    ) external view returns (address[] memory tokens);
}
