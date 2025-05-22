// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

import {Test} from "@forge-std-1.9.6/Test.sol";

// Mocks
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockCCIPRouter} from "src/test/policies/bridge/mocks/MockCCIPRouter.sol";
import {MockRMNProxy} from "src/test/policies/bridge/mocks/MockRMNProxy.sol";

// Contracts
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {CCIPLockReleaseTokenPool} from "src/periphery/bridge/CCIPLockReleaseTokenPool.sol";
import {Ownable2Step} from "@chainlink-ccip-1.6.0/shared/access/Ownable2Step.sol";
import {RateLimiter} from "@chainlink-ccip-1.6.0/ccip/libraries/RateLimiter.sol";
import {TokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/TokenPool.sol";
import {Pool} from "@chainlink-ccip-1.6.0/ccip/libraries/Pool.sol";

contract CCIPLockReleaseTokenPoolTest is Test {
    event Locked(address indexed sender, uint256 amount);
    event Released(address indexed sender, address indexed recipient, uint256 amount);

    MockCCIPRouter public router;
    MockRMNProxy public RMNProxy;
    MockOhm public OHM;
    MockOhm public remoteOHM;

    CCIPLockReleaseTokenPool public tokenPool;

    address public OWNER;
    address public SENDER;
    address public RECEIVER;
    address public ONRAMP;
    address public OFFRAMP;

    address public REMOTE_POOL;

    uint256 public constant AMOUNT = 1e9;
    uint64 public constant REMOTE_CHAIN = 111;

    function setUp() public {
        // Create the addresses
        OWNER = makeAddr("OWNER");
        SENDER = makeAddr("SENDER");
        RECEIVER = makeAddr("RECEIVER");
        ONRAMP = makeAddr("ONRAMP");
        OFFRAMP = makeAddr("OFFRAMP");
        REMOTE_POOL = makeAddr("REMOTE_POOL");

        // Create the OHM token
        OHM = new MockOhm("Olympus", "OHM", 9);
        remoteOHM = new MockOhm("OlympusRemote", "OHMR", 9);

        // Create the CCIP mocks
        router = new MockCCIPRouter();
        RMNProxy = new MockRMNProxy();
        router.setOffRamp(OFFRAMP);
        router.setOnRamp(ONRAMP);
        RMNProxy.setIsCursed(bytes16(uint128(REMOTE_CHAIN)), false);

        // Create the token pool
        vm.prank(OWNER);
        tokenPool = new CCIPLockReleaseTokenPool(address(OHM), address(RMNProxy), address(router));
    }

    modifier givenIsEnabled() {
        vm.prank(OWNER);
        tokenPool.enable("");
        _;
    }

    modifier givenIsDisabled() {
        vm.prank(OWNER);
        tokenPool.disable("");
        _;
    }

    modifier givenTokenPoolHasOHM(uint256 amount_) {
        OHM.mint(address(tokenPool), amount_);
        _;
    }

    modifier givenRemoteChainIsSupported(
        uint64 remoteChainSelector_,
        address remotePool_,
        address remoteTokenAddress_
    ) {
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool_);

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
            remoteChainSelector: remoteChainSelector_,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(remoteTokenAddress_),
            outboundRateLimiterConfig: outboundRateLimiterConfig,
            inboundRateLimiterConfig: inboundRateLimiterConfig
        });

        vm.prank(OWNER);
        tokenPool.applyChainUpdates(new uint64[](0), chainUpdates);
        _;
    }

    function _assertBridgedSupply(uint256 expected) internal view {
        assertEq(tokenPool.getBridgedSupply(), expected, "bridgedSupply");
    }

    function _assertIsEnabled(bool expected) internal view {
        assertEq(tokenPool.isEnabled(), expected, "isEnabled");
    }

    function _expectRevertNotEnabled() internal {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
    }

    function _expectRevertNotDisabled() internal {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotDisabled.selector));
    }

    function _expectRevertNotOwner() internal {
        vm.expectRevert(abi.encodeWithSelector(Ownable2Step.OnlyCallableByOwner.selector));
    }

    function _assertTokenPoolOhmBalance(uint256 expected_) internal view {
        assertEq(OHM.balanceOf(address(tokenPool)), expected_, "token pool ohm balance");
    }

    function _assertReceiverOhmBalance(uint256 expected_) internal view {
        assertEq(OHM.balanceOf(RECEIVER), expected_, "receiver ohm balance");
    }

    // ============ TESTS ============ //

    // enable
    // given the contraact is enabled
    //  [X] it reverts
    // given the caller is not the owner
    //  [X] it reverts
    // [X] it enables the contract

    function test_enable_givenEnabled_reverts() public givenIsEnabled {
        // Expect revert
        _expectRevertNotDisabled();

        // Call function
        vm.prank(OWNER);
        tokenPool.enable("");
    }

    function test_enable_callerNotOwner_reverts(address caller_) public {
        vm.assume(caller_ != OWNER);

        // Expect revert
        _expectRevertNotOwner();

        // Call function
        vm.prank(caller_);
        tokenPool.enable("");
    }

    function test_enable() public {
        // Call function
        vm.prank(OWNER);
        tokenPool.enable("");

        // Assert
        _assertIsEnabled(true);
    }

    // disable
    // given the contract is disabled
    //  [X] it reverts
    // given the caller is not the owner
    //  [X] it reverts
    // [X] it disables the contract

    function test_disable_givenDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(OWNER);
        tokenPool.disable("");
    }

    function test_disable_callerNotAdmin_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != OWNER);

        // Expect revert
        _expectRevertNotOwner();

        // Call function
        vm.prank(caller_);
        tokenPool.disable("");
    }

    function test_disable() public givenIsEnabled {
        // Call function
        vm.prank(OWNER);
        tokenPool.disable("");

        // Assert
        _assertIsEnabled(false);
    }

    // lockOrBurn
    // given the policy is disabled
    //  [X] it reverts
    // given the provided token is not the configured token of the token pool
    //  [X] it reverts
    // given the destination chain is not supported
    //  [X] it reverts
    // given the destination chain is cursed by the RMN
    //  [X] it reverts
    // given the caller is not the configured OnRamp for the destination chain
    //  [X] it reverts
    // [X] the bridged supply is incremented
    // [X] a Locked event is emitted
    // [X] it returns the destination token address
    // [X] it returns the pool data as encoded local decimals

    function _getLockOrBurnParams(
        uint256 amount_
    ) internal view returns (Pool.LockOrBurnInV1 memory) {
        return
            Pool.LockOrBurnInV1({
                receiver: abi.encode(RECEIVER),
                remoteChainSelector: REMOTE_CHAIN,
                originalSender: SENDER,
                amount: amount_,
                localToken: address(OHM)
            });
    }

    function test_lockOrBurn_givenDisabled_reverts()
        public
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
    {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(ONRAMP);
        tokenPool.lockOrBurn(_getLockOrBurnParams(AMOUNT));
    }

    function test_lockOrBurn_givenDifferentToken_reverts()
        public
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenTokenPoolHasOHM(AMOUNT)
    {
        // Create a new OHM token that will be passed to lockOrBurn
        MockOhm newOhm = new MockOhm("Olympus2", "OHM2", 9);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(TokenPool.InvalidToken.selector, address(newOhm)));

        // Call function
        vm.prank(ONRAMP);
        tokenPool.lockOrBurn(
            Pool.LockOrBurnInV1({
                receiver: abi.encode(RECEIVER),
                remoteChainSelector: REMOTE_CHAIN,
                originalSender: SENDER,
                amount: AMOUNT,
                localToken: address(newOhm)
            })
        );
    }

    function test_lockOrBurn_givenUnsupportedRemoteChain_reverts()
        public
        givenIsEnabled
        givenTokenPoolHasOHM(AMOUNT)
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(TokenPool.ChainNotAllowed.selector, REMOTE_CHAIN));

        // Call function
        vm.prank(ONRAMP);
        tokenPool.lockOrBurn(_getLockOrBurnParams(AMOUNT));
    }

    function test_lockOrBurn_remoteChainCursed_reverts()
        public
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenTokenPoolHasOHM(AMOUNT)
    {
        // Mark the remote chain as cursed
        RMNProxy.setIsCursed(bytes16(uint128(REMOTE_CHAIN)), true);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(TokenPool.CursedByRMN.selector));

        // Call function
        vm.prank(ONRAMP);
        tokenPool.lockOrBurn(_getLockOrBurnParams(AMOUNT));
    }

    function test_lockOrBurn_callerNotOnRamp_reverts()
        public
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenTokenPoolHasOHM(AMOUNT)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(TokenPool.CallerIsNotARampOnRouter.selector, SENDER)
        );

        // Call function
        vm.prank(SENDER);
        tokenPool.lockOrBurn(_getLockOrBurnParams(AMOUNT));
    }

    function test_lockOrBurn(
        uint256 sendAmount_
    )
        public
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenTokenPoolHasOHM(AMOUNT)
    {
        sendAmount_ = bound(sendAmount_, 1, AMOUNT);

        // Expect event
        vm.expectEmit();
        emit Locked(ONRAMP, sendAmount_);

        // Call function
        vm.prank(ONRAMP);
        Pool.LockOrBurnOutV1 memory result = tokenPool.lockOrBurn(
            _getLockOrBurnParams(sendAmount_)
        );

        // Assert
        _assertBridgedSupply(AMOUNT);
        _assertTokenPoolOhmBalance(AMOUNT);
        _assertReceiverOhmBalance(0);
        assertEq(result.destTokenAddress, abi.encode(address(remoteOHM)), "destTokenAddress");
        assertEq(result.destPoolData, abi.encode(9), "destPoolData");
    }

    // releaseOrMint
    // given the policy is disabled
    //  [X] it reverts
    // given the provided token is not the configured token of the token pool
    //  [X] it reverts
    // given the source chain is not supported
    //  [X] it reverts
    // given the source chain is cursed by the RMN
    //  [X] it reverts
    // given the caller is not the configured OffRamp for the source chain
    //  [X] it reverts
    // [X] the bridged supply is decremented
    // [X] a Released event is emitted
    // [X] it returns the local amount

    function _getReleaseOrMintParams(
        uint256 amount_
    ) internal view returns (Pool.ReleaseOrMintInV1 memory) {
        return
            Pool.ReleaseOrMintInV1({
                originalSender: abi.encode(SENDER),
                remoteChainSelector: REMOTE_CHAIN,
                receiver: RECEIVER,
                amount: amount_,
                localToken: address(OHM),
                sourcePoolAddress: abi.encode(REMOTE_POOL),
                sourcePoolData: abi.encode(9),
                offchainTokenData: ""
            });
    }

    function test_releaseOrMint_givenDisabled_reverts()
        public
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
    {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(OFFRAMP);
        tokenPool.releaseOrMint(_getReleaseOrMintParams(AMOUNT));
    }

    function test_releaseOrMint_givenDifferentToken_reverts()
        public
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenTokenPoolHasOHM(AMOUNT)
    {
        // Create a new OHM token that will be passed to releaseOrMint
        MockOhm newOhm = new MockOhm("Olympus2", "OHM2", 9);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(TokenPool.InvalidToken.selector, address(newOhm)));

        // Call function
        vm.prank(OFFRAMP);
        tokenPool.releaseOrMint(
            Pool.ReleaseOrMintInV1({
                originalSender: abi.encode(SENDER),
                remoteChainSelector: REMOTE_CHAIN,
                receiver: RECEIVER,
                amount: AMOUNT,
                localToken: address(newOhm),
                sourcePoolAddress: abi.encode(REMOTE_POOL),
                sourcePoolData: abi.encode(9),
                offchainTokenData: ""
            })
        );
    }

    function test_releaseOrMint_givenUnsupportedRemoteChain_reverts()
        public
        givenIsEnabled
        givenTokenPoolHasOHM(AMOUNT)
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(TokenPool.ChainNotAllowed.selector, REMOTE_CHAIN));

        // Call function
        vm.prank(OFFRAMP);
        tokenPool.releaseOrMint(_getReleaseOrMintParams(AMOUNT));
    }

    function test_releaseOrMint_sourceChainCursed_reverts()
        public
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenTokenPoolHasOHM(AMOUNT)
    {
        // Mark the remote chain as cursed
        RMNProxy.setIsCursed(bytes16(uint128(REMOTE_CHAIN)), true);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(TokenPool.CursedByRMN.selector));

        // Call function
        vm.prank(OFFRAMP);
        tokenPool.releaseOrMint(_getReleaseOrMintParams(AMOUNT));
    }

    function test_releaseOrMint_callerNotOffRamp_reverts()
        public
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenTokenPoolHasOHM(AMOUNT)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(TokenPool.CallerIsNotARampOnRouter.selector, SENDER)
        );

        // Call function
        vm.prank(SENDER);
        tokenPool.releaseOrMint(_getReleaseOrMintParams(AMOUNT));
    }

    function test_releaseOrMint_originalSenderNotEVM(
        uint256 sendAmount_
    )
        public
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenTokenPoolHasOHM(AMOUNT)
    {
        sendAmount_ = bound(sendAmount_, 1, AMOUNT);

        // Expect event
        vm.expectEmit();
        emit Released(OFFRAMP, RECEIVER, sendAmount_);

        // Call function
        vm.prank(OFFRAMP);
        Pool.ReleaseOrMintOutV1 memory result = tokenPool.releaseOrMint(
            Pool.ReleaseOrMintInV1({
                originalSender: abi.encode(bytes32("11111111111111111111111111111111")), // Mimic an SVM address
                remoteChainSelector: REMOTE_CHAIN,
                receiver: RECEIVER,
                amount: sendAmount_,
                localToken: address(OHM),
                sourcePoolAddress: abi.encode(REMOTE_POOL),
                sourcePoolData: abi.encode(9),
                offchainTokenData: ""
            })
        );

        // Assert
        _assertBridgedSupply(AMOUNT - sendAmount_);
        _assertTokenPoolOhmBalance(AMOUNT - sendAmount_);
        _assertReceiverOhmBalance(sendAmount_);
        assertEq(result.destinationAmount, sendAmount_, "destinationAmount");
    }

    function test_releaseOrMint(
        uint256 sendAmount_
    )
        public
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenTokenPoolHasOHM(AMOUNT)
    {
        sendAmount_ = bound(sendAmount_, 1, AMOUNT);

        // Expect event
        vm.expectEmit();
        emit Released(OFFRAMP, RECEIVER, sendAmount_);

        // Call function
        vm.prank(OFFRAMP);
        Pool.ReleaseOrMintOutV1 memory result = tokenPool.releaseOrMint(
            _getReleaseOrMintParams(sendAmount_)
        );

        // Assert
        _assertBridgedSupply(AMOUNT - sendAmount_);
        _assertTokenPoolOhmBalance(AMOUNT - sendAmount_);
        _assertReceiverOhmBalance(sendAmount_);
        assertEq(result.destinationAmount, sendAmount_, "destinationAmount");
    }

    // getBridgedSupply
    // [X] it returns the balance of OHM in the contract

    function test_getBridgedSupply(uint256 amount_) public {
        amount_ = bound(amount_, 1, AMOUNT);

        // Mint OHM to the token pool
        OHM.mint(address(tokenPool), amount_);

        // Assert
        assertEq(tokenPool.getBridgedSupply(), amount_, "bridgedSupply");
    }
}
