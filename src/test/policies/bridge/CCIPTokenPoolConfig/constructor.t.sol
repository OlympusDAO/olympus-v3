// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ILiquidityContainer} from "@chainlink-ccip-1.6.0/ccip/interfaces/ILiquidityContainer.sol";
import {ICCIPLiquidityContainer} from "src/external/bridge/ICCIPLiquidityContainer.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";

// Libraries
import {Pool} from "@chainlink-ccip-1.6.0/ccip/libraries/Pool.sol";

// Contracts
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {Kernel, Permissions} from "src/Kernel.sol";
import {CCIPTokenPoolConfig} from "src/policies/bridge/CCIPTokenPoolConfig.sol";
import {MockERC165Only} from "src/test/policies/bridge/mocks/MockERC165Only.sol";

import {CCIPTokenPoolConfigTest} from "./CCIPTokenPoolConfigTest.sol";

contract CCIPTokenPoolConfigTests_constructor is CCIPTokenPoolConfigTest {
    // when the grace period is zero
    //   [X] it reverts with GracePeriod_ZeroPeriod
    function test_whenGracePeriodIsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IGracePeriod.GracePeriod_ZeroPeriod.selector));
        new CCIPTokenPoolConfig(kernel, address(pool), 0);
    }

    // when the grace period is zero
    //   when the pool is the zero address
    //     [X] it reverts with GracePeriod_ZeroPeriod
    // Pins the guard order: the base constructor's grace check runs before the pool checks
    function test_whenGracePeriodIsZero_whenPoolIsZeroAddress_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IGracePeriod.GracePeriod_ZeroPeriod.selector));
        new CCIPTokenPoolConfig(kernel, address(0), 0);
    }

    // when the pool is the zero address
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidAddress("pool")
    // Pins the error identity: the dedicated zero check answers before the ERC165 probe, which
    // would also read the zero address as an invalid pool.
    function test_whenPoolIsZeroAddress_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_InvalidAddress.selector,
                "pool"
            )
        );
        new CCIPTokenPoolConfig(kernel, address(0), GRACE_PERIOD);
    }

    // when the pool candidate holds no code
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidPool
    // The ERC165 probe staticcall against an EOA returns no data and reads as false
    function test_whenPoolHasNoCode_reverts() public {
        address candidate = makeAddr("eoaPoolCandidate");

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_InvalidPool.selector,
                candidate
            )
        );
        new CCIPTokenPoolConfig(kernel, candidate, GRACE_PERIOD);
    }

    // when the pool candidate is a contract without supportsInterface
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidPool
    // The probe call reverts inside the candidate and reads as false; MockOhm is the candidate
    function test_whenPoolDoesNotImplementERC165_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_InvalidPool.selector,
                address(ohm)
            )
        );
        new CCIPTokenPoolConfig(kernel, address(ohm), GRACE_PERIOD);
    }

    // when the pool candidate answers ERC165 but does not advertise CCIP_POOL_V1
    //   [X] it reverts with CCIPTokenPoolConfig_InvalidPool
    // Requires the MockERC165Only mock: ERC165 answered, the pool identifier absent
    function test_whenPoolDoesNotAdvertiseCCIPPoolV1_reverts() public {
        MockERC165Only candidate = new MockERC165Only();
        vm.label(address(candidate), "erc165OnlyCandidate");

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfig.CCIPTokenPoolConfig_InvalidPool.selector,
                address(candidate)
            )
        );
        new CCIPTokenPoolConfig(kernel, address(candidate), GRACE_PERIOD);
    }

    // when the parameters are valid
    //   [X] it emits GracePeriodSet with the constructor argument
    //   [X] it reports the pool address through pool()
    //   [X] it reports isLiquidityContainer() true for the lock/release pool
    //   [X] it reports configOperator() as the zero address
    //   [X] it reports getDisabledRateLimiterConfig() as {true, 2, 1}
    //   [X] it reports VERSION() as (1, 0)
    //   [X] it reports isEnabled() false
    //   [X] it reports lastTransitionAt() zero
    //   [X] it reports gracePeriod() as the constructor argument
    //   [X] it returns an empty array from requestPermissions()
    //   [X] it reports the kernel address through kernel()
    //   [X] it reports ROLES() as the zero address before activation
    //   [X] it reports isActive() false before activation
    // The full initial-state assertion, covering the unset fields next to the set ones. The
    // instance is deployed inside the test so the pre-activation state is observable.
    function test_whenParametersAreValid() public {
        // The GracePeriodSet event is emitted from inside the base constructor, so it is
        // captured with recorded logs rather than an expectation on an external call
        vm.recordLogs();
        CCIPTokenPoolConfig freshConfig = _newConfig(address(pool), GRACE_PERIOD);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 gracePeriodSetCount;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(freshConfig) &&
                logs[i].topics[0] == IGracePeriod.GracePeriodSet.selector
            ) {
                ++gracePeriodSetCount;
                assertEq(
                    abi.decode(logs[i].data, (uint32)),
                    GRACE_PERIOD,
                    "GracePeriodSet should carry the constructor argument"
                );
            }
        }
        assertEq(gracePeriodSetCount, 1, "exactly one GracePeriodSet should be emitted");

        assertEq(freshConfig.pool(), address(pool), "pool() should report the constructor pool");
        assertTrue(
            freshConfig.isLiquidityContainer(),
            "the lock/release pool should probe as a liquidity container"
        );
        assertEq(freshConfig.configOperator(), address(0), "the config operator should be unset");
        _assertConfigEq(
            freshConfig.getDisabledRateLimiterConfig(),
            _containmentConfig(),
            "getDisabledRateLimiterConfig"
        );
        (uint8 major, uint8 minor) = freshConfig.VERSION();
        assertEq(major, 1, "the major version should be one");
        assertEq(minor, 0, "the minor version should be zero");
        assertFalse(freshConfig.isEnabled(), "the policy should start disabled");
        assertEq(freshConfig.lastTransitionAt(), 0, "lastTransitionAt should start at zero");
        assertEq(
            freshConfig.gracePeriod(),
            GRACE_PERIOD,
            "gracePeriod() should report the constructor argument"
        );
        Permissions[] memory requests = freshConfig.requestPermissions();
        assertEq(requests.length, 0, "requestPermissions() should be empty");
        assertEq(
            address(freshConfig.kernel()),
            address(kernel),
            "kernel() should report the constructor kernel"
        );
        assertEq(
            address(freshConfig.ROLES()),
            address(0),
            "ROLES should be unset before activation"
        );
        assertFalse(freshConfig.isActive(), "the policy should not be active before activation");
    }

    // when the pool is a burn/mint pool
    //   [X] it constructs successfully
    //   [X] it reports isLiquidityContainer() false
    function test_whenPoolIsBurnMintPool() public {
        CCIPTokenPoolConfig freshConfig = _newConfig(address(burnMintPool), GRACE_PERIOD);

        assertEq(
            freshConfig.pool(),
            address(burnMintPool),
            "pool() should report the burn/mint pool"
        );
        assertFalse(
            freshConfig.isLiquidityContainer(),
            "the burn/mint pool should not probe as a liquidity container"
        );
    }

    // given the pool is owned by an unrelated third party
    //   [X] it constructs successfully
    // Ownership is not probed at construction; the pool is adopted later through
    // acceptPoolOwnership.
    function test_givenPoolIsOwnedByThirdParty() public {
        // The direct proposal overwrites the pending proposal to the config made in setUp
        pool.transferOwnership(thirdParty);
        vm.prank(thirdParty);
        pool.acceptOwnership();
        assertEq(pool.owner(), thirdParty, "the third party should own the pool");

        CCIPTokenPoolConfig freshConfig = _newConfig(address(pool), GRACE_PERIOD);
        assertEq(freshConfig.pool(), address(pool), "pool() should report the constructor pool");
    }

    // when the grace period is one second
    //   [X] it constructs and reports gracePeriod() as one
    // The zero check is an equality, so one is the smallest accepted window
    function test_whenGracePeriodIsOne() public {
        CCIPTokenPoolConfig freshConfig = _newConfig(address(pool), 1);
        assertEq(freshConfig.gracePeriod(), 1, "gracePeriod() should be one");
    }

    // when the grace period is the uint32 maximum
    //   [X] it constructs and reports gracePeriod() as type(uint32).max
    function test_whenGracePeriodIsMax() public {
        CCIPTokenPoolConfig freshConfig = _newConfig(address(pool), type(uint32).max);
        assertEq(
            freshConfig.gracePeriod(),
            type(uint32).max,
            "gracePeriod() should be the uint32 maximum"
        );
    }

    // when the grace period is any non-zero value
    //   [X] it constructs and reports gracePeriod() equal to the argument
    // Fuzzed over the valid interval [1, type(uint32).max]
    function test_whenGracePeriodIsNonZero(uint32 gracePeriod_) public {
        uint32 boundedGracePeriod = uint32(bound(gracePeriod_, 1, type(uint32).max));
        // boundedGracePeriod is in the valid interval [1, type(uint32).max]

        CCIPTokenPoolConfig freshConfig = _newConfig(address(pool), boundedGracePeriod);
        assertEq(
            freshConfig.gracePeriod(),
            boundedGracePeriod,
            "gracePeriod() should equal the constructor argument"
        );
    }

    // when the kernel is the zero address
    //   [X] it constructs successfully
    // KernelAdapter validates nothing about the kernel; the failure surfaces only at
    // activation. Pins the absent guard as documented behavior.
    function test_whenKernelIsZeroAddress() public {
        CCIPTokenPoolConfig freshConfig = new CCIPTokenPoolConfig(
            Kernel(address(0)),
            address(pool),
            GRACE_PERIOD
        );
        vm.label(address(freshConfig), "zeroKernelConfig");

        assertEq(address(freshConfig.kernel()), address(0), "kernel() should be zero");
        assertEq(freshConfig.pool(), address(pool), "pool() should report the constructor pool");
    }

    // [X] Pool.CCIP_POOL_V1 equals 0xaff2afbf
    // [X] type(ICCIPLiquidityContainer).interfaceId equals the Chainlink ILiquidityContainer
    //     identifier and 0xe1d40566
    // [X] the lock/release pool advertises both identifiers and the burn/mint pool only the
    //     pool identifier
    // The constructor probes stand on these identities.
    function test_interfaceIdentifiersMatchChainlink() public view {
        assertEq(
            bytes32(Pool.CCIP_POOL_V1),
            bytes32(bytes4(0xaff2afbf)),
            "Pool.CCIP_POOL_V1 should equal 0xaff2afbf"
        );
        assertEq(
            bytes32(type(ICCIPLiquidityContainer).interfaceId),
            bytes32(type(ILiquidityContainer).interfaceId),
            "the MIT container interface id should equal the Chainlink one"
        );
        assertEq(
            bytes32(type(ICCIPLiquidityContainer).interfaceId),
            bytes32(bytes4(0xe1d40566)),
            "the container interface id should equal 0xe1d40566"
        );
        assertTrue(
            pool.supportsInterface(Pool.CCIP_POOL_V1),
            "the lock/release pool should advertise the pool identifier"
        );
        assertTrue(
            pool.supportsInterface(type(ICCIPLiquidityContainer).interfaceId),
            "the lock/release pool should advertise the container identifier"
        );
        assertTrue(
            burnMintPool.supportsInterface(Pool.CCIP_POOL_V1),
            "the burn/mint pool should advertise the pool identifier"
        );
        assertFalse(
            burnMintPool.supportsInterface(type(ICCIPLiquidityContainer).interfaceId),
            "the burn/mint pool should not advertise the container identifier"
        );
    }

    // [X] the applyChainUpdates selector equals 0xe8a1da17 on ICCIPTokenPoolAdmin
    // [X] the setChainRateLimiterConfig selector equals 0xcf7401f3
    // [X] the setChainRateLimiterConfigs selector equals 0x962d4020
    // The MIT interface layout must keep encoding to the Chainlink selectors so that the config
    // calls hit the deployed pool functions.
    function test_adminSelectorsMatchChainlink() public pure {
        assertEq(
            bytes32(ICCIPTokenPoolAdmin.applyChainUpdates.selector),
            bytes32(bytes4(0xe8a1da17)),
            "applyChainUpdates should keep the Chainlink selector"
        );
        assertEq(
            bytes32(ICCIPTokenPoolAdmin.setChainRateLimiterConfig.selector),
            bytes32(bytes4(0xcf7401f3)),
            "setChainRateLimiterConfig should keep the Chainlink selector"
        );
        assertEq(
            bytes32(ICCIPTokenPoolAdmin.setChainRateLimiterConfigs.selector),
            bytes32(bytes4(0x962d4020)),
            "setChainRateLimiterConfigs should keep the Chainlink selector"
        );
    }
}
