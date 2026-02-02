// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.4;

// Based on Bond Protocol's `IFixedStrikeOptionTeller`:
// `https://github.com/Bond-Protocol/option-contracts/blob/b8ce2ca2bae3bd06f0e7665c3aa8d827e4d8ca2c/src/interfaces/IFixedStrikeOptionTeller.sol`

interface IConvertibleOHMTeller {
    /// @notice Emitted when a new convertible token is deployed.
    event ConvertibleTokenCreated(
        address indexed token,
        address indexed quoteToken,
        uint48 eligible,
        uint48 indexed expiry,
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

    /// @notice Emitted when the reward distributor is set.
    event RewardDistributorSet(address indexed rewardDistributor);

    error Teller_InvalidParams(uint256 index, bytes value);

    error Teller_TokenDoesNotExist(bytes32 tokenHash);

    error Teller_UnsupportedToken(address token);

    error Teller_TokenExpired(uint48 expiry);

    error Teller_NotEligible(uint48 eligible);

    error Teller_OnlyRewardDistributor();

    /// @notice Deploys a new convertible token and returns its address.
    /// @dev Only callable by the reward distributor.
    ///      If a convertible token already exists for the parameters, it returns that address.
    /// @param quoteToken_ The address token used that the purchaser will need to provide on exercise.
    /// @param eligible_ The timestamp at which the convertible token can first be exercised
    ///        (rounded to the nearest day in UTC).
    /// @param expiry_ The timestamp at which the convertible token can no longer be exercised
    ///        (rounded to the nearest day in UTC).
    /// @param strikePrice_ The strike price of the convertible token (in units of the `quoteToken_` per OHM).
    /// @return token The address of the convertible token being created.
    function deploy(
        address quoteToken_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) external returns (address token);

    /// @notice Mints convertible tokens to the `to`.
    /// @dev Only callable by the reward distributor.
    /// @param token_ The convertible token to mint.
    /// @param to_ The recipient address.
    /// @param amount_ The amount of tokens to mint.
    function create(address token_, address to_, uint256 amount_) external;

    /// @notice Exercises a convertible token: provides required quote tokens and receives OHM.
    /// @dev Burns convertible tokens and mints OHM to the caller.
    ///      The `exerciseCost()` function is assumed to be used to get the amount of quote tokens required to exercise.
    /// @param token_ The convertible token to exercise.
    /// @param amount_ The amount of convertible tokens to exercise.
    function exercise(address token_, uint256 amount_) external;

    /// @notice Sets the minimum duration to exercise a convertible token.
    /// @dev Only callable by addresses that have the convertible admin role.
    ///      The absolute minimum is 1 day due to rounding of eligible and expiry timestamps.
    /// @param duration_ The minimum duration in seconds.
    function setMinDuration(uint48 duration_) external;

    /// @notice Sets the address of the reward distributor responsible for deploying new convertible tokens and
    ///         minting existing convertible tokens to users.
    /// @dev Only callable by addresses that have the convertible admin role.
    /// @param rewardDistributor_ The address of the reward distributor.
    function setRewardDistributor(address rewardDistributor_) external;

    /// @notice Calculates the cost to exercise an amount of convertible tokens.
    /// @param token_ The convertible token to exercise.
    /// @param amount_ The amount of the convertible token to exercise.
    /// @return quoteToken The quote token required to exercise.
    /// @return cost The amount of the convertible token required to exercise.
    function exerciseCost(
        address token_,
        uint256 amount_
    ) external view returns (address quoteToken, uint256 cost);

    /// @notice Returns the address of a convertible token corresponding to specified parameters,
    ///         reverts if no token exists.
    /// @param quoteToken_ The address token used that the purchaser will need to provide on exercise.
    /// @param eligible_ The timestamp at which the convertible token can first be exercised
    ///        (rounded to the nearest day in UTC).
    /// @param expiry_ The timestamp at which the convertible token can no longer be exercised
    ///        (rounded to the nearest day in UTC).
    /// @param strikePrice_ The strike price of the convertible token (in units of the `quoteToken_` per OHM).
    /// @return token The address of the convertible token.
    function getToken(
        address quoteToken_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) external view returns (address token);

    /// @notice Returns the hash ID of a convertible token corresponding to specified parameters.
    /// @param quoteToken_ The address token used that the purchaser will need to provide on exercise.
    /// @param eligible_ The timestamp at which the convertible token can first be exercised
    ///        (rounded to the nearest day in UTC).
    /// @param expiry_ The timestamp at which the convertible token can no longer be exercised
    ///        (rounded to the nearest day in UTC).
    /// @param strikePrice_ The strike price of the convertible token (in units of the `quoteToken_` per OHM).
    /// @return hash The hash ID of the convertible token.
    function getTokenHash(
        address quoteToken_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) external view returns (bytes32 hash);

    /// @notice Returns the address of the reward distributor responsible for deploying new convertible tokens and
    ///         minting existing convertible tokens to users.
    function rewardDistributor() external view returns (address);

    /// @notice Returns the minimum duration in seconds during which a convertible token must be eligible for exercise.
    function minDuration() external view returns (uint48);
}
