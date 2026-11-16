// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

// Contracts
import {BurnMintTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/BurnMintTokenPool.sol";
import {LockReleaseTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/LockReleaseTokenPool.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {CCIPTokenPoolConfig} from "src/policies/bridge/CCIPTokenPoolConfig.sol";
import {CCIPTokenPoolConfigTimelock} from "src/policies/bridge/CCIPTokenPoolConfigTimelock.sol";
import {ICCIPTokenPoolConfigProposalChecker} from "src/proposals/interfaces/ICCIPTokenPoolConfigProposalChecker.sol";
import {CCIPTokenPoolConfigProposalChecker} from "src/proposals/CCIPTokenPoolConfigProposalChecker.sol";

import {CCIPTokenPoolConfigProposalCheckerTest} from "./CCIPTokenPoolConfigProposalCheckerTest.sol";

contract CCIPTokenPoolConfigProposalCheckerTests_constructor is
    CCIPTokenPoolConfigProposalCheckerTest
{
    // ========== CONSTANTS ========== //

    /// @notice The positions of the constructor arguments, as `_deployWith` replaces them.
    uint256 internal constant _ARG_KERNEL = 0;
    uint256 internal constant _ARG_CONFIG = 1;
    uint256 internal constant _ARG_CONFIG_TIMELOCK = 2;
    uint256 internal constant _ARG_POOL = 3;
    uint256 internal constant _ARG_OHM = 4;
    uint256 internal constant _ARG_REGISTRY = 5;
    uint256 internal constant _ARG_ROLES = 6;
    uint256 internal constant _ARG_OCG_TIMELOCK = 7;
    uint256 internal constant _ARG_DAO_MS = 8;

    // ========== HELPERS ========== //

    /// @notice Deploys a checker with the rig's bindings, one argument replaced.
    function _deployWith(
        uint256 index_,
        address replacement_
    ) internal returns (CCIPTokenPoolConfigProposalChecker newChecker) {
        address[9] memory args = [
            address(kernel),
            address(config),
            address(timelock),
            address(pool),
            address(ohm),
            address(registry),
            address(rolesModule),
            ocgTimelock,
            daoMS
        ];
        args[index_] = replacement_;
        return
            _newChecker(
                args[0],
                args[1],
                args[2],
                args[3],
                args[4],
                args[5],
                args[6],
                args[7],
                args[8]
            );
    }

    // ========== ZERO ADDRESSES ========== //

    // when an argument is the zero address
    //   [X] it reverts with ZeroAddress naming the argument, in argument order

    function test_whenKernelIsZero_reverts() public {
        _expectRevertZeroAddress("kernel");
        _deployWith(_ARG_KERNEL, address(0));
    }

    function test_whenConfigIsZero_reverts() public {
        _expectRevertZeroAddress("config");
        _deployWith(_ARG_CONFIG, address(0));
    }

    function test_whenConfigTimelockIsZero_reverts() public {
        _expectRevertZeroAddress("configTimelock");
        _deployWith(_ARG_CONFIG_TIMELOCK, address(0));
    }

    function test_whenPoolIsZero_reverts() public {
        _expectRevertZeroAddress("pool");
        _deployWith(_ARG_POOL, address(0));
    }

    function test_whenOhmIsZero_reverts() public {
        _expectRevertZeroAddress("ohm");
        _deployWith(_ARG_OHM, address(0));
    }

    function test_whenRegistryIsZero_reverts() public {
        _expectRevertZeroAddress("registry");
        _deployWith(_ARG_REGISTRY, address(0));
    }

    function test_whenRolesIsZero_reverts() public {
        _expectRevertZeroAddress("roles");
        _deployWith(_ARG_ROLES, address(0));
    }

    function test_whenOcgTimelockIsZero_reverts() public {
        _expectRevertZeroAddress("ocgTimelock");
        _deployWith(_ARG_OCG_TIMELOCK, address(0));
    }

    function test_whenDaoMSIsZero_reverts() public {
        _expectRevertZeroAddress("daoMS");
        _deployWith(_ARG_DAO_MS, address(0));
    }

    // when every argument is zero
    //   [X] it reverts naming the first one

    function test_whenEveryArgumentIsZero_reverts() public {
        _expectRevertZeroAddress("kernel");
        _newChecker(
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        );
    }

    // ========== BINDINGS ========== //

    // when the pool is not the one the config policy reports
    //   [X] it reverts with BindingMismatch on the config pool

    function test_whenPoolIsNotTheConfigPool_reverts() public {
        LockReleaseTokenPool otherPool = _newLockReleasePool();

        _expectRevertBindingMismatch("CCIPTokenPoolConfig pool", address(pool), address(otherPool));
        _deployWith(_ARG_POOL, address(otherPool));
    }

    // when the config timelock reports another config policy
    //   [X] it reverts with BindingMismatch on the timelock config

    function test_whenTimelockReportsAnotherConfig_reverts() public {
        CCIPTokenPoolConfig otherConfig = _newConfig(address(pool));
        CCIPTokenPoolConfigTimelock otherTimelock = _newTimelockFor(address(otherConfig));

        _expectRevertBindingMismatch(
            "CCIPTokenPoolConfigTimelock config",
            address(otherConfig),
            address(config)
        );
        _deployWith(_ARG_CONFIG_TIMELOCK, address(otherTimelock));
    }

    // when the Kernel is not the one the config policy reports
    //   [X] it reverts with BindingMismatch on the config kernel

    function test_whenKernelIsNotTheConfigKernel_reverts() public {
        Kernel otherKernel = new Kernel();
        vm.label(address(otherKernel), "otherKernel");

        _expectRevertBindingMismatch(
            "CCIPTokenPoolConfig kernel",
            address(kernel),
            address(otherKernel)
        );
        _deployWith(_ARG_KERNEL, address(otherKernel));
    }

    // when the config timelock reports another Kernel than the config policy
    //   [X] it reverts with BindingMismatch on the timelock kernel

    function test_whenTimelockReportsAnotherKernel_reverts() public {
        // The timelock constructor requires the config policy to report the same Kernel, so
        // the divergence is stubbed on the deployed timelock
        address otherKernel = makeAddr("otherKernel");
        vm.mockCall(
            address(timelock),
            abi.encodeWithSignature("kernel()"),
            abi.encode(otherKernel)
        );

        _expectRevertBindingMismatch(
            "CCIPTokenPoolConfigTimelock kernel",
            otherKernel,
            address(kernel)
        );
        _deployWith(_ARG_KERNEL, address(kernel));
    }

    // when the ROLES module is not the one the Kernel reports
    //   [X] it reverts with BindingMismatch on the ROLES module

    function test_whenRolesIsNotTheKernelModule_reverts() public {
        address otherRoles = makeAddr("otherRoles");

        _expectRevertBindingMismatch("ROLES module", address(rolesModule), otherRoles);
        _deployWith(_ARG_ROLES, otherRoles);
    }

    // when the token is not the one the pool serves
    //   [X] it reverts with BindingMismatch on the pool token

    function test_whenOhmIsNotThePoolToken_reverts() public {
        address otherToken = makeAddr("otherToken");

        _expectRevertBindingMismatch("pool token", address(ohm), otherToken);
        _deployWith(_ARG_OHM, otherToken);
    }

    // when the config policy reports that the pool is not a liquidity container
    //   [X] it reverts with NotLiquidityContainer naming the pool

    function test_whenPoolIsNotALiquidityContainer_reverts() public {
        BurnMintTokenPool burnMintPool = _newBurnMintPool();
        CCIPTokenPoolConfig burnMintConfig = _newConfig(address(burnMintPool));
        CCIPTokenPoolConfigTimelock burnMintTimelock = _newTimelockFor(address(burnMintConfig));

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_NotLiquidityContainer
                    .selector,
                address(burnMintPool)
            )
        );
        _newChecker(
            address(kernel),
            address(burnMintConfig),
            address(burnMintTimelock),
            address(burnMintPool),
            address(ohm),
            address(registry),
            address(rolesModule),
            ocgTimelock,
            daoMS
        );
    }

    // ========== SUCCESS ========== //

    // when every argument is bound
    //   [X] the immutables report the arguments

    function test_whenBound() public view {
        assertEq(address(checker.KERNEL()), address(kernel), "KERNEL should be the Kernel");
        assertEq(address(checker.CONFIG()), address(config), "CONFIG should be the config policy");
        assertEq(
            address(checker.CONFIG_TIMELOCK()),
            address(timelock),
            "CONFIG_TIMELOCK should be the config timelock"
        );
        assertEq(address(checker.POOL()), address(pool), "POOL should be the pool");
        assertEq(address(checker.OHM()), address(ohm), "OHM should be the token");
        assertEq(address(checker.REGISTRY()), address(registry), "REGISTRY should be the registry");
        assertEq(
            address(checker.ROLES()),
            address(rolesModule),
            "ROLES should be the ROLES module"
        );
        assertEq(checker.OCG_TIMELOCK(), ocgTimelock, "OCG_TIMELOCK should be the OCG timelock");
        assertEq(checker.DAO_MS(), daoMS, "DAO_MS should be the DAO MS");
    }

    // when the policies are not active in the Kernel
    //   [X] the deployment succeeds, since activation is a live condition of check

    function test_whenPoliciesNotActive() public {
        Kernel rigKernel = kernel;
        address configAddress = address(config);
        address timelockAddress = address(timelock);
        rigKernel.executeAction(Actions.DeactivatePolicy, timelockAddress);
        rigKernel.executeAction(Actions.DeactivatePolicy, configAddress);

        CCIPTokenPoolConfigProposalChecker fresh = _deployWith(_ARG_KERNEL, address(kernel));
        assertEq(address(fresh.CONFIG()), address(config), "CONFIG should be the config policy");
    }
}
