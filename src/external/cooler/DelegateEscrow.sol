// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// Function sig taken from gOHM contract
interface IDelegate {
    function delegate(address to_) external;
}

/*
@todo considerations - up for discussion:

- This was made intentionally permisionless. 
- The accounting for who provided the delegation is partitioned by the contract which calls delegate(), such that only they can resindDelegation()
- Which means this same delegate escrow address could be used by other things within the ecosystem.
- The delegate can't control the gohm or change their delegation to another address. But perhaps that should be allowed?
- Any donations (gOHM or any other token) aren't recoverable. 
- If an incorrect delegate account is chosen, the user (via cooler v2) can rescindDelegation to pull that gOHM back.
- If cooler v2 winds down, it will have to rescindDelegation() for each user first (to pull back gOHM).

*/

/**
 * @title Delegate Escrow Account
 * @notice An escrow to hold gOHM and delegate that amount to exactly one account.
 * @dev Any caller (eg MonoCooler) can delegate on behalf of a `delegator` address, but only that same caller
 * can rescind the delegation to pull the gOHM back.
 */
contract DelegateEscrow {
    using SafeTransferLib for ERC20;

    ERC20 public immutable gohm;

    address public immutable delegateAccount;

    error ExceededDelegationBalance();

    event Delegate(address indexed caller, address indexed onBehalfOf, int256 delegationAmountDelta);

    /// @notice The mapping of delegation amounts. 
    /// @dev Partitioned by the calling address, and also by
    /// the address on behalf it is delegating for.
    mapping(address /* caller */ => 
        mapping(address /* onBehalfOf */ => uint256 /* amount */)
    ) public delegations;

    constructor(address gohm_, address delegateAccount_) {
        gohm = ERC20(gohm_);
        delegateAccount = delegateAccount_;
        IDelegate(gohm_).delegate(delegateAccount_);
    }

    /// @notice Delegate an amount of gOHM to the predefined `delegateAccount`
    /// @dev gOHM is pulled from the caller (which must provide allowance), and only that 
    /// same caller may rescind the delegation to recall the gOHM at a future date.
    function delegate(address onBehalfOf, uint256 gohmAmount) external returns (uint256 delegatedAmount) {
        gohm.safeTransferFrom(msg.sender, address(this), gohmAmount);

        mapping(address => uint256) storage delegatorAmounts = delegations[msg.sender];
        delegatorAmounts[onBehalfOf] = delegatedAmount = delegatorAmounts[onBehalfOf] + gohmAmount;

        emit Delegate(msg.sender, onBehalfOf, int256(gohmAmount));
    }

    /// @notice Rescind a delegation of gOHM and send back to the caller.
    function rescindDelegation(address onBehalfOf, uint256 gohmAmount) external returns (uint256 delegatedAmount) {
        mapping(address => uint256) storage delegatorAmounts = delegations[msg.sender];
        uint256 existingDelegatedAmount = delegatorAmounts[onBehalfOf];
        if (gohmAmount > existingDelegatedAmount) revert ExceededDelegationBalance();

        delegatorAmounts[onBehalfOf] = delegatedAmount = existingDelegatedAmount - gohmAmount;
        gohm.safeTransfer(msg.sender, gohmAmount);

        emit Delegate(msg.sender, onBehalfOf, -int256(gohmAmount));
    }
}
