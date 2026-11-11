// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IKernel} from "src/interfaces/IKernel.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {Test} from "forge-std/Test.sol";
import {Kernel} from "src/Kernel.sol";

contract PolicyDependencyTest is Test {
    Kernel internal _kernel;
    address internal _dependency;
    bytes4 internal constant _KERNEL_SELECTOR = 0xd4aae0c4; // kernel()

    function setUp() public {
        _kernel = new Kernel();
        _dependency = makeAddr("dependency");
        vm.etch(_dependency, hex"00");
        vm.mockCall(_dependency, abi.encodeWithSelector(_KERNEL_SELECTOR), abi.encode(_kernel));
        _setReadiness(true, true);
    }

    function requireSameKernel() external view {
        PolicyDependency.requireSameKernel(_dependency, address(_kernel));
    }

    function requireActive() external view {
        PolicyDependency.requireActive(_dependency, address(_kernel));
    }

    function requireActiveAndEnabled() external view {
        PolicyDependency.requireActiveAndEnabled(_dependency, address(_kernel));
    }

    function test_whenCompatibleAndReady(address caller_) public {
        vm.prank(caller_);
        this.requireActiveAndEnabled();
    }

    function test_whenOnlyCompatibilityRequired(bool active_, bool enabled_) public {
        _setReadiness(active_, enabled_);
        vm.expectCall(_dependency, abi.encodeCall(IEnabler.isEnabled, ()), uint64(0));
        this.requireSameKernel();
    }

    function test_givenPaused_whenOnlyMembershipRequired() public {
        _setReadiness(true, false);
        vm.expectCall(_dependency, abi.encodeCall(IEnabler.isEnabled, ()), uint64(0));
        this.requireActive();
    }

    function test_whenKernelDiffers_reverts(address reported_, bool active_, bool enabled_) public {
        vm.assume(reported_ != address(_kernel));
        _setReadiness(active_, enabled_);
        vm.mockCall(_dependency, abi.encodeWithSelector(_KERNEL_SELECTOR), abi.encode(reported_));
        vm.expectCall(_dependency, abi.encodeCall(IEnabler.isEnabled, ()), uint64(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                _dependency,
                address(_kernel),
                reported_
            )
        );
        this.requireActiveAndEnabled();
    }

    function test_whenKernelReadReverts_reverts() public {
        vm.mockCallRevert(_dependency, abi.encodeWithSelector(_KERNEL_SELECTOR), hex"deadbeef");
        _expectInvalidDependency();
        this.requireActiveAndEnabled();
    }

    function test_whenKernelResponseMalformed_reverts(bytes memory output_) public {
        if (output_.length == 32) vm.assume(abi.decode(output_, (uint256)) > type(uint160).max);
        vm.mockCall(_dependency, abi.encodeWithSelector(_KERNEL_SELECTOR), output_);
        _expectInvalidDependency();
        this.requireActiveAndEnabled();
    }

    function test_whenKernelResponseBoundarySeeds_reverts() public {
        test_whenKernelResponseMalformed_reverts("");
        test_whenKernelResponseMalformed_reverts(new bytes(1));
        test_whenKernelResponseMalformed_reverts(new bytes(31));
        test_whenKernelResponseMalformed_reverts(new bytes(33));
        test_whenKernelResponseMalformed_reverts(new bytes(64));
        test_whenKernelResponseMalformed_reverts(new bytes(65_536));
        test_whenKernelResponseMalformed_reverts(abi.encode(type(uint256).max));
    }

    function test_whenStatusReadReverts_reverts() public {
        vm.mockCallRevert(_dependency, abi.encodeCall(IEnabler.isEnabled, ()), hex"deadbeef");
        _expectInvalidDependency();
        this.requireActiveAndEnabled();
    }

    function test_whenStatusResponseMalformed_reverts(bytes memory output_) public {
        if (output_.length == 32) vm.assume(abi.decode(output_, (uint256)) > 1);
        vm.mockCall(_dependency, abi.encodeCall(IEnabler.isEnabled, ()), output_);
        _expectInvalidDependency();
        this.requireActiveAndEnabled();
    }

    function test_whenStatusResponseBoundarySeeds_reverts() public {
        test_whenStatusResponseMalformed_reverts("");
        test_whenStatusResponseMalformed_reverts(new bytes(31));
        test_whenStatusResponseMalformed_reverts(new bytes(33));
        test_whenStatusResponseMalformed_reverts(new bytes(65_536));
        test_whenStatusResponseMalformed_reverts(abi.encode(uint256(2)));
        test_whenStatusResponseMalformed_reverts(abi.encode(type(uint256).max));
    }

    function test_whenDependencyUnavailable_reverts(bool active_, bool enabled_) public {
        vm.assume(!active_ || !enabled_);
        _setReadiness(active_, enabled_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                _dependency
            )
        );
        this.requireActiveAndEnabled();
    }

    function _expectInvalidDependency() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                _dependency
            )
        );
    }

    function _setReadiness(bool active_, bool enabled_) internal {
        vm.mockCall(_dependency, abi.encodeCall(IEnabler.isEnabled, ()), abi.encode(enabled_));
        vm.mockCall(
            address(_kernel),
            abi.encodeCall(IKernel.isPolicyActive, (_dependency)),
            abi.encode(active_)
        );
    }
}
