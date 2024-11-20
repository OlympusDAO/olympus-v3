// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Module} from "src/Kernel.sol";

/// @title  Olympus Governance Delegation
/// @notice Olympus Governance Delegation (Module) Contract
/// @dev    The Olympus Governance Delegation Module enables policies to delegate gOHM on behalf
///         of users. 
///         If the gOHM is undelegated, this module acts as an escrow for the gOHM.
///         When the gOHM is delegated, new individual escrows are created for those delegates, and that
///         portion of gOHM is transferred to that escrow.
///         Account state is tracked per (policy, account) separately such that one policy cannot pull the 
///         gOHM from another policy (eg policy B pulling collateral out of the Cooler policy).
abstract contract DLGTEv1 is Module {

    // =========  ERRORS ========= //

    error DLGTE_InvalidAddress();
    error DLGTE_TooManyDelegates();
    error DLGTE_InvalidDelegateEscrow();
    error DLGTE_CanOnlyRescindDelegation();
    error DLGTE_InvalidAmount();
    error DLGTE_ExceededGOhmBalance(uint256 balance, uint256 requested);

    // ========= EVENTS ========= //

    event DelegateEscrowCreated(
        address indexed delegate,
        address indexed escrow
    );

    event TransferredGohm(
        address indexed policy,
        address indexed account, 
        int256 gOhmDelta
    );

    event DelegationApplied(
        address indexed policy,
        address indexed account, 
        address indexed fromDelegate, 
        address toDelegate, 
        uint256 gOhmAmount
    );

    event MaxDelegateAddressesSet(
        address indexed policy, 
        address indexed account, 
        uint256 maxDelegateAddresses
    );

    // ========= STRUCTS ======= //

    struct DelegationRequest {
        /// @dev The delegate to pull from. 
        /// In the case of utilising an undelegated amount, this can be address(0)
        address fromDelegate;

        /// @dev The address to delegate to. 
        /// In the case of removing from a delegate only (so it's undelegated), this can be address(0)
        address toDelegate;

        /// @dev The amount to (un)delegate.
        /// This may be set to type(uint256).max to represent all remaining undelegated gOHM
        /// A zero amount will revert
        uint256 amount;
    }
    
    struct AccountDelegation {
        /// @dev The delegate address - the receiver account of the gOHM voting power.
        address delegate;

        /// @dev The DelegateEscrow contract address for this `delegate`
        address escrow;

        /// @dev The amount delegated to this delegate address
        uint256 totalAmount;
    }

    enum AllowedDelegationRequests {
        /// @dev Both new delegations and rescinding delegations are allowed for each DelegationRequest
        Any,

        /// @dev Only rescinding delegations are allowed for each DelegationRequest
        RescindOnly
    }

    // ========= STATE ========= //

    /// @notice The gOhm token supplied by users/accounts, eg gOHM
    ERC20 public immutable gOHM;

    /// @dev The default maximum number of addresses an account can delegate to
    uint32 public constant DEFAULT_MAX_DELEGATE_ADDRESSES = 10;

    constructor(address gohm_) {
        gOHM = ERC20(gohm_);
    }

    // ========= FUNCTIONS ========= //

    /**
     * @notice Set an account to have more or less than the DEFAULT_MAX_DELEGATE_ADDRESSES 
     * number of delegates.
     */
    function setMaxDelegateAddresses(
        address account, 
        uint32 maxDelegateAddresses
    ) external virtual;

    /**
     * @notice Apply new gOHM delegations.
     * @param onBehalfOf The account to apply the delegation on behalf of
     * @param gOhmDelta .
     *     If positive, it represents a additional amount of gOHM which can then be delegated
     *      (it is pulled from the policy calling this function prior to applying the delegationRequests)
     *     If negative, that gOHM will be sent back to the policy after the delegationRequests are applied
     *      (at least this amount must be undelegated such that it is available to transfer)
     * @param delegationRequests The set of delegation requests to apply - which may be adding/removing 
     *     gOHM to delegates.
     * @param allowedRequests Whether the `delegationRequests` can add and rescind delegations,
     *     or only Rescind (in the case of liquidation events in Cooler where the collateral can be
     *     permisionlessly undelegated)
     */
    function applyDelegations(
        address onBehalfOf,
        int256 gOhmDelta,
        DelegationRequest[] calldata delegationRequests,
        AllowedDelegationRequests allowedRequests
    ) external virtual returns (
        uint256 totalDelegated
    );

    /**
     * @notice Paginated view of an account's delegations for a given policy
     * @dev This can be called sequentially, increasing the `startIndex` each time by the number of items
     * returned in the previous call, until number of items returned is less than `maxItems`
     * The `totalAmount` delegated within the return struct is across all policies for that user delegate
     */
    function accountDelegationsList(
        address policy,
        address account, 
        uint256 startIndex, 
        uint256 maxItems
    ) external virtual view returns (
        AccountDelegation[] memory delegations
    );

    /**
     * @notice A summary of an account's delegations for a given policy
     */
    function accountDelegationSummary(
        address policy,
        address account
    ) external virtual view returns (
        uint256 totalGOhm,
        uint256 delegatedGOhm,
        uint256 numDelegateAddresses,
        uint256 maxAllowedDelegateAddresses
    );
    
    /**
     * @notice The maximum number of delegates an account can have within a given policy
     */
    function maxDelegateAddresses(
        address policy,
        address account
    ) external virtual view returns (uint32 result);

}
