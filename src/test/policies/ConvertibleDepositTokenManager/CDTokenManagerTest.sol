// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";

// Bophades
import {Kernel, Actions} from "src/Kernel.sol";
import {CDTokenManager} from "src/policies/CDTokenManager.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {OlympusConvertibleDepository} from "src/modules/CDEPO/OlympusConvertibleDepository.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";

// Libraries
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";
import {IConvertibleDepositTokenManager} from "src/policies/interfaces/IConvertibleDepositTokenManager.sol";

contract CDTokenManagerTest is Test {
    Kernel public kernel;
    OlympusConvertibleDepository public CDEPO;
    OlympusRoles public ROLES;
    CDTokenManager public cdTokenManager;
    RolesAdmin public rolesAdmin;

    MockERC20 public reserveToken;
    MockERC4626 public vault;
    IERC4626 internal iVault;
    IERC20 internal iReserveToken;
    IConvertibleDepositERC20 internal cdToken;

    address public facility = address(0x1);
    address public emergency = address(0x4);
    address public admin = address(0xEEEEEE);

    uint48 public constant INITIAL_BLOCK = 1_000_000;

    function setUp() public {
        vm.warp(INITIAL_BLOCK);

        reserveToken = new MockERC20("Reserve Token", "RES", 18);
        iReserveToken = IERC20(address(reserveToken));
        vault = new MockERC4626(reserveToken, "Vault", "VAULT");
        iVault = IERC4626(address(vault));
        vm.label(address(reserveToken), "RES");
        vm.label(address(vault), "sRES");

        kernel = new Kernel();
        ROLES = new OlympusRoles(kernel);
        CDEPO = new OlympusConvertibleDepository(kernel);
        cdTokenManager = new CDTokenManager(address(kernel));
        rolesAdmin = new RolesAdmin(kernel);

        // Install modules
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.InstallModule, address(CDEPO));
        kernel.executeAction(Actions.ActivatePolicy, address(cdTokenManager));

        // Grant roles
        rolesAdmin.grantRole(bytes32("emergency"), emergency);
        rolesAdmin.grantRole(bytes32("admin"), admin);
        rolesAdmin.grantRole(bytes32("cd_token_manager"), facility);

        // Enable the CD token manager
        vm.prank(admin);
        cdTokenManager.enable("");

        // Mint reserve tokens and deposit them into the vault
        reserveToken.mint(address(this), 100e18);
        reserveToken.approve(address(this), 100e18);
        vault.deposit(100e18, address(this));

        // Add yield to the vault
        reserveToken.mint(address(vault), 50e18);
        assertTrue(vault.convertToShares(1e18) != 1e18, "Vault yield mismatch");
    }

    // ========== MODIFIERS ========== //

    modifier givenDisabled() {
        vm.prank(admin);
        cdTokenManager.disable("");
        _;
    }

    modifier givenEnabled() {
        vm.prank(admin);
        cdTokenManager.enable("");
        _;
    }

    modifier givenCDTokenCreated(IERC4626 vault_, uint8 periodMonths_) {
        vm.prank(admin);
        cdTokenManager.createToken(vault_, periodMonths_, 90e2);
        _;
    }

    modifier givenFacilityHasReserveToken(uint256 amount_) {
        reserveToken.mint(facility, amount_);
        _;
    }

    modifier givenFacilityHasApprovedReserveTokenSpending(uint256 amount_) {
        vm.prank(facility);
        reserveToken.approve(address(cdTokenManager), amount_);
        _;
    }

    modifier givenFacilityHasCDToken(uint256 amount_) {
        // Mint the reserve tokens to the facility
        reserveToken.mint(facility, amount_);

        // Approve the CD token manager to spend the reserve tokens
        vm.prank(facility);
        reserveToken.approve(address(cdTokenManager), amount_);

        // Create the CD token
        vm.prank(facility);
        cdTokenManager.mint(cdToken, amount_);
        _;
    }

    modifier givenFacilityHasApprovedCDTokenSpending(uint256 amount_) {
        vm.prank(facility);
        cdToken.approve(address(cdTokenManager), amount_);
    }

    // ========== REVERTS ========== //

    function _expectRevertDisabled() internal {
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));
    }

    function _expectRevertNotAdmin() internal {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("admin"))
        );
    }

    function _expectRevertNotCDTokenManagerRole() internal {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("cd_token_manager"))
        );
    }

    function _expectRevertNotCDToken() internal {
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_UnsupportedToken.selector)
        );
    }

    function _expectMissingApproval() internal {
        vm.expectRevert("TRANSFER_FROM_FAILED");
    }

    function _expectRevertInsufficientReserveToken() internal {
        vm.expectRevert("TRANSFER_FROM_FAILED");
    }

    function _expectRevertInsufficientCDToken() internal {
        vm.expectRevert("TRANSFER_FROM_FAILED");
    }

    function _expectRevertArithmeticError() internal {
        vm.expectRevert(stdError.arithmeticError);
    }

    function _expectRevertInsolvent(
        IConvertibleDepositERC20 cdToken_,
        uint256 sharesRequired_,
        uint256 sharesDeposited_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositTokenManager.ConvertibleDepositTokenManager_Insolvent.selector,
                address(cdToken_),
                sharesRequired_,
                sharesDeposited_
            )
        );
    }

    function _expectRevertZeroAmount() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositTokenManager.ConvertibleDepositTokenManager_ZeroAmount.selector
            )
        );
    }

    // ========== ASSERTIONS ========== //

    function _assertCDTokenBalance(IConvertibleDepositERC20 cdToken_, uint256 balance_) internal {
        assertEq(cdToken_.balanceOf(facility), balance_, "CD token balance mismatch");
    }

    function _assertTokenBalance(
        IERC20 token_,
        uint256 balanceBefore_,
        uint256 minted_,
        uint256 burned_
    ) internal {
        assertEq(
            token_.balanceOf(facility),
            balanceBefore_ - minted_ + burned_,
            "Token balance mismatch"
        );
    }

    function _assertCDTokenSupply(IConvertibleDepositERC20 cdToken_, uint256 supply_) internal {
        assertEq(
            cdTokenManager.getTokenSupply(facility, cdToken_),
            supply_,
            "CD token supply mismatch"
        );
    }

    function _assertDepositedShares(IERC4626 vault_, uint256 shares_) internal {
        assertEq(
            cdTokenManager.getDepositedShares(facility, vault_),
            shares_,
            "Deposited shares mismatch"
        );
    }

    function _assertVaultShares(IERC4626 vault_, uint256 shares_) internal {
        assertEq(vault_.balanceOf(facility), shares_, "Vault shares mismatch");
    }
}
