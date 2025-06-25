// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {OlympusDepositPositionManager} from "src/modules/DEPOS/OlympusDepositPositionManager.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {YieldDepositFacility} from "src/policies/YieldDepositFacility.sol";
import {DepositManager} from "src/policies/DepositManager.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {IDepositRedemptionVault} from "src/bases/interfaces/IDepositRedemptionVault.sol";
import {ERC6909} from "@openzeppelin-5.3.0/token/ERC6909/draft-ERC6909.sol";
import {CDFacility} from "src/policies/CDFacility.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IDepositManager} from "src/policies/interfaces/IDepositManager.sol";
import {IYieldDepositFacility} from "src/policies/interfaces/IYieldDepositFacility.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";

// solhint-disable max-states-count
contract YieldDepositFacilityTest is Test {
    Kernel public kernel;
    YieldDepositFacility public yieldDepositFacility;
    OlympusRoles public roles;
    OlympusDepositPositionManager public convertibleDepositPositions;
    OlympusTreasury public treasury;
    OlympusMinter public minter;
    RolesAdmin public rolesAdmin;
    DepositManager public depositManager;
    CDFacility public cdFacility;

    MockERC20 public ohm;

    MockERC20 public reserveToken;
    MockERC4626 public vault;
    IERC20 internal iReserveToken;
    IERC4626 internal iVault;
    uint256 internal _receiptTokenId;

    MockERC20 public reserveTokenTwo;
    MockERC4626 public vaultTwo;
    IERC20 internal iReserveTokenTwo;
    IERC4626 internal iVaultTwo;
    uint256 internal _receiptTokenIdTwo;

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

    uint256 internal _previousDepositActualAmount;

    function setUp() public {
        vm.warp(INITIAL_BLOCK);

        ohm = new MockERC20("OHM", "OHM", 9);

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
        convertibleDepositPositions = new OlympusDepositPositionManager(
            address(kernel),
            address(0)
        );
        treasury = new OlympusTreasury(kernel);
        depositManager = new DepositManager(address(kernel));
        yieldDepositFacility = new YieldDepositFacility(address(kernel), address(depositManager));
        rolesAdmin = new RolesAdmin(kernel);
        cdFacility = new CDFacility(address(kernel), address(depositManager));
        minter = new OlympusMinter(kernel, address(ohm));

        // Install modules
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(convertibleDepositPositions));
        kernel.executeAction(Actions.InstallModule, address(treasury));
        kernel.executeAction(Actions.InstallModule, address(minter));
        kernel.executeAction(Actions.ActivatePolicy, address(depositManager));
        kernel.executeAction(Actions.ActivatePolicy, address(yieldDepositFacility));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(cdFacility));

        // Grant roles
        rolesAdmin.grantRole(bytes32("emergency"), emergency);
        rolesAdmin.grantRole(bytes32("admin"), admin);
        rolesAdmin.grantRole(bytes32("heart"), heart);
        rolesAdmin.grantRole(bytes32("deposit_operator"), address(yieldDepositFacility));
        rolesAdmin.grantRole(bytes32("deposit_operator"), address(cdFacility));
        rolesAdmin.grantRole(bytes32("cd_auctioneer"), auctioneer);

        // Enable the deposit manager
        vm.prank(admin);
        depositManager.enable("");

        // Enable the yield deposit facility
        vm.prank(admin);
        yieldDepositFacility.enable("");

        // Enable the CD facility
        vm.prank(admin);
        cdFacility.enable("");

        // Create a receipt token
        vm.startPrank(admin);
        depositManager.addAsset(iReserveToken, iVault, type(uint256).max);

        depositManager.addAssetPeriod(iReserveToken, PERIOD_MONTHS, 90e2);

        _receiptTokenId = depositManager.getReceiptTokenId(iReserveToken, PERIOD_MONTHS);
        vm.stopPrank();

        // Create a second receipt token
        vm.startPrank(admin);
        depositManager.addAsset(iReserveTokenTwo, iVaultTwo, type(uint256).max);

        depositManager.addAssetPeriod(iReserveTokenTwo, PERIOD_MONTHS, 90e2);

        _receiptTokenIdTwo = depositManager.getReceiptTokenId(iReserveTokenTwo, PERIOD_MONTHS);
        vm.stopPrank();

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
        cdepoVaultBalanceBefore = vault.balanceOf(address(depositManager));
    }

    function _mintToken(IERC20 token_, address to_, uint256 amount_) internal {
        MockERC20(address(token_)).mint(to_, amount_);
    }

    modifier givenAddressHasReserveToken(address to_, uint256 amount_) {
        _mintToken(iReserveToken, to_, amount_);
        _;
    }

    function _approveTokenSpending(
        IERC20 token_,
        address owner_,
        address spender_,
        uint256 amount_
    ) internal {
        vm.prank(owner_);
        token_.approve(spender_, amount_);
    }

    modifier givenReserveTokenSpendingIsApproved(
        address owner_,
        address spender_,
        uint256 amount_
    ) {
        _approveTokenSpending(iReserveToken, owner_, spender_, amount_);
        _;
    }

    modifier mintConvertibleDepositToken(address account_, uint256 amount_) {
        vm.prank(account_);
        (, uint256 actualAmount) = yieldDepositFacility.deposit(
            iReserveToken,
            PERIOD_MONTHS,
            amount_,
            false
        );
        _previousDepositActualAmount = actualAmount;

        _updateReserveBalances();
        _updateCdepoVaultBalance();
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

        // Approve DepositManager to spend the reserve tokens
        vm.prank(account_);
        asset_.approve(address(depositManager), amount_);

        // Mint the receipt token to the account
        vm.prank(account_);
        (, uint256 actualAmount) = yieldDepositFacility.deposit(
            asset_,
            depositPeriod_,
            amount_,
            false
        );
        _previousDepositActualAmount = actualAmount;
        _;
    }

    function _mintAndApproveReserveToken(address account_, uint256 amount_) internal {
        // Mint the reserve token to the account
        reserveToken.mint(account_, amount_);

        // Approve the reserve token spending
        vm.prank(account_);
        reserveToken.approve(address(depositManager), amount_);
    }

    function _createYieldDepositPosition(
        address account_,
        uint256 amount_
    )
        internal
        returns (uint256 actualPositionId, uint256 actualReceiptTokenId, uint256 actualAmount)
    {
        // Mint the receipt token
        vm.prank(account_);
        (actualPositionId, actualReceiptTokenId, actualAmount) = yieldDepositFacility
            .createPosition(
                IYieldDepositFacility.CreatePositionParams({
                    asset: iReserveToken,
                    periodMonths: PERIOD_MONTHS,
                    amount: amount_,
                    wrapPosition: false,
                    wrapReceipt: false
                })
            );

        _updateReserveBalances();
        _updateCdepoVaultBalance();

        return (actualPositionId, actualReceiptTokenId, actualAmount);
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
        iVault = IERC4626(address(vault));

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

        // Update the treasury and DepositManager balances
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
        yieldDepositFacility.claimYield(positionIds);
        _;
    }

    modifier givenConvertibleDepositTokenSpendingIsApproved(
        address owner_,
        address spender_,
        uint256 amount_
    ) {
        vm.prank(owner_);
        depositManager.approve(spender_, _receiptTokenId, amount_);
        _;
    }

    modifier givenCommitted(
        address user_,
        IERC20 asset_,
        uint8 depositPeriod_,
        uint256 amount_
    ) {
        // Mint reserve tokens to the user
        MockERC20(address(asset_)).mint(user_, amount_);

        // Approve spending of the reserve tokens
        vm.prank(user_);
        asset_.approve(address(depositManager), amount_);

        // Mint the receipt token to the user
        vm.prank(user_);
        (, uint256 actualAmount) = yieldDepositFacility.deposit(
            asset_,
            depositPeriod_,
            amount_,
            false
        );
        _previousDepositActualAmount = actualAmount;

        // Approve spending of the receipt token
        vm.prank(user_);
        depositManager.approve(address(yieldDepositFacility), _receiptTokenId, actualAmount);

        // Commit
        vm.prank(user_);
        yieldDepositFacility.commitRedeem(asset_, depositPeriod_, actualAmount);
        _;
    }

    modifier givenRedeemed(address user_, uint16 commitmentId_) {
        // Adjust the amount of yield in the vault to avoid a rounding error
        // NOTE: This is an issue with how DepositManager tracks deposited funds. It is likely to be fixed when funds custodying is shifted to the policy.
        reserveToken.mint(address(vault), 1e18);

        vm.prank(user_);
        yieldDepositFacility.redeem(commitmentId_);
        _;
    }

    function _createConvertibleDepositPosition(
        address account_,
        uint256 amount_,
        uint256 conversionPrice_
    ) internal returns (uint256 positionId) {
        vm.prank(auctioneer);
        (positionId, , ) = cdFacility.createPosition(
            IConvertibleDepositFacility.CreatePositionParams({
                asset: iReserveToken,
                periodMonths: PERIOD_MONTHS,
                depositor: account_,
                amount: amount_,
                conversionPrice: conversionPrice_,
                wrapPosition: false,
                wrapReceipt: false
            })
        );
    }

    modifier givenAddressHasConvertibleDepositPosition(
        address account_,
        uint256 amount_,
        uint256 conversionPrice_
    ) {
        _createConvertibleDepositPosition(account_, amount_, conversionPrice_);
        _;
    }

    // ========== ASSERTIONS ========== //

    function _assertHarvestBalances(
        address caller_,
        uint256 positionId_,
        uint256 expectedYield_,
        uint256 expectedFee_,
        uint256 expectedTreasuryBalance_,
        uint256 expectedVaultSharesReduction_,
        uint256 expectedConversionRate_
    ) internal view {
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

        // Assert DepositManager's vault shares are reduced by the yield amount
        assertEq(
            cdepoVaultBalanceBefore - vault.balanceOf(address(depositManager)),
            expectedVaultSharesReduction_,
            "DepositManager's vault shares are not reduced by the yield amount"
        );

        // Assert conversion rate is updated
        assertEq(
            yieldDepositFacility.positionLastYieldConversionRate(positionId_),
            expectedConversionRate_,
            "Conversion rate is not updated"
        );
    }

    function _assertReserveTokenBalance(uint256 amount_) internal view {
        assertEq(reserveToken.balanceOf(recipient), amount_, "reserveToken.balanceOf(recipient)");
    }

    function _assertReceiptTokenBalance(
        address recipient_,
        uint256 depositAmount_,
        bool isWrapped_
    ) internal view {
        assertEq(
            depositManager.balanceOf(recipient_, _receiptTokenId),
            isWrapped_ ? 0 : depositAmount_,
            "receiptToken.balanceOf(recipient)"
        );

        IERC20 wrappedReceiptToken = IERC20(depositManager.getWrappedToken(_receiptTokenId));

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

    // ========== REVERT HELPERS ========== //

    function _expectRevertNotEnabled() internal {
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));
    }

    function _expectRoleRevert(bytes32 role_) internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, role_));
    }

    function _expectRevertRedemptionVaultInvalidToken(
        IERC20 asset_,
        uint8 depositPeriod_
    ) internal {
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

    function _expectRevertDepositManagerInvalidConfiguration(
        IERC20 asset_,
        uint8 periodMonths_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_InvalidAssetPeriod.selector,
                address(asset_),
                periodMonths_
            )
        );
    }

    function _expectRevertInvalidToken(IERC20 asset_, uint8 periodMonths_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldDepositFacility.YDF_InvalidToken.selector,
                address(asset_),
                periodMonths_
            )
        );
    }

    function _expectRevertUnsupported(uint256 positionId_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(IYieldDepositFacility.YDF_Unsupported.selector, positionId_)
        );
    }
}
