// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {OlympusConvertibleDepository} from "src/modules/CDEPO/OlympusConvertibleDepository.sol";
import {OlympusConvertibleDepositPositionManager} from "src/modules/CDPOS/OlympusConvertibleDepositPositionManager.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {YieldDepositFacility} from "src/policies/YieldDepositFacility.sol";

// solhint-disable max-states-count
contract YieldDepositFacilityTest is Test {
    Kernel public kernel;
    YieldDepositFacility public yieldDepositFacility;
    OlympusRoles public roles;
    OlympusConvertibleDepository public convertibleDepository;
    OlympusConvertibleDepositPositionManager public convertibleDepositPositions;
    OlympusTreasury public treasury;
    RolesAdmin public rolesAdmin;

    MockERC20 public reserveToken;
    MockERC4626 public vault;
    IERC20 internal iReserveToken;
    IERC4626 internal iVault;
    IConvertibleDepositERC20 internal cdToken;

    MockERC20 public reserveTokenTwo;
    MockERC4626 public vaultTwo;
    IERC20 internal iReserveTokenTwo;
    IERC4626 internal iVaultTwo;
    IConvertibleDepositERC20 internal cdTokenTwo;

    address public recipient = address(0x1);
    address public auctioneer = address(0x2);
    address public recipientTwo = address(0x3);
    address public emergency = address(0x4);
    address public admin = address(0xEEEEEE);
    address public heart = address(0x5);

    uint48 public constant INITIAL_BLOCK = 1_000_000;
    uint256 public constant RESERVE_TOKEN_AMOUNT = 10e18;
    uint8 public constant PERIOD_MONTHS = 6;
    uint48 public constant YIELD_EXPIRY = INITIAL_BLOCK + (30 days) * PERIOD_MONTHS;

    uint256 public treasuryReserveBalanceBefore;
    uint256 public cdepoVaultBalanceBefore;
    uint256 public recipientReserveTokenBalanceBefore;

    function setUp() public {
        vm.warp(INITIAL_BLOCK);

        reserveToken = new MockERC20("Reserve Token", "RES", 18);
        iReserveToken = IERC20(address(reserveToken));
        vault = new MockERC4626(reserveToken, "Vault", "VAULT");
        iVault = IERC4626(address(vault));
        vm.label(address(reserveToken), "RES");
        vm.label(address(vault), "sRES");

        reserveTokenTwo = new MockERC20("Reserve Token Two", "RES2", 18);
        iReserveTokenTwo = IERC20(address(reserveTokenTwo));
        vaultTwo = new MockERC4626(reserveTokenTwo, "Vault Two", "VAULT2");
        iVaultTwo = IERC4626(address(vaultTwo));
        vm.label(address(reserveTokenTwo), "RES2");
        vm.label(address(vaultTwo), "sRES2");

        // Instantiate bophades
        _createStack();

        // Deposit into the vault to create a non-equal conversion rate
        reserveToken.mint(address(this), 10e18);
        reserveToken.approve(address(vault), 10e18);
        vault.deposit(10e18, address(this));
        reserveToken.mint(address(vault), 1e18);
        assertTrue(vault.convertToAssets(1e18) != 1e18, "Vault conversion rate is equal to 1");

        // Labels
        vm.label(auctioneer, "auctioneer");
        vm.label(recipient, "recipient");
        vm.label(recipientTwo, "recipientTwo");
        vm.label(emergency, "emergency");
        vm.label(admin, "admin");
        vm.label(heart, "heart");

        // Store the treasury balance before
        _updateReserveBalances();
        _updateCdepoVaultBalance();
    }

    function _createStack() internal {
        kernel = new Kernel();
        roles = new OlympusRoles(kernel);
        convertibleDepository = new OlympusConvertibleDepository(kernel);
        convertibleDepositPositions = new OlympusConvertibleDepositPositionManager(address(kernel));
        treasury = new OlympusTreasury(kernel);
        yieldDepositFacility = new YieldDepositFacility(address(kernel));
        rolesAdmin = new RolesAdmin(kernel);

        // Install modules
        kernel.executeAction(Actions.InstallModule, address(roles));

        kernel.executeAction(Actions.InstallModule, address(convertibleDepository));
        kernel.executeAction(Actions.InstallModule, address(convertibleDepositPositions));
        kernel.executeAction(Actions.InstallModule, address(treasury));
        kernel.executeAction(Actions.ActivatePolicy, address(yieldDepositFacility));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // Grant roles
        rolesAdmin.grantRole(bytes32("emergency"), emergency);
        rolesAdmin.grantRole(bytes32("admin"), admin);
        rolesAdmin.grantRole(bytes32("heart"), heart);

        // Enable the facility
        vm.prank(admin);
        yieldDepositFacility.enable("");

        // Create a CD token
        vm.startPrank(admin);
        cdToken = yieldDepositFacility.create(IERC4626(address(vault)), PERIOD_MONTHS, 90e2);
        vm.stopPrank();
        vm.label(address(cdToken), "cdToken");

        // Create a CD token
        vm.startPrank(admin);
        cdTokenTwo = yieldDepositFacility.create(IERC4626(address(vaultTwo)), PERIOD_MONTHS, 90e2);
        vm.stopPrank();
        vm.label(address(cdTokenTwo), "cdTokenTwo");

        // Disable the facility
        vm.prank(emergency);
        yieldDepositFacility.disable("");
    }

    // ========== MODIFIERS ========== //

    function _updateReserveBalances() internal {
        treasuryReserveBalanceBefore = reserveToken.balanceOf(address(treasury));
        recipientReserveTokenBalanceBefore = reserveToken.balanceOf(recipient);
    }

    function _updateCdepoVaultBalance() internal {
        cdepoVaultBalanceBefore = vault.balanceOf(address(convertibleDepository));
    }

    modifier givenAddressHasReserveToken(address to_, uint256 amount_) {
        reserveToken.mint(to_, amount_);
        _;
    }

    modifier givenReserveTokenSpendingIsApproved(
        address owner_,
        address spender_,
        uint256 amount_
    ) {
        vm.prank(owner_);
        reserveToken.approve(spender_, amount_);
        _;
    }

    modifier mintConvertibleDepositToken(address account_, uint256 amount_) {
        vm.prank(account_);
        convertibleDepository.mint(cdToken, amount_);

        _updateReserveBalances();
        _updateCdepoVaultBalance();
        _;
    }

    function _mintAndApproveReserveToken(address account_, uint256 amount_) internal {
        // Mint the reserve token to the account
        reserveToken.mint(account_, amount_);

        // Approve the reserve token spending
        vm.prank(account_);
        reserveToken.approve(address(convertibleDepository), amount_);
    }

    function _createYieldDepositPosition(
        address account_,
        uint256 amount_
    ) internal returns (uint256 positionId) {
        // Mint the CD token
        vm.prank(account_);
        positionId = yieldDepositFacility.mint(cdToken, amount_, false);

        _updateReserveBalances();
        _updateCdepoVaultBalance();
    }

    modifier givenAddressHasYieldDepositPosition(address account_, uint256 amount_) {
        _mintAndApproveReserveToken(account_, amount_);
        _createYieldDepositPosition(account_, amount_);
        _;
    }

    modifier givenLocallyActive() {
        vm.prank(admin);
        yieldDepositFacility.enable("");
        _;
    }

    modifier givenLocallyInactive() {
        vm.prank(emergency);
        yieldDepositFacility.disable("");
        _;
    }

    modifier givenReserveTokenHasDecimals(uint8 decimals_) {
        reserveToken = new MockERC20("Reserve Token", "RES", decimals_);
        iReserveToken = IERC20(address(reserveToken));
        vault = new MockERC4626(reserveToken, "Vault", "VAULT");

        _createStack();
        _;
    }

    function _getRoundedTimestamp(uint48 timestamp_) internal pure returns (uint48) {
        return (uint48(timestamp_) / 8 hours) * 8 hours;
    }

    function _getRoundedTimestamp() internal view returns (uint48) {
        return _getRoundedTimestamp(uint48(block.timestamp));
    }

    modifier givenWarpForward(uint48 warp_) {
        vm.warp(block.timestamp + warp_);
        _;
    }

    modifier givenBeforeDepositPeriodEnd(uint48 before_) {
        vm.warp(YIELD_EXPIRY - before_);
        _;
    }

    modifier givenDepositPeriodEnded(uint48 elapsed_) {
        vm.warp(YIELD_EXPIRY + elapsed_);
        _;
    }

    function _takeRateSnapshot() internal {
        vm.prank(heart);
        yieldDepositFacility.execute();
    }

    modifier givenRateSnapshotTaken() {
        // Force a snapshot to be taken at the given timestamp
        _takeRateSnapshot();
        _;
    }

    function _accrueYield(IERC4626 vault_, uint256 amount_) internal {
        // Get the vault asset
        MockERC20 asset = MockERC20(vault_.asset());

        // Donate more of the asset into the given vault
        asset.mint(address(vault_), amount_);

        // Update the treasury and CDEPO balances
        _updateReserveBalances();
        _updateCdepoVaultBalance();
    }

    modifier givenVaultAccruesYield(IERC4626 vault_, uint256 amount_) {
        _accrueYield(vault_, amount_);
        _;
    }

    modifier givenYieldFee(uint16 yieldFee_) {
        vm.prank(admin);
        yieldDepositFacility.setYieldFee(yieldFee_);
        _;
    }

    modifier givenHarvest(address account_, uint256 positionId_) {
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId_;

        vm.prank(account_);
        yieldDepositFacility.harvest(positionIds);
        _;
    }

    // ========== ASSERTIONS ========== //

    function _expectRoleRevert(bytes32 role_) internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, role_));
    }

    function _assertHarvestBalances(
        address caller_,
        uint256 positionId_,
        uint256 expectedYield_,
        uint256 expectedFee_,
        uint256 expectedTreasuryBalance_,
        uint256 expectedVaultSharesReduction_,
        uint256 expectedConversionRate_
    ) internal {
        // Assert caller received yield minus fee
        assertEq(
            reserveToken.balanceOf(caller_),
            recipientReserveTokenBalanceBefore + expectedYield_ - expectedFee_,
            "Caller received incorrect yield"
        );

        // Assert treasury received fee
        assertEq(
            reserveToken.balanceOf(address(treasury)),
            treasuryReserveBalanceBefore + expectedTreasuryBalance_,
            "Treasury received incorrect fee"
        );

        // Assert convertibleDepository's vault shares are reduced by the yield amount
        assertEq(
            cdepoVaultBalanceBefore - vault.balanceOf(address(convertibleDepository)),
            expectedVaultSharesReduction_,
            "ConvertibleDepository's vault shares are not reduced by the yield amount"
        );

        // Assert conversion rate is updated
        assertEq(
            yieldDepositFacility.positionLastYieldConversionRate(positionId_),
            expectedConversionRate_,
            "Conversion rate is not updated"
        );
    }
}
