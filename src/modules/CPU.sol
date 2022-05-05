// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import "../Kernel.sol";

// CPU is the module that stores and executes batched instructions for the kernel
contract Processor is Module {
    /////////////////////////////////////////////////////////////////////////////////
    //                      DefaultOS Module Configuration                         //
    /////////////////////////////////////////////////////////////////////////////////

    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (bytes3) {
        return "CPU";
    }

    /////////////////////////////////////////////////////////////////////////////////
    //                              System Variables                               //
    /////////////////////////////////////////////////////////////////////////////////

    /* imported from Proxy.sol

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

    event InstructionsStored(uint256 instructionsId);
    event InstructionsExecuted(uint256 instructionsId);

    function storeInstructions(Instruction[] calldata instructions_)
        external
        onlyPermitted
        returns (uint256)
    {
        uint256 instructionsId = totalInstructions + 1;
        Instruction[] storage instructions = storedInstructions[instructionsId];

        require(
            instructions_.length > 0,
            "cannot storeInstructions(): instructions cannot be empty"
        );

        // @TODO use u256
        for (uint256 i = 0; i < instructions_.length; i++) {
            _ensureContract(instructions_[i].target);
            if (
                instructions_[i].action == Actions.InstallModule ||
                instructions_[i].action == Actions.UpgradeModule
            ) {
                bytes4 keycode = Module(instructions_[i].target).KEYCODE();
                _ensureValidKeycode(keycode);
                if (keycode == "CPU") {
                    require(
                        instructions_[instructions_.length - 1].action ==
                            Actions.ChangeExecutor,
                        "cannot storeInstructions(): changes to the Executive system (EXC) requires changing the Kernel executive as the last step of the proposal"
                    );
                    require(
                        instructions_[instructions_.length - 1].target ==
                            instructions_[i].target,
                        "cannot storeInstructions(): changeExecutive target address does not match the upgraded Executive system address"
                    );
                }
            }
            instructions.push(instructions_[i]);
        }
        totalInstructions++;

        emit InstructionsStored(instructionsId);

        return instructionsId;
    }

    function executeInstructions(uint256 instructionsId_)
        external
        onlyPermitted
    {
        Instruction[] storage proposal = storedInstructions[instructionsId_];

        require(
            proposal.length > 0,
            "cannot executeInstructions(): proposal does not exist"
        );

        for (uint256 step = 0; step < proposal.length; step++) {
            Actions action = proposal[step].action;
            address target = proposal[step].target;

            _kernel.executeAction(action, target);

            if (
                action == Actions.ApprovePolicy ||
                action == Actions.TerminatePolicy
            ) {
                bytes3[] memory codesToSet;
                bytes3[] memory keycodes = Policy(target).PERMS();

                uint256 length = codesToSet.length;

                // meaning if terminate then set all zeroes
                if (action == Actions.ApprovePolicy) codesToSet = keycodes;

                for (uint256 i; i < length; i++) {
                    _kernel.permitCall(target, codesToSet[i]);
                }
            }
        }

        emit InstructionsExecuted(instructionsId_);
    }

    /////////////////////////////// INTERNAL FUNCTIONS ////////////////////////////////

    function _ensureContract(address target_) internal view {
        uint256 size;
        assembly {
            size := extcodesize(target_)
        }
        require(
            size > 0,
            "cannot storeInstructions(): target address is not a contract"
        );
    }

    function _ensureValidKeycode(bytes4 keycode) internal pure {
        for (uint256 i = 0; i < 3; i++) {
            bytes1 char = keycode[i];
            require(
                char >= 0x41 && char <= 0x5A,
                " cannot storeInstructions(): invalid keycode"
            ); // A-Z only"
        }
    }
}
