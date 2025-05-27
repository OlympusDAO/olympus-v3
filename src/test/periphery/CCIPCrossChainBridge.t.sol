// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IAny2EVMMessageReceiver} from "@chainlink-ccip-1.6.0/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {IERC165} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v5.0.2/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v5.0.2/contracts/token/ERC20/IERC20.sol";

import {CCIPCrossChainBridge} from "src/periphery/bridge/CCIPCrossChainBridge.sol";
import {ICCIPCrossChainBridge} from "src/periphery/interfaces/ICCIPCrossChainBridge.sol";
import {Client} from "@chainlink-ccip-1.6.0/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink-ccip-1.6.0/ccip/applications/CCIPReceiver.sol";
import {ICCIPClient} from "src/external/bridge/ICCIPClient.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockCCIPRouter} from "src/test/policies/bridge/mocks/MockCCIPRouter.sol";

contract CCIPCrossChainBridgeTest is Test {
    event Bridged(
        bytes32 messageId,
        uint64 destinationChainSelector,
        address indexed sender,
        uint256 amount,
        uint256 fees
    );

    event Received(
        bytes32 messageId,
        uint64 sourceChainSelector,
        address indexed sender,
        uint256 amount
    );

    event Enabled();

    event Disabled();

    event Withdrawn(address indexed recipient, uint256 amount);

    event TrustedRemoteEVMSet(uint64 indexed dstChainSelector, address indexed to);

    event TrustedRemoteSVMSet(uint64 indexed dstChainSelector, bytes32 indexed to);

    event MessageFailed(bytes32 messageId);

    event RetryMessageSuccess(bytes32 messageId);

    CCIPCrossChainBridge public bridge;

    MockERC20 public OHM;
    MockCCIPRouter public router;

    address public SENDER;
    address public OWNER;
    address public EVM_RECIPIENT;
    address public TRSRY;

    bytes32 public constant MESSAGE_ID =
        bytes32(0x0000000000000000000000000000000000000000000000000000000000000222);
    uint64 public constant DESTINATION_CHAIN_SELECTOR = 111111;
    uint64 public constant SOURCE_CHAIN_SELECTOR = 222222;
    bytes32 public constant SVM_RECIPIENT =
        bytes32(0x0000000000000000000000000000000000000000000000000000000000000022);

    // The default SVM receiver address is the zero address
    // Source: https://docs.chain.link/ccip/tutorials/svm/destination/build-messages#receiver
    // base58 "11111111111111111111111111111111" decoded = 0x0000000000000000000000000000000000000000000000000000000000000000
    bytes32 public constant SVM_TRUSTED_REMOTE =
        0x0000000000000000000000000000000000000000000000000000000000000000;
    address public constant EVM_TRUSTED_REMOTE = 0x1234567890123456789012345678901234567890;
    uint256 public constant AMOUNT = 1e9;
    uint256 public constant ETH_AMOUNT = 1e18;
    uint256 public constant FEE = 1e16;

    function setUp() public {
        SENDER = makeAddr("SENDER");
        OWNER = makeAddr("OWNER");
        EVM_RECIPIENT = makeAddr("EVM_RECIPIENT");
        TRSRY = makeAddr("TRSRY");

        OHM = new MockERC20("Olympus", "OHM", 9);
        router = new MockCCIPRouter();
        router.setFee(FEE);

        bridge = new CCIPCrossChainBridge(address(OHM), address(router), OWNER);

        // Deal ETH to the sender
        deal(SENDER, ETH_AMOUNT);

        // Mint OHM to the sender
        OHM.mint(SENDER, AMOUNT);
    }

    // ============ HELPERS ============ //

    modifier givenSenderHasApprovedSpendingOHM(uint256 amount_) {
        vm.prank(SENDER);
        OHM.approve(address(bridge), amount_);
        _;
    }

    modifier givenContractIsEnabled() {
        vm.prank(OWNER);
        bridge.enable("");
        _;
    }

    modifier givenContractIsDisabled() {
        vm.prank(OWNER);
        bridge.disable("");
        _;
    }

    modifier givenBridgeHasEthBalance(uint256 amount_) {
        deal(address(bridge), amount_);
        _;
    }

    modifier givenBridgeHasOHMBalance(uint256 amount_) {
        OHM.mint(address(bridge), amount_);
        _;
    }

    modifier givenDestinationEVMChainHasTrustedRemote() {
        vm.prank(OWNER);
        bridge.setTrustedRemoteEVM(DESTINATION_CHAIN_SELECTOR, EVM_TRUSTED_REMOTE);
        _;
    }

    modifier givenSourceEVMChainHasTrustedRemote() {
        vm.prank(OWNER);
        bridge.setTrustedRemoteEVM(SOURCE_CHAIN_SELECTOR, EVM_TRUSTED_REMOTE);
        _;
    }

    modifier givenDestinationSVMChainHasTrustedRemote() {
        vm.prank(OWNER);
        bridge.setTrustedRemoteSVM(DESTINATION_CHAIN_SELECTOR, SVM_TRUSTED_REMOTE);
        _;
    }

    // ============ TESTS ============ //

    // constructor
    // when the OHM address is the zero address
    //  [X] it reverts
    // when the CCIP router address is the zero address
    //  [X] it reverts
    // when the owner address is the zero address
    //  [X] it reverts
    // [X] it sets the OHM address
    // [X] it sets the CCIP router address
    // [X] it sets the owner address

    function test_constructor_ohm_zeroAddress_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPCrossChainBridge.Bridge_InvalidAddress.selector, "ohm")
        );

        // Call function
        new CCIPCrossChainBridge(address(0), address(router), OWNER);
    }

    function test_constructor_router_zeroAddress_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, address(0)));

        // Call function
        new CCIPCrossChainBridge(address(OHM), address(0), OWNER);
    }

    function test_constructor_owner_zeroAddress_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPCrossChainBridge.Bridge_InvalidAddress.selector, "owner")
        );

        // Call function
        new CCIPCrossChainBridge(address(OHM), address(router), address(0));
    }

    function test_constructor() public {
        // Call function
        bridge = new CCIPCrossChainBridge(address(OHM), address(router), OWNER);

        // Assert state
        assertEq(address(bridge.OHM()), address(OHM));
        assertEq(address(bridge.getCCIPRouter()), address(router));
        assertEq(address(bridge.owner()), OWNER);
    }

    // enable
    // given the contract is already enabled
    //  [X] it reverts
    // when the caller is not the owner
    //  [X] it reverts
    // [X] it emits an Enabled event
    // [X] it sets the isEnabled flag to true

    function test_enable_alreadyEnabled_reverts() public givenContractIsEnabled {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotDisabled.selector));

        // Call function
        vm.prank(OWNER);
        bridge.enable("");
    }

    function test_enable_notOwner_reverts() public {
        // Expect revert
        vm.expectRevert("UNAUTHORIZED");

        // Call function
        vm.prank(SENDER);
        bridge.enable("");
    }

    function test_enable() public {
        // Expect event
        vm.expectEmit();
        emit Enabled();

        // Call function
        vm.prank(OWNER);
        bridge.enable("");

        // Assert state
        assertEq(bridge.isEnabled(), true, "isEnabled");
    }

    // disable
    // given the contract is not enabled
    //  [X] it reverts
    // when the caller is not the owner
    //  [X] it reverts
    // [X] it emits a Disabled event
    // [X] it sets the isEnabled flag to false

    function test_disable_notEnabled_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));

        // Call function
        vm.prank(OWNER);
        bridge.disable("");
    }

    function test_disable_notOwner_reverts() public givenContractIsEnabled {
        // Expect revert
        vm.expectRevert("UNAUTHORIZED");

        // Call function
        vm.prank(SENDER);
        bridge.disable("");
    }

    function test_disable() public givenContractIsEnabled {
        // Expect event
        vm.expectEmit();
        emit Disabled();

        // Call function
        vm.prank(OWNER);
        bridge.disable("");

        // Assert state
        assertEq(bridge.isEnabled(), false, "isEnabled");
    }

    // sendToSVM
    // given the contract is not enabled
    //  [X] it reverts
    // given the destination SVM chain does not have a defined trusted remote
    //  [X] it reverts
    // when the amount is zero
    //  [X] it reverts
    // when the sender has not provided enough native token to cover fees
    //  [X] it reverts
    // given the sender has insufficient OHM
    //  [X] it reverts
    // given the sender has not approved the contract to spend OHM
    //  [X] it reverts
    // [X] the recipient address is the default trusted remote
    // [X] the SVM extra args compute units are the default compute units
    // [X] the SVM extra args writeable bitmap is 0
    // [X] the SVM extra args allow out of order execution is true
    // [X] the SVM extra args recipient is the recipient address
    // [X] the SVM extra args accounts is an empty array
    // [X] the bridge transfers the OHM from the sender to itself
    // [X] the bridge transfers the fee from the sender to itself
    // [X] the CCIP router is called with the correct parameters
    // [X] the CCIP router transfers the OHM to itself
    // [X] the CCIP router transfers the fee to itself
    // [X] a Bridged event is emitted

    function test_sendToSVM_notEnabled_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));

        // Call function
        vm.prank(SENDER);
        bridge.sendToSVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, SVM_RECIPIENT, AMOUNT);
    }

    function test_sendToSVM_amountZero_reverts()
        public
        givenContractIsEnabled
        givenDestinationSVMChainHasTrustedRemote
    {
        // Expect revert
        vm.expectRevert(ICCIPCrossChainBridge.Bridge_ZeroAmount.selector);

        // Call function
        vm.prank(SENDER);
        bridge.sendToSVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, SVM_RECIPIENT, 0);
    }

    function test_sendToSVM_notEnoughNativeToken_reverts(
        uint256 msgValue_
    ) public givenContractIsEnabled givenDestinationSVMChainHasTrustedRemote {
        // Bound the msg.value to be less than the fee
        msgValue_ = bound(msgValue_, 0, FEE - 1);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPCrossChainBridge.Bridge_InsufficientNativeToken.selector,
                FEE,
                msgValue_
            )
        );

        // Call function
        vm.prank(SENDER);
        bridge.sendToSVM{value: msgValue_}(DESTINATION_CHAIN_SELECTOR, SVM_RECIPIENT, AMOUNT);
    }

    function test_sendToSVM_insufficientOHM_reverts(
        uint256 sendAmount_
    ) public givenContractIsEnabled givenDestinationSVMChainHasTrustedRemote {
        // Bound the send amount to be more than the sender's OHM balance
        sendAmount_ = bound(sendAmount_, AMOUNT + 1, type(uint256).max);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPCrossChainBridge.Bridge_InsufficientAmount.selector,
                sendAmount_,
                AMOUNT
            )
        );

        // Call function
        vm.prank(SENDER);
        bridge.sendToSVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, SVM_RECIPIENT, sendAmount_);
    }

    function test_sendToSVM_spendingNotApproved_reverts()
        public
        givenContractIsEnabled
        givenDestinationSVMChainHasTrustedRemote
        givenSenderHasApprovedSpendingOHM(AMOUNT - 1)
    {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        vm.prank(SENDER);
        bridge.sendToSVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, SVM_RECIPIENT, AMOUNT);
    }

    function test_sendToSVM_destinationChainNotTrusted_reverts()
        public
        givenContractIsEnabled
        givenSenderHasApprovedSpendingOHM(AMOUNT)
    {
        // Expect revert
        vm.expectRevert(ICCIPCrossChainBridge.Bridge_DestinationNotTrusted.selector);

        // Call function
        vm.prank(SENDER);
        bridge.sendToSVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, SVM_RECIPIENT, AMOUNT);
    }

    function test_sendToSVM()
        public
        givenContractIsEnabled
        givenDestinationSVMChainHasTrustedRemote
        givenSenderHasApprovedSpendingOHM(AMOUNT)
    {
        // Expect event
        vm.expectEmit();
        emit Bridged(router.DEFAULT_MESSAGE_ID(), DESTINATION_CHAIN_SELECTOR, SENDER, AMOUNT, FEE);

        // Call function
        vm.prank(SENDER);
        bridge.sendToSVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, SVM_RECIPIENT, AMOUNT);

        // Assert message parameters
        assertEq(
            router.destinationChainSelector(),
            DESTINATION_CHAIN_SELECTOR,
            "destinationChainSelector"
        );
        assertEq(router.messageReceiver(), abi.encodePacked(SVM_TRUSTED_REMOTE), "messageReceiver");
        assertEq(router.messageData().length, 0, "messageData");
        assertEq(router.messageFeeToken(), address(0), "messageFeeToken");
        address[] memory tokens = router.getMessageTokens();
        assertEq(tokens.length, 1, "tokens.length");
        assertEq(tokens[0], address(OHM), "tokens[0]");
        uint256[] memory amounts = router.getMessageTokenAmounts();
        assertEq(amounts.length, 1, "amounts.length");
        assertEq(amounts[0], AMOUNT, "amounts[0]");
        bytes memory extraArgs = router.messageExtraArgs();
        assertEq(
            extraArgs,
            Client._svmArgsToBytes(
                Client.SVMExtraArgsV1({
                    computeUnits: 0,
                    accountIsWritableBitmap: 0,
                    allowOutOfOrderExecution: true,
                    tokenReceiver: SVM_RECIPIENT,
                    accounts: new bytes32[](0)
                })
            ),
            "extraArgs"
        );

        // Assert token balances
        assertEq(OHM.balanceOf(SENDER), 0, "SENDER OHM balance");
        assertEq(OHM.balanceOf(address(bridge)), 0, "bridge OHM balance");
        assertEq(OHM.balanceOf(address(router)), AMOUNT, "router OHM balance");
        assertEq(SENDER.balance, ETH_AMOUNT - FEE, "SENDER ETH balance");
        assertEq(address(bridge).balance, 0, "bridge ETH balance");
        assertEq(address(router).balance, FEE, "router ETH balance");
    }

    // sendToEVM
    // given the contract is not enabled
    //  [X] it reverts
    // when the amount is zero
    //  [X] it reverts
    // when the sender has not provided enough native token to cover fees
    //  [X] it reverts
    // given the sender has insufficient OHM
    //  [X] it reverts
    // given the sender has not approved the contract to spend OHM
    //  [X] it reverts
    // given the destination chain does not have a defined CrossChainBridge
    //  [X] it reverts
    // [X] the recipient address is the destination chain's CrossChainBridge address
    // [X] the data contains the actual recipient address
    // [X] the EVM extra args gas limit is the default gas limit
    // [X] the EVM extra args allow out of order execution is true
    // [X] the bridge transfers the OHM from the sender to itself
    // [X] the bridge transfers the fee from the sender to itself
    // [X] the CCIP router is called with the correct parameters
    // [X] the CCIP router transfers the OHM to itself
    // [X] the CCIP router transfers the fee to itself
    // [X] a Bridged event is emitted

    function test_sendToEVM_notEnabled_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));

        // Call function
        vm.prank(SENDER);
        bridge.sendToEVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, EVM_RECIPIENT, AMOUNT);
    }

    function test_sendToEVM_amountZero_reverts()
        public
        givenContractIsEnabled
        givenDestinationEVMChainHasTrustedRemote
    {
        // Expect revert
        vm.expectRevert(ICCIPCrossChainBridge.Bridge_ZeroAmount.selector);

        // Call function
        vm.prank(SENDER);
        bridge.sendToEVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, EVM_RECIPIENT, 0);
    }

    function test_sendToEVM_notEnoughNativeToken_reverts(
        uint256 msgValue_
    ) public givenContractIsEnabled givenDestinationEVMChainHasTrustedRemote {
        // Bound the msg.value to be less than the fee
        msgValue_ = bound(msgValue_, 0, FEE - 1);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPCrossChainBridge.Bridge_InsufficientNativeToken.selector,
                FEE,
                msgValue_
            )
        );

        // Call function
        vm.prank(SENDER);
        bridge.sendToEVM{value: msgValue_}(DESTINATION_CHAIN_SELECTOR, EVM_RECIPIENT, AMOUNT);
    }

    function test_sendToEVM_insufficientOHM_reverts(
        uint256 sendAmount_
    ) public givenContractIsEnabled givenDestinationEVMChainHasTrustedRemote {
        // Bound the send amount to be more than the sender's OHM balance
        sendAmount_ = bound(sendAmount_, AMOUNT + 1, type(uint256).max);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPCrossChainBridge.Bridge_InsufficientAmount.selector,
                sendAmount_,
                AMOUNT
            )
        );

        // Call function
        vm.prank(SENDER);
        bridge.sendToEVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, EVM_RECIPIENT, sendAmount_);
    }

    function test_sendToEVM_spendingNotApproved_reverts()
        public
        givenContractIsEnabled
        givenDestinationEVMChainHasTrustedRemote
        givenSenderHasApprovedSpendingOHM(AMOUNT - 1)
    {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        vm.prank(SENDER);
        bridge.sendToEVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, EVM_RECIPIENT, AMOUNT);
    }

    function test_sendToEVM_destinationChainNotTrusted_reverts()
        public
        givenContractIsEnabled
        givenSenderHasApprovedSpendingOHM(AMOUNT - 1)
    {
        // Expect revert
        vm.expectRevert(ICCIPCrossChainBridge.Bridge_DestinationNotTrusted.selector);

        // Call function
        vm.prank(SENDER);
        bridge.sendToEVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, EVM_RECIPIENT, AMOUNT);
    }

    function test_sendToEVM()
        public
        givenContractIsEnabled
        givenDestinationEVMChainHasTrustedRemote
        givenSenderHasApprovedSpendingOHM(AMOUNT)
    {
        // Expect event
        vm.expectEmit();
        emit Bridged(router.DEFAULT_MESSAGE_ID(), DESTINATION_CHAIN_SELECTOR, SENDER, AMOUNT, FEE);

        // Call function
        vm.prank(SENDER);
        bridge.sendToEVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, EVM_RECIPIENT, AMOUNT);

        // Assert message parameters
        assertEq(
            router.destinationChainSelector(),
            DESTINATION_CHAIN_SELECTOR,
            "destinationChainSelector"
        );
        assertEq(router.messageReceiver(), abi.encode(EVM_TRUSTED_REMOTE), "messageReceiver");
        bytes memory messageData = router.messageData();
        assertEq(abi.decode(messageData, (address)), EVM_RECIPIENT, "messageData");
        assertEq(router.messageFeeToken(), address(0), "messageFeeToken");
        address[] memory tokens = router.getMessageTokens();
        assertEq(tokens.length, 1, "tokens.length");
        assertEq(tokens[0], address(OHM), "tokens[0]");
        uint256[] memory amounts = router.getMessageTokenAmounts();
        assertEq(amounts.length, 1, "amounts.length");
        assertEq(amounts[0], AMOUNT, "amounts[0]");
        bytes memory extraArgs = router.messageExtraArgs();
        assertEq(
            extraArgs,
            Client._argsToBytes(
                Client.GenericExtraArgsV2({gasLimit: 200_000, allowOutOfOrderExecution: true})
            ),
            "extraArgs"
        );

        // Assert token balances
        assertEq(OHM.balanceOf(SENDER), 0, "SENDER OHM balance");
        assertEq(OHM.balanceOf(address(bridge)), 0, "bridge OHM balance");
        assertEq(OHM.balanceOf(address(router)), AMOUNT, "router OHM balance");
        assertEq(SENDER.balance, ETH_AMOUNT - FEE, "SENDER ETH balance");
        assertEq(address(bridge).balance, 0, "bridge ETH balance");
        assertEq(address(router).balance, FEE, "router ETH balance");
    }

    // ccipReceive
    // when the caller is not the CCIP router
    //  [X] it reverts
    // given the contract is not enabled
    //  [X] it marks the message as failed
    //  [X] it emits an event
    // given the message handler fails
    //  [X] it marks the message as failed
    //  [X] it emits an event
    // [X] it transfers the OHM to the recipient

    function test_ccipReceive_callerNotRouter_reverts() public givenContractIsEnabled {
        Client.Any2EVMMessage memory message = _getAnyToEVMMessage();

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, address(this)));

        // Call function
        vm.prank(address(this));
        bridge.ccipReceive(message);
    }

    function test_ccipReceive_notEnabled()
        public
        givenSourceEVMChainHasTrustedRemote
        givenBridgeHasOHMBalance(AMOUNT)
    {
        Client.Any2EVMMessage memory message = _getAnyToEVMMessage();

        // Expect emit
        vm.expectEmit();
        emit MessageFailed(message.messageId);

        // Call function
        vm.prank(address(router));
        bridge.ccipReceive(message);

        // Assert state
        ICCIPClient.Any2EVMMessage memory failedMessage = bridge.getFailedMessage(
            message.messageId
        );
        assertEq(failedMessage.messageId, message.messageId, "messageId");
        assertEq(
            failedMessage.sourceChainSelector,
            message.sourceChainSelector,
            "sourceChainSelector"
        );
        assertEq(failedMessage.sender, message.sender, "sender");
        assertEq(failedMessage.data, message.data, "data");
        ICCIPClient.EVMTokenAmount[] memory destTokenAmounts = failedMessage.destTokenAmounts;
        for (uint256 i = 0; i < destTokenAmounts.length; i++) {
            assertEq(
                destTokenAmounts[i].token,
                message.destTokenAmounts[i].token,
                "destTokenAmounts[i].token"
            );
            assertEq(
                destTokenAmounts[i].amount,
                message.destTokenAmounts[i].amount,
                "destTokenAmounts[i].amount"
            );
        }
    }

    function test_ccipReceive_messageHandlerReverts() public givenContractIsEnabled {
        Client.Any2EVMMessage memory message = _getAnyToEVMMessage();

        // Expect emit
        vm.expectEmit();
        emit MessageFailed(message.messageId);

        // Call function
        // Will fail due to the lack of a trusted remote
        vm.prank(address(router));
        bridge.ccipReceive(message);

        // Assert state
        ICCIPClient.Any2EVMMessage memory failedMessage = bridge.getFailedMessage(
            message.messageId
        );
        assertEq(failedMessage.messageId, message.messageId, "messageId");
        assertEq(
            failedMessage.sourceChainSelector,
            message.sourceChainSelector,
            "sourceChainSelector"
        );
        assertEq(failedMessage.sender, message.sender, "sender");
        assertEq(failedMessage.data, message.data, "data");
        ICCIPClient.EVMTokenAmount[] memory destTokenAmounts = failedMessage.destTokenAmounts;
        for (uint256 i = 0; i < destTokenAmounts.length; i++) {
            assertEq(
                destTokenAmounts[i].token,
                message.destTokenAmounts[i].token,
                "destTokenAmounts[i].token"
            );
            assertEq(
                destTokenAmounts[i].amount,
                message.destTokenAmounts[i].amount,
                "destTokenAmounts[i].amount"
            );
        }
    }

    function test_ccipReceive()
        public
        givenContractIsEnabled
        givenSourceEVMChainHasTrustedRemote
        givenBridgeHasOHMBalance(AMOUNT)
    {
        Client.Any2EVMMessage memory message = _getAnyToEVMMessage();

        // Expect event
        vm.expectEmit();
        emit Received(MESSAGE_ID, SOURCE_CHAIN_SELECTOR, EVM_TRUSTED_REMOTE, AMOUNT);

        // Call function
        vm.prank(address(router));
        bridge.ccipReceive(message);

        // Assert state
        assertEq(OHM.balanceOf(EVM_RECIPIENT), AMOUNT, "OHM balance");
        assertEq(
            bridge.getFailedMessage(MESSAGE_ID).sender,
            "",
            "should not have a failed message"
        );
    }

    // receiveMessage
    // when the caller is not the contract
    //  [X] it reverts
    // given the contract is not enabled
    //  [X] it reverts
    // given the source bridge is not trusted
    //  [X] it reverts
    // when the message has multiple tokens
    //  [X] it reverts
    // when the message has does not use the destination OHM token
    //  [X] it reverts
    // when the message data has an invalid format
    //  [X] it reverts
    // [X] it transfers the OHM to the recipient
    // [X] it emits an event

    function _getAnyToEVMMessage() internal view returns (Client.Any2EVMMessage memory) {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(OHM), amount: AMOUNT});

        return
            Client.Any2EVMMessage({
                messageId: MESSAGE_ID,
                sourceChainSelector: SOURCE_CHAIN_SELECTOR,
                sender: abi.encode(EVM_TRUSTED_REMOTE),
                data: abi.encode(EVM_RECIPIENT),
                destTokenAmounts: tokenAmounts
            });
    }

    function test_receiveMessage_callerNotSelf_reverts()
        public
        givenContractIsEnabled
        givenSourceEVMChainHasTrustedRemote
    {
        Client.Any2EVMMessage memory message = _getAnyToEVMMessage();

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPCrossChainBridge.Bridge_InvalidCaller.selector)
        );

        // Call function
        vm.prank(address(this));
        bridge.receiveMessage(message);
    }

    function test_receiveMessage_notEnabled_reverts() public givenSourceEVMChainHasTrustedRemote {
        Client.Any2EVMMessage memory message = _getAnyToEVMMessage();

        // Expect revert
        vm.expectRevert(IEnabler.NotEnabled.selector);

        // Call function
        vm.prank(address(bridge));
        bridge.receiveMessage(message);
    }

    function test_receiveMessage_sourceBridgeNotTrusted_reverts() public givenContractIsEnabled {
        Client.Any2EVMMessage memory message = _getAnyToEVMMessage();

        // Expect revert
        vm.expectRevert(ICCIPCrossChainBridge.Bridge_SourceNotTrusted.selector);

        // Call function
        vm.prank(address(bridge));
        bridge.receiveMessage(message);
    }

    function test_receiveMessage_multipleTokens_reverts()
        public
        givenContractIsEnabled
        givenSourceEVMChainHasTrustedRemote
    {
        MockERC20 newToken = new MockERC20("New Token", "NT", 18);
        Client.Any2EVMMessage memory message = _getAnyToEVMMessage();
        message.destTokenAmounts = new Client.EVMTokenAmount[](2);
        message.destTokenAmounts[0] = Client.EVMTokenAmount({token: address(OHM), amount: AMOUNT});
        message.destTokenAmounts[1] = Client.EVMTokenAmount({
            token: address(newToken),
            amount: AMOUNT
        });

        // Expect revert
        vm.expectRevert(ICCIPCrossChainBridge.Bridge_InvalidPayloadTokensLength.selector);

        // Call function
        vm.prank(address(bridge));
        bridge.receiveMessage(message);
    }

    function test_receiveMessage_invalidToken_reverts()
        public
        givenContractIsEnabled
        givenSourceEVMChainHasTrustedRemote
    {
        MockERC20 newToken = new MockERC20("New Token", "NT", 18);
        Client.Any2EVMMessage memory message = _getAnyToEVMMessage();
        message.destTokenAmounts[0].token = address(newToken);

        // Expect revert
        vm.expectRevert(ICCIPCrossChainBridge.Bridge_InvalidPayloadToken.selector);

        // Call function
        vm.prank(address(bridge));
        bridge.receiveMessage(message);
    }

    function test_receiveMessage_invalidData_reverts()
        public
        givenContractIsEnabled
        givenSourceEVMChainHasTrustedRemote
    {
        Client.Any2EVMMessage memory message = _getAnyToEVMMessage();
        // Incorrect data format
        message.data = abi.encode(EVM_RECIPIENT, 12345);

        // Expect revert
        // With no data, due to abi.decode()
        vm.expectRevert();

        // Call function
        vm.prank(address(bridge));
        bridge.receiveMessage(message);
    }

    function test_receiveMessage()
        public
        givenContractIsEnabled
        givenSourceEVMChainHasTrustedRemote
        givenBridgeHasOHMBalance(AMOUNT)
    {
        Client.Any2EVMMessage memory message = _getAnyToEVMMessage();

        // Expect event
        vm.expectEmit();
        emit Received(MESSAGE_ID, SOURCE_CHAIN_SELECTOR, EVM_TRUSTED_REMOTE, AMOUNT);

        // Call function
        vm.prank(address(bridge));
        bridge.receiveMessage(message);

        // Assert state
        assertEq(OHM.balanceOf(EVM_RECIPIENT), AMOUNT, "OHM balance");
    }

    // retryFailedMessage
    // when the message id is not in the failedMessages mapping
    //  [X] it reverts
    // given the contract is not enabled
    //  [X] it reverts
    // given the message execution fails again
    //  [X] it reverts
    // [X] it transfers the OHM to the recipient
    // [X] it removes the message from the failedMessages mapping
    // [X] it emits an event

    function test_retryFailedMessage_messageIdNotFound_reverts() public givenContractIsEnabled {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPCrossChainBridge.Bridge_FailedMessageNotFound.selector,
                MESSAGE_ID
            )
        );

        // Call function
        bridge.retryFailedMessage(MESSAGE_ID);
    }

    function test_retryFailedMessage_notEnabled_reverts()
        public
        givenSourceEVMChainHasTrustedRemote
    {
        Client.Any2EVMMessage memory message = _getAnyToEVMMessage();

        // Initial attempt to execute
        vm.prank(address(router));
        bridge.ccipReceive(message);

        // Expect revert
        vm.expectRevert(IEnabler.NotEnabled.selector);

        // Call function
        bridge.retryFailedMessage(MESSAGE_ID);
    }

    function test_retryFailedMessage_messageExecutionReverts_reverts()
        public
        givenContractIsEnabled
    {
        Client.Any2EVMMessage memory message = _getAnyToEVMMessage();

        // Initial attempt to execute
        vm.prank(address(router));
        bridge.ccipReceive(message);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPCrossChainBridge.Bridge_SourceNotTrusted.selector)
        );

        // Call function
        bridge.retryFailedMessage(MESSAGE_ID);
    }

    function test_retryFailedMessage()
        public
        givenContractIsEnabled
        givenBridgeHasOHMBalance(AMOUNT)
    {
        Client.Any2EVMMessage memory message = _getAnyToEVMMessage();

        // Initial attempt to execute
        vm.prank(address(router));
        bridge.ccipReceive(message);

        // Set the sending bridge as trusted, which will allow the message to succeed
        vm.prank(OWNER);
        bridge.setTrustedRemoteEVM(SOURCE_CHAIN_SELECTOR, EVM_TRUSTED_REMOTE);

        // Expect event
        vm.expectEmit();
        emit Received(MESSAGE_ID, SOURCE_CHAIN_SELECTOR, EVM_TRUSTED_REMOTE, AMOUNT);

        // Call function
        bridge.retryFailedMessage(MESSAGE_ID);

        // Assert state
        assertEq(OHM.balanceOf(EVM_RECIPIENT), AMOUNT, "OHM balance");
        assertEq(
            bridge.getFailedMessage(MESSAGE_ID).sender,
            "",
            "failed message should be deleted"
        );
    }

    // withdraw
    // when the caller is not the owner
    //  [X] it reverts
    // given the balance is zero
    //  [X] it reverts
    // given the recipient is the zero address
    //  [X] it reverts
    // given the native token transfer fails
    //  [X] it reverts
    // given the contract is not enabled
    //  [X] the contract transfers the native token to the recipient
    //  [X] a Withdrawn event is emitted
    // [X] the contract transfers the native token to the recipient
    // [X] a Withdrawn event is emitted

    function test_withdraw_callerNotOwner_reverts() public {
        // Expect revert
        vm.expectRevert("UNAUTHORIZED");

        // Call function
        vm.prank(SENDER);
        bridge.withdraw(TRSRY);
    }

    function test_withdraw_balanceZero_reverts() public givenContractIsEnabled {
        // Expect revert
        vm.expectRevert(ICCIPCrossChainBridge.Bridge_ZeroAmount.selector);

        // Call function
        vm.prank(OWNER);
        bridge.withdraw(TRSRY);
    }

    function test_withdraw_recipientZeroAddress_reverts() public givenContractIsEnabled {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPCrossChainBridge.Bridge_InvalidAddress.selector,
                "recipient"
            )
        );

        // Call function
        vm.prank(OWNER);
        bridge.withdraw(address(0));
    }

    function test_withdraw_transferFailed_reverts()
        public
        givenContractIsEnabled
        givenBridgeHasEthBalance(1e18)
    {
        // Create a contract that is unable to receive ETH
        MockERC20 newContract = new MockERC20("New Contract", "NC", 18);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPCrossChainBridge.Bridge_TransferFailed.selector,
                address(OWNER),
                address(newContract),
                1e18
            )
        );

        // Call function
        vm.prank(OWNER);
        bridge.withdraw(address(newContract));
    }

    function test_withdraw_notEnabled() public givenBridgeHasEthBalance(1e18) {
        // Expect event
        vm.expectEmit();
        emit Withdrawn(TRSRY, 1e18);

        // Call function
        vm.prank(OWNER);
        bridge.withdraw(TRSRY);

        // Assert state
        assertEq(address(bridge).balance, 0, "bridge balance");
        assertEq(TRSRY.balance, 1e18, "TRSRY balance");
    }

    function test_withdraw() public givenContractIsEnabled givenBridgeHasEthBalance(1e18) {
        // Expect event
        vm.expectEmit();
        emit Withdrawn(TRSRY, 1e18);

        // Call function
        vm.prank(OWNER);
        bridge.withdraw(TRSRY);

        // Assert state
        assertEq(address(bridge).balance, 0, "bridge balance");
        assertEq(TRSRY.balance, 1e18, "TRSRY balance");
    }

    // getFeeSVM
    // given the destination chain does not have a trusted remote
    //  [X] it reverts
    // [X] it returns the mock fee

    function test_getFeeSVM_destinationChainNotTrusted_reverts() public {
        // Expect revert
        vm.expectRevert(ICCIPCrossChainBridge.Bridge_DestinationNotTrusted.selector);

        // Call function
        bridge.getFeeSVM(DESTINATION_CHAIN_SELECTOR, SVM_RECIPIENT, AMOUNT);
    }

    function test_getFeeSVM() public givenDestinationSVMChainHasTrustedRemote {
        // Call function
        uint256 fee = bridge.getFeeSVM(DESTINATION_CHAIN_SELECTOR, SVM_RECIPIENT, AMOUNT);

        // Assert
        assertEq(fee, FEE, "fee");
    }

    // getFeeEVM
    // given the destination chain does not have a trusted remote
    //  [X] it reverts
    // [X] it returns the mock fee

    function test_getFeeEVM_destinationChainNotTrusted_reverts() public {
        // Expect revert
        vm.expectRevert(ICCIPCrossChainBridge.Bridge_DestinationNotTrusted.selector);

        // Call function
        bridge.getFeeEVM(DESTINATION_CHAIN_SELECTOR, EVM_RECIPIENT, AMOUNT);
    }

    function test_getFeeEVM() public givenDestinationEVMChainHasTrustedRemote {
        // Call function
        uint256 fee = bridge.getFeeEVM(DESTINATION_CHAIN_SELECTOR, EVM_RECIPIENT, AMOUNT);

        // Assert
        assertEq(fee, FEE, "fee");
    }

    // supportsInterface
    // when the interface id is the IAny2EVMMessageReceiver interface id
    //  [X] it returns true
    // when the interface id is the ICCIPCrossChainBridge interface id
    //  [X] it returns true
    // [X] it returns false

    function test_supportsInterface() public view {
        assertEq(
            bridge.supportsInterface(type(IAny2EVMMessageReceiver).interfaceId),
            true,
            "IAny2EVMMessageReceiver"
        );
        assertEq(
            bridge.supportsInterface(type(ICCIPCrossChainBridge).interfaceId),
            true,
            "ICCIPCrossChainBridge"
        );
        assertEq(bridge.supportsInterface(type(IERC165).interfaceId), true, "IERC165");
        assertEq(bridge.supportsInterface(type(IERC20).interfaceId), false, "IERC20");
    }

    // setTrustedRemoteEVM
    // when the caller is not the owner
    //  [X] it reverts
    // [X] it sets the trusted remote for the destination chain
    // [X] it emits an event

    function test_setTrustedRemoteEVM_callerNotOwner_reverts() public {
        // Expect revert
        vm.expectRevert("UNAUTHORIZED");

        // Call function
        vm.prank(SENDER);
        bridge.setTrustedRemoteEVM(DESTINATION_CHAIN_SELECTOR, EVM_RECIPIENT);
    }

    function test_setTrustedRemoteEVM() public {
        // Expect event
        vm.expectEmit();
        emit TrustedRemoteEVMSet(DESTINATION_CHAIN_SELECTOR, EVM_RECIPIENT);

        // Call function
        vm.prank(OWNER);
        bridge.setTrustedRemoteEVM(DESTINATION_CHAIN_SELECTOR, EVM_RECIPIENT);

        // Assert state
        assertEq(
            bridge.getTrustedRemoteEVM(DESTINATION_CHAIN_SELECTOR),
            EVM_RECIPIENT,
            "trustedRemoteEVM"
        );
        assertEq(
            bridge.getTrustedRemoteSVM(DESTINATION_CHAIN_SELECTOR),
            bytes32(0),
            "trustedRemoteSVM"
        );
    }

    // setTrustedRemoteSVM
    // when the caller is not the owner
    //  [X] it reverts
    // [X] it sets the trusted remote for the destination chain
    // [X] it emits an event

    function test_setTrustedRemoteSVM_callerNotOwner_reverts() public {
        // Expect revert
        vm.expectRevert("UNAUTHORIZED");

        // Call function
        vm.prank(SENDER);
        bridge.setTrustedRemoteSVM(DESTINATION_CHAIN_SELECTOR, SVM_TRUSTED_REMOTE);
    }

    function test_setTrustedRemoteSVM() public {
        // Expect event
        vm.expectEmit();
        emit TrustedRemoteSVMSet(DESTINATION_CHAIN_SELECTOR, SVM_TRUSTED_REMOTE);

        // Call function
        vm.prank(OWNER);
        bridge.setTrustedRemoteSVM(DESTINATION_CHAIN_SELECTOR, SVM_TRUSTED_REMOTE);

        // Assert state
        assertEq(
            bridge.getTrustedRemoteSVM(DESTINATION_CHAIN_SELECTOR),
            SVM_TRUSTED_REMOTE,
            "trustedRemoteSVM"
        );
        assertEq(
            bridge.getTrustedRemoteEVM(DESTINATION_CHAIN_SELECTOR),
            address(0),
            "trustedRemoteEVM"
        );
    }
}
