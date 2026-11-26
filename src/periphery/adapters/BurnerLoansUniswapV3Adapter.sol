// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {ISwapRouter} from "@uniswap-v3-periphery-1.4.2/interfaces/ISwapRouter.sol";
import {IBurnerLoansSwapAdapter} from "src/periphery/interfaces/IBurnerLoansSwapAdapter.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";

// Contracts
import {ERC165} from "@openzeppelin-5.7.0/utils/introspection/ERC165.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";

/// @notice Swaps ERC-20 tokens through a fixed Uniswap V3 SwapRouter.
/// @dev Intended for exact-transfer, nonrebasing tokens.
contract BurnerLoansUniswapV3Adapter is IBurnerLoansSwapAdapter, ERC165, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using SafeERC20Exact for IERC20;

    uint256 private constant _TOKEN_BYTES = 20;
    uint256 private constant _FEE_BYTES = 3;
    uint256 private constant _HOP_BYTES = _FEE_BYTES + _TOKEN_BYTES;
    uint256 private constant _SINGLE_HOP_BYTES = _TOKEN_BYTES + _HOP_BYTES;

    ISwapRouter internal immutable _ROUTER;

    /// @notice Binds the router for all swaps.
    /// @dev Reverts if:
    ///      - The router address has no code.
    /// @param router_ Trusted Uniswap V3 SwapRouter deployment.
    constructor(address router_) {
        if (router_.code.length == 0) revert InvalidRouter(router_);
        _ROUTER = ISwapRouter(router_);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId_) public view override returns (bool) {
        return
            interfaceId_ == type(IBurnerLoansSwapAdapter).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @inheritdoc IBurnerLoansSwapAdapter
    /// @dev The final hop must meet the output minimum before route refunds are settled.
    ///      Reverts if:
    ///      - A swap is already running.
    ///      - The token addresses are identical or either has no code.
    ///      - The input amount or output minimum is zero.
    ///      - The deadline has passed.
    ///      - The forward route has an invalid length or endpoint.
    ///      - Input collection is inexact or a token or router call fails.
    ///      - A hop debits more than its assigned input.
    ///      - The actual output received by the caller falls below the minimum.
    ///      - A route token's balance differs from its starting balance after settlement.
    function swapExactInput(
        ExactInputParams calldata params_
    ) external nonReentrant returns (uint256 amountOut) {
        _validateSwap(
            params_.tokenIn,
            params_.tokenOut,
            params_.amountIn,
            params_.minAmountOut,
            params_.deadline
        );
        uint256 routeLength = _validateRoute(params_.route, params_.tokenIn, params_.tokenOut);

        uint256[] memory startingBalances = _snapshotRoute(params_.route, routeLength);
        IERC20 output = IERC20(params_.tokenOut);
        uint256 outputBefore = output.balanceOf(msg.sender);
        IERC20(params_.tokenIn).safeTransferFromExact(msg.sender, address(this), params_.amountIn);
        uint256 hopCount = routeLength - 1;
        uint256 amount = params_.amountIn;
        for (uint256 i; i < hopCount; ++i) {
            uint256 start = i * _HOP_BYTES;
            amount = _swapInputHop(
                params_.route[start:start + _SINGLE_HOP_BYTES],
                amount,
                i + 1 == hopCount ? params_.minAmountOut : 1,
                params_.deadline
            );
        }
        _refundRoute(params_.route, startingBalances);
        amountOut = _checkOutput(outputBefore, output.balanceOf(msg.sender), params_.minAmountOut);
    }

    /// @inheritdoc IBurnerLoansSwapAdapter
    /// @dev The router path starts at the output token. Verifies the spend cap and caller receipt,
    ///      refunds unused route balances, and preserves each token's starting adapter balance.
    ///      Reverts if:
    ///      - A swap is already running.
    ///      - The token addresses are identical or either has no code.
    ///      - The input cap or output amount is zero.
    ///      - The deadline has passed.
    ///      - The reverse route has an invalid length or endpoint.
    ///      - Input collection is inexact or a token or router call fails.
    ///      - The router increases the input balance or debits more than the cap.
    ///      - The actual output received by the caller falls below the requested amount.
    ///      - A route token's balance differs from its starting balance after settlement.
    function swapExactOutput(
        ExactOutputParams calldata params_
    ) external nonReentrant returns (uint256 amountIn) {
        _validateSwap(
            params_.tokenIn,
            params_.tokenOut,
            params_.maxAmountIn,
            params_.amountOut,
            params_.deadline
        );
        uint256 routeLength = _validateRoute(params_.route, params_.tokenOut, params_.tokenIn);

        uint256[] memory startingBalances = _snapshotRoute(params_.route, routeLength);
        IERC20 output = IERC20(params_.tokenOut);
        uint256 outputBefore = output.balanceOf(msg.sender);
        IERC20 input = IERC20(params_.tokenIn);
        uint256 startingInputBalance = input.safeTransferFromExact(
            msg.sender,
            address(this),
            params_.maxAmountIn
        );
        uint256 fundedInputBalance = startingInputBalance + params_.maxAmountIn;
        input.forceApprove(address(_ROUTER), params_.maxAmountIn);
        // The router's reported spend is not used to determine settlement.
        // forge-lint: disable-start(unused-return)
        _ROUTER.exactOutput(
            ISwapRouter.ExactOutputParams({
                path: params_.route,
                recipient: address(this),
                deadline: params_.deadline,
                amountOut: params_.amountOut,
                amountInMaximum: params_.maxAmountIn
            })
        );
        // forge-lint: disable-end(unused-return)
        input.forceApprove(address(_ROUTER), 0);

        uint256 inputAfterSwap = input.balanceOf(address(this));
        if (inputAfterSwap > fundedInputBalance) revert UnsettledBalance(address(input));
        amountIn = fundedInputBalance - inputAfterSwap;
        if (amountIn > params_.maxAmountIn)
            revert InputLimitExceeded(params_.maxAmountIn, amountIn);
        _refundRoute(params_.route, startingBalances);
        _checkOutput(outputBefore, output.balanceOf(msg.sender), params_.amountOut);
    }

    /// @inheritdoc IBurnerLoansSwapAdapter
    /// @dev Reverts if the route length cannot encode one or more complete hops.
    function intermediateTokens(
        bytes calldata route_
    ) external pure returns (address[] memory tokens) {
        tokens = new address[](_routeLength(route_) - 2);
        for (uint256 i; i < tokens.length; ++i) tokens[i] = address(_routeToken(route_, i + 1));
    }

    /// @notice Executes one hop and measures the resulting output.
    /// @dev Reverts if:
    ///      - A token or router call fails.
    ///      - The hop spends more than its assigned input.
    ///      - The adapter receives less than the minimum output.
    /// @param hop_ Packed single-hop path.
    /// @param amount_ Input budget in raw token units.
    /// @param minimum_ Minimum output in raw token units.
    /// @param deadline_ Latest allowed timestamp, inclusive.
    /// @return received Actual output received by the adapter in raw token units.
    // Each hop must call the router individually to keep intermediate proceeds in the adapter.
    // A hop that exceeds its assigned input must revert the entire swap.
    // forge-lint: disable-start(calls-loop,require-revert-in-loop)
    function _swapInputHop(
        bytes calldata hop_,
        uint256 amount_,
        uint256 minimum_,
        uint256 deadline_
    ) private returns (uint256 received) {
        IERC20 input = _routeToken(hop_, 0);
        IERC20 output = _routeToken(hop_, 1);
        uint256 inputBefore = input.balanceOf(address(this));
        uint256 outputBefore = output.balanceOf(address(this));
        input.forceApprove(address(_ROUTER), amount_);
        // Use observed balances as the source of truth for each hop.
        // forge-lint: disable-start(unused-return)
        _ROUTER.exactInput(
            ISwapRouter.ExactInputParams({
                path: hop_,
                recipient: address(this),
                deadline: deadline_,
                amountIn: amount_,
                amountOutMinimum: minimum_
            })
        );
        // forge-lint: disable-end(unused-return)
        input.forceApprove(address(_ROUTER), 0);
        uint256 inputAfter = input.balanceOf(address(this));
        if (inputBefore > inputAfter && inputBefore - inputAfter > amount_)
            revert InputLimitExceeded(amount_, inputBefore - inputAfter);
        return _checkOutput(outputBefore, output.balanceOf(address(this)), minimum_);
    }

    // forge-lint: disable-end(calls-loop,require-revert-in-loop)

    /// @notice Validates the endpoints, nonzero amount bounds and deadline shared by both modes.
    /// @dev Reverts if:
    ///      - The endpoints match or either token has no code.
    ///      - Either amount bound is zero.
    ///      - The deadline has passed.
    /// @param input_ Input token.
    /// @param output_ Output token.
    /// @param inputLimit_ Input amount or cap in raw token units.
    /// @param outputLimit_ Output minimum or requested amount in raw token units.
    /// @param deadline_ Latest allowed timestamp, inclusive.
    function _validateSwap(
        address input_,
        address output_,
        uint256 inputLimit_,
        uint256 outputLimit_,
        uint256 deadline_
    ) private view {
        if (input_ == output_ || input_.code.length == 0 || output_.code.length == 0)
            revert InvalidTokenPair(input_, output_);
        if (inputLimit_ == 0 || outputLimit_ == 0) revert InvalidAmount();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > deadline_) revert DeadlineExpired(deadline_);
    }

    /// @notice Measures the output receipt and enforces its minimum.
    /// @dev Reverts if the observed increase falls below the minimum.
    /// @param before_ Output balance before the transfer, in raw units.
    /// @param after_ Output balance after the transfer, in raw units.
    /// @param minimum_ Minimum receipt in raw units.
    /// @return received Nonnegative output balance increase in raw units.
    function _checkOutput(
        uint256 before_,
        uint256 after_,
        uint256 minimum_
    ) private pure returns (uint256 received) {
        received = after_ >= before_ ? after_ - before_ : 0;
        // Each hop must meet its assigned minimum for the swap to proceed.
        // forge-lint: disable-next-line(require-revert-in-loop)
        if (received < minimum_) revert InsufficientOutput(minimum_, received);
    }

    // Each route token is an ERC-20 selected by the swap path. A failed snapshot or refund
    // must roll back the entire swap.
    // forge-lint: disable-start(calls-loop,require-revert-in-loop)
    /// @notice Records the adapter balance of each token in a validated route.
    /// @dev Reverts if a route token has no code or its balance cannot be read.
    /// @param route_ Validated packed route.
    /// @param routeLength_ Number of token positions, including both endpoints.
    /// @return balances Starting balances in path order, in each token's raw units.
    function _snapshotRoute(
        bytes calldata route_,
        uint256 routeLength_
    ) private view returns (uint256[] memory balances) {
        balances = new uint256[](routeLength_);
        for (uint256 i; i < balances.length; ++i) {
            IERC20 token = _routeToken(route_, i);
            if (address(token).code.length == 0) revert InvalidRoute();
            balances[i] = token.balanceOf(address(this));
        }
    }

    /// @notice Transfers the surplus for each route token to the swap caller.
    /// @dev Reverts if:
    ///      - Reading a balance or transferring a token fails.
    ///      - A route balance is below its starting value or settlement fails to restore it.
    /// @param route_ Validated packed route.
    /// @param startingBalances_ Adapter balances before funding, in path order and raw units.
    function _refundRoute(bytes calldata route_, uint256[] memory startingBalances_) private {
        for (uint256 i; i < startingBalances_.length; ++i) {
            IERC20 token = _routeToken(route_, i);
            uint256 current = token.balanceOf(address(this));
            uint256 starting = startingBalances_[i];
            if (current < starting) revert UnsettledBalance(address(token));
            if (current > starting) token.safeTransfer(msg.sender, current - starting);
        }
        // A refund callback can change the balance of a token already checked or refunded.
        for (uint256 i; i < startingBalances_.length; ++i) {
            IERC20 token = _routeToken(route_, i);
            // forge-lint: disable-next-line(incorrect-strict-equality)
            if (token.balanceOf(address(this)) != startingBalances_[i])
                revert UnsettledBalance(address(token));
        }
    }

    // forge-lint: disable-end(calls-loop,require-revert-in-loop)

    /// @notice Reads a token address at a given position in the packed route.
    /// @dev Reverts if the token position is out of bounds.
    /// @param route_ Packed route.
    /// @param index_ Zero-based token position.
    /// @return token ERC-20 token at that position.
    function _routeToken(
        bytes calldata route_,
        uint256 index_
    ) private pure returns (IERC20 token) {
        uint256 start = index_ * _HOP_BYTES;
        return IERC20(address(bytes20(route_[start:start + _TOKEN_BYTES])));
    }

    /// @notice Returns the number of token positions in a packed route.
    /// @dev Reverts if the route length cannot encode one or more complete hops.
    /// @param route_ Packed route.
    /// @return count Number of tokens including both endpoints.
    function _routeLength(bytes calldata route_) private pure returns (uint256 count) {
        if (route_.length < _SINGLE_HOP_BYTES || (route_.length - _TOKEN_BYTES) % _HOP_BYTES != 0)
            revert InvalidRoute();
        return route_.length / _HOP_BYTES + 1;
    }

    /// @notice Requires one or more V3 hops with matching input and output endpoints.
    /// @dev Each path starts with a 20-byte token and adds 23 bytes per hop (fee and next token).
    /// @param route_ Packed Uniswap V3 path.
    /// @param tokenIn_ Expected first token.
    /// @param tokenOut_ Expected last token.
    /// @return length Number of token positions, including both endpoints.
    function _validateRoute(
        bytes calldata route_,
        address tokenIn_,
        address tokenOut_
    ) private pure returns (uint256 length) {
        length = _routeLength(route_);
        if (
            address(_routeToken(route_, 0)) != tokenIn_ ||
            address(_routeToken(route_, length - 1)) != tokenOut_
        ) revert InvalidRoute();
    }
}
