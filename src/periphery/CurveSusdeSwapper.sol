// SPDX-License-Identifier: MIT
pragma solidity >=0.8.30;

// Interfaces
import {ICurveStableSwapNG} from "src/interfaces/ICurveStableSwapNG.sol";
import {ISusdeSwapper} from "src/periphery/interfaces/ISusdeSwapper.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.3.0/token/ERC20/utils/SafeERC20.sol";

// Contracts
import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";

/// @title CurveSusdeSwapper
/// @notice Swaps sUSDe for USDe through two Curve StableSwap-NG pools.
/// @dev The swapper is the route abstraction used by the OlympusSUSDe wrapper to
///      convert sUSDe into USDe on demand. It encapsulates a specific on-chain route.
///
///      The wrapper is responsible for computing `minUsdeOut` from an independent
///      value reference (the sUSDe vault conversion rate) and passing it to
///      `swap`. The swapper enforces the floor but does not itself own a slippage policy.
///
///      The route is fixed at deployment and immutable:
///
///          sUSDe --[Pool 1: crvUSD/sUSDe]--> crvUSD --[Pool 2: crvUSD/USDe]--> USDe
///
///      The swapper is a stateless, ownerless periphery contract. It custodies no
///      funds between transactions: each `swap` pulls exactly the sUSDe it needs,
///      routes the proceeds through both pools, and forwards the resulting USDe to
///      the receiver. The coin indices are resolved and validated from each pool's
///      `coins` getter at construction.
///
///      All three tokens use 18 decimals, so the amounts pass through both legs
///      without scaling.
///
///      The slippage policy lives in the caller (the OlympusSUSDe wrapper), which
///      derives `minUsdeOut` from the sUSDe vault value. The per-leg pool
///      `min_dy` is left at zero because, within a single transaction, the pool
///      state read by `get_dy` matches the state used by `exchange`, so a per-leg
///      bound offers no protection against an earlier same-block manipulation. The
///      single reliable guard is the final `minUsdeOut` check on the measured output.
///
///      Operational notes:
///      - sUSDe can restrict transfers. If Ethena assigns the `FULL_RESTRICTED_STAKER_ROLE`
///        to this swapper, `swap` reverts at the inbound `transferFrom` (the swapper is the
///        recipient) and at the pool pull (the swapper is the sender).
///      - If a pool is paused or too illiquid to clear the floor, `swap` reverts. Callers
///        should tolerate this.
contract CurveSusdeSwapper is ISusdeSwapper, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    // ========== IMMUTABLES ========== //

    /// @notice The sUSDe token (the input).
    IERC20 private immutable _SUSDE;

    /// @notice The crvUSD token (the intermediate hop).
    IERC20 private immutable _CRVUSD;

    /// @notice The USDe token (the output).
    IERC20 private immutable _USDE;

    /// @notice The Curve crvUSD/sUSDe pool (leg 1).
    ICurveStableSwapNG private immutable _POOL1;

    /// @notice The Curve crvUSD/USDe pool (leg 2).
    ICurveStableSwapNG private immutable _POOL2;

    /// @notice The sUSDe coin index in pool 1.
    int128 private immutable _SUSDE_INDEX_1;

    /// @notice The crvUSD coin index in pool 1.
    int128 private immutable _CRVUSD_INDEX_1;

    /// @notice The crvUSD coin index in pool 2.
    int128 private immutable _CRVUSD_INDEX_2;

    /// @notice The USDe coin index in pool 2.
    int128 private immutable _USDE_INDEX_2;

    // ========== CONSTRUCTOR ========== //

    /// @notice Configures the immutable swap route.
    /// @dev Resolves and validates the coin indices from each pool and grants the
    ///      one-time maximum approvals each pool needs to pull its input coin.
    ///
    ///      Reverts if:
    ///      - Any argument is the zero address.
    ///      - Pool 1 does not contain exactly the sUSDe and crvUSD coin pair.
    ///      - Pool 2 does not contain exactly the crvUSD and USDe coin pair.
    /// @param susde_ The sUSDe token.
    /// @param crvUsd_ The crvUSD token.
    /// @param usde_  The USDe token.
    /// @param pool1_ The Curve crvUSD/sUSDe pool.
    /// @param pool2_ The Curve crvUSD/USDe pool.
    constructor(
        IERC20 susde_,
        IERC20 crvUsd_,
        IERC20 usde_,
        ICurveStableSwapNG pool1_,
        ICurveStableSwapNG pool2_
    ) {
        if (
            address(susde_) == address(0) ||
            address(crvUsd_) == address(0) ||
            address(usde_) == address(0) ||
            address(pool1_) == address(0) ||
            address(pool2_) == address(0)
        ) revert SusdeSwapper_ZeroAddress();

        _SUSDE = susde_;
        _CRVUSD = crvUsd_;
        _USDE = usde_;
        _POOL1 = pool1_;
        _POOL2 = pool2_;

        // Resolve the coin indices on-chain, preventing misconfiguration of the route.
        (_SUSDE_INDEX_1, _CRVUSD_INDEX_1) = _resolveIndices(
            pool1_,
            address(susde_),
            address(crvUsd_)
        );
        (_CRVUSD_INDEX_2, _USDE_INDEX_2) = _resolveIndices(
            pool2_,
            address(crvUsd_),
            address(usde_)
        );

        // Each pool pulls its input coin from this contract during the exchange, so a
        // single maximum approval per leg is granted once at deployment. The contract
        // holds no balance between transactions, so the standing approvals are not a
        // custody risk.
        susde_.forceApprove(address(pool1_), type(uint256).max);
        crvUsd_.forceApprove(address(pool2_), type(uint256).max);
    }

    // ========== SWAP ========== //

    /// @inheritdoc ISusdeSwapper
    /// @dev Pulls `susdeIn` sUSDe from the caller, so the caller must approve the
    ///      swapper beforehand.
    ///
    ///      Reverts if:
    ///      - `susdeIn` is zero.
    ///      - `receiver` is the zero address.
    ///      - The realized USDe output is below `minUsdeOut`.
    ///      - The caller does not approve this contract for the required sUSDe amount.
    function swap(
        uint256 susdeIn,
        uint256 minUsdeOut,
        address receiver
    ) external override nonReentrant returns (uint256 usdeOut) {
        if (susdeIn == 0) revert SusdeSwapper_ZeroAmount();
        if (receiver == address(0)) revert SusdeSwapper_ZeroAddress();

        // Pull the sUSDe from the caller (the wrapper), which must have approved this contract.
        _SUSDE.safeTransferFrom(msg.sender, address(this), susdeIn);

        // Leg 1: sUSDe -> crvUSD. The output is routed to this contract and measured by
        // the balance delta, which is more reliable than the pool return value.
        uint256 crvBefore = _CRVUSD.balanceOf(address(this));
        _POOL1.exchange(_SUSDE_INDEX_1, _CRVUSD_INDEX_1, susdeIn, 0, address(this));
        uint256 crvReceived = _CRVUSD.balanceOf(address(this)) - crvBefore;

        // Leg 2: crvUSD -> USDe, measured the same way.
        uint256 usdeBefore = _USDE.balanceOf(address(this));
        _POOL2.exchange(_CRVUSD_INDEX_2, _USDE_INDEX_2, crvReceived, 0, address(this));
        usdeOut = _USDE.balanceOf(address(this)) - usdeBefore;

        // Enforce the caller-supplied value floor. This is the single reliable guard.
        if (usdeOut < minUsdeOut) revert SusdeSwapper_SlippageExceeded(usdeOut, minUsdeOut);

        // Forward the USDe to the receiver.
        _USDE.safeTransfer(receiver, usdeOut);

        emit Swapped(msg.sender, receiver, susdeIn, usdeOut);
    }

    /// @inheritdoc ISusdeSwapper
    /// @dev This is a spot estimate read from the current pool state and can be
    ///      manipulated within a block. It must not be relied upon as a slippage
    ///      guard; it is intended for off-chain quoting and conservative sizing.
    function previewSwap(uint256 susdeIn) external view override returns (uint256 usdeOut) {
        if (susdeIn == 0) return 0;

        uint256 crvOut = _POOL1.get_dy(_SUSDE_INDEX_1, _CRVUSD_INDEX_1, susdeIn);
        usdeOut = _POOL2.get_dy(_CRVUSD_INDEX_2, _USDE_INDEX_2, crvOut);
    }

    // ========== VIEWS ========== //

    /// @inheritdoc ISusdeSwapper
    function susde() external view override returns (address) {
        return address(_SUSDE);
    }

    /// @inheritdoc ISusdeSwapper
    function usde() external view override returns (address) {
        return address(_USDE);
    }

    /// @notice The crvUSD token used as the intermediate hop.
    function crvUsd() external view returns (address) {
        return address(_CRVUSD);
    }

    /// @notice The Curve crvUSD/sUSDe pool (leg 1).
    function pool1() external view returns (address) {
        return address(_POOL1);
    }

    /// @notice The Curve crvUSD/USDe pool (leg 2).
    function pool2() external view returns (address) {
        return address(_POOL2);
    }

    // ========== INTERNAL ========== //

    /// @notice Resolves the indices of `tokenA_` and `tokenB_` within a two-coin pool.
    /// @dev Reverts with `SusdeSwapper_InvalidPool` if the pool does not hold exactly two
    ///      coins, or if its two coins are not exactly `tokenA_` and `tokenB_` in either
    ///      order. The two-coin check rejects pools whose invariant differs from the plain
    ///      pair this route assumes (the swap itself only operates on the two indices).
    /// @param pool_ The pool to inspect.
    /// @param tokenA_ The first token to locate.
    /// @param tokenB_ The second token to locate.
    /// @return idxA The index of `tokenA_`.
    /// @return idxB The index of `tokenB_`.
    function _resolveIndices(
        ICurveStableSwapNG pool_,
        address tokenA_,
        address tokenB_
    ) private view returns (int128 idxA, int128 idxB) {
        if (pool_.N_COINS() != 2) revert SusdeSwapper_InvalidPool(address(pool_));

        address coin0 = pool_.coins(0);
        address coin1 = pool_.coins(1);
        if (coin0 == tokenA_ && coin1 == tokenB_) return (0, 1);
        if (coin0 == tokenB_ && coin1 == tokenA_) return (1, 0);
        revert SusdeSwapper_InvalidPool(address(pool_));
    }
}
