// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {DepositRedemptionVault} from "src/policies/deposits/DepositRedemptionVault.sol";
import {ConvertibleDepositFacility} from "src/policies/deposits/ConvertibleDepositFacility.sol";
import {YieldDepositFacility} from "src/policies/deposits/YieldDepositFacility.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusDepositPositionManager} from "src/modules/DEPOS/OlympusDepositPositionManager.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/deposits/IConvertibleDepositFacility.sol";
import {IYieldDepositFacility} from "src/policies/interfaces/deposits/IYieldDepositFacility.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";
import {ERC6909} from "@openzeppelin-5.3.0/token/ERC6909/draft-ERC6909.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// solhint-disable max-states-count
contract DepositRedemptionVaultTest is Test {
    Kernel public kernel;
    DepositRedemptionVault public redemptionVault;
    ConvertibleDepositFacility public cdFacility;
    YieldDepositFacility public ydFacility;
    OlympusTreasury public treasury;
    OlympusMinter public minter;
    OlympusRoles public roles;
    OlympusDepositPositionManager public convertibleDepositPositions;
    RolesAdmin public rolesAdmin;
    DepositManager public depositManager;
    ReceiptTokenManager public receiptTokenManager;

    address public cdFacilityAddress;
    address public ydFacilityAddress;

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
    address public manager;
    address public defaultRewardClaimer;

    uint48 public constant INITIAL_BLOCK = 1_000_000;
    uint256 public constant CONVERSION_PRICE = 2e18;
    uint256 public constant RESERVE_TOKEN_AMOUNT = 10e18;
    uint16 public constant RECLAIM_RATE = 90e2;
    uint8 public constant PERIOD_MONTHS = 6;
    uint48 public constant YIELD_EXPIRY = INITIAL_BLOCK + (30 days) * PERIOD_MONTHS;
    uint48 public constant CONVERSION_EXPIRY = INITIAL_BLOCK + (30 days) * PERIOD_MONTHS;
    uint256 public constant COMMITMENT_AMOUNT = 1e18;

    uint16 public constant ANNUAL_INTEREST_RATE = 10e2;
    uint16 public constant MAX_BORROW_PERCENTAGE = 90e2;
    uint256 public constant LOAN_AMOUNT = (COMMITMENT_AMOUNT * 90e2) / 100e2;

    uint256 internal _previousDepositActualAmount;

    function setUp() public virtual {
        vm.warp(INITIAL_BLOCK);

        recipient = makeAddr("RECIPIENT");
        auctioneer = makeAddr("AUCTIONEER");
        recipientTwo = makeAddr("RECIPIENT_TWO");
        emergency = makeAddr("EMERGENCY");
        admin = makeAddr("ADMIN");
        HEART = makeAddr("HEART");
        manager = makeAddr("MANAGER");
        defaultRewardClaimer = makeAddr("DEFAULT_REWARD_CLAIMER");

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
        receiptTokenManager = new ReceiptTokenManager();
        depositManager = new DepositManager(address(kernel), address(receiptTokenManager));
        redemptionVault = new DepositRedemptionVault(address(kernel), address(depositManager));
        cdFacility = new ConvertibleDepositFacility(address(kernel), address(depositManager));
        cdFacilityAddress = address(cdFacility);
        ydFacility = new YieldDepositFacility(address(kernel), address(depositManager));
        ydFacilityAddress = address(ydFacility);
        rolesAdmin = new RolesAdmin(kernel);

        // Install modules
        kernel.executeAction(Actions.InstallModule, address(treasury));
        kernel.executeAction(Actions.InstallModule, address(minter));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(convertibleDepositPositions));
        kernel.executeAction(Actions.ActivatePolicy, address(depositManager));
        kernel.executeAction(Actions.ActivatePolicy, address(redemptionVault));
        kernel.executeAction(Actions.ActivatePolicy, address(cdFacility));
        kernel.executeAction(Actions.ActivatePolicy, address(ydFacility));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // Grant roles
        rolesAdmin.grantRole(bytes32("cd_auctioneer"), auctioneer);
        rolesAdmin.grantRole(bytes32("emergency"), emergency);
        rolesAdmin.grantRole(bytes32("admin"), admin);
        rolesAdmin.grantRole(bytes32("deposit_operator"), address(cdFacility));
        rolesAdmin.grantRole(bytes32("deposit_operator"), address(ydFacility));
        rolesAdmin.grantRole(bytes32("heart"), HEART);
        rolesAdmin.grantRole(bytes32("manager"), manager);

        // Enable the deposit manager
        vm.prank(admin);
        depositManager.enable("");

        // Enable the redemption vault
        vm.prank(admin);
        redemptionVault.enable("");

        // Enable the facilities
        vm.prank(admin);
        cdFacility.enable("");

        vm.prank(admin);
        ydFacility.enable("");

        // Register facilities in redemption vault
        vm.prank(admin);
        redemptionVault.authorizeFacility(address(cdFacility));

        vm.prank(admin);
        redemptionVault.authorizeFacility(address(ydFacility));

        // Create receipt tokens
        vm.startPrank(admin);

        // Set the facility names
        depositManager.setOperatorName(address(cdFacility), "cdf");
        depositManager.setOperatorName(address(ydFacility), "ydf");

        depositManager.addAsset(
            IERC20(address(reserveToken)),
            IERC4626(address(vault)),
            type(uint256).max,
            0
        );

        // Enable the token/period/facility combo
        depositManager.addAssetPeriod(
            IERC20(address(reserveToken)),
            PERIOD_MONTHS,
            address(cdFacility),
            90e2
        );

        // Enable the token/period/facility combo for the YieldDepositFacility
        depositManager.addAssetPeriod(
            IERC20(address(reserveToken)),
            PERIOD_MONTHS,
            address(ydFacility),
            90e2
        );

        receiptTokenId = depositManager.getReceiptTokenId(
            IERC20(address(reserveToken)),
            PERIOD_MONTHS,
            address(cdFacility)
        );
        vm.stopPrank();

        // Create a second receipt token
        vm.startPrank(admin);
        depositManager.addAsset(
            IERC20(address(reserveTokenTwo)),
            IERC4626(address(vaultTwo)),
            type(uint256).max,
            0
        );

        // Enable the token/period/facility combo
        depositManager.addAssetPeriod(
            IERC20(address(reserveTokenTwo)),
            PERIOD_MONTHS,
            address(cdFacility),
            90e2
        );

        // Enable the token/period/facility combo for the YieldDepositFacility
        depositManager.addAssetPeriod(
            IERC20(address(reserveTokenTwo)),
            PERIOD_MONTHS,
            address(ydFacility),
            90e2
        );

        receiptTokenIdTwo = depositManager.getReceiptTokenId(
            IERC20(address(reserveTokenTwo)),
            PERIOD_MONTHS,
            address(cdFacility)
        );
        vm.stopPrank();

        // Authorize the redemption vault to interact with CD Facility
        vm.prank(admin);
        cdFacility.authorizeOperator(address(redemptionVault));

        // Set the annual interest rate
        vm.prank(admin);
        redemptionVault.setAnnualInterestRate(
            iReserveToken,
            address(cdFacility),
            ANNUAL_INTEREST_RATE
        );

        // Set the max borrow percentage
        vm.prank(admin);
        redemptionVault.setMaxBorrowPercentage(
            iReserveToken,
            address(cdFacility),
            MAX_BORROW_PERCENTAGE
        );

        // Disable the redemption vault
        vm.prank(admin);
        redemptionVault.disable("");
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
        vm.startPrank(recipient);
        reserveToken.approve(address(depositManager), RESERVE_TOKEN_AMOUNT);
        vm.stopPrank();
        _;
    }

    modifier givenReserveTokenSpendingByRedemptionVaultIsApprovedByRecipient() {
        vm.startPrank(recipient);
        reserveToken.approve(address(redemptionVault), RESERVE_TOKEN_AMOUNT);
        vm.stopPrank();
        _;
    }

    function _createCDPosition(
        address account_,
        uint256 amount_,
        uint256 conversionPrice_,
        bool wrapPosition_
    ) internal returns (uint256 positionId) {
        return
            _createCDPosition(
                iReserveToken,
                PERIOD_MONTHS,
                account_,
                amount_,
                conversionPrice_,
                wrapPosition_,
                true
            );
    }

    function _createCDPosition(
        address account_,
        uint256 amount_,
        uint256 conversionPrice_,
        bool wrapPosition_,
        bool wrapReceipt_
    ) internal returns (uint256 positionId) {
        return
            _createCDPosition(
                iReserveToken,
                PERIOD_MONTHS,
                account_,
                amount_,
                conversionPrice_,
                wrapPosition_,
                wrapReceipt_
            );
    }

    function _createCDPosition(
        IERC20 asset_,
        uint8 depositPeriod_,
        address account_,
        uint256 amount_,
        uint256 conversionPrice_,
        bool wrapPosition_,
        bool wrapReceipt_
    ) internal returns (uint256 positionId) {
        vm.prank(auctioneer);
        (positionId, , ) = cdFacility.createPosition(
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
        (, uint256 actualAmount) = cdFacility.deposit(iReserveToken, PERIOD_MONTHS, amount_, false);

        _previousDepositActualAmount = actualAmount;
        _;
    }

    function _createDeposit(
        address account_,
        IERC20 asset_,
        uint8 depositPeriod_,
        uint256 amount_
    ) internal returns (uint256) {
        // Mint reserve tokens to the account
        MockERC20(address(asset_)).mint(account_, amount_);

        // Approve deposit manager to spend the reserve tokens
        vm.startPrank(account_);
        asset_.approve(address(depositManager), amount_);
        vm.stopPrank();

        // Mint the receipt token to the account
        vm.prank(account_);
        (, uint256 actualAmount) = cdFacility.deposit(asset_, depositPeriod_, amount_, false);

        _previousDepositActualAmount = actualAmount;

        return actualAmount;
    }

    modifier givenAddressHasConvertibleDepositToken(
        address account_,
        IERC20 asset_,
        uint8 depositPeriod_,
        uint256 amount_
    ) {
        _createDeposit(account_, asset_, depositPeriod_, amount_);
        _;
    }

    modifier givenAddressHasConvertibleDepositTokenDefault(uint256 amount_) {
        _createDeposit(recipient, iReserveToken, PERIOD_MONTHS, amount_);
        _;
    }

    modifier givenAddressHasPosition(address account_, uint256 amount_) {
        _createCDPosition(account_, amount_, CONVERSION_PRICE, false);
        _;
    }

    modifier givenAddressHasPositionNoWrap(address account_, uint256 amount_) {
        _createCDPosition(account_, amount_, CONVERSION_PRICE, false, false);
        _;
    }

    function _createYDPosition(
        address account_,
        uint256 amount_
    ) internal returns (uint256 positionId) {
        uint256 actualAmount;

        vm.prank(account_);
        (positionId, , actualAmount) = ydFacility.createPosition(
            IYieldDepositFacility.CreatePositionParams({
                asset: iReserveToken,
                periodMonths: PERIOD_MONTHS,
                amount: amount_,
                wrapPosition: false,
                wrapReceipt: false
            })
        );

        _previousDepositActualAmount = actualAmount;
    }

    modifier givenAddressHasYieldDepositPosition(address account_, uint256 amount_) {
        _createYDPosition(account_, amount_);
        _;
    }

    modifier givenAddressHasDifferentTokenAndPosition(address account_, uint256 amount_) {
        // Mint
        reserveTokenTwo.mint(account_, amount_);

        // Approve
        vm.startPrank(account_);
        reserveTokenTwo.approve(address(depositManager), amount_);
        vm.stopPrank();

        // Create position
        _createCDPosition(
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
        receiptTokenManager.approve(spender_, receiptTokenId, amount_);
        _;
    }

    modifier givenReceiptTokenTwoSpendingIsApproved(
        address owner_,
        address spender_,
        uint256 amount_
    ) {
        vm.prank(owner_);
        receiptTokenManager.approve(spender_, receiptTokenIdTwo, amount_);
        _;
    }

    modifier givenLocallyActive() {
        vm.prank(admin);
        redemptionVault.enable("");
        _;
    }

    modifier givenLocallyInactive() {
        vm.prank(emergency);
        redemptionVault.disable("");
        _;
    }

    modifier givenReserveTokenHasDecimals(uint8 decimals_) {
        reserveToken = new MockERC20("Reserve Token", "RES", decimals_);
        iReserveToken = IERC20(address(reserveToken));
        vault = new MockERC4626(reserveToken, "Vault", "VAULT");

        _createStack();
        _;
    }

    function _startRedemption(
        address user_,
        IERC20 asset_,
        uint8 depositPeriod_,
        uint256 amount_
    ) internal {
        // Approve spending of the receipt token
        vm.startPrank(user_);
        receiptTokenManager.approve(
            address(redemptionVault),
            depositManager.getReceiptTokenId(asset_, depositPeriod_, address(cdFacility)),
            amount_
        );
        vm.stopPrank();

        // Start redemption
        vm.startPrank(user_);
        redemptionVault.startRedemption(asset_, depositPeriod_, amount_, address(cdFacility));
        vm.stopPrank();
    }

    function _depositAndStartRedemption(
        address user_,
        IERC20 asset_,
        uint8 depositPeriod_,
        uint256 amount_
    ) internal {
        // Mint reserve tokens to the user
        MockERC20(address(asset_)).mint(user_, amount_);

        // Approve spending of the reserve tokens
        vm.startPrank(user_);
        asset_.approve(address(depositManager), amount_);
        vm.stopPrank();

        // Mint the receipt token to the user
        vm.prank(user_);
        (, _previousDepositActualAmount) = cdFacility.deposit(
            asset_,
            depositPeriod_,
            amount_,
            false
        );

        _startRedemption(user_, asset_, depositPeriod_, _previousDepositActualAmount);
    }

    modifier givenCommitted(
        address user_,
        IERC20 asset_,
        uint8 depositPeriod_,
        uint256 amount_
    ) {
        _depositAndStartRedemption(user_, asset_, depositPeriod_, amount_);
        _;
    }

    modifier givenCommittedDefault(uint256 amount_) {
        _depositAndStartRedemption(recipient, iReserveToken, PERIOD_MONTHS, amount_);
        _;
    }

    modifier givenRedeemed(address user_, uint16 redemptionId_) {
        vm.prank(user_);
        redemptionVault.finishRedemption(redemptionId_);
        _;
    }

    function _getWrappedReceiptToken(
        IERC20 asset_,
        uint8 depositPeriod_
    ) internal view returns (IERC20) {
        return
            IERC20(
                receiptTokenManager.getWrappedToken(
                    depositManager.getReceiptTokenId(asset_, depositPeriod_, address(cdFacility))
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

    modifier givenFacilityIsAuthorized(address facility_) {
        vm.prank(admin);
        redemptionVault.authorizeFacility(facility_);
        _;
    }

    modifier givenFacilityIsDeauthorized(address facility_) {
        vm.prank(admin);
        redemptionVault.deauthorizeFacility(facility_);
        _;
    }

    modifier givenYieldFee(uint16 yieldFee_) {
        vm.prank(admin);
        ydFacility.setYieldFee(yieldFee_);
        _;
    }

    modifier givenDepositPeriodEnded(uint48 elapsed_) {
        vm.warp(YIELD_EXPIRY + elapsed_);
        _;
    }

    function _takeRateSnapshot() internal {
        vm.prank(HEART);
        ydFacility.execute();
    }

    modifier givenRateSnapshotTaken() {
        // Force a snapshot to be taken at the given timestamp
        _takeRateSnapshot();
        _;
    }

    modifier givenDeauthorizedByFacility(address facility_) {
        vm.startPrank(admin);
        IDepositFacility(facility_).deauthorizeOperator(address(redemptionVault));
        vm.stopPrank();
        _;
    }

    modifier givenMaxBorrowPercentage(IERC20 asset_, uint16 percent_) {
        vm.prank(admin);
        redemptionVault.setMaxBorrowPercentage(asset_, address(cdFacility), percent_);
        _;
    }

    modifier givenAnnualInterestRate(IERC20 asset_, uint16 rate_) {
        vm.prank(admin);
        redemptionVault.setAnnualInterestRate(asset_, address(cdFacility), rate_);
        _;
    }

    modifier givenClaimDefaultRewardPercentage(uint16 percent_) {
        vm.prank(admin);
        redemptionVault.setClaimDefaultRewardPercentage(percent_);
        _;
    }

    modifier givenLoan(address user_, uint16 redemptionId_) {
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(redemptionId_);
        _;
    }

    modifier givenLoanDefault() {
        vm.prank(recipient);
        redemptionVault.borrowAgainstRedemption(0);
        _;
    }

    modifier givenLoanExpired(address user_, uint16 redemptionId_) {
        vm.warp(block.timestamp + PERIOD_MONTHS * 30 days);
        _;
    }

    modifier givenLoanClaimedDefault(address user_, uint16 redemptionId_) {
        vm.prank(defaultRewardClaimer);
        redemptionVault.claimDefaultedLoan(user_, redemptionId_);
        _;
    }

    function _repayLoan(address user_, uint16 redemptionId_, uint256 amount_) internal {
        vm.prank(user_);
        redemptionVault.repayLoan(redemptionId_, amount_);
    }

    modifier givenLoanRepaid(
        address user_,
        uint16 redemptionId_,
        uint256 amount_
    ) {
        _repayLoan(user_, redemptionId_, amount_);
        _;
    }

    modifier givenVaultHasDeposit(uint256 amount_) {
        // Mint the amount
        reserveToken.mint(address(this), amount_);

        // Approve spending
        reserveToken.approve(address(iVault), amount_);

        // Deposit into the vault
        iVault.deposit(amount_, address(this));
        _;
    }

    // ========== ASSERTIONS ========== //

    function _assertMintApproval(uint256 expected_) internal view {
        assertEq(
            minter.mintApproval(address(cdFacility)),
            expected_,
            "minter.mintApproval(address(cdFacility))"
        );
    }

    function _assertReceiptTokenBalance(
        address recipient_,
        uint256 depositAmount_,
        bool isWrapped_
    ) internal view {
        assertEq(
            receiptTokenManager.balanceOf(recipient_, receiptTokenId),
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
            reserveToken.balanceOf(address(cdFacility)),
            0,
            "reserveToken.balanceOf(address(cdFacility))"
        );
        assertEq(
            reserveToken.balanceOf(recipient),
            expectedRecipientBalance_,
            "reserveToken.balanceOf(recipient)"
        );
    }

    function _assertVaultBalance() internal view {
        assertEq(vault.balanceOf(address(treasury)), 0, "vault.balanceOf(address(treasury))");
        assertEq(vault.balanceOf(address(cdFacility)), 0, "vault.balanceOf(address(cdFacility))");
        assertEq(vault.balanceOf(recipient), 0, "vault.balanceOf(recipient)");
    }

    function _assertAvailableDeposits(uint256 expected_) internal view {
        assertEq(
            cdFacility.getAvailableDeposits(iReserveToken),
            expected_,
            "cdFacility.getAvailableDeposits(iReserveToken)"
        );
    }

    function _assertRedemption(
        address user_,
        uint16 redemptionId_,
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address facility_
    ) internal view {
        IDepositRedemptionVault.UserRedemption memory redemption = redemptionVault
            .getUserRedemption(user_, redemptionId_);

        assertEq(redemption.depositToken, address(depositToken_), "depositToken mismatch");
        assertEq(redemption.depositPeriod, depositPeriod_, "depositPeriod mismatch");
        assertEq(redemption.amount, amount_, "amount mismatch");
        assertEq(redemption.facility, facility_, "facility mismatch");
    }

    function _assertLoan(
        address user_,
        uint16 redemptionId_,
        uint256 initialPrincipal_,
        uint256 principal_,
        uint256 interest_,
        bool isDefaulted_,
        uint48 dueDate_
    ) internal view {
        IDepositRedemptionVault.Loan memory loan = redemptionVault.getRedemptionLoan(
            user_,
            redemptionId_
        );

        assertEq(loan.initialPrincipal, initialPrincipal_, "initialPrincipal mismatch");
        assertEq(loan.principal, principal_, "principal mismatch");
        assertEq(loan.interest, interest_, "interest mismatch");
        assertEq(loan.isDefaulted, isDefaulted_, "isDefaulted mismatch");
        assertEq(loan.dueDate, dueDate_, "dueDate mismatch");
    }

    function _assertLoan(
        address user_,
        uint16 redemptionId_,
        uint256 principal_,
        uint256 interest_,
        bool isDefaulted_,
        uint48 dueDate_
    ) internal view {
        _assertLoan(
            user_,
            redemptionId_,
            LOAN_AMOUNT,
            principal_,
            interest_,
            isDefaulted_,
            dueDate_
        );
    }

    function _assertDepositTokenBalances(
        address user_,
        uint256 userExpected_,
        uint256 treasuryExpected_,
        uint256 claimerExpected_
    ) internal view {
        assertEq(
            reserveToken.balanceOf(user_),
            userExpected_,
            "deposit token: user balance mismatch"
        );
        assertEq(
            reserveToken.balanceOf(address(treasury)),
            treasuryExpected_,
            "deposit token: treasury balance mismatch"
        );
        assertEq(
            reserveToken.balanceOf(address(defaultRewardClaimer)),
            claimerExpected_,
            "deposit token: claimer balance mismatch"
        );
        assertEq(
            reserveToken.balanceOf(address(redemptionVault)),
            0,
            "deposit token: redemption vault balance mismatch"
        );
        assertEq(
            reserveToken.balanceOf(address(cdFacility)),
            0,
            "deposit token: cd facility balance mismatch"
        );
    }

    function _assertReceiptTokenBalances(
        address user_,
        uint256 userExpected_,
        uint256 redemptionVaultExpected_
    ) internal view {
        assertEq(
            receiptTokenManager.balanceOf(user_, receiptTokenId),
            userExpected_,
            "receipt token: user balance mismatch"
        );
        assertEq(
            receiptTokenManager.balanceOf(address(redemptionVault), receiptTokenId),
            redemptionVaultExpected_,
            "receipt token: redemption vault balance mismatch"
        );
    }

    // ========== REVERT HELPERS ========== //

    function _expectRoleRevert(bytes32 role_) internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, role_));
    }

    function _expectRevertNotAuthorized() internal {
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
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
                IDepositManager.DepositManager_InvalidAssetPeriod.selector,
                address(asset_),
                depositPeriod_,
                cdFacilityAddress
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
                depositManager.getReceiptTokenId(iReserveToken, PERIOD_MONTHS, address(cdFacility))
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
                depositManager.getReceiptTokenId(iReserveToken, PERIOD_MONTHS, address(cdFacility))
            )
        );
    }

    function _expectRevertInsufficientAvailableDeposits(
        uint256 requestedAmount_,
        uint256 availableAmount_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositFacility.DepositFacility_InsufficientDeposits.selector,
                requestedAmount_,
                availableAmount_
            )
        );
    }

    function _expectRevertInvalidFacility(address facility_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_InvalidFacility.selector,
                facility_
            )
        );
    }

    function _expectRevertFacilityNotRegistered(address facility_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_FacilityNotRegistered.selector,
                facility_
            )
        );
    }

    function _expectRevertFacilityExists(address facility_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_FacilityExists.selector,
                facility_
            )
        );
    }

    function _expectRevertInvalidRedemptionId(address user_, uint16 redemptionId_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_InvalidRedemptionId.selector,
                user_,
                redemptionId_
            )
        );
    }

    function _expectRevertInvalidLoan(address user_, uint16 redemptionId_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_InvalidLoan.selector,
                user_,
                redemptionId_
            )
        );
    }

    function _expectRevertLoanAmountExceeded(
        address user_,
        uint16 redemptionId_,
        uint256 amount_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_LoanAmountExceeded.selector,
                user_,
                redemptionId_,
                amount_
            )
        );
    }

    function _expectRevertMaxBorrowPercentageNotSet(IERC20 asset_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_MaxBorrowPercentageNotSet.selector,
                address(asset_),
                address(cdFacility)
            )
        );
    }

    function _expectRevertInterestRateNotSet(IERC20 asset_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_InterestRateNotSet.selector,
                address(asset_),
                address(cdFacility)
            )
        );
    }

    function _expectRevertLoanIncorrectState(address user_, uint16 redemptionId_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_LoanIncorrectState.selector,
                user_,
                redemptionId_
            )
        );
    }

    function _expectRevertERC20InsufficientAllowance() internal {
        vm.expectRevert("TRANSFER_FROM_FAILED");
    }

    function _expectRevertOutOfBounds(uint16 rate_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_OutOfBounds.selector,
                rate_
            )
        );
    }

    function _expectRevertRedemptionVaultUnpaidLoan(address user_, uint16 redemptionId_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_UnpaidLoan.selector,
                user_,
                redemptionId_
            )
        );
    }

    function _expectRevertInvalidAmount(
        address user_,
        uint16 redemptionId_,
        uint256 amount_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_InvalidAmount.selector,
                user_,
                redemptionId_,
                amount_
            )
        );
    }

    function _expectRevertAlreadyRedeemed(address user_, uint16 redemptionId_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositRedemptionVault.RedemptionVault_AlreadyRedeemed.selector,
                user_,
                redemptionId_
            )
        );
    }

    function _expectRevertZeroAddress() internal {
        vm.expectRevert(
            abi.encodeWithSelector(IDepositRedemptionVault.RedemptionVault_ZeroAddress.selector)
        );
    }
}
