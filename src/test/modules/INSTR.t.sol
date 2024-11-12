// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {Parthenon} from "policies/Parthenon.sol";
import {MockModuleWriter} from "test/mocks/MockModuleWriter.sol";
import {MockInvalidModule} from "test/mocks/MockInvalidModule.sol";
import {MockValidModule} from "test/mocks/MockValidModule.sol";
import {MockValidUpgradedModule} from "test/mocks/MockValidUpgradedModule.sol";

import "modules/INSTR/OlympusInstructions.sol";
import "src/Kernel.sol";

contract InstructionsTest is Test {
    Kernel internal kernel;
    using ModuleTestFixtureGenerator for OlympusInstructions;

    OlympusInstructions internal instr;
    Parthenon internal governance;
    address internal writer;
    Module internal invalidModule;

    event InstructionsStored(uint256);

    function setUp() public {
        /// Deploy kernel
        kernel = new Kernel(); // this contract will be the executor

        /// Deploy modules (some mocks)
        instr = new OlympusInstructions(kernel);
        invalidModule = new MockInvalidModule(kernel);

        /// Deploy policies
        writer = instr.generateGodmodeFixture(type(OlympusInstructions).name);
        governance = new Parthenon(kernel);

        /// Install modules
        kernel.executeAction(Actions.InstallModule, address(instr));

        /// Approve policies
        kernel.executeAction(Actions.ActivatePolicy, writer);
    }

    function testRevert_InstructionsCannotBeEmpty() public {
        vm.expectRevert(INSTRv1.INSTR_InstructionsCannotBeEmpty.selector);

        // create valid instructions
        Instruction[] memory instructions = new Instruction[](0);
        vm.prank(writer);
        instr.store(instructions);
    }

    function testRevert_InvalidAction() public {
        // create invalid instructions
        Instruction[] memory instructions = new Instruction[](2);
        instructions[0] = Instruction(Actions.MigrateKernel, address(governance));
        instructions[1] = Instruction(Actions.ActivatePolicy, address(governance));

        vm.expectRevert(INSTRv1.INSTR_InvalidAction.selector);
        vm.prank(writer);
        instr.store(instructions);

        // Change to first action to MigrateKernel to test if it reverts
        instructions[0] = Instruction(Actions.MigrateKernel, address(governance));

        vm.expectRevert(INSTRv1.INSTR_InvalidAction.selector);
        vm.prank(writer);
        instr.store(instructions);
    }

    function testRevert_InvalidTargetNotAContract() public {
        // create invalid instructions
        Instruction[] memory instructions = new Instruction[](1);
        instructions[0] = Instruction(Actions.InstallModule, address(0));

        vm.expectRevert(abi.encodeWithSelector(TargetNotAContract.selector, address(0)));
        vm.prank(writer);
        instr.store(instructions);
    }

    function testRevert_InvalidModuleKeycode() public {
        // create invalid instructions
        Instruction[] memory instructions = new Instruction[](1);
        instructions[0] = Instruction(Actions.InstallModule, address(invalidModule));

        vm.expectRevert(abi.encodeWithSelector(InvalidKeycode.selector, invalidModule.KEYCODE()));
        vm.prank(writer);
        instr.store(instructions);
    }

    function testCorrectness_InstallModule() public {
        // deploy new sample module
        address mockModuleAddress = address(new MockValidModule(kernel));

        // create valid instructions
        Instruction[] memory instructions = new Instruction[](1);
        instructions[0] = Instruction(Actions.InstallModule, mockModuleAddress);

        vm.expectEmit(true, true, true, true);
        emit InstructionsStored(1);

        vm.prank(writer);
        instr.store(instructions);

        instructions = instr.getInstructions(1);

        assertEq(uint256(instructions[0].action), uint256(Actions.InstallModule));
        assertEq(instructions[0].target, address(mockModuleAddress));
    }

    function testCorrectness_UpgradeModule() public {
        // deploy new sample module and upgrade
        Module mockModuleAddress = Module(new MockValidModule(kernel));
        Policy mockModuleWriter = Policy(
            new MockModuleWriter(kernel, mockModuleAddress, new Permissions[](0))
        );
        Module mockUpgradedModuleAddress = Module(new MockValidUpgradedModule(kernel));

        // install a pre-existing module and policy
        kernel.executeAction(Actions.InstallModule, address(mockModuleAddress));
        kernel.executeAction(Actions.ActivatePolicy, address(mockModuleWriter));

        // create the upgrade instruction
        Instruction[] memory instructions = new Instruction[](1);
        instructions[0] = Instruction(Actions.UpgradeModule, address(mockUpgradedModuleAddress));

        vm.expectEmit(true, true, true, true);
        emit InstructionsStored(1);

        // store it
        vm.prank(writer);
        instr.store(instructions);

        assertEq(uint256(instructions[0].action), uint256(Actions.UpgradeModule));
        assertEq(instructions[0].target, address(mockUpgradedModuleAddress));
        assertEq(instr.totalInstructions(), 1);

        // execute the upgrade
        kernel.executeAction(instructions[0].action, instructions[0].target);

        // ******CHECK IF OLD POLICY CAN CALL THE UPGRADED MODULE WITH NEW ROLES*******
        // update the mockvalidmodule test
        // MockValidModule(mockModuleWriter).roleCall();
        // assertEq(mockUpgradedModuleAddress.counter, 1);
    }

    function testCorrectness_ActivatePolicy() public {
        MockValidModule mockModuleAddress = new MockValidModule(kernel);
        MockValidModule mockModuleWriter = MockValidModule(
            address(new MockModuleWriter(kernel, mockModuleAddress, new Permissions[](0)))
        );

        kernel.executeAction(Actions.InstallModule, address(mockModuleAddress));

        // create valid instructions
        Instruction[] memory instructions = new Instruction[](1);
        instructions[0] = Instruction(Actions.ActivatePolicy, address(mockModuleWriter));

        vm.expectEmit(true, true, true, true);
        emit InstructionsStored(1);

        vm.prank(writer);
        instr.store(instructions);
        instructions = instr.getInstructions(1);

        kernel.executeAction(instructions[0].action, instructions[0].target);

        assertEq(uint256(instructions[0].action), uint256(Actions.ActivatePolicy));
        assertEq(instructions[0].target, address(mockModuleWriter));
        assertEq(instr.totalInstructions(), 1);

        //mockModuleWriter.roleCall();
        //assertEq(mockModuleAddress.counter(), 1);
    }

    function testCorrectness_DeactivatePolicy() public {
        MockValidModule mockModuleAddress = new MockValidModule(kernel);
        MockValidModule mockModuleWriter = MockValidModule(
            address(new MockModuleWriter(kernel, mockModuleAddress, new Permissions[](0)))
        );

        kernel.executeAction(Actions.InstallModule, address(mockModuleAddress));
        kernel.executeAction(Actions.ActivatePolicy, address(mockModuleWriter));

        // create valid instructions
        Instruction[] memory instructions = new Instruction[](1);
        instructions[0] = Instruction(Actions.DeactivatePolicy, address(mockModuleWriter));

        vm.expectEmit(true, true, true, true);
        emit InstructionsStored(1);

        vm.prank(writer);
        instr.store(instructions);
        instructions = instr.getInstructions(1);
        kernel.executeAction(instructions[0].action, instructions[0].target);

        assertEq(uint256(instructions[0].action), uint256(Actions.DeactivatePolicy));
        assertEq(instructions[0].target, address(mockModuleWriter));

        // TODO update with correct error message
        // vm.expectRevert(Module_PolicyNotPermitted.selector);
        // mockModuleWriter.roleCall();
    }

    function testCorrectness_ChangeExecutor() public {
        // create valid instructions
        Instruction[] memory instructions = new Instruction[](2);
        instructions[0] = Instruction(Actions.ActivatePolicy, address(governance));
        instructions[1] = Instruction(Actions.ChangeExecutor, address(governance));

        vm.expectEmit(true, true, true, true);
        emit InstructionsStored(1);

        vm.prank(writer);
        instr.store(instructions);

        instructions = instr.getInstructions(1);

        assertEq(uint256(instructions[0].action), uint256(Actions.ActivatePolicy));
        assertEq(instructions[0].target, address(governance));
        assertEq(uint256(instructions[1].action), uint256(Actions.ChangeExecutor));
        assertEq(instructions[1].target, address(governance));
        assertEq(instr.totalInstructions(), 1);
    }
}
