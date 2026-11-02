// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,missing-zero-check,unused-return)

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_INVENTORY_PROVIDER_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Test} from "forge-std/Test.sol";
import {Actions, Kernel, Policy} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {BurnerLoansInventory} from "src/policies/burnerloans/BurnerLoansInventory.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {BurnerLoansInventoryPrincipal} from "src/test/policies/BurnerLoansInventory/BurnerLoansInventoryPrincipal.sol";

// Test actions assert their effects directly; return values are intentionally unused.
// Test fixtures accept zero addresses to model unset, cleared, and invalid states.

abstract contract BurnerLoansInventoryTest is Test {
    uint128 internal constant DEFAULT_CAP = 1_000_000e9;

    address internal admin;
    address internal burnerLoansAdmin;
    address internal emergency;
    address internal provider;
    address internal recipient;
    address internal outsider;

    Kernel internal kernel;
    MockOhm internal ohm;
    OlympusMinter internal mintr;
    OlympusRoles internal roles;
    OlympusTreasury internal trsry;
    RolesAdmin internal rolesAdmin;
    BurnerLoansInventoryPrincipal internal config;
    BurnerLoansInventoryPrincipal internal facility;
    BurnerLoansInventory internal inventory;

    function setUp() public virtual {
        admin = makeAddr("admin");
        burnerLoansAdmin = makeAddr("burnerLoansAdmin");
        emergency = makeAddr("emergency");
        provider = makeAddr("provider");
        recipient = makeAddr("recipient");
        outsider = makeAddr("outsider");

        vm.startPrank(admin);
        kernel = new Kernel();
        ohm = _deployOhm();
        mintr = new OlympusMinter(kernel, address(ohm));
        roles = new OlympusRoles(kernel);
        trsry = new OlympusTreasury(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        facility = new BurnerLoansInventoryPrincipal(kernel, address(0));
        config = new BurnerLoansInventoryPrincipal(kernel, address(facility));
        inventory = new BurnerLoansInventory(kernel, IERC20(address(ohm)), address(facility));
        vm.label(address(kernel), "Kernel");
        vm.label(address(ohm), "OHM");
        vm.label(address(mintr), "MINTR");
        vm.label(address(roles), "ROLES");
        vm.label(address(trsry), "TRSRY");
        vm.label(address(rolesAdmin), "Roles admin");
        vm.label(address(facility), "Burner Loans facility fixture");
        vm.label(address(config), "Burner Loans config fixture");
        vm.label(address(inventory), "Burner Loans inventory");

        kernel.executeAction(Actions.InstallModule, address(mintr));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(trsry));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(config));
        kernel.executeAction(Actions.ActivatePolicy, address(facility));
        kernel.executeAction(Actions.ActivatePolicy, address(inventory));

        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(EMERGENCY_ROLE, emergency);
        rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, burnerLoansAdmin);
        rolesAdmin.grantRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE, provider);
        vm.stopPrank();
    }

    function _initializeAndEnable() internal {
        vm.startPrank(admin);
        if (inventory.configOperator() != address(config))
            inventory.setConfigOperator(address(config));
        if (!inventory.isEnabled()) inventory.enable("");
        vm.stopPrank();
    }

    function _deployOhm() internal virtual returns (MockOhm) {
        return new MockOhm("OHM", "OHM", 9);
    }

    function _enableAndSetCap(uint128 cap_) internal {
        if (!inventory.isEnabled()) _initializeAndEnable();
        vm.prank(admin);
        inventory.setGlobalDebtCap(cap_);
    }

    function _assertInventoryState(
        address balanceAccount_,
        uint256 expectedBalance_,
        uint256 expectedActivePrincipal_,
        uint256 expectedSuppliedOhm_,
        uint256 expectedSuppliedIdleOhm_,
        uint256 expectedMintApproval_
    ) internal view {
        assertEq(ohm.balanceOf(balanceAccount_), expectedBalance_, "OHM balance");
        assertEq(inventory.activePrincipalOhm(), expectedActivePrincipal_, "active principal");
        assertEq(inventory.suppliedOhm(), expectedSuppliedOhm_, "supplied OHM");
        assertEq(inventory.suppliedIdleOhm(), expectedSuppliedIdleOhm_, "supplied idle OHM");
        assertEq(mintr.mintApproval(address(inventory)), expectedMintApproval_, "MINTR approval");
        _assertInventoryInvariant();
    }

    function _prepareSupply(uint128 amount_) internal {
        ohm.mint(provider, amount_);
        vm.prank(provider);
        ohm.approve(address(inventory), amount_);
    }

    function _supply(uint128 amount_) internal {
        _prepareSupply(amount_);
        vm.prank(provider);
        inventory.supply(amount_);
    }

    function _draw(uint128 amount_) internal {
        vm.prank(address(facility));
        inventory.draw(recipient, amount_);
    }

    function _transferRepayment(uint128 amount_) internal {
        ohm.mint(address(inventory), amount_);
    }

    function _assertInventoryInvariant() internal view {
        uint256 active = inventory.activePrincipalOhm();
        uint256 cap = inventory.globalDebtCapOhm();
        uint256 idle = inventory.suppliedIdleOhm();
        uint256 claim = inventory.suppliedOhm();
        uint256 approval = mintr.mintApproval(address(inventory));
        uint256 desired = cap > active + idle ? cap - active - idle : 0;
        assertLe(active, cap, "active principal exceeds cap");
        assertLe(approval, desired, "mint approval exceeds desired approval");
        assertLe(idle, ohm.balanceOf(address(inventory)), "idle exceeds raw balance");
        assertLe(idle, claim, "idle exceeds provider claim");

        uint256 capRoom = cap > active ? cap - active : 0;
        uint256 requiredApproval = idle >= capRoom ? 0 : capRoom - idle;
        uint256 expectedCapacity = idle >= capRoom || approval >= requiredApproval
            ? capRoom
            : idle + approval;
        assertEq(inventory.availableCapacity(), expectedCapacity, "available capacity");
    }

    /// @dev Compare authoritative accounting and token state across failed calls and lifecycle
    /// transitions. Excludes lifecycle/configuration fields that those actions intentionally change.
    function _accountingState() internal view returns (bytes32) {
        bytes32 accounting = keccak256(
            abi.encode(
                inventory.activePrincipalOhm(),
                inventory.suppliedOhm(),
                inventory.suppliedIdleOhm(),
                inventory.providerClaimOhm(provider),
                inventory.providerClaimOhm(outsider)
            )
        );
        bytes32 balances = keccak256(
            abi.encode(
                ohm.balanceOf(address(inventory)),
                ohm.balanceOf(provider),
                ohm.balanceOf(recipient),
                ohm.balanceOf(address(trsry)),
                ohm.totalSupply()
            )
        );
        return
            keccak256(
                abi.encode(
                    accounting,
                    balances,
                    ohm.allowance(provider, address(inventory)),
                    ohm.allowance(address(inventory), address(mintr)),
                    mintr.mintApproval(address(inventory))
                )
            );
    }

    function _deactivateInventory() internal {
        _setPolicyActive(address(inventory), false);
    }

    function _reactivateInventory() internal {
        _setPolicyActive(address(inventory), true);
    }

    function _newInventory() internal returns (BurnerLoansInventory) {
        return new BurnerLoansInventory(kernel, IERC20(address(ohm)), address(facility));
    }

    /// @dev Fuzz independent exclusive and overlapping role classes without inheriting fixture roles.
    function _grantTransitionCaller(address caller_, uint8 roleSeed_, bytes32 otherRole_) internal {
        vm.assume(
            caller_ != address(0) &&
                caller_ != admin &&
                caller_ != emergency &&
                caller_ != burnerLoansAdmin
        );
        uint256 roleClass = uint256(roleSeed_) % 3;
        vm.startPrank(admin);
        if (roleClass == 1 && roles.hasRole(caller_, ADMIN_ROLE))
            rolesAdmin.revokeRole(ADMIN_ROLE, caller_);
        if (roleClass == 0 && roles.hasRole(caller_, otherRole_))
            rolesAdmin.revokeRole(otherRole_, caller_);
        if (roleClass != 1 && !roles.hasRole(caller_, ADMIN_ROLE))
            rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (roleClass != 0 && !roles.hasRole(caller_, otherRole_))
            rolesAdmin.grantRole(otherRole_, caller_);
        vm.stopPrank();
    }

    function _setPolicyActive(address policy_, bool active_) internal {
        if (kernel.isPolicyActive(Policy(policy_)) == active_) return;
        vm.prank(admin);
        kernel.executeAction(active_ ? Actions.ActivatePolicy : Actions.DeactivatePolicy, policy_);
    }

    function _givenInitialLifecycle(bool active_, bool enabled_) internal {
        if (enabled_) _enableInventory();
        _setPolicyActive(address(inventory), active_);
    }

    function _disableInventory() internal {
        vm.prank(emergency);
        inventory.disable("");
    }

    function _reEnableInventory() internal {
        vm.prank(burnerLoansAdmin);
        inventory.reEnable();
    }

    function _mockFacilityEnabled(bool enabled_) internal {
        vm.mockCall(
            address(facility),
            abi.encodeWithSignature("isEnabled()"),
            abi.encode(enabled_)
        );
    }

    function _mockFacilityKernel(address kernel_) internal {
        vm.mockCall(address(facility), abi.encodeWithSignature("kernel()"), abi.encode(kernel_));
    }

    function _mockFacilityKernelRevert(bytes memory failure_) internal {
        vm.mockCallRevert(address(facility), abi.encodeWithSignature("kernel()"), failure_);
    }

    function _grantAdminRole(address caller_) internal {
        if (roles.hasRole(caller_, ADMIN_ROLE)) return;
        vm.prank(admin);
        rolesAdmin.grantRole(ADMIN_ROLE, caller_);
    }

    function _expectInventoryNotActive() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(inventory)
            )
        );
    }

    function _expectNotAuthorised() internal {
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
    }

    function _expectNotEnabled() internal {
        vm.expectRevert(IEnabler.NotEnabled.selector);
    }

    function _expectAdminRole() internal {
        _expectRole(ADMIN_ROLE);
    }

    function _enableInventory() internal {
        vm.prank(admin);
        inventory.enable("");
    }

    function _expectRole(bytes32 role_) internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, role_));
    }

    function _expectInvalidCore(address core_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidCore.selector,
                core_
            )
        );
    }
}

// forge-lint: disable-end(calls-loop,missing-zero-check,unused-return)
