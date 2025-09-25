// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(screaming-snake-case-immutable)
pragma solidity ^0.8.15;

import {IVotes} from "openzeppelin/governance/utils/IVotes.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Clone} from "clones/Clone.sol";
import {DelegateEscrowFactory} from "src/external/cooler/DelegateEscrowFactory.sol";

/**
 * @title Delegate Escrow Account
 * @notice An escrow to hold gOHM and delegate that amount to exactly one account.
 * @dev Any caller (eg MonoCooler) can delegate on behalf of a `delegator` address, but only that same caller
 * can rescind the delegation to pull the gOHM back.
 * This contract uses Clones (https://github.com/wighawag/clones-with-immutable-args)
 * to save gas on deployment.
 * Note: Any donated gOHM (transferred directly rather than using `delegate()`) cannot be recovered.
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
    mapping(address /* caller */ => mapping(address /* onBehalfOf */ => uint256 /* amount */))
        public delegations;

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
    function delegate(
        address onBehalfOf,
        uint256 gohmAmount
    ) external returns (uint256 delegatedAmount) {
        gohm.safeTransferFrom(msg.sender, address(this), gohmAmount);

        mapping(address => uint256) storage delegatorAmounts = delegations[msg.sender];
        delegatorAmounts[onBehalfOf] = delegatedAmount = delegatorAmounts[onBehalfOf] + gohmAmount;

        factory().logDelegate(msg.sender, onBehalfOf, int256(gohmAmount));
    }

    /// @notice Rescind a delegation of gOHM and send back to the caller.
    function rescindDelegation(
        address onBehalfOf,
        uint256 gohmAmount
    ) external returns (uint256 delegatedAmount) {
        mapping(address => uint256) storage delegatorAmounts = delegations[msg.sender];
        uint256 existingDelegatedAmount = delegatorAmounts[onBehalfOf];
        if (gohmAmount > existingDelegatedAmount) revert ExceededDelegationBalance();

        unchecked {
            delegatorAmounts[onBehalfOf] = delegatedAmount = existingDelegatedAmount - gohmAmount;
        }
        gohm.safeTransfer(msg.sender, gohmAmount);

        factory().logDelegate(msg.sender, onBehalfOf, -int256(gohmAmount));
    }

    /// @notice The total amount delegated via this escrow across all callers, including donations.
    function totalDelegated() external view returns (uint256) {
        return gohm.balanceOf(address(this));
    }

    /// @notice Ensure that the caller is the factory which created this contract only.
    modifier onlyFactory() {
        if (msg.sender != address(factory())) revert NotFactory();
        _;
    }
}
/// forge-lint: disable-end(screaming-snake-case-immutable)
