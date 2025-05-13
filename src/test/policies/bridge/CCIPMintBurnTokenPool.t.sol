// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";

import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {CCIPMintBurnTokenPool} from "src/policies/bridge/CCIPMintBurnTokenPool.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockCCIPRouter} from "src/test/policies/bridge/mocks/MockCCIPRouter.sol";
import {MockRMNProxy} from "src/test/policies/bridge/mocks/MockRMNProxy.sol";

// solhint-disable max-states-count
contract CCIPMintBurnTokenPoolTest is Test {
    using ModuleTestFixtureGenerator for OlympusMinter;

    MockCCIPRouter public router;

    MockRMNProxy public RMNProxy;

    MockOhm public OHM;
    OlympusMinter public MINTR;
    OlympusRoles public ROLES;
    Kernel public kernel;
    RolesAdmin public rolesAdmin;
    CCIPMintBurnTokenPool public tokenPool;

    uint256 public constant INITIAL_BRIDGED_SUPPLY = 123_456;

    address public SENDER;
    address public RECEIVER;
    address public ADMIN;

    address public mintrGodmode;

    function setUp() public {
        // Addresses
        SENDER = makeAddr("SENDER");
        RECEIVER = makeAddr("RECEIVER");
        ADMIN = makeAddr("ADMIN");

        // Ensure the chain id is set to mainnet
        vm.chainId(1);

        OHM = new MockOhm("Olympus", "OHM", 9);

        router = new MockCCIPRouter();
        RMNProxy = new MockRMNProxy();

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

    function _installTokenPool() internal {
        tokenPool = new CCIPMintBurnTokenPool(
            address(kernel),
            INITIAL_BRIDGED_SUPPLY,
            address(OHM),
            address(RMNProxy),
            address(router),
            1
        );

        kernel.executeAction(Actions.ActivatePolicy, address(tokenPool));
    }

    function _uninstallTokenPool() internal {
        kernel.executeAction(Actions.DeactivatePolicy, address(tokenPool));
    }

    modifier givenTokenPoolIsInstalled() {
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

    modifier givenPolicyIsEnabled() {
        vm.prank(ADMIN);
        tokenPool.enable("");
        _;
    }

    modifier givenPolicyIsDisabled() {
        vm.prank(ADMIN);
        tokenPool.disable("");
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

    // =========  TESTS ========= //

    // TODO rate limiting

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
        CCIPMintBurnTokenPool newTokenPool = new CCIPMintBurnTokenPool(
            address(kernel),
            INITIAL_BRIDGED_SUPPLY,
            address(OHM),
            address(RMNProxy),
            address(router),
            1
        );

        assertEq(newTokenPool.owner(), address(this), "owner");
        assertEq(newTokenPool.isEnabled(), false, "isEnabled");

        assertEq(newTokenPool.isChainMainnet(), true, "isChainMainnet");
        assertEq(newTokenPool.getBridgedSupply(), 0, "bridgedSupply");
        assertEq(newTokenPool.isBridgeSupplyInitialized(), false, "isBridgeSupplyInitialized");
    }

    function test_constructor_notMainnet() public {
        CCIPMintBurnTokenPool newTokenPool = new CCIPMintBurnTokenPool(
            address(kernel),
            INITIAL_BRIDGED_SUPPLY,
            address(OHM),
            address(RMNProxy),
            address(router),
            2
        );

        assertEq(newTokenPool.owner(), address(this), "owner");
        assertEq(newTokenPool.isEnabled(), false, "isEnabled");

        assertEq(newTokenPool.isChainMainnet(), false, "isChainMainnet");
        assertEq(newTokenPool.getBridgedSupply(), 0, "bridgedSupply");
        assertEq(newTokenPool.isBridgeSupplyInitialized(), false, "isBridgeSupplyInitialized");
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

    function test_enable_givenEnabled_reverts()
        public
        givenTokenPoolIsInstalled
        givenPolicyIsEnabled
    {
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
        givenPolicyIsEnabled
        givenPolicyIsDisabled
    {
        // Set the MINTR approval to a different value
        _increaseMinterApproval(100);

        // Expect revert
        // This is due to the bridgedSupply and MINTR approval being out of sync
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPMintBurnTokenPool.TokenPool_MintApprovalOutOfSync.selector,
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
        givenPolicyIsEnabled
        givenPolicyIsDisabled
    {
        // TODO mimic a bridge so that the bridgedSupply is different to the initial value

        // Call function
        vm.prank(ADMIN);
        tokenPool.enable("");

        // Assert
        _assertBridgedSupply(INITIAL_BRIDGED_SUPPLY);
        _assertBridgedSupplyInitialized(true);
        _assertMinterApproval(INITIAL_BRIDGED_SUPPLY);
        assertEq(tokenPool.isEnabled(), true, "isEnabled");
    }

    function test_enable_mainnet_nonZeroMinterApproval_reverts() public givenTokenPoolIsInstalled {
        // Set the MINTR approval to a non-zero value
        _increaseMinterApproval(100);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPMintBurnTokenPool.TokenPool_MintApprovalOutOfSync.selector,
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
        assertEq(tokenPool.isEnabled(), true, "isEnabled");
    }

    function test_enable_notMainnet() public givenChainIsNotMainnet givenTokenPoolIsInstalled {
        // Call function
        vm.prank(ADMIN);
        tokenPool.enable("");

        // Assert
        _assertBridgedSupply(0);
        _assertBridgedSupplyInitialized(false);
        _assertMinterApproval(0);
        assertEq(tokenPool.isEnabled(), true, "isEnabled");
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
    ) public givenTokenPoolIsInstalled givenPolicyIsEnabled {
        vm.assume(caller_ != ADMIN);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyAdmin.NotAuthorised.selector));

        // Call function
        vm.prank(caller_);
        tokenPool.disable("");
    }

    function test_disable() public givenTokenPoolIsInstalled givenPolicyIsEnabled {
        // Call function
        vm.prank(ADMIN);
        tokenPool.disable("");

        // Assert
        assertEq(tokenPool.isEnabled(), false, "isEnabled");
    }

    // configureDependencies
    // given the provided token is not the OHM registered in the MINTR module
    //  [ ] it reverts
    // given the provided token does not have 9 decimals
    //  [ ] it reverts
    // given the chain is mainnet
    //  given bridgedSupplyInitialized is true
    //   given the MINTR approval is different to the bridgedSupply value
    //    [ ] it reverts
    //   [ ] the bridgedSupply is unchanged
    //   [ ] the MINTR approval is unchanged
    //   [ ] it activates the policy
    //  given the MINTR approval is non-zero
    //   [ ] it reverts
    //  [ ] the bridgedSupply is unchanged
    //  [ ] the MINTR approval is unchanged
    //  [ ] it activates the policy
    // [ ] the bridgedSupply is unchanged
    // [ ] the MINTR approval is unchanged
    // [ ] it activates the policy

    // lockOrBurn
    // given the policy is disabled
    //  [ ] it reverts
    // given the provided token is not the configured token of the token pool
    //  [ ] it reverts
    // given the destination chain is cursed by the RMN
    //  [ ] it reverts
    // given the caller is not the configured OffRamp for the destination chain
    //  [ ] it reverts
    // given the sender has not approved the router to spend the OHM tokens
    //  [ ] it reverts
    // given the sender has an insufficient balance of OHM tokens
    //  [ ] it reverts
    // given the amount of tokens to be bridged is 0
    //  [ ] it reverts
    // given the current chain is mainnet or sepolia
    //  [ ] the bridgedSupply is incremented by the amount of tokens to be bridged
    //  [ ] the MINTR approval is increased by the amount of tokens to be bridged
    //  [ ] the OHM tokens are burned from the token pool
    //  [ ] a Burned event is emitted
    //  [ ] it returns the destination token address
    //  [ ] it returns the pool data as encoded local decimals
    // [ ] the bridgedSupply is not incremented
    // [ ] the MINTR approval is not incremented
    // [ ] the OHM tokens are burned from the token pool
    // [ ] a Burned event is emitted
    // [ ] it returns the destination token address
    // [ ] it returns the pool data as encoded local decimals

    // releaseOrMint
    // given the policy is disabled
    //  [ ] it reverts
    // given the provided token is not the configured token of the token pool
    //  [ ] it reverts
    // given the destination chain is cursed by the RMN
    //  [ ] it reverts
    // given the caller is not the configured OnRamp for the source chain
    //  [ ] it reverts
    // given the sender has not approved the router to spend the OHM tokens
    //  [ ] it reverts
    // given the sender has an insufficient balance of OHM tokens
    //  [ ] it reverts
    // given the amount of tokens to be bridged is 0
    //  [ ] it reverts
    // given the current chain is mainnet or sepolia
    //  [ ] the bridgedSupply is decremented by the amount of tokens bridged
    //  [ ] the MINTR approval is decreased by the amount of tokens bridged
    //  [ ] the OHM tokens are minted to the recipient
    //  [ ] a Minted event is emitted
    //  [ ] it returns the amount of tokens minted
    // [ ] the bridgedSupply is not decremented
    // [ ] the MINTR approval is not decremented
    // [ ] the OHM tokens are minted to the recipient
    // [ ] a Minted event is emitted
    // [ ] it returns the amount of tokens minted
}
