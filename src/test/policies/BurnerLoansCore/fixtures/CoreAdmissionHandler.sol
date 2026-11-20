// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

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
    IBurnerLoansAuth internal _auth;
    address internal _asset;
    address public constant OPERATOR = address(0x777);
    bool public expectedActive = true;
    bool public expectedEnabled = true;
    uint256 public expectedNonce;
    uint48 public expectedDeadline;

    // Controlled test bindings/callers intentionally retain zero-address cases where applicable.
    // forge-lint: disable-start(missing-zero-check)
    constructor(BurnerLoansCore core_, Kernel kernel_, IBurnerLoansAuth auth_, address asset_) {
        _core = core_;
        _kernel = kernel_;
        _auth = auth_;
        _asset = asset_;
    }

    // forge-lint: disable-end(missing-zero-check)

    // Fixture/cheatcode calls deliberately interleave effects to exercise callbacks and model transitions.
    // forge-lint: disable-start(reentrancy-no-eth)
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

    // forge-lint: disable-end(reentrancy-no-eth)

    function grant() external {
        IOperatorAuth.Grant memory grant = IOperatorAuth.Grant({
            account: address(this),
            operator: OPERATOR,
            accountEpoch: _auth.accountEpochs(address(this)),
            pairEpoch: _auth.pairEpochs(address(this), OPERATOR),
            deadline: type(uint48).max,
            multiple: true,
            actions: 1,
            context: _auth.authorizationContext(address(this), OPERATOR),
            permissions: abi.encode(
                IBurnerLoansAuth.Permissions(
                    _asset,
                    type(uint128).max,
                    address(0),
                    address(0),
                    0,
                    address(0),
                    address(0),
                    0,
                    address(0),
                    0
                )
            )
        });
        if (!expectedActive || !expectedEnabled) {
            uint256 beforeEpoch = _auth.pairEpochs(address(this), OPERATOR);
            (bool success, ) = address(_auth).call(abi.encodeCall(_auth.approveGrant, (grant)));
            assertFalse(success, "Unavailable Core rejects new authority");
            assertEq(
                _auth.pairEpochs(address(this), OPERATOR),
                beforeEpoch,
                "Failed approval preserves epoch"
            );
            return;
        }
        _auth.approveGrant(grant);
        ++expectedNonce;
        expectedDeadline = type(uint48).max;
    }

    function cancel() external {
        _auth.cancelGrant(OPERATOR);
        ++expectedNonce;
        // The live-only getter hides the cancelled record without deleting permission storage.
        expectedDeadline = 0;
    }

    function _ownerAuthContext()
        internal
        view
        returns (IBurnerLoansCore.AuthorizationContext memory)
    {
        return IBurnerLoansCore.AuthorizationContext(address(_auth), 1, bytes32(0));
    }

    function unauthorizedSettlement() external {
        if (!expectedActive) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                    address(_core)
                )
            );
        } else if (!expectedEnabled) {
            vm.expectRevert(IEnabler.NotEnabled.selector);
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_DEBT_POLICY_ROLE)
            );
        }
        _core.settleBorrow(
            IBurnerLoansCore.BorrowRequest(
                address(0),
                address(0),
                address(0),
                address(0),
                0,
                0,
                0,
                address(0),
                0
            ),
            address(0),
            _ownerAuthContext()
        );
    }
}
// forge-lint: disable-end(unused-return)
