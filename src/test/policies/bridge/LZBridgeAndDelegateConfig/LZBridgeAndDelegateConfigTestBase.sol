// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

// Interfaces
import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {LZConfigLib} from "src/scripts/ops/lib/LZConfigLib.sol";
import {TestHelperOz5} from "@lz-test-devtools-8.0.1/TestHelperOz5.sol";

// Contracts
import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {LZEndpointDelegate} from "src/policies/bridge/LZEndpointDelegate.sol";
import {LZBridgeAndDelegateConfig} from "src/policies/bridge/LZBridgeAndDelegateConfig.sol";
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, BRIDGE_CONFIGURATOR_ROLE, BRIDGE_FACILITATOR_ROLE, BRIDGE_RATE_LIMITER_ROLE, EMERGENCY_ROLE, MANAGER_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

// solhint-disable max-states-count

/// @dev Shared deployment for `LZBridgeAndDelegateConfig` tests. Wires a single canonical
///      gateway / delegate / periphery-bridge triple against a mock LZ V2 endpoint, then
///      activates the config policy, grants it the `bridge_configurator` role on the
///      gateway/delegate, and bootstraps it into the periphery bridge's `configurator`.
contract LZBridgeAndDelegateConfigTestBase is TestHelperOz5 {
    uint32 constant CANONICAL_EID = 1;
    uint32 constant NONCANONICAL_EID = 2;
    uint256 constant INITIAL_AMOUNT = 100_000e9;
    uint32 constant GRACE_SECONDS = 1 days;
    uint48 constant INITIAL_TIMELOCK_DELAY = 1 days;

    uint256 constant DEFAULT_RATE_LIMIT = 1_000_000e9;
    uint32 constant DEFAULT_RATE_WINDOW = 1 days;

    // Canonical stack
    Kernel kernel;
    OlympusMinter mintr;
    OlympusRoles roles;
    RolesAdmin rolesAdmin;
    LZBridgeGateway gateway;
    LZEndpointDelegate lzDelegate;
    LZCrossChainBridge facilitator;
    LZBridgeAndDelegateConfig config;

    // Non-canonical destination stack
    Kernel kernel2;
    OlympusMinter mintr2;
    OlympusRoles roles2;
    RolesAdmin rolesAdmin2;
    LZBridgeGateway gateway2;

    MockOhm ohm;

    address admin = makeAddr("admin");
    address bridgeAdmin = makeAddr("bridgeAdmin");
    address bridgeRateLimiter = makeAddr("bridgeRateLimiter");
    address manager = makeAddr("manager");
    address emergency = makeAddr("emergency");
    address user = makeAddr("user");
    address ownerAddr = makeAddr("facilitatorOwner");

    bytes constant DEFAULT_OPTIONS =
        abi.encodePacked(uint16(3), uint8(1), uint16(17), uint8(1), uint128(200_000));

    function setUp() public virtual override {
        super.setUp();

        setUpEndpoints(2, LibraryType.UltraLightNode);
        ohm = new MockOhm("Olympus", "OHM", 9);

        // Canonical
        kernel = new Kernel();
        mintr = new OlympusMinter(kernel, address(ohm));
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        gateway = new LZBridgeGateway(
            kernel,
            address(endpointSetup.endpointList[0]),
            true,
            GRACE_SECONDS
        );
        lzDelegate = new LZEndpointDelegate(kernel, address(gateway));
        facilitator = new LZCrossChainBridge(
            address(ohm),
            ownerAddr,
            address(gateway),
            address(0),
            GRACE_SECONDS
        );
        config = new LZBridgeAndDelegateConfig(
            kernel,
            address(gateway),
            address(lzDelegate),
            address(facilitator),
            INITIAL_TIMELOCK_DELAY
        );

        kernel.executeAction(Actions.InstallModule, address(mintr));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(gateway));
        kernel.executeAction(Actions.ActivatePolicy, address(lzDelegate));
        kernel.executeAction(Actions.ActivatePolicy, address(config));

        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(BRIDGE_ADMIN_ROLE, bridgeAdmin);
        rolesAdmin.grantRole(BRIDGE_RATE_LIMITER_ROLE, bridgeRateLimiter);
        rolesAdmin.grantRole(EMERGENCY_ROLE, emergency);
        rolesAdmin.grantRole(MANAGER_ROLE, manager);
        rolesAdmin.grantRole(BRIDGE_FACILITATOR_ROLE, address(facilitator));
        // The config policy is the production holder of bridge_configurator; without this
        // grant `executeQueuedAction` would revert when the queued sub-action reaches the
        // gateway/delegate.
        rolesAdmin.grantRole(BRIDGE_CONFIGURATOR_ROLE, address(config));

        // Enable the delegate and the config policy. The delegate must be enabled before any
        // queued sub-action lands on it; the config policy must be enabled before `queue*` and
        // `executeQueuedAction` are accepted.
        vm.startPrank(admin);
        lzDelegate.enable("");
        config.enable("");
        vm.stopPrank();

        // Non-canonical destination stack (only the gateway, just enough to deliver packets).
        kernel2 = new Kernel();
        mintr2 = new OlympusMinter(kernel2, address(ohm));
        roles2 = new OlympusRoles(kernel2);
        rolesAdmin2 = new RolesAdmin(kernel2);
        gateway2 = new LZBridgeGateway(
            kernel2,
            address(endpointSetup.endpointList[1]),
            false,
            GRACE_SECONDS
        );
        kernel2.executeAction(Actions.InstallModule, address(mintr2));
        kernel2.executeAction(Actions.InstallModule, address(roles2));
        kernel2.executeAction(Actions.ActivatePolicy, address(rolesAdmin2));
        kernel2.executeAction(Actions.ActivatePolicy, address(gateway2));
        rolesAdmin2.grantRole(ADMIN_ROLE, admin);

        // Peers & enforced options under admin; gateway lifecycle under admin too.
        vm.startPrank(admin);
        gateway.setPeer(NONCANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway2)));
        gateway2.setPeer(CANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway)));

        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam({
            eid: NONCANONICAL_EID,
            msgType: gateway.MSG_BRIDGE_OHM(),
            options: DEFAULT_OPTIONS
        });
        gateway.setEnforcedOptions(opts);

        EnforcedOptionParam[] memory opts2 = new EnforcedOptionParam[](1);
        opts2[0] = EnforcedOptionParam({
            eid: CANONICAL_EID,
            msgType: gateway2.MSG_BRIDGE_OHM(),
            options: DEFAULT_OPTIONS
        });
        gateway2.setEnforcedOptions(opts2);

        gateway.enable(bytes(""));
        gateway2.enable(bytes(""));
        vm.stopPrank();

        // In the intended deployment the config policy holds the `bridge_configurator`
        // role and every `bridge_configurator`-gated gateway mutator is queued through it.
        // For setup-only steps the queue is bypassed by pranking the policy address
        // directly; a real deployment would queue these calls via the activator and
        // execute after the config's timelock.
        _executeWithoutTimelock(
            address(gateway),
            abi.encodeCall(LZBridgeGateway.setDelegate, (address(lzDelegate))),
            address(config),
            BRIDGE_CONFIGURATOR_ROLE
        );

        // Default rate limits for tests that bridge between the two endpoints.
        IOffsettingRateLimiter.RateLimitConfig[]
            memory rateConfigs = new IOffsettingRateLimiter.RateLimitConfig[](1);
        rateConfigs[0] = IOffsettingRateLimiter.RateLimitConfig({
            eid: NONCANONICAL_EID,
            limit: DEFAULT_RATE_LIMIT,
            window: DEFAULT_RATE_WINDOW
        });
        vm.startPrank(address(config));
        gateway.setOutRateLimits(rateConfigs);
        gateway.setInRateLimits(rateConfigs);
        vm.stopPrank();

        // Bootstrap the periphery bridge's configurator with the config policy.
        vm.prank(ownerAddr);
        facilitator.setConfigurator(address(config));

        // Periphery is enabled by its owner.
        vm.prank(ownerAddr);
        facilitator.enable(bytes(""));

        ohm.mint(user, INITIAL_AMOUNT);
        vm.deal(user, 100 ether);
    }

    /// @dev Pranks `caller_` and invokes `target_` with `data_`. Helper for setup steps that
    ///      bypass the timelock when modelling the deployed end-state.
    function _executeWithoutTimelock(
        address target_,
        bytes memory data_,
        address caller_,
        bytes32 /* role_ */
    ) internal {
        vm.prank(caller_);
        (bool ok, bytes memory ret) = target_.call(data_);
        // solhint-disable-next-line custom-errors,gas-custom-errors
        if (!ok) revert(string(ret));
    }

    /// @dev Warps past the configured timelock delay so a queued action is executable.
    function _warpPastTimelock() internal {
        vm.warp(vm.getBlockTimestamp() + INITIAL_TIMELOCK_DELAY + 1);
    }

    /// @dev Wraps a single (target, selector, payload) triple as a length-1 batch so a
    ///      single gateway/delegate/facilitator sub-action can be queued through `queue`.
    function _singleAction(
        address target_,
        bytes4 selector_,
        bytes memory payload_
    ) internal pure returns (ITimelockBatchQueue.BatchAction[] memory batch) {
        batch = new ITimelockBatchQueue.BatchAction[](1);
        batch[0] = ITimelockBatchQueue.BatchAction({
            target: target_,
            selector: selector_,
            payload: payload_
        });
    }

    /// @dev Asserts the standard `IPolicyAdmin.NotAuthorised` revert returned by both the
    ///      `bridge_admin`-or-`admin` and the rate-limiter-class proposer gates.
    function _expectNotAuthorized() internal {
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
    }

    /// @dev Asserts the strict `ROLES_RequireRole(admin)` revert returned by the admin-only
    ///      proposer gate.
    function _expectAdminRole() internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
    }

    /// @dev Asserts the exact `ITimelockBatchQueue_ActionInvalid(target, selector)` revert
    ///      raised by the queue-time payload-length and canonical-encoding guards, including
    ///      its parameters (not just the error selector).
    function _expectActionInvalid(address target_, bytes4 selector_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                target_,
                selector_
            )
        );
    }
}
