// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

// Interfaces
import {MessagingFee} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";
import {RateLimiter} from "@lz-oapp-evm-0.4.1/oapp/utils/RateLimiter.sol";
import {TestHelperOz5} from "@lz-test-devtools-8.0.1/TestHelperOz5.sol";

// Contracts
import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

// solhint-disable max-states-count

contract LZBridgeGatewayTestBase is TestHelperOz5 {
    uint32 constant CANONICAL_EID = 1;
    uint32 constant NONCANONICAL_EID = 2;
    uint256 constant INITIAL_AMOUNT = 100_000e9;
    uint256 constant SUPPLY_CAP = 1_000_000e9;

    // Canonical stack (eid=1)
    Kernel kernel;
    OlympusMinter mintr;
    OlympusRoles roles;
    RolesAdmin rolesAdmin;
    LZBridgeGateway gateway;

    // Non-canonical stack (eid=2)
    Kernel kernel2;
    OlympusMinter mintr2;
    OlympusRoles roles2;
    RolesAdmin rolesAdmin2;
    LZBridgeGateway gateway2;

    MockOhm ohm;

    address admin = makeAddr("admin");
    address bridgeAdmin = makeAddr("bridgeAdmin");
    address facilitator = makeAddr("facilitator");
    address user = makeAddr("user");
    address recipient = makeAddr("recipient");

    /// @dev Type 3 options with 200k gas for lzReceive:
    ///      WORKER_ID=1, size=17 (16 bytes gas + 1 byte optionType), OPTION_TYPE_LZRECEIVE=1, gas=200k
    bytes constant DEFAULT_OPTIONS =
        abi.encodePacked(uint16(3), uint8(1), uint16(17), uint8(1), uint128(200_000));

    function setUp() public virtual override {
        super.setUp();

        // Create 2 LZ V2 mock endpoints (eid=1, eid=2)
        setUpEndpoints(2, LibraryType.UltraLightNode);

        // Deploy mock OHM token
        ohm = new MockOhm("Olympus", "OHM", 9);

        // ---- Canonical stack (endpoint 1) ----
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
        rolesAdmin.grantRole("bridge_admin", bridgeAdmin);
        rolesAdmin.grantRole("bridge_facilitator", facilitator);

        // ---- Non-canonical stack (endpoint 2) ----
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
        rolesAdmin2.grantRole("bridge_admin", bridgeAdmin);
        rolesAdmin2.grantRole("bridge_facilitator", facilitator);

        // ---- Wire peers ----
        vm.startPrank(admin);
        gateway.setPeer(NONCANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway2)));
        gateway2.setPeer(CANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway)));

        // Set enforced options
        EnforcedOptionParam[] memory enforcedOpts = new EnforcedOptionParam[](1);
        enforcedOpts[0] = EnforcedOptionParam({
            eid: NONCANONICAL_EID,
            msgType: gateway.MSG_BRIDGE_OHM(),
            options: DEFAULT_OPTIONS
        });
        gateway.setEnforcedOptions(enforcedOpts);

        EnforcedOptionParam[] memory enforcedOpts2 = new EnforcedOptionParam[](1);
        enforcedOpts2[0] = EnforcedOptionParam({
            eid: CANONICAL_EID,
            msgType: gateway2.MSG_BRIDGE_OHM(),
            options: DEFAULT_OPTIONS
        });
        gateway2.setEnforcedOptions(enforcedOpts2);

        // Set bridged supply cap on canonical
        gateway.setBridgedSupplyCap(SUPPLY_CAP);

        // Enable gateways
        gateway.enable(bytes(""));
        gateway2.enable(bytes(""));
        vm.stopPrank();

        // Mint OHM and fund facilitator
        ohm.mint(facilitator, INITIAL_AMOUNT);
        vm.deal(facilitator, 100 ether);
    }

    function _setRateLimit(uint32 dstEid_, uint192 limit_, uint64 window_) internal {
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({dstEid: dstEid_, limit: limit_, window: window_});
        vm.prank(bridgeAdmin);
        gateway.setRateLimits(configs);
    }

    /// @dev Get fee + send from canonical to non-canonical
    function _sendCanonicalToNonCanonical(
        address to_,
        uint256 amount_
    ) internal returns (MessagingFee memory fee) {
        fee = gateway.estimateSendFee(NONCANONICAL_EID, to_, amount_, bytes(""));

        // Transfer OHM to gateway, then call burnAndSend
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount_);
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            to_,
            amount_,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        // Deliver packet
        verifyPackets(NONCANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway2)));
    }

    /// @dev Get fee + send from non-canonical to canonical
    function _sendNonCanonicalToCanonical(
        address to_,
        uint256 amount_
    ) internal returns (MessagingFee memory fee) {
        fee = gateway2.estimateSendFee(CANONICAL_EID, to_, amount_, bytes(""));

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway2), amount_);
        gateway2.burnAndSend{value: fee.nativeFee}(
            CANONICAL_EID,
            to_,
            amount_,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        // Deliver packet
        verifyPackets(CANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway)));
    }
}
