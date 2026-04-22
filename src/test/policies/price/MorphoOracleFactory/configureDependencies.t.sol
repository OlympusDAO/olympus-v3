// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {Kernel, Actions, Keycode, Module, toKeycode} from "src/Kernel.sol";
import {MorphoOracleFactory} from "src/policies/price/MorphoOracleFactory.sol";
import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";

contract MockRolesV2 is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("ROLES");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (2, 0);
    }
}

contract MorphoOracleFactoryConfigureDependenciesTest is MorphoOracleFactoryTest {
    function test_whenDependenciesConfigured_setsRolesModule() public view {
        assertEq(address(factory.ROLES()), address(roles), "ROLES module should be set");
    }

    function test_whenROLESMajorVersionIsNotSupported_reverts() public {
        Kernel newKernel = new Kernel();
        MockRolesV2 newRoles = new MockRolesV2(newKernel);
        MockPriceCache newPriceCache = new MockPriceCache(address(newKernel));
        MorphoOracleFactory newFactory = new MorphoOracleFactory(newKernel, address(newPriceCache));

        newKernel.executeAction(Actions.InstallModule, address(newRoles));

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_UnsupportedModuleVersion.selector,
                bytes5("ROLES"),
                2,
                0
            )
        );
        newKernel.executeAction(Actions.ActivatePolicy, address(newFactory));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
