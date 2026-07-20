// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(unwrapped-modifier-logic)
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {Actions, Kernel} from "src/Kernel.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusFixedTermLoan} from "src/modules/FLOAN/OlympusFixedTermLoan.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {BurnerLoansConfigTimelock} from "src/policies/BurnerLoansConfigTimelock.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockDepositManager} from "src/test/mocks/MockDepositManager.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockOlympusBackingOracle} from "src/test/mocks/MockOlympusBackingOracle.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";
import {BurnerLoansHarness} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarness.sol";

abstract contract BurnerLoansTest is Test {
    event AuthorizationSet(
        address indexed caller,
        address indexed account,
        address indexed authorized,
        uint48 authorizationDeadline
    );

    address internal admin;
    address internal burnerLoansAdmin;
    address internal emergency;
    address internal alice;

    Kernel internal kernel;
    OlympusMinter internal mintr;
    OlympusFixedTermLoan internal floan;
    OlympusRoles internal roles;
    OlympusTreasury internal trsry;
    RolesAdmin internal rolesAdmin;
    MockPrice internal price;
    MockOhm internal ohm;
    MockERC20 internal usds;
    ReceiptTokenManager internal receiptTokenManager;
    DepositManager internal depositManager;
    MockDepositManager internal mockDepositManager;
    BurnerLoansHarness internal burnerLoans;
    BurnerLoansConfig internal burnerLoansConfig;
    BurnerLoansConfigTimelock internal configTimelock;
    MockOlympusBackingOracle internal backingOracle;

    uint8 internal constant OHM_DECIMALS = 9;
    uint8 internal constant USDS_DECIMALS = 6;
    uint8 internal constant PRICE_DECIMALS = 18;

    function _ohmDecimals() internal pure virtual returns (uint8) {
        return OHM_DECIMALS;
    }

    function _collateralDecimals() internal pure virtual returns (uint8) {
        return USDS_DECIMALS;
    }

    function setUp() public virtual {
        admin = makeAddr("admin");
        burnerLoansAdmin = makeAddr("burnerLoansAdmin");
        emergency = makeAddr("emergency");
        alice = makeAddr("alice");

        vm.startPrank(admin);

        kernel = new Kernel();
        ohm = new MockOhm("OHM", "OHM", _ohmDecimals());
        usds = new MockERC20("USDS", "USDS", _collateralDecimals());
        mintr = new OlympusMinter(kernel, address(ohm));
        floan = new OlympusFixedTermLoan(kernel);
        roles = new OlympusRoles(kernel);
        trsry = new OlympusTreasury(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        price = new MockPrice(kernel, PRICE_DECIMALS, uint32(8 hours));
        receiptTokenManager = new ReceiptTokenManager();
        depositManager = new DepositManager(address(kernel), address(receiptTokenManager));
        burnerLoans = new BurnerLoansHarness(kernel, IERC20(address(ohm)), depositManager);
        burnerLoansConfig = new BurnerLoansConfig(kernel, IERC20(address(ohm)), depositManager);
        burnerLoans.setConfigForTest(burnerLoansConfig);
        backingOracle = new MockOlympusBackingOracle(1e18);
        configTimelock = new BurnerLoansConfigTimelock(
            kernel,
            burnerLoansConfig,
            address(burnerLoans)
        );

        kernel.executeAction(Actions.InstallModule, address(floan));
        kernel.executeAction(Actions.InstallModule, address(mintr));
        kernel.executeAction(Actions.InstallModule, address(price));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(trsry));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(depositManager));
        kernel.executeAction(Actions.ActivatePolicy, address(burnerLoansConfig));
        kernel.executeAction(Actions.ActivatePolicy, address(burnerLoans));
        kernel.executeAction(Actions.ActivatePolicy, address(configTimelock));

        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(ADMIN_ROLE, address(burnerLoans));
        rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, burnerLoansAdmin);
        rolesAdmin.grantRole(EMERGENCY_ROLE, emergency);
        rolesAdmin.grantRole("manager", admin);
        rolesAdmin.grantRole("manager", address(this));
        rolesAdmin.grantRole("deposit_operator", address(burnerLoans));

        depositManager.enable("");
        burnerLoansConfig.enable("");
        depositManager.setOperatorName(address(burnerLoans), "brn");
        burnerLoans.enable("");
        burnerLoans.setBackingOracle(address(backingOracle));

        vm.stopPrank();
    }

    function _defaultAssetDebtCap() internal pure returns (uint128) {
        return uint128(100_000 * 10 ** _ohmDecimals());
    }

    function _defaultAssetFeeConfig() internal pure returns (IBurnerLoans.AssetFeeConfig memory) {
        return
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: 25,
                kinkBps: 8_000,
                preKinkSlopeBps: 100,
                postKinkSlopeBps: 900
            });
    }

    function _defaultAssetRiskConfigInput()
        internal
        pure
        returns (IBurnerLoans.AssetRiskConfigInput memory)
    {
        return
            IBurnerLoans.AssetRiskConfigInput({
                collateralFactorBps: 10_000,
                minCollateralRatioBps: 11_500,
                backingMultiplierBps: 10_000,
                keeperRewardBps: 100,
                termLength: 30 days,
                maxMaturityHorizon: 90 days,
                maxKeeperReward: 1_000e6
            });
    }

    function _defaultAssetConfig(
        uint8 collateralDecimals_
    ) internal pure returns (IBurnerLoans.AssetConfig memory) {
        return
            IBurnerLoans.AssetConfig({
                enabled: true,
                collateralDecimals: collateralDecimals_,
                collateralFactorBps: 10_000,
                minCollateralRatioBps: 11_500,
                backingMultiplierBps: 10_000,
                keeperRewardBps: 100,
                termLength: 30 days,
                maxMaturityHorizon: 90 days,
                debtCap: _defaultAssetDebtCap(),
                maxKeeperReward: 1_000e6
            });
    }

    function _assetRiskConfigInputFromConfig(
        IBurnerLoans.AssetConfig memory config_
    ) internal pure returns (IBurnerLoans.AssetRiskConfigInput memory) {
        return
            IBurnerLoans.AssetRiskConfigInput({
                collateralFactorBps: config_.collateralFactorBps,
                minCollateralRatioBps: config_.minCollateralRatioBps,
                backingMultiplierBps: config_.backingMultiplierBps,
                keeperRewardBps: config_.keeperRewardBps,
                termLength: config_.termLength,
                maxMaturityHorizon: config_.maxMaturityHorizon,
                maxKeeperReward: config_.maxKeeperReward
            });
    }

    function _configurePrice(address asset_, uint256 price_) internal {
        price.setPrice(asset_, price_);
    }

    function _configureDepositManagerAsset(address asset_) internal {
        vm.startPrank(admin);
        depositManager.addAsset(IERC20(asset_), IERC4626(address(0)), type(uint256).max, 0);
        depositManager.addAssetPeriod(
            IERC20(asset_),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        vm.stopPrank();
    }

    function _configureUsdsDependencies() internal {
        _configurePrice(address(usds), 1e18);
        _configureDepositManagerAsset(address(usds));
    }

    function _setDefaultGlobalDebtCap() internal {
        vm.prank(admin);
        burnerLoans.setGlobalDebtCap(uint128(1_000_000 * 10 ** _ohmDecimals()));
    }

    function _addDefaultUsdsAsset() internal {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();

        vm.prank(admin);
        burnerLoans.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
    }

    function _setOtherMarketDebtForTest(uint128 debtOhm_) internal returns (MockERC20 asset) {
        asset = new MockERC20("Other Collateral", "OTHER", 18);
        _configurePrice(address(asset), 1e18);
        _configureDepositManagerAsset(address(asset));

        vm.prank(admin);
        burnerLoansConfig.addAsset(
            address(burnerLoans),
            address(asset),
            type(uint128).max,
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
        burnerLoans.setActiveDebtForTest(address(asset), debtOhm_, debtOhm_);
    }

    function _setAuthorizationAndExpectEvent(
        address owner_,
        address operator_,
        uint48 deadline_
    ) internal {
        vm.prank(owner_);
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit AuthorizationSet(owner_, owner_, operator_, deadline_);
        burnerLoans.setAuthorization(operator_, deadline_);
    }

    function _assertDepositMatchesPreview(
        uint256 previewDeposit_,
        uint256 previewTotal_,
        uint256 deposited_,
        uint256 total_
    ) internal pure {
        assertEq(previewDeposit_, deposited_, "preview deposit");
        assertEq(previewTotal_, total_, "preview total");
    }

    function _assertWithdrawalMatchesPreview(
        IBurnerLoans.WithdrawPreview memory preview_,
        address tokenOut_,
        uint256 amountOut_,
        uint256 remaining_,
        uint256 health_
    ) internal pure {
        assertEq(tokenOut_, preview_.returnToken, "preview token");
        assertEq(amountOut_, preview_.returnAmount, "preview amount");
        assertEq(remaining_, preview_.remainingDepositedCollateral, "preview remaining");
        assertEq(health_, preview_.resultingHealthFactor, "preview health");
        assertTrue(preview_.executable, "preview executable");
    }

    function _assertPositionAndActiveDebt(
        address asset_,
        address account_,
        uint256 expectedCollateral_,
        uint256 expectedDebtOhm_,
        uint48 expectedMaturity_
    ) internal view {
        IBurnerLoans.Position memory position = burnerLoans.getPosition(asset_, account_);
        assertEq(position.depositedCollateral, expectedCollateral_, "position collateral");
        assertEq(position.debtOhm, expectedDebtOhm_, "position debt");
        assertEq(position.maturity, expectedMaturity_, "position maturity");
        assertEq(burnerLoans.totalActiveDebtOhm(), expectedDebtOhm_, "total active debt");
        assertEq(burnerLoans.assetActiveDebtOhm(asset_), expectedDebtOhm_, "asset active debt");
    }

    /// @dev Replaces the real custody policy for tests that need injected impossible-state failures.
    function _useMockDepositManager() internal {
        vm.startPrank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));

        mockDepositManager = new MockDepositManager(kernel, address(usds));
        burnerLoans = new BurnerLoansHarness(kernel, IERC20(address(ohm)), mockDepositManager);
        burnerLoansConfig = new BurnerLoansConfig(kernel, IERC20(address(ohm)), mockDepositManager);
        burnerLoans.setConfigForTest(burnerLoansConfig);
        kernel.executeAction(Actions.ActivatePolicy, address(burnerLoansConfig));
        kernel.executeAction(Actions.ActivatePolicy, address(burnerLoans));
        rolesAdmin.grantRole("deposit_operator", address(burnerLoans));

        mockDepositManager.addAsset(
            IERC20(address(usds)),
            IERC4626(address(0)),
            type(uint256).max,
            0
        );
        mockDepositManager.addAssetPeriod(
            IERC20(address(usds)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        mockDepositManager.enableAssetPeriod(
            IERC20(address(usds)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );

        price.setPrice(address(usds), 1e18);
        burnerLoansConfig.enable("");
        burnerLoans.enable("");
        burnerLoans.setBackingOracle(address(backingOracle));
        burnerLoans.setGlobalDebtCap(1_000_000e9);
        burnerLoansConfig.addAsset(
            address(burnerLoans),
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
        vm.stopPrank();
    }

    function _setDefaultConfigurator() internal {
        vm.prank(admin);
        burnerLoansConfig.setConfigurator(address(configTimelock));
    }

    function _enableConfigTimelock() internal {
        vm.prank(admin);
        configTimelock.enable("");
    }
}
/// forge-lint: disable-end(unwrapped-modifier-logic)
