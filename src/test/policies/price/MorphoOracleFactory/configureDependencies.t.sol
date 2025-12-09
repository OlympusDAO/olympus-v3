// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {Kernel, Actions, Module, Keycode, toKeycode} from "src/Kernel.sol";
import {MorphoOracleFactory} from "src/policies/price/MorphoOracleFactory.sol";
import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";

/// @notice Mock PRICE module that doesn't support IPRICEv2 interface
contract MockPriceWithoutInterface is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("PRICE");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (2, 0);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

/// @notice Mock PRICE module with v1.1 version
contract MockPriceV1_1 is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("PRICE");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 1);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

contract MorphoOracleFactoryConfigureDependenciesTest is MorphoOracleFactoryTest {
    // ========== TESTS ========== //

    // when PRICE module is v1.1 or lower
    //  [X] it reverts with UnsupportedPRICEVersion

    function test_whenPRICEModuleIsV1_1_reverts() public {
        // Deploy new factory with v1.1 PRICE module
        Kernel newKernel = new Kernel();
        MockPriceV1_1 v1_1Price = new MockPriceV1_1(newKernel);
        OlympusRoles newRoles = new OlympusRoles(newKernel);
        RolesAdmin newRolesAdmin = new RolesAdmin(newKernel);
        MorphoOracleFactory newFactory = new MorphoOracleFactory(newKernel);

        // Install modules
        newKernel.executeAction(Actions.InstallModule, address(v1_1Price));
        newKernel.executeAction(Actions.InstallModule, address(newRoles));
        newKernel.executeAction(Actions.ActivatePolicy, address(newRolesAdmin));

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_UnsupportedPRICEVersion.selector,
                1,
                1
            )
        );

        newKernel.executeAction(Actions.ActivatePolicy, address(newFactory));
    }

    // when PRICE module does not support IPRICEv2
    //  [X] it reverts with PRICEInterfaceNotSupported

    function test_whenPRICEModuleDoesNotSupportIPRICEv2_reverts() public {
        // Deploy new factory with PRICE module that doesn't support IPRICEv2
        Kernel newKernel = new Kernel();
        MockPriceWithoutInterface noInterfacePrice = new MockPriceWithoutInterface(newKernel);
        OlympusRoles newRoles = new OlympusRoles(newKernel);
        RolesAdmin newRolesAdmin = new RolesAdmin(newKernel);
        MorphoOracleFactory newFactory = new MorphoOracleFactory(newKernel);

        // Install modules
        newKernel.executeAction(Actions.InstallModule, address(noInterfacePrice));
        newKernel.executeAction(Actions.InstallModule, address(newRoles));
        newKernel.executeAction(Actions.ActivatePolicy, address(newRolesAdmin));

        // Expect revert
        vm.expectRevert(IOracleFactory.OracleFactory_PRICEInterfaceNotSupported.selector);

        newKernel.executeAction(Actions.ActivatePolicy, address(newFactory));
    }

    // when PRICE module is v1.2+
    //  [X] it sets PRICE module
    //  [X] it sets PRICE_DECIMALS

    function test_success() public view {
        // Factory is already configured in setUp, verify PRICE is set
        assertEq(address(factory.PRICE()), address(priceModule), "PRICE module should be set");
        assertEq(factory.PRICE_DECIMALS(), PRICE_DECIMALS, "PRICE_DECIMALS should be set");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
