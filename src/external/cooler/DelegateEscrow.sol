// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IVotes} from "openzeppelin/governance/utils/IVotes.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Clone} from "clones/Clone.sol";
import {DelegateEscrowFactory} from "src/external/cooler/DelegateEscrowFactory.sol";

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
 * This contract uses Clones (https://github.com/wighawag/clones-with-immutable-args)
 * to save gas on deployment.
 */
contract DelegateEscrow is Clone {
    using SafeTransferLib for ERC20;

    /// @notice OHM governance token
    ERC20 public immutable gohm;

    /// @notice A caller cannot rescind a delegation for more the gOHM which was
    /// delegated.
    error ExceededDelegationBalance();

    /// @notice Can only be called from the factory which created this contract
    error NotFactory();

    /// @notice The mapping of delegation amounts. 
    /// @dev Partitioned by the calling address, and also by
    /// the address on behalf it is delegating for.
    mapping(address /* caller */ => 
        mapping(address /* onBehalfOf */ => uint256 /* amount */)
    ) public delegations;

    constructor(address gohm_) {
        gohm = ERC20(gohm_);
    }

    function initialize() external onlyFactory {
        IVotes(address(gohm)).delegate(delegateAccount());
    }

    /// @notice The delegate address of the gOHM collateral in this escrow
    function delegateAccount() public pure returns (address) {
        return _getArgAddress(0x0);
    }

    /// @notice The factory contract which created this escrow
    function factory() public pure returns (DelegateEscrowFactory _factory) {
        return DelegateEscrowFactory(_getArgAddress(0x14));
    }

    /// @notice Delegate an amount of gOHM to the predefined `delegateAccount`
    /// @dev gOHM is pulled from the caller (which must provide allowance), and only that 
    /// same caller may rescind the delegation to recall the gOHM at a future date.
    function delegate(address onBehalfOf, uint256 gohmAmount) external returns (uint256 delegatedAmount) {
        gohm.safeTransferFrom(msg.sender, address(this), gohmAmount);

        mapping(address => uint256) storage delegatorAmounts = delegations[msg.sender];
        delegatorAmounts[onBehalfOf] = delegatedAmount = delegatorAmounts[onBehalfOf] + gohmAmount;

        factory().logDelegate(msg.sender, onBehalfOf, int256(gohmAmount));
    }

    /// @notice Rescind a delegation of gOHM and send back to the caller.
    function rescindDelegation(address onBehalfOf, uint256 gohmAmount) external returns (uint256 delegatedAmount) {
        mapping(address => uint256) storage delegatorAmounts = delegations[msg.sender];
        uint256 existingDelegatedAmount = delegatorAmounts[onBehalfOf];
        if (gohmAmount > existingDelegatedAmount) revert ExceededDelegationBalance();

        delegatorAmounts[onBehalfOf] = delegatedAmount = existingDelegatedAmount - gohmAmount;
        gohm.safeTransfer(msg.sender, gohmAmount);

        factory().logDelegate(msg.sender, onBehalfOf, -int256(gohmAmount));
    }

    /// @notice Ensure that the caller is the factory which created this contract only.
    modifier onlyFactory() {
        if (msg.sender != address(factory())) revert NotFactory();
        _;
    }
}
