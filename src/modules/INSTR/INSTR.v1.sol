// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "src/Kernel.sol";

/// @notice Caches and executes batched instructions for protocol upgrades in the Kernel.
abstract contract INSTRv1 is Module {
    // =========  EVENTS ========= //

    event InstructionsStored(uint256 instructionsId);

    // =========  ERRORS ========= //

    error INSTR_InstructionsCannotBeEmpty();
    error INSTR_InvalidAction();

    // =========  STATE ========= //

    /// @notice Counter of total instructions
    uint256 public totalInstructions;

    /// @notice All stored instructions per count in totalInstructions
    mapping(uint256 => Instruction[]) public storedInstructions;

    // =========  FUNCTIONS ========= //

    /// @notice View function for retrieving a list of Instructions in an outside contract.
    function getInstructions(uint256 instructionsId_)
        external
        virtual
        returns (Instruction[] memory);

    /// @notice Store a list of Instructions to be executed in the future.
    function store(Instruction[] calldata instructions_) external virtual returns (uint256);
}
