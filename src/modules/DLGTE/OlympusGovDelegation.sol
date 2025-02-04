// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {EnumerableSet} from "openzeppelin/utils/structs/EnumerableSet.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Kernel, Module, Keycode, toKeycode} from "src/Kernel.sol";
import {DLGTEv1} from "modules/DLGTE/DLGTE.v1.sol";
import {DelegateEscrow} from "src/external/cooler/DelegateEscrow.sol";
import {DelegateEscrowFactory} from "src/external/cooler/DelegateEscrowFactory.sol";
import {SafeCast} from "libraries/SafeCast.sol";

/*
@todo considerations - up for discussion:

1/ It is NOT possible for policy A (some other non-Cooler policy) to withdraw and use the gOHM which was deposited by policy B (eg cooler)
      Since this could be dangerous if policy A utilises that gOHM - as that could be collateral that needs to be used in a liquidation event.

   It IS however possible for policy A to *(un)delegate* the gOHM on behalf of a user across policies.
   Eg - If policy A deposited and then delegated Alice's gOHM to Bob. 
      - And then there's a cooler liquidation on Alice. 
      - Cooler is allowed to undelegate the total gOHM for Alice across both policies.
      - However cooler is NOT allowed to withdraw the gOHM deposited by policy B

2/ Because deposit/withdraw is split by policy, but applyDelegations is across all policies - the functions are split in this way too:
    depositUndelegatedGohm(onBehalfOf, amount)
    withdrawUndelegatedGohm(onBehalfOf, amount)
    applyDelegations(onBehalfOf, delegationRequests)

3/ The lowest number of delegates an account can be set to is 1 (if zero, it will be reset to the default of 10)

4/ I didn't add (more) state to get the set of all delegates. Can rely on subgraph to get that imo.
  BUT do we need onchain state for these?
    a/ Total delegated + undelegated gOHM across all policies and accounts (ie grand total)?
    b/ Total delegated + undelegated gOHM per policy?

  Tradeoff for user tx gas cost vs utility.

5/ There's also no current way to get the list of delegates/accounts for a given policy (on-chain), so would again be relying on subgraph.
  Is this ok or do you think we need anything specific here (at the cost of more gas)?
*/

/**
 * @title  Olympus Governance Delegation
 * @notice Olympus Governance Delegation (Module) Contract
 * @dev    The Olympus Governance Delegation Module enables policies to delegate gOHM on behalf of users.
 *         If the gOHM is undelegated, this module acts as an escrow for the gOHM.
 *         When the gOHM is delegated, new individual escrows are created for those delegates, and that
 *         portion of gOHM is transferred to that escrow.
 *         gOHM balances are tracked per (policy, account) separately such that one policy cannot pull the
 *         gOHM from another policy (eg policy B pulling collateral out of the Cooler policy).
 */
contract OlympusGovDelegation is DLGTEv1 {
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeTransferLib for ERC20;

    struct AccountState {
        /// @dev A regular account is allowed to delegate up to 10 different addresses.
        /// The account may be whitelisted to delegate more than that.
        EnumerableSet.AddressSet delegateAddresses;
        /// @dev The total gOHM undelegated and delegated gOHM for this account across all delegates.
        uint112 totalGOhm;
        /// @dev The total gOhm delegated for this account across all delegates
        uint112 delegatedGOhm;
        /// @dev By default an account can only delegate to 10 addresses.
        /// This may be increased on a per account basis by governance.
        uint32 maxDelegateAddresses;
    }

    DelegateEscrowFactory public immutable delegateEscrowFactory;

    /// @dev The mapping of a delegate's address to their escrow contract
    // mapping(address /*delegate*/ => DelegateEscrow /*delegateEscrow*/) private _delegateEscrows;

    /**
     * @dev An account's current state across all policies
     * A given account is allowed up to 10 delegates. This is capped because to avoid gas griefing,
     * eg within Cooler, upon a liquidation, the gOHM needs to be pulled from all delegates.
     */
    mapping(address /*account*/ => AccountState /*delegations*/) private _accountState;

    /**
     * @dev The per policy balances of (delegated and undelegated) gOHM for each end user account
     * One policy isn't allowed to deposit/withdraw to another policy's tracked balances
     * Eg policy B cannot withdraw gOHM from the collateral held here by the Cooler policy
     */
    mapping(address /*policy*/ => mapping(address /*account*/ => uint256 /*totalGOhm*/))
        private _policyAccountBalances;

    //============================================================================================//
    //                                      MODULE SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        address gohm_,
        DelegateEscrowFactory delegateEscrowFactory_
    ) Module(kernel_) DLGTEv1(gohm_) {
        delegateEscrowFactory = delegateEscrowFactory_;
    }

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("DLGTE");
    }

    /// @inheritdoc Module
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    function depositUndelegatedGohm(
        address onBehalfOf,
        uint256 amount
    ) external override permissioned {
        if (onBehalfOf == address(0)) revert DLGTE_InvalidAddress();
        if (amount == 0) revert DLGTE_InvalidAmount();

        // Update state
        mapping(address => uint256) storage policyBalances = _policyAccountBalances[msg.sender];
        policyBalances[onBehalfOf] += amount;

        AccountState storage aState = _accountState[onBehalfOf];
        aState.totalGOhm += amount.encodeUInt112();

        // Pull gOHM from the calling policy
        gOHM.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawUndelegatedGohm(
        address onBehalfOf,
        uint256 amount
    ) external override permissioned {
        if (onBehalfOf == address(0)) revert DLGTE_InvalidAddress();
        if (amount == 0) revert DLGTE_InvalidAmount();

        mapping(address => uint256) storage policyBalances = _policyAccountBalances[msg.sender];
        uint256 policyAccountBalance = policyBalances[onBehalfOf];
        if (amount > policyAccountBalance)
            revert DLGTE_ExceededPolicyAccountBalance(policyAccountBalance, amount);

        AccountState storage aState = _accountState[onBehalfOf];
        uint256 accountTotalBalance = aState.totalGOhm;
        uint256 accountUndelegatedBalance = accountTotalBalance - aState.delegatedGOhm;
        if (amount > accountUndelegatedBalance)
            revert DLGTE_ExceededUndelegatedBalance(accountUndelegatedBalance, amount);

        // Update state
        policyBalances[onBehalfOf] = policyAccountBalance - amount;
        aState.totalGOhm = (accountTotalBalance - amount).encodeUInt112();

        // Send the gOHM
        gOHM.safeTransfer(msg.sender, amount);
    }

    /// @inheritdoc DLGTEv1
    function applyDelegations(
        address onBehalfOf,
        DLGTEv1.DelegationRequest[] calldata delegationRequests
    )
        external
        override
        permissioned
        returns (
            uint256 appliedDelegationAmounts, 
            uint256 appliedUndelegationAmounts,
            uint256 undelegatedBalance
        )
    {
        if (onBehalfOf == address(0)) revert DLGTE_InvalidAddress();
        if (delegationRequests.length == 0) revert DLGTE_InvalidDelegationRequests();

        AccountState storage aState = _accountState[onBehalfOf];
        uint256 totalAccountGOhm = aState.totalGOhm;
        undelegatedBalance = totalAccountGOhm - aState.delegatedGOhm;

        (
            appliedDelegationAmounts,
            appliedUndelegationAmounts,
            undelegatedBalance
        ) = _applyDelegations(onBehalfOf, aState, undelegatedBalance, delegationRequests);

        // Update state for the delegated amount of gOHM for this account
        aState.delegatedGOhm = (totalAccountGOhm - undelegatedBalance).encodeUInt112();
    }

    /// @inheritdoc DLGTEv1
    function setMaxDelegateAddresses(
        address account,
        uint32 maxDelegates
    ) external override permissioned {
        emit MaxDelegateAddressesSet(account, maxDelegates);
        _accountState[account].maxDelegateAddresses = maxDelegates;
    }

    //============================================================================================//
    //                                      VIEW FUNCTIONS                                        //
    //============================================================================================//

    /// @inheritdoc DLGTEv1
    function policyAccountBalances(
        address policy,
        address account
    ) external view override returns (uint256 gOhmBalance) {
        return _policyAccountBalances[policy][account];
    }

    /// @inheritdoc DLGTEv1
    function accountDelegationsList(
        address account,
        uint256 startIndex,
        uint256 maxItems
    ) external view override returns (DLGTEv1.AccountDelegation[] memory delegations) {
        AccountState storage aState = _accountState[account];
        EnumerableSet.AddressSet storage acctDelegateAddresses = aState.delegateAddresses;

        // No items if either maxItems is zero or there are no delegate addresses.
        if (maxItems == 0) return new AccountDelegation[](0);
        uint256 length = acctDelegateAddresses.length();
        if (length == 0) return new AccountDelegation[](0);

        // No items if startIndex is greater than the max array index
        if (startIndex >= length) return new AccountDelegation[](0);

        // end index is the max of the requested items or the length
        uint256 requestedEndIndex = startIndex + maxItems - 1;
        uint256 maxPossibleEndIndex = length - startIndex - 1;
        if (maxPossibleEndIndex < requestedEndIndex) requestedEndIndex = maxPossibleEndIndex;

        delegations = new AccountDelegation[](requestedEndIndex - startIndex + 1);
        DelegateEscrow escrow;
        AccountDelegation memory delegateInfo;
        for (uint256 i = startIndex; i <= requestedEndIndex; ++i) {
            delegateInfo = delegations[i];
            delegateInfo.delegate = acctDelegateAddresses.at(i);
            escrow = delegateEscrowFactory.escrowFor(delegateInfo.delegate);
            delegateInfo.escrow = address(escrow);

            // Note the amount here is the amount for this account over *all* policies
            delegateInfo.totalAmount = escrow.delegations(address(this), account);
        }
    }

    /// @inheritdoc DLGTEv1
    function accountDelegationSummary(
        address account
    )
        external
        view
        override
        returns (
            uint256 /*totalGOhm*/,
            uint256 /*delegatedGOhm*/,
            uint256 /*numDelegateAddresses*/,
            uint256 /*maxAllowedDelegateAddresses*/
        )
    {
        AccountState storage aState = _accountState[account];
        uint32 maxDelegates = aState.maxDelegateAddresses;
        if (maxDelegates == 0) maxDelegates = DEFAULT_MAX_DELEGATE_ADDRESSES;
        return (
            aState.totalGOhm,
            aState.delegatedGOhm,
            aState.delegateAddresses.length(),
            maxDelegates
        );
    }

    /// @inheritdoc DLGTEv1
    function maxDelegateAddresses(address account) external view override returns (uint32 result) {
        result = _accountState[account].maxDelegateAddresses;
        if (result == 0) result = DEFAULT_MAX_DELEGATE_ADDRESSES;
    }

    //============================================================================================//
    //                                    INTERNAL FUNCTIONS                                      //
    //============================================================================================//

    function _applyDelegations(
        address onBehalfOf,
        AccountState storage aState,
        uint256 undelegatedBalance,
        DLGTEv1.DelegationRequest[] calldata delegationRequests
    )
        private
        returns (
            uint256 appliedDelegationAmounts,
            uint256 appliedUndelegationAmounts,
            uint256 newUndelegatedBalance
        )
    {
        uint32 maxDelegates = _maxDelegateAddresses(aState);
        EnumerableSet.AddressSet storage acctDelegateAddresses = aState.delegateAddresses;

        uint256 length = delegationRequests.length;
        uint256 currentDelegatedAmount;
        uint256 currentUndelegatedAmount;
        newUndelegatedBalance = undelegatedBalance;
        for (uint256 i; i < length; ++i) {
            (currentDelegatedAmount, currentUndelegatedAmount) = _applyDelegation(
                onBehalfOf,
                newUndelegatedBalance,
                maxDelegates,
                acctDelegateAddresses,
                delegationRequests[i]
            );

            appliedDelegationAmounts += currentDelegatedAmount;
            appliedUndelegationAmounts += currentUndelegatedAmount;
            newUndelegatedBalance =
                newUndelegatedBalance +
                currentUndelegatedAmount -
                currentDelegatedAmount;
        }
    }

    // If this is the first delegation, set to the default.
    // NB: This means the lowest number of delegate addresses an account can have after
    // whitelisting is 1 (since if it's set to zero, it will reset to the default)
    function _maxDelegateAddresses(
        AccountState storage aState
    ) private returns (uint32 maxDelegates) {
        maxDelegates = aState.maxDelegateAddresses;
        if (maxDelegates == 0) {
            aState.maxDelegateAddresses = maxDelegates = DEFAULT_MAX_DELEGATE_ADDRESSES;
        }
    }

    function _applyDelegation(
        address onBehalfOf,
        uint256 undelegatedBalance,
        uint32 maxDelegates,
        EnumerableSet.AddressSet storage acctDelegateAddresses,
        DLGTEv1.DelegationRequest calldata delegationRequest
    ) private returns (uint256 delegatedAmount, uint256 undelegatedAmount) {
        if (delegationRequest.delegate == address(0)) revert DLGTE_InvalidAddress();

        // Special case to delegate all remaining (undelegated) gOhm.
        int256 delegatedDelta = delegationRequest.amount == type(int256).max
            ? int256(undelegatedBalance)
            : delegationRequest.amount;
        if (delegatedDelta == 0) revert DLGTE_InvalidAmount();

        // If the amount is positive, it is adding to the delegation
        if (delegationRequest.amount > 0) {
            delegatedAmount = uint256(delegatedDelta);

            // Ensure the account isn't delegating more than the undelegated balance
            if (delegatedAmount > undelegatedBalance) {
                revert DLGTE_ExceededUndelegatedBalance(undelegatedBalance, delegatedAmount);
            }

            DelegateEscrow delegateEscrow = _getOrCreateDelegateEscrow(
                delegationRequest.delegate,
                acctDelegateAddresses,
                maxDelegates
            );

            // Push gOhm to the new escrow
            gOHM.safeApprove(address(delegateEscrow), delegatedAmount);
            delegateEscrow.delegate(onBehalfOf, delegatedAmount);
        } else {
            // Otherwise if the amount is negative, is is undelegating
            undelegatedAmount = uint256(delegatedDelta * -1);

            DelegateEscrow delegateEscrow = delegateEscrowFactory.escrowFor(
                delegationRequest.delegate
            );
            if (address(delegateEscrow) == address(0)) revert DLGTE_InvalidDelegateEscrow();

            // Pull gOhm from the escrow
            // And remove from acctDelegateAddresses if it's now empty
            uint256 delegatedBalance = delegateEscrow.rescindDelegation(
                onBehalfOf,
                undelegatedAmount
            );
            if (delegatedBalance == 0) {
                acctDelegateAddresses.remove(delegationRequest.delegate);
            }
        }

        emit DelegationApplied(onBehalfOf, delegationRequest.delegate, delegatedDelta);
    }

    function _getOrCreateDelegateEscrow(
        address delegate,
        EnumerableSet.AddressSet storage acctDelegateAddresses,
        uint128 maxDelegates
    ) private returns (DelegateEscrow delegateEscrow) {
        delegateEscrow = delegateEscrowFactory.create(delegate);

        // Ensure it's added to this user's set of delegate addresses
        if (acctDelegateAddresses.add(delegate)) {
            // A given account cannot have more than the permissable number of delegates
            if (acctDelegateAddresses.length() > maxDelegates) revert DLGTE_TooManyDelegates();
        }
    }
}
