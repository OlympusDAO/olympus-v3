// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test-utils/UserFactory.sol";

import {Kernel, Module, Instruction, Actions} from "../../Kernel.sol";
import "modules/INSTR.sol";
import {Governance} from "policies/Governance.sol";
import {MockModuleWriter} from "../mocks/MockModuleWriter.sol";
import {MockInvalidModule} from "../mocks/MockInvalidModule.sol";

contract InstructionsTest is Test {
    Kernel internal kernel;

    OlympusInstructions internal instr;
    Governance internal governance;
    OlympusInstructions internal instrWriter;
    Module internal invalidModule;

    event InstructionsStored(uint256);

    function setUp() public {
        /// Deploy kernel
        kernel = new Kernel(); // this contract will be the executor

        /// Deploy modules (some mocks)
        instr = new OlympusInstructions(kernel);
        invalidModule = new MockInvalidModule(kernel);

        /// Deploy policies
        instrWriter = OlympusInstructions(
            address(new MockModuleWriter(kernel, instr))
        );
        governance = new Governance(kernel);

        /// Install modules
        kernel.executeAction(Actions.InstallModule, address(instr));

        /// Approve policies
        kernel.executeAction(Actions.ApprovePolicy, address(instrWriter));

        // Change executor
        kernel.executeAction(Actions.ChangeExecutor, address(instrWriter));
    }

    function testRevert_InstructionsCannotBeEmpty() public {
        vm.expectRevert(INSTR_InstructionsCannotBeEmpty.selector);

        // create valid instructions
        Instruction[] memory instructions = new Instruction[](0);
        instrWriter.store(instructions);
    }

    function testRevert_InvalidChangeExecutorAction() public {
        // create invalid instructions
        Instruction[] memory instructions = new Instruction[](2);
        instructions[0] = Instruction(
            Actions.ChangeExecutor,
            address(governance)
        );
        instructions[1] = Instruction(
            Actions.ApprovePolicy,
            address(governance)
        );

        vm.expectRevert(INSTR_InvalidChangeExecutorAction.selector);
        instrWriter.store(instructions);
    }

    function testRevert_InvalidTargetNotAContract() public {
        // create invalid instructions
        Instruction[] memory instructions = new Instruction[](1);
        instructions[0] = Instruction(Actions.InstallModule, address(0));

        vm.expectRevert(INSTR_InvalidTargetNotAContract.selector);
        instrWriter.store(instructions);
    }

    function testRevert_InvalidModuleKeycode() public {
        // create invalid instructions
        Instruction[] memory instructions = new Instruction[](1);
        instructions[0] = Instruction(
            Actions.InstallModule,
            address(invalidModule)
        );

        vm.expectRevert(INSTR_InvalidModuleKeycode.selector);
        instrWriter.store(instructions);
    }

    function testCorrectness_StoreInstructions() public {
        // create valid instructions
        Instruction[] memory instructions = new Instruction[](2);
        instructions[0] = Instruction(
            Actions.ApprovePolicy,
            address(governance)
        );
        instructions[1] = Instruction(
            Actions.ChangeExecutor,
            address(governance)
        );

        vm.expectEmit(true, true, true, true);
        emit InstructionsStored(1);

        instrWriter.store(instructions);

        instructions = instr.getInstructions(1);

        assertEq(
            uint256(instructions[0].action),
            uint256(Actions.ApprovePolicy)
        );
        assertEq(instructions[0].target, address(governance));
        assertEq(
            uint256(instructions[1].action),
            uint256(Actions.ChangeExecutor)
        );
        assertEq(instructions[1].target, address(governance));
        assertEq(instr.totalInstructions(), 1);
    }
}
