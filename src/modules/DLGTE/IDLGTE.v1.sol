// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "../../interfaces/IERC20.sol";

interface IDLGTEv1 {
    // =========  ERRORS ========= //

    error DLGTE_InvalidAddress();
    error DLGTE_InvalidDelegationRequests();
    error DLGTE_TooManyDelegates();
    error DLGTE_InvalidDelegateEscrow();
    error DLGTE_InvalidAmount();

    error DLGTE_ExceededUndelegatedBalance(uint256 balance, uint256 requested);
    error DLGTE_ExceededDelegatedBalance(address delegate, uint256 balance, uint256 requested);
    error DLGTE_ExceededPolicyAccountBalance(uint256 balance, uint256 requested);

    // ========= EVENTS ========= //

    event DelegationApplied(address indexed account, address indexed delegate, int256 amount);

    event MaxDelegateAddressesSet(address indexed account, uint256 maxDelegateAddresses);

    // ========= STRUCTS ======= //

    struct DelegationRequest {
        /// @dev The address of the delegate
        address delegate;
        /// @dev The amount to (un)delegate.
        /// positive means delegate, negative undelegate.
        int256 amount;
    }

    struct AccountDelegation {
        /// @dev The delegate address - the receiver account of the gOHM voting power.
        address delegate;
        /// @dev The amount of gOHM delegated to `delegate`
        uint256 amount;
        /// @dev The DelegateEscrow contract address for this `delegate`
        address escrow;
    }

    // ========= FUNCTIONS ========= //

    /**
     * @notice Set an account to have more or less than the DEFAULT_MAX_DELEGATE_ADDRESSES
     * number of delegates.
     */
    function setMaxDelegateAddresses(address account, uint32 maxDelegateAddresses) external;

    /**
     * @notice gOHM is pulled from the calling policy - this will not be used for governance delegation
     * @dev Balances are tracked per policy such that policyA cannot interfere with policyB's gOHM
     */
    function depositUndelegatedGohm(address onBehalfOf, uint256 amount) external;

    /**
     * @notice Undelegated gOHM is transferred to the calling policy.
     * This will revert if there is not enough undelegated gOHM for `onBehalfOf`
     * or if policy is attempting to withdraw more gOHM than it is entitled to.
     * @dev Balances are tracked per policy such that policyA cannot interfere with policyB's gOHM
     */
    function withdrawUndelegatedGohm(address onBehalfOf, uint256 amount) external;

    /**
     * @notice Apply a set of delegation requests on behalf of a given account.
     *  - Each delegation request either delegates or undelegates to an address
     *  - It applies across total gOHM balances for a given account across all calling policies
     *    So policyA may (un)delegate the account's gOHM set by policyA, B and C
     */
    function applyDelegations(
        address onBehalfOf,
        DelegationRequest[] calldata delegationRequests
    )
        external
        returns (uint256 totalDelegated, uint256 totalUndelegated, uint256 undelegatedBalance);

    /**
     * @notice Report the total delegated and undelegated gOHM balance for an account
     * in a given policy
     */
    function policyAccountBalances(
        address policy,
        address account
    ) external view returns (uint256 gOhmBalance);

    /**
     * @notice Paginated view of an account's delegations
     * @dev This can be called sequentially, increasing the `startIndex` each time by the number of items
     * returned in the previous call, until number of items returned is less than `maxItems`
     * The `totalAmount` delegated within the return struct is across all policies for that account delegate
     */
    function accountDelegationsList(
        address account,
        uint256 startIndex,
        uint256 maxItems
    ) external view returns (AccountDelegation[] memory delegations);

    /**
     * @notice A summary of an account's delegations
     */
    function accountDelegationSummary(
        address account
    )
        external
        view
        returns (
            uint256 totalGOhm,
            uint256 delegatedGOhm,
            uint256 numDelegateAddresses,
            uint256 maxAllowedDelegateAddresses
        );

    /**
     * @notice The total amount delegated to a particular delegate across all policies,
     * and externally made delegations (including any permanent donations)
     */
    function totalDelegatedTo(address delegate) external view returns (uint256);

    /**
     * @notice The maximum number of delegates an account can have accross all policies
     */
    function maxDelegateAddresses(address account) external view returns (uint32 result);

    /// @notice The gOhm token supplied by accounts
    function gOHM() external view returns (IERC20);

    /// @notice The default maximum number of addresses an account can delegate to
    function DEFAULT_MAX_DELEGATE_ADDRESSES() external view returns (uint32);
}
