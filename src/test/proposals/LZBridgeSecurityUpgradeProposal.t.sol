// SPDX-License-Identifier: UNLICENSED
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";
import {console2} from "forge-std/console2.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";

// Contracts
import {Kernel, Actions, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {ILayerZeroEndpoint} from "@layer-zero-endpoint-v1-1.1.0/lzApp/interfaces/ILayerZeroEndpoint.sol";

// Proposal
import {LZBridgeSecurityUpgradeProposal} from "src/proposals/LZBridgeSecurityUpgradeProposal.sol";

contract LZBridgeSecurityUpgradeProposalTest is ProposalTest {
    /// @dev Block where timelock already has `admin` + `bridge_admin` roles.
    ///      Update this once the contracts are deployed on mainnet.
    uint256 public constant BLOCK = 24621400;

    /// @dev Number of remote chains (Arbitrum, Optimism, Base).
    uint256 internal constant _REMOTE_CHAIN_COUNT = 3;

    // ========== DEPLOYMENT TOGGLES ==========

    /// @dev Set to true once LZBridgeGateway has been deployed on Ethereum.
    ///      When false, setUp() deploys it locally and registers it in
    ///      the address registry before proposal simulation.
    bool public constant IS_CONTRACTS_DEPLOYED = false;

    // ========== CONTRACTS ==========

    Kernel public kernel;
    LZBridgeGateway public gateway;
    LZBridgeSecurityUpgradeProposal public proposal;
    ROLESv1 public roles;
    IERC20 public ohm;

    // ========== ADDRESSES ==========

    address public daoMS;
    address public timelock;
    address public oldCrossChainBridge;

    function setUp() public virtual {
        // Mainnet fork at a fixed block
        vm.createSelectFork(_RPC_ALIAS, BLOCK);

        // ========== PROPOSAL SETUP ==========

        proposal = new LZBridgeSecurityUpgradeProposal();

        // Set to true once the proposal has been submitted on-chain
        hasBeenSubmitted = false;

        // Initialize test suite and addresses
        _setupSuite(address(proposal));

        // ========== LOAD COMMON ADDRESSES ==========

        kernel = Kernel(addresses.getAddress("olympus-kernel"));
        roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        ohm = IERC20(addresses.getAddress("olympus-legacy-ohm"));
        daoMS = addresses.getAddress("olympus-multisig-dao");
        timelock = addresses.getAddress("olympus-timelock");
        oldCrossChainBridge = addresses.getAddress("olympus-policy-cross-chain-bridge");

        // ========== CONDITIONAL DEPLOYMENT ==========

        if (IS_CONTRACTS_DEPLOYED) {
            gateway = LZBridgeGateway(addresses.getAddress("olympus-policy-lz-bridge-gateway"));
            console2.log("Contracts already deployed on mainnet");
        } else {
            // Deploy LZCrossChainBridge (periphery, owned by DAO MS - configured via MS batch)
            LZCrossChainBridge bridge = new LZCrossChainBridge(address(ohm), daoMS);
            vm.label(address(bridge), "LZCrossChainBridge");

            // Deploy LZBridgeGateway (policy, canonical on mainnet)
            gateway = new LZBridgeGateway(
                kernel,
                LZConfigLib.LZ_ENDPOINT,
                true, // isCanonical
                address(bridge) // facilitator
            );
            vm.label(address(gateway), "LZBridgeGateway");

            // Register in the address registry
            addresses.addAddress(
                "olympus-policy-lz-bridge-gateway",
                address(gateway),
                block.chainid
            );
            console2.log("Contracts deployed locally");
        }

        // ========== PRE-OCG: MS BATCH 1 ==========

        // Simulate what the DAO MS does before the OCG proposal: activate new LZBridgeGateway
        vm.prank(daoMS);
        kernel.executeAction(Actions.ActivatePolicy, address(gateway));

        // ========== SIMULATE PROPOSAL ==========

        suite.setDebug(true);
        _simulateProposal();

        // Re-read addresses in case simulation updated them
        addresses = suite.addresses();
    }

    // ========== LZ CONFIG VERIFICATION HELPERS ==========

    function _verifySendUlnConfig(uint16 sendVer_, uint16 remoteChainId_) internal view {
        bytes memory cfg = gateway.getConfig(
            sendVer_,
            remoteChainId_,
            address(gateway),
            LZConfigLib.CONFIG_TYPE_ULN
        );
        assertGt(cfg.length, 0, "Send ULN config should be set");

        LZConfigLib.UlnConfig memory uln = abi.decode(cfg, (LZConfigLib.UlnConfig));
        assertEq(
            uln.confirmations,
            LZConfigLib.ETH_OUTBOUND_CONFIRMATIONS,
            "Send ULN confirmations mismatch"
        );
        assertEq(uln.requiredDVNCount, 2, "Send ULN should require 2 DVNs");
        assertEq(uln.requiredDVNs.length, 2, "Send ULN should have 2 required DVNs");
        // DVNs sorted ascending: ETH_LZ_DVN (0x589d...) < GCLOUD_DVN (0xD56e...)
        assertEq(
            uln.requiredDVNs[0],
            LZConfigLib.ETH_LZ_DVN,
            "Send ULN DVN[0] should be ETH_LZ_DVN"
        );
        assertEq(
            uln.requiredDVNs[1],
            LZConfigLib.GCLOUD_DVN,
            "Send ULN DVN[1] should be GCLOUD_DVN"
        );
        assertEq(uln.optionalDVNCount, 0, "Send ULN should have 0 optional DVNs");
    }

    function _verifyRecvUlnConfig(
        uint16 recvVer_,
        uint16 remoteChainId_,
        uint64 expectedConfirmations_
    ) internal view {
        bytes memory cfg = gateway.getConfig(
            recvVer_,
            remoteChainId_,
            address(gateway),
            LZConfigLib.CONFIG_TYPE_ULN
        );
        assertGt(cfg.length, 0, "Recv ULN config should be set");

        LZConfigLib.UlnConfig memory uln = abi.decode(cfg, (LZConfigLib.UlnConfig));
        assertEq(uln.confirmations, expectedConfirmations_, "Recv ULN confirmations mismatch");
        assertEq(uln.requiredDVNCount, 2, "Recv ULN should require 2 DVNs");
        assertEq(uln.requiredDVNs.length, 2, "Recv ULN should have 2 required DVNs");
        assertEq(
            uln.requiredDVNs[0],
            LZConfigLib.ETH_LZ_DVN,
            "Recv ULN DVN[0] should be ETH_LZ_DVN"
        );
        assertEq(
            uln.requiredDVNs[1],
            LZConfigLib.GCLOUD_DVN,
            "Recv ULN DVN[1] should be GCLOUD_DVN"
        );
        assertEq(uln.optionalDVNCount, 0, "Recv ULN should have 0 optional DVNs");
    }

    function _verifyExecutorConfig(uint16 sendVer_, uint16 remoteChainId_) internal view {
        bytes memory cfg = gateway.getConfig(
            sendVer_,
            remoteChainId_,
            address(gateway),
            LZConfigLib.CONFIG_TYPE_EXECUTOR
        );
        assertGt(cfg.length, 0, "Executor config should be set");

        LZConfigLib.ExecutorConfig memory exec = abi.decode(cfg, (LZConfigLib.ExecutorConfig));
        assertEq(
            exec.maxMessageSize,
            LZConfigLib.MAX_MESSAGE_SIZE,
            "Executor maxMessageSize mismatch"
        );
        assertEq(exec.executor, LZConfigLib.LZ_EXECUTOR, "Executor address mismatch");
    }

    function _verifyTrustedRemotes() internal view {
        uint16[_REMOTE_CHAIN_COUNT] memory remoteIds = [
            LZConfigLib.ARB_CHAIN_ID,
            LZConfigLib.OPT_CHAIN_ID,
            LZConfigLib.BASE_CHAIN_ID
        ];
        address[_REMOTE_CHAIN_COUNT] memory remoteGateways = [
            proposal.ARB_GATEWAY(),
            proposal.OPT_GATEWAY(),
            proposal.BASE_GATEWAY()
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            bytes memory path = gateway.trustedRemoteLookup(remoteIds[i]);
            if (remoteGateways[i] == address(0)) {
                assertEq(path.length, 0, "Trusted remote should be empty for zero gateway");
            } else {
                assertEq(path.length, 40, "Trusted remote path should be 40 bytes");
                assertEq(
                    keccak256(path),
                    keccak256(abi.encodePacked(remoteGateways[i], address(gateway))),
                    "Trusted remote path mismatch"
                );
            }
        }
    }

    // ========================================================================
    // End State Tests
    // ========================================================================

    /// @notice Validates that the proposal leaves the system in the correct end state.
    function test_proposalEndState() public view {
        // 1. Policy active and enabled
        assertTrue(Policy(address(gateway)).isActive(), "LZBridgeGateway should be active");
        assertTrue(gateway.isEnabled(), "LZBridgeGateway should be enabled");

        // 2. DAO MS has bridge_admin role
        assertTrue(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(daoMS, bytes32("bridge_admin")),
            "DAO MS should have bridge_admin role"
        );

        // 3. Gateway immutables
        assertEq(gateway.LZ_ENDPOINT(), LZConfigLib.LZ_ENDPOINT, "LZ_ENDPOINT should match");
        assertTrue(gateway.IS_CANONICAL(), "Gateway should be canonical on mainnet");
        assertEq(gateway.ohm(), address(ohm), "OHM should match");

        // 4. Bridged supply cap
        assertEq(
            gateway.bridgedSupplyCap(),
            proposal.BRIDGED_SUPPLY_CAP(),
            "Bridged supply cap should match proposal constant"
        );

        // 5. LZ versions pinned
        ILayerZeroEndpoint endpoint = ILayerZeroEndpoint(LZConfigLib.LZ_ENDPOINT);
        uint16 sendVer = endpoint.getSendVersion(address(gateway));
        uint16 recvVer = endpoint.getReceiveVersion(address(gateway));
        assertGt(sendVer, 0, "Send version should be pinned");
        assertEq(recvVer, sendVer + 1, "Receive version should be send version + 1");

        // 6. Per-remote LZ config (send ULN, executor, receive ULN)
        uint16[_REMOTE_CHAIN_COUNT] memory remoteIds = [
            LZConfigLib.ARB_CHAIN_ID,
            LZConfigLib.OPT_CHAIN_ID,
            LZConfigLib.BASE_CHAIN_ID
        ];
        uint64[_REMOTE_CHAIN_COUNT] memory remoteConfs = [
            LZConfigLib.ARB_OUTBOUND_CONFIRMATIONS,
            LZConfigLib.OPT_OUTBOUND_CONFIRMATIONS,
            LZConfigLib.BASE_OUTBOUND_CONFIRMATIONS
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            _verifySendUlnConfig(sendVer, remoteIds[i]);
            _verifyExecutorConfig(sendVer, remoteIds[i]);
            _verifyRecvUlnConfig(recvVer, remoteIds[i], remoteConfs[i]);
        }

        // 7. Trusted remotes
        _verifyTrustedRemotes();
    }
}

/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
