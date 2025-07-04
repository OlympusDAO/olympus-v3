// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {ConvertibleDepositFacility} from "src/policies/deposits/ConvertibleDepositFacility.sol";
import {YieldDepositFacility} from "src/policies/deposits/YieldDepositFacility.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusDepositPositionManager} from "src/modules/DEPOS/OlympusDepositPositionManager.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositRedemptionVault} from "src/bases/interfaces/IDepositRedemptionVault.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/deposits/IConvertibleDepositFacility.sol";
import {IYieldDepositFacility} from "src/policies/interfaces/deposits/IYieldDepositFacility.sol";
import {ERC6909} from "@openzeppelin-5.3.0/token/ERC6909/draft-ERC6909.sol";

// solhint-disable max-states-count
contract ConvertibleDepositFacilityTest is Test {
    Kernel public kernel;
    ConvertibleDepositFacility public facility;
    YieldDepositFacility public yieldDepositFacility;
    OlympusTreasury public treasury;
    OlympusMinter public minter;
    OlympusRoles public roles;
    OlympusDepositPositionManager public convertibleDepositPositions;
    RolesAdmin public rolesAdmin;
    DepositManager public depositManager;

    MockERC20 public ohm;
    MockERC20 public reserveToken;
    MockERC4626 public vault;
    IERC20 internal iReserveToken;
    IERC4626 internal iVault;
    uint256 public receiptTokenId;

    MockERC20 public reserveTokenTwo;
    MockERC4626 public vaultTwo;
    IERC20 internal iReserveTokenTwo;
    IERC4626 internal iVaultTwo;
    uint256 public receiptTokenIdTwo;

    address public recipient;
    address public auctioneer;
    address public recipientTwo;
    address public emergency;
    address public admin;
    address public HEART;

    uint48 public constant INITIAL_BLOCK = 1_000_000;
    uint256 public constant CONVERSION_PRICE = 2e18;
    uint256 public constant RESERVE_TOKEN_AMOUNT = 10e18;
    uint16 public constant RECLAIM_RATE = 90e2;
    uint8 public constant PERIOD_MONTHS = 6;
    uint48 public constant CONVERSION_EXPIRY = INITIAL_BLOCK + (30 days) * PERIOD_MONTHS;

    function setUp() public {
        vm.warp(INITIAL_BLOCK);

        recipient = makeAddr("RECIPIENT");
        auctioneer = makeAddr("AUCTIONEER");
        recipientTwo = makeAddr("RECIPIENT_TWO");
        emergency = makeAddr("EMERGENCY");
        admin = makeAddr("ADMIN");
        HEART = makeAddr("HEART");

        ohm = new MockERC20("Olympus", "OHM", 9);
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
    }

    function _createStack() internal {
        kernel = new Kernel();
        treasury = new OlympusTreasury(kernel);
        minter = new OlympusMinter(kernel, address(ohm));
        roles = new OlympusRoles(kernel);
        convertibleDepositPositions = new OlympusDepositPositionManager(
            address(kernel),
            address(0)
        );
        depositManager = new DepositManager(address(kernel));
        facility = new ConvertibleDepositFacility(address(kernel), address(depositManager));
        yieldDepositFacility = new YieldDepositFacility(address(kernel), address(depositManager));
        rolesAdmin = new RolesAdmin(kernel);

        // Install modules
        kernel.executeAction(Actions.InstallModule, address(treasury));
        kernel.executeAction(Actions.InstallModule, address(minter));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(convertibleDepositPositions));
        kernel.executeAction(Actions.ActivatePolicy, address(depositManager));
        kernel.executeAction(Actions.ActivatePolicy, address(facility));
        kernel.executeAction(Actions.ActivatePolicy, address(yieldDepositFacility));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // Grant roles
        rolesAdmin.grantRole(bytes32("cd_auctioneer"), auctioneer);
        rolesAdmin.grantRole(bytes32("emergency"), emergency);
        rolesAdmin.grantRole(bytes32("admin"), admin);
        rolesAdmin.grantRole(bytes32("deposit_operator"), address(facility));
        rolesAdmin.grantRole(bytes32("deposit_operator"), address(yieldDepositFacility));
        rolesAdmin.grantRole(bytes32("heart"), HEART);

        // Enable the deposit manager
        vm.prank(admin);
        depositManager.enable("");

        // Enable the facility
        vm.prank(admin);
        facility.enable("");

        // Create a receipt token
        vm.startPrank(admin);
        depositManager.addAsset(
            IERC20(address(reserveToken)),
            IERC4626(address(vault)),
            type(uint256).max
        );

        depositManager.addAssetPeriod(IERC20(address(reserveToken)), PERIOD_MONTHS, 90e2);

        receiptTokenId = depositManager.getReceiptTokenId(
            IERC20(address(reserveToken)),
            PERIOD_MONTHS
        );
        vm.stopPrank();

        // Create a second receipt token
        vm.startPrank(admin);
        depositManager.addAsset(
            IERC20(address(reserveTokenTwo)),
            IERC4626(address(vaultTwo)),
            type(uint256).max
        );

        depositManager.addAssetPeriod(IERC20(address(reserveTokenTwo)), PERIOD_MONTHS, 90e2);

        receiptTokenIdTwo = depositManager.getReceiptTokenId(
            IERC20(address(reserveTokenTwo)),
            PERIOD_MONTHS
        );
        vm.stopPrank();

        // Disable the facility
        vm.prank(emergency);
        facility.disable("");

        // Enable the yield deposit facility
        vm.prank(admin);
        yieldDepositFacility.enable("");
    }

    // ========== MODIFIERS ========== //

    modifier givenAddressHasReserveToken(address to_, uint256 amount_) {
        reserveToken.mint(to_, amount_);
        _;
    }

    modifier givenRecipientHasReserveToken() {
        reserveToken.mint(recipient, RESERVE_TOKEN_AMOUNT);
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

    modifier givenReserveTokenSpendingIsApprovedByRecipient() {
        vm.prank(recipient);
        reserveToken.approve(address(depositManager), RESERVE_TOKEN_AMOUNT);
        _;
    }

    function _createPosition(
        address account_,
        uint256 amount_,
        uint256 conversionPrice_,
        bool wrapPosition_
    ) internal returns (uint256 positionId) {
        return
            _createPosition(
                iReserveToken,
                PERIOD_MONTHS,
                account_,
                amount_,
                conversionPrice_,
                wrapPosition_,
                true
            );
    }

    function _createPosition(
        address account_,
        uint256 amount_,
        uint256 conversionPrice_,
        bool wrapPosition_,
        bool wrapReceipt_
    ) internal returns (uint256 positionId) {
        return
            _createPosition(
                iReserveToken,
                PERIOD_MONTHS,
                account_,
                amount_,
                conversionPrice_,
                wrapPosition_,
                wrapReceipt_
            );
    }

    function _createPosition(
        IERC20 asset_,
        uint8 depositPeriod_,
        address account_,
        uint256 amount_,
        uint256 conversionPrice_,
        bool wrapPosition_,
        bool wrapReceipt_
    ) internal returns (uint256 positionId) {
        vm.prank(auctioneer);
        (positionId, , ) = facility.createPosition(
            IConvertibleDepositFacility.CreatePositionParams({
                asset: asset_,
                periodMonths: depositPeriod_,
                depositor: account_,
                amount: amount_,
                conversionPrice: conversionPrice_,
                wrapPosition: wrapPosition_,
                wrapReceipt: wrapReceipt_
            })
        );
    }

    modifier mintConvertibleDepositToken(address account_, uint256 amount_) {
        vm.prank(account_);
        facility.deposit(iReserveToken, PERIOD_MONTHS, amount_, false);
        _;
    }

    modifier givenAddressHasConvertibleDepositToken(
        address account_,
        IERC20 asset_,
        uint8 depositPeriod_,
        uint256 amount_
    ) {
        // Mint reserve tokens to the account
        MockERC20(address(asset_)).mint(account_, amount_);

        // Approve deposit manager to spend the reserve tokens
        vm.prank(account_);
        asset_.approve(address(depositManager), amount_);

        // Mint the receipt token to the account
        vm.prank(account_);
        facility.deposit(asset_, depositPeriod_, amount_, false);
        _;
    }

    modifier givenAddressHasPosition(address account_, uint256 amount_) {
        _createPosition(account_, amount_, CONVERSION_PRICE, false);
        _;
    }

    modifier givenAddressHasPositionNoWrap(address account_, uint256 amount_) {
        _createPosition(account_, amount_, CONVERSION_PRICE, false, false);
        _;
    }

    function _createYieldDepositPosition(
        address account_,
        uint256 amount_
    ) internal returns (uint256 positionId) {
        vm.prank(account_);
        (positionId, , ) = yieldDepositFacility.createPosition(
            IYieldDepositFacility.CreatePositionParams({
                asset: iReserveToken,
                periodMonths: PERIOD_MONTHS,
                amount: amount_,
                wrapPosition: false,
                wrapReceipt: false
            })
        );
    }

    modifier givenAddressHasYieldDepositPosition(address account_, uint256 amount_) {
        _createYieldDepositPosition(account_, amount_);
        _;
    }

    modifier givenAddressHasDifferentTokenAndPosition(address account_, uint256 amount_) {
        // Mint
        reserveTokenTwo.mint(account_, amount_);

        // Approve
        vm.prank(account_);
        reserveTokenTwo.approve(address(depositManager), amount_);

        // Create position
        _createPosition(
            iReserveTokenTwo,
            PERIOD_MONTHS,
            account_,
            amount_,
            CONVERSION_PRICE,
            false,
            true
        );
        _;
    }

    function _approveWrappedReceiptTokenSpending(
        address owner_,
        address spender_,
        uint256 amount_
    ) internal {
        IERC20 wrappedToken = _getWrappedReceiptToken(iReserveToken, PERIOD_MONTHS);

        vm.prank(owner_);
        wrappedToken.approve(spender_, amount_);
    }

    modifier givenWrappedReceiptTokenSpendingIsApproved(
        address owner_,
        address spender_,
        uint256 amount_
    ) {
        _approveWrappedReceiptTokenSpending(owner_, spender_, amount_);
        _;
    }

    modifier givenReceiptTokenSpendingIsApproved(
        address owner_,
        address spender_,
        uint256 amount_
    ) {
        vm.prank(owner_);
        depositManager.approve(spender_, receiptTokenId, amount_);
        _;
    }

    modifier givenLocallyActive() {
        vm.prank(admin);
        facility.enable("");
        _;
    }

    modifier givenLocallyInactive() {
        vm.prank(emergency);
        facility.disable("");
        _;
    }

    modifier givenReserveTokenHasDecimals(uint8 decimals_) {
        reserveToken = new MockERC20("Reserve Token", "RES", decimals_);
        iReserveToken = IERC20(address(reserveToken));
        vault = new MockERC4626(reserveToken, "Vault", "VAULT");

        _createStack();
        _;
    }

    modifier givenCommitted(address user_, uint256 amount_) {
        // Mint reserve tokens to the user
        reserveToken.mint(user_, amount_);

        // Approve spending of the reserve tokens
        vm.prank(user_);
        reserveToken.approve(address(depositManager), amount_);

        // Mint the receipt token to the user
        vm.prank(user_);
        facility.deposit(iReserveToken, PERIOD_MONTHS, amount_, false);

        // Approve spending of the receipt token
        vm.prank(user_);
        depositManager.approve(address(facility), receiptTokenId, amount_);

        // Commit
        vm.prank(user_);
        facility.startRedemption(iReserveToken, PERIOD_MONTHS, amount_);
        _;
    }

    modifier givenRedeemed(address user_, uint16 redemptionId_) {
        vm.prank(user_);
        facility.finishRedemption(redemptionId_);
        _;
    }

    function _getWrappedReceiptToken(
        IERC20 asset_,
        uint8 depositPeriod_
    ) internal view returns (IERC20) {
        return
            IERC20(
                depositManager.getWrappedToken(
                    depositManager.getReceiptTokenId(asset_, depositPeriod_)
                )
            );
    }

    function _accrueYield(IERC4626 vault_, uint256 amount_) internal {
        // Get the vault asset
        MockERC20 asset = MockERC20(vault_.asset());

        // Donate more of the asset into the given vault
        asset.mint(address(vault_), amount_);
    }

    modifier givenVaultAccruesYield(IERC4626 vault_, uint256 amount_) {
        _accrueYield(vault_, amount_);
        _;
    }

    // ========== ASSERTIONS ========== //

    function _assertMintApproval(uint256 expected_) internal view {
        assertEq(
            minter.mintApproval(address(facility)),
            expected_,
            "minter.mintApproval(address(facility))"
        );
    }

    function _assertReceiptTokenBalance(
        address recipient_,
        uint256 depositAmount_,
        bool isWrapped_
    ) internal view {
        assertEq(
            depositManager.balanceOf(recipient_, receiptTokenId),
            isWrapped_ ? 0 : depositAmount_,
            "receiptToken.balanceOf(recipient)"
        );

        IERC20 wrappedReceiptToken = _getWrappedReceiptToken(iReserveToken, PERIOD_MONTHS);

        if (!isWrapped_) {
            // If the wrapped receipt token is set, make sure the balance is 0
            if (address(wrappedReceiptToken) != address(0)) {
                assertEq(
                    wrappedReceiptToken.balanceOf(recipient_),
                    0,
                    "wrappedReceiptToken.balanceOf(recipient)"
                );
            }
        } else {
            if (address(wrappedReceiptToken) == address(0)) {
                // solhint-disable-next-line gas-custom-errors
                revert("wrappedReceiptToken is not set");
            }

            assertEq(
                wrappedReceiptToken.balanceOf(recipient_),
                isWrapped_ ? depositAmount_ : 0,
                "wrappedReceiptToken.balanceOf(recipient)"
            );
        }
    }

    function _assertAssetBalance(
        uint256 expectedTreasuryBalance_,
        uint256 expectedRecipientBalance_
    ) internal view {
        assertEq(
            reserveToken.balanceOf(address(treasury)),
            expectedTreasuryBalance_,
            "reserveToken.balanceOf(address(treasury))"
        );
        assertEq(
            reserveToken.balanceOf(address(facility)),
            0,
            "reserveToken.balanceOf(address(facility))"
        );
        assertEq(
            reserveToken.balanceOf(recipient),
            expectedRecipientBalance_,
            "reserveToken.balanceOf(recipient)"
        );
    }

    function _assertVaultBalance() internal view {
        assertEq(vault.balanceOf(address(treasury)), 0, "vault.balanceOf(address(treasury))");
        assertEq(vault.balanceOf(address(facility)), 0, "vault.balanceOf(address(facility))");
        assertEq(vault.balanceOf(recipient), 0, "vault.balanceOf(recipient)");
    }

    function _assertAvailableDeposits(uint256 expected_) internal view {
        assertEq(
            facility.getAvailableDeposits(iReserveToken),
            expected_,
            "facility.getAvailableDeposits(iReserveToken)"
        );
    }

    // ========== REVERT HELPERS ========== //

    function _expectRoleRevert(bytes32 role_) internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, role_));
    }

    function _expectRevertNotEnabled() internal {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
    }

    function _expectRevertInvalidConfiguration(IERC20 asset_, uint8 depositPeriod_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_InvalidAssetPeriod.selector,
                address(asset_),
                depositPeriod_
            )
        );
    }

    function _expectRevertDepositNotConfigured(IERC20 asset_, uint8 depositPeriod_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_InvalidToken.selector,
                address(asset_),
                depositPeriod_
            )
        );
    }

    function _expectRevertRedemptionVaultZeroAmount() internal {
        vm.expectRevert(
            abi.encodeWithSelector(IDepositRedemptionVault.RedemptionVault_ZeroAmount.selector)
        );
    }

    function _expectRevertReceiptTokenInsufficientAllowance(
        address spender_,
        uint256 currentAllowance_,
        uint256 amount_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909.ERC6909InsufficientAllowance.selector,
                spender_,
                currentAllowance_,
                amount_,
                depositManager.getReceiptTokenId(iReserveToken, PERIOD_MONTHS)
            )
        );
    }

    function _expectRevertReceiptTokenInsufficientBalance(
        uint256 currentBalance_,
        uint256 amount_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909.ERC6909InsufficientBalance.selector,
                recipient,
                currentBalance_,
                amount_,
                depositManager.getReceiptTokenId(iReserveToken, PERIOD_MONTHS)
            )
        );
    }

    function _expectRevertUnsupported(uint256 positionId_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositFacility.CDF_Unsupported.selector,
                positionId_
            )
        );
    }

    function _expectRevertInsufficientAvailableDeposits(
        uint256 requestedAmount_,
        uint256 availableAmount_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_InsufficientAvailableDeposits.selector,
                requestedAmount_,
                availableAmount_
            )
        );
    }
}
