// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZEndpointDelegateTestBase} from "src/test/policies/bridge/LZEndpointDelegate/LZEndpointDelegateTestBase.sol";

// Interfaces
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";

// Constants
import {BRIDGE_CONFIGURATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev ILZEndpointV2Authorized endpoint configuration via the LZEndpointDelegate policy: mock-based
///      verification that every external OApp-authorized call lands on the LZ endpoint with the
///      gateway passed as the OApp argument, plus role-gated access control. Every entry point
///      is gated to `bridge_configurator`.
contract LZEndpointDelegateTests_EndpointConfig is LZEndpointDelegateTestBase {
    function test_setSendLibrary_bridgeConfiguratorCanCall() external {
        address lib = address(0xBEEF);

        vm.mockCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "setSendLibrary(address,uint32,address)",
                gateway,
                NONCANONICAL_EID,
                lib
            ),
            bytes("")
        );
        vm.expectCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "setSendLibrary(address,uint32,address)",
                gateway,
                NONCANONICAL_EID,
                lib
            )
        );
        vm.prank(bridgeConfigurator);
        lzDelegate.setSendLibrary(NONCANONICAL_EID, lib);
    }

    function testFuzz_setSendLibrary_revertsIfNotBridgeConfigurator(address caller_) external {
        vm.assume(caller_ != bridgeConfigurator);

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(caller_);
        lzDelegate.setSendLibrary(NONCANONICAL_EID, address(1));
    }

    function test_setReceiveLibrary_bridgeConfiguratorCanCall() external {
        address lib = address(0xBEEF);
        uint256 gracePeriod = 100;

        vm.mockCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "setReceiveLibrary(address,uint32,address,uint256)",
                gateway,
                NONCANONICAL_EID,
                lib,
                gracePeriod
            ),
            bytes("")
        );
        vm.expectCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "setReceiveLibrary(address,uint32,address,uint256)",
                gateway,
                NONCANONICAL_EID,
                lib,
                gracePeriod
            )
        );
        vm.prank(bridgeConfigurator);
        lzDelegate.setReceiveLibrary(NONCANONICAL_EID, lib, gracePeriod);
    }

    function testFuzz_setReceiveLibrary_revertsIfNotBridgeConfigurator(address caller_) external {
        vm.assume(caller_ != bridgeConfigurator);

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(caller_);
        lzDelegate.setReceiveLibrary(NONCANONICAL_EID, address(1), 0);
    }

    function test_setReceiveLibraryTimeout_bridgeConfiguratorCanCall() external {
        address lib = address(0xBEEF);
        uint256 expiry = vm.getBlockTimestamp() + 1 days;

        vm.mockCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "setReceiveLibraryTimeout(address,uint32,address,uint256)",
                gateway,
                NONCANONICAL_EID,
                lib,
                expiry
            ),
            bytes("")
        );
        vm.expectCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "setReceiveLibraryTimeout(address,uint32,address,uint256)",
                gateway,
                NONCANONICAL_EID,
                lib,
                expiry
            )
        );
        vm.prank(bridgeConfigurator);
        lzDelegate.setReceiveLibraryTimeout(NONCANONICAL_EID, lib, expiry);
    }

    function testFuzz_setReceiveLibraryTimeout_revertsIfNotBridgeConfigurator(
        address caller_
    ) external {
        vm.assume(caller_ != bridgeConfigurator);

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(caller_);
        lzDelegate.setReceiveLibraryTimeout(NONCANONICAL_EID, address(1), 0);
    }

    function test_setEndpointConfig_bridgeConfiguratorCanCall() external {
        address lib = address(0xBEEF);
        SetConfigParam[] memory params = new SetConfigParam[](0);

        vm.mockCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "setConfig(address,address,(uint32,uint32,bytes)[])",
                gateway,
                lib,
                params
            ),
            bytes("")
        );
        vm.expectCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "setConfig(address,address,(uint32,uint32,bytes)[])",
                gateway,
                lib,
                params
            )
        );
        vm.prank(bridgeConfigurator);
        lzDelegate.setEndpointConfig(lib, params);
    }

    function testFuzz_setEndpointConfig_revertsIfNotBridgeConfigurator(address caller_) external {
        vm.assume(caller_ != bridgeConfigurator);

        SetConfigParam[] memory params = new SetConfigParam[](0);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(caller_);
        lzDelegate.setEndpointConfig(address(1), params);
    }
}
