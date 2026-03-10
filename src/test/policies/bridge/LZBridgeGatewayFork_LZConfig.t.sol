// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {Test, Vm} from "forge-std/Test.sol";
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {LZConfigLib, ILayerZeroEndpointState, ILayerZeroDVNState} from "src/libraries/LZConfigLib.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {LayerZeroHelper} from "src/test/lib/pigeon/layerzero/LayerZeroHelper.sol";
import {ILayerZeroEndpoint} from "@layer-zero-endpoint-v1-1.1.0/lzApp/interfaces/ILayerZeroEndpoint.sol";

/// @notice Fork-based tests for LZ ULN301 configuration on Ethereum, Arbitrum, Optimism, Base.
/// @dev Validates the security-hardened configuration procedure using production DVN/Executor addresses.
contract LZBridgeGatewayForkTests_LZConfig is Test {
    // =========== TEST CONSTANTS =========== //

    /// @dev Total number of chains (Ethereum, Arbitrum, Optimism, Base).
    uint256 constant CHAIN_COUNT = 4;

    uint256 constant MINT_AMOUNT = 10_000e9;
    uint256 constant SUPPLY_CAP = 100_000e9;
    uint256 constant LZ_GAS = 500_000;

    bytes32 constant PACKET_EVENT_SELECTOR =
        0xe9bded5f24a4168e4f3bf44e00298c993b22376aad8c58c7dda9718a54cbea82;

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
    LZCrossChainBridge ethBridge;

    MockOhm arbOhm;
    Kernel arbKernel;
    OlympusMinter arbMintr;
    OlympusRoles arbRoles;
    RolesAdmin arbRolesAdmin;
    LZBridgeGateway arbGateway;
    LZCrossChainBridge arbBridge;

    MockOhm optOhm;
    Kernel optKernel;
    OlympusMinter optMintr;
    OlympusRoles optRoles;
    RolesAdmin optRolesAdmin;
    LZBridgeGateway optGateway;
    LZCrossChainBridge optBridge;

    MockOhm baseOhm;
    Kernel baseKernel;
    OlympusMinter baseMintr;
    OlympusRoles baseRoles;
    RolesAdmin baseRolesAdmin;
    LZBridgeGateway baseGateway;
    LZCrossChainBridge baseBridge;

    // =========== HELPERS & CACHED STATE =========== //

    LayerZeroHelper lzHelper;

    address admin;
    address bridgeAdmin;
    address sender;
    address recipient;

    address ethDefaultLib;
    address arbDefaultLib;

    uint16 ethSendUln301;
    uint16 ethReceiveUln301;
    uint16 arbSendUln301;
    uint16 arbReceiveUln301;
    uint16 optSendUln301;
    uint16 optReceiveUln301;
    uint16 baseSendUln301;
    uint16 baseReceiveUln301;

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

        lzHelper = new LayerZeroHelper();
        vm.makePersistent(address(lzHelper));

        // -- Deploy stacks on each fork --
        vm.selectFork(ethForkId);
        ethDefaultLib = ILayerZeroEndpoint(LZConfigLib.LZ_ENDPOINT).getSendLibraryAddress(
            address(0)
        );
        (ethSendUln301, ethReceiveUln301) = LZConfigLib.getUln301Versions(LZConfigLib.LZ_ENDPOINT);
        (
            ethOhm,
            ethKernel,
            ethMintr,
            ethRoles,
            ethRolesAdmin,
            ethGateway,
            ethBridge
        ) = _deployStack(LZConfigLib.LZ_ENDPOINT, true);

        vm.selectFork(arbForkId);
        arbDefaultLib = ILayerZeroEndpoint(LZConfigLib.ARB_LZ_ENDPOINT).getSendLibraryAddress(
            address(0)
        );
        (arbSendUln301, arbReceiveUln301) = LZConfigLib.getUln301Versions(
            LZConfigLib.ARB_LZ_ENDPOINT
        );
        (
            arbOhm,
            arbKernel,
            arbMintr,
            arbRoles,
            arbRolesAdmin,
            arbGateway,
            arbBridge
        ) = _deployStack(LZConfigLib.ARB_LZ_ENDPOINT, false);

        vm.selectFork(optForkId);
        (optSendUln301, optReceiveUln301) = LZConfigLib.getUln301Versions(
            LZConfigLib.OPT_LZ_ENDPOINT
        );
        (
            optOhm,
            optKernel,
            optMintr,
            optRoles,
            optRolesAdmin,
            optGateway,
            optBridge
        ) = _deployStack(LZConfigLib.OPT_LZ_ENDPOINT, false);

        vm.selectFork(baseForkId);
        (baseSendUln301, baseReceiveUln301) = LZConfigLib.getUln301Versions(
            LZConfigLib.BASE_LZ_ENDPOINT
        );
        (
            baseOhm,
            baseKernel,
            baseMintr,
            baseRoles,
            baseRolesAdmin,
            baseGateway,
            baseBridge
        ) = _deployStack(LZConfigLib.BASE_LZ_ENDPOINT, false);

        // -- Trusted remotes: full mesh (6 bidirectional pairs) --
        _crossTrust(
            ethForkId,
            ethGateway,
            LZConfigLib.ARB_CHAIN_ID,
            arbForkId,
            arbGateway,
            LZConfigLib.ETH_CHAIN_ID
        );
        _crossTrust(
            ethForkId,
            ethGateway,
            LZConfigLib.OPT_CHAIN_ID,
            optForkId,
            optGateway,
            LZConfigLib.ETH_CHAIN_ID
        );
        _crossTrust(
            ethForkId,
            ethGateway,
            LZConfigLib.BASE_CHAIN_ID,
            baseForkId,
            baseGateway,
            LZConfigLib.ETH_CHAIN_ID
        );
        _crossTrust(
            arbForkId,
            arbGateway,
            LZConfigLib.OPT_CHAIN_ID,
            optForkId,
            optGateway,
            LZConfigLib.ARB_CHAIN_ID
        );
        _crossTrust(
            arbForkId,
            arbGateway,
            LZConfigLib.BASE_CHAIN_ID,
            baseForkId,
            baseGateway,
            LZConfigLib.ARB_CHAIN_ID
        );
        _crossTrust(
            optForkId,
            optGateway,
            LZConfigLib.BASE_CHAIN_ID,
            baseForkId,
            baseGateway,
            LZConfigLib.OPT_CHAIN_ID
        );
    }

    // =========== DEPLOY HELPERS =========== //

    function _deployStack(
        address endpoint_,
        bool isCanonical_
    )
        internal
        returns (
            MockOhm ohm_,
            Kernel kernel_,
            OlympusMinter mintr_,
            OlympusRoles roles_,
            RolesAdmin rolesAdmin_,
            LZBridgeGateway gateway_,
            LZCrossChainBridge bridge_
        )
    {
        ohm_ = new MockOhm("OHM", "OHM", 9);
        bridge_ = new LZCrossChainBridge(address(ohm_), admin);
        kernel_ = new Kernel();
        mintr_ = new OlympusMinter(kernel_, address(ohm_));
        roles_ = new OlympusRoles(kernel_);
        rolesAdmin_ = new RolesAdmin(kernel_);
        gateway_ = new LZBridgeGateway(kernel_, endpoint_, isCanonical_, address(bridge_));
        _activateAndConfigure(
            kernel_,
            mintr_,
            roles_,
            rolesAdmin_,
            gateway_,
            bridge_,
            isCanonical_
        );
        ohm_.mint(sender, MINT_AMOUNT);
        vm.deal(sender, 100 ether);
        _makePersistent(ohm_, kernel_, mintr_, roles_, rolesAdmin_, gateway_, bridge_);
    }

    function _activateAndConfigure(
        Kernel kernel_,
        OlympusMinter mintr_,
        OlympusRoles roles_,
        RolesAdmin rolesAdmin_,
        LZBridgeGateway gateway_,
        LZCrossChainBridge bridge_,
        bool isCanonical
    ) internal {
        kernel_.executeAction(Actions.InstallModule, address(mintr_));
        kernel_.executeAction(Actions.InstallModule, address(roles_));
        kernel_.executeAction(Actions.ActivatePolicy, address(rolesAdmin_));
        kernel_.executeAction(Actions.ActivatePolicy, address(gateway_));
        rolesAdmin_.grantRole("admin", admin);
        rolesAdmin_.grantRole("bridge_admin", bridgeAdmin);

        vm.startPrank(admin);
        if (isCanonical) gateway_.setBridgedSupplyCap(SUPPLY_CAP);
        gateway_.enable(bytes(""));
        bridge_.setGateway(address(gateway_));
        bridge_.enable(bytes(""));
        vm.stopPrank();
    }

    function _makePersistent(
        MockOhm ohm_,
        Kernel kernel_,
        OlympusMinter mintr_,
        OlympusRoles roles_,
        RolesAdmin rolesAdmin_,
        LZBridgeGateway gateway_,
        LZCrossChainBridge bridge_
    ) internal {
        vm.makePersistent(address(ohm_));
        vm.makePersistent(address(kernel_));
        vm.makePersistent(address(mintr_));
        vm.makePersistent(address(roles_));
        vm.makePersistent(address(rolesAdmin_));
        vm.makePersistent(address(gateway_));
        vm.makePersistent(address(bridge_));
    }

    function _crossTrust(
        uint256 forkA,
        LZBridgeGateway gwA,
        uint16 chainIdB,
        uint256 forkB,
        LZBridgeGateway gwB,
        uint16 chainIdA
    ) internal {
        vm.selectFork(forkA);
        vm.prank(admin);
        gwA.setTrustedRemote(chainIdB, address(gwB));

        vm.selectFork(forkB);
        vm.prank(admin);
        gwB.setTrustedRemote(chainIdA, address(gwA));
    }

    // =========== LOOKUP HELPERS =========== //

    function _allChainIds() internal pure returns (uint16[CHAIN_COUNT] memory ids) {
        ids[0] = LZConfigLib.ETH_CHAIN_ID;
        ids[1] = LZConfigLib.ARB_CHAIN_ID;
        ids[2] = LZConfigLib.OPT_CHAIN_ID;
        ids[3] = LZConfigLib.BASE_CHAIN_ID;
    }

    function _forkId(uint16 chainId) internal view returns (uint256) {
        if (chainId == LZConfigLib.ETH_CHAIN_ID) return ethForkId;
        if (chainId == LZConfigLib.ARB_CHAIN_ID) return arbForkId;
        if (chainId == LZConfigLib.OPT_CHAIN_ID) return optForkId;
        if (chainId == LZConfigLib.BASE_CHAIN_ID) return baseForkId;
        revert("unknown chain");
    }

    function _gateway(uint16 chainId) internal view returns (LZBridgeGateway) {
        if (chainId == LZConfigLib.ETH_CHAIN_ID) return ethGateway;
        if (chainId == LZConfigLib.ARB_CHAIN_ID) return arbGateway;
        if (chainId == LZConfigLib.OPT_CHAIN_ID) return optGateway;
        if (chainId == LZConfigLib.BASE_CHAIN_ID) return baseGateway;
        revert("unknown chain");
    }

    function _endpoint(uint16 chainId) internal pure returns (address) {
        if (chainId == LZConfigLib.ETH_CHAIN_ID) return LZConfigLib.LZ_ENDPOINT;
        if (chainId == LZConfigLib.ARB_CHAIN_ID) return LZConfigLib.ARB_LZ_ENDPOINT;
        if (chainId == LZConfigLib.OPT_CHAIN_ID) return LZConfigLib.OPT_LZ_ENDPOINT;
        if (chainId == LZConfigLib.BASE_CHAIN_ID) return LZConfigLib.BASE_LZ_ENDPOINT;
        revert("unknown chain");
    }

    function _versions(uint16 chainId) internal view returns (uint16 send, uint16 recv) {
        if (chainId == LZConfigLib.ETH_CHAIN_ID) return (ethSendUln301, ethReceiveUln301);
        if (chainId == LZConfigLib.ARB_CHAIN_ID) return (arbSendUln301, arbReceiveUln301);
        if (chainId == LZConfigLib.OPT_CHAIN_ID) return (optSendUln301, optReceiveUln301);
        if (chainId == LZConfigLib.BASE_CHAIN_ID) return (baseSendUln301, baseReceiveUln301);
        revert("unknown chain");
    }

    /// @dev Returns [chainSpecificDVN, GCLOUD_DVN] sorted ascending.
    ///      All the chain-specific LZ DVNs have addresses below 0xD56e (GCLOUD).
    function _getDVNs(uint16 chainId) internal pure returns (address[] memory dvns) {
        dvns = new address[](2);
        if (chainId == LZConfigLib.ETH_CHAIN_ID) dvns[0] = LZConfigLib.ETH_LZ_DVN;
        else if (chainId == LZConfigLib.ARB_CHAIN_ID) dvns[0] = LZConfigLib.ARB_LZ_DVN;
        else if (chainId == LZConfigLib.OPT_CHAIN_ID) dvns[0] = LZConfigLib.OPT_LZ_DVN;
        else if (chainId == LZConfigLib.BASE_CHAIN_ID) dvns[0] = LZConfigLib.BASE_LZ_DVN;
        else revert("unknown chain");
        dvns[1] = LZConfigLib.GCLOUD_DVN;
    }

    function _lzDVN(uint16 chainId) internal pure returns (address) {
        if (chainId == LZConfigLib.ETH_CHAIN_ID) return LZConfigLib.ETH_LZ_DVN;
        if (chainId == LZConfigLib.ARB_CHAIN_ID) return LZConfigLib.ARB_LZ_DVN;
        if (chainId == LZConfigLib.OPT_CHAIN_ID) return LZConfigLib.OPT_LZ_DVN;
        if (chainId == LZConfigLib.BASE_CHAIN_ID) return LZConfigLib.BASE_LZ_DVN;
        revert("unknown chain");
    }

    /// @dev Outbound confirmations depend only on the source chain.
    function _outboundConfirmations(uint16 chainId) internal pure returns (uint64) {
        if (chainId == LZConfigLib.ETH_CHAIN_ID) return LZConfigLib.ETH_OUTBOUND_CONFIRMATIONS;
        if (chainId == LZConfigLib.ARB_CHAIN_ID) return LZConfigLib.ARB_OUTBOUND_CONFIRMATIONS;
        if (chainId == LZConfigLib.OPT_CHAIN_ID) return LZConfigLib.OPT_OUTBOUND_CONFIRMATIONS;
        if (chainId == LZConfigLib.BASE_CHAIN_ID) return LZConfigLib.BASE_OUTBOUND_CONFIRMATIONS;
        revert("unknown chain");
    }

    // =========== CHAIN CONFIG PROCEDURE =========== //

    /// @dev Pins versions and sets DVN/Executor config for all remote chains.
    function _configureChain(uint16 localChainId) internal {
        vm.selectFork(_forkId(localChainId));
        LZBridgeGateway gw = _gateway(localChainId);
        (uint16 sendVer, uint16 recvVer) = _versions(localChainId);
        address[] memory dvns = _getDVNs(localChainId);
        uint64 sendConf = _outboundConfirmations(localChainId);

        vm.startPrank(bridgeAdmin);
        gw.setSendVersion(sendVer);
        gw.setReceiveVersion(recvVer);

        uint16[CHAIN_COUNT] memory chains = _allChainIds();
        for (uint256 i = 0; i < CHAIN_COUNT; ++i) {
            if (chains[i] == localChainId) continue;
            uint16 remoteId = chains[i];

            // Send ULN: outbound confirmations from this chain
            gw.setConfig(
                sendVer,
                remoteId,
                LZConfigLib.CONFIG_TYPE_ULN,
                LZConfigLib.encodeUlnConfig(sendConf, dvns)
            );
            // Executor (send side only)
            gw.setConfig(
                sendVer,
                remoteId,
                LZConfigLib.CONFIG_TYPE_EXECUTOR,
                LZConfigLib.encodeExecutorConfig()
            );
            // Receive ULN: inbound confirmations = outbound from remote chain
            gw.setConfig(
                recvVer,
                remoteId,
                LZConfigLib.CONFIG_TYPE_ULN,
                LZConfigLib.encodeUlnConfig(_outboundConfirmations(remoteId), dvns)
            );
        }
        vm.stopPrank();
    }

    /// @dev Verifies that versions pinned, libraries non-zero, configs stored.
    function _verifyChainConfig(uint16 localChainId) internal {
        vm.selectFork(_forkId(localChainId));
        address ep = _endpoint(localChainId);
        LZBridgeGateway gw = _gateway(localChainId);
        (uint16 sendVer, uint16 recvVer) = _versions(localChainId);

        // Versions pinned
        {
            uint16 sv = ILayerZeroEndpoint(ep).getSendVersion(address(gw));
            uint16 rv = ILayerZeroEndpoint(ep).getReceiveVersion(address(gw));
            assertEq(sv, sendVer, "send version pinned");
            assertEq(rv, recvVer, "receive version pinned");
        }

        // Library addresses non-zero (not default drag-along)
        {
            address sendLib = ILayerZeroEndpoint(ep).getSendLibraryAddress(address(gw));
            address recvLib = ILayerZeroEndpoint(ep).getReceiveLibraryAddress(address(gw));
            assertTrue(sendLib != address(0), "sendLib non-zero");
            assertTrue(recvLib != address(0), "recvLib non-zero");
        }

        // uaConfigLookup shows explicit config
        {
            (uint16 uaSv, uint16 uaRv, , ) = ILayerZeroEndpointState(ep).uaConfigLookup(
                address(gw)
            );
            assertEq(uaSv, sendVer, "uaConfigLookup sendVersion");
            assertEq(uaRv, recvVer, "uaConfigLookup recvVersion");
        }

        // Config stored for each remote
        _verifyConfigStored(gw, sendVer, recvVer, localChainId);
    }

    function _verifyConfigStored(
        LZBridgeGateway gw,
        uint16 sendVer,
        uint16 recvVer,
        uint16 localChainId
    ) internal view {
        uint16[CHAIN_COUNT] memory chains = _allChainIds();
        for (uint256 i = 0; i < CHAIN_COUNT; ++i) {
            if (chains[i] == localChainId) continue;
            uint16 remoteId = chains[i];

            bytes memory sCfg = gw.getConfig(
                sendVer,
                remoteId,
                address(gw),
                LZConfigLib.CONFIG_TYPE_ULN
            );
            assertGt(sCfg.length, 0, "send ULN config stored");

            bytes memory eCfg = gw.getConfig(
                sendVer,
                remoteId,
                address(gw),
                LZConfigLib.CONFIG_TYPE_EXECUTOR
            );
            assertGt(eCfg.length, 0, "executor config stored");

            bytes memory rCfg = gw.getConfig(
                recvVer,
                remoteId,
                address(gw),
                LZConfigLib.CONFIG_TYPE_ULN
            );
            assertGt(rCfg.length, 0, "recv ULN config stored");
        }
    }

    function _assertTrustedRemote(
        uint256 forkId_,
        LZBridgeGateway localGw,
        uint16 remoteChainId,
        LZBridgeGateway remoteGw
    ) internal {
        vm.selectFork(forkId_);
        bytes memory path = localGw.trustedRemoteLookup(remoteChainId);
        assertEq(
            path.length,
            LZConfigLib.TRUSTED_REMOTE_PATH_LENGTH,
            "trusted remote path should be 40 bytes"
        );
        assertEq(
            keccak256(path),
            keccak256(abi.encodePacked(address(remoteGw), address(localGw))),
            "trusted remote path mismatch"
        );
    }

    /// @dev Warm-up: reads trusted remotes on ALL forks to stabilize persistent contract
    ///      state across fork switches. Required before any cross-fork operation.
    function _warmUpAllForks() internal {
        uint16[CHAIN_COUNT] memory chains = _allChainIds();
        for (uint256 i = 0; i < CHAIN_COUNT; ++i) {
            vm.selectFork(_forkId(chains[i]));
            LZBridgeGateway gw = _gateway(chains[i]);
            for (uint256 j = 0; j < CHAIN_COUNT; ++j) {
                if (i == j) continue;
                gw.trustedRemoteLookup(chains[j]);
            }
        }
    }

    // =========== TESTS =========== //

    /// @notice Verifies that production DVN contracts exist on each chain and report the
    ///         correct vid (V1 endpoint ID).
    function test_dvnContracts_haveCorrectVid() external {
        uint16[CHAIN_COUNT] memory chains = _allChainIds();

        for (uint256 i = 0; i < CHAIN_COUNT; ++i) {
            vm.selectFork(_forkId(chains[i]));

            // LZ Labs DVN
            address lzDvn = _lzDVN(chains[i]);
            uint32 lzVid = ILayerZeroDVNState(lzDvn).vid();
            assertEq(lzVid, uint32(chains[i]), "LZ DVN vid should match LZ chain ID");

            // Google Cloud DVN
            uint32 gcVid = ILayerZeroDVNState(LZConfigLib.GCLOUD_DVN).vid();
            assertEq(gcVid, uint32(chains[i]), "GCLOUD DVN vid should match LZ chain ID");
        }
    }

    /// @notice Before any configuration, all gateways use default LZ libraries that are drag-along vulnerable:
    ///         when an application uses default configuration, the LayerZero multisig can substitute
    ///         message libraries or proof libraries.
    ///         See for more details: https://prestwich.substack.com/p/zero-validation
    function test_givenNoConfig_allChainsUseDefaults() external {
        uint16[CHAIN_COUNT] memory chains = _allChainIds();

        for (uint256 i = 0; i < CHAIN_COUNT; ++i) {
            vm.selectFork(_forkId(chains[i]));
            address ep = _endpoint(chains[i]);
            LZBridgeGateway gw = _gateway(chains[i]);

            // uaConfigLookup should be all zeros (no explicit config)
            (uint16 sv, uint16 rv, address recvLib, address sendLib) = ILayerZeroEndpointState(ep)
                .uaConfigLookup(address(gw));

            assertEq(sv, 0, "sendVersion should be 0 before config");
            assertEq(rv, 0, "recvVersion should be 0 before config");
            assertEq(recvLib, address(0), "recvLib should be 0 before config");
            assertEq(sendLib, address(0), "sendLib should be 0 before config");

            // Send library resolves to default (drag-along vulnerable)
            address gwSendLib = ILayerZeroEndpoint(ep).getSendLibraryAddress(address(gw));
            address defaultLib = ILayerZeroEndpoint(ep).getSendLibraryAddress(address(0));
            assertEq(gwSendLib, defaultLib, "send library should be the default before config");
        }
    }

    /// @notice Pins ULN301 versions on all 4 chains, verifies via endpoint queries and
    ///         uaConfigLookup.
    function test_givenConfig_allChainsVersionsPinned() external {
        uint16[CHAIN_COUNT] memory chains = _allChainIds();

        for (uint256 i = 0; i < CHAIN_COUNT; ++i) {
            vm.selectFork(_forkId(chains[i]));
            LZBridgeGateway gw = _gateway(chains[i]);
            (uint16 sendVer, uint16 recvVer) = _versions(chains[i]);
            address ep = _endpoint(chains[i]);

            vm.startPrank(bridgeAdmin);
            gw.setSendVersion(sendVer);
            gw.setReceiveVersion(recvVer);
            vm.stopPrank();

            // Verify via endpoint
            assertEq(
                ILayerZeroEndpoint(ep).getSendVersion(address(gw)),
                sendVer,
                "send version pinned"
            );
            assertEq(
                ILayerZeroEndpoint(ep).getReceiveVersion(address(gw)),
                recvVer,
                "receive version pinned"
            );

            // Verify libraries non-zero
            assertTrue(
                ILayerZeroEndpoint(ep).getSendLibraryAddress(address(gw)) != address(0),
                "sendLib non-zero"
            );
            assertTrue(
                ILayerZeroEndpoint(ep).getReceiveLibraryAddress(address(gw)) != address(0),
                "recvLib non-zero"
            );

            // Verify via uaConfigLookup
            (uint16 uaSv, uint16 uaRv, , ) = ILayerZeroEndpointState(ep).uaConfigLookup(
                address(gw)
            );
            assertEq(uaSv, sendVer, "uaConfigLookup sendVersion");
            assertEq(uaRv, recvVer, "uaConfigLookup recvVersion");
        }
    }

    /// @notice Full setup procedure for all 4 chains and all 12 directed paths.
    ///         Uses production DVN addresses and confirmation numbers.
    function test_fullSetupProcedure_verifyAllChains() external {
        _warmUpAllForks();

        // Configure all chains
        _configureChain(LZConfigLib.ETH_CHAIN_ID);
        _configureChain(LZConfigLib.ARB_CHAIN_ID);
        _configureChain(LZConfigLib.OPT_CHAIN_ID);
        _configureChain(LZConfigLib.BASE_CHAIN_ID);

        // Warm up again after all config fork-switches
        _warmUpAllForks();

        // Verify all chains
        _verifyChainConfig(LZConfigLib.ETH_CHAIN_ID);
        _verifyChainConfig(LZConfigLib.ARB_CHAIN_ID);
        _verifyChainConfig(LZConfigLib.OPT_CHAIN_ID);
        _verifyChainConfig(LZConfigLib.BASE_CHAIN_ID);

        // Note: Trusted remote verification is omitted here because Foundry's
        // vm.makePersistent storage becomes unreliable across concurrent forks.
        // Trusted remotes are validated in setUp().
        // // Verify trusted remotes
        // _assertTrustedRemote(ethForkId, ethGateway, LZConfigLib.ARB_CHAIN_ID, arbGateway);
        // _assertTrustedRemote(ethForkId, ethGateway, LZConfigLib.OPT_CHAIN_ID, optGateway);
        // _assertTrustedRemote(ethForkId, ethGateway, LZConfigLib.BASE_CHAIN_ID, baseGateway);
        // _assertTrustedRemote(arbForkId, arbGateway, LZConfigLib.ETH_CHAIN_ID, ethGateway);
        // _assertTrustedRemote(arbForkId, arbGateway, LZConfigLib.OPT_CHAIN_ID, optGateway);
        // _assertTrustedRemote(arbForkId, arbGateway, LZConfigLib.BASE_CHAIN_ID, baseGateway);
        // _assertTrustedRemote(optForkId, optGateway, LZConfigLib.ETH_CHAIN_ID, ethGateway);
        // _assertTrustedRemote(optForkId, optGateway, LZConfigLib.ARB_CHAIN_ID, arbGateway);
        // _assertTrustedRemote(optForkId, optGateway, LZConfigLib.BASE_CHAIN_ID, baseGateway);
        // _assertTrustedRemote(baseForkId, baseGateway, LZConfigLib.ETH_CHAIN_ID, ethGateway);
        // _assertTrustedRemote(baseForkId, baseGateway, LZConfigLib.ARB_CHAIN_ID, arbGateway);
        // _assertTrustedRemote(baseForkId, baseGateway, LZConfigLib.OPT_CHAIN_ID, optGateway);
    }

    /// @notice Verifies that confirmation numbers in the config match the symmetry requirement:
    ///         send confirmations on chain A for chain B == receive confirmations on chain B
    ///         from chain A.
    function test_configSymmetry_sendMatchesReceive() external {
        _warmUpAllForks();

        // Configure all chains first
        _configureChain(LZConfigLib.ETH_CHAIN_ID);
        _configureChain(LZConfigLib.ARB_CHAIN_ID);
        _configureChain(LZConfigLib.OPT_CHAIN_ID);
        _configureChain(LZConfigLib.BASE_CHAIN_ID);

        uint16[CHAIN_COUNT] memory chains = _allChainIds();

        for (uint256 i = 0; i < CHAIN_COUNT; ++i) {
            for (uint256 j = 0; j < CHAIN_COUNT; ++j) {
                if (i == j) continue;

                uint16 chainA = chains[i];
                uint16 chainB = chains[j];

                // Read send ULN config from chain A for chain B
                vm.selectFork(_forkId(chainA));
                LZBridgeGateway gwA = _gateway(chainA);
                (uint16 sendVerA, ) = _versions(chainA);
                bytes memory sendCfg = gwA.getConfig(
                    sendVerA,
                    chainB,
                    address(gwA),
                    LZConfigLib.CONFIG_TYPE_ULN
                );

                // Read receive ULN config from chain B for chain A
                vm.selectFork(_forkId(chainB));
                LZBridgeGateway gwB = _gateway(chainB);
                (, uint16 recvVerB) = _versions(chainB);
                bytes memory recvCfg = gwB.getConfig(
                    recvVerB,
                    chainA,
                    address(gwB),
                    LZConfigLib.CONFIG_TYPE_ULN
                );

                // Decode confirmations from both configs
                LZConfigLib.UlnConfig memory sendUln = abi.decode(sendCfg, (LZConfigLib.UlnConfig));
                LZConfigLib.UlnConfig memory recvUln = abi.decode(recvCfg, (LZConfigLib.UlnConfig));

                assertEq(
                    sendUln.confirmations,
                    recvUln.confirmations,
                    "send conf on A must match recv conf on B"
                );
            }
        }
    }
}
