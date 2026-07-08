// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(unwrapped-modifier-logic)
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {Actions, Kernel} from "src/Kernel.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {BurnerLoansConfigTimelock} from "src/policies/BurnerLoansConfigTimelock.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockDepositManager} from "src/test/mocks/MockDepositManager.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";
import {BurnerLoansHarness} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarness.sol";

abstract contract BurnerLoansTest is Test {
    address internal admin;
    address internal burnerLoansAdmin;
    address internal emergency;
    address internal alice;

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
    BurnerLoansConfigTimelock internal configTimelock;

    uint8 internal constant OHM_DECIMALS = 9;
    uint8 internal constant USDS_DECIMALS = 6;
    uint8 internal constant PRICE_DECIMALS = 18;

    function setUp() public virtual {
        admin = makeAddr("admin");
        burnerLoansAdmin = makeAddr("burnerLoansAdmin");
        emergency = makeAddr("emergency");
        alice = makeAddr("alice");

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
        configTimelock = new BurnerLoansConfigTimelock(kernel, burnerLoans);

        kernel.executeAction(Actions.InstallModule, address(mintr));
        kernel.executeAction(Actions.InstallModule, address(price));
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(trsry));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(burnerLoans));
        kernel.executeAction(Actions.ActivatePolicy, address(configTimelock));

        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, burnerLoansAdmin);
        rolesAdmin.grantRole(EMERGENCY_ROLE, emergency);

        burnerLoans.enable("");

        vm.stopPrank();
    }

    function _defaultAssetDebtCap() internal pure returns (uint256) {
        return 100_000e9;
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
        depositManager.addAsset(IERC20(asset_), IERC4626(address(0)), type(uint256).max, 0);
        depositManager.addAssetPeriod(
            IERC20(asset_),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        depositManager.enableAssetPeriod(
            IERC20(asset_),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
    }

    function _configureUsdsDependencies() internal {
        _configurePrice(address(usds), 1e18);
        _configureDepositManagerAsset(address(usds));
    }

    function _setDefaultGlobalDebtCap() internal {
        vm.prank(admin);
        burnerLoans.setGlobalDebtCap(1_000_000e9);
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

    function _setDefaultConfigurator() internal {
        vm.prank(admin);
        burnerLoans.setConfigurator(address(configTimelock));
    }

    function _enableConfigTimelock() internal {
        vm.prank(admin);
        configTimelock.enable("");
    }
}
/// forge-lint: disable-end(unwrapped-modifier-logic)
