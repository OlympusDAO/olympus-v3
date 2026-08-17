// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";

// Contracts
import {Test} from "forge-std/Test.sol";
import {Actions, Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {BurnerLoansInventory} from "src/policies/BurnerLoansInventory.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_INVENTORY_PROVIDER_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

contract BurnerLoansInventoryPrincipal is Policy {
    address internal immutable _facility;

    constructor(Kernel kernel_, address facility_) Policy(kernel_) {
        _facility = facility_;
    }

    function facility() external view returns (address) {
        return _facility;
    }

    function configureDependencies() external pure override returns (Keycode[] memory) {
        return new Keycode[](0);
    }

    function requestPermissions() external pure override returns (Permissions[] memory) {
        return new Permissions[](0);
    }
}

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
        ohm = new MockOhm("OHM", "OHM", 9);
        mintr = new OlympusMinter(kernel, address(ohm));
        roles = new OlympusRoles(kernel);
        trsry = new OlympusTreasury(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        facility = new BurnerLoansInventoryPrincipal(kernel, address(0));
        config = new BurnerLoansInventoryPrincipal(kernel, address(facility));
        inventory = new BurnerLoansInventory(kernel, IERC20(address(ohm)), address(facility));

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
        inventory.setConfigurator(address(config));
        inventory.enable("");
        vm.stopPrank();
    }

    function _enableAndSetCap(uint128 cap_) internal {
        if (!inventory.isEnabled()) _initializeAndEnable();
        vm.prank(address(config));
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

    function _supply(uint128 amount_) internal {
        ohm.mint(provider, amount_);
        vm.startPrank(provider);
        ohm.approve(address(inventory), amount_);
        inventory.supply(amount_);
        vm.stopPrank();
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
}
