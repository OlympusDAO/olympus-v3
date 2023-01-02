// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "src/Kernel.sol";

/// @title  Olympus Lender
/// @notice Olympus Lender (Module) Contract
/// @dev    The Olympus Lender Module tracks approval and debt limits for OHM denominated debt
///         markets. This facilitates the minting of OHM into those markets to provide liquidity.
abstract contract LENDRv1 is Module {
    // ========= EVENTS ========= //

    event Borrow(address indexed market, uint256 amount);
    event Repay(address indexed market, uint256 amount);
    event MarketApproved(address indexed market);
    event MarketRemoved(address indexed market);
    event MarketLimitUpdated(address indexed market, uint256 newLimit);
    event MarketRateUpdated(address indexed market, uint32 newRate);
    event MarketUnwindUpdated(address indexed market, bool shouldUnwind);
    event GlobalLimitUpdated(uint256 newLimit);

    // ========= ERRORS ========= //

    error LENDR_GlobalLimitViolation();
    error LENDR_MarketLimitViolation();
    error LENDR_MarketAlreadyApproved();
    error LENDR_InvalidMarketRemoval();
    error LENDR_UnapprovedMarket();
    error LENDR_InvalidParams();

    // ========= STATE ========= //

    /// @notice Maximum level of total debt in the system
    uint256 public globalDebtLimit;

    /// @notice Current level of total debt in the system
    uint256 public globalDebtOutstanding;

    /// @notice approvedMarketsCount
    /// @dev    This is a useless variable in contracts but useful for any frontends or
    ///         off-chain requests where the array is not easily accessible.
    uint256 public approvedMarketsCount;

    /// @notice List of approved lending markets
    /// @dev    This is redundant with isMarketApproved, but is used to iterate over all markets
    ///         for future reportin use cases
    address[] public approvedMarkets;

    /// @notice Tracks whether an address is an approved lending market
    mapping(address => bool) public isMarketApproved;

    /// @notice Maximum level of debt a market can take on
    mapping(address => uint256) public marketDebtLimit;

    /// @notice Current debt level of a market
    mapping(address => uint256) public marketDebtOutstanding;

    /// @notice The rate that a market should target
    mapping(address => uint32) public marketTargetRate;

    /// @notice Should the market be reducing debt as quickly as possible
    mapping(address => bool) public shouldUnwind;

    // ========= FUNCTIONS ========= //

    /// @notice                 Increases the current debt outstanding of a market
    /// @param amount_          The amount of OHM to borrow and increase debt outstanding by
    /// @dev                    Cannot borrow more than the market's limit
    function borrow(uint256 amount_) external virtual;

    /// @notice                 Decreases the current debt outstanding of a market
    /// @param amount_          The amount of OHM to repay and decrease debt outstanding by
    function repay(uint256 amount_) external virtual;

    /// @notice                 Updates the global debt limit
    /// @param newLimit_        The new global debt limit
    /// @dev                    The new limit cannot be less than the current global debt outstanding
    function setGlobalLimit(uint256 newLimit_) external virtual;

    /// @notice                 Updates a market's debt limit
    /// @param market_          The market to set the new debt limit for
    /// @param newLimit_        The new debt limit for the market
    /// @dev                    The new limit cannot be less than the current market debt outstanding
    function setMarketLimit(address market_, uint256 newLimit_) external virtual;

    /// @notice                 Updates a market's target interest rate
    /// @param market_          The market to set the new target interest rate for
    /// @param newRate_         The new target rate for the market
    function setMarketTargetRate(address market_, uint32 newRate_) external virtual;

    /// @notice                 Sets whether a market should be reducing debt as quickly as possible
    /// @param market_          The market to change the shouldUnwind status for
    /// @param shouldUnwind_    Should the market be reducing debt as quickly as possible
    function setUnwind(address market_, bool shouldUnwind_) external virtual;

    /// @notice                 Approves a market for borrowing
    /// @param market_          The market to approve
    function approveMarket(address market_) external virtual;

    /// @notice                 Revokes a market's borrowing privileges
    /// @param index_           The index of the market in the list of approved markets to remove
    /// @param market_          The address of the market to remove
    function removeMarket(uint256 index_, address market_) external virtual;
}
