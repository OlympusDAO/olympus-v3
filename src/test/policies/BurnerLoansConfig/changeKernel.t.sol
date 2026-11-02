// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";
import {Kernel, KernelAdapter} from "src/Kernel.sol";

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansConfigChangeKernelTest is BurnerLoansConfigTest {
    // Scenarios: BLCFG-KERNEL-P01.
    function test_givenCurrentKernel_whenKernelChanged(
        address next_,
        bool active_,
        bool enabled_
    ) public {
        _setPolicyState(_config, active_, enabled_);
        bytes32 state = _stateDigest();
        vm.prank(address(_kernel));
        _config.changeKernel(Kernel(next_));
        assertEq(address(_config.kernel()), next_, "Exact next Kernel");
        assertEq(_config.facility(), address(_core), "Immutable Core preserved");
        assertEq(_config.configOperator(), _configurationCaller, "Operator preserved");
        vm.prank(next_);
        _config.changeKernel(_kernel);
        assertEq(_stateDigest(), state, "Kernel round trip preserves all other state");
    }

    // Scenarios: BLCFG-KERNEL-P02.
    function test_whenCallerIsNotKernel_reverts(address caller_, address next_) public {
        vm.assume(caller_ != address(_kernel));
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.changeKernel, (Kernel(next_))),
            abi.encodeWithSelector(KernelAdapter.KernelAdapter_OnlyKernel.selector, caller_)
        );
    }
}
