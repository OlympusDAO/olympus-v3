// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "src/Kernel.sol";

error INSTR_InstructionsCannotBeEmpty();
error INSTR_InvalidChangeExecutorAction();

/// @notice Caches and executes batched instructions for protocol upgrades in the Kernel.
contract OlympusInstructions is Module {
    event InstructionsStored(uint256 instructionsId);

    uint256 public totalInstructions;
    mapping(uint256 => Instruction[]) public storedInstructions;

    /*//////////////////////////////////////////////////////////////
                            MODULE INTERFACE
    //////////////////////////////////////////////////////////////*/

    constructor(Kernel kernel_) Module(kernel_) {}

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("INSTR");
    }

    /// @inheritdoc Module
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /*//////////////////////////////////////////////////////////////
                               CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice View function for retrieving a list of Instructions in an outside contract.
    function getInstructions(uint256 instructionsId_) public view returns (Instruction[] memory) {
        return storedInstructions[instructionsId_];
    }

    /// @notice Store a list of Instructions to be executed in the future.
    function store(Instruction[] calldata instructions_) external permissioned returns (uint256) {
        uint256 length = instructions_.length;
        uint256 instructionsId = ++totalInstructions;

        Instruction[] storage instructions = storedInstructions[instructionsId];

        if (length == 0) revert INSTR_InstructionsCannotBeEmpty();

        for (uint256 i; i < length; ) {
            Instruction calldata instruction = instructions_[i];
            ensureContract(instruction.target);

            // If the instruction deals with a module, make sure the module has a valid keycode (UPPERCASE A-Z ONLY)
            if (
                instruction.action == Actions.InstallModule ||
                instruction.action == Actions.UpgradeModule
            ) {
                Module module = Module(instruction.target);
                ensureValidKeycode(module.KEYCODE());
            } else if (instruction.action == Actions.ChangeExecutor && i != length - 1) {
                // Throw an error if ChangeExecutor exists and is not the last Action in the instruction list.
                // This exists because if ChangeExecutor is not the last item in the list of instructions,
                // the Kernel will not recognize any of the following instructions as valid, since the policy
                // executing the list of instructions no longer has permissions in the Kernel. To avoid this issue
                // and prevent invalid proposals from being saved, we perform this check.
                revert INSTR_InvalidChangeExecutorAction();
            }

            instructions.push(instructions_[i]);
            unchecked {
                ++i;
            }
        }

        emit InstructionsStored(instructionsId);

        return instructionsId;
    }
}
