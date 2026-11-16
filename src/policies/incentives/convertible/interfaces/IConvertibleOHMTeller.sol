// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.4;

// Based on Bond Protocol's `IFixedStrikeOptionTeller`:
// `https://github.com/Bond-Protocol/option-contracts/blob/b8ce2ca2bae3bd06f0e7665c3aa8d827e4d8ca2c/src/interfaces/IFixedStrikeOptionTeller.sol`
// The AGPL-3.0 license is retained from the upstream interface this is derived from.

interface IConvertibleOHMTeller {
    // ========== EVENTS ========== //

    /// @notice Emitted when a new convertible token is deployed.
    event ConvertibleTokenCreated(
        address indexed token,
        address indexed quoteToken,
        address indexed creator,
        uint48 eligible,
        uint48 expiry,
        uint256 strikePrice
    );

    /// @notice Emitted when a convertible token is minted to a user.
    event ConvertibleTokenMinted(address indexed token, address indexed to, uint256 amount);

    /// @notice Emitted when a convertible token is exercised.
    event ConvertibleTokenExercised(
        address indexed token,
        address indexed user,
        uint256 amount,
        uint256 quoteAmount
    );

    /// @notice Emitted when the minimum duration is updated.
    /// @param duration The new minimum duration in seconds.
    event MinDurationSet(uint48 duration);

    /// @notice Emitted when the minimum eligible delay is updated.
    /// @param delay The new delay in seconds.
    event MinEligibleDelaySet(uint48 delay);

    /// @notice Emitted when a per-creator mint cap is set.
    /// @param creator The token creator address.
    /// @param cap The new cumulative mint cap in OHM units.
    event CreatorMintCapSet(address indexed creator, uint256 cap);

    /// @notice Emitted when an expired token is swept out of the active set.
    /// @param token The swept token address.
    /// @param reclaimedSupply The token's remaining supply at the time of sweep.
    event ActiveTokenSwept(address indexed token, uint256 reclaimedSupply);

    /// @notice Emitted when the heart-driven sweep call reverts internally and is swallowed by execute().
    event SweepExpiredTokensFailed();

    // ========== ERRORS ========== //

    /// @notice Thrown when invalid parameters are provided.
    /// @param index The index of the invalid parameter.
    /// @param value The invalid value.
    error Teller_InvalidParams(uint256 index, bytes value);

    /// @notice Thrown when referencing a token that does not exist.
    /// @param tokenHash The hash of the non-existent token.
    error Teller_TokenDoesNotExist(bytes32 tokenHash);

    /// @notice Thrown when the provided token is not supported.
    /// @param token The unsupported token address.
    error Teller_UnsupportedToken(address token);

    /// @notice Thrown when the caller is not the token's creator.
    /// @param caller The address of the caller.
    /// @param creator The expected creator address.
    error Teller_NotTokenCreator(address caller, address creator);

    /// @notice Thrown when an operation that requires a live token encounters an expired one.
    /// @param expiry The expiry timestamp of the token.
    error Teller_TokenExpired(uint48 expiry);

    /// @notice Thrown when attempting to exercise a token before its eligible date.
    /// @param eligible The eligible timestamp of the token.
    error Teller_NotEligible(uint48 eligible);

    /// @notice Thrown when a fee-on-transfer token is detected (received less than expected).
    /// @param expected The expected amount to be received.
    /// @param actual The actual amount received.
    error Teller_FeeOnTransfer(uint256 expected, uint256 actual);

    /// @notice Thrown when minting would push the creator's cumulative minted above the configured cap.
    /// @param creator The token creator address.
    /// @param minted The cumulative minted value that would result from the operation.
    /// @param cap The configured mint cap for this creator.
    error Teller_CapExceeded(address creator, uint256 minted, uint256 cap);

    /// @notice Thrown when setCreatorMintCap is called with a cap below the creator's cumulative minted.
    /// @param creator The token creator address.
    /// @param minted The creator's current cumulative minted value.
    /// @param cap The attempted new cap.
    error Teller_CapBelowMinted(address creator, uint256 minted, uint256 cap);

    // ========== CORE FUNCTIONS ========== //

    /// @notice Deploys a new convertible token and returns its address.
    /// @dev Only callable by addresses with the distributor role.
    ///      If a convertible token already exists for the parameters, it returns that address.
    ///
    ///      Both `eligible_` and `expiry_` are truncated to 00:00:00 UTC of their respective day.
    ///      Pass `eligible_ = 0` to have the teller compute the earliest UTC midnight that
    ///      satisfies the configured `minEligibleDelay`.
    ///
    /// @param quoteToken_ The token the purchaser will need to provide on exercise.
    /// @param eligible_ The timestamp at which the convertible token can first be exercised
    ///        (truncated to 00:00:00 UTC). Pass 0 to auto-compute from minEligibleDelay.
    /// @param expiry_ The timestamp at which the convertible token can no longer be exercised
    ///        (truncated to 00:00:00 UTC).
    /// @param strikePrice_ The strike price of the convertible token (in units of `quoteToken_` per OHM).
    /// @return token The address of the convertible token.
    function deploy(
        address quoteToken_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) external returns (address token);

    /// @notice Mints convertible tokens to `to_`.
    /// @dev Only callable by addresses with the distributor role.
    ///      Increases MINTR approval atomically to reserve OHM for future exercise.
    /// @param token_ The convertible token to mint.
    /// @param to_ The recipient address.
    /// @param amount_ The amount of convOHM to mint.
    function create(address token_, address to_, uint256 amount_) external;

    /// @notice Exercises a convertible token: burns convOHM, transfers quote tokens, mints OHM.
    /// @param token_ The convertible token to exercise.
    /// @param amount_ The amount of convertible tokens to exercise.
    function exercise(address token_, uint256 amount_) external;

    // ========== TOKEN LIFECYCLE ========== //

    /// @notice Removes expired tokens from the active set and reclaims MINTR approval.
    /// @dev Permissionless. Inspects up to `maxIterations_` entries of the active token set
    ///      and removes each one whose expiry has passed.
    /// @param maxIterations_ Maximum number of active-set entries to inspect.
    function sweepExpiredTokens(uint256 maxIterations_) external;

    // ========== ADMIN CONFIG ========== //

    /// @notice Sets the minimum duration to exercise a convertible token.
    /// @dev Only callable by admin. Minimum value is 1 day.
    /// @param duration_ The minimum duration in seconds.
    function setMinDuration(uint48 duration_) external;

    /// @notice Sets the minimum delay between token deployment and eligibility.
    /// @dev Only callable by admin. Minimum value is 1 day.
    ///      Ensures the emergency role has a time window to disable the contract
    ///      before newly deployed tokens become exercisable.
    /// @param delay_ The minimum eligible delay in seconds.
    function setMinEligibleDelay(uint48 delay_) external;

    /// @notice Sets the per-creator mint cap.
    /// @dev Only callable by admin.
    ///      The cap applies cumulatively: `create()` enforces `creatorMinted[creator] + amount <= cap`.
    ///      The cap must remain at or above the creator's current `creatorMinted` so budget
    ///      already charged cannot be retroactively shrunk.
    ///      Setting the cap equal to the current `creatorMinted` freezes new mints while keeping
    ///      existing tokens exercisable.
    /// @param creator_ The creator address.
    /// @param cap_ The new mint cap in OHM units.
    function setCreatorMintCap(address creator_, uint256 cap_) external;

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Calculates the cost to exercise an amount of convertible tokens.
    /// @param token_ The convertible token to exercise.
    /// @param amount_ The amount of the convertible token to exercise.
    /// @return quoteToken The quote token required to exercise.
    /// @return cost The amount of quote tokens required to exercise.
    function exerciseCost(
        address token_,
        uint256 amount_
    ) external view returns (address quoteToken, uint256 cost);

    /// @notice Returns the address of a convertible token corresponding to specified parameters,
    ///         reverts if no token exists.
    /// @dev Timestamps are truncated to 00:00:00 UTC before lookup, so any timestamp within the
    ///      same UTC day will resolve to the same token.
    /// @param quoteToken_ The token the purchaser will need to provide on exercise.
    /// @param creator_ The distributor address that deployed the convertible token.
    /// @param eligible_ The timestamp at which the convertible token can first be exercised
    ///        (truncated to 00:00:00 UTC).
    /// @param expiry_ The timestamp at which the convertible token can no longer be exercised
    ///        (truncated to 00:00:00 UTC).
    /// @param strikePrice_ The strike price of the convertible token (in units of `quoteToken_` per OHM).
    /// @return token The address of the convertible token.
    function getToken(
        address quoteToken_,
        address creator_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) external view returns (address token);

    /// @notice Returns the hash ID of a convertible token corresponding to specified parameters.
    /// @dev Timestamps are truncated to 00:00:00 UTC before hashing, so any timestamp within the
    ///      same UTC day will produce the same hash.
    /// @param quoteToken_ The token the purchaser will need to provide on exercise.
    /// @param creator_ The distributor address that deployed the convertible token.
    /// @param eligible_ The timestamp at which the convertible token can first be exercised
    ///        (truncated to 00:00:00 UTC).
    /// @param expiry_ The timestamp at which the convertible token can no longer be exercised
    ///        (truncated to 00:00:00 UTC).
    /// @param strikePrice_ The strike price of the convertible token (in units of `quoteToken_` per OHM).
    /// @return hash The hash ID of the convertible token.
    function getTokenHash(
        address quoteToken_,
        address creator_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) external pure returns (bytes32 hash);

    /// @notice Returns the minimum duration in seconds during which a convertible token must be eligible for exercise.
    /// @return duration The minimum duration in seconds.
    function minDuration() external view returns (uint48 duration);

    /// @notice Returns the minimum delay in seconds between token deployment and eligibility.
    /// @return delay The minimum eligible delay in seconds.
    function minEligibleDelay() external view returns (uint48 delay);

    /// @notice Returns the remaining MINTR approval for this contract.
    /// @return remaining The remaining MINTR approval in OHM units.
    function remainingMintApproval() external view returns (uint256 remaining);

    /// @notice Returns the mint cap configured for a given creator.
    /// @param creator The creator address.
    /// @return cap The cumulative mint cap in OHM units.
    function creatorMintCap(address creator) external view returns (uint256 cap);

    /// @notice Returns the current outstanding convOHM for a given creator.
    /// @param creator The creator address.
    /// @return outstanding The sum of live convOHM across this creator's active tokens.
    function creatorOutstanding(address creator) external view returns (uint256 outstanding);

    /// @notice Returns the cumulative convOHM ever minted for a given creator.
    /// @dev Monotonically non-decreasing. Used as the basis for the cumulative mint cap enforced in create().
    /// @param creator The creator address.
    /// @return minted The cumulative convOHM ever minted for this creator.
    function creatorMinted(address creator) external view returns (uint256 minted);

    /// @notice Returns the number of tokens in the active set (deployed and not yet swept;
    ///         may briefly include expired tokens until the next sweep).
    /// @return length The number of tokens currently in the active set.
    function activeTokensLength() external view returns (uint256 length);

    /// @notice Returns the active token at the given index.
    /// @param index_ The index in the active set.
    /// @return token The token address at the given index.
    function activeTokenAt(uint256 index_) external view returns (address token);

    /// @notice Returns true if the token is in the active set.
    /// @param token_ The token address to check.
    /// @return isActive True if the token is in the active set, false otherwise.
    function isActiveToken(address token_) external view returns (bool isActive);

    /// @notice Returns all active tokens as an array.
    /// @dev May be gas-intensive for large sets; prefer `activeTokenAt` for on-chain use.
    /// @return tokens The array of active token addresses.
    function activeTokens() external view returns (address[] memory tokens);
}
