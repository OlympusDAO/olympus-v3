// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

import {Test} from "@forge-std-1.9.6/Test.sol";
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {CCIPBurnMintTokenPool} from "src/policies/bridge/CCIPBurnMintTokenPool.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {CCIPCrossChainBridge} from "src/periphery/bridge/CCIPCrossChainBridge.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink-local-0.2.5/ccip/CCIPLocalSimulatorFork.sol";
import {RateLimiter} from "@chainlink-ccip-1.6.0/ccip/libraries/RateLimiter.sol";
import {TokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/TokenPool.sol";
import {ITokenAdminRegistry} from "@chainlink-ccip-1.6.0/ccip/interfaces/ITokenAdminRegistry.sol";
import {Client} from "@chainlink-ccip-1.6.0/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink-ccip-1.6.0/ccip/interfaces/IRouterClient.sol";

interface IOwnable {
    function owner() external returns (address);
}

// solhint-disable max-states-count
contract CCIPBurnMintTokenPoolForkTest is Test {
    using ModuleTestFixtureGenerator for OlympusMinter;

    CCIPLocalSimulatorFork public simulator;

    MockOhm public mainnetOHM;
    MockOhm public polygonOHM;
    OlympusMinter public mainnetMinter;
    OlympusMinter public polygonMinter;
    OlympusRoles public mainnetRoles;
    OlympusRoles public polygonRoles;
    Kernel public mainnetKernel;
    Kernel public polygonKernel;
    RolesAdmin public mainnetRolesAdmin;
    RolesAdmin public polygonRolesAdmin;
    CCIPBurnMintTokenPool public mainnetTokenPool;
    CCIPBurnMintTokenPool public polygonTokenPool;
    CCIPCrossChainBridge public mainnetBridge;
    CCIPCrossChainBridge public polygonBridge;

    uint64 public mainnetChainSelector;
    uint64 public polygonChainSelector;

    address public SENDER;
    address public RECIPIENT;
    address public ADMIN;

    address public mintrGodmode;

    uint256 public constant MINT_AMOUNT = 1e9;
    uint256 public constant SEND_AMOUNT = 1e8;

    uint256 public mainnetForkId;
    uint256 public polygonForkId;

    // Pin the blocks so that RPC responses are cached
    uint256 public constant MAINNET_BLOCK = 8360176;
    uint256 public constant POLYGON_BLOCK = 21855529;

    function setUp() public {
        // Set up forks
        // Mainnet is active
        // These use Sepolia RPCs, as CCIPLocalSimulatorFork only supports sepolia testnets
        mainnetForkId = vm.createFork(vm.envString("ETH_TESTNET_RPC_URL"), MAINNET_BLOCK);
        polygonForkId = vm.createFork(vm.envString("POLYGON_TESTNET_RPC_URL"), POLYGON_BLOCK);
        vm.selectFork(mainnetForkId);

        // Addresses
        SENDER = makeAddr("SENDER");
        vm.makePersistent(SENDER);
        RECIPIENT = makeAddr("RECIPIENT");
        vm.makePersistent(RECIPIENT);
        ADMIN = makeAddr("ADMIN");
        vm.makePersistent(ADMIN);

        // Create the simulator and make it persistent across forks
        simulator = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(simulator));

        // Create the stack on mainnet
        {
            mainnetOHM = new MockOhm("OHM", "OHM", 9);

            Register.NetworkDetails memory mainnetDetails = simulator.getNetworkDetails(
                block.chainid
            );
            mainnetChainSelector = mainnetDetails.chainSelector;

            mainnetKernel = new Kernel();
            mainnetMinter = new OlympusMinter(mainnetKernel, address(mainnetOHM));
            mainnetRoles = new OlympusRoles(mainnetKernel);
            mainnetRolesAdmin = new RolesAdmin(mainnetKernel);
            mainnetTokenPool = new CCIPBurnMintTokenPool(
                address(mainnetKernel),
                address(mainnetOHM),
                mainnetDetails.rmnProxyAddress,
                mainnetDetails.routerAddress
            );
            mainnetBridge = new CCIPCrossChainBridge(
                address(mainnetOHM),
                mainnetDetails.routerAddress,
                ADMIN
            );

            // Configure the token and token pool
            _addTokenAndPool(
                mainnetOHM,
                mainnetTokenPool,
                mainnetDetails.tokenAdminRegistryAddress
            );

            // Install into kernel
            mainnetKernel.executeAction(Actions.InstallModule, address(mainnetMinter));
            mainnetKernel.executeAction(Actions.InstallModule, address(mainnetRoles));
            mainnetKernel.executeAction(Actions.ActivatePolicy, address(mainnetRolesAdmin));
            mainnetKernel.executeAction(Actions.ActivatePolicy, address(mainnetTokenPool));

            // Grant admin role
            mainnetRolesAdmin.grantRole("admin", ADMIN);

            // Enable the token pool
            vm.prank(ADMIN);
            mainnetTokenPool.enable("");

            // Enable the bridge
            vm.prank(ADMIN);
            mainnetBridge.enable("");

            // Mint OHM to the sender
            mainnetOHM.mint(SENDER, MINT_AMOUNT);

            // Mint ETH to the sender
            vm.deal(SENDER, 100 ether);
        }

        // Create the stack on polygon
        {
            vm.selectFork(polygonForkId);

            polygonOHM = new MockOhm("OHM", "OHM", 9);

            Register.NetworkDetails memory polygonDetails = simulator.getNetworkDetails(
                block.chainid
            );
            polygonChainSelector = polygonDetails.chainSelector;

            polygonKernel = new Kernel();
            polygonMinter = new OlympusMinter(polygonKernel, address(polygonOHM));
            polygonRoles = new OlympusRoles(polygonKernel);
            polygonRolesAdmin = new RolesAdmin(polygonKernel);
            polygonTokenPool = new CCIPBurnMintTokenPool(
                address(polygonKernel),
                address(polygonOHM),
                polygonDetails.rmnProxyAddress,
                polygonDetails.routerAddress
            );
            polygonBridge = new CCIPCrossChainBridge(
                address(polygonOHM),
                polygonDetails.routerAddress,
                ADMIN
            );

            // Configure the token and token pool
            _addTokenAndPool(
                polygonOHM,
                polygonTokenPool,
                polygonDetails.tokenAdminRegistryAddress
            );

            // Install into kernel
            polygonKernel.executeAction(Actions.InstallModule, address(polygonMinter));
            polygonKernel.executeAction(Actions.InstallModule, address(polygonRoles));
            polygonKernel.executeAction(Actions.ActivatePolicy, address(polygonRolesAdmin));
            polygonKernel.executeAction(Actions.ActivatePolicy, address(polygonTokenPool));

            // Grant admin role
            polygonRolesAdmin.grantRole("admin", ADMIN);

            // Enable the token pool
            vm.prank(ADMIN);
            polygonTokenPool.enable("");

            // Enable the bridge
            vm.prank(ADMIN);
            polygonBridge.enable("");

            // Mint OHM to the sender
            polygonOHM.mint(SENDER, MINT_AMOUNT);

            // Mint ETH to the sender
            vm.deal(SENDER, 100 ether);
        }

        // Configure the mainnet token pool
        {
            vm.selectFork(mainnetForkId);

            _applyChainUpdates(
                mainnetTokenPool,
                polygonChainSelector,
                address(polygonTokenPool),
                address(polygonOHM)
            );

            _setTrustedRemote(mainnetBridge, polygonChainSelector, address(polygonBridge));
        }

        // Configure the polygon token pool
        {
            vm.selectFork(polygonForkId);

            _applyChainUpdates(
                polygonTokenPool,
                mainnetChainSelector,
                address(mainnetTokenPool),
                address(mainnetOHM)
            );

            _setTrustedRemote(polygonBridge, mainnetChainSelector, address(mainnetBridge));
        }

        // Set the active chain to mainnet
        vm.selectFork(mainnetForkId);
    }

    function _addTokenAndPool(
        MockOhm token_,
        CCIPBurnMintTokenPool tokenPool_,
        address tokenAdminRegistry_
    ) internal {
        ITokenAdminRegistry registry = ITokenAdminRegistry(tokenAdminRegistry_);

        // Propose the ADMIN as the owner of the token
        vm.prank(IOwnable(tokenAdminRegistry_).owner());
        registry.proposeAdministrator(address(token_), ADMIN);

        // Accept the proposal
        vm.prank(ADMIN);
        registry.acceptAdminRole(address(token_));

        // Set the pool for the token
        vm.prank(ADMIN);
        registry.setPool(address(token_), address(tokenPool_));
    }

    function _applyChainUpdates(
        CCIPBurnMintTokenPool tokenPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteTokenAddress
    ) internal {
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);

        RateLimiter.Config memory outboundRateLimiterConfig = RateLimiter.Config({
            isEnabled: false,
            capacity: 0,
            rate: 0
        });
        RateLimiter.Config memory inboundRateLimiterConfig = RateLimiter.Config({
            isEnabled: false,
            capacity: 0,
            rate: 0
        });

        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](1);
        chainUpdates[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: outboundRateLimiterConfig,
            inboundRateLimiterConfig: inboundRateLimiterConfig
        });

        tokenPool.applyChainUpdates(new uint64[](0), chainUpdates);
    }

    function _setTrustedRemote(
        CCIPCrossChainBridge bridge_,
        uint64 chainSelector_,
        address remote_
    ) internal {
        vm.prank(ADMIN);
        bridge_.setTrustedRemoteEVM(chainSelector_, remote_);
    }

    // ========= TESTS ========= //

    // mainnet -> polygon
    // [X] the OHM is burned on mainnet
    // [X] the OHM is minted on polygon to the recipient
    // [X] the bridged supply on mainnet is not updated
    // [X] the bridged supply on polygon is not updated
    // [X] the MINTR approval on mainnet is not updated
    // [X] the MINTR approval on polygon is not updated

    function test_mainnetToPolygon() public {
        uint256 fee = mainnetBridge.getFeeEVM(polygonChainSelector, RECIPIENT, SEND_AMOUNT);

        // Call the bridge
        vm.startPrank(SENDER);
        mainnetOHM.approve(address(mainnetBridge), SEND_AMOUNT);
        mainnetBridge.sendToEVM{value: fee}(polygonChainSelector, RECIPIENT, SEND_AMOUNT);
        vm.stopPrank();

        // Assertions - mainnet
        assertEq(
            mainnetOHM.balanceOf(SENDER),
            MINT_AMOUNT - SEND_AMOUNT,
            "mainnet: sender: OHM balance"
        );
        assertEq(mainnetOHM.balanceOf(RECIPIENT), 0, "mainnet: recipient: OHM balance");
        assertEq(mainnetTokenPool.getBridgedSupply(), 0, "mainnet: bridged supply");
        assertEq(
            mainnetMinter.mintApproval(address(mainnetTokenPool)),
            0,
            "mainnet: minter approval"
        );

        // The following command runs into an OutOfGas error, so disable gas metering
        vm.pauseGasMetering();

        // Process the bridging transaction
        simulator.switchChainAndRouteMessage(polygonForkId);

        // Assertions - polygon
        assertEq(polygonOHM.balanceOf(SENDER), MINT_AMOUNT, "polygon: sender: OHM balance");
        assertEq(polygonOHM.balanceOf(RECIPIENT), SEND_AMOUNT, "polygon: recipient: OHM balance");
        assertEq(polygonTokenPool.getBridgedSupply(), 0, "polygon: bridged supply");
        assertEq(
            polygonMinter.mintApproval(address(polygonTokenPool)),
            0,
            "polygon: minter approval"
        );
    }

    // when the bridge contract is not used
    //  [X] the OHM is burned on mainnet
    //  [X] the OHM is minted on polygon to the recipient
    //  [X] the bridged supply on mainnet is not updated
    //  [X] the bridged supply on polygon is not updated
    //  [X] the MINTR approval on mainnet is not updated
    //  [X] the MINTR approval on polygon is not updated

    function test_mainnetToPolygon_noBridge() public {
        uint256 fee = mainnetBridge.getFeeEVM(polygonChainSelector, RECIPIENT, SEND_AMOUNT);

        // Construct the CCIP message
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(mainnetOHM), amount: SEND_AMOUNT});
        Client.EVM2AnyMessage memory ccipMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(RECIPIENT),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({gasLimit: 0, allowOutOfOrderExecution: false})
            ),
            feeToken: address(0)
        });

        IRouterClient router = IRouterClient(mainnetBridge.getCCIPRouter());

        // Call the CCIP router
        vm.startPrank(SENDER);
        mainnetOHM.approve(address(router), SEND_AMOUNT);
        router.ccipSend{value: fee}(polygonChainSelector, ccipMessage);
        vm.stopPrank();

        // Assertions - mainnet
        assertEq(
            mainnetOHM.balanceOf(SENDER),
            MINT_AMOUNT - SEND_AMOUNT,
            "mainnet: sender: OHM balance"
        );
        assertEq(mainnetOHM.balanceOf(RECIPIENT), 0, "mainnet: recipient: OHM balance");
        assertEq(mainnetTokenPool.getBridgedSupply(), 0, "mainnet: bridged supply");
        assertEq(
            mainnetMinter.mintApproval(address(mainnetTokenPool)),
            0,
            "mainnet: minter approval"
        );

        // The following command runs into an OutOfGas error, so disable gas metering
        vm.pauseGasMetering();

        // Process the bridging transaction
        simulator.switchChainAndRouteMessage(polygonForkId);

        // Assertions - polygon
        assertEq(polygonOHM.balanceOf(SENDER), MINT_AMOUNT, "polygon: sender: OHM balance");
        assertEq(polygonOHM.balanceOf(RECIPIENT), SEND_AMOUNT, "polygon: recipient: OHM balance");
        assertEq(polygonTokenPool.getBridgedSupply(), 0, "polygon: bridged supply");
        assertEq(
            polygonMinter.mintApproval(address(polygonTokenPool)),
            0,
            "polygon: minter approval"
        );
    }

    // polygon -> mainnet
    // [X] the OHM is burned on polygon
    // [X] the OHM is minted on mainnet to the recipient
    // [X] the bridged supply on polygon is not updated
    // [X] the bridged supply on mainnet is not updated
    // [X] the MINTR approval on polygon is not updated
    // [X] the MINTR approval on mainnet is not updated

    function test_polygonToMainnet() public {
        // Start on Polygon
        vm.selectFork(polygonForkId);

        // Get the fee
        uint256 fee = polygonBridge.getFeeEVM(mainnetChainSelector, RECIPIENT, SEND_AMOUNT);

        // Call the bridge
        vm.startPrank(SENDER);
        polygonOHM.approve(address(polygonBridge), SEND_AMOUNT);
        polygonBridge.sendToEVM{value: fee}(mainnetChainSelector, RECIPIENT, SEND_AMOUNT);
        vm.stopPrank();

        // Assertions - polygon
        assertEq(
            polygonOHM.balanceOf(SENDER),
            MINT_AMOUNT - SEND_AMOUNT,
            "polygon: sender: OHM balance"
        );
        assertEq(polygonOHM.balanceOf(RECIPIENT), 0, "polygon: recipient: OHM balance");
        assertEq(polygonTokenPool.getBridgedSupply(), 0, "polygon: bridged supply");
        assertEq(
            polygonMinter.mintApproval(address(polygonTokenPool)),
            0,
            "polygon: minter approval"
        );

        // The following command runs into an OutOfGas error, so disable gas metering
        vm.pauseGasMetering();

        // Process the bridging transaction
        simulator.switchChainAndRouteMessage(mainnetForkId);

        // Assertions - mainnet
        assertEq(mainnetOHM.balanceOf(SENDER), MINT_AMOUNT, "mainnet: sender: OHM balance");
        assertEq(mainnetOHM.balanceOf(RECIPIENT), SEND_AMOUNT, "mainnet: recipient: OHM balance");
        assertEq(mainnetTokenPool.getBridgedSupply(), 0, "mainnet: bridged supply");
        assertEq(
            mainnetMinter.mintApproval(address(mainnetTokenPool)),
            0,
            "mainnet: minter approval"
        );
    }

    // when the bridge contract is not used
    // [X] the OHM is burned on polygon
    // [X] the OHM is minted on mainnet to the recipient
    // [X] the bridged supply on polygon is not updated
    // [X] the bridged supply on mainnet is not updated
    // [X] the MINTR approval on polygon is not updated
    // [X] the MINTR approval on mainnet is not updated

    function test_polygonToMainnet_noBridge() public {
        // Start on Polygon
        vm.selectFork(polygonForkId);

        // Get the fee
        uint256 fee = polygonBridge.getFeeEVM(mainnetChainSelector, RECIPIENT, SEND_AMOUNT);

        // Construct the CCIP message
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(polygonOHM), amount: SEND_AMOUNT});
        Client.EVM2AnyMessage memory ccipMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(RECIPIENT),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({gasLimit: 0, allowOutOfOrderExecution: false})
            ),
            feeToken: address(0)
        });

        IRouterClient router = IRouterClient(polygonBridge.getCCIPRouter());

        // Call the CCIP router
        vm.startPrank(SENDER);
        polygonOHM.approve(address(router), SEND_AMOUNT);
        router.ccipSend{value: fee}(mainnetChainSelector, ccipMessage);
        vm.stopPrank();

        // Assertions - polygon
        assertEq(
            polygonOHM.balanceOf(SENDER),
            MINT_AMOUNT - SEND_AMOUNT,
            "polygon: sender: OHM balance"
        );
        assertEq(polygonOHM.balanceOf(RECIPIENT), 0, "polygon: recipient: OHM balance");
        assertEq(polygonTokenPool.getBridgedSupply(), 0, "polygon: bridged supply");
        assertEq(
            polygonMinter.mintApproval(address(polygonTokenPool)),
            0,
            "polygon: minter approval"
        );

        // The following command runs into an OutOfGas error, so disable gas metering
        vm.pauseGasMetering();

        // Process the bridging transaction
        simulator.switchChainAndRouteMessage(mainnetForkId);

        // Assertions - mainnet
        assertEq(mainnetOHM.balanceOf(SENDER), MINT_AMOUNT, "mainnet: sender: OHM balance");
        assertEq(mainnetOHM.balanceOf(RECIPIENT), SEND_AMOUNT, "mainnet: recipient: OHM balance");
        assertEq(mainnetTokenPool.getBridgedSupply(), 0, "mainnet: bridged supply");
        assertEq(
            mainnetMinter.mintApproval(address(mainnetTokenPool)),
            0,
            "mainnet: minter approval"
        );
    }

    // mainnet -> solana
    // [ ] the OHM is burned on mainnet
    // [ ] the OHM is minted on solana to the recipient
    // [ ] the bridged supply on mainnet is not updated
    // [ ] the MINTR approval on mainnet is not updated
    // NOTE: unable to test this as solana is not supported by the ccip simulator

    // solana -> mainnet
    // [ ] the OHM is burned on solana
    // [ ] the OHM is minted on mainnet to the recipient
    // [ ] the bridged supply on mainnet is not updated
    // [ ] the MINTR approval on mainnet is not updated
    // NOTE: unable to test this as solana is not supported by the ccip simulator
}
