// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

// Interfaces
import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";
import {TestHelperOz5} from "@lz-test-devtools-8.0.1/TestHelperOz5.sol";

// Contracts
import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

contract LZCrossChainBridgeTestBase is TestHelperOz5 {
    uint32 constant CANONICAL_EID = 1;
    uint32 constant NONCANONICAL_EID = 2;
    uint256 constant SUPPLY_CAP = 100_000e9;

    Kernel kernel;
    OlympusMinter mintr;
    OlympusRoles roles;
    RolesAdmin rolesAdmin;
    LZBridgeGateway gateway;

    // Non-canonical stack for receiving
    Kernel kernel2;
    OlympusMinter mintr2;
    OlympusRoles roles2;
    RolesAdmin rolesAdmin2;
    LZBridgeGateway gateway2;

    LZCrossChainBridge bridge;
    MockOhm ohm;

    address owner;
    address admin = makeAddr("admin");
    address user = makeAddr("user");
    address recipient = makeAddr("recipient");

    /// @dev Type 3 options with 200k gas for lzReceive:
    ///      WORKER_ID=1, size=17, OPTION_TYPE_LZRECEIVE=1, gas=200k
    bytes constant DEFAULT_OPTIONS =
        abi.encodePacked(uint16(3), uint8(1), uint16(17), uint8(1), uint128(200_000));

    function setUp() public virtual override {
        super.setUp();

        // Owner is this test contract deployer
        owner = address(this);

        // Create 2 LZ V2 mock endpoints (eid=1, eid=2)
        setUpEndpoints(2, LibraryType.UltraLightNode);

        // Deploy mock tokens
        ohm = new MockOhm("Olympus", "OHM", 9);

        // Deploy canonical stack
        kernel = new Kernel();
        mintr = new OlympusMinter(kernel, address(ohm));
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        gateway = new LZBridgeGateway(kernel, address(endpointSetup.endpointList[0]), true);

        kernel.executeAction(Actions.InstallModule, address(mintr));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(gateway));

        rolesAdmin.grantRole("admin", admin);

        // Deploy non-canonical stack for destination
        kernel2 = new Kernel();
        mintr2 = new OlympusMinter(kernel2, address(ohm));
        roles2 = new OlympusRoles(kernel2);
        rolesAdmin2 = new RolesAdmin(kernel2);
        gateway2 = new LZBridgeGateway(kernel2, address(endpointSetup.endpointList[1]), false);

        kernel2.executeAction(Actions.InstallModule, address(mintr2));
        kernel2.executeAction(Actions.InstallModule, address(roles2));
        kernel2.executeAction(Actions.ActivatePolicy, address(rolesAdmin2));
        kernel2.executeAction(Actions.ActivatePolicy, address(gateway2));

        rolesAdmin2.grantRole("admin", admin);

        // Deploy bridge (periphery, owned by this test contract)
        bridge = new LZCrossChainBridge(address(ohm), owner, address(gateway));

        // Grant bridge_facilitator role to bridge on both kernels
        rolesAdmin.grantRole("bridge_facilitator", address(bridge));
        rolesAdmin2.grantRole("bridge_facilitator", address(bridge));

        // Configure gateways
        vm.startPrank(admin);
        gateway.setBridgedSupplyCap(SUPPLY_CAP);

        // Set peers
        gateway.setPeer(NONCANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway2)));
        gateway2.setPeer(CANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway)));

        // Set enforced options
        EnforcedOptionParam[] memory opts1 = new EnforcedOptionParam[](1);
        opts1[0] = EnforcedOptionParam({
            eid: NONCANONICAL_EID,
            msgType: gateway.MSG_BRIDGE_OHM(),
            options: DEFAULT_OPTIONS
        });
        gateway.setEnforcedOptions(opts1);

        EnforcedOptionParam[] memory opts2 = new EnforcedOptionParam[](1);
        opts2[0] = EnforcedOptionParam({
            eid: CANONICAL_EID,
            msgType: gateway2.MSG_BRIDGE_OHM(),
            options: DEFAULT_OPTIONS
        });
        gateway2.setEnforcedOptions(opts2);

        // Enable gateways
        gateway.enable(bytes(""));
        gateway2.enable(bytes(""));
        vm.stopPrank();

        // Configure bridge
        bridge.enable(bytes(""));

        // Mint OHM to user and approve bridge
        ohm.mint(user, 100_000e9);
        vm.prank(user);
        ohm.approve(address(bridge), type(uint256).max);

        // Fund user for native fees
        vm.deal(user, 100 ether);
    }
}
