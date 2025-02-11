// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Module} from "src/Kernel.sol";
import {IDLGTEv1} from "modules/DLGTE/IDLGTE.v1.sol";

/**
 * @title  Olympus Governance Delegation
 * @notice Olympus Governance Delegation (Module) Contract
 * @dev    The Olympus Governance Delegation Module enables policies to delegate gOHM on behalf of accounts.
 *         If the gOHM is undelegated, this module acts as an escrow for the gOHM.
 *         When the gOHM is delegated, new individual escrows are created for those delegates, and that
 *         portion of gOHM is transferred to that escrow.
 *         gOHM balances are tracked per (policy, account) separately such that one policy cannot pull the
 *         gOHM from another policy (eg policy B pulling collateral out of the Cooler policy).
 */
abstract contract DLGTEv1 is Module, IDLGTEv1 {
    // ========= STATE ========= //

    /// @notice The gOhm token supplied by accounts, eg gOHM
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
    function setMaxDelegateAddresses(address account, uint32 maxDelegateAddresses) external virtual;

    /**
     * @notice gOHM is pulled from the calling policy - this will not be used for governance delegation
     * @dev Balances are tracked per policy such that policyA cannot interfere with policyB's gOHM
     */
    function depositUndelegatedGohm(address onBehalfOf, uint256 amount) external virtual;

    /**
     * @notice Undelegated gOHM is transferred to the calling policy.
     * This will revert if there is not enough undelegated gOHM for `onBehalfOf`
     * or if policy is attempting to withdraw more gOHM than it is entitled to.
     * @dev Balances are tracked per policy such that policyA cannot interfere with policyB's gOHM
     */
    function withdrawUndelegatedGohm(address onBehalfOf, uint256 amount) external virtual;

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
        virtual
        returns (uint256 totalDelegated, uint256 totalUndelegated, uint256 undelegatedBalance);

    /**
     * @notice Report the total delegated and undelegated gOHM balance for an account
     * in a given policy
     */
    function policyAccountBalances(
        address policy,
        address account
    ) external view virtual returns (uint256 gOhmBalance);

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
    ) external view virtual returns (AccountDelegation[] memory delegations);

    /**
     * @notice A summary of an account's delegations
     */
    function accountDelegationSummary(
        address account
    )
        external
        view
        virtual
        returns (
            uint256 totalGOhm,
            uint256 delegatedGOhm,
            uint256 numDelegateAddresses,
            uint256 maxAllowedDelegateAddresses
        );

    /**
     * @notice The maximum number of delegates an account can have accross all policies
     */
    function maxDelegateAddresses(address account) external view virtual returns (uint32 result);
}
