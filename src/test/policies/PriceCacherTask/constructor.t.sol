// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPriceCacherTask} from "src/policies/interfaces/IPriceCacherTask.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {MockPriceCacherTaskCache} from "./MockPriceCacherTaskCache.sol";
import {PriceCacherTaskTest} from "./PriceCacherTaskTest.sol";
import {Kernel} from "src/Kernel.sol";
import {PriceCacherTask} from "src/policies/PriceCacherTask.sol";

contract PriceCacherTaskConstructorTest is PriceCacherTaskTest {
    // when PriceCache is zero
    //  then the call reverts
    // Scenarios: PCACHER-CONSTRUCTOR-I01.
    function test_whenPriceCacheIsZero_reverts() public {
        vm.expectRevert(IPriceCacherTask.PriceCacherTask_ZeroAddress.selector);
        _deployWithTestLimits(IPriceCache(address(0)));
    }

    // Scenarios: PCACHER-CONSTRUCTOR-I03.
    function test_whenPairGasLimitIsZero_reverts(uint32 executionGas_) public {
        _expectInvalidGasLimits(executionGas_, 0);
    }

    // Scenarios: PCACHER-CONSTRUCTOR-I04.
    function test_whenExecutionGasEqualsPairGasPlusReserve_reverts() public {
        _expectInvalidGasLimits(440_000, 400_000);
    }

    // Scenarios: PCACHER-CONSTRUCTOR-I05.
    function test_whenGasLimitsAreInvalid_revertsAtBoundaries() public {
        _expectInvalidGasLimits(type(uint32).max, 0);
        _expectInvalidGasLimits(0, 1);
        _expectInvalidGasLimits(1, 1);
        _expectInvalidGasLimits(40_000, 1);
        _expectInvalidGasLimits(40_001, 1);
        _expectInvalidGasLimits(type(uint32).max, type(uint32).max - 40_000);
        _expectInvalidGasLimits(type(uint32).max, type(uint32).max);
    }

    // Scenarios: PCACHER-CONSTRUCTOR-I06.
    function test_whenExecutionGasLeavesInsufficientGasForAPair_reverts(
        uint32 executionGas_,
        uint32 pairGas_
    ) public {
        pairGas_ = uint32(bound(pairGas_, 1, type(uint32).max));
        uint256 highestInvalidExecutionGas = uint256(pairGas_) + 40_000;
        if (highestInvalidExecutionGas > type(uint32).max)
            highestInvalidExecutionGas = type(uint32).max;
        executionGas_ = uint32(bound(executionGas_, 0, highestInvalidExecutionGas));

        _expectInvalidGasLimits(executionGas_, pairGas_);
    }

    // Scenarios: PCACHER-CONSTRUCTOR-P02.
    function test_whenGasLimitsAreValid_storesBoundaryValues() public {
        _assertDeployedGasLimits(40_002, 1);
        _assertDeployedGasLimits(40_003, 2);
        _assertDeployedGasLimits(440_001, 400_000);
        _assertDeployedGasLimits(type(uint32).max, type(uint32).max - 40_001);
    }

    // Scenarios: PCACHER-CONSTRUCTOR-P03.
    function test_whenGasLimitsAreValid_storesBoth(uint32 executionGas_, uint32 pairGas_) public {
        executionGas_ = uint32(bound(executionGas_, 40_002, type(uint32).max));
        pairGas_ = uint32(bound(pairGas_, 1, executionGas_ - 40_001));

        _assertDeployedGasLimits(executionGas_, pairGas_);
    }

    function _expectInvalidGasLimits(uint32 executionGas_, uint32 pairGas_) private {
        vm.expectRevert(IPriceCacherTask.PriceCacherTask_InvalidGasLimits.selector);
        new PriceCacherTask(kernel, priceCache, executionGas_, pairGas_);
    }

    function _assertDeployedGasLimits(uint32 executionGas_, uint32 pairGas_) private {
        PriceCacherTask candidate = new PriceCacherTask(
            kernel,
            priceCache,
            executionGas_,
            pairGas_
        );
        assertEq(candidate.executionGasLimit(), executionGas_, "configured execution gas");
        assertEq(candidate.pairGasLimit(), pairGas_, "configured pair gas");
    }

    function _deployWithTestLimits(IPriceCache cache_) private {
        new PriceCacherTask(kernel, cache_, _TEST_EXECUTION_GAS_LIMIT, _TEST_PAIR_GAS_LIMIT);
    }

    // when PriceCache is not a contract
    //  then the call reverts
    // Scenarios: PCACHER-CONSTRUCTOR-I02.
    function test_whenPriceCacheIsNotContract_reverts() public {
        address candidate = makeAddr("candidate");
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_InvalidPriceCache.selector,
                candidate
            )
        );
        _deployWithTestLimits(IPriceCache(candidate));
    }

    // when PriceCache does not support required interface
    //  then the call reverts
    // Scenarios: PCACHER-CONSTRUCTOR-D01.
    function test_whenPriceCacheDoesNotSupportRequiredInterface_reverts() public {
        MockPriceCacherTaskCache candidate = new MockPriceCacherTaskCache(kernel);
        candidate.setInterfaceSupport(true, false, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_InvalidPriceCache.selector,
                address(candidate)
            )
        );
        _deployWithTestLimits(candidate);
    }

    // when PriceCache belongs to a different Kernel
    //  then the call reverts
    // Scenarios: PCACHER-CONSTRUCTOR-D05.
    function test_whenPriceCacheUsesDifferentKernel_reverts() public {
        Kernel otherKernel = new Kernel();
        MockPriceCacherTaskCache candidate = new MockPriceCacherTaskCache(otherKernel);

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(candidate),
                address(kernel),
                address(otherKernel)
            )
        );
        _deployWithTestLimits(candidate);
    }

    // when the configuration is valid
    //  then it starts with no asset pairs
    // Scenarios: PCACHER-CONSTRUCTOR-P01.
    function test_whenConfigurationIsValid_startsWithNoAssetPairs(address deployer_) public {
        vm.prank(deployer_);
        PriceCacherTask candidate = new PriceCacherTask(kernel, priceCache, 620_000, 300_000);

        assertEq(candidate.priceCache(), address(priceCache), "price cache");
        assertEq(candidate.executionGasLimit(), 620_000, "configured execution gas");
        assertEq(candidate.pairGasLimit(), 300_000, "configured pair gas");
        assertEq(candidate.getAssetPairs().length, 0, "pair count");
        assertEq(address(candidate.kernel()), address(kernel), "constructor Kernel binding");
        assertFalse(candidate.isEnabled(), "initially disabled");
        assertEq(candidate.lastTransitionAt(), 0, "no transition history");
        assertEq(candidate.gracePeriod(), 7 days, "initial grace");
    }

    // Scenarios: PCACHER-CONSTRUCTOR-L01.
    function test_givenCacheLifecycle_whenDeployed(
        address deployer_,
        bool active_,
        bool enabled_
    ) public {
        _setCacheState(priceCache, active_, enabled_);
        test_whenConfigurationIsValid_startsWithNoAssetPairs(deployer_);
    }

    // Scenarios: PCACHER-CONSTRUCTOR-L01.
    function test_whenStartupLifecycleSeedsUsed() public {
        for (uint256 active; active < 2; ++active)
            for (uint256 enabled; enabled < 2; ++enabled) {
                uint256 snapshot = vm.snapshotState();
                test_givenCacheLifecycle_whenDeployed(address(0), active != 0, enabled != 0);
                assertTrue(vm.revertToStateAndDelete(snapshot), "restore startup state");
            }
    }

    // Scenarios: PCACHER-CONSTRUCTOR-D02.
    function test_givenCacheInterfaceMissing_whenDeployed_reverts() public {
        priceCache.setInterfaceSupport(false, true, true);
        _expectInvalidCache();
    }

    // Scenarios: PCACHER-CONSTRUCTOR-D08.
    function test_givenKernelGetterReverts_whenDeployed_reverts() public {
        vm.mockCallRevert(address(priceCache), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        _expectInvalidMetadata();
    }

    // Scenarios: PCACHER-CONSTRUCTOR-D09.
    function test_givenMalformedKernelLength_whenDeployed_reverts(bytes memory data_) public {
        vm.assume(data_.length <= 256 && data_.length != 32);
        vm.mockCall(address(priceCache), abi.encodeWithSignature("kernel()"), data_);
        _expectInvalidMetadata();
    }

    // Scenarios: PCACHER-CONSTRUCTOR-D09.
    function test_givenNoncanonicalKernel_whenDeployed_reverts(uint256 word_) public {
        word_ = bound(word_, uint256(type(uint160).max) + 1, type(uint256).max);
        vm.mockCall(address(priceCache), abi.encodeWithSignature("kernel()"), abi.encode(word_));
        _expectInvalidMetadata();
    }

    // Scenarios: PCACHER-CONSTRUCTOR-D09.
    function test_whenMalformedMetadataBoundarySeeds_reverts() public {
        test_givenNoncanonicalKernel_whenDeployed_reverts(uint256(type(uint160).max) + 1);
        vm.clearMockedCalls();
        test_givenNoncanonicalKernel_whenDeployed_reverts(type(uint256).max);
        vm.clearMockedCalls();
        test_givenMalformedKernelLength_whenDeployed_reverts("");
        vm.clearMockedCalls();
        test_givenMalformedKernelLength_whenDeployed_reverts(new bytes(33));
    }

    function _expectInvalidCache() internal {
        vm.expectRevert(_invalidCache(address(priceCache)));
        _deployWithTestLimits(priceCache);
    }

    function _expectInvalidMetadata() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(priceCache)
            )
        );
        _deployWithTestLimits(priceCache);
    }

    // Scenarios: PCACHER-CONSTRUCTOR-D11.
    function test_givenInterfaceProbeReverts_whenDeployed_reverts() public {
        vm.mockCallRevert(
            address(priceCache),
            abi.encodeWithSignature("supportsInterface(bytes4)", type(IPriceCache).interfaceId),
            hex"deadbeef"
        );
        _expectInvalidCache();
    }

    // Scenarios: PCACHER-CONSTRUCTOR-D12.
    function test_givenInterfaceProbeMalformed_whenDeployed_reverts() public {
        vm.mockCall(
            address(priceCache),
            abi.encodeWithSignature("supportsInterface(bytes4)", type(IPriceCache).interfaceId),
            hex"01"
        );
        _expectInvalidCache();
    }

    // Scenarios: PCACHER-CONSTRUCTOR-D10.
    function test_givenNoVersionInterface_whenDeployed_thenAccepted(address deployer_) public {
        priceCache.setInterfaceSupport(true, true, false);
        _forbidCacheVersionReads(priceCache);
        test_whenConfigurationIsValid_startsWithNoAssetPairs(deployer_);
    }

    // Scenarios: PCACHER-CONSTRUCTOR-D06.
    function test_givenVersionGetterReverts_whenDeployed_thenIgnored(address deployer_) public {
        _forbidCacheVersionReads(priceCache);
        test_whenConfigurationIsValid_startsWithNoAssetPairs(deployer_);
    }
}
