// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {BL_COLLATERAL_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansCollateral} from "src/policies/burnerloans/BurnerLoansCollateral.sol";
import {BurnerLoansCollateralTest} from "src/test/policies/BurnerLoansCollateral/BurnerLoansCollateralTest.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralConstructorTest is BurnerLoansCollateralTest {
    // Scenarios: BLCOL-CONSTRUCTOR-I01.
    function test_whenCoreZero_reverts(address deployer_) public {
        _expectInvalidCore(address(0));
        vm.prank(deployer_);
        new BurnerLoansCollateral(kernel, IBurnerLoansCore(address(0)));
    }

    // Scenarios: BLCOL-CONSTRUCTOR-I02.
    function test_whenCoreEOA_reverts(address candidate_, address deployer_) public {
        vm.assume(candidate_.code.length == 0);
        _expectInvalidCore(candidate_);
        vm.prank(deployer_);
        new BurnerLoansCollateral(kernel, IBurnerLoansCore(candidate_));
    }

    // Scenarios: BLCOL-CONSTRUCTOR-I03.
    function test_whenCoreInterfaceMissing_reverts(address deployer_) public {
        _removeInterface(type(IBurnerLoansCore).interfaceId);
        _expectInvalidCore(address(policy));
        vm.prank(deployer_);
        new BurnerLoansCollateral(kernel, IBurnerLoansCore(address(policy)));
    }

    // Scenarios: BLCOL-CONSTRUCTOR-I04.
    function test_whenEnablerInterfaceMissing_reverts(address deployer_) public {
        _removeInterface(type(IEnabler).interfaceId);
        _expectInvalidCore(address(policy));
        vm.prank(deployer_);
        new BurnerLoansCollateral(kernel, IBurnerLoansCore(address(policy)));
    }

    // Scenarios: BLCOL-CONSTRUCTOR-I05.
    function test_whenERC165Reverts_reverts(address deployer_) public {
        vm.mockCallRevert(
            address(policy),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansCore).interfaceId
            ),
            hex"deadbeef"
        );
        _expectInvalidCore(address(policy));
        vm.prank(deployer_);
        new BurnerLoansCollateral(kernel, IBurnerLoansCore(address(policy)));
    }

    // Scenarios: BLCOL-CONSTRUCTOR-I06.
    function test_whenERC165Malformed_reverts(address deployer_) public {
        vm.mockCall(
            address(policy),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansCore).interfaceId
            ),
            hex"01"
        );
        _expectInvalidCore(address(policy));
        vm.prank(deployer_);
        new BurnerLoansCollateral(kernel, IBurnerLoansCore(address(policy)));
    }

    // Scenarios: BLCOL-CONSTRUCTOR-I07.
    function test_whenCoreKernelDiffers_reverts(address deployer_) public {
        Kernel otherKernel = new Kernel();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(policy),
                address(otherKernel),
                address(kernel)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansCollateral(otherKernel, IBurnerLoansCore(address(policy)));
    }

    // Scenarios: BLCOL-CONSTRUCTOR-I08, BLCOL-CONSTRUCTOR-I09, BLCOL-CONSTRUCTOR-I10, BLCOL-CONSTRUCTOR-I11.
    function test_whenValidCoreBinding(address deployer_, bool active_, bool enabled_) public {
        _setPolicyState(policy, active_, enabled_);
        vm.expectEmit();
        emit IGracePeriod.GracePeriodSet(7 days);
        vm.prank(deployer_);
        BurnerLoansCollateral deployed = new BurnerLoansCollateral(
            kernel,
            IBurnerLoansCore(address(policy))
        );
        assertEq(deployed.core(), address(policy), "Immutable Core binding mismatch");
        assertEq(address(deployed.kernel()), address(kernel), "Kernel binding mismatch");
        assertFalse(deployed.isEnabled(), "Action must start disabled");
        assertFalse(kernel.isPolicyActive(deployed), "Construction must not activate policy");
        assertEq(deployed.lastTransitionAt(), 0, "Fresh action has no transition history");
        assertEq(deployed.gracePeriod(), 7 days, "Default grace period mismatch");
        assertFalse(
            roles.hasRole(address(deployed), BL_COLLATERAL_POLICY_ROLE),
            "Construction must not grant settlement role"
        );
        _assertAccountingPreserved();
        assertEq(_asset.balanceOf(address(deployed)), 0, "Construction funds no collateral");
        assertEq(_ohm.balanceOf(address(deployed)), 0, "Construction funds no OHM");
        (uint8 major, uint8 minor) = deployed.VERSION();
        assertEq(major, 1, "Version major mismatch");
        assertEq(minor, 0, "Version minor mismatch");
    }

    function _expectInvalidCore(address candidate_) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore.selector,
                candidate_
            )
        );
    }

    function _removeInterface(bytes4 id_) private {
        vm.mockCall(
            address(policy),
            abi.encodeWithSignature("supportsInterface(bytes4)", id_),
            abi.encode(false)
        );
    }

    // Scenarios: BLCOL-CONSTRUCTOR-I08, BLCOL-CONSTRUCTOR-I09, BLCOL-CONSTRUCTOR-I10, BLCOL-CONSTRUCTOR-I11.
    function test_whenCoreLifecycleSeedsUsed_thenInitializationIsIndependent() public {
        for (uint256 flags; flags < 4; ++flags) {
            uint256 checkpoint = vm.snapshotState();
            test_whenValidCoreBinding(address(0), flags & 1 != 0, flags & 2 != 0);
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore Core between constructor lifecycle seeds"
            );
        }
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
