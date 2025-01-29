// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {CoolerTreasuryBorrower} from "policies/cooler/CoolerTreasuryBorrower.sol";
import {ICoolerTreasuryBorrower} from "policies/interfaces/cooler/ICoolerTreasuryBorrower.sol";

import {Permissions, Keycode, fromKeycode, toKeycode, Kernel, Module, Policy, Actions} from "policies/RolesAdmin.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {ROLESv1, OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract CoolerTreasuryBorrowerTestBase is Test {
    MockERC20 internal usds;
    MockERC4626 internal susds;
    CoolerTreasuryBorrower internal treasuryBorrower;

    Kernel internal kernel;
    OlympusRoles internal ROLES;
    OlympusTreasury internal TRSRY;
    RolesAdmin internal rolesAdmin;

    address internal immutable EXECUTOR = makeAddr("executor");
    address internal immutable TB_ADMIN = makeAddr("tb_admin");
    address internal immutable TB_COOLER = makeAddr("tb_cooler");
    address internal immutable OTHERS = makeAddr("others");
    address internal immutable RECEIVER = makeAddr("receiver");

    uint256 internal constant INITIAL_TRSRY_MINT = 200_000_000e18;

    function setUp() public {
        usds = new MockERC20("usds", "USDS", 18);
        susds = new MockERC4626(usds, "sUSDS", "sUSDS");
        
        kernel = new Kernel();
        ROLES = new OlympusRoles(kernel);
        TRSRY = new OlympusTreasury(kernel);

        treasuryBorrower = new CoolerTreasuryBorrower(
            address(kernel),
            address(susds)
        );

        rolesAdmin = new RolesAdmin(kernel);

        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(treasuryBorrower));

        rolesAdmin.grantRole("treasuryborrower_cooler", TB_COOLER);
        rolesAdmin.grantRole("treasuryborrower_admin", TB_ADMIN);
        kernel.executeAction(Actions.ChangeExecutor, EXECUTOR);

        // Setup Treasury
        usds.mint(address(TRSRY), INITIAL_TRSRY_MINT);
        // Deposit all reserves into the DSR
        vm.startPrank(address(TRSRY));
        usds.approve(address(susds), INITIAL_TRSRY_MINT);
        susds.deposit(INITIAL_TRSRY_MINT, address(TRSRY));
        vm.stopPrank();

        // Fund others so that TRSRY is not the only account with sUSDS shares
        usds.mint(OTHERS, INITIAL_TRSRY_MINT * 33);
        vm.startPrank(OTHERS);
        usds.approve(address(susds), INITIAL_TRSRY_MINT * 33);
        susds.deposit(INITIAL_TRSRY_MINT * 33, OTHERS);
        vm.stopPrank();

        // And update so sUSDS share price is 10% higher
        usds.mint(address(susds), usds.balanceOf(address(susds))/10);
    }

    function test_construction_failDecimalsDebt() public {
        usds = new MockERC20("usds", "USDS", 6);
        susds = new MockERC4626(usds, "sUSDS", "sUSDS");
        vm.expectRevert(abi.encodeWithSelector(ICoolerTreasuryBorrower.InvalidParam.selector));
        treasuryBorrower = new CoolerTreasuryBorrower(
            address(kernel),
            address(susds)
        );
    }

    function test_construction_success() public view {
        assertEq(address(treasuryBorrower.susds()), address(susds));
        assertEq(address(treasuryBorrower.debtToken()), address(usds));
        (ERC20 dToken, uint256 dTokenAmount) = treasuryBorrower.convertToDebtTokenAmount(1e18);
        assertEq(address(dToken), address(usds));
        assertEq(dTokenAmount, 1e18);
        assertEq(address(treasuryBorrower.ROLES()), address(ROLES));
        assertEq(address(treasuryBorrower.TRSRY()), address(TRSRY));
        assertEq(treasuryBorrower.COOLER_ROLE(), bytes32("treasuryborrower_cooler"));
        assertEq(treasuryBorrower.ADMIN_ROLE(), bytes32("treasuryborrower_admin"));
    }

    function test_configureDependencies_success() public {
        Keycode[] memory expectedDeps = new Keycode[](2);
        expectedDeps[0] = toKeycode("ROLES");
        expectedDeps[1] = toKeycode("TRSRY");

        Keycode[] memory deps = treasuryBorrower.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
    }

    function test_configureDependencies_fail() public {
        vm.mockCall(
            address(TRSRY),
            abi.encodeWithSelector(Module.VERSION.selector),
            abi.encode(uint8(2), uint8(1))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Policy.Policy_WrongModuleVersion.selector,
                abi.encode([1, 1])
            )
        );
        treasuryBorrower.configureDependencies();
    }

    function test_requestPermissions() public view {
        Permissions[] memory expectedPerms = new Permissions[](3);
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");
        expectedPerms[0] = Permissions(TRSRY_KEYCODE, TRSRY.setDebt.selector);
        expectedPerms[1] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
        expectedPerms[2] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);

        Permissions[] memory perms = treasuryBorrower.requestPermissions();
        // Check: permission storage
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    function test_access_borrow() public {
        vm.startPrank(OTHERS);
        vm.expectRevert(
            abi.encodeWithSelector(
                ROLESv1.ROLES_RequireRole.selector,
                treasuryBorrower.COOLER_ROLE()
            )
        );
        treasuryBorrower.borrow(123, OTHERS);
    }

    function test_access_repay() public {
        vm.startPrank(OTHERS);
        vm.expectRevert(
            abi.encodeWithSelector(
                ROLESv1.ROLES_RequireRole.selector,
                treasuryBorrower.COOLER_ROLE()
            )
        );
        treasuryBorrower.repay();
    }

    function test_access_setDebt() public {
        vm.startPrank(OTHERS);
        vm.expectRevert(
            abi.encodeWithSelector(
                ROLESv1.ROLES_RequireRole.selector,
                treasuryBorrower.COOLER_ROLE()
            )
        );
        treasuryBorrower.repay();
    }

    function test_borrow_failZeroAmount() public {
        vm.startPrank(TB_COOLER);
        vm.expectRevert(abi.encodeWithSelector(ICoolerTreasuryBorrower.ExpectedNonZero.selector));
        treasuryBorrower.borrow(0, RECEIVER);
    }

    function test_borrow_failZeroReceiver() public {
        vm.startPrank(TB_COOLER);
        vm.expectRevert(abi.encodeWithSelector(ICoolerTreasuryBorrower.InvalidAddress.selector));
        treasuryBorrower.borrow(123, address(0));
    }

    function test_borrow_once() public {
        vm.startPrank(TB_COOLER);

        uint256 borrowedAmount = 110e18;
        uint256 susdsBefore = susds.balanceOf(address(TRSRY));
        treasuryBorrower.borrow(borrowedAmount, RECEIVER);
        uint256 susdsAfter = susds.balanceOf(address(TRSRY));

        assertEq(usds.balanceOf(RECEIVER), borrowedAmount);
        assertEq(TRSRY.reserveDebt(usds, address(treasuryBorrower)), borrowedAmount);
        assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);

        // Treasury has 100 less sUSDS (share price = 1.1)
        assertEq(susdsBefore-susdsAfter, 100e18);
    }

    function test_borrow_twice() public {
        vm.startPrank(TB_COOLER);

        uint256 borrowedAmount = 110e18;

        uint256 susdsBefore = susds.balanceOf(address(TRSRY));
        treasuryBorrower.borrow(borrowedAmount, RECEIVER);

        // Send another 10% higher
        usds.mint(address(susds), usds.balanceOf(address(susds))/10);
        treasuryBorrower.borrow(borrowedAmount, RECEIVER);

        uint256 susdsAfter = susds.balanceOf(address(TRSRY));

        assertEq(usds.balanceOf(RECEIVER), borrowedAmount*2);
        assertEq(TRSRY.reserveDebt(usds, address(treasuryBorrower)), borrowedAmount*2);
        assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);

        // Treasury has 100+90.9 less sUSDS
        assertEq(susdsBefore-susdsAfter, 190.909090909090909091e18);
    }

    function test_repay_failZeroAmount() public {
        vm.startPrank(TB_COOLER);
        vm.expectRevert(abi.encodeWithSelector(ICoolerTreasuryBorrower.ExpectedNonZero.selector));
        treasuryBorrower.repay();
    }

    function test_repay_noDebt() public {
        vm.startPrank(TB_COOLER);
        uint256 susdsBefore = susds.balanceOf(address(TRSRY));
        
        usds.mint(address(treasuryBorrower), 110e18);
        treasuryBorrower.repay();

        assertEq(TRSRY.reserveDebt(usds, address(treasuryBorrower)), 0);
        assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);
        uint256 susdsAfter = susds.balanceOf(address(TRSRY));

        // Treasury has 100 more sUSDS
        assertEq(susdsAfter-susdsBefore, 100e18);
    }

    function test_repay_overRepay() public {
        vm.startPrank(TB_COOLER);
        uint256 susdsBefore = susds.balanceOf(address(TRSRY));

        uint256 borrowedAmount = 110e18;
        uint256 repayAmount = borrowedAmount * 2;
        treasuryBorrower.borrow(borrowedAmount, RECEIVER);
        usds.mint(address(treasuryBorrower), repayAmount);
        treasuryBorrower.repay();

        assertEq(usds.balanceOf(RECEIVER), borrowedAmount);
        assertEq(TRSRY.reserveDebt(usds, address(treasuryBorrower)), 0);
        assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);
        uint256 susdsAfter = susds.balanceOf(address(TRSRY));

        // Treasury has 100 more sUSDS
        assertEq(susdsAfter-susdsBefore, 100e18);
    }

    function test_repay_underRepay() public {
        vm.startPrank(TB_COOLER);
        uint256 susdsBefore = susds.balanceOf(address(TRSRY));

        uint256 borrowedAmount = 110e18;
        uint256 repayAmount = 50e18;
        treasuryBorrower.borrow(borrowedAmount, RECEIVER);
        usds.mint(address(treasuryBorrower), repayAmount);
        treasuryBorrower.repay();

        assertEq(usds.balanceOf(RECEIVER), borrowedAmount);
        assertEq(TRSRY.reserveDebt(usds, address(treasuryBorrower)), borrowedAmount-repayAmount);
        assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);
        uint256 susdsAfter = susds.balanceOf(address(TRSRY));

        assertEq(susdsBefore-susdsAfter, 54.545454545454545455e18);
    }

    function test_setDebt() public {
        vm.startPrank(TB_ADMIN);
        treasuryBorrower.setDebt(333.33e18);
        assertEq(TRSRY.reserveDebt(usds, address(treasuryBorrower)), 333.33e18);
    }
}
