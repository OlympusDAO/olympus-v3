// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";

import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";
import {ICCIPMintBurnTokenPool} from "src/policies/interfaces/ICCIPMintBurnTokenPool.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {CCIPMintBurnTokenPool} from "src/policies/bridge/CCIPMintBurnTokenPool.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockCCIPRouter} from "src/test/policies/bridge/mocks/MockCCIPRouter.sol";
import {MockRMNProxy} from "src/test/policies/bridge/mocks/MockRMNProxy.sol";

import {Pool} from "@chainlink-ccip-1.6.0/ccip/libraries/Pool.sol";
import {RateLimiter} from "@chainlink-ccip-1.6.0/ccip/libraries/RateLimiter.sol";
import {TokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/TokenPool.sol";

// solhint-disable max-states-count
contract CCIPMintBurnTokenPoolTest is Test {
    using ModuleTestFixtureGenerator for OlympusMinter;

    MockCCIPRouter public router;

    MockRMNProxy public RMNProxy;

    MockOhm public OHM;
    MockOhm public remoteOHM;
    OlympusMinter public MINTR;
    OlympusRoles public ROLES;
    Kernel public kernel;
    RolesAdmin public rolesAdmin;
    CCIPMintBurnTokenPool public tokenPool;

    uint256 public constant INITIAL_BRIDGED_SUPPLY = 1_234_567_890;

    address public SENDER;
    address public RECEIVER;
    address public ADMIN;
    address public ONRAMP;
    address public OFFRAMP;

    address public mintrGodmode;

    address public REMOTE_POOL;

    uint256 public constant AMOUNT = 1e9;
    uint64 public constant REMOTE_CHAIN = 111;

    event Burned(address indexed sender, uint256 amount);
    event Minted(address indexed sender, address indexed recipient, uint256 amount);

    function setUp() public {
        // Addresses
        SENDER = makeAddr("SENDER");
        RECEIVER = makeAddr("RECEIVER");
        ADMIN = makeAddr("ADMIN");
        ONRAMP = makeAddr("ONRAMP");
        OFFRAMP = makeAddr("OFFRAMP");
        REMOTE_POOL = makeAddr("REMOTE_POOL");

        // Ensure the chain id is set to mainnet
        vm.chainId(1);

        // Create the OHM token
        OHM = new MockOhm("Olympus", "OHM", 9);
        remoteOHM = new MockOhm("OlympusRemote", "OHMR", 9);

        // Create the stack
        _createStack();
    }

    function _createStack() internal {
        router = new MockCCIPRouter();
        RMNProxy = new MockRMNProxy();

        router.setOffRamp(OFFRAMP);
        router.setOnRamp(ONRAMP);
        RMNProxy.setIsCursed(bytes16(uint128(REMOTE_CHAIN)), false);

        kernel = new Kernel();
        MINTR = new OlympusMinter(kernel, address(OHM));
        ROLES = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        mintrGodmode = MINTR.generateGodmodeFixture(type(OlympusMinter).name);

        // Install into kernel
        kernel.executeAction(Actions.InstallModule, address(MINTR));
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, mintrGodmode);

        // Grant admin role
        rolesAdmin.grantRole("admin", ADMIN);
    }

    // ========= HELPERS ========= //

    function _createTokenPool() internal {
        tokenPool = new CCIPMintBurnTokenPool(
            address(kernel),
            INITIAL_BRIDGED_SUPPLY,
            address(OHM),
            address(RMNProxy),
            address(router),
            1
        );
    }

    function _installTokenPool() internal {
        kernel.executeAction(Actions.ActivatePolicy, address(tokenPool));
    }

    function _uninstallTokenPool() internal {
        kernel.executeAction(Actions.DeactivatePolicy, address(tokenPool));
    }

    modifier givenTokenPoolIsInstalled() {
        _createTokenPool();
        _installTokenPool();
        _;
    }

    modifier givenTokenPoolIsUninstalled() {
        _uninstallTokenPool();
        _;
    }

    modifier givenChainIsNotMainnet() {
        vm.chainId(2);
        _;
    }

    modifier givenIsEnabled() {
        vm.prank(ADMIN);
        tokenPool.enable("");
        _;
    }

    modifier givenIsDisabled() {
        vm.prank(ADMIN);
        tokenPool.disable("");
        _;
    }

    modifier givenPolicyIsDeactivated() {
        kernel.executeAction(Actions.DeactivatePolicy, address(tokenPool));
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

        tokenPool.applyChainUpdates(new uint64[](0), chainUpdates);
        _;
    }

    modifier givenTokenPoolHasOHM(uint256 amount_) {
        // Mint OHM to the sender
        vm.startPrank(mintrGodmode);
        MINTR.increaseMintApproval(mintrGodmode, amount_);
        MINTR.mintOhm(address(tokenPool), amount_);
        vm.stopPrank();
        _;
    }

    modifier givenBridgedOut(uint256 amount_) {
        vm.prank(ONRAMP);
        tokenPool.lockOrBurn(_getLockOrBurnParams(amount_));
        _;
    }

    function _increaseMinterApproval(uint256 amount) internal {
        vm.prank(mintrGodmode);
        MINTR.increaseMintApproval(address(tokenPool), amount);
    }

    function _assertBridgedSupply(uint256 expected) internal view {
        assertEq(tokenPool.getBridgedSupply(), expected, "bridgedSupply");
    }

    function _assertMinterApproval(uint256 expected) internal view {
        assertEq(MINTR.mintApproval(address(tokenPool)), expected, "mintApproval");
    }

    function _assertBridgedSupplyInitialized(bool expected) internal view {
        assertEq(tokenPool.isBridgeSupplyInitialized(), expected, "isBridgeSupplyInitialized");
    }

    function _assertIsChainMainnet(bool expected) internal view {
        assertEq(tokenPool.isChainMainnet(), expected, "isChainMainnet");
    }

    function _assertIsEnabled(bool expected) internal view {
        assertEq(tokenPool.isEnabled(), expected, "isEnabled");
    }

    function _assertIsPolicyActive(bool expected) internal view {
        assertEq(tokenPool.isActive(), expected, "isActive");
    }

    function _expectRevertNotEnabled() internal {
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));
    }

    function _expectRevertNotDisabled() internal {
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotDisabled.selector));
    }

    function _expectRevertNotAdmin() internal {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("admin"))
        );
    }

    function _assertTokenPoolOhmBalance(uint256 expected_) internal view {
        assertEq(OHM.balanceOf(address(tokenPool)), expected_, "token pool ohm balance");
    }

    function _assertReceiverOhmBalance(uint256 expected_) internal view {
        assertEq(OHM.balanceOf(RECEIVER), expected_, "receiver ohm balance");
    }

    // =========  TESTS ========= //

    // constructor
    // given the chain is mainnet
    //  [X] isChainMainnet is true
    //  [X] the owner is the deployer
    //  [X] the contract is disabled
    //  [X] bridgedSupply is 0
    //  [X] isBridgeSupplyInitialized is false
    // [X] isChainMainnet is false
    // [X] the owner is the deployer
    // [X] the contract is disabled
    // [X] bridgedSupply is 0
    // [X] isBridgeSupplyInitialized is false

    function test_constructor_mainnet() public {
        _createTokenPool();

        // Assert
        assertEq(tokenPool.owner(), address(this), "owner");
        _assertIsEnabled(false);
        _assertIsChainMainnet(true);
        _assertBridgedSupply(0);
        _assertBridgedSupplyInitialized(false);
    }

    function test_constructor_notMainnet() public {
        tokenPool = new CCIPMintBurnTokenPool(
            address(kernel),
            INITIAL_BRIDGED_SUPPLY,
            address(OHM),
            address(RMNProxy),
            address(router),
            2
        );

        // Assert
        assertEq(tokenPool.owner(), address(this), "owner");
        _assertIsEnabled(false);
        _assertIsChainMainnet(false);
        _assertBridgedSupply(0);
        _assertBridgedSupplyInitialized(false);
    }

    // enable
    // given the contract is enabled
    //  [X] it reverts
    // given the caller does not have the admin role
    //  [X] it reverts
    // given the chain is mainnet
    //  given the contract has been enabled before
    //   given the MINTR approval is different to the bridgedSupply value
    //    [X] it reverts
    //   [X] it enables the contract
    //  given the MINTR approval is non-zero
    //   [X] it reverts
    //  [X] bridgedSupply is set to INITIAL_BRIDGED_SUPPLY
    //  [X] bridgedSupplyInitialized is true
    //  [X] the MINTR approval is set to INITIAL_BRIDGED_SUPPLY
    //  [X] it enables the contract
    // [X] bridgedSupply remains 0
    // [X] bridgedSupplyInitialized is false
    // [X] the MINTR approval remains 0
    // [X] it enables the contract

    function test_enable_givenEnabled_reverts() public givenTokenPoolIsInstalled givenIsEnabled {
        // Expect revert
        _expectRevertNotDisabled();

        // Call function
        vm.prank(ADMIN);
        tokenPool.enable("");
    }

    function test_enable_callerNotAdmin_reverts(address caller_) public givenTokenPoolIsInstalled {
        vm.assume(caller_ != ADMIN);

        // Expect revert
        _expectRevertNotAdmin();

        // Call function
        vm.prank(caller_);
        tokenPool.enable("");
    }

    function test_enable_mainnet_previouslyEnabled_differentMinterApproval_reverts()
        public
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenIsDisabled
    {
        // Set the MINTR approval to a different value
        _increaseMinterApproval(100);

        // Expect revert
        // This is due to the bridgedSupply and MINTR approval being out of sync
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPMintBurnTokenPool.TokenPool_MintApprovalOutOfSync.selector,
                INITIAL_BRIDGED_SUPPLY,
                INITIAL_BRIDGED_SUPPLY + 100
            )
        );

        // Call function
        vm.prank(ADMIN);
        tokenPool.enable("");
    }

    function test_enable_mainnet_previouslyEnabled()
        public
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenTokenPoolHasOHM(AMOUNT)
        givenBridgedOut(AMOUNT)
        givenIsDisabled
    {
        // Call function
        vm.prank(ADMIN);
        tokenPool.enable("");

        // Assert
        _assertBridgedSupply(INITIAL_BRIDGED_SUPPLY + AMOUNT);
        _assertBridgedSupplyInitialized(true);
        _assertMinterApproval(INITIAL_BRIDGED_SUPPLY + AMOUNT);
        _assertIsEnabled(true);
    }

    function test_enable_mainnet_nonZeroMinterApproval_reverts() public givenTokenPoolIsInstalled {
        // Set the MINTR approval to a non-zero value
        _increaseMinterApproval(100);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPMintBurnTokenPool.TokenPool_MintApprovalOutOfSync.selector,
                0,
                100
            )
        );

        // Call function
        vm.prank(ADMIN);
        tokenPool.enable("");
    }

    function test_enable_mainnet() public givenTokenPoolIsInstalled {
        // Call function
        vm.prank(ADMIN);
        tokenPool.enable("");

        // Assert
        _assertBridgedSupply(INITIAL_BRIDGED_SUPPLY);
        _assertBridgedSupplyInitialized(true);
        _assertMinterApproval(INITIAL_BRIDGED_SUPPLY);
        _assertIsEnabled(true);
    }

    function test_enable_notMainnet() public givenChainIsNotMainnet givenTokenPoolIsInstalled {
        // Call function
        vm.prank(ADMIN);
        tokenPool.enable("");

        // Assert
        _assertBridgedSupply(0);
        _assertBridgedSupplyInitialized(false);
        _assertMinterApproval(0);
        _assertIsEnabled(true);
    }

    // disable
    // given the policy is disabled
    //  [X] it reverts
    // given the caller does not have the admin role
    //  [X] it reverts
    // [X] it disables the policy

    function test_disable_givenDisabled_reverts() public givenTokenPoolIsInstalled {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(ADMIN);
        tokenPool.disable("");
    }

    function test_disable_callerNotAdmin_reverts(
        address caller_
    ) public givenTokenPoolIsInstalled givenIsEnabled {
        vm.assume(caller_ != ADMIN);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyAdmin.NotAuthorised.selector));

        // Call function
        vm.prank(caller_);
        tokenPool.disable("");
    }

    function test_disable() public givenTokenPoolIsInstalled givenIsEnabled {
        // Call function
        vm.prank(ADMIN);
        tokenPool.disable("");

        // Assert
        _assertIsEnabled(false);
    }

    // configureDependencies
    // given the provided token is not the OHM registered in the MINTR module
    //  [X] it reverts
    // given the chain is mainnet
    //  given bridgedSupplyInitialized is true
    //   given the MINTR approval is different to the bridgedSupply value
    //    [X] it reverts
    //   [X] the bridgedSupply is unchanged
    //   [X] the MINTR approval is unchanged
    //   [X] it activates the policy
    //  given the MINTR approval is non-zero
    //   [X] it reverts
    //  [X] the bridgedSupply is unchanged
    //  [X] the MINTR approval is unchanged
    //  [X] it activates the policy
    // [X] the bridgedSupply is unchanged
    // [X] the MINTR approval is unchanged
    // [X] it activates the policy

    function test_configureDependencies_differentToken_reverts() public {
        // Create a new OHM token that will be different to OHM in MINTR
        address oldOHM = address(OHM);
        OHM = new MockOhm("Olympus", "OHM", 9);

        _createTokenPool();

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPMintBurnTokenPool.TokenPool_InvalidToken.selector,
                oldOHM,
                address(OHM)
            )
        );

        // Call function
        _installTokenPool();
    }

    function test_configureDependencies_notMainnet() public givenChainIsNotMainnet {
        // Call function
        _createTokenPool();
        _installTokenPool();

        // Assert
        _assertIsChainMainnet(false);
        _assertBridgedSupply(0);
        _assertBridgedSupplyInitialized(false);
        _assertMinterApproval(0);
        _assertIsEnabled(false);
        _assertIsPolicyActive(true);
    }

    function test_configureDependencies_mainnet_previouslyEnabled_differentMinterApproval_reverts()
        public
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenPolicyIsDeactivated
    {
        // Change the MINTR approval to a different value
        _increaseMinterApproval(100);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPMintBurnTokenPool.TokenPool_MintApprovalOutOfSync.selector,
                INITIAL_BRIDGED_SUPPLY,
                INITIAL_BRIDGED_SUPPLY + 100
            )
        );

        // Call function
        _installTokenPool();
    }

    function test_configureDependencies_mainnet_previouslyEnabled()
        public
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenTokenPoolHasOHM(AMOUNT)
        givenBridgedOut(AMOUNT)
        givenPolicyIsDeactivated
    {
        // Call function
        _installTokenPool();

        // Assert
        _assertBridgedSupply(INITIAL_BRIDGED_SUPPLY + AMOUNT);
        _assertBridgedSupplyInitialized(true);
        _assertMinterApproval(INITIAL_BRIDGED_SUPPLY + AMOUNT);
        _assertIsEnabled(true); // Previously enabled
        _assertIsPolicyActive(true);
    }

    function test_configureDependencies_mainnet_nonZeroMinterApproval_reverts() public {
        _createTokenPool();

        // Set the MINTR approval to a non-zero value
        _increaseMinterApproval(100);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPMintBurnTokenPool.TokenPool_MintApprovalOutOfSync.selector,
                0,
                100
            )
        );

        // Call function
        _installTokenPool();
    }

    function test_configureDependencies_mainnet() public {
        // Call function
        _createTokenPool();
        _installTokenPool();

        // Assert
        _assertBridgedSupply(0); // Not yet enabled
        _assertBridgedSupplyInitialized(false); // Not yet enabled
        _assertMinterApproval(0); // Not yet enabled
        _assertIsEnabled(false); // Not yet enabled
        _assertIsPolicyActive(true); // Policy is active
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
    // given the router has sent an insufficient balance of OHM tokens
    //  [X] it reverts
    // given the amount of tokens to be bridged is 0
    //  [X] it reverts
    // given the current chain is mainnet or sepolia
    //  [X] the bridgedSupply is incremented by the amount of tokens to be bridged
    //  [X] the MINTR approval is increased by the amount of tokens to be bridged
    //  [X] the OHM tokens are burned from the token pool
    //  [X] a Burned event is emitted
    //  [X] it returns the destination token address
    //  [X] it returns the pool data as encoded local decimals
    // [X] the bridgedSupply is not incremented
    // [X] the MINTR approval is not incremented
    // [X] the OHM tokens are burned from the token pool
    // [X] a Burned event is emitted
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

    function test_lockOrBurn_givenDisabled_reverts() public givenTokenPoolIsInstalled {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(ONRAMP);
        tokenPool.lockOrBurn(_getLockOrBurnParams(AMOUNT));
    }

    function test_lockOrBurn_givenDifferentToken_reverts()
        public
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
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
        givenTokenPoolIsInstalled
        givenIsEnabled
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(TokenPool.ChainNotAllowed.selector, REMOTE_CHAIN));

        // Call function
        vm.prank(ONRAMP);
        tokenPool.lockOrBurn(_getLockOrBurnParams(AMOUNT));
    }

    function test_lockOrBurn_remoteChainCursed_reverts()
        public
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
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
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(TokenPool.CallerIsNotARampOnRouter.selector, SENDER)
        );

        // Call function
        vm.prank(SENDER);
        tokenPool.lockOrBurn(_getLockOrBurnParams(AMOUNT));
    }

    function test_lockOrBurn_insufficientBalance_reverts()
        public
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenTokenPoolHasOHM(AMOUNT - 1)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPMintBurnTokenPool.TokenPool_InsufficientBalance.selector,
                AMOUNT,
                AMOUNT - 1
            )
        );

        // Call function
        vm.prank(ONRAMP);
        tokenPool.lockOrBurn(_getLockOrBurnParams(AMOUNT));
    }

    function test_lockOrBurn_zeroAmount_reverts()
        public
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenTokenPoolHasOHM(AMOUNT - 1)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPMintBurnTokenPool.TokenPool_ZeroAmount.selector)
        );

        // Call function
        vm.prank(ONRAMP);
        tokenPool.lockOrBurn(_getLockOrBurnParams(0));
    }

    function test_lockOrBurn_notMainnet()
        public
        givenChainIsNotMainnet
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenTokenPoolHasOHM(AMOUNT)
    {
        // Expect event
        vm.expectEmit();
        emit Burned(SENDER, AMOUNT);

        // Call function
        vm.prank(ONRAMP);
        Pool.LockOrBurnOutV1 memory result = tokenPool.lockOrBurn(_getLockOrBurnParams(AMOUNT));

        // Assert
        _assertBridgedSupply(0); // No change
        _assertMinterApproval(0); // No change
        _assertTokenPoolOhmBalance(0); // Burned
        _assertReceiverOhmBalance(0);
        assertEq(result.destTokenAddress, abi.encode(address(remoteOHM)), "destTokenAddress");
        assertEq(result.destPoolData, abi.encode(9), "destPoolData");
    }

    function test_lockOrBurn_mainnet()
        public
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
        givenTokenPoolHasOHM(AMOUNT)
    {
        // Expect event
        vm.expectEmit();
        emit Burned(SENDER, AMOUNT);

        // Call function
        vm.prank(ONRAMP);
        Pool.LockOrBurnOutV1 memory result = tokenPool.lockOrBurn(_getLockOrBurnParams(AMOUNT));

        // Assert
        _assertBridgedSupply(INITIAL_BRIDGED_SUPPLY + AMOUNT); // Incremented
        _assertMinterApproval(INITIAL_BRIDGED_SUPPLY + AMOUNT); // Incremented
        _assertTokenPoolOhmBalance(0); // Burned
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
    // given the amount of tokens to be bridged is 0
    //  [X] it reverts
    // given the current chain is mainnet or sepolia
    //   when the amount of tokens to be bridged is greater than the bridgedSupply
    //    [X] it reverts
    //  [X] the bridgedSupply is decremented by the amount of tokens bridged
    //  [X] the MINTR approval is decreased by the amount of tokens bridged
    //  [X] the OHM tokens are minted to the recipient
    //  [X] a Minted event is emitted
    //  [X] it returns the amount of tokens minted
    // [X] the bridgedSupply is not decremented
    // [X] the MINTR approval is not decremented
    // [X] the OHM tokens are minted to the recipient
    // [X] a Minted event is emitted
    // [X] it returns the amount of tokens minted

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

    function test_releaseOrMint_givenDisabled_reverts() public givenTokenPoolIsInstalled {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(OFFRAMP);
        tokenPool.releaseOrMint(_getReleaseOrMintParams(AMOUNT));
    }

    function test_releaseOrMint_givenDifferentToken_reverts()
        public
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
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
        givenTokenPoolIsInstalled
        givenIsEnabled
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(TokenPool.ChainNotAllowed.selector, REMOTE_CHAIN));

        // Call function
        vm.prank(OFFRAMP);
        tokenPool.releaseOrMint(_getReleaseOrMintParams(AMOUNT));
    }

    function test_releaseOrMint_sourceChainCursed_reverts()
        public
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
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
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(TokenPool.CallerIsNotARampOnRouter.selector, SENDER)
        );

        // Call function
        vm.prank(SENDER);
        tokenPool.releaseOrMint(_getReleaseOrMintParams(AMOUNT));
    }

    function test_releaseOrMint_zeroAmount_reverts()
        public
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPMintBurnTokenPool.TokenPool_ZeroAmount.selector)
        );

        // Call function
        vm.prank(OFFRAMP);
        tokenPool.releaseOrMint(_getReleaseOrMintParams(0));
    }

    function test_releaseOrMint_notMainnet()
        public
        givenChainIsNotMainnet
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
    {
        // Expect event
        vm.expectEmit();
        emit Minted(SENDER, RECEIVER, AMOUNT);

        // Call function
        vm.prank(OFFRAMP);
        Pool.ReleaseOrMintOutV1 memory result = tokenPool.releaseOrMint(
            _getReleaseOrMintParams(AMOUNT)
        );

        // Assert
        _assertBridgedSupply(0); // No change
        _assertMinterApproval(0); // Incremented, then minting brings back to 0
        _assertTokenPoolOhmBalance(0);
        _assertReceiverOhmBalance(AMOUNT);
        assertEq(result.destinationAmount, AMOUNT, "destinationAmount");
    }

    function test_releaseOrMint_notMainnet_originalSenderNotEVM()
        public
        givenChainIsNotMainnet
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
    {
        // Expect event
        vm.expectEmit();
        emit Minted(0x0000000000000000000000000000000000000000, RECEIVER, AMOUNT);

        // Call function
        vm.prank(OFFRAMP);
        Pool.ReleaseOrMintOutV1 memory result = tokenPool.releaseOrMint(
            Pool.ReleaseOrMintInV1({
                originalSender: abi.encode(bytes32("11111111111111111111111111111111")), // Mimic an SVM address
                remoteChainSelector: REMOTE_CHAIN,
                receiver: RECEIVER,
                amount: AMOUNT,
                localToken: address(OHM),
                sourcePoolAddress: abi.encode(REMOTE_POOL),
                sourcePoolData: abi.encode(9),
                offchainTokenData: ""
            })
        );

        // Assert
        _assertBridgedSupply(0); // No change
        _assertMinterApproval(0); // Incremented, then minting brings back to 0
        _assertTokenPoolOhmBalance(0);
        _assertReceiverOhmBalance(AMOUNT);
        assertEq(result.destinationAmount, AMOUNT, "destinationAmount");
    }

    function test_releaseOrMint_mainnet()
        public
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
    {
        // Expect event
        vm.expectEmit();
        emit Minted(SENDER, RECEIVER, AMOUNT);

        // Call function
        vm.prank(OFFRAMP);
        Pool.ReleaseOrMintOutV1 memory result = tokenPool.releaseOrMint(
            _getReleaseOrMintParams(AMOUNT)
        );

        // Assert
        _assertBridgedSupply(INITIAL_BRIDGED_SUPPLY - AMOUNT); // Amount deducted
        _assertMinterApproval(INITIAL_BRIDGED_SUPPLY - AMOUNT); // Amount deducted
        _assertTokenPoolOhmBalance(0);
        _assertReceiverOhmBalance(AMOUNT);
        assertEq(result.destinationAmount, AMOUNT, "destinationAmount");
    }

    function test_releaseOrMint_greaterThanBridgedSupply_reverts()
        public
        givenTokenPoolIsInstalled
        givenIsEnabled
        givenRemoteChainIsSupported(REMOTE_CHAIN, REMOTE_POOL, address(remoteOHM))
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPMintBurnTokenPool.TokenPool_BridgedSupplyExceeded.selector,
                INITIAL_BRIDGED_SUPPLY,
                INITIAL_BRIDGED_SUPPLY + 1
            )
        );

        // Call function
        vm.prank(OFFRAMP);
        tokenPool.releaseOrMint(_getReleaseOrMintParams(INITIAL_BRIDGED_SUPPLY + 1));
    }
}
