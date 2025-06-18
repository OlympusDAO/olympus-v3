// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

import {Test} from "@forge-std-1.9.6/Test.sol";

// Mocks
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockCCIPRouter} from "src/test/policies/bridge/mocks/MockCCIPRouter.sol";
import {MockRMNProxy} from "src/test/policies/bridge/mocks/MockRMNProxy.sol";

// Contracts
import {IERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {LockReleaseTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/LockReleaseTokenPool.sol";
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

    LockReleaseTokenPool public tokenPool;

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
        tokenPool = new LockReleaseTokenPool(
            IERC20(address(OHM)),
            9,
            new address[](0),
            address(RMNProxy),
            true,
            address(router)
        );
    }

    modifier givenIsEnabled() {
        RateLimiter.Config memory outboundRateLimiterConfig = RateLimiter.Config({
            isEnabled: false, // Rate limiter disabled will enable bridging
            capacity: 0,
            rate: 0
        });
        RateLimiter.Config memory inboundRateLimiterConfig = RateLimiter.Config({
            isEnabled: false, // Rate limiter disabled will enable bridging
            capacity: 0,
            rate: 0
        });

        vm.prank(OWNER);
        tokenPool.setChainRateLimiterConfig(
            REMOTE_CHAIN,
            outboundRateLimiterConfig,
            inboundRateLimiterConfig
        );
        _;
    }

    modifier givenIsDisabled() {
        RateLimiter.Config memory outboundRateLimiterConfig = RateLimiter.Config({
            isEnabled: true, // Rate limiter enabled will disable bridging
            capacity: 2,
            rate: 1
        });
        RateLimiter.Config memory inboundRateLimiterConfig = RateLimiter.Config({
            isEnabled: true, // Rate limiter enabled will disable bridging
            capacity: 2,
            rate: 1
        });

        vm.prank(OWNER);
        tokenPool.setChainRateLimiterConfig(
            REMOTE_CHAIN,
            outboundRateLimiterConfig,
            inboundRateLimiterConfig
        );
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
            isEnabled: true, // Disabled by default
            capacity: 2,
            rate: 1
        });
        RateLimiter.Config memory inboundRateLimiterConfig = RateLimiter.Config({
            isEnabled: true, // Disabled by default
            capacity: 2,
            rate: 1
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
        assertEq(OHM.balanceOf(address(tokenPool)), expected, "bridgedSupply");
    }

    function _expectRevertNotEnabled() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                RateLimiter.TokenMaxCapacityExceeded.selector,
                2,
                AMOUNT,
                address(OHM)
            )
        );
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

    // lockOrBurn
    // given bridging is disabled
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
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenIsEnabled
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
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenIsEnabled
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
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenIsEnabled
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
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenIsEnabled
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
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenIsEnabled
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
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenIsEnabled
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
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenIsEnabled
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
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenIsEnabled
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
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenIsEnabled
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
}
