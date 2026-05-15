// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {UlnConfig} from "@lz-evm-messagelib-v2-3.0.162/uln/UlnBase.sol";
import {ILayerZeroEndpointV2} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";
import {Test} from "forge-std/Test.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {LZConfigLib} from "src/scripts/ops/lib/LZConfigLib.sol";
import {ILayerZeroDVNState} from "src/interfaces/layerzero/ILayerZeroDVNState.sol";
import {IUlnConfigState} from "src/interfaces/layerzero/IUlnConfigState.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZEndpointDelegate} from "src/policies/bridge/LZEndpointDelegate.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, BRIDGE_FACILITATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

/// @notice Fork-based tests for LZ V2 endpoint configuration on Ethereum, Arbitrum, Optimism, Base.
/// @dev Validates the security-hardened configuration procedure using production DVN/Executor
///      addresses. All endpoint config is forwarded through the LZEndpointDelegate policy, which is
///      set as the gateway's LZ endpoint delegate during stack deployment.
contract LZBridgeGatewayForkTests_LZConfig is Test {
    // =========== TEST CONSTANTS =========== //

    uint256 constant CHAIN_COUNT = 4;
    uint256 constant MINT_AMOUNT = 10_000e9;
    uint256 constant SUPPLY_CAP = 100_000e9;

    // =========== FORKS =========== //

    uint256 ethForkId;
    uint256 arbForkId;
    uint256 optForkId;
    uint256 baseForkId;

    // =========== PER-CHAIN CONTRACTS =========== //

    MockOhm ethOhm;
    Kernel ethKernel;
    OlympusMinter ethMintr;
    OlympusRoles ethRoles;
    RolesAdmin ethRolesAdmin;
    LZBridgeGateway ethGateway;
    LZEndpointDelegate ethLzAdmin;
    LZCrossChainBridge ethBridge;

    MockOhm arbOhm;
    Kernel arbKernel;
    OlympusMinter arbMintr;
    OlympusRoles arbRoles;
    RolesAdmin arbRolesAdmin;
    LZBridgeGateway arbGateway;
    LZEndpointDelegate arbLzAdmin;
    LZCrossChainBridge arbBridge;

    MockOhm optOhm;
    Kernel optKernel;
    OlympusMinter optMintr;
    OlympusRoles optRoles;
    RolesAdmin optRolesAdmin;
    LZBridgeGateway optGateway;
    LZEndpointDelegate optLzAdmin;
    LZCrossChainBridge optBridge;

    MockOhm baseOhm;
    Kernel baseKernel;
    OlympusMinter baseMintr;
    OlympusRoles baseRoles;
    RolesAdmin baseRolesAdmin;
    LZBridgeGateway baseGateway;
    LZEndpointDelegate baseLzAdmin;
    LZCrossChainBridge baseBridge;

    // =========== HELPERS =========== //

    address admin;
    address bridgeAdmin;
    address sender;
    address recipient;

    uint32 constant GRACE_SECONDS = 1 days;

    // =========== setUp =========== //

    function setUp() public {
        ethForkId = vm.createFork("mainnet");
        arbForkId = vm.createFork("arbitrum");
        optForkId = vm.createFork("optimism");
        baseForkId = vm.createFork("base");

        admin = makeAddr("admin");
        bridgeAdmin = makeAddr("bridgeAdmin");
        sender = makeAddr("sender");
        recipient = makeAddr("recipient");
        vm.makePersistent(admin);
        vm.makePersistent(bridgeAdmin);
        vm.makePersistent(sender);
        vm.makePersistent(recipient);

        // Deploy stacks on each fork
        vm.selectFork(ethForkId);
        _deployEthStack();

        vm.selectFork(arbForkId);
        _deployArbStack();

        vm.selectFork(optForkId);
        _deployOptStack();

        vm.selectFork(baseForkId);
        _deployBaseStack();

        // Set peers (full mesh)
        _crossPeer(
            ethForkId,
            ethGateway,
            LZConfigLib.ARB_EID,
            arbForkId,
            arbGateway,
            LZConfigLib.ETH_EID
        );
        _crossPeer(
            ethForkId,
            ethGateway,
            LZConfigLib.OPT_EID,
            optForkId,
            optGateway,
            LZConfigLib.ETH_EID
        );
        _crossPeer(
            ethForkId,
            ethGateway,
            LZConfigLib.BASE_EID,
            baseForkId,
            baseGateway,
            LZConfigLib.ETH_EID
        );
        _crossPeer(
            arbForkId,
            arbGateway,
            LZConfigLib.OPT_EID,
            optForkId,
            optGateway,
            LZConfigLib.ARB_EID
        );
        _crossPeer(
            arbForkId,
            arbGateway,
            LZConfigLib.BASE_EID,
            baseForkId,
            baseGateway,
            LZConfigLib.ARB_EID
        );
        _crossPeer(
            optForkId,
            optGateway,
            LZConfigLib.BASE_EID,
            baseForkId,
            baseGateway,
            LZConfigLib.OPT_EID
        );
    }

    // =========== DEPLOY HELPERS =========== //

    struct ChainStack {
        MockOhm ohm;
        Kernel kernel;
        OlympusMinter mintr;
        OlympusRoles roles;
        RolesAdmin rolesAdmin;
        LZBridgeGateway gateway;
        LZEndpointDelegate lzDelegate;
        LZCrossChainBridge bridge;
    }

    function _deployStack(
        bool isCanonical_,
        uint32 localEid_
    ) internal returns (ChainStack memory s) {
        s.ohm = new MockOhm("OHM", "OHM", 9);
        s.kernel = new Kernel();
        s.mintr = new OlympusMinter(s.kernel, address(s.ohm));
        s.roles = new OlympusRoles(s.kernel);
        s.rolesAdmin = new RolesAdmin(s.kernel);
        s.gateway = new LZBridgeGateway(
            s.kernel,
            LZConfigLib.endpointForEid(localEid_),
            isCanonical_,
            GRACE_SECONDS
        );
        s.lzDelegate = new LZEndpointDelegate(s.kernel, address(s.gateway));

        s.kernel.executeAction(Actions.InstallModule, address(s.mintr));
        s.kernel.executeAction(Actions.InstallModule, address(s.roles));
        s.kernel.executeAction(Actions.ActivatePolicy, address(s.rolesAdmin));
        s.kernel.executeAction(Actions.ActivatePolicy, address(s.gateway));
        s.kernel.executeAction(Actions.ActivatePolicy, address(s.lzDelegate));
        s.rolesAdmin.grantRole(ADMIN_ROLE, admin);
        s.rolesAdmin.grantRole(BRIDGE_ADMIN_ROLE, bridgeAdmin);

        s.bridge = new LZCrossChainBridge(
            address(s.ohm),
            admin,
            address(s.gateway),
            admin,
            GRACE_SECONDS
        );
        s.rolesAdmin.grantRole(BRIDGE_FACILITATOR_ROLE, address(s.bridge));

        vm.startPrank(admin);
        s.gateway.setDelegate(address(s.lzDelegate));
        s.gateway.enable(bytes(""));
        s.bridge.enable(bytes(""));
        vm.stopPrank();

        s.ohm.mint(sender, MINT_AMOUNT);
        vm.deal(sender, 100 ether);

        _makePersistent(
            s.ohm,
            s.kernel,
            s.mintr,
            s.roles,
            s.rolesAdmin,
            s.gateway,
            s.lzDelegate,
            s.bridge
        );
    }

    function _deployEthStack() internal {
        ChainStack memory s = _deployStack(true, LZConfigLib.ETH_EID);
        ethOhm = s.ohm;
        ethKernel = s.kernel;
        ethMintr = s.mintr;
        ethRoles = s.roles;
        ethRolesAdmin = s.rolesAdmin;
        ethGateway = s.gateway;
        ethLzAdmin = s.lzDelegate;
        ethBridge = s.bridge;
    }

    function _deployArbStack() internal {
        ChainStack memory s = _deployStack(false, LZConfigLib.ARB_EID);
        arbOhm = s.ohm;
        arbKernel = s.kernel;
        arbMintr = s.mintr;
        arbRoles = s.roles;
        arbRolesAdmin = s.rolesAdmin;
        arbGateway = s.gateway;
        arbLzAdmin = s.lzDelegate;
        arbBridge = s.bridge;
    }

    function _deployOptStack() internal {
        ChainStack memory s = _deployStack(false, LZConfigLib.OPT_EID);
        optOhm = s.ohm;
        optKernel = s.kernel;
        optMintr = s.mintr;
        optRoles = s.roles;
        optRolesAdmin = s.rolesAdmin;
        optGateway = s.gateway;
        optLzAdmin = s.lzDelegate;
        optBridge = s.bridge;
    }

    function _deployBaseStack() internal {
        ChainStack memory s = _deployStack(false, LZConfigLib.BASE_EID);
        baseOhm = s.ohm;
        baseKernel = s.kernel;
        baseMintr = s.mintr;
        baseRoles = s.roles;
        baseRolesAdmin = s.rolesAdmin;
        baseGateway = s.gateway;
        baseLzAdmin = s.lzDelegate;
        baseBridge = s.bridge;
    }

    function _makePersistent(
        MockOhm ohm_,
        Kernel kernel_,
        OlympusMinter mintr_,
        OlympusRoles roles_,
        RolesAdmin rolesAdmin_,
        LZBridgeGateway gateway_,
        LZEndpointDelegate lzDelegate_,
        LZCrossChainBridge bridge_
    ) internal {
        vm.makePersistent(address(ohm_));
        vm.makePersistent(address(kernel_));
        vm.makePersistent(address(mintr_));
        vm.makePersistent(address(roles_));
        vm.makePersistent(address(rolesAdmin_));
        vm.makePersistent(address(gateway_));
        vm.makePersistent(address(lzDelegate_));
        vm.makePersistent(address(bridge_));
    }

    function _crossPeer(
        uint256 forkA,
        LZBridgeGateway gwA,
        uint32 eidB,
        uint256 forkB,
        LZBridgeGateway gwB,
        uint32 eidA
    ) internal {
        vm.selectFork(forkA);
        vm.prank(admin);
        gwA.setPeer(eidB, LZConfigLib.addressToBytes32(address(gwB)));

        vm.selectFork(forkB);
        vm.prank(admin);
        gwB.setPeer(eidA, LZConfigLib.addressToBytes32(address(gwA)));
    }

    // =========== LOOKUP HELPERS =========== //

    function _allEids() internal pure returns (uint32[CHAIN_COUNT] memory eids) {
        eids[0] = LZConfigLib.ETH_EID;
        eids[1] = LZConfigLib.ARB_EID;
        eids[2] = LZConfigLib.OPT_EID;
        eids[3] = LZConfigLib.BASE_EID;
    }

    function _forkId(uint32 eid) internal view returns (uint256) {
        if (eid == LZConfigLib.ETH_EID) return ethForkId;
        if (eid == LZConfigLib.ARB_EID) return arbForkId;
        if (eid == LZConfigLib.OPT_EID) return optForkId;
        if (eid == LZConfigLib.BASE_EID) return baseForkId;
        revert("unknown eid");
    }

    function _gateway(uint32 eid) internal view returns (LZBridgeGateway) {
        if (eid == LZConfigLib.ETH_EID) return ethGateway;
        if (eid == LZConfigLib.ARB_EID) return arbGateway;
        if (eid == LZConfigLib.OPT_EID) return optGateway;
        if (eid == LZConfigLib.BASE_EID) return baseGateway;
        revert("unknown eid");
    }

    function _lzDelegate(uint32 eid) internal view returns (LZEndpointDelegate) {
        if (eid == LZConfigLib.ETH_EID) return ethLzAdmin;
        if (eid == LZConfigLib.ARB_EID) return arbLzAdmin;
        if (eid == LZConfigLib.OPT_EID) return optLzAdmin;
        if (eid == LZConfigLib.BASE_EID) return baseLzAdmin;
        revert("unknown eid");
    }

    // =========== CHAIN CONFIG PROCEDURE =========== //

    /// @dev Pins libraries and sets DVN/Executor config for all remote chains by forwarding
    ///      the calls through the LZEndpointDelegate policy (the gateway's LZ endpoint delegate).
    function _configureChain(uint32 localEid) internal {
        vm.selectFork(_forkId(localEid));
        LZEndpointDelegate lzDelegate_ = _lzDelegate(localEid);
        address sendLib = LZConfigLib.sendUln302ForEid(localEid);
        address recvLib = LZConfigLib.recvUln302ForEid(localEid);
        uint64 sendConf = LZConfigLib.outboundConfirmationsForEid(localEid);

        uint32[CHAIN_COUNT] memory eids = _allEids();

        vm.startPrank(bridgeAdmin);
        for (uint256 i = 0; i < CHAIN_COUNT; ++i) {
            if (eids[i] == localEid) continue;
            uint32 remoteEid = eids[i];
            address[] memory dvns = LZConfigLib.dvnsForRoute(localEid, remoteEid);

            // Pin libraries via the delegate policy
            lzDelegate_.setSendLibrary(remoteEid, sendLib);
            lzDelegate_.setReceiveLibrary(remoteEid, recvLib, 0);

            // Send config (ULN + Executor)
            SetConfigParam[] memory sendParams = new SetConfigParam[](2);
            sendParams[0] = SetConfigParam({
                eid: remoteEid,
                configType: LZConfigLib.CONFIG_TYPE_ULN,
                config: LZConfigLib.encodeUlnConfig(sendConf, dvns)
            });
            sendParams[1] = SetConfigParam({
                eid: remoteEid,
                configType: LZConfigLib.CONFIG_TYPE_EXECUTOR,
                config: LZConfigLib.encodeExecutorConfig(localEid)
            });
            lzDelegate_.setEndpointConfig(sendLib, sendParams);

            // Receive config (ULN only)
            uint64 recvConf = LZConfigLib.outboundConfirmationsForEid(remoteEid);
            SetConfigParam[] memory recvParams = new SetConfigParam[](1);
            recvParams[0] = SetConfigParam({
                eid: remoteEid,
                configType: LZConfigLib.CONFIG_TYPE_ULN,
                config: LZConfigLib.encodeUlnConfig(recvConf, dvns)
            });
            lzDelegate_.setEndpointConfig(recvLib, recvParams);
        }
        vm.stopPrank();
    }

    /// @dev Verifies that libraries are pinned and configs are stored for all remote EIDs.
    function _verifyChainConfig(uint32 localEid) internal {
        vm.selectFork(_forkId(localEid));
        ILayerZeroEndpointV2 ep = ILayerZeroEndpointV2(LZConfigLib.endpointForEid(localEid));
        LZBridgeGateway gw = _gateway(localEid);
        address sendLib = LZConfigLib.sendUln302ForEid(localEid);
        address recvLib = LZConfigLib.recvUln302ForEid(localEid);

        uint32[CHAIN_COUNT] memory eids = _allEids();
        for (uint256 i = 0; i < CHAIN_COUNT; ++i) {
            if (eids[i] == localEid) continue;
            uint32 remoteEid = eids[i];

            // Send library pinned
            assertEq(ep.getSendLibrary(address(gw), remoteEid), sendLib, "send lib pinned");

            // Receive library pinned (not default)
            (address rLib, bool isDefault) = ep.getReceiveLibrary(address(gw), remoteEid);
            assertEq(rLib, recvLib, "recv lib pinned");
            assertFalse(isDefault, "recv lib should not be default");

            // Send ULN config stored
            bytes memory sCfg = ep.getConfig(
                address(gw),
                sendLib,
                remoteEid,
                LZConfigLib.CONFIG_TYPE_ULN
            );
            assertGt(sCfg.length, 0, "send ULN config stored");

            // Executor config stored
            bytes memory eCfg = ep.getConfig(
                address(gw),
                sendLib,
                remoteEid,
                LZConfigLib.CONFIG_TYPE_EXECUTOR
            );
            assertGt(eCfg.length, 0, "executor config stored");

            // Receive ULN config stored
            bytes memory rCfg = ep.getConfig(
                address(gw),
                recvLib,
                remoteEid,
                LZConfigLib.CONFIG_TYPE_ULN
            );
            assertGt(rCfg.length, 0, "recv ULN config stored");

            // Send/Recv app-level ULN configs must pin optional DVNs to NIL so the app does
            // not inherit LayerZero's EID-level default.
            UlnConfig memory sendApp = IUlnConfigState(sendLib).getAppUlnConfig(
                address(gw),
                remoteEid
            );
            assertEq(
                sendApp.optionalDVNCount,
                type(uint8).max,
                "send app optionalDVNCount must be NIL"
            );
            assertEq(sendApp.optionalDVNs.length, 0, "send app optionalDVNs must be empty");
            assertEq(sendApp.optionalDVNThreshold, 0, "send app optional threshold must be 0");

            UlnConfig memory recvApp = IUlnConfigState(recvLib).getAppUlnConfig(
                address(gw),
                remoteEid
            );
            assertEq(
                recvApp.optionalDVNCount,
                type(uint8).max,
                "recv app optionalDVNCount must be NIL"
            );
            assertEq(recvApp.optionalDVNs.length, 0, "recv app optionalDVNs must be empty");
            assertEq(recvApp.optionalDVNThreshold, 0, "recv app optional threshold must be 0");
        }
    }

    // =========== TESTS =========== //

    /// @notice Verifies that production DVN contracts exist on each chain and report the
    ///         correct vid (V1 endpoint ID).
    function test_dvnContracts_haveCorrectVid() external {
        uint32[CHAIN_COUNT] memory eids = _allEids();
        uint16[CHAIN_COUNT] memory v1ChainIds = [
            LZConfigLib.ETH_CHAIN_ID,
            LZConfigLib.ARB_CHAIN_ID,
            LZConfigLib.OPT_CHAIN_ID,
            LZConfigLib.BASE_CHAIN_ID
        ];

        for (uint256 i = 0; i < CHAIN_COUNT; ++i) {
            vm.selectFork(_forkId(eids[i]));

            // LZ Labs DVN
            address lzDvn = LZConfigLib.lzDvnForEid(eids[i]);
            uint32 lzVid = ILayerZeroDVNState(lzDvn).vid();
            assertEq(lzVid, uint32(v1ChainIds[i]), "LZ DVN vid should match LZ chain ID");

            // Google Cloud DVN
            uint32 gcVid = ILayerZeroDVNState(LZConfigLib.gcloudDvnForEid(eids[i])).vid();
            assertEq(gcVid, uint32(v1ChainIds[i]), "GCLOUD DVN vid should match LZ chain ID");
        }
    }

    /// @notice Before any configuration, gateways use default LZ libraries (drag-along vulnerable).
    function test_givenNoConfig_allChainsUseDefaults() external {
        uint32[CHAIN_COUNT] memory eids = _allEids();

        for (uint256 i = 0; i < CHAIN_COUNT; ++i) {
            vm.selectFork(_forkId(eids[i]));
            ILayerZeroEndpointV2 ep = ILayerZeroEndpointV2(LZConfigLib.endpointForEid(eids[i]));
            LZBridgeGateway gw = _gateway(eids[i]);

            // For any remote EID, receive library should be default
            uint32 someRemoteEid = (eids[i] == LZConfigLib.ETH_EID)
                ? LZConfigLib.ARB_EID
                : LZConfigLib.ETH_EID;
            (, bool isDefault) = ep.getReceiveLibrary(address(gw), someRemoteEid);
            assertTrue(isDefault, "receive library should be default before config");
        }
    }

    /// @notice After configuration, all chains have libraries pinned (not default).
    function test_givenConfig_allChainsLibrariesPinned() external {
        uint32[CHAIN_COUNT] memory eids = _allEids();

        // Configure all chains
        for (uint256 i = 0; i < CHAIN_COUNT; ++i) {
            _configureChain(eids[i]);
        }

        // Verify all chains
        for (uint256 i = 0; i < CHAIN_COUNT; ++i) {
            _verifyChainConfig(eids[i]);
        }
    }

    /// @notice Full setup procedure: configure + verify all chains.
    function test_fullSetupProcedure_verifyAllChains() external {
        _configureChain(LZConfigLib.ETH_EID);
        _configureChain(LZConfigLib.ARB_EID);
        _configureChain(LZConfigLib.OPT_EID);
        _configureChain(LZConfigLib.BASE_EID);

        _verifyChainConfig(LZConfigLib.ETH_EID);
        _verifyChainConfig(LZConfigLib.ARB_EID);
        _verifyChainConfig(LZConfigLib.OPT_EID);
        _verifyChainConfig(LZConfigLib.BASE_EID);
    }

    /// @notice Verifies that confirmation numbers match symmetry:
    ///         send confirmations on chain A for chain B == receive confirmations on chain B from A.
    function test_configSymmetry_sendMatchesReceive() external {
        uint32[CHAIN_COUNT] memory eids = _allEids();

        // Configure all chains
        for (uint256 i = 0; i < CHAIN_COUNT; ++i) {
            _configureChain(eids[i]);
        }

        for (uint256 i = 0; i < CHAIN_COUNT; ++i) {
            for (uint256 j = 0; j < CHAIN_COUNT; ++j) {
                if (i == j) continue;

                uint32 eidA = eids[i];
                uint32 eidB = eids[j];

                // Read send ULN config from chain A for chain B
                vm.selectFork(_forkId(eidA));
                ILayerZeroEndpointV2 epA = ILayerZeroEndpointV2(LZConfigLib.endpointForEid(eidA));
                bytes memory sendCfg = epA.getConfig(
                    address(_gateway(eidA)),
                    LZConfigLib.sendUln302ForEid(eidA),
                    eidB,
                    LZConfigLib.CONFIG_TYPE_ULN
                );

                // Read receive ULN config from chain B for chain A
                vm.selectFork(_forkId(eidB));
                ILayerZeroEndpointV2 epB = ILayerZeroEndpointV2(LZConfigLib.endpointForEid(eidB));
                bytes memory recvCfg = epB.getConfig(
                    address(_gateway(eidB)),
                    LZConfigLib.recvUln302ForEid(eidB),
                    eidA,
                    LZConfigLib.CONFIG_TYPE_ULN
                );

                UlnConfig memory sendUln = abi.decode(sendCfg, (UlnConfig));
                UlnConfig memory recvUln = abi.decode(recvCfg, (UlnConfig));

                assertEq(
                    sendUln.confirmations,
                    recvUln.confirmations,
                    "send conf on A must match recv conf on B"
                );
            }
        }
    }

    /// @notice Verifies that hardcoded library addresses match on-chain defaults.
    function test_libraryAddressesMatchDefaults() external {
        uint32[CHAIN_COUNT] memory eids = _allEids();

        for (uint256 i = 0; i < CHAIN_COUNT; ++i) {
            vm.selectFork(_forkId(eids[i]));
            ILayerZeroEndpointV2 ep = ILayerZeroEndpointV2(LZConfigLib.endpointForEid(eids[i]));

            // Pick any remote EID to query the default
            uint32 someRemoteEid = (eids[i] == LZConfigLib.ETH_EID)
                ? LZConfigLib.ARB_EID
                : LZConfigLib.ETH_EID;

            // Default send library should match our hardcoded constant
            address defaultSendLib = ep.defaultSendLibrary(someRemoteEid);
            assertEq(
                defaultSendLib,
                LZConfigLib.sendUln302ForEid(eids[i]),
                "hardcoded sendUln302 should match on-chain default"
            );

            // Default receive library should match our hardcoded constant
            address defaultRecvLib = ep.defaultReceiveLibrary(someRemoteEid);
            assertEq(
                defaultRecvLib,
                LZConfigLib.recvUln302ForEid(eids[i]),
                "hardcoded recvUln302 should match on-chain default"
            );
        }
    }
}
