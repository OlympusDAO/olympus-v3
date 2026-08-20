// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

// Scripting
import {console2} from "@forge-std-1.16.2/console2.sol";
import {LZBridgeTestnetBase} from "./LZBridgeTestnetBase.sol";

// Interfaces
import {ILayerZeroEndpointV2} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";
import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEndpointV2State} from "src/interfaces/layerzero/IEndpointV2State.sol";
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {ILZEndpointV2Authorized} from "src/policies/interfaces/ILZEndpointV2Authorized.sol";

// Contracts
import {Kernel, Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {LZEndpointDelegate} from "src/policies/bridge/LZEndpointDelegate.sol";
import {LZBridgeAndDelegateConfig} from "src/policies/bridge/LZBridgeAndDelegateConfig.sol";
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, BRIDGE_CONFIGURATOR_ROLE, BRIDGE_FACILITATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Local
import {LZTestnetConfig} from "./LZTestnetConfig.sol";
import {LZTestnetMockStack} from "./LZTestnetMockStack.sol";

/// @title LZBridgeTestnetDeploy
/// @notice Deploys and wires the full LayerZero V2 OHM bridge stack across three testnets
///         (Ethereum Sepolia, Base Sepolia and Arbitrum Sepolia) for end-to-end testing.
///
/// @dev This is a deploy script (not a test). It is driven by a single EOA read from the
///      environment (via `--account` / `--ledger` / `PRIVATE_KEY`). The active chain is
///      resolved from `block.chainid`, so the same script runs against whichever testnet the
///      `--chain` / `--rpc-url` selects, one chain at a time.
///
///      Unlike production, the three testnets collapse the Kernel executor, the RolesAdmin admin
///      and the DAO multisig into the same deployer EOA, so no split-by-caller flow (as in
///      `LZBridgeGatewayL2Batch`) is needed; the script asserts this in pre-flight and fails
///      loudly if run by the wrong account. On production these are distinct multisigs and the
///      MS batch flow must be used instead.
///
///      Run order:
///        1. `deploy()` on EACH of the three chains (records addresses under deployments/).
///        2. `configure()` on EACH of the three chains (peers reference the remote gateways
///           recorded in step 1, so all three must be deployed first).
///        3. (optional) `status()` to print the wired state.
contract LZBridgeTestnetDeploy is LZBridgeTestnetBase {
    // ========== STRUCTS ========== //

    /// @notice The underlying Default Framework stack the bridge plugs into.
    struct Infra {
        address kernel;
        address ohm;
        address roles;
        address mintr;
        address rolesAdmin;
    }

    /// @notice The four bridge contracts deployed by {deploy}.
    struct Deployed {
        address gateway;
        address delegate;
        address periphery;
        address config;
    }

    // ========== CONFIGURE STATE ========== //
    // Set at the top of `configure` and read by its helpers to avoid stack-too-deep.

    address internal _gateway;
    address internal _delegate;
    address internal _periphery;
    address internal _rolesAdmin;
    address internal _roles;
    address internal _endpoint;
    uint32 internal _localEid;
    uint32[] internal _remoteEids;
    address[] internal _remoteGateways;

    // ========== CONSTANTS ========== //

    uint32 internal constant _GRACE_SECONDS = 86_400;
    uint48 internal constant _TIMELOCK_DELAY = 86_400;

    // ========== ENTRY POINTS ========== //

    /// @notice Deploys the LZ bridge stack on the active chain. Deploys a minimal Kernel stack
    ///         first if the chain has no Kernel in env.json (arbitrum-sepolia).
    function deploy() external {
        string memory chain_ = _resolveChain();
        _loadEnv(chain_);

        console2.log("\n=== [LZ testnet] Deploy:", chain_, "===");
        console2.log("  Deployer:", msg.sender);

        bool isCanonical = LZTestnetConfig.eidForChain(chain_) == LZTestnetConfig.SEPOLIA_EID;

        vm.startBroadcast();
        Infra memory infra = _resolveInfra(msg.sender);
        Deployed memory dep = _deployStack(infra, isCanonical, msg.sender);
        vm.stopBroadcast();

        _writeDeployment(chain_, infra, dep, isCanonical);
    }

    /// @dev Resolves the Kernel stack from env.json, or deploys a minimal mock stack when the
    ///      chain has none. Asserts the deployer is the executor/admin for existing chains.
    function _resolveInfra(address deployer_) internal returns (Infra memory infra) {
        if (_envAddress("olympus.Kernel") == address(0)) {
            console2.log("  No Kernel in env.json: deploying minimal mock stack");
            LZTestnetMockStack.Stack memory s = LZTestnetMockStack.deploy(deployer_);
            infra = Infra({
                kernel: s.kernel,
                ohm: s.ohm,
                roles: s.roles,
                mintr: s.mintr,
                rolesAdmin: s.rolesAdmin
            });
        } else {
            infra = Infra({
                kernel: _envAddressNotZero("olympus.Kernel"),
                ohm: _envAddressNotZero("olympus.legacy.OHM"),
                roles: _envAddressNotZero("olympus.modules.OlympusRoles"),
                mintr: _envAddressNotZero("olympus.modules.OlympusMinter"),
                rolesAdmin: _envAddressNotZero("olympus.policies.RolesAdmin")
            });
            _requireCaller("KernelExecutor", Kernel(infra.kernel).executor(), deployer_);
            _requireCaller("RolesAdmin.admin", RolesAdmin(infra.rolesAdmin).admin(), deployer_);
        }
    }

    /// @dev Deploys the four bridge contracts and activates the three policies in the Kernel.
    function _deployStack(
        Infra memory infra_,
        bool isCanonical_,
        address deployer_
    ) internal returns (Deployed memory dep) {
        Kernel kernel = Kernel(infra_.kernel);

        LZBridgeGateway gateway = new LZBridgeGateway(
            kernel,
            LZTestnetConfig.TESTNET_LZ_ENDPOINT,
            isCanonical_,
            _GRACE_SECONDS
        );
        LZEndpointDelegate delegate = new LZEndpointDelegate(kernel, address(gateway));
        LZCrossChainBridge periphery = new LZCrossChainBridge(
            infra_.ohm,
            deployer_, // owner: the testnet deployer can enable/disable/rescue directly
            address(gateway),
            deployer_, // reEnabler
            _GRACE_SECONDS
        );
        LZBridgeAndDelegateConfig config = new LZBridgeAndDelegateConfig(
            kernel,
            address(gateway),
            address(delegate),
            address(periphery),
            _TIMELOCK_DELAY
        );

        // Activate the three policies in the Kernel (the periphery is not a policy).
        kernel.executeAction(Actions.ActivatePolicy, address(gateway));
        kernel.executeAction(Actions.ActivatePolicy, address(delegate));
        kernel.executeAction(Actions.ActivatePolicy, address(config));

        dep = Deployed({
            gateway: address(gateway),
            delegate: address(delegate),
            periphery: address(periphery),
            config: address(config)
        });

        console2.log("  LZBridgeGateway:", dep.gateway);
        console2.log("  LZEndpointDelegate:", dep.delegate);
        console2.log("  LZCrossChainBridge:", dep.periphery);
        console2.log("  LZBridgeAndDelegateConfig:", dep.config);
    }

    /// @notice Wires the deployed stack on the active chain: grants the bootstrap roles to the
    ///         deployer, configures the LZ endpoint (libraries, ULN/Executor, two DVNs), sets
    ///         peers, enforced options and bidirectional rate limits, then enables the delegate,
    ///         the gateway and the periphery. Requires all three chains to be deployed first.
    /// @dev Idempotent: re-running it on a live deployment re-applies the current `LZTestnetConfig`
    ///      values (skipping no-op role grants, library re-pins and enables), so it doubles as the
    ///      "set config" path after changing DVNs or any other endpoint parameter.
    function configure() external {
        string memory chain_ = _resolveChain();
        _loadEnv(chain_);
        address deployer = msg.sender;

        console2.log("\n=== [LZ testnet] Configure:", chain_, "===");

        // Load the local deployment and the remote gateways (peers).
        string memory json = _readDeployment(chain_);
        _gateway = vm.parseJsonAddress(json, ".gateway");
        _delegate = vm.parseJsonAddress(json, ".delegate");
        _periphery = vm.parseJsonAddress(json, ".periphery");
        _rolesAdmin = vm.parseJsonAddress(json, ".rolesAdmin");
        _roles = vm.parseJsonAddress(json, ".roles");
        _endpoint = LZTestnetConfig.TESTNET_LZ_ENDPOINT;
        _localEid = LZTestnetConfig.eidForChain(chain_);

        _requireCaller("RolesAdmin.admin", RolesAdmin(_rolesAdmin).admin(), deployer);
        _requireCaller("periphery.owner", LZCrossChainBridge(_periphery).owner(), deployer);

        _loadRemotes(chain_);

        vm.startBroadcast();

        _grantBootstrapRoles(deployer);

        // Enable the delegate first so its OApp-authorized setters pass the enabled gate.
        if (!IEnabler(_delegate).isEnabled()) IEnabler(_delegate).enable("");

        // Point the gateway's LZ endpoint delegate at the delegate policy, then drive all
        // endpoint configuration through it.
        if (IEndpointV2State(_endpoint).delegates(_gateway) != _delegate) {
            ILZBridgeGateway(_gateway).setDelegate(_delegate);
        }

        _configureLZ();
        _setPeers();
        _setEnforcedOptions();
        _setRateLimits();

        if (!IEnabler(_gateway).isEnabled()) IEnabler(_gateway).enable("");
        if (!IEnabler(_periphery).isEnabled()) IEnabler(_periphery).enable("");

        vm.stopBroadcast();

        console2.log("  Configure complete for", chain_);
    }

    /// @notice Prints the wired state of the active chain's bridge stack (read-only).
    function status() external {
        string memory chain_ = _resolveChain();
        _loadEnv(chain_);

        string memory json = _readDeployment(chain_);
        address gateway = vm.parseJsonAddress(json, ".gateway");
        address delegate = vm.parseJsonAddress(json, ".delegate");
        address periphery = vm.parseJsonAddress(json, ".periphery");

        console2.log("\n=== [LZ testnet] Status:", chain_, "===");
        console2.log("  gateway enabled:", IEnabler(gateway).isEnabled());
        console2.log("  delegate enabled:", IEnabler(delegate).isEnabled());
        console2.log("  periphery enabled:", IEnabler(periphery).isEnabled());

        _loadRemotes(chain_);
        for (uint256 i = 0; i < _remoteEids.length; ++i) {
            bytes32 peer = ILZBridgeGateway(gateway).peers(_remoteEids[i]);
            console2.log("  peer EID", _remoteEids[i], peer != bytes32(0) ? "set" : "MISSING");
        }
    }

    // ========== CONFIGURE HELPERS ========== //

    /// @dev Grants the bootstrap roles to the deployer (admin, bridge_admin, bridge_configurator)
    ///      and the facilitator role to the periphery so it can call burnAndSend. Each grant is
    ///      skipped when already present, since OlympusRoles reverts on a duplicate grant.
    function _grantBootstrapRoles(address deployer_) internal {
        _grantIfMissing(ADMIN_ROLE, deployer_);
        _grantIfMissing(BRIDGE_ADMIN_ROLE, deployer_);
        _grantIfMissing(BRIDGE_CONFIGURATOR_ROLE, deployer_);
        _grantIfMissing(BRIDGE_FACILITATOR_ROLE, _periphery);
    }

    function _grantIfMissing(bytes32 role_, address who_) internal {
        if (!ROLESv1(_roles).hasRole(who_, role_)) {
            RolesAdmin(_rolesAdmin).grantRole(role_, who_);
        }
    }

    /// @dev Configures send/receive libraries and ULN/Executor config for every remote, using
    ///      the two verifying DVNs shared by all three testnets (LayerZero Labs and Horizen).
    function _configureLZ() internal {
        ILZEndpointV2Authorized delegate = ILZEndpointV2Authorized(_delegate);
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(_endpoint);
        address sendLib = LZTestnetConfig.sendUln302ForEid(_localEid);
        address recvLib = LZTestnetConfig.recvUln302ForEid(_localEid);
        uint64 localConf = LZTestnetConfig.confirmationsForEid(_localEid);

        for (uint256 i = 0; i < _remoteEids.length; ++i) {
            uint32 remoteEid = _remoteEids[i];
            address[] memory dvns = LZTestnetConfig.dvnsForRoute(_localEid, remoteEid);

            // Pin libraries, skipping a no-op re-pin (the endpoint reverts with LZ_SameValue).
            if (
                endpoint.isDefaultSendLibrary(_gateway, remoteEid) ||
                endpoint.getSendLibrary(_gateway, remoteEid) != sendLib
            ) {
                delegate.setSendLibrary(remoteEid, sendLib);
            }
            (address curRecv, bool recvIsDefault) = endpoint.getReceiveLibrary(_gateway, remoteEid);
            if (recvIsDefault || curRecv != recvLib) {
                delegate.setReceiveLibrary(remoteEid, recvLib, 0);
            }

            // Send ULN + Executor config.
            SetConfigParam[] memory sendParams = new SetConfigParam[](2);
            sendParams[0] = SetConfigParam({
                eid: remoteEid,
                configType: LZTestnetConfig.CONFIG_TYPE_ULN,
                config: LZTestnetConfig.encodeUlnConfig(localConf, dvns)
            });
            sendParams[1] = SetConfigParam({
                eid: remoteEid,
                configType: LZTestnetConfig.CONFIG_TYPE_EXECUTOR,
                config: LZTestnetConfig.encodeExecutorConfig(_localEid)
            });
            delegate.setEndpointConfig(sendLib, sendParams);

            // Receive ULN config (inbound confirmations equal the remote chain's outbound count).
            SetConfigParam[] memory recvParams = new SetConfigParam[](1);
            recvParams[0] = SetConfigParam({
                eid: remoteEid,
                configType: LZTestnetConfig.CONFIG_TYPE_ULN,
                config: LZTestnetConfig.encodeUlnConfig(
                    LZTestnetConfig.confirmationsForEid(remoteEid),
                    dvns
                )
            });
            delegate.setEndpointConfig(recvLib, recvParams);

            console2.log("  Configured route to EID:", remoteEid);
        }
    }

    function _setPeers() internal {
        for (uint256 i = 0; i < _remoteEids.length; ++i) {
            ILZBridgeGateway(_gateway).setPeer(
                _remoteEids[i],
                LZTestnetConfig.addressToBytes32(_remoteGateways[i])
            );
        }
    }

    function _setEnforcedOptions() internal {
        uint8 msgType = ILZBridgeGateway(_gateway).MSG_BRIDGE_OHM();
        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](_remoteEids.length);
        for (uint256 i = 0; i < _remoteEids.length; ++i) {
            opts[i] = EnforcedOptionParam({
                eid: _remoteEids[i],
                msgType: msgType,
                // Type 3 options: WORKER_ID=1 (Executor), size=17, OPTION_TYPE_LZRECEIVE=1, gas=200k.
                options: abi.encodePacked(
                    uint16(3),
                    uint8(1),
                    uint16(17),
                    uint8(1),
                    uint128(200_000)
                )
            });
        }
        ILZBridgeGateway(_gateway).setEnforcedOptions(opts);
    }

    function _setRateLimits() internal {
        IOffsettingRateLimiter.RateLimitConfig[]
            memory outConfigs = new IOffsettingRateLimiter.RateLimitConfig[](_remoteEids.length);
        IOffsettingRateLimiter.RateLimitConfig[]
            memory inConfigs = new IOffsettingRateLimiter.RateLimitConfig[](_remoteEids.length);
        for (uint256 i = 0; i < _remoteEids.length; ++i) {
            outConfigs[i] = IOffsettingRateLimiter.RateLimitConfig({
                eid: _remoteEids[i],
                limit: LZTestnetConfig.TESTNET_RATE_LIMIT,
                window: LZTestnetConfig.RATE_LIMIT_WINDOW
            });
            inConfigs[i] = IOffsettingRateLimiter.RateLimitConfig({
                eid: _remoteEids[i],
                limit: LZTestnetConfig.TESTNET_RATE_LIMIT,
                window: LZTestnetConfig.RATE_LIMIT_WINDOW
            });
        }
        ILZBridgeGateway(_gateway).setOutRateLimits(outConfigs);
        ILZBridgeGateway(_gateway).setInRateLimits(inConfigs);
    }

    /// @dev Loads the remote chain names, their EIDs, and their gateway addresses from the
    ///      per-chain deployment files written by `deploy`.
    function _loadRemotes(string memory chain_) internal {
        string[] memory remoteChains = LZTestnetConfig.remoteChainsForChain(chain_);
        delete _remoteEids;
        delete _remoteGateways;
        for (uint256 i = 0; i < remoteChains.length; ++i) {
            _remoteEids.push(LZTestnetConfig.eidForChain(remoteChains[i]));
            _remoteGateways.push(vm.parseJsonAddress(_readDeployment(remoteChains[i]), ".gateway"));
        }
    }

    // ========== PERSISTENCE ========== //

    function _writeDeployment(
        string memory chain_,
        Infra memory infra_,
        Deployed memory dep_,
        bool isCanonical_
    ) internal {
        string memory k = "lzTestnet";
        vm.serializeAddress(k, "kernel", infra_.kernel);
        vm.serializeAddress(k, "ohm", infra_.ohm);
        vm.serializeAddress(k, "roles", infra_.roles);
        vm.serializeAddress(k, "mintr", infra_.mintr);
        vm.serializeAddress(k, "rolesAdmin", infra_.rolesAdmin);
        vm.serializeAddress(k, "gateway", dep_.gateway);
        vm.serializeAddress(k, "delegate", dep_.delegate);
        vm.serializeAddress(k, "periphery", dep_.periphery);
        vm.serializeBool(k, "isCanonical", isCanonical_);
        string memory out = vm.serializeAddress(k, "config", dep_.config);
        vm.writeJson(out, _deploymentPath(chain_));
        console2.log("  Wrote", _deploymentPath(chain_));
    }
}
