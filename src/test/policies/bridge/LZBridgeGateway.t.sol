// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {Origin, MessagingFee} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {ILayerZeroReceiver} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroReceiver.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";
import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";
import {RateLimiter} from "@lz-oapp-evm-0.4.1/oapp/utils/RateLimiter.sol";
import {TestHelperOz5, EndpointV2} from "@lz-test-devtools-8.0.1/TestHelperOz5.sol";

import {Kernel, Actions, toKeycode, Keycode, Policy, Permissions} from "src/Kernel.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {ILZEndpointV2Admin} from "src/policies/interfaces/ILZEndpointV2Admin.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
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
        gateway = new LZBridgeGateway(
            kernel,
            address(endpointSetup.endpointList[0]),
            true,
            facilitator
        );

        kernel.executeAction(Actions.InstallModule, address(mintr));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(gateway));

        rolesAdmin.grantRole("admin", admin);
        rolesAdmin.grantRole("bridge_admin", bridgeAdmin);

        // ---- Non-canonical stack (endpoint 2) ----
        kernel2 = new Kernel();
        mintr2 = new OlympusMinter(kernel2, address(ohm));
        roles2 = new OlympusRoles(kernel2);
        rolesAdmin2 = new RolesAdmin(kernel2);
        gateway2 = new LZBridgeGateway(
            kernel2,
            address(endpointSetup.endpointList[1]),
            false,
            facilitator
        );

        kernel2.executeAction(Actions.InstallModule, address(mintr2));
        kernel2.executeAction(Actions.InstallModule, address(roles2));
        kernel2.executeAction(Actions.ActivatePolicy, address(rolesAdmin2));
        kernel2.executeAction(Actions.ActivatePolicy, address(gateway2));

        rolesAdmin2.grantRole("admin", admin);
        rolesAdmin2.grantRole("bridge_admin", bridgeAdmin);

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
        vm.prank(admin);
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

/// @dev Deployment and immutable state validation.
contract LZBridgeGatewayTests_Constructor is LZBridgeGatewayTestBase {
    function test_constructor_canonical() external {
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.FacilitatorSet(facilitator);

        LZBridgeGateway fresh = new LZBridgeGateway(
            kernel,
            address(endpointSetup.endpointList[0]),
            true,
            facilitator
        );

        // Immutables
        assertEq(
            fresh.LZ_ENDPOINT(),
            address(endpointSetup.endpointList[0]),
            "LZ_ENDPOINT should be set"
        );
        assertTrue(fresh.IS_CANONICAL(), "IS_CANONICAL should be true");

        // State
        assertEq(address(fresh.kernel()), address(kernel), "Kernel should be set");
        assertEq(fresh.facilitator(), facilitator, "Facilitator should be set");
        assertFalse(fresh.isEnabled(), "Should start disabled");
        assertEq(fresh.bridgedSupply(), 0, "Bridged supply should be zero");
        assertEq(fresh.bridgedSupplyCap(), 0, "Bridged supply cap should be zero");
    }

    function test_constructor_nonCanonical() external {
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.FacilitatorSet(facilitator);

        LZBridgeGateway fresh = new LZBridgeGateway(
            kernel2,
            address(endpointSetup.endpointList[1]),
            false,
            facilitator
        );

        assertEq(address(fresh.kernel()), address(kernel2), "Kernel should be set");
        assertEq(
            fresh.LZ_ENDPOINT(),
            address(endpointSetup.endpointList[1]),
            "LZ_ENDPOINT should be the non-canonical endpoint"
        );
        assertFalse(fresh.IS_CANONICAL(), "IS_CANONICAL should be false");
        assertEq(fresh.facilitator(), facilitator, "Facilitator should be set");
        assertFalse(fresh.isEnabled(), "Should start disabled");
    }

    function test_constructor_revertsIfKernelZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector,
                "kernel"
            )
        );
        new LZBridgeGateway(Kernel(address(0)), address(1), true, facilitator);
    }

    function test_constructor_revertsIfEndpointZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector,
                "lzEndpoint"
            )
        );
        new LZBridgeGateway(kernel, address(0), true, facilitator);
    }

    function test_constructor_revertsIfFacilitatorZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector,
                "facilitator"
            )
        );
        new LZBridgeGateway(kernel, address(endpointSetup.endpointList[0]), true, address(0));
    }
}

contract LZBridgeGatewayTests_PolicySetup is LZBridgeGatewayTestBase {
    function test_configureDependencies() external view {
        assertEq(address(gateway.MINTR()), address(mintr), "MINTR should be set");
        assertEq(gateway.ohm(), address(ohm), "OHM address should be set from MINTR");
    }

    function test_requestPermissions() external view {
        Permissions[] memory perms = gateway.requestPermissions();

        assertEq(perms.length, 3, "Should request 3 permissions");
        // All three should be on MINTR keycode
        assertEq(
            Keycode.unwrap(perms[0].keycode),
            bytes5("MINTR"),
            "Permission 0 should be on MINTR"
        );
        assertEq(
            Keycode.unwrap(perms[1].keycode),
            bytes5("MINTR"),
            "Permission 1 should be on MINTR"
        );
        assertEq(
            Keycode.unwrap(perms[2].keycode),
            bytes5("MINTR"),
            "Permission 2 should be on MINTR"
        );
    }

    function test_VERSION() external view {
        (uint8 major, uint8 minor) = gateway.VERSION();
        assertEq(major, 1, "Major version should be 1");
        assertEq(minor, 0, "Minor version should be 0");
    }
}

/// @dev Enable/disable lifecycle.
contract LZBridgeGatewayTests_EnableDisable is LZBridgeGatewayTestBase {
    function test_enable() external {
        vm.startPrank(admin);
        gateway.disable(bytes(""));
        assertFalse(gateway.isEnabled(), "Should be disabled");

        gateway.enable(bytes(""));
        assertTrue(gateway.isEnabled(), "Should be enabled");
        vm.stopPrank();
    }

    function test_enable_revertsIfAlreadyEnabled() external {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotDisabled.selector));
        vm.prank(admin);
        gateway.enable(bytes(""));
    }

    function test_enable_revertsIfNotAdmin() external {
        // Disable first so enable is valid
        vm.prank(admin);
        gateway.disable(bytes(""));

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(user);
        gateway.enable(bytes(""));
    }

    function test_disable() external {
        vm.prank(admin);
        gateway.disable(bytes(""));
        assertFalse(gateway.isEnabled(), "Should be disabled");
    }

    function test_disable_revertsIfAlreadyDisabled() external {
        vm.prank(admin);
        gateway.disable(bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(admin);
        gateway.disable(bytes(""));
    }

    function test_disable_revertsIfNotAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(user);
        gateway.disable(bytes(""));
    }
}

/// @dev Outbound OHM bridging (burn + LZ send).
contract LZBridgeGatewayTests_BurnAndSend is LZBridgeGatewayTestBase {
    function test_burnAndSend_canonical() external {
        uint256 amount = 1000e9;
        uint256 facilitatorBalanceBefore = ohm.balanceOf(facilitator);

        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            amount,
            bytes("")
        );

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount);

        uint256 facilitatorEthBefore = facilitator.balance;

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyIncreased(amount);

        vm.expectEmit(true, true, true, false);
        emit ILZBridgeGateway.Sent(facilitator, amount, NONCANONICAL_EID, bytes32(0));

        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        assertEq(
            ohm.balanceOf(facilitator),
            facilitatorBalanceBefore - amount,
            "Facilitator balance should decrease by amount"
        );
        assertEq(ohm.balanceOf(address(gateway)), 0, "Gateway should have no OHM after burn");
        assertEq(gateway.bridgedSupply(), amount, "Bridged supply should increase by amount");
        assertEq(
            facilitator.balance,
            facilitatorEthBefore - fee.nativeFee,
            "Facilitator should spend exactly the native fee"
        );
        assertEq(address(gateway).balance, 0, "Gateway should hold no ETH after send");
    }

    function test_burnAndSend_nonCanonical_burnsWithoutSupplyTracking() external {
        // 1. Preparation: first bridge to non-canonical so facilitator has OHM there
        _sendCanonicalToNonCanonical(facilitator, 5000e9);

        uint256 amount = 1000e9;
        uint256 facilitatorBalanceBefore = ohm.balanceOf(facilitator);

        MessagingFee memory fee = gateway2.estimateSendFee(
            CANONICAL_EID,
            recipient,
            amount,
            bytes("")
        );

        // 2. Test: send from non-canonical back to canonical
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway2), amount);

        uint256 facilitatorEthBefore = facilitator.balance;

        gateway2.burnAndSend{value: fee.nativeFee}(
            CANONICAL_EID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        assertEq(gateway2.bridgedSupply(), 0, "Non-canonical should not track supply");
        assertEq(
            ohm.balanceOf(facilitator),
            facilitatorBalanceBefore - amount,
            "Facilitator balance should decrease by amount"
        );
        assertEq(ohm.balanceOf(address(gateway2)), 0, "Gateway2 should have no OHM after burn");
        assertEq(
            facilitator.balance,
            facilitatorEthBefore - fee.nativeFee,
            "Facilitator should spend exactly the native fee"
        );
        assertEq(address(gateway2).balance, 0, "Gateway2 should hold no ETH after send");
    }

    function test_burnAndSend_refundsExcessEth() external {
        uint256 amount = 1000e9;
        address payable refundAddr = payable(makeAddr("refundReceiver"));

        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            amount,
            bytes("")
        );

        uint256 excess = 5 ether;
        uint256 totalSent = fee.nativeFee + excess;

        uint256 refundBalanceBefore = refundAddr.balance;

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount);
        gateway.burnAndSend{value: totalSent}(
            NONCANONICAL_EID,
            recipient,
            amount,
            refundAddr,
            bytes("")
        );
        vm.stopPrank();

        uint256 refundReceived = refundAddr.balance - refundBalanceBefore;
        // Refund should be approximately the excess (minus any rounding)
        assertGe(refundReceived, excess - 0.01 ether, "Refund should return most of the excess");
        assertLe(refundReceived, totalSent, "Refund should not exceed total sent");
    }

    function test_burnAndSend_withExtraOptions() external {
        uint256 amount = 1000e9;

        // Extra Type 3 options: add 100K more lzReceive gas on top of enforced 200K
        bytes memory extraOptions = abi.encodePacked(
            uint16(3),
            uint8(1),
            uint16(17),
            uint8(1),
            uint128(100_000)
        );

        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            amount,
            extraOptions
        );

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount);
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            amount,
            payable(facilitator),
            extraOptions
        );
        vm.stopPrank();

        // Deliver packet: should succeed with combined options
        verifyPackets(NONCANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway2)));

        assertEq(ohm.balanceOf(recipient), amount, "Recipient should receive OHM");
        assertEq(gateway.bridgedSupply(), amount, "Bridged supply should increase");
    }

    function test_burnAndSend_skipsUnconfiguredRateLimits() external {
        // No rate limit configured on either gateway
        (, , uint192 limit, uint64 window) = gateway.rateLimits(NONCANONICAL_EID);
        assertEq(limit, 0, "Limit should be 0");
        assertEq(window, 0, "Window should be 0");

        // Outflow succeeds
        _sendCanonicalToNonCanonical(recipient, 1000e9);

        // Inflow succeeds
        vm.prank(recipient);
        ohm.transfer(facilitator, 1000e9);
        _sendNonCanonicalToCanonical(recipient, 1000e9);
    }

    function test_burnAndSend_canonical_inflowRateLimit() external {
        // Set rate limit on canonical for both directions
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({
            dstEid: NONCANONICAL_EID,
            limit: 10_000e9,
            window: 3600
        });
        vm.prank(admin);
        gateway.setRateLimits(configs);

        // Send some out
        _sendCanonicalToNonCanonical(recipient, 5000e9);

        (uint256 inFlight, ) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(inFlight, 5000e9, "5000e9 should be in flight");

        // Bridge back: _inflow(NONCANONICAL_EID) reduces amountInFlight for the same key
        _sendNonCanonicalToCanonical(recipient, 2000e9);

        (inFlight, ) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(inFlight, 3000e9, "Inflow should reduce in-flight");
    }

    function test_burnAndSend_nonCanonical_inflowSkipsWhenAmountInFlightZero() external {
        // Configure rate limit on non-canonical gateway for inbound from canonical
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({
            dstEid: CANONICAL_EID,
            limit: 10_000e9,
            window: 3600
        });
        vm.prank(admin);
        gateway2.setRateLimits(configs);

        // No outflow from gateway2: amountInFlight for CANONICAL_EID is 0
        (uint192 amountInFlight, , , ) = gateway2.rateLimits(CANONICAL_EID);
        assertEq(amountInFlight, 0, "amountInFlight should be 0 before inflow");

        // Send from canonical to non-canonical: gateway2 receives, _inflow hits amountInFlight == 0
        _sendCanonicalToNonCanonical(recipient, 1000e9);

        // amountInFlight remains 0: the _inflow override skipped the write
        (amountInFlight, , , ) = gateway2.rateLimits(CANONICAL_EID);
        assertEq(amountInFlight, 0, "amountInFlight should remain 0 after skipped inflow");

        // Full outflow capacity on gateway2 is still available
        (, uint256 canSend) = gateway2.getAmountCanBeSent(CANONICAL_EID);
        assertEq(canSend, 10_000e9, "Full outflow capacity should be available");
    }

    function test_burnAndSend_canonical_outflowRateLimit() external {
        // Set rate limit on canonical
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({
            dstEid: NONCANONICAL_EID,
            limit: 5_000e9,
            window: 3600
        });
        vm.prank(admin);
        gateway.setRateLimits(configs);

        // Send within limit succeeds
        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            3_000e9,
            bytes("")
        );
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 3_000e9);
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            3_000e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        (uint256 inFlight, uint256 canSend) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(inFlight, 3_000e9, "3000e9 should be in flight");
        assertEq(canSend, 2_000e9, "2000e9 should remain");

        // Send exceeding remaining limit reverts
        ohm.mint(facilitator, 2_001e9);
        fee = gateway.estimateSendFee(NONCANONICAL_EID, recipient, 2_001e9, bytes(""));
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 2_001e9);
        vm.expectRevert(abi.encodeWithSelector(RateLimiter.RateLimitExceeded.selector));
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            2_001e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_revertsIfEnforcedOptionsLackExecutorGas() external {
        // Override enforced options to Type 3 prefix only (no executor lzReceive entry).
        // The LZ endpoint executor rejects options without a gas specification.
        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam({
            eid: NONCANONICAL_EID,
            msgType: gateway.MSG_BRIDGE_OHM(),
            options: abi.encodePacked(uint16(3))
        });
        vm.prank(admin);
        gateway.setEnforcedOptions(opts);

        uint256 amount = 1000e9;

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount);

        // endpoint.send() reverts because the options contain no executor gas entry.
        // The entire burnAndSend reverts atomically (OHM burn is also rolled back).
        vm.expectRevert(abi.encodeWithSignature("Executor_NoOptions()"));
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_EID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_revertsIfInsufficientFee() external {
        uint256 amount = 1000e9;
        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            amount,
            bytes("")
        );

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount);

        // Send less ETH than required fee, so the endpoint reverts with LZ_InsufficientFee
        vm.expectRevert(
            abi.encodeWithSignature(
                "LZ_InsufficientFee(uint256,uint256,uint256,uint256)",
                fee.nativeFee,
                fee.nativeFee / 2,
                0,
                0
            )
        );
        gateway.burnAndSend{value: fee.nativeFee / 2}(
            NONCANONICAL_EID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_revertsIfZeroRecipient() external {
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 100e9);

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector, "to")
        );
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_EID,
            address(0),
            100e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_revertsIfNoPeer() external {
        // Clear peer
        vm.prank(admin);
        gateway.setPeer(NONCANONICAL_EID, bytes32(0));

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 100e9);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_NoPeer.selector,
                NONCANONICAL_EID
            )
        );
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_EID,
            recipient,
            100e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_revertsIfSupplyCapExceeded() external {
        uint256 overCap = SUPPLY_CAP + 1;
        ohm.mint(facilitator, overCap);

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), overCap);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_BridgedSupplyCapExceeded.selector,
                overCap,
                SUPPLY_CAP
            )
        );
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_EID,
            recipient,
            overCap,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_revertsIfNotEnabled() external {
        vm.prank(admin);
        gateway.disable(bytes(""));

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 100e9);

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_EID,
            recipient,
            100e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_revertsIfNotFacilitator() external {
        vm.deal(user, 10 ether);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_OnlyFacilitator.selector)
        );
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_EID,
            recipient,
            100e9,
            payable(user),
            bytes("")
        );
    }
}

/// @dev Inbound message handling (mint on receive).
contract LZBridgeGatewayTests_LzReceive is LZBridgeGatewayTestBase {
    function test_lzReceive_canonical_decrementsSupply() external {
        // 1. Preparation: bridge out first
        _sendCanonicalToNonCanonical(recipient, 5000e9);
        assertEq(gateway.bridgedSupply(), 5000e9, "Supply should be 5000e9 after send");

        // 2. Test: bridge back
        _sendNonCanonicalToCanonical(recipient, 2000e9);

        assertEq(gateway.bridgedSupply(), 3000e9, "Supply should decrease on receive");
        // Recipient got 5000e9 from first bridge + 2000e9 from second = 7000e9
        assertEq(ohm.balanceOf(recipient), 7000e9, "Recipient should have OHM from both bridges");
    }

    function test_lzReceive_nonCanonical_mintsWithoutSupplyTracking() external {
        _sendCanonicalToNonCanonical(recipient, 5000e9);

        assertEq(ohm.balanceOf(recipient), 5000e9, "Recipient should receive OHM");
        assertEq(gateway2.bridgedSupply(), 0, "Non-canonical should not track supply");
    }

    function test_lzReceive_revertsIfNotEndpoint() external {
        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway)),
            nonce: 1
        });

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_OnlyEndpoint.selector)
        );
        vm.prank(user);
        gateway2.lzReceive(origin, bytes32(0), bytes(""), address(0), bytes(""));
    }

    function test_lzReceive_revertsIfWrongPeer() external {
        address wrongSender = makeAddr("wrongSender");
        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(wrongSender),
            nonce: 1
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_OnlyPeer.selector,
                CANONICAL_EID,
                LZConfigLib.addressToBytes32(wrongSender)
            )
        );
        vm.prank(address(endpointSetup.endpointList[1]));
        gateway2.lzReceive(origin, bytes32(0), bytes(""), address(0), bytes(""));
    }

    function test_lzReceive_revertsIfInvalidMessageType() external {
        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway)),
            nonce: 1
        });

        // Encode an invalid message type
        bytes memory invalidPayload = abi.encode(uint8(99), abi.encode(recipient, uint256(100e9)));

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidMessageType.selector, 99)
        );
        vm.prank(address(endpointSetup.endpointList[1]));
        gateway2.lzReceive(origin, bytes32(0), invalidPayload, address(0), bytes(""));
    }

    function test_lzReceive_revertsIfSupplyUnderflow() external {
        // Don't bridge out first, so bridgedSupply = 0
        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway2)),
            nonce: 1
        });

        bytes memory payload = abi.encode(uint8(1), abi.encode(recipient, uint256(100e9)));

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_BridgedSupplyUnderflow.selector,
                0,
                100e9
            )
        );
        vm.prank(address(endpointSetup.endpointList[0]));
        gateway.lzReceive(origin, bytes32(0), payload, address(0), bytes(""));
    }

    function test_lzReceive_revertsIfEmptyPayload() external {
        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway)),
            nonce: 1
        });

        // Empty payload should fail ABI decoding
        vm.expectRevert();
        vm.prank(address(endpointSetup.endpointList[1]));
        gateway2.lzReceive(origin, bytes32(0), bytes(""), address(0), bytes(""));
    }

    function test_lzReceive_revertsIfPayloadDataTooShort() external {
        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway)),
            nonce: 1
        });

        // msgType=1 but inner data is only 32 bytes (address only, missing uint256 amount)
        bytes memory shortData = abi.encode(recipient);
        bytes memory payload = abi.encode(uint8(1), shortData);

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidPayload.selector)
        );
        vm.prank(address(endpointSetup.endpointList[1]));
        gateway2.lzReceive(origin, bytes32(0), payload, address(0), bytes(""));
    }

    function test_lzReceive_revertsIfPayloadDataTooLong() external {
        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway)),
            nonce: 1
        });

        // msgType=1 but inner data is 96 bytes (extra word appended)
        bytes memory longData = abi.encode(recipient, uint256(100e9), uint256(0));
        bytes memory payload = abi.encode(uint8(1), longData);

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidPayload.selector)
        );
        vm.prank(address(endpointSetup.endpointList[1]));
        gateway2.lzReceive(origin, bytes32(0), payload, address(0), bytes(""));
    }

    function test_lzReceive_revertsIfNotEnabled() external {
        vm.prank(admin);
        gateway2.disable(bytes(""));

        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway)),
            nonce: 1
        });

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(address(endpointSetup.endpointList[1]));
        gateway2.lzReceive(origin, bytes32(0), bytes(""), address(0), bytes(""));
    }
}

/// @dev Fee quoting for cross-chain sends.
contract LZBridgeGatewayTests_EstimateSendFee is LZBridgeGatewayTestBase {
    function test_estimateSendFee() external view {
        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            1000e9,
            bytes("")
        );
        assertGt(fee.nativeFee, 0, "Native fee should be non-zero");
    }

    function test_estimateSendFee_revertsIfNoPeer() external {
        vm.prank(admin);
        gateway.setPeer(NONCANONICAL_EID, bytes32(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_NoPeer.selector,
                NONCANONICAL_EID
            )
        );
        gateway.estimateSendFee(NONCANONICAL_EID, recipient, 1000e9, bytes(""));
    }
}

/// @dev Peer registration and removal.
contract LZBridgeGatewayTests_SetPeer is LZBridgeGatewayTestBase {
    function test_setPeer() external {
        bytes32 newPeer = LZConfigLib.addressToBytes32(makeAddr("newPeer"));

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.PeerSet(uint32(42), newPeer);

        vm.prank(admin);
        gateway.setPeer(uint32(42), newPeer);

        assertEq(gateway.peers(uint32(42)), newPeer, "Peer should be set");
    }

    function test_setPeer_clears() external {
        vm.prank(admin);
        gateway.setPeer(NONCANONICAL_EID, bytes32(0));

        assertEq(gateway.peers(NONCANONICAL_EID), bytes32(0), "Peer should be cleared");
    }

    function test_setPeer_revertsIfNotAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(user);
        gateway.setPeer(uint32(42), bytes32(uint256(1)));
    }
}

/// @dev LZ endpoint delegate assignment.
contract LZBridgeGatewayTests_SetDelegate is LZBridgeGatewayTestBase {
    function test_setDelegate() external {
        address newDelegate = makeAddr("newDelegate");

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.DelegateSet(newDelegate);

        vm.prank(bridgeAdmin);
        gateway.setDelegate(newDelegate);
    }

    function test_setDelegate_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.setDelegate(makeAddr("delegate2"));
    }
}

/// @dev Facilitator address management.
contract LZBridgeGatewayTests_SetFacilitator is LZBridgeGatewayTestBase {
    function test_setFacilitator() external {
        address newFac = makeAddr("newFac");

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.FacilitatorSet(newFac);

        vm.prank(admin);
        gateway.setFacilitator(newFac);

        assertEq(gateway.facilitator(), newFac, "Facilitator should be updated");
    }

    function test_setFacilitator_revertsIfZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector,
                "facilitator"
            )
        );
        vm.prank(admin);
        gateway.setFacilitator(address(0));
    }

    function test_setFacilitator_revertsIfNotAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(user);
        gateway.setFacilitator(makeAddr("x"));
    }
}

/// @dev Bridged supply tracking and cap enforcement.
contract LZBridgeGatewayTests_SetBridgedSupply is LZBridgeGatewayTestBase {
    function test_setBridgedSupply() external {
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplySet(42e9);

        vm.prank(bridgeAdmin);
        gateway.setBridgedSupply(42e9);

        assertEq(gateway.bridgedSupply(), 42e9, "Bridged supply should be set");
    }

    function test_setBridgedSupply_revertsIfNotCanonical() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_NotCanonical.selector)
        );
        vm.prank(bridgeAdmin);
        gateway2.setBridgedSupply(100);
    }

    function test_setBridgedSupply_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.setBridgedSupply(100);
    }

    function test_setBridgedSupplyCap() external {
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyCapSet(1_000_000);

        vm.prank(admin);
        gateway.setBridgedSupplyCap(1_000_000);

        assertEq(gateway.bridgedSupplyCap(), 1_000_000, "Cap should be set");
    }

    function test_setBridgedSupplyCap_lessThanCurrentSupplyPreventsNewBridgings() external {
        // 1. Preparation: build up bridged supply
        uint256 bridgedAmount = 10_000e9;
        _sendCanonicalToNonCanonical(recipient, bridgedAmount);
        assertEq(gateway.bridgedSupply(), bridgedAmount, "Bridged supply should match");

        // Set cap below current bridged supply
        uint256 lowCap = 5_000e9;
        vm.prank(admin);
        gateway.setBridgedSupplyCap(lowCap);

        // 2. Test: new bridgings should revert due to cap exceeded
        uint256 newAmount = 1e9;
        ohm.mint(facilitator, newAmount);

        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            newAmount,
            bytes("")
        );

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), newAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_BridgedSupplyCapExceeded.selector,
                bridgedAmount + newAmount,
                lowCap
            )
        );
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            newAmount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_setBridgedSupplyCap_revertsIfNotCanonical() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_NotCanonical.selector)
        );
        vm.prank(admin);
        gateway2.setBridgedSupplyCap(100);
    }

    function test_setBridgedSupplyCap_revertsIfNotAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(user);
        gateway.setBridgedSupplyCap(100_000e9);
    }
}

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

    function test_setEnforcedOptions_revertsIfNotAdmin() external {
        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam({
            eid: uint32(42),
            msgType: uint16(1),
            options: DEFAULT_OPTIONS
        });

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(user);
        gateway.setEnforcedOptions(opts);
    }
}

/// @dev Enforced + extra option merging.
contract LZBridgeGatewayTests_CombineOptions is LZBridgeGatewayTestBase {
    function test_combineOptions_enforcedOnly() external view {
        // Enforced options are set for NONCANONICAL_EID, MSG_BRIDGE_OHM in setUp
        bytes memory combined = gateway.combineOptions(
            NONCANONICAL_EID,
            gateway.MSG_BRIDGE_OHM(),
            bytes("")
        );
        assertEq(combined, DEFAULT_OPTIONS, "Should return enforced options");
    }

    function test_combineOptions_extraOnly() external view {
        // No enforced options for eid=42
        bytes memory extra = DEFAULT_OPTIONS;
        bytes memory combined = gateway.combineOptions(uint32(42), uint16(1), extra);
        assertEq(combined, extra, "Should return extra options when no enforced");
    }

    function test_combineOptions_bothCombined() external view {
        // Extra Type 3 options with 100k gas lzReceive
        bytes memory extra = abi.encodePacked(
            uint16(3),
            uint8(1),
            uint16(17),
            uint8(1),
            uint128(100_000)
        );
        bytes memory combined = gateway.combineOptions(
            NONCANONICAL_EID,
            gateway.MSG_BRIDGE_OHM(),
            extra
        );
        // Should be enforced + extra[2:]
        bytes memory expected = bytes.concat(
            DEFAULT_OPTIONS,
            abi.encodePacked(uint8(1), uint16(17), uint8(1), uint128(100_000))
        );
        assertEq(combined, expected, "Should combine enforced + extra");
    }

    function test_combineOptions_noEnforcedNoExtra_returnsEmpty() external view {
        // eid=42 has no enforced options configured, empty extra
        bytes memory combined = gateway.combineOptions(uint32(42), uint16(1), bytes(""));
        assertEq(combined.length, 0, "Should return empty bytes");
    }

    function test_combineOptions_revertsIfExtraNotType3() external {
        bytes memory notType3 = abi.encodePacked(uint16(1), uint128(200_000));

        // combineOptions is a view function, so use try/catch via low-level call
        (bool success, bytes memory returnData) = address(gateway).call(
            abi.encodeWithSelector(
                gateway.combineOptions.selector,
                NONCANONICAL_EID,
                gateway.MSG_BRIDGE_OHM(),
                notType3
            )
        );
        assertFalse(success, "Should revert with invalid options");
        assertEq(
            bytes4(returnData),
            ILZBridgeGateway.LZBridgeGateway_InvalidOptions.selector,
            "Should revert with InvalidOptions"
        );
    }

    function test_combineOptions_revertsIfExtraIs1Byte() external {
        bytes memory oneByte = abi.encodePacked(uint8(3));

        (bool success, bytes memory returnData) = address(gateway).call(
            abi.encodeWithSelector(
                gateway.combineOptions.selector,
                NONCANONICAL_EID,
                gateway.MSG_BRIDGE_OHM(),
                oneByte
            )
        );
        assertFalse(success, "Should revert with 1-byte extra options");
        assertEq(
            bytes4(returnData),
            ILZBridgeGateway.LZBridgeGateway_InvalidOptions.selector,
            "Should revert with InvalidOptions"
        );
    }
}

/// @dev Setting rate limits.
contract LZBridgeGatewayTests_SetRateLimits is LZBridgeGatewayTestBase {
    function test_setRateLimits() external {
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({
            dstEid: NONCANONICAL_EID,
            limit: 10_000e9,
            window: 3600
        });

        vm.expectEmit(true, true, true, true);
        emit RateLimiter.RateLimitsChanged(configs);

        vm.prank(admin);
        gateway.setRateLimits(configs);

        (uint192 amountInFlight, , uint192 limit, uint64 window) = gateway.rateLimits(
            NONCANONICAL_EID
        );
        assertEq(limit, 10_000e9, "Limit should be set");
        assertEq(window, 3600, "Window should be set");
        assertEq(amountInFlight, 0, "AmountInFlight should be 0");
    }

    function test_setRateLimits_revertsIfNotAdmin() external {
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({
            dstEid: NONCANONICAL_EID,
            limit: 10_000e9,
            window: 3600
        });

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(user);
        gateway.setRateLimits(configs);
    }
}

/// @dev Emergency rate limit reset.
contract LZBridgeGatewayTests_ResetRateLimits is LZBridgeGatewayTestBase {
    function test_resetRateLimits() external {
        // Configure rate limit
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({
            dstEid: NONCANONICAL_EID,
            limit: 1_000e9,
            window: 3600
        });
        vm.prank(admin);
        gateway.setRateLimits(configs);

        // Use up the full limit
        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            1_000e9,
            bytes("")
        );
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 1_000e9);
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            1_000e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        // Verify limit is exhausted
        (, uint256 canSend) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(canSend, 0, "Should be exhausted");

        // Reset
        uint32[] memory eids = new uint32[](1);
        eids[0] = NONCANONICAL_EID;

        vm.expectEmit(true, true, true, true);
        emit RateLimiter.RateLimitsReset(eids);

        vm.prank(bridgeAdmin);
        gateway.resetRateLimits(eids);

        // amountInFlight should be 0, full limit available
        (uint192 amountInFlight, , uint192 limit, uint64 window) = gateway.rateLimits(
            NONCANONICAL_EID
        );
        assertEq(amountInFlight, 0, "amountInFlight should be reset");
        assertEq(limit, 1_000e9, "Limit should be preserved");
        assertEq(window, 3600, "Window should be preserved");

        (, canSend) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(canSend, 1_000e9, "Full limit should be available after reset");
    }

    function test_resetRateLimits_revertsIfNotBridgeAdmin() external {
        uint32[] memory eids = new uint32[](1);
        eids[0] = NONCANONICAL_EID;

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.resetRateLimits(eids);
    }
}

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

/// @dev ILZEndpointV2Admin message management access control.
contract LZBridgeGatewayTests_LZMessageManagement is LZBridgeGatewayTestBase {
    function test_skip_proxiesToEndpoint() external {
        bytes32 sender = LZConfigLib.addressToBytes32(address(gateway2));
        uint64 nonce = 1;
        address endpoint_ = gateway.LZ_ENDPOINT();

        vm.mockCall(
            endpoint_,
            abi.encodeWithSignature(
                "skip(address,uint32,bytes32,uint64)",
                address(gateway),
                NONCANONICAL_EID,
                sender,
                nonce
            ),
            bytes("")
        );
        vm.prank(bridgeAdmin);
        gateway.skip(NONCANONICAL_EID, sender, nonce);
    }

    function test_skip_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.skip(NONCANONICAL_EID, bytes32(uint256(1)), 1);
    }

    function test_nilify_proxiesToEndpoint() external {
        bytes32 sender = LZConfigLib.addressToBytes32(address(gateway2));
        uint64 nonce = 1;
        bytes32 payloadHash = keccak256("test");
        address endpoint_ = gateway.LZ_ENDPOINT();

        vm.mockCall(
            endpoint_,
            abi.encodeWithSignature(
                "nilify(address,uint32,bytes32,uint64,bytes32)",
                address(gateway),
                NONCANONICAL_EID,
                sender,
                nonce,
                payloadHash
            ),
            bytes("")
        );
        vm.prank(bridgeAdmin);
        gateway.nilify(NONCANONICAL_EID, sender, nonce, payloadHash);
    }

    function test_nilify_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.nilify(NONCANONICAL_EID, bytes32(uint256(1)), 1, bytes32(uint256(1)));
    }

    function test_burn_proxiesToEndpoint() external {
        bytes32 sender = LZConfigLib.addressToBytes32(address(gateway2));
        uint64 nonce = 1;
        bytes32 payloadHash = keccak256("test");
        address endpoint_ = gateway.LZ_ENDPOINT();

        vm.mockCall(
            endpoint_,
            abi.encodeWithSignature(
                "burn(address,uint32,bytes32,uint64,bytes32)",
                address(gateway),
                NONCANONICAL_EID,
                sender,
                nonce,
                payloadHash
            ),
            bytes("")
        );
        vm.prank(bridgeAdmin);
        gateway.burn(NONCANONICAL_EID, sender, nonce, payloadHash);
    }

    function test_burn_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.burn(NONCANONICAL_EID, bytes32(uint256(1)), 1, bytes32(uint256(1)));
    }

    function test_clear_proxiesToEndpoint() external {
        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway2)),
            nonce: 1
        });
        bytes32 guid = bytes32(uint256(42));
        bytes memory message = bytes("test_message");
        address endpoint_ = gateway.LZ_ENDPOINT();

        vm.mockCall(
            endpoint_,
            abi.encodeWithSignature(
                "clear(address,(uint32,bytes32,uint64),bytes32,bytes)",
                address(gateway),
                origin,
                guid,
                message
            ),
            bytes("")
        );
        vm.prank(bridgeAdmin);
        gateway.clear(origin, guid, message);
    }

    function test_clear_revertsIfNotBridgeAdmin() external {
        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: bytes32(uint256(1)),
            nonce: 1
        });
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.clear(origin, bytes32(0), bytes(""));
    }
}

/// @dev Public view function verification.
contract LZBridgeGatewayTests_View is LZBridgeGatewayTestBase {
    function test_allowInitializePath_validPeer() external view {
        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway2)),
            nonce: 0
        });
        assertTrue(gateway.allowInitializePath(origin), "Should allow valid peer");
    }

    function test_allowInitializePath_noPeer() external view {
        Origin memory origin = Origin({
            srcEid: uint32(42),
            sender: LZConfigLib.addressToBytes32(address(gateway2)),
            nonce: 0
        });
        assertFalse(gateway.allowInitializePath(origin), "Should not allow unknown peer");
    }

    function test_nextNonce_returnsZero() external view {
        assertEq(
            gateway.nextNonce(NONCANONICAL_EID, bytes32(0)),
            0,
            "Should return 0 (unordered messaging)"
        );
    }

    function test_LZ_ENDPOINT() external view {
        assertEq(
            gateway.LZ_ENDPOINT(),
            address(endpointSetup.endpointList[0]),
            "LZ_ENDPOINT should match endpoint"
        );
    }

    function test_IS_CANONICAL() external view {
        assertTrue(gateway.IS_CANONICAL(), "Canonical gateway should return true");
        assertFalse(gateway2.IS_CANONICAL(), "Non-canonical gateway should return false");
    }

    function test_MINTR() external view {
        assertEq(address(gateway.MINTR()), address(mintr), "MINTR should match deployed module");
    }

    function test_ohm() external view {
        assertEq(gateway.ohm(), address(ohm), "OHM should match token address");
    }

    function test_facilitator() external view {
        assertEq(gateway.facilitator(), facilitator, "Facilitator should match configured address");
    }

    function test_bridgedSupply() external view {
        assertEq(gateway.bridgedSupply(), 0, "Bridged supply should be zero initially");
    }

    function test_bridgedSupplyCap() external view {
        assertEq(
            gateway.bridgedSupplyCap(),
            SUPPLY_CAP,
            "Bridged supply cap should match setUp value"
        );
    }

    function test_MSG_BRIDGE_OHM() external view {
        assertEq(gateway.MSG_BRIDGE_OHM(), 1, "MSG_BRIDGE_OHM should be 1");
    }

    function test_peers() external view {
        assertEq(
            gateway.peers(NONCANONICAL_EID),
            LZConfigLib.addressToBytes32(address(gateway2)),
            "Peer should match non-canonical gateway"
        );
    }

    function test_getAmountCanBeSent() external {
        // Configure rate limit: 10_000e9 over 1 hour
        uint192 limit = 10_000e9;
        uint64 window = 1 hours;
        _setRateLimit(NONCANONICAL_EID, limit, window);

        (uint256 currentInFlight, uint256 canSend) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(currentInFlight, 0, "No amount should be in flight initially");
        assertEq(canSend, limit, "Full limit should be available");
    }
}

/// @dev ERC-165 interface detection.
contract LZBridgeGatewayTests_SupportsInterface is LZBridgeGatewayTestBase {
    function test_supportsInterface_ILZBridgeGateway() external view {
        assertTrue(
            gateway.supportsInterface(type(ILZBridgeGateway).interfaceId),
            "Should support ILZBridgeGateway"
        );
    }

    function test_supportsInterface_ILZEndpointV2Admin() external view {
        assertTrue(
            gateway.supportsInterface(type(ILZEndpointV2Admin).interfaceId),
            "Should support ILZEndpointV2Admin"
        );
    }

    function test_supportsInterface_ILayerZeroReceiver() external view {
        assertTrue(
            gateway.supportsInterface(type(ILayerZeroReceiver).interfaceId),
            "Should support ILayerZeroReceiver"
        );
    }

    function test_supportsInterface_IVersioned() external view {
        assertTrue(
            gateway.supportsInterface(type(IVersioned).interfaceId),
            "Should support IVersioned"
        );
    }

    function test_supportsInterface_IEnabler() external view {
        assertTrue(
            gateway.supportsInterface(type(IEnabler).interfaceId),
            "Should support IEnabler"
        );
    }

    function test_supportsInterface_ERC165() external view {
        assertTrue(gateway.supportsInterface(bytes4(0x01ffc9a7)), "Should support ERC-165");
    }

    function test_supportsInterface_unsupported() external view {
        assertFalse(
            gateway.supportsInterface(bytes4(0xdeadbeef)),
            "Should not support random interface"
        );
    }
}

/// @dev Full canonical <-> non-canonical round trip.
contract LZBridgeGatewayTests_EndToEndWithMock is LZBridgeGatewayTestBase {
    function test_roundTrip_canonicalToNonCanonicalAndBack() external {
        uint256 sendAmount = 10_000e9;

        // 1. Bridge canonical -> non-canonical
        _sendCanonicalToNonCanonical(recipient, sendAmount);

        assertEq(gateway.bridgedSupply(), sendAmount, "Canonical supply should increase");
        assertEq(
            ohm.balanceOf(recipient),
            sendAmount,
            "Recipient should receive OHM on non-canonical"
        );

        // 2. Bridge non-canonical -> canonical (bridge back half)
        uint256 returnAmount = 5_000e9;

        // Recipient needs to give OHM to facilitator first
        vm.prank(recipient);
        ohm.transfer(facilitator, returnAmount);

        _sendNonCanonicalToCanonical(recipient, returnAmount);

        assertEq(
            gateway.bridgedSupply(),
            sendAmount - returnAmount,
            "Canonical supply should decrease"
        );
        assertEq(ohm.balanceOf(recipient), sendAmount, "Recipient should have original + returned");
    }

    function test_canonicalToNonCanonical() external {
        uint256 amount = 5_000e9;
        uint256 facilitatorBalanceBefore = ohm.balanceOf(facilitator);

        _sendCanonicalToNonCanonical(recipient, amount);

        assertEq(
            ohm.balanceOf(facilitator),
            facilitatorBalanceBefore - amount,
            "Facilitator should have less OHM"
        );
        assertEq(
            ohm.balanceOf(recipient),
            amount,
            "Recipient should receive minted OHM on non-canonical"
        );
        assertEq(gateway.bridgedSupply(), amount, "Canonical bridgedSupply should increase");
        assertEq(gateway2.bridgedSupply(), 0, "Non-canonical bridgedSupply should remain zero");
    }

    function test_nonCanonicalToCanonical() external {
        // 1. Preparation: bridge OHM to non-canonical so there's bridgedSupply
        uint256 amount = 5_000e9;
        _sendCanonicalToNonCanonical(recipient, amount);
        assertEq(gateway.bridgedSupply(), amount, "Bridged supply after outbound");
        assertEq(ohm.balanceOf(recipient), amount, "Recipient should have OHM on non-canonical");

        // 2. Test: send OHM back from non-canonical to canonical
        vm.prank(recipient);
        ohm.transfer(facilitator, amount);

        _sendNonCanonicalToCanonical(user, amount);

        // Verify
        assertEq(ohm.balanceOf(user), amount, "User should receive OHM on canonical");
        assertEq(gateway.bridgedSupply(), 0, "Canonical bridgedSupply should return to 0");
    }
}
