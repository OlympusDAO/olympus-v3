// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev Type 3 enforced option configuration.
contract LZBridgeGatewayTests_EnforcedOptions is LZBridgeGatewayTestBase {
    function test_setEnforcedOptions() external {
        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam({
            eid: uint32(42),
            msgType: uint16(1),
            options: DEFAULT_OPTIONS
        });

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.EnforcedOptionsSet(opts);

        vm.prank(admin);
        gateway.setEnforcedOptions(opts);

        bytes memory stored = gateway.enforcedOptions(uint32(42), uint16(1));
        assertEq(stored, DEFAULT_OPTIONS, "Options should be stored");
    }

    function test_setEnforcedOptions_revertsIfNotType3() external {
        // Type 1 options (not Type 3)
        bytes memory type1Options = abi.encodePacked(uint16(1), uint128(200_000));

        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam({eid: uint32(42), msgType: uint16(1), options: type1Options});

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidOptions.selector,
                type1Options
            )
        );
        vm.prank(admin);
        gateway.setEnforcedOptions(opts);
    }

    function test_setEnforcedOptions_revertsIfOptionsEmpty() external {
        bytes memory emptyOptions = "";

        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam({eid: uint32(42), msgType: uint16(1), options: emptyOptions});

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidOptions.selector,
                emptyOptions
            )
        );
        vm.prank(admin);
        gateway.setEnforcedOptions(opts);
    }

    function test_setEnforcedOptions_revertsIfOptionsShorterThanType3Prefix() external {
        // A single byte is too short to carry the 2-byte Type 3 prefix.
        bytes memory shortOptions = hex"03";

        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam({eid: uint32(42), msgType: uint16(1), options: shortOptions});

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidOptions.selector,
                shortOptions
            )
        );
        vm.prank(admin);
        gateway.setEnforcedOptions(opts);
    }

    function testFuzz_setEnforcedOptions_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);

        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam({
            eid: uint32(42),
            msgType: uint16(1),
            options: DEFAULT_OPTIONS
        });

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        gateway.setEnforcedOptions(opts);
    }
}
