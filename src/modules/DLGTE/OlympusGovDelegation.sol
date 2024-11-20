// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {DLGTEv1} from "modules/DLGTE/DLGTE.v1.sol";
import {EnumerableSet} from "openzeppelin/utils/structs/EnumerableSet.sol";
import {DelegateEscrow} from "src/external/cooler/DelegateEscrow.sol";
import {SafeCast} from "libraries/SafeCast.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Kernel, Module, Keycode, toKeycode} from "src/Kernel.sol";

/*
@todo considerations - up for discussion:

- It's NOT possible for policy A to delegate and use the gOHM added in policy B (eg cooler)
   It could be dangerous if policy A utilises the gOHM - as that could be collateral that needs to be used in a
   liquidation event.
  regardless of permissions - since it uses msg.sender rather than passed in parameter for the policy
- applyDelegations() takes a signed int256 representing whether it's
     - positive: net ADDING new gOHM to delegate (eg cooler add collateral)
     - negative: net REMOVING gOHM from delegations (eg cooler withdraw collateral)
     - zero:     net no change - just updating delegations (undelegated -> delegate.A, delegate.A -> delegate.B)
   I like this style rather than many functions that are basically the same thing, but open for opinions.
- The lowest number of delegates an account can be set to is 1 (if zero, it will be reset to the default of 10)
- I didn't add (more) state to get the set of all delegates. Can rely on subgraph to get that imo.
  BUT:
   - Should we track state for total delegated + undelegated gOHM across all policies and accounts (ie grand total)?
   - Should we track state for total delegated + undelegated gOHM across per policy?
- There's also no way to get the list of delegates or accounts for a given policy. Anything here required?
*/

/// @title  Olympus Governance Delegation
/// @notice Olympus Governance Delegation (Module) Contract
/// @dev    The Olympus Governance Delegation Module enables policies to delegate gOHM on behalf
///         of users. 
///         If the gOHM is undelegated, this module acts as an escrow for the gOHM.
///         When the gOHM is delegated, new individual escrows are created for those delegates, and that
///         portion of gOHM is transferred to that escrow.
///         Account state is tracked per (policy, account) separately such that one policy cannot pull the 
///         gOHM from another policy (eg policy B pulling collateral out of the Cooler policy).
contract OlympusGovDelegation is DLGTEv1 {
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeTransferLib for ERC20;

    /// @dev The mapping of delegate address to their escrow contract state
    mapping(address /*delegate*/ => DelegateEscrow /*delegateEscrow*/) private delegateEscrows;

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

    /**
     * @dev Mapping a (policy, account) tuple to the current state.
     * It is intentionally segregated per policy such that one policy cannot apply delegations
     * on behalf of another policy (eg policy.B taking gOHM collateral out of the Cooler policy)
     * A given account is allowed up to 10 delegates. This is capped because to avoid gas griefing,
     * eg within Cooler, upon a liquidation, the gOHM needs to be pulled from all delegates.
     */
    mapping(address /*policy*/ => 
        mapping(address /*account*/ => AccountState /*delegations*/)
    ) private _accountState;
    
    //============================================================================================//
    //                                      MODULE SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_, address gohm_) Module(kernel_) DLGTEv1(gohm_) {}

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("DLGTE");
    }

    /// @inheritdoc Module
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    /// @inheritdoc DLGTEv1
    function applyDelegations(
        address onBehalfOf,
        int256 gOhmDelta,
        DLGTEv1.DelegationRequest[] calldata delegationRequests,
        DLGTEv1.AllowedDelegationRequests allowedRequests
    ) external override permissioned returns (
        uint256 totalDelegated
    ) {
        if (onBehalfOf == address(0)) revert DLGTE_InvalidAddress();

        AccountState storage aState = _accountState[msg.sender][onBehalfOf];
        uint112 totalAccountGOhm = aState.totalGOhm;

        // Pull gOHM from the caller
        if (gOhmDelta > 0) {
            emit TransferredGohm(msg.sender, onBehalfOf, gOhmDelta);
            uint256 gOhmToPull = uint256(gOhmDelta);
            gOHM.safeTransferFrom(msg.sender, address(this), gOhmToPull);
            totalAccountGOhm += gOhmToPull.encodeUInt112();
        }

        // Apply any delegations
        if (delegationRequests.length > 0) {
            uint32 maxDelegates = _maxDelegateAddresses(aState);
            totalDelegated = _applyDelegations(
                onBehalfOf, 
                aState, 
                totalAccountGOhm,
                maxDelegates,
                delegationRequests,
                allowedRequests
            );
        }

        // Return gOHM to the caller
        if (gOhmDelta < 0) {
            uint256 gOhmToReturn = uint256(gOhmDelta * -1);
            uint256 totalUndelegated = totalAccountGOhm - totalDelegated;
            if (gOhmToReturn > totalUndelegated) revert DLGTE_ExceededGOhmBalance(totalUndelegated, gOhmToReturn);

            unchecked {
                totalAccountGOhm -= gOhmToReturn.encodeUInt112();
            }

            emit TransferredGohm(msg.sender, onBehalfOf, gOhmDelta);
            gOHM.safeTransfer(msg.sender, gOhmToReturn);
        }

        aState.totalGOhm = totalAccountGOhm;
    }

    /// @inheritdoc DLGTEv1
    function setMaxDelegateAddresses(
        address account, 
        uint32 maxDelegates
    ) external override permissioned {
        emit MaxDelegateAddressesSet(msg.sender, account, maxDelegates);
        _accountState[msg.sender][account].maxDelegateAddresses = maxDelegates;
    }
    
    /// @inheritdoc DLGTEv1
    function accountDelegationsList(
        address policy,
        address account, 
        uint256 startIndex, 
        uint256 maxItems
    ) external override view returns (
        DLGTEv1.AccountDelegation[] memory delegations
    ) {
        AccountState storage aState = _accountState[policy][account];
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

        delegations = new AccountDelegation[](requestedEndIndex-startIndex+1);
        DelegateEscrow escrow;
        AccountDelegation memory delegateInfo;
        for (uint256 i = startIndex; i <= requestedEndIndex; ++i) {
            delegateInfo = delegations[i];
            delegateInfo.delegate = acctDelegateAddresses.at(i);
            escrow = delegateEscrows[delegateInfo.delegate];
            delegateInfo.escrow = address(escrow);

            // Note the amount here is the amount for this account over *all* policies
            delegateInfo.totalAmount = escrow.delegations(address(this), account);
        }
    }

    /// @inheritdoc DLGTEv1
    function accountDelegationSummary(
        address policy, 
        address account
    ) external override view returns (
        uint256 /*totalGOhm*/,
        uint256 /*delegatedGOhm*/,
        uint256 /*numDelegateAddresses*/,
        uint256 /*maxAllowedDelegateAddresses*/
    ) {
        AccountState storage aState = _accountState[policy][account];
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
    function maxDelegateAddresses(
        address policy,
        address account
    ) external override view returns (uint32 result) {
        result = _accountState[policy][account].maxDelegateAddresses;
        if (result == 0) result = DEFAULT_MAX_DELEGATE_ADDRESSES;
    }

    // If this is the first delegation, set to the default.
    // NB: This means the lowest number of delegate addresses an account can have after
    // whitelisting is 1 (since if it's set to zero, it will reset to the default)
    function _maxDelegateAddresses(
        AccountState storage aState
    ) private returns (
        uint32 maxDelegates
    ) {
        maxDelegates = aState.maxDelegateAddresses;
        if (maxDelegates == 0) {
            aState.maxDelegateAddresses = maxDelegates = DEFAULT_MAX_DELEGATE_ADDRESSES;
        }
    }

    function _applyDelegations(
        address onBehalfOf, 
        AccountState storage aState,
        uint112 totalAccountGOhm,
        uint32 maxDelegates,
        DLGTEv1.DelegationRequest[] calldata delegationRequests,
        DLGTEv1.AllowedDelegationRequests allowedRequests
    ) private returns (uint112 totalDelegated) {
        EnumerableSet.AddressSet storage acctDelegateAddresses = aState.delegateAddresses;

        totalDelegated = aState.delegatedGOhm;
        uint256 length = delegationRequests.length;
        for (uint256 i; i < length; ++i) {
            totalDelegated = _applyDelegation(
                onBehalfOf, 
                totalAccountGOhm, 
                totalDelegated,
                maxDelegates,
                acctDelegateAddresses,
                delegationRequests[i],
                allowedRequests
            );
        }

        // Ensure the account hasn't delegated more than their actual gOhm balance.
        if (totalDelegated > totalAccountGOhm) {
            revert DLGTE_ExceededGOhmBalance(totalAccountGOhm, totalDelegated);
        }

        aState.delegatedGOhm = totalDelegated;
    }

    function _applyDelegation(
        address onBehalfOf,
        uint112 totalAccountGOhm,
        uint112 totalDelegated,
        uint32 maxDelegates,
        EnumerableSet.AddressSet storage acctDelegateAddresses,
        DLGTEv1.DelegationRequest calldata delegationRequest,
        DLGTEv1.AllowedDelegationRequests allowedRequests
    ) private returns (uint112 newTotalDelegated) {
        if (delegationRequest.fromDelegate == address(0) && delegationRequest.toDelegate == address(0)) {
            revert DLGTE_InvalidAddress();
        }
        if (delegationRequest.fromDelegate == delegationRequest.toDelegate) {
            revert DLGTE_InvalidAddress();
        }

        // Special case to delegate all remaining (undelegated) gOhm.
        uint112 gOhmAmount = delegationRequest.amount == type(uint256).max
            ? (totalAccountGOhm - totalDelegated)
            : delegationRequest.amount.encodeUInt112();
        if (gOhmAmount == 0) revert DLGTE_InvalidAmount();

        // Handle the fromDelegate
        newTotalDelegated = totalDelegated;
        DelegateEscrow delegateEscrow;
        if (delegationRequest.fromDelegate == address(0)) {
            newTotalDelegated += gOhmAmount;
        } else {
            delegateEscrow = delegateEscrows[delegationRequest.fromDelegate];
            if (address(delegateEscrow) == address(0)) revert DLGTE_InvalidDelegateEscrow();

            // Pull gOhm from the old escrow
            // And remove from acctDelegateAddresses if it's now empty
            uint256 delegatedBalance = delegateEscrow.rescindDelegation(onBehalfOf, gOhmAmount);
            if (delegatedBalance == 0) {
                acctDelegateAddresses.remove(delegationRequest.fromDelegate);
            }
        }
        
        // Handle the toDelegate
        if (delegationRequest.toDelegate == address(0)) {
            newTotalDelegated -= gOhmAmount;
        } else if (allowedRequests == DLGTEv1.AllowedDelegationRequests.RescindOnly) {
            revert DLGTE_CanOnlyRescindDelegation();
        } else {
            // Throw a nice error if there isn't enough gOhm balance
            uint256 gOhmBalance = gOHM.balanceOf(address(this));
            if (gOhmAmount > gOhmBalance)
                revert DLGTE_ExceededGOhmBalance(gOhmBalance, gOhmAmount);

            delegateEscrow = _getOrCreateDelegateEscrow(
                delegationRequest.toDelegate, 
                acctDelegateAddresses, 
                maxDelegates
            );

            // Push gOhm to the new escrow
            gOHM.safeApprove(address(delegateEscrow), gOhmAmount);
            delegateEscrow.delegate(onBehalfOf, gOhmAmount);
        }

        emit DelegationApplied(
            msg.sender,
            onBehalfOf,
            delegationRequest.fromDelegate, 
            delegationRequest.toDelegate, 
            gOhmAmount
        );
    }

    function _getOrCreateDelegateEscrow(
        address delegate, 
        EnumerableSet.AddressSet storage acctDelegateAddresses,
        uint128 maxDelegates
    ) private returns (DelegateEscrow delegateEscrow) {
        delegateEscrow = delegateEscrows[delegate];

        // Ensure it's added to this user's set of delegate addresses
        acctDelegateAddresses.add(delegate);
        
        if (address(delegateEscrow) == address(0)) {
            // create new escrow if the user has under the 10 cap
            if (acctDelegateAddresses.length() > maxDelegates) revert DLGTE_TooManyDelegates();

            // @todo clones factory required
            delegateEscrow = new DelegateEscrow(address(gOHM), delegate);

            delegateEscrows[delegate] = delegateEscrow;
            emit DelegateEscrowCreated(delegate, address(delegateEscrow));
        }
    }
}