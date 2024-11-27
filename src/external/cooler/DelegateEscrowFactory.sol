// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ClonesWithImmutableArgs} from "clones/ClonesWithImmutableArgs.sol";
import {DelegateEscrow} from "src/external/cooler/DelegateEscrow.sol";

/// @title  Delegate Escrow Factory.
/// @notice The Delegate Escrow Factory creates new escrow contracts, each holding the delegated
///         gOHM from other accounts
/// @dev    This contract uses Clones (https://github.com/wighawag/clones-with-immutable-args)
///         to save gas on deployment.
contract DelegateEscrowFactory {
    using ClonesWithImmutableArgs for address;

    // --- ERRORS ----------------------------------------------------

    error NotFromFactory();

    // --- EVENTS ----------------------------------------------------

    /// @notice A caller has created a new escrow for a delegate
    event DelegateEscrowCreated(
        address indexed caller,
        address indexed delegate,
        address indexed escrow
    );

    /// @notice A `caller` has (un)delegated their gOHM amount from `escrow` on behalf of a user
    /// @dev
    ///      delegationAmountDelta > 0: It has been delegated to this escrow
    ///      delegationAmountDelta < 0: It has been undelegated from this escrow
    event Delegate(
        address indexed escrow,
        address indexed caller,
        address indexed onBehalfOf,
        int256 delegationAmountDelta
    );

    // -- STATE VARIABLES --------------------------------------------

    /// @notice Reference implementation (deployed on creation to clone from).
    DelegateEscrow public immutable escrowImplementation;

    /// @notice Mapping to validate deployed escrows.
    mapping(address => bool) public created;

    /// @notice Mapping to query escrows for a given delegate.
    mapping(address => DelegateEscrow) public escrowFor;

    // --- INITIALIZATION --------------------------------------------

    constructor(address gohm_) {
        escrowImplementation = new DelegateEscrow(gohm_);
    }

    // --- DEPLOY NEW COOLERS ----------------------------------------

    /// @notice creates a new escrow contract for a delegate.
    function create(address delegate) external returns (DelegateEscrow escrow) {
        escrow = escrowFor[delegate];

        // If not found, generate a new escrow
        if (address(escrow) == address(0)) {
            // Clone the escrow implementation.
            bytes memory escrowData = abi.encodePacked(
                delegate,
                address(this) // factory
            );
            escrow = DelegateEscrow(address(escrowImplementation).clone(escrowData));
            escrow.initialize();
            emit DelegateEscrowCreated(msg.sender, delegate, address(escrow));

            // Update storage accordingly.
            escrowFor[delegate] = escrow;
            created[address(escrow)] = true;
        }
    }

    // --- EMIT EVENTS -----------------------------------------------

    /// @notice Ensure that the called is a Cooler.
    modifier onlyFromFactory() {
        if (!created[msg.sender]) revert NotFromFactory();
        _;
    }

    /// @notice Emit a global event when a new loan request is created.
    function logDelegate(
        address caller,
        address onBehalfOf,
        int256 delegationAmountDelta
    ) external onlyFromFactory {
        emit Delegate(msg.sender, caller, onBehalfOf, delegationAmountDelta);
    }
}
