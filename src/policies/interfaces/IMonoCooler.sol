// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {DLGTEv1} from "modules/DLGTE/DLGTE.v1.sol";

interface IMonoCooler {
    error ExceededMaxOriginationLtv(uint256 newLtv, uint256 maxOriginationLtv);
    error ExceededCollateralBalance();
    error MinDebtNotMet(uint256 minRequired, uint256 current);
    error InvalidAddress();
    error InvalidParam();
    error ExpectedNonZero();
    error Paused();
    error CannotLiquidate();
    error InvalidDelegationRequests();
    error ExceededPreviousLtv(uint256 oldLtv, uint256 newLtv);
    error InvalidCollateralDelta();

    event LiquidationLtvSet(uint256 ltv);
    event MaxOriginationLtvSet(uint256 ltv);
    event BorrowPausedSet(bool isPaused);
    event LiquidationsPausedSet(bool isPaused);
    event MinDebtRequiredSet(uint128 amount);
    event InterestRateSet(uint16 interestRateBps);

    event CollateralAdded(
        address indexed fundedBy,
        address indexed onBehalfOf,
        uint128 collateralAmount
    );
    event CollateralWithdrawn(
        address indexed account,
        address indexed recipient,
        uint128 collateralAmount
    );
    event Borrow(address indexed account, address indexed recipient, uint128 amount);
    event Repay(address indexed fundedBy, address indexed onBehalfOf, uint128 repayAmount);
    event Liquidated(address indexed account, uint128 collateralSeized, uint128 debtWiped);

    /// @notice The record of an individual account's collateral and debt data
    struct AccountState {
        /// @notice The amount of gOHM collateral the account has posted
        uint128 collateral;
        /**
         * @notice A checkpoint of user debt, updated after a borrow/repay/liquidation
         * @dev Debt as of now =  (
         *    `account.debtCheckpoint` *
         *    `debtTokenData.interestAccumulator` /
         *    `account.interestAccumulator`
         * )
         */
        uint128 debtCheckpoint;
        /// @notice The account's last interest accumulator checkpoint
        uint256 interestAccumulatorRay;
    }

    /// @notice The status for whether an account can be liquidated or not
    struct LiquidationStatus {
        /// @notice The amount [in gOHM collateral terms] of collateral which has been provided by the user
        uint128 collateral;
        /// @notice The up to date amount of debt [in debtToken terms]
        uint128 currentDebt;
        /// @notice The current LTV of this account [in debtTokens per gOHM collateral terms]
        uint256 currentLtv;
        /// @notice Has this account exceeded the liquidation LTV
        bool exceededLiquidationLtv;
        /// @notice Has this account exceeded the max origination LTV
        bool exceededMaxOriginationLtv;
    }

    /// @notice An account's collateral and debt position details
    /// Provided for UX
    struct AccountPosition {
        /// @notice The amount [in gOHM collateral terms] of collateral which has been provided by the user
        uint256 collateral;
        /// @notice The up to date amount of debt [in debtToken terms]
        uint256 currentDebt;
        /// @notice The maximum amount of debtToken's this account can borrow given the
        /// collateral posted, up to `maxOriginationLtv`
        uint256 maxOriginationDebtAmount;
        /// @notice The maximum amount of debtToken's this account can accrue before being
        /// eligable to be liquidated, up to `liquidationLtv`
        uint256 liquidationDebtAmount;
        /// @notice The health factor of this accounts position.
        /// Anything less than 1 can be liquidated, relative to `liquidationLtv`
        uint256 healthFactor;
        /// @notice The current LTV of this account [in debtTokens per gOHM collateral terms]
        uint256 currentLtv;
        /// @notice The total collateral delegated for this user across all delegates
        uint256 totalDelegated;
        /// @notice The current number of addresses this account has delegated to
        uint256 numDelegateAddresses;
        /// @notice The max number of delegates this account is allowed to delegate to
        uint256 maxDelegateAddresses;
    }

    /// @notice The collateral token supplied by users/accounts, eg gOHM
    function collateralToken() external view returns (ERC20);

    /// @notice The debt token which can be borrowed, eg DAI or USDS
    function debtToken() external view returns (ERC20);

    /**
     * @notice The minimum debt a user needs to maintain
     * @dev It costs gas to liquidate users, so we don't want dust amounts.
     */
    function minDebtRequired() external view returns (uint256);

    /// @notice The total amount of collateral posted across all accounts.
    function totalCollateral() external view returns (uint128);

    /// @notice The total amount of debt which has been borrowed across all users
    /// as of the latest checkpoint
    function totalDebt() external view returns (uint128);

    /// @notice Liquidations may be paused in order for users to recover/repay debt after
    /// emergency actions or interest rate changes
    function liquidationsPaused() external view returns (bool);

    /// @notice Borrows may be paused for emergency actions or deprecating the facility
    function borrowsPaused() external view returns (bool);

    /// @notice The flat interest rate, defined in basis points.
    /// @dev Interest (approximately) continuously compounds at this rate.
    function interestRateBps() external view returns (uint16);

    /// @notice The Loan To Value point at which an account can be liquidated
    /// @dev Defined in terms of [debtToken/collateralToken] -- eg [USDS/gOHM]
    function liquidationLtv() external view returns (uint96);

    /// @notice The maximum Loan To Value an account is allowed when borrowing or withdrawing collateral
    /// @dev Defined in terms of [debtToken/collateralToken] -- eg [USDS/gOHM]
    function maxOriginationLtv() external view returns (uint96);

    /// @notice The last time the global debt accumulator was updated
    function interestAccumulatorUpdatedAt() external view returns (uint32);

    /// @notice The accumulator index used to track the compounding of debt, starting at 1e27 at genesis
    /// @dev To RAY (1e27) precision
    function interestAccumulatorRay() external view returns (uint256);

    //============================================================================================//
    //                                        COLLATERAL                                          //
    //============================================================================================//

    /**
     * @notice Deposit gOHM as collateral
     * @param collateralAmount The amount to deposit
     *    - MUST be greater than zero
     * @param onBehalfOf An account can add collateral on behalf of themselves or another address.
     *    - MUST NOT be address(0)
     * @param delegationRequests The set of delegations to apply after adding collateral.
     *    - MAY be empty, meaning no delegations are applied.
     *    - Total collateral delegated as part of these requests MUST BE less than the account collateral.
     *    - MUST NOT apply delegations that results in more collateral being undelegated than
     *      the account has collateral for.
     *    - MUST be empty if `onBehalfOf` does not equal msg.sender - ie calling on behalf of another address.
     */
    function addCollateral(
        uint128 collateralAmount,
        address onBehalfOf,
        DLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external;

    /**
     * @notice Withdraw gOHM collateral.
     *    - Account LTV MUST be less than or equal to `maxOriginationLtv` after the withdraw is applied
     *    - At least `collateralAmount` collateral MUST be undelegated for this account.
     *      Use the `delegationRequests` to rescind enough as part of this request.
     * @param collateralAmount The amount of collateral to remove
     *    - MUST be greater than zero
     *    - If set to type(uint128).max then withdraw the max amount up to maxOriginationLtv
     * @param recipient Send the gOHM collateral to a specified recipient address.
     *    - MUST NOT be address(0)
     * @param delegationRequests The set of delegations to apply before removing collateral.
     *    - MAY be empty, meaning no delegations are applied.
     *    - Total collateral delegated as part of these requests MUST BE less than the account collateral.
     *    - MUST NOT apply delegations that results in more collateral being undelegated than
     *      the account has collateral for.
     */
    function withdrawCollateral(
        uint128 collateralAmount,
        address recipient,
        DLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external returns (uint128 collateralWithdrawn);

    //============================================================================================//
    //                                       BORROW/REPAY                                         //
    //============================================================================================//

    /**
     * @notice Borrow `debtToken`
     *    - Account LTV MUST be less than or equal to `maxOriginationLtv` after the borrow is applied
     *    - Total debt for this account MUST be greater than or equal to the `minDebtRequired`
     *      after the borrow is applied
     * @param borrowAmount The amount of `debtToken` to borrow
     *    - MUST be greater than zero
     *    - If set to type(uint128).max then borrow the max amount up to maxOriginationLtv
     * @param recipient Send the borrowed token to a specified recipient address.
     *    - MUST NOT be address(0)
     * @return amountBorrowed The amount actually borrowed.
     */
    function borrow(
        uint128 borrowAmount,
        address recipient
    ) external returns (uint128 amountBorrowed);

    /**
     * @notice Repay a portion, or all of the debt
     *    - MUST NOT be called for an account which has no debt
     *    - If the entire debt isn't paid off, then the total debt for this account
     *      MUST be greater than or equal to the `minDebtRequired` after the borrow is applied
     * @param repayAmount The amount to repay.
     *    - MUST be greater than zero
     *    - MAY be greater than the latest debt as of this block. In which case it will be capped
     *      to that latest debt
     * @param onBehalfOf Another address can repay the debt on behalf of someone else
     * @return amountRepaid The amount actually repaid.
     */
    function repay(uint128 repayAmount, address onBehalfOf) external returns (uint128 amountRepaid);

    //============================================================================================//
    //                                         COMPOSITE                                          //
    //============================================================================================//

    /**
     * @notice Caller adds collateral and borrows in the same transaction
     *    - The same functionality as individually calling addCollateral() and then borrow()
     *    - Cannot call 'on behalf of' another address.
     * @param collateralAmount The amount to deposit
     *    - MUST be greater than zero
     * @param borrowAmount The amount of `debtToken` to borrow
     *    - MUST be greater than zero
     *    - If set to type(uint128).max then borrow the max amount up to maxOriginationLtv
     * @param recipient Send the borrowed token to a specified recipient address.
     *    - MUST NOT be address(0)
     * @param delegationRequests The set of delegations to apply after adding collateral.
     *    - MAY be empty, meaning no delegations are applied.
     *    - Total collateral delegated as part of these requests MUST BE less than the account collateral.
     *    - MUST NOT apply delegations that results in more collateral being undelegated than
     *      the account has collateral for.
     * @return amountBorrowed The amount actually borrowed.
     */
    function addCollateralAndBorrow(
        uint128 collateralAmount,
        uint128 borrowAmount,
        address recipient,
        DLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external returns (uint128 amountBorrowed);

    /**
     * @notice Caller adds collateral and borrows on behalf of another account, in the same transaction
     *    - The new LTV of `onBehalfOf` must be less than or equal to the existing LTV
     *    - The same functionality as individually calling addCollateral() and then borrow()
     *      on behalf of another account.
     * @param onBehalfOf An account can add collateral on behalf of themselves or another address.
     *    - MUST NOT be address(0)
     *    - This account also receives the borrowed funds
     * @param collateralAmount The amount to deposit
     *    - MUST be greater than zero
     * @param borrowAmount The amount of `debtToken` to borrow
     *    - MUST be greater than zero
     *    - LTV for `onBehalfOf` MUST NOT exceed their LTV prior to calling this function, or it is
     *      a new position
     *    - If set to type(uint128).max then borrow the max amount up to the EXISTING LTV of that account
     * @return amountBorrowed The amount actually borrowed.
     */
    function addCollateralAndBorrowOnBehalfOf(
        address onBehalfOf,
        uint128 collateralAmount,
        uint128 borrowAmount
    ) external returns (uint128 amountBorrowed);

    /**
     * @notice Caller repays a portion, or all of the debt and then withdraws collateral, in the same transaction
     *    - The same functionality as individually calling repay() and then removeCollateral()
     *    - MUST NOT be called for an account which has no debt
     *    - If the entire debt isn't paid off, then the total debt for this account
     *      MUST be greater than or equal to the `minDebtRequired` after the borrow is applied
     * @param repayAmount The amount to repay.
     *    - MUST be greater than zero
     *    - MAY be greater than the latest debt as of this block. In which case it will be capped
     *      to that latest debt
     * @param collateralAmount The amount of collateral to remove
     *    - MUST be greater than zero
     *    - If set to type(uint128).max then withdraw the max amount up to maxOriginationLtv
     * @param recipient Send the gOHM collateral to a specified recipient address.
     *    - MUST NOT be address(0)
     * @param delegationRequests The set of delegations to apply before removing collateral.
     *    - MAY be empty, meaning no delegations are applied.
     *    - Total collateral delegated as part of these requests MUST BE less than the account collateral.
     *    - MUST NOT apply delegations that results in more collateral being undelegated than
     *      the account has collateral for.
     * @return amountRepaid The amount actually repaid.
     */
    function repayAndWithdrawCollateral(
        uint128 repayAmount,
        uint128 collateralAmount,
        address recipient,
        DLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external returns (uint128 amountRepaid, uint128 withdrawCollateral);

    /**
     * @notice Apply a set of delegation requests on behalf of a given user.
     *  - Each delegation request either delegates or undelegates to an address
     *  - It applies across total gOHM balances for a given account across all calling policies
     *    So this may (un)delegate the account's gOHM set by another policy
     */
    function applyDelegations(
        DLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external returns (uint256 totalDelegated, uint256 totalUndelegated);

    /**
     * @notice Liquidate one or more accounts which have exceeded the `liquidationLtv`
     * The gOHM collateral is seized (unstaked to OHM and burned), and the accounts debt is wiped.
     * @dev If one of the provided accounts in the batch hasn't exceeded the max LTV then it is skipped.
     */
    function batchLiquidate(
        address[] calldata accounts,
        DLGTEv1.DelegationRequest[][] calldata delegationRequests
    ) external returns (uint128 totalCollateralClaimed, uint128 totalDebtWiped);

    /**
     * @notice If an account becomes unhealthy and has many delegations such that liquidation can't be
     * performed in one transaction, then delegations can be rescinded over multiple transactions
     * in order to get this account into a state where it can then be liquidated.
     */
    function applyUnhealthyDelegations(
        address account,
        DLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external returns (uint256 totalUndelegated);

    //============================================================================================//
    //                                           ADMIN                                            //
    //============================================================================================//

    /**
     * @notice Set the Loan To Value's for both the `liquidationLtv` and `maxOriginationLtv`
     * @param newLiquidationLtv The Loan To Value point at which an account can be liquidated
     *    - Defined in terms of [debtToken/collateralToken] -- eg [USDS/gOHM]
     *    - MUST NOT decrease compared to the existing `liquidationLtv`
     * @param newMaxOriginationLtv The maximum Loan To Value an account is allowed to have when
     *      borrowing or withdrawing collateral
     *    - Defined in terms of [debtToken/collateralToken] -- eg [USDS/gOHM]
     *    - MUST be greater than the `newLiquidationLtv`
     */
    function setLoanToValue(uint96 newLiquidationLtv, uint96 newMaxOriginationLtv) external;

    /**
     * @notice Liquidation may be paused in order for users to recover/repay debt after emergency
     * actions
     */
    function setLiquidationsPaused(bool isPaused) external;

    /**
     * @notice Pause any new borrows of `debtToken`
     */
    function setBorrowPaused(bool isPaused) external;

    /**
     * @notice Update the interest rate, specified in basis points.
     */
    function setInterestRateBps(uint16 newInterestRateBps) external;

    /**
     * @notice Allow an account to have more or less than the DEFAULT_MAX_DELEGATE_ADDRESSES
     * number of delegates.
     */
    function setMaxDelegateAddresses(address account, uint32 maxDelegateAddresses) external;

    /**
     * @notice Update and checkpoint the total debt up until now
     * @dev May be useful in case there are no new user actions for some time.
     */
    function checkpointDebt() external returns (uint128 totalDebt, uint256 interestAccumulatorRay);

    //============================================================================================//
    //                                      AUX FUNCTIONS                                         //
    //============================================================================================//

    /**
     * @notice Calculate the difference in debt required in order to be at or just under
     * the maxOriginationLTV if `collateralDelta` was added/removed
     * from the current position.
     * A positive `debtDelta` means the account can borrow that amount after adding that `collateralDelta` collateral
     * A negative `debtDelta` means it needs to repay that amount in order to withdraw that `collateralDelta` collateral
     */
    function debtDeltaForMaxOriginationLtv(
        address account,
        int128 collateralDelta
    ) external view returns (int128 debtDelta);

    /**
     * @notice An view of an accounts current and up to date position as of this block
     * @param account The account to get a position for
     */
    function accountPosition(
        address account
    ) external view returns (AccountPosition memory position);

    /**
     * @notice Compute the liquidity status for a set of accounts.
     * @dev This can be used to verify if accounts can be liquidated or not.
     * @param accounts The accounts to get the status for.
     */
    function computeLiquidity(
        address[] calldata accounts
    ) external view returns (LiquidationStatus[] memory status);

    /**
     * @notice Paginated view of an account's delegations
     * @dev Can call sequentially increasing the `startIndex` each time by the number of items returned in the previous call,
     * until number of items returned is less than `maxItems`
     */
    function accountDelegationsList(
        address account,
        uint256 startIndex,
        uint256 maxItems
    ) external view returns (DLGTEv1.AccountDelegation[] memory delegations);

    /**
     * @notice A view of the last checkpoint of account data (not as of this block)
     */
    function accountState(address account) external view returns (AccountState memory);

    /**
     * @notice A view of the derived/internal cache data.
     */
    function globalState()
        external
        view
        returns (uint128 totalDebt, uint256 interestAccumulatorRay);
}
