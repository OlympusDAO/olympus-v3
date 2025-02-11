// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IDLGTEv1 {
    // =========  ERRORS ========= //

    error DLGTE_InvalidAddress();
    error DLGTE_InvalidDelegationRequests();
    error DLGTE_TooManyDelegates();
    error DLGTE_InvalidDelegateEscrow();
    error DLGTE_InvalidAmount();

    error DLGTE_ExceededUndelegatedBalance(uint256 balance, uint256 requested);
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
        /// @dev The DelegateEscrow contract address for this `delegate`
        address escrow;
        /// @dev The amount delegated to this delegate address
        uint256 totalAmount;
    }
}
