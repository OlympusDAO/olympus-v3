// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {Test, Vm} from "forge-std/Test.sol";
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {LayerZeroHelper} from "src/test/lib/pigeon/layerzero/LayerZeroHelper.sol";

interface ILZEndpoint {
    function send(
        uint16 _dstChainId,
        bytes calldata _path,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable;

    function getSendLibraryAddress(address _userApplication) external view returns (address);

    function receivePayload(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        address _dstAddress,
        uint64 _nonce,
        uint _gasLimit,
        bytes calldata _payload
    ) external;
}

/// @notice Fork-based end-to-end tests for LZBridgeGateway cross-chain bridge
contract LZBridgeGatewayForkTests is Test {
    // ========= LZ ENDPOINTS (V1) ========= //

    address constant MAINNET_LZ_ENDPOINT = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;
    address constant POLYGON_LZ_ENDPOINT = 0x3c2269811836af69497E5F486A85D7316753cf62;

    uint16 constant MAINNET_LZ_CHAIN_ID = 101;
    uint16 constant POLYGON_LZ_CHAIN_ID = 109;

    // ========= FORKS ========= //

    uint256 mainnetForkId;
    uint256 polygonForkId;

    // ========= MAINNET CONTRACTS ========= //

    MockOhm mainnetOhm;
    Kernel mainnetKernel;
    OlympusMinter mainnetMintr;
    OlympusRoles mainnetRoles;
    RolesAdmin mainnetRolesAdmin;
    LZBridgeGateway mainnetGateway;
    LZCrossChainBridge mainnetBridge;

    // ========= POLYGON CONTRACTS ========= //

    MockOhm polygonOhm;
    Kernel polygonKernel;
    OlympusMinter polygonMintr;
    OlympusRoles polygonRoles;
    RolesAdmin polygonRolesAdmin;
    LZBridgeGateway polygonGateway;
    LZCrossChainBridge polygonBridge;

    // ========= HELPERS ========= //

    LayerZeroHelper lzHelper;

    // ========= ADDRESSES ========= //

    address admin;
    address sender;
    address recipient;

    uint256 constant MINT_AMOUNT = 10_000e9;
    uint256 constant SUPPLY_CAP = 100_000e9;
    uint256 constant LZ_GAS = 500_000;

    // Packet event selector for LayerZero V1
    bytes32 constant PACKET_EVENT_SELECTOR =
        0xe9bded5f24a4168e4f3bf44e00298c993b22376aad8c58c7dda9718a54cbea82;

    // Cached default library addresses (resolved per-fork during setUp)
    address mainnetDefaultLib;
    address polygonDefaultLib;

    function setUp() external {
        // Create forks at latest block
        mainnetForkId = vm.createFork("mainnet");
        polygonForkId = vm.createFork("polygon");

        // Create persistent addresses
        admin = makeAddr("admin");
        vm.makePersistent(admin);
        sender = makeAddr("sender");
        vm.makePersistent(sender);
        recipient = makeAddr("recipient");
        vm.makePersistent(recipient);

        // Create the LZ helper and make persistent
        lzHelper = new LayerZeroHelper();
        vm.makePersistent(address(lzHelper));

        // Deploy mainnet stack and cache its default library
        vm.selectFork(mainnetForkId);
        mainnetDefaultLib = _getDefaultLibrary(MAINNET_LZ_ENDPOINT);
        _deployMainnetStack();

        // Deploy polygon stack and cache its default library
        vm.selectFork(polygonForkId);
        polygonDefaultLib = _getDefaultLibrary(POLYGON_LZ_ENDPOINT);
        _deployPolygonStack();

        // Cross-configure trusted remotes
        vm.selectFork(mainnetForkId);
        vm.prank(admin);
        mainnetGateway.setTrustedRemote(POLYGON_LZ_CHAIN_ID, address(polygonGateway));

        vm.selectFork(polygonForkId);
        vm.prank(admin);
        polygonGateway.setTrustedRemote(MAINNET_LZ_CHAIN_ID, address(mainnetGateway));
    }

    function _deployMainnetStack() internal {
        mainnetOhm = new MockOhm("OHM", "OHM", 9);
        mainnetBridge = new LZCrossChainBridge(address(mainnetOhm), admin);
        mainnetKernel = new Kernel();
        mainnetMintr = new OlympusMinter(mainnetKernel, address(mainnetOhm));
        mainnetRoles = new OlympusRoles(mainnetKernel);
        mainnetRolesAdmin = new RolesAdmin(mainnetKernel);
        mainnetGateway = new LZBridgeGateway(
            mainnetKernel,
            MAINNET_LZ_ENDPOINT,
            true, // canonical
            address(mainnetBridge)
        );

        mainnetKernel.executeAction(Actions.InstallModule, address(mainnetMintr));
        mainnetKernel.executeAction(Actions.InstallModule, address(mainnetRoles));
        mainnetKernel.executeAction(Actions.ActivatePolicy, address(mainnetRolesAdmin));
        mainnetKernel.executeAction(Actions.ActivatePolicy, address(mainnetGateway));

        mainnetRolesAdmin.grantRole("admin", admin);

        vm.startPrank(admin);
        mainnetGateway.setBridgedSupplyCap(SUPPLY_CAP);
        mainnetGateway.enable(bytes(""));
        mainnetBridge.setGateway(address(mainnetGateway));
        mainnetBridge.enable(bytes(""));
        vm.stopPrank();

        // Mint OHM and fund sender
        mainnetOhm.mint(sender, MINT_AMOUNT);
        vm.deal(sender, 100 ether);

        // Make persistent across forks
        vm.makePersistent(address(mainnetOhm));
        vm.makePersistent(address(mainnetKernel));
        vm.makePersistent(address(mainnetMintr));
        vm.makePersistent(address(mainnetRoles));
        vm.makePersistent(address(mainnetRolesAdmin));
        vm.makePersistent(address(mainnetGateway));
        vm.makePersistent(address(mainnetBridge));
    }

    function _deployPolygonStack() internal {
        polygonOhm = new MockOhm("OHM", "OHM", 9);
        polygonBridge = new LZCrossChainBridge(address(polygonOhm), admin);
        polygonKernel = new Kernel();
        polygonMintr = new OlympusMinter(polygonKernel, address(polygonOhm));
        polygonRoles = new OlympusRoles(polygonKernel);
        polygonRolesAdmin = new RolesAdmin(polygonKernel);
        polygonGateway = new LZBridgeGateway(
            polygonKernel,
            POLYGON_LZ_ENDPOINT,
            false, // non-canonical
            address(polygonBridge)
        );

        polygonKernel.executeAction(Actions.InstallModule, address(polygonMintr));
        polygonKernel.executeAction(Actions.InstallModule, address(polygonRoles));
        polygonKernel.executeAction(Actions.ActivatePolicy, address(polygonRolesAdmin));
        polygonKernel.executeAction(Actions.ActivatePolicy, address(polygonGateway));

        polygonRolesAdmin.grantRole("admin", admin);

        vm.startPrank(admin);
        polygonGateway.enable(bytes(""));
        polygonBridge.setGateway(address(polygonGateway));
        polygonBridge.enable(bytes(""));
        vm.stopPrank();

        // Mint OHM and fund sender on polygon
        polygonOhm.mint(sender, MINT_AMOUNT);
        vm.deal(sender, 100 ether);

        // Make persistent across forks
        vm.makePersistent(address(polygonOhm));
        vm.makePersistent(address(polygonKernel));
        vm.makePersistent(address(polygonMintr));
        vm.makePersistent(address(polygonRoles));
        vm.makePersistent(address(polygonRolesAdmin));
        vm.makePersistent(address(polygonGateway));
        vm.makePersistent(address(polygonBridge));
    }

    // ========= HELPERS ========= //

    /// @dev Get the default library address from the LZ endpoint
    function _getDefaultLibrary(address endpoint) internal view returns (address) {
        return ILZEndpoint(endpoint).getSendLibraryAddress(address(0));
    }

    /// @dev Send OHM from mainnet to polygon and relay the message
    function _bridgeMainnetToPolygon(uint256 amount) internal {
        vm.selectFork(mainnetForkId);

        // Estimate fee
        (uint256 fee, ) = mainnetBridge.estimateSendFee(POLYGON_LZ_CHAIN_ID, recipient, amount);

        // Approve and send
        vm.startPrank(sender);
        mainnetOhm.approve(address(mainnetBridge), amount);
        vm.recordLogs();
        mainnetBridge.sendOhm{value: fee}(POLYGON_LZ_CHAIN_ID, recipient, amount);
        vm.stopPrank();

        // Relay to polygon (use cached default library)
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(
            POLYGON_LZ_ENDPOINT,
            polygonDefaultLib,
            LZ_GAS,
            PACKET_EVENT_SELECTOR,
            polygonForkId,
            logs
        );
    }

    /// @dev Send OHM from polygon to mainnet and relay the message
    function _bridgePolygonToMainnet(uint256 amount) internal {
        vm.selectFork(polygonForkId);

        // Estimate fee
        (uint256 fee, ) = polygonBridge.estimateSendFee(MAINNET_LZ_CHAIN_ID, recipient, amount);

        // Approve and send
        vm.startPrank(sender);
        polygonOhm.approve(address(polygonBridge), amount);
        vm.recordLogs();
        polygonBridge.sendOhm{value: fee}(MAINNET_LZ_CHAIN_ID, recipient, amount);
        vm.stopPrank();

        // Relay to mainnet (use cached default library)
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(
            MAINNET_LZ_ENDPOINT,
            mainnetDefaultLib,
            LZ_GAS,
            PACKET_EVENT_SELECTOR,
            mainnetForkId,
            logs
        );
    }

    // ========= TESTS ========= //

    function test_mainnetToPolygon_sendsAndReceivesOhm() external {
        // Verify trusted remote is set on polygon gateway
        vm.selectFork(polygonForkId);
        bytes memory trustedRemote = polygonGateway.trustedRemoteLookup(MAINNET_LZ_CHAIN_ID);
        bytes memory expectedPath = abi.encodePacked(
            address(mainnetGateway),
            address(polygonGateway)
        );
        assertEq(trustedRemote.length, 40, "Trusted remote should be 40 bytes");
        assertEq(keccak256(trustedRemote), keccak256(expectedPath), "Trusted remote should match");

        uint256 amount = 1000e9;

        // Record balances before
        vm.selectFork(mainnetForkId);
        uint256 senderBalanceBefore = mainnetOhm.balanceOf(sender);

        // Bridge
        _bridgeMainnetToPolygon(amount);

        // Verify mainnet: sender lost OHM
        vm.selectFork(mainnetForkId);
        assertEq(
            mainnetOhm.balanceOf(sender),
            senderBalanceBefore - amount,
            "Mainnet: sender balance should decrease"
        );
        assertEq(mainnetGateway.bridgedSupply(), amount, "Mainnet: bridgedSupply should increase");

        // Verify polygon: recipient received OHM
        vm.selectFork(polygonForkId);
        assertEq(polygonOhm.balanceOf(recipient), amount, "Polygon: recipient should receive OHM");
    }

    function test_polygonToMainnet_sendsAndReceivesOhm() external {
        // Verify trusted remote is set on polygon gateway
        vm.selectFork(polygonForkId);
        bytes memory trustedRemote = polygonGateway.trustedRemoteLookup(MAINNET_LZ_CHAIN_ID);
        bytes memory expectedPath = abi.encodePacked(
            address(mainnetGateway),
            address(polygonGateway)
        );
        assertEq(trustedRemote.length, 40, "Trusted remote should be 40 bytes");
        assertEq(keccak256(trustedRemote), keccak256(expectedPath), "Trusted remote should match");

        uint256 amount = 1000e9;

        // First bridge some OHM to polygon to establish bridgedSupply
        _bridgeMainnetToPolygon(amount);

        // Set bridgedSupply on mainnet for the return trip
        // (In production this would already be set from the outbound bridge)
        // The outbound should have already set it, verify
        vm.selectFork(mainnetForkId);
        assertEq(mainnetGateway.bridgedSupply(), amount, "Bridged supply should be set");

        // Now bridge from polygon to mainnet
        // First mint OHM for sender on polygon (they received from the bridge)
        vm.selectFork(polygonForkId);
        uint256 recipientBalPolygon = polygonOhm.balanceOf(recipient);

        // Transfer recipient's OHM to sender for the return trip
        vm.prank(recipient);
        polygonOhm.transfer(sender, recipientBalPolygon);

        _bridgePolygonToMainnet(recipientBalPolygon);

        // Verify mainnet: bridgedSupply decreases
        vm.selectFork(mainnetForkId);
        assertEq(mainnetGateway.bridgedSupply(), 0, "Mainnet: bridgedSupply should decrease to 0");

        // Recipient should have received OHM on mainnet
        assertEq(
            mainnetOhm.balanceOf(recipient),
            recipientBalPolygon,
            "Mainnet: recipient should receive OHM"
        );
    }

    function test_roundTrip_fullFlow() external {
        // Verify trusted remote is set on polygon gateway
        vm.selectFork(polygonForkId);
        bytes memory trustedRemote = polygonGateway.trustedRemoteLookup(MAINNET_LZ_CHAIN_ID);
        bytes memory expectedPath = abi.encodePacked(
            address(mainnetGateway),
            address(polygonGateway)
        );
        assertEq(trustedRemote.length, 40, "Trusted remote should be 40 bytes");
        assertEq(keccak256(trustedRemote), keccak256(expectedPath), "Trusted remote should match");

        uint256 amount = 500e9;

        // Step 1: mainnet -> polygon
        _bridgeMainnetToPolygon(amount);

        vm.selectFork(mainnetForkId);
        assertEq(mainnetGateway.bridgedSupply(), amount, "Supply after outbound");

        vm.selectFork(polygonForkId);
        assertEq(polygonOhm.balanceOf(recipient), amount, "Polygon recipient balance");

        // Step 2: polygon -> mainnet (recipient sends back to recipient)
        vm.prank(recipient);
        polygonOhm.transfer(sender, amount);

        _bridgePolygonToMainnet(amount);

        // Verify round-trip
        vm.selectFork(mainnetForkId);
        assertEq(
            mainnetGateway.bridgedSupply(),
            0,
            "Bridged supply should return to zero after round-trip"
        );
        assertEq(
            mainnetOhm.balanceOf(recipient),
            amount,
            "Recipient should receive OHM after round-trip on mainnet"
        );
    }
}
