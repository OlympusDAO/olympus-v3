// SPDX-License-Identifier: MIT
pragma solidity >=0.8.30;

import {Owned} from "@solmate-6.2.0/auth/Owned.sol";
import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {ILZEndpointDelegate} from "src/policies/interfaces/ILZEndpointDelegate.sol";
import {ILZEndpointV2Authorized} from "src/policies/interfaces/ILZEndpointV2Authorized.sol";
import {LZConfigLib} from "src/scripts/ops/lib/LZConfigLib.sol";

/// @title LZBridgeActivator
/// @notice Single-use contract to configure and activate the LZBridgeGateway during the
///         OCG proposal. Batches all endpoint configuration, peer setup, enforced options,
///         per-endpoint bidirectional rate limits and enablement into a single proposal action,
///         working around the governor's 15-action limit.
///
/// @dev Assumes:
///      - The `admin`, `bridge_admin`, and `bridge_configurator` roles have been granted to
///        this contract for the duration of the activation. `bridge_configurator` is the role
///        that gates the privileged configuration mutators on the gateway and the LZ
///        endpoint delegate; granting it temporarily lets the activator drive setup
///        directly, without routing the calls through the LZBridgeAndDelegateConfig timelock.
///        All three are revoked immediately after `activate()`, leaving `bridge_configurator`
///        only on the LZBridgeAndDelegateConfig policy.
///      - The gateway and the LZEndpointDelegate policy have been activated in the Kernel
///        (by the DAO MS pre-OCG).
///      - The caller is this contract's owner (the OCG timelock).
///
///      `activate()` points the gateway's endpoint delegate at the LZEndpointDelegate policy and
///      drives all OApp-authorized endpoint calls through that policy (libraries, ULN/Executor config).
///      Gateway-level operations (setPeer, setEnforcedOptions, enable) are called through the
///      gateway's role-gated functions directly. The delegate assignment is the steady-state
///      configuration and is not revoked when activation completes; subsequent OApp-authorized
///      endpoint operations continue to go through LZEndpointDelegate.
contract LZBridgeActivator is Owned {
    // ========== CONSTANTS ========== //

    /// @dev Number of remote chains configured by this activator.
    uint256 internal constant _REMOTE_CHAIN_COUNT = 4;

    // ========== IMMUTABLES ========== //

    address public immutable GATEWAY;
    address public immutable DELEGATE;
    address public immutable ENDPOINT;

    address public immutable ARB_GATEWAY;
    address public immutable OPT_GATEWAY;
    address public immutable BASE_GATEWAY;
    address public immutable BERA_GATEWAY;

    // ========== STATE ========== //

    bool public isActivated;

    // ========== EVENTS & ERRORS ========== //

    event Activated(address caller);
    error AlreadyActivated();
    error InvalidParams(string reason);

    // ========== CONSTRUCTOR ========== //

    /// @param owner_ The OCG timelock address.
    /// @param gateway_ The LZBridgeGateway address on this chain.
    /// @param delegate_ The LZEndpointDelegate policy address on this chain.
    /// @param endpoint_ The LayerZero V2 endpoint address.
    /// @param arbGateway_ Remote gateway on Arbitrum.
    /// @param optGateway_ Remote gateway on Optimism.
    /// @param baseGateway_ Remote gateway on Base.
    /// @param beraGateway_ Remote gateway on Berachain.
    constructor(
        address owner_,
        address gateway_,
        address delegate_,
        address endpoint_,
        address arbGateway_,
        address optGateway_,
        address baseGateway_,
        address beraGateway_
    ) Owned(owner_) {
        _requireNonzeroAddress(owner_, "owner");
        _requireNonzeroAddress(gateway_, "gateway");
        _requireNonzeroAddress(delegate_, "delegate");
        _requireNonzeroAddress(endpoint_, "endpoint");
        _requireNonzeroAddress(arbGateway_, "arbGateway");
        _requireNonzeroAddress(optGateway_, "optGateway");
        _requireNonzeroAddress(baseGateway_, "baseGateway");
        _requireNonzeroAddress(beraGateway_, "beraGateway");
        if (endpoint_ != ILZBridgeGateway(gateway_).LZ_ENDPOINT()) revert InvalidParams("endpoint");
        if (
            endpoint_ != ILZEndpointDelegate(delegate_).LZ_ENDPOINT() ||
            gateway_ != ILZEndpointDelegate(delegate_).GATEWAY()
        ) revert InvalidParams("delegate");

        GATEWAY = gateway_;
        DELEGATE = delegate_;
        ENDPOINT = endpoint_;
        ARB_GATEWAY = arbGateway_;
        OPT_GATEWAY = optGateway_;
        BASE_GATEWAY = baseGateway_;
        BERA_GATEWAY = beraGateway_;
    }

    // ========== ACTIVATION ========== //

    /// @notice Configures and activates the LZBridgeGateway.
    /// @dev  This function assumes:
    ///       - The `admin`, `bridge_admin`, and `bridge_configurator` roles have been granted
    ///         to this contract for the duration of the activation.
    ///       - The LZEndpointDelegate policy is active in the Kernel.
    ///
    ///       This function reverts if:
    ///       - The caller is not the owner.
    ///       - The function has already been run.
    function activate() external onlyOwner {
        if (isActivated) revert AlreadyActivated();

        // Point the gateway's endpoint delegate at the LZEndpointDelegate policy so subsequent
        // OApp-authorized endpoint calls forwarded by this activator (and, after the proposal closes,
        // by the DAO MS via batches) succeed.
        ILZBridgeGateway(GATEWAY).setDelegate(DELEGATE);

        _configureLZEndpoint();
        _setPeers();
        _setEnforcedOptions();
        _setRateLimits();
        _enable();

        isActivated = true;
        emit Activated(msg.sender);
    }

    // ========== INTERNAL ========== //

    /// @dev Configures the LZ V2 endpoint via the LZEndpointDelegate policy: pin libraries and
    ///      set ULN/Executor config for all 4 remote chains.
    function _configureLZEndpoint() internal {
        ILZEndpointV2Authorized lzDelegate = ILZEndpointV2Authorized(DELEGATE);
        address sendLib = LZConfigLib.ETH_SEND_ULN_302;
        address recvLib = LZConfigLib.ETH_RECV_ULN_302;
        uint64 localConf = LZConfigLib.ETH_OUTBOUND_CONFIRMATIONS;

        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID,
            LZConfigLib.BERA_EID
        ];
        uint64[_REMOTE_CHAIN_COUNT] memory remoteConfs = [
            LZConfigLib.ARB_OUTBOUND_CONFIRMATIONS,
            LZConfigLib.OPT_OUTBOUND_CONFIRMATIONS,
            LZConfigLib.BASE_OUTBOUND_CONFIRMATIONS,
            LZConfigLib.BERA_OUTBOUND_CONFIRMATIONS
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            uint32 eid = remoteEids[i];
            address[] memory dvns = LZConfigLib.dvnsForRoute(LZConfigLib.ETH_EID, eid);

            // Pin libraries (the delegate proxies the call to the endpoint with GATEWAY as the OApp)
            lzDelegate.setSendLibrary(eid, sendLib);
            lzDelegate.setReceiveLibrary(eid, recvLib, 0);

            // Send ULN + Executor config
            SetConfigParam[] memory sendParams = new SetConfigParam[](2);
            sendParams[0] = SetConfigParam({
                eid: eid,
                configType: LZConfigLib.CONFIG_TYPE_ULN,
                config: LZConfigLib.encodeUlnConfig(localConf, dvns)
            });
            sendParams[1] = SetConfigParam({
                eid: eid,
                configType: LZConfigLib.CONFIG_TYPE_EXECUTOR,
                config: LZConfigLib.encodeExecutorConfig(LZConfigLib.ETH_EID)
            });
            lzDelegate.setEndpointConfig(sendLib, sendParams);

            // Receive ULN config
            SetConfigParam[] memory recvParams = new SetConfigParam[](1);
            recvParams[0] = SetConfigParam({
                eid: eid,
                configType: LZConfigLib.CONFIG_TYPE_ULN,
                config: LZConfigLib.encodeUlnConfig(remoteConfs[i], dvns)
            });
            lzDelegate.setEndpointConfig(recvLib, recvParams);
        }
    }

    /// @dev Sets peers on the gateway for all 4 remote chains.
    function _setPeers() internal {
        address gw = GATEWAY;

        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID,
            LZConfigLib.BERA_EID
        ];
        address[_REMOTE_CHAIN_COUNT] memory remoteGateways = [
            ARB_GATEWAY,
            OPT_GATEWAY,
            BASE_GATEWAY,
            BERA_GATEWAY
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            ILZBridgeGateway(gw).setPeer(
                remoteEids[i],
                LZConfigLib.addressToBytes32(remoteGateways[i])
            );
        }
    }

    /// @dev Sets enforced options (200k gas minimum) for all 4 remote chains.
    function _setEnforcedOptions() internal {
        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID,
            LZConfigLib.BERA_EID
        ];

        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](_REMOTE_CHAIN_COUNT);
        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            opts[i] = EnforcedOptionParam({
                eid: remoteEids[i],
                msgType: 1, // MSG_BRIDGE_OHM
                options: abi.encodePacked(
                    uint16(3), // Type 3
                    uint8(1), // WORKER_ID (Executor)
                    uint16(17), // size
                    uint8(1), // OPTION_TYPE_LZRECEIVE
                    uint128(200_000)
                )
            });
        }

        ILZBridgeGateway(GATEWAY).setEnforcedOptions(opts);
    }

    /// @dev Sets bidirectional rate limits on the gateway for all 4 remote chains.
    ///      Outbound limit applies to OHM leaving the canonical chain; inbound limit
    ///      applies to OHM arriving from a remote chain. Window and per-direction
    ///      limits are sourced from `LZConfigLib`.
    function _setRateLimits() internal {
        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID,
            LZConfigLib.BERA_EID
        ];

        IOffsettingRateLimiter.RateLimitConfig[]
            memory outConfigs = new IOffsettingRateLimiter.RateLimitConfig[](_REMOTE_CHAIN_COUNT);
        IOffsettingRateLimiter.RateLimitConfig[]
            memory inConfigs = new IOffsettingRateLimiter.RateLimitConfig[](_REMOTE_CHAIN_COUNT);

        uint32 window = LZConfigLib.RATE_LIMIT_WINDOW;

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            outConfigs[i] = IOffsettingRateLimiter.RateLimitConfig({
                eid: remoteEids[i],
                limit: LZConfigLib.outRateLimitForRoute(LZConfigLib.ETH_EID, remoteEids[i]),
                window: window
            });
            inConfigs[i] = IOffsettingRateLimiter.RateLimitConfig({
                eid: remoteEids[i],
                limit: LZConfigLib.inRateLimitForRoute(LZConfigLib.ETH_EID, remoteEids[i]),
                window: window
            });
        }

        ILZBridgeGateway(GATEWAY).setOutRateLimits(outConfigs);
        ILZBridgeGateway(GATEWAY).setInRateLimits(inConfigs);
    }

    /// @dev Enables the gateway policy.
    function _enable() internal {
        IEnabler(GATEWAY).enable("");
    }

    function _requireNonzeroAddress(address address_, string memory parameter_) private pure {
        if (address_ == address(0)) revert InvalidParams(parameter_);
    }
}
