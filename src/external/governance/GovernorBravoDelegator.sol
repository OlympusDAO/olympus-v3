// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.15;

import {IGovernorBravoEventsAndErrors} from "./interfaces/IGovernorBravoEvents.sol";
import {GovernorBravoDelegatorStorage} from "./abstracts/GovernorBravoStorage.sol";

contract GovernorBravoDelegator is GovernorBravoDelegatorStorage, IGovernorBravoEventsAndErrors {
    // --- CONSTRUCTOR -------------------------------------------------------------

    constructor(
        address timelock_,
        address gohm_,
        address kernel_,
        address vetoGuardian_,
        address implementation_,
        uint256 votingPeriod_,
        uint256 votingDelay_,
        uint256 activationGracePeriod_,
        uint256 proposalThreshold_
    ) {
        // Admin set to msg.sender for initialization
        admin = msg.sender;

        delegateTo(
            implementation_,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint256,uint256,uint256,uint256)",
                timelock_,
                gohm_,
                kernel_,
                vetoGuardian_,
                votingPeriod_,
                votingDelay_,
                activationGracePeriod_,
                proposalThreshold_
            )
        );

        _setImplementation(implementation_);

        admin = timelock_;
    }

    // --- PROXY LOGIC -------------------------------------------------------------

    /**
     * @notice Called by the admin to update the implementation of the delegator
     * @param implementation_ The address of the new implementation for delegation
     */
    function _setImplementation(address implementation_) public {
        require(msg.sender == admin, "GovernorBravoDelegator::_setImplementation: admin only");
        require(
            implementation_ != address(0),
            "GovernorBravoDelegator::_setImplementation: invalid implementation address"
        );

        address oldImplementation = implementation;
        implementation = implementation_;

        emit NewImplementation(oldImplementation, implementation);
    }

    /**
     * @notice Internal method to delegate execution to another contract
     * @dev It returns to the external caller whatever the implementation returns or forwards reverts
     * @param callee The contract to delegatecall
     * @param data The raw data to delegatecall
     */
    function delegateTo(address callee, bytes memory data) internal {
        (bool success, bytes memory returnData) = callee.delegatecall(data);
        assembly {
            if eq(success, 0) {
                revert(add(returnData, 0x20), returndatasize())
            }
        }
    }

    /**
     * @dev Delegates execution to an implementation contract.
     * It returns to the external caller whatever the implementation returns
     * or forwards reverts.
     */
    fallback() external payable {
        // delegate all other functions to current implementation
        (bool success, ) = implementation.delegatecall(msg.data);

        assembly {
            let free_mem_ptr := mload(0x40)
            returndatacopy(free_mem_ptr, 0, returndatasize())

            switch success
            case 0 {
                revert(free_mem_ptr, returndatasize())
            }
            default {
                return(free_mem_ptr, returndatasize())
            }
        }
    }
}
