// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZEndpointDelegateTestBase} from "src/test/policies/bridge/LZEndpointDelegate/LZEndpointDelegateTestBase.sol";

// Interfaces
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

/// @dev ILZEndpointV2Authorized endpoint configuration via the LZEndpointDelegate policy: mock-based
///      verification that every external OApp-authorized call lands on the LZ endpoint with the gateway
///      passed as the OApp argument, plus role-gated access control.
contract LZEndpointDelegateTests_EndpointConfig is LZEndpointDelegateTestBase {
    function _test_setSendLibrary(address caller_) internal {
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
        vm.prank(caller_);
        lzDelegate.setSendLibrary(NONCANONICAL_EID, lib);
    }

    function test_setSendLibrary_adminCanCall() external {
        _test_setSendLibrary(admin);
    }

    function test_setSendLibrary_bridgeAdminCanCall() external {
        _test_setSendLibrary(bridgeAdmin);
    }

    function testFuzz_setSendLibrary_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        lzDelegate.setSendLibrary(NONCANONICAL_EID, address(1));
    }

    function _test_setReceiveLibrary(address caller_) internal {
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
        vm.prank(caller_);
        lzDelegate.setReceiveLibrary(NONCANONICAL_EID, lib, gracePeriod);
    }

    function test_setReceiveLibrary_adminCanCall() external {
        _test_setReceiveLibrary(admin);
    }

    function test_setReceiveLibrary_bridgeAdminCanCall() external {
        _test_setReceiveLibrary(bridgeAdmin);
    }

    function testFuzz_setReceiveLibrary_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        lzDelegate.setReceiveLibrary(NONCANONICAL_EID, address(1), 0);
    }

    function _test_setReceiveLibraryTimeout(address caller_) internal {
        address lib = address(0xBEEF);
        uint256 expiry = block.timestamp + 1 days;

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
        vm.prank(caller_);
        lzDelegate.setReceiveLibraryTimeout(NONCANONICAL_EID, lib, expiry);
    }

    function test_setReceiveLibraryTimeout_adminCanCall() external {
        _test_setReceiveLibraryTimeout(admin);
    }

    function test_setReceiveLibraryTimeout_bridgeAdminCanCall() external {
        _test_setReceiveLibraryTimeout(bridgeAdmin);
    }

    function testFuzz_setReceiveLibraryTimeout_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        lzDelegate.setReceiveLibraryTimeout(NONCANONICAL_EID, address(1), 0);
    }

    function _test_setEndpointConfig(address caller_) internal {
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
        vm.prank(caller_);
        lzDelegate.setEndpointConfig(lib, params);
    }

    function test_setEndpointConfig_adminCanCall() external {
        _test_setEndpointConfig(admin);
    }

    function test_setEndpointConfig_bridgeAdminCanCall() external {
        _test_setEndpointConfig(bridgeAdmin);
    }

    function testFuzz_setEndpointConfig_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        SetConfigParam[] memory params = new SetConfigParam[](0);
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        lzDelegate.setEndpointConfig(address(1), params);
    }
}
