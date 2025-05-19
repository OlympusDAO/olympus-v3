// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";

import {CCIPCrossChainBridge} from "src/periphery/CCIPCrossChainBridge.sol";
import {ICCIPCrossChainBridge} from "src/periphery/interfaces/ICCIPCrossChainBridge.sol";
import {Client} from "@chainlink-ccip-1.6.0/ccip/libraries/Client.sol";

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

    event BridgeEnabled();

    event BridgeDisabled();

    event Withdrawn(address indexed recipient, uint256 amount);

    CCIPCrossChainBridge public bridge;

    MockERC20 public OHM;
    MockCCIPRouter public router;

    address public SENDER;
    address public OWNER;
    address public EVM_RECIPIENT;
    address public TRSRY;

    uint64 public constant DESTINATION_CHAIN_SELECTOR = 111111;
    bytes32 public constant SVM_RECIPIENT =
        bytes32(0x0000000000000000000000000000000000000000000000000000000000000022);
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
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPCrossChainBridge.Bridge_InvalidAddress.selector,
                "ccipRouter"
            )
        );

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
        assertEq(address(bridge.CCIP_ROUTER()), address(router));
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
        vm.expectRevert(abi.encodeWithSelector(ICCIPCrossChainBridge.Bridge_NotDisabled.selector));

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
        emit BridgeEnabled();

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
        vm.expectRevert(abi.encodeWithSelector(ICCIPCrossChainBridge.Bridge_NotEnabled.selector));

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
        emit BridgeDisabled();

        // Call function
        vm.prank(OWNER);
        bridge.disable("");

        // Assert state
        assertEq(bridge.isEnabled(), false, "isEnabled");
    }

    // sendToSVM
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
    // [X] the recipient address is the default public key
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
        vm.expectRevert(abi.encodeWithSelector(ICCIPCrossChainBridge.Bridge_NotEnabled.selector));

        // Call function
        vm.prank(SENDER);
        bridge.sendToSVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, SVM_RECIPIENT, AMOUNT);
    }

    function test_sendToSVM_amountZero_reverts() public givenContractIsEnabled {
        // Expect revert
        vm.expectRevert(ICCIPCrossChainBridge.Bridge_ZeroAmount.selector);

        // Call function
        vm.prank(SENDER);
        bridge.sendToSVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, SVM_RECIPIENT, 0);
    }

    function test_sendToSVM_notEnoughNativeToken_reverts(
        uint256 msgValue_
    ) public givenContractIsEnabled {
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
    ) public givenContractIsEnabled {
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
        givenSenderHasApprovedSpendingOHM(AMOUNT - 1)
    {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        vm.prank(SENDER);
        bridge.sendToSVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, SVM_RECIPIENT, AMOUNT);
    }

    function test_sendToSVM()
        public
        givenContractIsEnabled
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
        assertEq(router.messageReceiver(), "11111111111111111111111111111111", "messageReceiver");
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
    // [X] the recipient address is the recipient address
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
        vm.expectRevert(abi.encodeWithSelector(ICCIPCrossChainBridge.Bridge_NotEnabled.selector));

        // Call function
        vm.prank(SENDER);
        bridge.sendToEVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, EVM_RECIPIENT, AMOUNT);
    }

    function test_sendToEVM_amountZero_reverts() public givenContractIsEnabled {
        // Expect revert
        vm.expectRevert(ICCIPCrossChainBridge.Bridge_ZeroAmount.selector);

        // Call function
        vm.prank(SENDER);
        bridge.sendToEVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, EVM_RECIPIENT, 0);
    }

    function test_sendToEVM_notEnoughNativeToken_reverts(
        uint256 msgValue_
    ) public givenContractIsEnabled {
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
    ) public givenContractIsEnabled {
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
        givenSenderHasApprovedSpendingOHM(AMOUNT - 1)
    {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        vm.prank(SENDER);
        bridge.sendToEVM{value: FEE}(DESTINATION_CHAIN_SELECTOR, EVM_RECIPIENT, AMOUNT);
    }

    function test_sendToEVM()
        public
        givenContractIsEnabled
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
        assertEq(router.messageReceiver(), abi.encode(EVM_RECIPIENT), "messageReceiver");
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
            Client._argsToBytes(
                Client.GenericExtraArgsV2({gasLimit: 0, allowOutOfOrderExecution: true})
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
    // [X] it returns the mock fee

    function test_getFeeSVM() public view {
        // Call function
        uint256 fee = bridge.getFeeSVM(DESTINATION_CHAIN_SELECTOR, SVM_RECIPIENT, AMOUNT);

        // Assert
        assertEq(fee, FEE, "fee");
    }

    // getFeeEVM
    // [X] it returns the mock fee

    function test_getFeeEVM() public view {
        // Call function
        uint256 fee = bridge.getFeeEVM(DESTINATION_CHAIN_SELECTOR, EVM_RECIPIENT, AMOUNT);

        // Assert
        assertEq(fee, FEE, "fee");
    }
}
