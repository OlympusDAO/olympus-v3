// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansPayout} from "src/policies/burnerloans/BurnerLoansPayout.sol";

contract BurnerLoansPayoutConstructorTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-CONSTRUCTOR-I01.
    function test_whenCoreIsZero_reverts(address deployer_) public {
        vm.expectCall(
            address(0),
            abi.encodeCall(IERC165.supportsInterface, (type(IERC165).interfaceId)),
            uint64(0)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidCore.selector,
                address(0)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansPayout(_kernel, address(0));
    }

    // Scenarios: BLCU-CONSTRUCTOR-I02.
    function test_whenCoreIsEoa_reverts(address deployer_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidCore.selector,
                _recipient
            )
        );
        vm.prank(deployer_);
        new BurnerLoansPayout(_kernel, _recipient);
    }

    // Scenarios: BLCU-CONSTRUCTOR-P02, BLCU-CONSTRUCTOR-V03.
    function test_whenPayoutDeployed_thenDisabledWithEmptyObligations(
        address deployer_,
        address caller_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenPendingBuckets {
        _setState(_core, coreActive_, coreEnabled_);
        bytes32 beforeState = _ledgerDigest();
        vm.prank(deployer_);
        BurnerLoansPayout payout = new BurnerLoansPayout(_kernel, address(_core));
        vm.startPrank(caller_);
        assertEq(payout.core(), address(_core), "Immutable Core binding");
        assertEq(address(payout.kernel()), address(_kernel), "Immutable Kernel binding");
        assertFalse(payout.isEnabled(), "Starts paused");
        assertEq(payout.configOperator(), address(0), "Delegation starts unset");
        assertEq(payout.revenueDistributor(), address(0), "Route starts unset");
        assertFalse(payout.sendFeesToDistributor(), "Default fee route Treasury");
        assertFalse(payout.sendYieldToDistributor(), "Default yield route Treasury");
        assertEq(payout.getPendingPayoutTokens().length, 0, "No initial obligations");
        vm.stopPrank();
        assertEq(payout.lastTransitionAt(), 0, "No initial transition history");
        assertEq(_ledgerDigest(), beforeState, "Deployment does not mutate existing obligations");
    }

    // Scenarios: BLCU-CONSTRUCTOR-D01.
    function test_givenMissingCoreInterface_whenDeployed_reverts(address caller_) public {
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansCore).interfaceId
            ),
            abi.encode(false)
        );
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("kernel()"), hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidCore.selector,
                address(_core)
            )
        );
        vm.prank(caller_);
        new BurnerLoansPayout(_kernel, address(_core));
    }

    // Scenarios: BLCU-CONSTRUCTOR-D02.
    function test_givenRevertingCoreInterface_whenDeployed_reverts(address caller_) public {
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansCore).interfaceId
            ),
            hex"deadbeef"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidCore.selector,
                address(_core)
            )
        );
        vm.prank(caller_);
        new BurnerLoansPayout(_kernel, address(_core));
    }

    // Scenarios: BLCU-CONSTRUCTOR-D03.
    function test_givenMalformedCoreInterface_whenDeployed_reverts(address caller_) public {
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansCore).interfaceId
            ),
            hex"01"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidCore.selector,
                address(_core)
            )
        );
        vm.prank(caller_);
        new BurnerLoansPayout(_kernel, address(_core));
    }

    // Scenarios: BLCU-CONSTRUCTOR-D04.
    function test_givenDifferentCoreKernel_whenDeployed_reverts(address caller_) public {
        Kernel next = new Kernel();
        vm.prank(address(_kernel));
        _core.changeKernel(next);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(_kernel),
                address(next)
            )
        );
        vm.prank(caller_);
        new BurnerLoansPayout(_kernel, address(_core));
    }

    // Scenarios: BLCU-CONSTRUCTOR-D05.
    function test_givenUnreadableCoreMetadata_whenDeployed_reverts(
        address caller_,
        bytes memory data_
    ) public {
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("kernel()"), data_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_core)
            )
        );
        vm.prank(caller_);
        new BurnerLoansPayout(_kernel, address(_core));
    }

    // Scenarios: BLCU-CONSTRUCTOR-K03.
    function test_givenMalformedCoreKernel_whenDeployed_reverts(
        address caller_,
        bytes memory data_
    ) public {
        vm.assume(data_.length != 32);
        vm.mockCall(address(_core), abi.encodeWithSignature("kernel()"), data_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_core)
            )
        );
        vm.prank(caller_);
        new BurnerLoansPayout(_kernel, address(_core));
    }

    // Scenarios: BLCU-CONSTRUCTOR-K03.
    function test_givenMalformedCoreKernelBoundaries_whenDeployed_reverts(address caller_) public {
        bytes[6] memory responses = [
            new bytes(0),
            new bytes(1),
            new bytes(31),
            new bytes(33),
            new bytes(64),
            abi.encode(type(uint256).max)
        ];
        // Every response must fail with the same owned error and preserve state.
        // forge-lint: disable-next-line(calls-loop)
        for (uint256 i; i < responses.length; ++i) {
            vm.mockCall(address(_core), abi.encodeWithSignature("kernel()"), responses[i]);
            vm.expectRevert(
                abi.encodeWithSelector(
                    PolicyDependency.PolicyDependency_InvalidDependency.selector,
                    address(_core)
                )
            );
            vm.prank(caller_);
            new BurnerLoansPayout(_kernel, address(_core));
        }
    }
}
