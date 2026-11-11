// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(literal-instead-of-constant,unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {Actions, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

/// @dev Inventory integration helpers keep the shared Core deployment fixture unchanged.
abstract contract BurnerLoansInventoryModularTest is BurnerLoansModularTest {
    function _disableInventory() internal {
        _inventory.disable("");
    }

    function _setPolicyActive(address policy_, bool active_) internal {
        if (_kernel.isPolicyActive(Policy(policy_)) == active_) return;
        _kernel.executeAction(active_ ? Actions.ActivatePolicy : Actions.DeactivatePolicy, policy_);
    }

    function _expectInventoryNotActive() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_inventory)
            )
        );
    }

    function _expectNotAuthorised() internal {
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
    }

    function _expectNotEnabled() internal {
        vm.expectRevert(IEnabler.NotEnabled.selector);
    }

    function _replaceCoreController() internal returns (address replacement_) {
        replacement_ = makeAddr("new Core controller");
        _risk.setConfigOperator(replacement_);
        _core.setConfigOperator(replacement_);
    }

    function _prepareFeeReceiptCallback() internal returns (ReentrantFeeToken token_) {
        token_ = new ReentrantFeeToken();
        _price.setPrice(address(token_), 1e18);
        _admit(address(token_));
        token_.mint(_borrower, 3000e18);
        vm.startPrank(_borrower);
        token_.approve(address(_core), type(uint256).max);
        _collateral.depositCollateral(address(token_), 2000e18, _borrower);
        vm.stopPrank();
        _rolesAdmin.grantRole(ADMIN_ROLE, address(token_));
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(uint256(7), uint256(0))
        );
    }

    function _assertInventoryGovernanceUnchanged() internal view {
        assertEq(_inventory.globalDebtCapOhm(), 100_000e9, "No nested cap change");
        assertEq(_inventory.configOperator(), _inventoryConfigurator, "No nested operator change");
    }

    function _assertCoreCallbackCaught(ReentrantFeeToken token_) internal view {
        _assertInventoryGovernanceUnchanged();
        assertEq(
            token_.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "Authorized nested call reaches Core guard"
        );
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Borrow funded once");
        assertEq(_ohm.balanceOf(_borrower), 100e9, "Borrower paid once");
    }

    function _assertCoreCallbackRolledBack(
        ReentrantFeeToken token_,
        uint256 payerBalance_
    ) internal view {
        _assertInventoryGovernanceUnchanged();
        assertEq(token_.balanceOf(_borrower), payerBalance_, "Earlier incoming fee rolled back");
        assertEq(_inventory.activePrincipalOhm(), 0, "No funding exposure");
        assertEq(_lens.getPosition(address(token_), _borrower).debtOhm, 0, "No loan debt");
    }

    function _expectAdminRole() internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unused-return)
