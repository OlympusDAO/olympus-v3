// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// The two forks are set up by mirrored blocks, so each setup value appears once per fork
// forge-lint: disable-start(literal-instead-of-constant)

import {Test} from "@forge-std-1.16.2/Test.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {CCIPBurnMintTokenPool} from "src/policies/bridge/CCIPBurnMintTokenPool.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {CCIPCrossChainBridge} from "src/periphery/bridge/CCIPCrossChainBridge.sol";
import {CCIPFeeBudgetLib} from "src/scripts/ops/lib/CCIPFeeBudgetLib.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink-local-0.3.1/ccip/CCIPLocalSimulatorFork.sol";
import {RateLimiter} from "@chainlink-ccip-1.6.0/ccip/libraries/RateLimiter.sol";
import {TokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/TokenPool.sol";
import {ITokenAdminRegistry} from "@chainlink-ccip-1.6.0/ccip/interfaces/ITokenAdminRegistry.sol";
import {Client} from "@chainlink-ccip-1.6.0/ccip/libraries/Client.sol";
import {IRouter} from "@chainlink-ccip-1.6.0/ccip/interfaces/IRouter.sol";
import {IRouterClient} from "@chainlink-ccip-1.6.0/ccip/interfaces/IRouterClient.sol";

// Calls are made for their effect or their expected revert; a test reads only the returned
// values it asserts.
// forge-lint: disable-start(unused-return)

// The fork base, its two suites and the interfaces they read through share this file
// forge-lint: disable-start(multi-contract-file)

interface IOwnable {
    function owner() external returns (address);
}

/// @notice The token transfer fee setter of `EVM2EVMOnRamp 1.5`, which holds the fee entries of
///         its lane.
interface IEVM2EVMOnRampFeeConfig {
    /// @param token The token of the entry.
    /// @param minFeeUSDCents The minimum fee per token transfer, in multiples of 0.01 USD.
    /// @param maxFeeUSDCents The maximum fee per token transfer, in multiples of 0.01 USD.
    /// @param deciBps The fee on the transferred value, in multiples of 0.1 bps.
    /// @param destGasOverhead The gas that the on-ramp stamps as the `destGasAmount` of the
    ///        token, under which the off-ramp runs the release or mint.
    /// @param destBytesOverhead The data availability bytes of the pool return data.
    /// @param aggregateRateLimitEnabled Whether the token counts toward the aggregate rate limit.
    struct TokenTransferFeeConfigArgs {
        address token;
        uint32 minFeeUSDCents;
        uint32 maxFeeUSDCents;
        uint16 deciBps;
        uint32 destGasOverhead;
        uint32 destBytesOverhead;
        bool aggregateRateLimitEnabled;
    }

    /// @notice Writes the given token entries and removes the entries of the listed tokens.
    /// @param tokenTransferFeeConfigArgs The entries to write.
    /// @param tokensToUseDefaultFeeConfigs The tokens whose entries are removed.
    function setTokenTransferFeeConfig(
        TokenTransferFeeConfigArgs[] memory tokenTransferFeeConfigArgs,
        address[] memory tokensToUseDefaultFeeConfigs
    ) external;
}

/// @notice Bridges OHM between two forks through the live CCIP lanes, with the OHM stack
///         (MockOhm, MINTR, `CCIPBurnMintTokenPool`, `CCIPCrossChainBridge`) deployed on each fork
///         and `chainlink-local`'s `CCIPLocalSimulatorFork` delivering the messages. The
///         simulator routes strictly: a message that it cannot route or whose execution fails
///         reverts the routing call with the decoded reason. Gas metering stays on, since
///         `vm.pauseGasMetering` keeps the gas of every call frame constant and would let a
///         release or mint run past the gas budget that the destination off-ramp gives it.
///         Each suite pins the forks to blocks of one ramp generation.
// solhint-disable max-states-count
abstract contract CCIPBurnMintTokenPoolForkTestBase is Test {
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

    uint256 public constant MINT_AMOUNT = 1e9;
    uint256 public constant SEND_AMOUNT = 1e8;

    uint256 public mainnetForkId;
    uint256 public polygonForkId;

    /// @notice Returns the Ethereum Sepolia and Polygon Amoy blocks the forks are pinned to.
    /// @dev    Both blocks must sit on the same side of every ramp upgrade of the lane, so that
    ///         the two directions run one generation.
    function _forkBlocks()
        internal
        pure
        virtual
        returns (uint256 mainnetBlock_, uint256 polygonBlock_);

    /// @notice Configures the live lanes of both forks before any message is sent. Does nothing
    ///         unless a suite overrides it.
    function _configureLanes() internal virtual {}

    function setUp() public {
        // Set up forks
        // Mainnet is active
        // Ethereum Sepolia and Polygon Amoy stand in for mainnet and a burn/mint chain
        (uint256 mainnetBlock, uint256 polygonBlock) = _forkBlocks();
        mainnetForkId = vm.createFork("sepolia", mainnetBlock);
        polygonForkId = vm.createFork("polygon-amoy", polygonBlock);
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

            // Label the stack and the live CCIP contracts it uses
            vm.label(address(mainnetOHM), "mainnet.OHM");
            vm.label(address(mainnetKernel), "mainnet.Kernel");
            vm.label(address(mainnetMinter), "mainnet.MINTR");
            vm.label(address(mainnetRoles), "mainnet.ROLES");
            vm.label(address(mainnetRolesAdmin), "mainnet.RolesAdmin");
            vm.label(address(mainnetTokenPool), "mainnet.TokenPool");
            vm.label(address(mainnetBridge), "mainnet.Bridge");
            vm.label(mainnetDetails.routerAddress, "mainnet.Router");
            vm.label(mainnetDetails.rmnProxyAddress, "mainnet.RMNProxy");
            vm.label(mainnetDetails.tokenAdminRegistryAddress, "mainnet.TokenAdminRegistry");

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

            // Label the stack and the live CCIP contracts it uses
            vm.label(address(polygonOHM), "polygon.OHM");
            vm.label(address(polygonKernel), "polygon.Kernel");
            vm.label(address(polygonMinter), "polygon.MINTR");
            vm.label(address(polygonRoles), "polygon.ROLES");
            vm.label(address(polygonRolesAdmin), "polygon.RolesAdmin");
            vm.label(address(polygonTokenPool), "polygon.TokenPool");
            vm.label(address(polygonBridge), "polygon.Bridge");
            vm.label(polygonDetails.routerAddress, "polygon.Router");
            vm.label(polygonDetails.rmnProxyAddress, "polygon.RMNProxy");
            vm.label(polygonDetails.tokenAdminRegistryAddress, "polygon.TokenAdminRegistry");

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

            // Gas limit needed for bridging with data
            _setGasLimit(mainnetBridge, polygonChainSelector, 200_000);
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

            // Gas limit needed for bridging with data
            _setGasLimit(polygonBridge, mainnetChainSelector, 200_000);
        }

        _configureLanes();

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

    function _setGasLimit(
        CCIPCrossChainBridge bridge_,
        uint64 chainSelector_,
        uint32 gasLimit_
    ) internal {
        vm.prank(ADMIN);
        bridge_.setGasLimit(chainSelector_, gasLimit_);
    }

    /// @dev Delivery checks, to be called after `switchChainAndRouteMessage`. Strict routing
    ///      already reverts on a message that the simulator cannot route or whose execution
    ///      fails. The status check also catches a message that the simulator never captured
    ///      (`NOT_FOUND`) or left waiting (`QUEUED`: a CCIP 1.6 or 2.0 message whose destination
    ///      fork was not passed, or a CCIP 2.0 message held for manual execution); the
    ///      total-supply check proves a single mint of the sent amount.
    function _assertDelivered(bytes32 messageId_, MockOhm destOhm_, string memory chain_) internal {
        (CCIPLocalSimulatorFork.MessageStatus status, ) = simulator.getMessageStatus(messageId_);
        assertEq(
            uint8(status),
            uint8(CCIPLocalSimulatorFork.MessageStatus.SUCCESS),
            string.concat(chain_, ": delivery: message status")
        );
        // Total supply = MINT_AMOUNT (minted in setUp) + SEND_AMOUNT (minted on delivery)
        assertEq(
            destOhm_.totalSupply(),
            MINT_AMOUNT + SEND_AMOUNT,
            string.concat(chain_, ": delivery: OHM total supply")
        );
    }

    // ========= TESTS ========= //

    // mainnet -> polygon
    // [X] the OHM is burned on mainnet
    // [X] the OHM is minted on polygon to the recipient
    // [X] the bridged supply on mainnet is not updated
    // [X] the bridged supply on polygon is not updated
    // [X] the MINTR approval on mainnet is not updated
    // [X] the MINTR approval on polygon is not updated
    // [X] the message is routed and executed on polygon

    function test_mainnetToPolygon() public {
        uint256 fee = mainnetBridge.getFeeEVM(polygonChainSelector, RECIPIENT, SEND_AMOUNT);

        // Call the bridge
        vm.startPrank(SENDER);
        mainnetOHM.approve(address(mainnetBridge), SEND_AMOUNT);
        // The value is the CCIP fee quoted above, sent to the bridge that this suite deploys
        // forge-lint: disable-next-item(arbitrary-send-eth)
        bytes32 messageId = mainnetBridge.sendToEVM{value: fee}(
            polygonChainSelector,
            RECIPIENT,
            SEND_AMOUNT
        );
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

        // Process the bridging transaction
        simulator.switchChainAndRouteMessage(polygonForkId);

        _assertDelivered(messageId, polygonOHM, "polygon");

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
    //  [X] the message is routed and executed on polygon

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
        // The value is the CCIP fee quoted above, sent to the CCIP router of the fork
        // forge-lint: disable-next-line(arbitrary-send-eth)
        bytes32 messageId = router.ccipSend{value: fee}(polygonChainSelector, ccipMessage);
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

        // Process the bridging transaction
        simulator.switchChainAndRouteMessage(polygonForkId);

        _assertDelivered(messageId, polygonOHM, "polygon");

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
    // [X] the message is routed and executed on mainnet

    function test_polygonToMainnet() public {
        // Start on Polygon
        vm.selectFork(polygonForkId);

        // Get the fee
        uint256 fee = polygonBridge.getFeeEVM(mainnetChainSelector, RECIPIENT, SEND_AMOUNT);

        // Call the bridge
        vm.startPrank(SENDER);
        polygonOHM.approve(address(polygonBridge), SEND_AMOUNT);
        // The value is the CCIP fee quoted above, sent to the bridge that this suite deploys
        // forge-lint: disable-next-item(arbitrary-send-eth)
        bytes32 messageId = polygonBridge.sendToEVM{value: fee}(
            mainnetChainSelector,
            RECIPIENT,
            SEND_AMOUNT
        );
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

        // Process the bridging transaction
        simulator.switchChainAndRouteMessage(mainnetForkId);

        _assertDelivered(messageId, mainnetOHM, "mainnet");

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
    // [X] the message is routed and executed on mainnet

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
        // The value is the CCIP fee quoted above, sent to the CCIP router of the fork
        // forge-lint: disable-next-line(arbitrary-send-eth)
        bytes32 messageId = router.ccipSend{value: fee}(mainnetChainSelector, ccipMessage);
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

        // Process the bridging transaction
        simulator.switchChainAndRouteMessage(mainnetForkId);

        _assertDelivered(messageId, mainnetOHM, "mainnet");

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

/// @notice Runs the fork suite over the CCIP 2.0 lanes between Ethereum Sepolia and Polygon Amoy
///         (`OnRamp` / `OffRamp` 2.0.0 in both directions at the pinned blocks), the ramp
///         generation of the EVM lanes in scope (see the CCIP lane generations of the RUNBOOK).
///         The simulator executes each message through the permissionless `execute` of the
///         destination off-ramp, which calls `releaseOrMint` on the v1 pool without a per-token
///         gas limit, so these runs do not exercise the OHM delivery gas budget.
contract CCIPBurnMintTokenPoolForkTest is CCIPBurnMintTokenPoolForkTestBase {
    /// @notice A Sepolia block and an Amoy block of 2026-10-14 00:00:00 UTC.
    uint256 internal constant MAINNET_BLOCK = 11909528;
    uint256 internal constant POLYGON_BLOCK = 50113473;

    function _forkBlocks() internal pure override returns (uint256, uint256) {
        return (MAINNET_BLOCK, POLYGON_BLOCK);
    }
}

/// @notice Runs the fork suite over the CCIP 1.5 lanes between Ethereum Sepolia and Polygon Amoy
///         (`EVM2EVMOnRamp` / `EVM2EVMOffRamp` 1.5.0 in both directions at the pinned blocks).
///         The 1.5 off-ramp runs the receiver balance reads and `releaseOrMint` under the
///         `destGasAmount` that the source on-ramp stamps from the lane's OHM fee entry. Each
///         source on-ramp therefore carries an entry of
///         `CCIPFeeBudgetLib.OHM_MIN_DEST_GAS_OVERHEAD`, written by impersonating the on-ramp
///         owner, as Chainlink writes it at step 0 of the rollout. Without the entry the stamp is
///         the lane default of 90000, under which the mint on Sepolia runs out of gas.
contract CCIPBurnMintTokenPoolForkTest_V1dot5 is CCIPBurnMintTokenPoolForkTestBase {
    /// @notice A Sepolia block of 2025-05-19 and an Amoy block of 2026-08-31, both before the
    ///         move of the lane to CCIP 2.0 at Sepolia block 11606202 and Amoy block 46367173
    ///         (2026-08-31 14:13 UTC).
    uint256 internal constant MAINNET_BLOCK = 8360176;
    uint256 internal constant POLYGON_BLOCK = 46360000;

    function _forkBlocks() internal pure override returns (uint256, uint256) {
        return (MAINNET_BLOCK, POLYGON_BLOCK);
    }

    function _configureLanes() internal override {
        vm.selectFork(mainnetForkId);
        _setOhmFeeEntry(
            "mainnet",
            mainnetBridge.getCCIPRouter(),
            polygonChainSelector,
            address(mainnetOHM)
        );

        vm.selectFork(polygonForkId);
        _setOhmFeeEntry(
            "polygon",
            polygonBridge.getCCIPRouter(),
            mainnetChainSelector,
            address(polygonOHM)
        );
    }

    /// @notice Writes an enabled OHM entry with the minimum delivery gas budget on the 1.5
    ///         on-ramp of the lane toward `destChainSelector_`, on the active fork.
    function _setOhmFeeEntry(
        string memory chain_,
        address router_,
        uint64 destChainSelector_,
        address token_
    ) internal {
        address onRamp = IRouter(router_).getOnRamp(destChainSelector_);
        vm.label(onRamp, string.concat(chain_, ".EVM2EVMOnRamp"));

        IEVM2EVMOnRampFeeConfig.TokenTransferFeeConfigArgs[]
            memory entries = new IEVM2EVMOnRampFeeConfig.TokenTransferFeeConfigArgs[](1);
        // The 1.5 on-ramp requires destBytesOverhead >= 32, the size of the pool return data
        entries[0] = IEVM2EVMOnRampFeeConfig.TokenTransferFeeConfigArgs({
            token: token_,
            minFeeUSDCents: 0,
            maxFeeUSDCents: 0,
            deciBps: 0,
            destGasOverhead: CCIPFeeBudgetLib.OHM_MIN_DEST_GAS_OVERHEAD,
            destBytesOverhead: 32,
            aggregateRateLimitEnabled: false
        });

        address owner = IOwnable(onRamp).owner();
        vm.prank(owner);
        IEVM2EVMOnRampFeeConfig(onRamp).setTokenTransferFeeConfig(entries, new address[](0));
    }
}

// forge-lint: disable-end(multi-contract-file)

// forge-lint: disable-end(unused-return)

// forge-lint: disable-end(literal-instead-of-constant)
