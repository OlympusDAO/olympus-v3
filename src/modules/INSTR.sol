// SPDX-License-Identifier: AGPL-3.0-only

// [INSTR] The Instructions Module caches and executes batched instructions for protocol upgrades in the Kernel

pragma solidity ^0.8.13;

import "src/Kernel.sol";

error INSTR_CannotBeEmpty();
error INSTR_InstructionModuleMustBeLast();
error INSTR_NotAContract(address target_);
error INSTR_InvalidKeycode(Kernel.Keycode keycode_);

contract Instructions is Module {
    /////////////////////////////////////////////////////////////////////////////////
    //                         Kernel Module Configuration                         //
    /////////////////////////////////////////////////////////////////////////////////

    Kernel.Role public constant EXECUTOR = Kernel.Role.wrap("INSTR_Executor");

    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Kernel.Keycode) {
        return Kernel.Keycode.wrap("INSTR");
    }

    function ROLES() public pure override returns (Kernel.Role[] memory roles) {
        roles = new Kernel.Role[](1);
        roles[0] = EXECUTOR;
    }

    /////////////////////////////////////////////////////////////////////////////////
    //                              Module Variables                               //
    /////////////////////////////////////////////////////////////////////////////////

    event InstructionsStored(uint256 instructionsId);
    event InstructionsExecuted(uint256 instructionsId);

    /* Imported from Kernel, just here for reference:

    enum Actions {
        ChangeExecutive,
        ApprovePolicy,
        TerminatePolicy,
        InstallSystem,
        UpgradeSystem
    }

    struct Instruction {
        Actions action;
        address target;
    }
    */

    uint256 public totalInstructions;
    mapping(uint256 => Instruction[]) public storedInstructions;

    /////////////////////////////////////////////////////////////////////////////////
    //                             Policy Interface                                //
    /////////////////////////////////////////////////////////////////////////////////

    function store(Instruction[] calldata instructions_)
        external
        onlyRole(EXECUTOR)
        returns (uint256)
    {
        uint256 length = instructions_.length;
        uint256 instructionsId = totalInstructions + 1;
        Instruction[] storage instructions = storedInstructions[instructionsId];

        if (length == 0) revert INSTR_CannotBeEmpty();

        for (uint256 i = 0; i < length; i++) {
            Instruction calldata instruction = instructions_[i];
            _ensureContract(instruction.target);

            if (
                instruction.action == Actions.InstallModule ||
                instruction.action == Actions.UpgradeModule
            ) {
                Kernel.Keycode keycode = Module(instruction.target).KEYCODE();
                _ensureValidKeycode(keycode);

                /* 
                CAUTION: Review the conditional below & make sure it's implemented correctly so
                upgrades to the instructions module cannot brick the system

                [INSTR] Module change must be coupled with a "changeExecutor" Instruction
                or the old module will have executor roles while the new modules will be accessed by policies
                Change executor to whitelist of addresses vs. single owner?
                */

                if (
                    Kernel.Keycode.unwrap(keycode) == "INSTR" && length - 1 != i
                ) revert INSTR_InstructionModuleMustBeLast();
            }

            instructions.push(instructions_[i]);
        }
        totalInstructions++;

        emit InstructionsStored(instructionsId);

        return instructionsId;
    }

    function execute(uint256 instructionsId_) external onlyRole(EXECUTOR) {
        Instruction[] memory instructions = storedInstructions[instructionsId_];

        for (uint256 step = 0; step < instructions.length; step++) {
            kernel.executeAction(
                instructions[step].action,
                instructions[step].target
            );
        }

        emit InstructionsExecuted(instructionsId_);
    }

    /////////////////////////////// INTERNAL FUNCTIONS ////////////////////////////////

    function _ensureContract(address target_) internal view {
        uint256 size;
        assembly {
            size := extcodesize(target_)
        }
        if (size == 0) revert INSTR_NotAContract(target_);
    }

    function _ensureValidKeycode(Kernel.Keycode keycode_) internal pure {
        bytes5 unwrapped = Kernel.Keycode.unwrap(keycode_);

        for (uint256 i = 0; i < 5; ) {
            bytes1 char = unwrapped[i];

            if (char < 0x41 || char > 0x5A)
                revert INSTR_InvalidKeycode(keycode_);
            // A-Z only"

            unchecked {
                i++;
            }
        }
    }
}
