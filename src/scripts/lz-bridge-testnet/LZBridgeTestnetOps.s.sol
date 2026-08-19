// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.30;

// Scripting
import {console2} from "@forge-std-1.16.2/console2.sol";
import {LZBridgeTestnetBase} from "./LZBridgeTestnetBase.sol";

// Interfaces
import {IEndpointV2State} from "src/interfaces/layerzero/IEndpointV2State.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {ILZEndpointDelegate} from "src/policies/interfaces/ILZEndpointDelegate.sol";
import {ILZEndpointV2Authorized} from "src/policies/interfaces/ILZEndpointV2Authorized.sol";

// Contracts
import {Kernel, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, BRIDGE_CONFIGURATOR_ROLE, BRIDGE_CHANNEL_MANAGER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Local
import {LZTestnetConfig} from "./LZTestnetConfig.sol";

/// @title LZBridgeTestnetOps
/// @notice Operational tooling for an already-deployed testnet bridge: unblock a stuck inbound
///         message and correct the canonical bridged supply after an undeliverable send, plus a
///         read-only discovery helper.
///
/// @dev The endpoint config (libraries, ULN/DVNs, Executor, peers, enforced options, rate limits)
///      is owned by the deploy script's idempotent `configure()`: to change DVNs or any other
///      endpoint parameter, edit `LZTestnetConfig` and re-run `configure`. This script holds only
///      the entry points that `configure` cannot cover, because they act on in-flight message state
///      rather than on configuration.
///
///      The local gateway address is read from `deployments/<chain>.json` (the file written by
///      `deploy`). The delegate is then read on-chain from `endpoint.delegates(gateway)` and the
///      stuck-message sender from `gateway.peers(srcEid)`, so only the local gateway needs to be
///      on file.
///
///      Every mutating entry point checks its preconditions before broadcasting and reverts with a
///      descriptive error: the gateway points at the expected endpoint, the delegate is wired and
///      enabled, the caller holds the required role, and (for supply correction) the chain is
///      canonical and the amount is in range. All privileged calls go directly through the
///      caller's roles, NOT through the `LZBridgeAndDelegateConfig` timelock.
///
///      Entry points:
///      - `skipInbound(srcChain, nonce)`  skips one stuck inbound nonce on the active
///        (destination) chain. Caller needs `admin`, `bridge_admin`, or `bridge_channel_manager`.
///      - `correctBridgedSupply(amount)`  reduces the canonical bridged supply after an
///        undeliverable send. Caller needs `bridge_configurator`; canonical chain only.
///      - `discover()`  (read-only) prints the delegate and remote peers.
contract LZBridgeTestnetOps is LZBridgeTestnetBase {
    error LZTestnet_NoDelegate(address gateway);
    error LZTestnet_NoPeer(uint32 srcEid);
    error LZTestnet_MissingRole(string role, address account);
    error LZTestnet_DelegateDisabled(address delegate);
    error LZTestnet_EndpointMismatch(address expected, address actual);
    error LZTestnet_DelegateGatewayMismatch(address delegate, address gateway);
    error LZTestnet_NotCanonical(string chain);
    error LZTestnet_ZeroAmount();
    error LZTestnet_AmountExceedsSupply(uint256 amount, uint256 supply);

    /// @notice Prints the delegate and remote peers for the active chain's gateway (read-only).
    function discover() external {
        string memory chain_ = _resolveChain();
        _loadEnv(chain_);
        address gateway = _localGateway(chain_);
        address delegate = _resolveDelegate(gateway);

        console2.log("\n=== [LZ testnet] Discover:", chain_, "===");
        console2.log("  gateway:", gateway);
        console2.log("  delegate (endpoint.delegates):", delegate);
        console2.log("  delegate enabled:", IEnabler(delegate).isEnabled());

        string[] memory remotes = LZTestnetConfig.remoteChainsForChain(chain_);
        for (uint256 i = 0; i < remotes.length; ++i) {
            uint32 eid = LZTestnetConfig.eidForChain(remotes[i]);
            bytes32 peer = ILZBridgeGateway(gateway).peers(eid);
            console2.log("  remote:", remotes[i]);
            console2.log("    eid:", eid);
            console2.log("    peer (remote gateway, bytes32):");
            console2.logBytes32(peer);
        }
    }

    /// @notice Skips a single stuck inbound nonce on the active (destination) chain.
    /// @dev The sender is read from `gateway.peers(srcEid)`. Preconditions: endpoint matches,
    ///      delegate wired and enabled, a peer exists for `srcChain_`, and the caller holds
    ///      `admin`, `bridge_admin`, or `bridge_channel_manager`. The skipped message is discarded.
    /// @param srcChain_ The source chain name the stuck message came from.
    /// @param nonce_ The inbound nonce to skip (from LayerZero Scan, e.g. 1).
    function skipInbound(string calldata srcChain_, uint64 nonce_) external {
        string memory chain_ = _resolveChain();
        _loadEnv(chain_);
        address gateway = _localGateway(chain_);
        address delegate = _resolveDelegate(gateway);
        _requireDelegateEnabled(delegate);
        _requireChannelManager(gateway);

        uint32 srcEid = LZTestnetConfig.eidForChain(srcChain_);
        bytes32 sender = ILZBridgeGateway(gateway).peers(srcEid);
        if (sender == bytes32(0)) revert LZTestnet_NoPeer(srcEid);

        console2.log("\n=== [LZ testnet] Skip inbound on:", chain_, "===");
        console2.log("  gateway:", gateway, "delegate:", delegate);
        console2.log("  srcChain:", srcChain_);
        console2.log("  srcEid:", srcEid);
        console2.log("  nonce:", nonce_);
        console2.log("  sender (peer, bytes32):");
        console2.logBytes32(sender);

        vm.startBroadcast();
        ILZEndpointV2Authorized(delegate).skip(srcEid, sender, nonce_);
        vm.stopBroadcast();

        console2.log("  Skipped. The channel can now move past this nonce.");
    }

    /// @notice Corrects the canonical bridged supply after an undeliverable message, by the amount
    ///         that was burned on the source but never minted on the destination.
    /// @dev Mirrors `LZBridgeGateway_RecoveryAfterUndeliverableMessages.t.sol`. Preconditions: the
    ///      active chain is canonical (Sepolia), the caller holds `bridge_configurator`, and
    ///      `0 < amount_ <= bridgedSupply`. Called directly on the gateway, not via the timelock.
    /// @param amount_ The OHM amount (9 decimals) of the stuck transfer to subtract.
    function correctBridgedSupply(uint256 amount_) external {
        string memory chain_ = _resolveChain();
        _loadEnv(chain_);
        address gateway = _localGateway(chain_);
        _resolveDelegate(gateway); // endpoint / delegate sanity
        if (LZTestnetConfig.eidForChain(chain_) != LZTestnetConfig.SEPOLIA_EID) {
            revert LZTestnet_NotCanonical(chain_);
        }
        _requireRole(gateway, BRIDGE_CONFIGURATOR_ROLE, "bridge_configurator");

        if (amount_ == 0) revert LZTestnet_ZeroAmount();
        uint256 current = ILZBridgeGateway(gateway).bridgedSupply();
        if (amount_ > current) revert LZTestnet_AmountExceedsSupply(amount_, current);

        console2.log("\n=== [LZ testnet] Correct bridged supply:", chain_, "===");
        console2.log("  gateway:", gateway);
        console2.log("  bridgedSupply before:", current);
        console2.log("  decrease by:", amount_);

        vm.startBroadcast();
        ILZBridgeGateway(gateway).decreaseBridgedSupply(amount_);
        vm.stopBroadcast();

        console2.log("  bridgedSupply after:", ILZBridgeGateway(gateway).bridgedSupply());
    }

    // ========== PRECONDITION HELPERS ========== //

    /// @dev Reads the active chain's gateway address from `deployments/<chain>.json`.
    function _localGateway(string memory chain_) internal view returns (address) {
        return vm.parseJsonAddress(_readDeployment(chain_), ".gateway");
    }

    /// @dev Asserts the gateway points at the expected endpoint and returns its (non-zero) LZ
    ///      endpoint delegate, asserting the delegate points back at the gateway.
    function _resolveDelegate(address gateway_) internal view returns (address delegate) {
        address endpoint = LZTestnetConfig.TESTNET_LZ_ENDPOINT;
        address gatewayEndpoint = ILZBridgeGateway(gateway_).LZ_ENDPOINT();
        if (gatewayEndpoint != endpoint) {
            revert LZTestnet_EndpointMismatch(endpoint, gatewayEndpoint);
        }
        delegate = IEndpointV2State(endpoint).delegates(gateway_);
        if (delegate == address(0)) revert LZTestnet_NoDelegate(gateway_);
        if (ILZEndpointDelegate(delegate).GATEWAY() != gateway_) {
            revert LZTestnet_DelegateGatewayMismatch(delegate, gateway_);
        }
    }

    function _requireDelegateEnabled(address delegate_) internal view {
        if (!IEnabler(delegate_).isEnabled()) revert LZTestnet_DelegateDisabled(delegate_);
    }

    /// @dev Resolves the ROLES module from the gateway's Kernel and reverts unless `msg.sender`
    ///      holds `role_`.
    function _requireRole(address gateway_, bytes32 role_, string memory label_) internal view {
        if (!_rolesModule(gateway_).hasRole(msg.sender, role_)) {
            revert LZTestnet_MissingRole(label_, msg.sender);
        }
    }

    /// @dev Reverts unless `msg.sender` holds any of the channel-management roles accepted by the
    ///      delegate's `skip` (admin, bridge_admin, or bridge_channel_manager).
    function _requireChannelManager(address gateway_) internal view {
        ROLESv1 roles = _rolesModule(gateway_);
        bool ok = roles.hasRole(msg.sender, ADMIN_ROLE) ||
            roles.hasRole(msg.sender, BRIDGE_ADMIN_ROLE) ||
            roles.hasRole(msg.sender, BRIDGE_CHANNEL_MANAGER_ROLE);
        if (!ok) {
            revert LZTestnet_MissingRole("admin|bridge_admin|bridge_channel_manager", msg.sender);
        }
    }

    function _rolesModule(address gateway_) internal view returns (ROLESv1) {
        Kernel kernel = Policy(gateway_).kernel();
        return ROLESv1(address(kernel.getModuleForKeycode(toKeycode("ROLES"))));
    }
}
