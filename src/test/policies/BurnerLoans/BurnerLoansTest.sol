// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(unwrapped-modifier-logic)
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {Actions, Kernel} from "src/Kernel.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockDepositManager} from "src/test/mocks/MockDepositManager.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";
import {BurnerLoansHarness} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarness.sol";

abstract contract BurnerLoansTest is Test {
    address internal admin;
    address internal emergency;
    address internal alice;
    address internal unauthorized;

    Kernel internal kernel;
    OlympusMinter internal mintr;
    OlympusRoles internal roles;
    OlympusTreasury internal trsry;
    RolesAdmin internal rolesAdmin;
    MockPrice internal price;
    MockOhm internal ohm;
    MockERC20 internal usds;
    MockDepositManager internal depositManager;
    BurnerLoansHarness internal burnerLoans;

    uint8 internal constant OHM_DECIMALS = 9;
    uint8 internal constant USDS_DECIMALS = 6;
    uint8 internal constant PRICE_DECIMALS = 18;

    function setUp() public virtual {
        admin = makeAddr("admin");
        emergency = makeAddr("emergency");
        alice = makeAddr("alice");
        unauthorized = makeAddr("unauthorized");

        vm.startPrank(admin);

        kernel = new Kernel();
        ohm = new MockOhm("OHM", "OHM", OHM_DECIMALS);
        usds = new MockERC20("USDS", "USDS", USDS_DECIMALS);
        mintr = new OlympusMinter(kernel, address(ohm));
        roles = new OlympusRoles(kernel);
        trsry = new OlympusTreasury(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        price = new MockPrice(kernel, PRICE_DECIMALS, uint32(8 hours));
        depositManager = new MockDepositManager(kernel, address(usds));
        burnerLoans = new BurnerLoansHarness(kernel, IERC20(address(ohm)), depositManager);

        kernel.executeAction(Actions.InstallModule, address(mintr));
        kernel.executeAction(Actions.InstallModule, address(price));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(trsry));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(burnerLoans));

        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(EMERGENCY_ROLE, emergency);

        vm.stopPrank();
    }

    function _defaultFeeConfig() internal pure returns (IBurnerLoans.FeeConfig memory) {
        return
            IBurnerLoans.FeeConfig({
                baseFeeBps: 25,
                kinkBps: 8_000,
                slope1Bps: 100,
                slope2Bps: 900
            });
    }
}
/// forge-lint: disable-end(unwrapped-modifier-logic)
