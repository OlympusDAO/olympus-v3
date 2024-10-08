// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {EXREGv1} from "src/modules/EXREG/EXREG.v1.sol";
import {OlympusExternalRegistry} from "src/modules/EXREG/OlympusExternalRegistry.sol";

contract ExternalRegistryTest is Test {
    using ModuleTestFixtureGenerator for OlympusExternalRegistry;

    address public godmode;

    Kernel internal _kernel;
    OlympusExternalRegistry internal _exreg;

    // External Registry Expected events
    event ContractRegistered(bytes5 indexed name, address indexed contractAddress);
    event ContractDeregistered(bytes5 indexed name);

    function setUp() public {
        // Deploy Kernel and modules
        _kernel = new Kernel();
        _exreg = new OlympusExternalRegistry(address(_kernel));

        // Generate fixtures
        godmode = _exreg.generateGodmodeFixture(type(OlympusExternalRegistry).name);

        // Install modules and policies on Kernel
        _kernel.executeAction(Actions.InstallModule, address(_exreg));
        _kernel.executeAction(Actions.ActivatePolicy, godmode);
    }

    // =========  TESTS ========= //

    // constructor
    // when the kernel address is zero
    //  [ ] it reverts
    // when the kernel address is not zero
    //  [ ] it sets the kernel address

    // registerContract
    // when the caller is not permissioned
    //  [ ] it reverts
    // when the name is empty
    //  [ ] it reverts
    // when the contract address is zero
    //  [ ] it reverts
    // given the name is registered
    //  [ ] it updates the contract address and emits an event, but does not update the names array
    // given the name is not registered
    //  [ ] it registers the contract address, emits an event and updates the names array

    // deregisterContract
    // when the caller is not permissioned
    //  [ ] it reverts
    // given the name is not registered
    //  [ ] it reverts
    // given the name is registered
    //  given multiple names are registered
    //   [ ] it deregisters the name, emits an event and updates the names array
    //  [ ] it deregisters the name, emits an event and updates the names array

    // getContract
    // given the name is not registered
    //  [ ] it reverts
    // given the name is registered
    //  given the name has been updated
    //   [ ] it returns the latest address
    //  [ ] it returns the contract address

    // getContractNames
    // given no names are registered
    //  [ ] it returns an empty array
    // given names are registered
    //  [ ] it returns the names array
}
