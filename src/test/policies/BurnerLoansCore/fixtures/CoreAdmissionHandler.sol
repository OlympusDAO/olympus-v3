// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {BL_DEBT_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansCore} from "src/policies/burnerloans/BurnerLoansCore.sol";

/// @dev One owner/operator model; independent Kernel/local transitions and grant/revocation sequences.
contract CoreAdmissionHandler is Test {
    BurnerLoansCore internal _core;
    Kernel internal _kernel;
    address public constant OPERATOR = address(0x777);
    bool public expectedActive = true;
    bool public expectedEnabled = true;
    uint256 public expectedNonce;
    uint48 public expectedDeadline;

    constructor(BurnerLoansCore core_, Kernel kernel_) {
        _core = core_;
        _kernel = kernel_;
    }

    function transition(bool active_, bool enabled_) external {
        // Enable requires activity; temporarily restore it before independently selecting the final flags.
        if (!expectedActive) {
            vm.prank(_kernel.executor());
            _kernel.executeAction(Actions.ActivatePolicy, address(_core));
        }
        if (enabled_ && !expectedEnabled) _core.enable("");
        if (!enabled_ && expectedEnabled) _core.disable("");
        if (!active_) {
            vm.prank(_kernel.executor());
            _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        }
        expectedActive = active_;
        expectedEnabled = enabled_;
    }

    function grant() external {
        if (!expectedActive) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                    address(_core)
                )
            );
            _core.setAuthorization(OPERATOR, type(uint48).max);
            return;
        }
        if (!expectedEnabled) {
            vm.expectRevert(IEnabler.NotEnabled.selector);
            _core.setAuthorization(OPERATOR, type(uint48).max);
            return;
        }
        _core.setAuthorization(OPERATOR, type(uint48).max);
        ++expectedNonce;
        expectedDeadline = type(uint48).max;
    }

    function cancel() external {
        _core.cancelAuthorization(OPERATOR);
        ++expectedNonce;
        expectedDeadline = 0;
    }

    function unauthorizedSettlement() external {
        if (!expectedActive)
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                    address(_core)
                )
            );
        else if (!expectedEnabled) vm.expectRevert(IEnabler.NotEnabled.selector);
        else
            vm.expectRevert(
                abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_DEBT_POLICY_ROLE)
            );
        _core.settleBorrow(
            IBurnerLoansCore.BorrowRequest(address(0), address(0), address(0), address(0), 0, 0, 0)
        );
    }
}
