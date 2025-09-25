// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";
import {MockContractRegistryPolicy, MockImmutableContractRegistryPolicy} from "src/test/mocks/MockContractRegistryPolicy.sol";

import {Kernel, Actions, Module, fromKeycode} from "src/Kernel.sol";
import {RGSTYv1} from "src/modules/RGSTY/RGSTY.v1.sol";
import {OlympusContractRegistry} from "src/modules/RGSTY/OlympusContractRegistry.sol";

contract ContractRegistryTest is Test {
    using ModuleTestFixtureGenerator for OlympusContractRegistry;

    address public godmode;
    address public notOwner = address(0x1);

    address public addressOne = address(0x2);
    address public addressTwo = address(0x3);

    Kernel internal _kernel;
    OlympusContractRegistry internal RGSTY;
    MockContractRegistryPolicy internal _policy;
    MockImmutableContractRegistryPolicy internal _policyImmutable;

    // Contract Registry Expected events
    event ContractRegistered(
        bytes5 indexed name,
        address indexed contractAddress,
        bool isImmutable
    );
    event ContractUpdated(bytes5 indexed name, address indexed contractAddress);
    event ContractDeregistered(bytes5 indexed name);

    function setUp() public {
        // Deploy Kernel and modules
        // This contract is the owner
        _kernel = new Kernel();
        RGSTY = new OlympusContractRegistry(address(_kernel));
        _policy = new MockContractRegistryPolicy(_kernel);
        _policyImmutable = new MockImmutableContractRegistryPolicy(_kernel);

        // Generate fixtures
        godmode = RGSTY.generateGodmodeFixture(type(OlympusContractRegistry).name);

        // Install modules and policies on Kernel
        _kernel.executeAction(Actions.InstallModule, address(RGSTY));
        _kernel.executeAction(Actions.ActivatePolicy, godmode);
    }

    function _registerImmutableContract(bytes5 name_, address contractAddress_) internal {
        vm.prank(godmode);
        RGSTY.registerImmutableContract(name_, contractAddress_);
    }

    function _registerContract(bytes5 name_, address contractAddress_) internal {
        vm.prank(godmode);
        RGSTY.registerContract(name_, contractAddress_);
    }

    function _deregisterContract(bytes5 name_) internal {
        vm.prank(godmode);
        RGSTY.deregisterContract(name_);
    }

    function _updateContract(bytes5 name_, address contractAddress_) internal {
        vm.prank(godmode);
        RGSTY.updateContract(name_, contractAddress_);
    }

    function _activatePolicyOne() internal {
        _kernel.executeAction(Actions.ActivatePolicy, address(_policy));
    }

    function _activatePolicyImmutable() internal {
        _kernel.executeAction(Actions.ActivatePolicy, address(_policyImmutable));
    }

    modifier givenImmutableContractIsRegistered(bytes5 name_, address contractAddress_) {
        _registerImmutableContract(name_, contractAddress_);
        _;
    }

    modifier givenContractIsRegistered(bytes5 name_, address contractAddress_) {
        _registerContract(name_, contractAddress_);
        _;
    }

    modifier givenContractIsDeregistered(bytes5 name_) {
        _deregisterContract(name_);
        _;
    }

    modifier givenContractIsUpdated(bytes5 name_, address contractAddress_) {
        _updateContract(name_, contractAddress_);
        _;
    }

    modifier givenPolicyOneIsActive() {
        _activatePolicyOne();
        _;
    }

    modifier givenPolicyImmutableIsActive() {
        _activatePolicyImmutable();
        _;
    }

    // =========  TESTS ========= //

    // constructor
    // when the kernel address is zero
    //  [X] it reverts
    // when the kernel address is not zero
    //  [X] it sets the kernel address

    function test_constructor_whenKernelAddressIsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidAddress.selector));

        new OlympusContractRegistry(address(0));
    }

    function test_constructor_whenKernelAddressIsNotZero_reverts() public {
        OlympusContractRegistry rgsty = new OlympusContractRegistry(address(1));

        assertEq(address(rgsty.kernel()), address(1), "Kernel address is not set correctly");
    }

    // registerImmutableContract
    // when the caller is not permissioned
    //  [X] it reverts
    // when the name is empty
    //  [X] it reverts
    // when the start of the name contains null characters
    //  [X] it reverts
    // when the end of the name contains null characters
    //  [X] it succeeds
    // when the contract address is zero
    //  [X] it reverts
    // when the name is not lowercase
    //  [X] it reverts
    // when the name contains punctuation
    //  [X] it reverts
    // when the name contains a numeral
    //  [X] it succeeds
    // given the name is registered
    //  [X] it reverts
    // given the name is registered as mutable address
    //  [X] it reverts
    // given the name is not registered
    //  given there are existing registrations
    //   [X] it updates the contract address, emits an event and updates the names array
    //  [X] it registers the contract address, emits an event and updates the names array
    // given dependent policies are registered
    //  [X] it refreshes the dependents

    function test_registerImmutableContract_callerNotPermissioned_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, notOwner)
        );

        vm.prank(notOwner);
        RGSTY.registerImmutableContract(bytes5("ohm"), addressOne);
    }

    function test_registerImmutableContract_whenNameIsEmpty_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));

        _registerImmutableContract(bytes5(""), addressOne);
    }

    function test_registerImmutableContract_whenNameStartsWithNullCharacters_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));

        _registerImmutableContract(bytes5("\x00\x00ohm"), addressOne);
    }

    function test_registerImmutableContract_whenNameContainsNullCharacters_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));

        _registerImmutableContract(bytes5("o\x00\x00hm"), addressOne);
    }

    function test_registerImmutableContract_whenNameEndsWithNullCharacters_succeeds() public {
        _registerImmutableContract(bytes5("ohm\x00"), addressOne);

        assertEq(RGSTY.getImmutableContract(bytes5("ohm")), addressOne);
    }

    function test_registerImmutableContract_whenNameIsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));

        _registerImmutableContract(bytes5(0), addressOne);
    }

    function test_registerImmutableContract_whenNameIsNotLowercase_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));
        _registerImmutableContract(bytes5("Ohm"), addressOne);

        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));
        _registerImmutableContract(bytes5("oHm"), addressOne);

        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));
        _registerImmutableContract(bytes5("ohM"), addressOne);
    }

    function test_registerImmutableContract_whenNameContainsPunctuation_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));
        _registerImmutableContract(bytes5("ohm!"), addressOne);

        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));
        _registerImmutableContract(bytes5("ohm "), addressOne);

        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));
        _registerImmutableContract(bytes5("ohm-"), addressOne);
    }

    function test_registerImmutableContract_whenNameContainsNumeral() public {
        _registerImmutableContract(bytes5("ohm1"), addressOne);

        assertEq(RGSTY.getImmutableContract(bytes5("ohm1")), addressOne);
    }

    function test_registerImmutableContract_whenContractAddressIsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidAddress.selector));

        _registerImmutableContract(bytes5("ohm"), address(0));
    }

    function test_registerImmutableContract_whenNameIsRegistered_reverts()
        public
        givenContractIsRegistered(bytes5("ohm"), addressOne)
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_ContractAlreadyRegistered.selector));

        // Register the second time
        _registerImmutableContract(bytes5("ohm"), addressTwo);
    }

    function test_registerImmutableContract_whenImmutableNameIsRegistered_reverts()
        public
        givenImmutableContractIsRegistered(bytes5("ohm"), addressOne)
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_ContractAlreadyRegistered.selector));

        // Register the second time
        _registerImmutableContract(bytes5("ohm"), addressTwo);
    }

    function test_registerImmutableContract_whenNameIsNotRegistered() public {
        // Expect an event to be emitted for updated registration
        vm.expectEmit();
        emit ContractRegistered(bytes5("ohm"), addressOne, true);

        // Register the first time
        _registerImmutableContract(bytes5("ohm"), addressOne);

        assertEq(
            RGSTY.getImmutableContract(bytes5("ohm")),
            addressOne,
            "Contract address is not set correctly"
        );
        assertEq(
            RGSTY.getImmutableContractNames().length,
            1,
            "Immutable names array is not updated correctly"
        );
        assertEq(
            RGSTY.getImmutableContractNames()[0],
            bytes5("ohm"),
            "Immutable names array is not updated correctly"
        );
        assertEq(RGSTY.getContractNames().length, 0, "Names array is not updated correctly");
    }

    function test_registerImmutableContract_whenOtherNamesAreRegistered()
        public
        givenImmutableContractIsRegistered(bytes5("ohm"), addressOne)
        givenImmutableContractIsRegistered(bytes5("ohm2"), addressTwo)
        givenImmutableContractIsRegistered(bytes5("ohm3"), address(0x4))
    {
        // Assert values
        assertEq(
            RGSTY.getImmutableContract(bytes5("ohm")),
            addressOne,
            "ohm contract address is not set correctly"
        );
        assertEq(
            RGSTY.getImmutableContract(bytes5("ohm2")),
            addressTwo,
            "ohm2 contract address is not set correctly"
        );
        assertEq(
            RGSTY.getImmutableContract(bytes5("ohm3")),
            address(0x4),
            "ohm3 contract address is not set correctly"
        );
        assertEq(
            RGSTY.getImmutableContractNames().length,
            3,
            "Immutable names array is not updated correctly"
        );
        assertEq(
            RGSTY.getImmutableContractNames()[0],
            bytes5("ohm"),
            "Immutable names array is not updated correctly"
        );
        assertEq(
            RGSTY.getImmutableContractNames()[1],
            bytes5("ohm2"),
            "Immutable names array is not updated correctly"
        );
        assertEq(
            RGSTY.getImmutableContractNames()[2],
            bytes5("ohm3"),
            "Immutable names array is not updated correctly"
        );
        assertEq(RGSTY.getContractNames().length, 0, "Names array is not updated correctly");
    }

    function test_registerImmutableContract_activatePolicy_whenContractIsRegistered() public {
        // Register the contract
        _registerImmutableContract(bytes5("dai"), addressOne);

        assertEq(_policyImmutable.dai(), address(0));

        // Activate the dependent policy
        _activatePolicyImmutable();

        assertEq(_policyImmutable.dai(), addressOne);
    }

    function test_registerImmutableContract_activatePolicies_whenContractNotRegistered_reverts()
        public
    {
        // Expect the policy to revert
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_ContractNotRegistered.selector));

        // Activate the dependent policies
        _activatePolicyImmutable();
    }

    // registerContract
    // when the caller is not permissioned
    //  [X] it reverts
    // when the name is empty
    //  [X] it reverts
    // when the start of the name contains null characters
    //  [X] it reverts
    // when the end of the name contains null characters
    //  [X] it succeeds
    // when the contract address is zero
    //  [X] it reverts
    // when the name is not lowercase
    //  [X] it reverts
    // when the name contains punctuation
    //  [X] it reverts
    // when the name contains a numeral
    //  [X] it succeeds
    // given the name is registered
    //  [X] it reverts
    // given the name is registered as an immutable address
    //  [X] it reverts
    // given the name is not registered
    //  given there are existing registrations
    //   [X] it updates the contract address, emits an event and updates the names array
    //  [X] it registers the contract address, emits an event and updates the names array
    // given dependent policies are registered
    //  [X] it refreshes the dependents

    function test_registerContract_callerNotPermissioned_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, notOwner)
        );

        vm.prank(notOwner);
        RGSTY.registerContract(bytes5("ohm"), addressOne);
    }

    function test_registerContract_whenNameIsEmpty_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));

        _registerContract(bytes5(""), addressOne);
    }

    function test_registerContract_whenNameStartsWithNullCharacters_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));

        _registerContract(bytes5("\x00\x00ohm"), addressOne);
    }

    function test_registerContract_whenNameContainsNullCharacters_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));

        _registerContract(bytes5("o\x00\x00hm"), addressOne);
    }

    function test_registerContract_whenNameEndsWithNullCharacters_succeeds() public {
        _registerContract(bytes5("ohm\x00"), addressOne);

        assertEq(RGSTY.getContract(bytes5("ohm")), addressOne);
    }

    function test_registerContract_whenNameIsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));

        _registerContract(bytes5(0), addressOne);
    }

    function test_registerContract_whenNameIsNotLowercase_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));
        _registerContract(bytes5("Ohm"), addressOne);

        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));
        _registerContract(bytes5("oHm"), addressOne);

        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));
        _registerContract(bytes5("ohM"), addressOne);
    }

    function test_registerContract_whenNameContainsPunctuation_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));
        _registerContract(bytes5("ohm!"), addressOne);

        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));
        _registerContract(bytes5("ohm "), addressOne);

        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidName.selector));
        _registerContract(bytes5("ohm-"), addressOne);
    }

    function test_registerContract_whenNameContainsNumeral() public {
        _registerContract(bytes5("ohm1"), addressOne);

        assertEq(RGSTY.getContract(bytes5("ohm1")), addressOne);
    }

    function test_registerContract_whenContractAddressIsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidAddress.selector));

        _registerContract(bytes5("ohm"), address(0));
    }

    function test_registerContract_whenImmutableNameIsRegistered_reverts()
        public
        givenImmutableContractIsRegistered(bytes5("ohm"), addressOne)
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_ContractAlreadyRegistered.selector));

        // Register the second time
        _registerContract(bytes5("ohm"), addressTwo);
    }

    function test_registerContract_whenNameIsRegistered_reverts()
        public
        givenContractIsRegistered(bytes5("ohm"), addressOne)
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_ContractAlreadyRegistered.selector));

        // Register the second time
        _registerContract(bytes5("ohm"), addressTwo);
    }

    function test_registerContract_whenNameIsNotRegistered() public {
        // Expect an event to be emitted for updated registration
        vm.expectEmit();
        emit ContractRegistered(bytes5("ohm"), addressOne, false);

        // Register the first time
        _registerContract(bytes5("ohm"), addressOne);

        assertEq(
            RGSTY.getContract(bytes5("ohm")),
            addressOne,
            "Contract address is not set correctly"
        );
        assertEq(RGSTY.getContractNames().length, 1, "Names array is not updated correctly");
        assertEq(
            RGSTY.getContractNames()[0],
            bytes5("ohm"),
            "Names array is not updated correctly"
        );
        assertEq(
            RGSTY.getImmutableContractNames().length,
            0,
            "Immutable names array is not updated correctly"
        );
    }

    function test_registerContract_whenOtherNamesAreRegistered()
        public
        givenContractIsRegistered(bytes5("ohm"), addressOne)
        givenContractIsRegistered(bytes5("ohm2"), addressTwo)
        givenContractIsRegistered(bytes5("ohm3"), address(0x4))
    {
        // Assert values
        assertEq(
            RGSTY.getContract(bytes5("ohm")),
            addressOne,
            "ohm contract address is not set correctly"
        );
        assertEq(
            RGSTY.getContract(bytes5("ohm2")),
            addressTwo,
            "ohm2 contract address is not set correctly"
        );
        assertEq(
            RGSTY.getContract(bytes5("ohm3")),
            address(0x4),
            "ohm3 contract address is not set correctly"
        );
        assertEq(RGSTY.getContractNames().length, 3, "Names array is not updated correctly");
        assertEq(
            RGSTY.getContractNames()[0],
            bytes5("ohm"),
            "Names array is not updated correctly"
        );
        assertEq(
            RGSTY.getContractNames()[1],
            bytes5("ohm2"),
            "Names array is not updated correctly"
        );
        assertEq(
            RGSTY.getContractNames()[2],
            bytes5("ohm3"),
            "Names array is not updated correctly"
        );
        assertEq(
            RGSTY.getImmutableContractNames().length,
            0,
            "Immutable names array is not updated correctly"
        );
    }

    function test_registerContract_activatePolicies_whenContractIsRegistered() public {
        // Register the contract
        _registerContract(bytes5("dai"), addressOne);

        assertEq(_policy.dai(), address(0));

        // Activate the dependent policies
        _activatePolicyOne();

        assertEq(_policy.dai(), addressOne);
    }

    function test_registerContract_activatePolicies_whenContractNotRegistered_reverts() public {
        // Expect the policy to revert
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_ContractNotRegistered.selector));

        // Activate the dependent policies
        _activatePolicyOne();
    }

    // updateContract
    // when the caller is not permissioned
    //  [X] it reverts
    // when the name is not registered
    //  [X] it reverts
    // when the address is zero
    //  [X] it reverts
    // when the name is registered as an immutable address
    //  [X] it reverts
    // given dependent policies are registered
    //  [X] it refreshes the dependents
    // [X] it updates the contract address

    function test_updateContract_callerNotPermissioned_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, notOwner)
        );

        vm.prank(notOwner);
        RGSTY.updateContract(bytes5("ohm"), addressOne);
    }

    function test_updateContract_whenNameIsNotRegistered_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_ContractNotRegistered.selector));

        _updateContract(bytes5("ohm"), addressOne);
    }

    function test_updateContract_whenContractAddressIsZero_reverts()
        public
        givenContractIsRegistered(bytes5("ohm"), addressOne)
    {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_InvalidAddress.selector));

        _updateContract(bytes5("ohm"), address(0));
    }

    function test_updateContract_whenImmutableNameIsRegistered_reverts()
        public
        givenImmutableContractIsRegistered(bytes5("ohm"), addressOne)
    {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_ContractNotRegistered.selector));

        _updateContract(bytes5("ohm"), addressOne);
    }

    function test_updateContract() public givenContractIsRegistered(bytes5("ohm"), addressOne) {
        // Expect an event to be emitted
        vm.expectEmit();
        emit ContractUpdated(bytes5("ohm"), addressTwo);

        // Update the contract
        _updateContract(bytes5("ohm"), addressTwo);

        // Assert values
        assertEq(
            RGSTY.getContract(bytes5("ohm")),
            addressTwo,
            "Contract address is not updated correctly"
        );
    }

    function test_updateContract_whenDependentPolicyIsRegistered()
        public
        givenContractIsRegistered(bytes5("dai"), addressOne)
        givenPolicyOneIsActive
    {
        // Update the contract
        _updateContract(bytes5("dai"), addressTwo);

        // Assert values in the policies have been updated
        assertEq(_policy.dai(), addressTwo);
    }

    // deregisterContract
    // when the caller is not permissioned
    //  [X] it reverts
    // given the name is not registered
    //  [X] it reverts
    // given the name is registered as an immutable address
    //  [X] it reverts
    // given the name is registered
    //  given multiple names are registered
    //   [X] it deregisters the name, emits an event and updates the names array
    //  [X] it deregisters the name, emits an event and updates the names array
    // given dependent policies are registered
    //  given one of the required contracts is deregistered
    //   [X] it reverts
    //  [X] it refreshes the dependents

    function test_deregisterContract_whenCallerIsNotPermissioned_reverts() public {
        // Register the first time
        _registerContract(bytes5("ohm"), addressOne);

        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, notOwner)
        );

        vm.prank(notOwner);
        RGSTY.deregisterContract(bytes5("ohm"));
    }

    function test_deregisterContract_whenNameIsNotRegistered_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_ContractNotRegistered.selector));

        _deregisterContract(bytes5(""));
    }

    function test_deregisterContract_whenImmutableNameIsRegistered_reverts()
        public
        givenImmutableContractIsRegistered(bytes5("ohm"), addressOne)
    {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_ContractNotRegistered.selector));

        _deregisterContract(bytes5(""));
    }

    function test_deregisterContract_whenNameIsRegistered() public {
        // Register the first time
        _registerContract(bytes5("ohm"), addressOne);

        // Deregister the first time
        _deregisterContract(bytes5("ohm"));

        // Assert values
        // Deregistered contract should revert
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_ContractNotRegistered.selector));
        RGSTY.getContract(bytes5("ohm"));

        // Names array should be empty
        assertEq(RGSTY.getContractNames().length, 0, "Names array is not updated correctly");
    }

    function test_deregisterContract_whenMultipleNamesAreRegistered(uint256 index_) public {
        uint256 randomIndex = bound(index_, 0, 2);

        bytes5[] memory names = new bytes5[](3);
        names[0] = bytes5("ohm");
        names[1] = bytes5("ohm2");
        names[2] = bytes5("ohm3");

        // Register the first time
        _registerContract(names[0], addressOne);

        // Register the second time
        _registerContract(names[1], addressTwo);

        // Register the third time
        _registerContract(names[2], address(0x4));

        // Deregister a random name
        _deregisterContract(names[randomIndex]);

        // Assert values
        // Deregistered contract should revert
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_ContractNotRegistered.selector));
        RGSTY.getContract(names[randomIndex]);

        // Other contracts should still be registered
        if (randomIndex != 0) {
            assertEq(
                RGSTY.getContract(names[0]),
                addressOne,
                "ohm contract address is not set correctly"
            );
        }
        if (randomIndex != 1) {
            assertEq(
                RGSTY.getContract(names[1]),
                addressTwo,
                "ohm2 contract address is not set correctly"
            );
        }
        if (randomIndex != 2) {
            assertEq(
                RGSTY.getContract(names[2]),
                address(0x4),
                "ohm3 contract address is not set correctly"
            );
        }

        // Names array should be updated
        bytes5[] memory expectedNames = new bytes5[](2);
        uint256 expectedIndex = 0;
        for (uint256 i = 0; i < 3; i++) {
            if (i != randomIndex) {
                expectedNames[expectedIndex] = names[i];
                expectedIndex++;
            }
        }

        bytes5[] memory contractNames = RGSTY.getContractNames();
        assertEq(RGSTY.getContractNames().length, 2, "Names array is not updated correctly");

        // Check that the expected names are in the array
        // This is done as the order of names in the array is not guaranteed
        for (uint256 i = 0; i < expectedNames.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < contractNames.length; j++) {
                if (expectedNames[i] == contractNames[j]) {
                    found = true;
                    break;
                }
            }
            assertEq(found, true, "Names array is not updated correctly");
        }
    }

    function test_deregisterContract_whenDependentPolicyIsRegistered_reverts()
        public
        givenContractIsRegistered(bytes5("dai"), addressOne)
        givenPolicyOneIsActive
    {
        // Expect the policies to revert
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_ContractNotRegistered.selector));

        // Deregister the contract
        _deregisterContract(bytes5("dai"));
    }

    function test_deregisterContract_whenDependentPolicyIsRegistered()
        public
        givenContractIsRegistered(bytes5("ohm"), addressOne)
    {
        // Deregister the contract
        _deregisterContract(bytes5("ohm"));

        // Assert values
        assertEq(_policy.dai(), address(0));
    }

    // getImmutableContract
    // given the name is not registered
    //  [X] it reverts
    // [X] it returns the contract address

    function test_getImmutableContract_whenNameIsNotRegistered_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_ContractNotRegistered.selector));

        RGSTY.getImmutableContract(bytes5("ohm"));
    }

    function test_getImmutableContract()
        public
        givenImmutableContractIsRegistered(bytes5("ohm"), addressOne)
    {
        assertEq(RGSTY.getImmutableContract(bytes5("ohm")), addressOne);
    }

    // getContract
    // given the name is not registered
    //  [X] it reverts
    // given the name is registered
    //  given the name has been updated
    //   [X] it returns the latest address
    //  [X] it returns the contract address

    function test_getContract_whenNameIsNotRegistered_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RGSTYv1.Params_ContractNotRegistered.selector));

        RGSTY.getContract(bytes5("ohm"));
    }

    function test_getContract() public givenContractIsRegistered(bytes5("ohm"), addressOne) {
        assertEq(
            RGSTY.getContract(bytes5("ohm")),
            addressOne,
            "Contract address is not set correctly"
        );
    }

    function test_getContract_whenNameIsUpdated()
        public
        givenContractIsRegistered(bytes5("ohm"), addressOne)
        givenContractIsUpdated(bytes5("ohm"), addressTwo)
    {
        assertEq(
            RGSTY.getContract(bytes5("ohm")),
            addressTwo,
            "Contract address is not updated correctly"
        );
    }

    // getImmutableContractNames
    // given no names are registered
    //  [X] it returns an empty array
    // given names are registered
    //  [X] it returns the names array

    function test_getImmutableContractNames_whenNoNamesAreRegistered() public view {
        assertEq(RGSTY.getImmutableContractNames().length, 0, "Immutable names array is not empty");
    }

    function test_getImmutableContractNames()
        public
        givenImmutableContractIsRegistered(bytes5("ohm"), addressOne)
    {
        assertEq(
            RGSTY.getImmutableContractNames().length,
            1,
            "Immutable names array is not updated correctly"
        );
    }

    // getContractNames
    // given no names are registered
    //  [X] it returns an empty array
    // given names are registered
    //  [X] it returns the names array

    function test_getContractNames_whenNoNamesAreRegistered() public view {
        assertEq(RGSTY.getContractNames().length, 0, "Names array is not empty");
    }

    function test_getContractNames_whenNamesAreRegistered()
        public
        givenContractIsRegistered(bytes5("ohm"), addressOne)
        givenContractIsRegistered(bytes5("ohm2"), addressTwo)
        givenContractIsRegistered(bytes5("ohm3"), address(0x4))
    {
        assertEq(RGSTY.getContractNames().length, 3, "Names array is not updated correctly");
        assertEq(
            RGSTY.getContractNames()[0],
            bytes5("ohm"),
            "Names array at index 0 is not updated correctly"
        );
        assertEq(
            RGSTY.getContractNames()[1],
            bytes5("ohm2"),
            "Names array at index 1 is not updated correctly"
        );
        assertEq(
            RGSTY.getContractNames()[2],
            bytes5("ohm3"),
            "Names array at index 2 is not updated correctly"
        );
    }

    // KEYCODE
    // [X] it returns the correct keycode

    function test_KEYCODE() public view {
        assertEq(fromKeycode(RGSTY.KEYCODE()), bytes5("RGSTY"));
    }

    // VERSION
    // [X] it returns the correct version

    function test_VERSION() public view {
        (uint8 major, uint8 minor) = RGSTY.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }
}
