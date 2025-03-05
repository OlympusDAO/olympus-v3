// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {EnumerableMap} from "openzeppelin/utils/structs/EnumerableMap.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Kernel, Module, Keycode, toKeycode} from "src/Kernel.sol";
import {IDLGTEv1} from "modules/DLGTE/IDLGTE.v1.sol";
import {DLGTEv1} from "modules/DLGTE/DLGTE.v1.sol";
import {DelegateEscrow} from "src/external/cooler/DelegateEscrow.sol";
import {DelegateEscrowFactory} from "src/external/cooler/DelegateEscrowFactory.sol";
import {SafeCast} from "libraries/SafeCast.sol";

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
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using SafeTransferLib for ERC20;

    struct AccountState {
        /// @dev A regular account is allowed to delegate up to 10 different addresses.
        /// The account may be whitelisted to delegate more than that.
        EnumerableMap.AddressToUintMap delegatedAmounts;
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
        _gOHM.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawUndelegatedGohm(
        address onBehalfOf,
        uint256 amount,
        bool autoRescindDelegations
    ) external override permissioned {
        if (onBehalfOf == address(0)) revert DLGTE_InvalidAddress();
        if (amount == 0) revert DLGTE_InvalidAmount();
        AccountState storage aState = _accountState[onBehalfOf];
        uint256 totalAccountGOhm = aState.totalGOhm;

        if (autoRescindDelegations) {
            // Don't need to handle the case where it didn't rescind enough
            // As it will just fail with DLGTE_ExceededUndelegatedBalance below.
            _autoRescindDelegations(onBehalfOf, amount, aState, totalAccountGOhm);
        }

        mapping(address => uint256) storage policyBalances = _policyAccountBalances[msg.sender];
        uint256 policyAccountBalance = policyBalances[onBehalfOf];
        if (amount > policyAccountBalance)
            revert DLGTE_ExceededPolicyAccountBalance(policyAccountBalance, amount);

        uint256 accountUndelegatedBalance = totalAccountGOhm - aState.delegatedGOhm;
        if (amount > accountUndelegatedBalance)
            revert DLGTE_ExceededUndelegatedBalance(accountUndelegatedBalance, amount);

        // Update state
        policyBalances[onBehalfOf] = policyAccountBalance - amount;
        aState.totalGOhm = (totalAccountGOhm - amount).encodeUInt112();

        // Send the gOHM
        _gOHM.safeTransfer(msg.sender, amount);
    }

    /// @inheritdoc DLGTEv1
    function rescindDelegations(
        address onBehalfOf,
        uint256 requestedUndelegatedBalance
    ) external override permissioned returns (uint256 actualUndelegatedBalance) {
        if (onBehalfOf == address(0)) revert DLGTE_InvalidAddress();
        AccountState storage aState = _accountState[onBehalfOf];
        return
            _autoRescindDelegations(
                onBehalfOf,
                requestedUndelegatedBalance,
                aState,
                aState.totalGOhm
            );
    }

    /// @inheritdoc DLGTEv1
    function applyDelegations(
        address onBehalfOf,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
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
    ) external view override returns (IDLGTEv1.AccountDelegation[] memory delegations) {
        AccountState storage aState = _accountState[account];
        EnumerableMap.AddressToUintMap storage acctDelegatedAmounts = aState.delegatedAmounts;

        // No items if either maxItems is zero or there are no delegate addresses.
        if (maxItems == 0) return new AccountDelegation[](0);
        uint256 length = acctDelegatedAmounts.length();
        if (length == 0) return new AccountDelegation[](0);

        // No items if startIndex is greater than the max array index
        if (startIndex >= length) return new AccountDelegation[](0);

        // end index is the max of the requested items or the length
        uint256 requestedEndIndex = startIndex + maxItems - 1;
        uint256 maxPossibleEndIndex = length - 1;
        if (maxPossibleEndIndex < requestedEndIndex) requestedEndIndex = maxPossibleEndIndex;

        uint256 numDelegations = requestedEndIndex - startIndex + 1;
        delegations = new AccountDelegation[](numDelegations);
        DelegateEscrow escrow;
        AccountDelegation memory delegateInfo;
        for (uint256 i; i < numDelegations; ++i) {
            delegateInfo = delegations[i];
            (delegateInfo.delegate, delegateInfo.amount) = acctDelegatedAmounts.at(i + startIndex);
            escrow = delegateEscrowFactory.escrowFor(delegateInfo.delegate);
            delegateInfo.escrow = address(escrow);
        }
    }

    /// @inheritdoc DLGTEv1
    function totalDelegatedTo(address delegate) external view override returns (uint256) {
        DelegateEscrow escrow = delegateEscrowFactory.escrowFor(delegate);
        return address(escrow) == address(0) ? 0 : escrow.totalDelegated();
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
            aState.delegatedAmounts.length(),
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
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    )
        private
        returns (
            uint256 appliedDelegationAmounts,
            uint256 appliedUndelegationAmounts,
            uint256 newUndelegatedBalance
        )
    {
        uint32 maxDelegates = _maxDelegateAddresses(aState);
        EnumerableMap.AddressToUintMap storage acctDelegatedAmounts = aState.delegatedAmounts;

        uint256 length = delegationRequests.length;
        uint256 currentDelegatedAmount;
        uint256 currentUndelegatedAmount;
        newUndelegatedBalance = undelegatedBalance;
        for (uint256 i; i < length; ++i) {
            (currentDelegatedAmount, currentUndelegatedAmount) = _applyDelegation(
                onBehalfOf,
                newUndelegatedBalance,
                maxDelegates,
                acctDelegatedAmounts,
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
        EnumerableMap.AddressToUintMap storage acctDelegatedAmounts,
        IDLGTEv1.DelegationRequest calldata delegationRequest
    ) private returns (uint256 delegatedAmount, uint256 undelegatedAmount) {
        if (delegationRequest.delegate == address(0)) revert DLGTE_InvalidAddress();

        // If the amount is positive, it is add a delegation
        // negative will rescind the delegation
        if (delegationRequest.amount >= 0) {
            // Special case to delegate all remaining (undelegated) gOhm.
            delegatedAmount = delegationRequest.amount == type(int256).max
                ? undelegatedBalance
                : uint256(delegationRequest.amount);
            if (delegatedAmount == 0) revert DLGTE_InvalidAmount();

            // Ensure the account isn't delegating more than the undelegated balance
            if (delegatedAmount > undelegatedBalance) {
                revert DLGTE_ExceededUndelegatedBalance(undelegatedBalance, delegatedAmount);
            }

            _addDelegation(
                onBehalfOf,
                delegationRequest.delegate,
                delegatedAmount,
                acctDelegatedAmounts,
                maxDelegates
            );
        } else {
            // Revert with a custom error if trying to rescind and there's no record of this delegation.
            (bool exists, uint256 delegatedBalance) = acctDelegatedAmounts.tryGet(
                delegationRequest.delegate
            );
            if (!exists) revert DLGTE_InvalidDelegateEscrow();

            // Special case to undelegate all remaining (delegated) gOhm.
            undelegatedAmount = delegationRequest.amount == type(int256).min
                ? delegatedBalance
                : uint256(-delegationRequest.amount);
            if (undelegatedAmount == 0) revert DLGTE_InvalidAmount();

            // Ensure the account isn't trying to undelegate more than the recorded amount
            if (undelegatedAmount > delegatedBalance) {
                revert DLGTE_ExceededDelegatedBalance(
                    delegationRequest.delegate,
                    delegatedBalance,
                    undelegatedAmount
                );
            }

            _rescindDelegation(
                onBehalfOf,
                delegationRequest.delegate,
                delegatedBalance,
                undelegatedAmount,
                acctDelegatedAmounts
            );
        }
    }

    function _addDelegation(
        address onBehalfOf,
        address delegate,
        uint256 delegatedAmount,
        EnumerableMap.AddressToUintMap storage acctDelegatedAmounts,
        uint32 maxDelegates
    ) private {
        // Check the maxDelegates if this is a new delegation record for the `onBehalfOf`
        (bool alreadyExisted, uint256 existingAmount) = acctDelegatedAmounts.tryGet(delegate);
        if (!alreadyExisted && acctDelegatedAmounts.length() >= maxDelegates) {
            revert DLGTE_TooManyDelegates();
        }

        // Increase the delegation record amount
        acctDelegatedAmounts.set(delegate, existingAmount + delegatedAmount);

        // Delegate gOhm to the new escrow.
        DelegateEscrow delegateEscrow = delegateEscrowFactory.create(delegate);
        _gOHM.safeApprove(address(delegateEscrow), delegatedAmount);
        delegateEscrow.delegate(onBehalfOf, delegatedAmount);
        emit DelegationApplied(onBehalfOf, delegate, int256(delegatedAmount));
    }

    function _autoRescindDelegations(
        address onBehalfOf,
        uint256 requestedUndelegatedBalance,
        AccountState storage aState,
        uint256 totalAccountGOhm
    ) private returns (uint256 actualUndelegatedBalance) {
        actualUndelegatedBalance = totalAccountGOhm - aState.delegatedGOhm;

        // Nothing to do if the undelegated balance is already greater than the requested amount
        if (actualUndelegatedBalance >= requestedUndelegatedBalance)
            return actualUndelegatedBalance;

        // EnumerableMap internals are used here for gas efficiency.
        // Deleting keys from the EnumerableMap changes the order (swap and pop) and size
        // So take an upfront in-memory copy of the delegateAddrs keys to iterate over first.
        EnumerableMap.AddressToUintMap storage acctDelegatedAmounts = aState.delegatedAmounts;
        bytes32[] memory delegateAddrs = acctDelegatedAmounts._inner._keys._inner._values;
        bytes32 delegateAddr;
        uint256 delegatedBalance;
        uint256 rescindAmount;
        for (uint256 i; i < delegateAddrs.length; ++i) {
            delegateAddr = delegateAddrs[i];
            delegatedBalance = uint256(acctDelegatedAmounts._inner._values[delegateAddr]);

            // Cap the amount to rescind for this delegate by the remaining required to get to the
            // requested undelegated balance
            rescindAmount = requestedUndelegatedBalance - actualUndelegatedBalance;
            rescindAmount = delegatedBalance < rescindAmount ? delegatedBalance : rescindAmount;

            _rescindDelegation(
                onBehalfOf,
                address(uint160(uint256(delegateAddr))),
                delegatedBalance,
                rescindAmount,
                acctDelegatedAmounts
            );

            actualUndelegatedBalance += rescindAmount;

            // Reached the requested undelegated balance
            if (actualUndelegatedBalance == requestedUndelegatedBalance) break;
        }

        // Update state for the delegated amount of gOHM for this account
        aState.delegatedGOhm = (totalAccountGOhm - actualUndelegatedBalance).encodeUInt112();

        // May not have undelegated the full requested amount - left up to the calling policy on how to handle this gap
        return actualUndelegatedBalance;
    }

    function _rescindDelegation(
        address onBehalfOf,
        address delegate,
        uint256 delegatedBalance,
        uint256 rescindAmount,
        EnumerableMap.AddressToUintMap storage acctDelegatedAmounts
    ) private {
        // Rescind the delegation from the escrow
        DelegateEscrow delegateEscrow = delegateEscrowFactory.create(delegate);
        delegateEscrow.rescindDelegation(onBehalfOf, rescindAmount);
        emit DelegationApplied(onBehalfOf, delegate, -int256(rescindAmount));

        // Decrease the delegation record amount.
        // Remove if that is now zero such that it doesn't count towards the `maxDelegates` cap
        delegatedBalance -= rescindAmount;
        if (delegatedBalance == 0) {
            acctDelegatedAmounts.remove(delegate);
        } else {
            acctDelegatedAmounts.set(delegate, delegatedBalance);
        }
    }
}
