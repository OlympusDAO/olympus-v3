// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IBurnerLoansAuthTarget} from "src/policies/interfaces/burnerloans/IBurnerLoansAuthTarget.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansAuthTest} from "./BurnerLoansAuthTest.sol";
import {BurnerLoansAuth} from "src/policies/burnerloans/BurnerLoansAuth.sol";

contract BurnerLoansAuthConstructorTest is BurnerLoansAuthTest {
    // Scenarios: BLAUTH-CONSTRUCTOR-D01.
    function test_whenCoreReportsOtherKernel_reverts(
        address reported_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(reported_ != address(_kernel));
        _kernel.setActive(active_);
        _core.setEnabled(enabled_);
        vm.mockCall(address(_core), abi.encodeWithSignature("kernel()"), abi.encode(reported_));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(_kernel),
                reported_
            )
        );
        new BurnerLoansAuth(address(_kernel), address(_core));
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-D01.
    function test_whenReportedKernelBoundarySeeds_reverts() public {
        test_whenCoreReportsOtherKernel_reverts(address(0), false, false);
        test_whenCoreReportsOtherKernel_reverts(address(type(uint160).max), true, true);
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-D02.
    function test_whenCoreKernelGetterReverts_reverts() public {
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSelector(IBurnerLoansAuth.BurnerLoansAuth_NotSelected.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_core)
            )
        );
        new BurnerLoansAuth(address(_kernel), address(_core));
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-D03.
    function test_whenCoreKernelGetterMalformed_reverts(bool noncanonical_) public {
        bytes memory data = noncanonical_
            ? abi.encode(uint256(type(uint160).max) + 1)
            : bytes(hex"01");
        vm.mockCall(address(_core), abi.encodeWithSignature("kernel()"), data);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_core)
            )
        );
        new BurnerLoansAuth(address(_kernel), address(_core));
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-I02.
    function test_whenKernelIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansAuth.BurnerLoansAuth_InvalidKernel.selector,
                address(0)
            )
        );
        new BurnerLoansAuth(address(0), address(_core));
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-P03.
    function test_whenNonzeroKernelHasNoCode(address kernel_, bool enabled_) public {
        vm.assume(kernel_ != address(0) && kernel_.code.length == 0);
        _core.setEnabled(enabled_);
        vm.mockCall(address(_core), abi.encodeWithSignature("kernel()"), abi.encode(kernel_));
        BurnerLoansAuth auth = new BurnerLoansAuth(kernel_, address(_core));
        assertEq(
            auth.core(),
            address(_core),
            "Construction records identity without code admission"
        );
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-P03.
    function test_whenNonzeroKernelBoundarySeeds() public {
        test_whenNonzeroKernelHasNoCode(address(1), false);
        test_whenNonzeroKernelHasNoCode(address(type(uint160).max), true);
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-I01.
    function test_whenCoreIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansAuth.BurnerLoansAuth_InvalidCore.selector,
                address(0)
            )
        );
        new BurnerLoansAuth(address(_kernel), address(0));
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-P01.
    function test_whenCoreIsDeployed(address deployer_, bool active_, bool enabled_) public {
        _kernel.setActive(active_);
        _core.setEnabled(enabled_);
        vm.prank(deployer_);
        BurnerLoansAuth auth = new BurnerLoansAuth(address(_kernel), address(_core));
        assertEq(
            auth.core(),
            address(_core),
            "Constructor checks compatibility without readiness or prior selection"
        );
        (uint8 major, uint8 minor) = auth.VERSION();
        assertEq(major, 1, "Authorization interface major version");
        assertEq(minor, 0, "Authorization interface minor version");
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-I03.
    function test_whenCoreHasNoCode_reverts(address core_) public {
        vm.assume(core_.code.length == 0);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansAuth.BurnerLoansAuth_InvalidCore.selector, core_)
        );
        new BurnerLoansAuth(address(_kernel), core_);
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-I03.
    function test_whenCoreNoCodeBoundarySeeds_reverts() public {
        test_whenCoreHasNoCode_reverts(address(0));
        test_whenCoreHasNoCode_reverts(address(1));
        test_whenCoreHasNoCode_reverts(address(type(uint160).max));
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-I04.
    function test_whenCoreOmitsTargetInterface_reverts() public {
        vm.mockCall(
            address(_core),
            abi.encodeCall(IERC165.supportsInterface, (type(IBurnerLoansAuthTarget).interfaceId)),
            abi.encode(false)
        );
        _expectInvalidCore();
        new BurnerLoansAuth(address(_kernel), address(_core));
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-I04.
    function test_whenCoreIsAnotherContract_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansAuth.BurnerLoansAuth_InvalidCore.selector,
                address(_auth)
            )
        );
        new BurnerLoansAuth(address(_kernel), address(_auth));
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-I05.
    function test_whenCoreRejectsErc165_reverts() public {
        vm.mockCall(
            address(_core),
            abi.encodeCall(IERC165.supportsInterface, (type(IERC165).interfaceId)),
            abi.encode(false)
        );
        _expectInvalidCore();
        new BurnerLoansAuth(address(_kernel), address(_core));
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-I06.
    function test_whenCoreSupportsInvalidInterface_reverts() public {
        vm.mockCall(
            address(_core),
            abi.encodeCall(IERC165.supportsInterface, (bytes4(0xffffffff))),
            abi.encode(true)
        );
        _expectInvalidCore();
        new BurnerLoansAuth(address(_kernel), address(_core));
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-I07.
    function test_whenCoreInterfaceProbeReverts_reverts() public {
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(IERC165.supportsInterface, (type(IBurnerLoansAuthTarget).interfaceId)),
            abi.encodeWithSelector(IBurnerLoansAuth.BurnerLoansAuth_NotSelected.selector)
        );
        _expectInvalidCore();
        new BurnerLoansAuth(address(_kernel), address(_core));
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-I08.
    function test_whenCoreInterfaceProbeReturnsShortData_reverts() public {
        vm.mockCall(
            address(_core),
            abi.encodeCall(IERC165.supportsInterface, (type(IBurnerLoansAuthTarget).interfaceId)),
            hex"01"
        );
        _expectInvalidCore();
        new BurnerLoansAuth(address(_kernel), address(_core));
    }

    function _expectInvalidCore() private {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansAuth.BurnerLoansAuth_InvalidCore.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLAUTH-CONSTRUCTOR-P02.
    function test_whenInterfacesQueried() public view {
        assertTrue(_auth.supportsInterface(type(IERC165).interfaceId), "ERC165 is supported");
        assertTrue(
            _auth.supportsInterface(type(IOperatorAuth).interfaceId),
            "Generic grant interface is supported"
        );
        assertTrue(
            _auth.supportsInterface(type(IBurnerLoansAuth).interfaceId),
            "Lending bound interface is supported"
        );
        assertTrue(
            _auth.supportsInterface(type(IBurnerLoansCoreBound).interfaceId),
            "Immutable Core binding interface is supported"
        );
        assertTrue(
            _auth.supportsInterface(type(IVersioned).interfaceId),
            "Version discovery is supported"
        );
        assertFalse(
            _auth.supportsInterface(0xffffffff),
            "Invalid interface identifier is rejected"
        );
    }
}
