// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev ILZEndpointV2Admin endpoint configuration access control.
contract LZBridgeGatewayTests_EndpointConfig is LZBridgeGatewayTestBase {
    function test_setSendLibrary_proxiesToEndpoint() external {
        address lib = address(0xBEEF);
        address endpoint_ = gateway.LZ_ENDPOINT();

        vm.mockCall(
            endpoint_,
            abi.encodeWithSignature(
                "setSendLibrary(address,uint32,address)",
                address(gateway),
                NONCANONICAL_EID,
                lib
            ),
            bytes("")
        );
        vm.expectCall(
            endpoint_,
            abi.encodeWithSignature(
                "setSendLibrary(address,uint32,address)",
                address(gateway),
                NONCANONICAL_EID,
                lib
            )
        );
        vm.prank(bridgeAdmin);
        gateway.setSendLibrary(NONCANONICAL_EID, lib);
    }

    function test_setSendLibrary_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.setSendLibrary(NONCANONICAL_EID, address(1));
    }

    function test_setReceiveLibrary_proxiesToEndpoint() external {
        address lib = address(0xBEEF);
        uint256 gracePeriod = 100;
        address endpoint_ = gateway.LZ_ENDPOINT();

        vm.mockCall(
            endpoint_,
            abi.encodeWithSignature(
                "setReceiveLibrary(address,uint32,address,uint256)",
                address(gateway),
                NONCANONICAL_EID,
                lib,
                gracePeriod
            ),
            bytes("")
        );
        vm.expectCall(
            endpoint_,
            abi.encodeWithSignature(
                "setReceiveLibrary(address,uint32,address,uint256)",
                address(gateway),
                NONCANONICAL_EID,
                lib,
                gracePeriod
            )
        );
        vm.prank(bridgeAdmin);
        gateway.setReceiveLibrary(NONCANONICAL_EID, lib, gracePeriod);
    }

    function test_setReceiveLibrary_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.setReceiveLibrary(NONCANONICAL_EID, address(1), 0);
    }

    function test_setReceiveLibraryTimeout_proxiesToEndpoint() external {
        address lib = address(0xBEEF);
        uint256 expiry = block.timestamp + 1 days;
        address endpoint_ = gateway.LZ_ENDPOINT();

        vm.mockCall(
            endpoint_,
            abi.encodeWithSignature(
                "setReceiveLibraryTimeout(address,uint32,address,uint256)",
                address(gateway),
                NONCANONICAL_EID,
                lib,
                expiry
            ),
            bytes("")
        );
        vm.expectCall(
            endpoint_,
            abi.encodeWithSignature(
                "setReceiveLibraryTimeout(address,uint32,address,uint256)",
                address(gateway),
                NONCANONICAL_EID,
                lib,
                expiry
            )
        );
        vm.prank(bridgeAdmin);
        gateway.setReceiveLibraryTimeout(NONCANONICAL_EID, lib, expiry);
    }

    function test_setReceiveLibraryTimeout_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.setReceiveLibraryTimeout(NONCANONICAL_EID, address(1), 0);
    }

    function test_setEndpointConfig_proxiesToEndpoint() external {
        address lib = address(0xBEEF);
        SetConfigParam[] memory params = new SetConfigParam[](0);
        address endpoint_ = gateway.LZ_ENDPOINT();

        vm.mockCall(
            endpoint_,
            abi.encodeWithSignature(
                "setConfig(address,address,(uint32,uint32,bytes)[])",
                address(gateway),
                lib,
                params
            ),
            bytes("")
        );
        vm.expectCall(
            endpoint_,
            abi.encodeWithSignature(
                "setConfig(address,address,(uint32,uint32,bytes)[])",
                address(gateway),
                lib,
                params
            )
        );
        vm.prank(bridgeAdmin);
        gateway.setEndpointConfig(lib, params);
    }

    function test_setEndpointConfig_revertsIfNotBridgeAdmin() external {
        SetConfigParam[] memory params = new SetConfigParam[](0);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.setEndpointConfig(address(1), params);
    }
}
