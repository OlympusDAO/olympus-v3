// SPDX-License-Identifier: Unlicense
// Live-PRICE and cached variants share one fork fixture so their gas measurements remain comparable.
// forge-lint: disable-start(multi-contract-file)
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {BL_COLLATERAL_POLICY_ROLE, BL_DEBT_POLICY_ROLE, BL_LIQUIDATION_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BURNER_LOANS_SEIZER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {Actions, Kernel, toKeycode} from "src/Kernel.sol";
import {OlympusFixedTermLoan} from "src/modules/FLOAN/OlympusFixedTermLoan.sol";
import {OlympusPricev1_2} from "src/modules/PRICE/OlympusPrice.v1_2.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {BurnerLoansCollateral} from "src/policies/burnerloans/BurnerLoansCollateral.sol";
import {BurnerLoansConfig} from "src/policies/burnerloans/BurnerLoansConfig.sol";
import {BurnerLoansCore} from "src/policies/burnerloans/BurnerLoansCore.sol";
import {BurnerLoansDebt} from "src/policies/burnerloans/BurnerLoansDebt.sol";
import {BurnerLoansInventory} from "src/policies/burnerloans/BurnerLoansInventory.sol";
import {BurnerLoansLens} from "src/policies/burnerloans/BurnerLoansLens.sol";
import {BurnerLoansPayout} from "src/policies/burnerloans/BurnerLoansPayout.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";
import {BurnerLoansSeize} from "src/policies/burnerloans/BurnerLoansSeize.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {MockBackingOracle} from "src/test/mocks/MockBackingOracle.sol";

contract BurnerLoansLivePriceForkGasTest is Test {
    uint256 internal constant _FORK_BLOCK = 25_894_485;

    address internal constant _KERNEL = 0x2286d7f9639e8158FaD1169e76d1FbC38247f54b;
    address internal constant _OHM = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address internal constant _USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address internal constant _ROLES_ADMIN = 0xb216d714d91eeC4F7120a732c11428857C659eC8;
    address internal constant _ROLES_ADMIN_ADMIN = 0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39;

    uint256 internal constant _PINNED_OHM_USD_PRICE = 20_097_127_953_802_461_330;
    uint256 internal constant _PINNED_USDS_USD_PRICE = 999_819_106_666_666_666;
    uint256 internal constant _BACKING_PER_OHM_USD = 1e18;

    uint128 internal constant _COLLATERAL = 4_000e18;
    uint128 internal constant _NEW_POSITION_COLLATERAL = 2_000e18;
    uint128 internal constant _COLLATERAL_CHANGE = 500e18;
    uint128 internal constant _DEBT = 100e9;
    uint128 internal constant _REPAYMENT = 40e9;
    uint128 internal constant _GLOBAL_DEBT_CAP = 1_000_000e9;
    uint128 internal constant _ASSET_DEBT_CAP = 100_000e9;
    uint48 internal constant _TERM_LENGTH = 30 days;
    uint16 internal constant _KEEPER_REWARD_BPS = 100;
    uint16 internal constant _PRE_KINK_SLOPE_BPS = 100;

    uint256 internal constant _HEALTH_AFTER_EXISTING_DEPOSIT = 1_902_912_740_462_711_134;
    uint256 internal constant _HEALTH_AFTER_PARTIAL_WITHDRAWAL = 1_480_043_242_582_108_659;
    uint256 internal constant _HEALTH_AFTER_BORROW = 1_691_477_991_522_409_896;
    uint256 internal constant _HEALTH_AFTER_REPAYMENT = 2_819_129_985_870_683_161;

    /// @dev Starts each test with 4,000 USDS collateral and 100 OHM debt.
    address internal _alice;
    /// @dev Starts each test with 4,000 USDS collateral and no debt.
    address internal _bob;
    /// @dev Starts each test funded and approved, but without a Burner Loans position.
    address internal _carol;
    uint48 internal _aliceMaturity;
    uint256 internal _aliceUsdsBalanceBeforeTest;
    uint256 internal _bobUsdsBalanceBeforeTest;
    uint256 internal _carolUsdsBalanceBeforeTest;
    uint256 internal _aliceOhmBalanceBeforeTest;
    uint256 internal _bobOhmBalanceBeforeTest;
    uint256 internal _custodyUsdsBalanceBeforeTest;

    Kernel internal _kernel;
    IERC20 internal _ohm;
    IERC20 internal _usds;
    IPRICEv2 internal _price;
    DepositManager internal _depositManager;
    BurnerLoansCore internal _core;
    BurnerLoansRisk internal _risk;
    BurnerLoansPayout internal _payout;
    BurnerLoansCollateral internal _collateral;
    BurnerLoansDebt internal _debt;
    BurnerLoansSeize internal _liquidation;
    BurnerLoansLens internal _lens;
    BurnerLoansInventory internal _inventory;
    BurnerLoansConfig internal _burnerLoansConfig;
    MockBackingOracle internal _backingOracle;

    function setUp() public virtual {
        uint256 forkId = vm.createSelectFork("mainnet", _FORK_BLOCK);
        assertEq(vm.activeFork(), forkId, "active mainnet fork");

        _alice = makeAddr("alice");
        _bob = makeAddr("bob");
        _carol = makeAddr("carol");

        _kernel = Kernel(_KERNEL);
        _ohm = IERC20(_OHM);
        _usds = IERC20(_USDS);
        _price = IPRICEv2(address(_kernel.getModuleForKeycode(toKeycode("PRICE"))));

        _assertPinnedPriceConfiguration();
        _deployAndConfigureBurnerLoans();

        _fundAndApprove(_alice);
        _fundAndApprove(_bob);
        _fundAndApprove(_carol);

        _deposit(_alice, _COLLATERAL);
        _aliceMaturity = _borrow(_alice, _DEBT);
        _deposit(_bob, _COLLATERAL);

        // Repayment cannot occur in the same block as the latest borrow. The fork state remains
        // pinned at _FORK_BLOCK; only the test execution block advances by one.
        vm.roll(_FORK_BLOCK + 1);

        _aliceUsdsBalanceBeforeTest = _usds.balanceOf(_alice);
        _bobUsdsBalanceBeforeTest = _usds.balanceOf(_bob);
        _carolUsdsBalanceBeforeTest = _usds.balanceOf(_carol);
        _aliceOhmBalanceBeforeTest = _ohm.balanceOf(_alice);
        _bobOhmBalanceBeforeTest = _ohm.balanceOf(_bob);
        _custodyUsdsBalanceBeforeTest = _usds.balanceOf(address(_depositManager));
    }

    function test_gasSnapshot_depositCollateral_newPosition() public {
        vm.startPrank(_carol);
        vm.startSnapshotGas(_snapshotName("depositCollateral.newPosition"));
        (uint256 depositedAmount, uint256 resultingCollateral, uint256 healthFactor) = _collateral
            .depositCollateral(_USDS, _NEW_POSITION_COLLATERAL, _carol);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(depositedAmount, _NEW_POSITION_COLLATERAL, "deposited amount");
        assertEq(resultingCollateral, _NEW_POSITION_COLLATERAL, "resulting collateral");
        // Resulting debt is zero, so health is defined as max uint256 without a PRICE read.
        assertEq(healthFactor, type(uint256).max, "debt-free health factor");
        assertEq(
            _carolUsdsBalanceBeforeTest - _usds.balanceOf(_carol),
            _NEW_POSITION_COLLATERAL,
            "USDS balance decrease"
        );
        assertEq(
            _usds.balanceOf(address(_depositManager)) - _custodyUsdsBalanceBeforeTest,
            _NEW_POSITION_COLLATERAL,
            "custody USDS increase"
        );
        assertEq(
            _lens.getPosition(_USDS, _carol).depositedCollateral,
            _NEW_POSITION_COLLATERAL,
            "position collateral"
        );
        _assertGasRecorded(gasUsed);
    }

    function test_gasSnapshot_depositCollateral_existingDebtPosition() public {
        vm.startPrank(_alice);
        vm.startSnapshotGas(_snapshotName("depositCollateral.existingDebtPosition"));
        (uint256 depositedAmount, uint256 resultingCollateral, uint256 healthFactor) = _collateral
            .depositCollateral(_USDS, _COLLATERAL_CHANGE, _alice);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(depositedAmount, _COLLATERAL_CHANGE, "deposited amount");
        assertEq(resultingCollateral, _COLLATERAL + _COLLATERAL_CHANGE, "resulting collateral");
        // collateralValueUsd = floor(4_500e18 * 0.999819106666666666e18 / 1e18)
        //                    = 4_499_185_979_999_999_997_000 (18 decimals)
        // debtValueUsd = ceil(100e9 * 20.097127953802461330e18 / 1e9)
        //              = 2_009_712_795_380_246_133_000 (18 decimals)
        // marketRequirementUsd = ceil(debtValueUsd * 10_000 / 8_500)
        //                      = 2_364_367_994_564_995_450_589
        // backingDebtValueUsd = ceil(100e9 * 1e18 / 1e9) = 100e18
        // backingRequirementUsd = ceil(100e18 * 12_500 / 10_000) = 125e18
        // requiredCollateralUsd = max(marketRequirementUsd, backingRequirementUsd)
        // health = floor(collateralValueUsd * 1e18 / requiredCollateralUsd)
        //        = 1_902_912_740_462_711_134
        assertEq(healthFactor, _HEALTH_AFTER_EXISTING_DEPOSIT, "resulting health factor");
        assertEq(
            _aliceUsdsBalanceBeforeTest - _usds.balanceOf(_alice),
            _COLLATERAL_CHANGE,
            "USDS balance decrease"
        );
        assertEq(
            _usds.balanceOf(address(_depositManager)) - _custodyUsdsBalanceBeforeTest,
            _COLLATERAL_CHANGE,
            "custody USDS increase"
        );
        assertEq(
            _lens.getPosition(_USDS, _alice).depositedCollateral,
            _COLLATERAL + _COLLATERAL_CHANGE,
            "position collateral"
        );
        _assertGasRecorded(gasUsed);
    }

    function test_gasSnapshot_withdrawCollateral_partialWithDebt() public {
        vm.startPrank(_alice);
        vm.startSnapshotGas(_snapshotName("withdrawCollateral.partialWithDebt"));
        IBurnerLoansCollateral.WithdrawPreview memory result = _collateral.withdrawCollateral(
            _USDS,
            _COLLATERAL_CHANGE,
            _alice,
            _alice
        );
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(result.returnToken, _USDS, "withdrawal token");
        assertEq(result.returnAmount, _COLLATERAL_CHANGE, "withdrawal amount");
        assertEq(
            result.remainingDepositedCollateral,
            _COLLATERAL - _COLLATERAL_CHANGE,
            "remaining collateral"
        );
        // collateralValueUsd = floor(3_500e18 * 0.999819106666666666e18 / 1e18)
        //                    = 3_499_366_873_333_333_331_000 (18 decimals)
        // debtValueUsd = ceil(100e9 * 20.097127953802461330e18 / 1e9)
        //              = 2_009_712_795_380_246_133_000 (18 decimals)
        // marketRequirementUsd = ceil(debtValueUsd * 10_000 / 8_500)
        //                      = 2_364_367_994_564_995_450_589
        // backingRequirementUsd = ceil(ceil(100e9 * 1e18 / 1e9) * 12_500 / 10_000)
        //                       = 125e18
        // requiredCollateralUsd = 2_364_367_994_564_995_450_589
        // health = floor(collateralValueUsd * 1e18 / requiredCollateralUsd)
        //        = 1_480_043_242_582_108_659
        assertEq(
            result.resultingHealthFactor,
            _HEALTH_AFTER_PARTIAL_WITHDRAWAL,
            "resulting health factor"
        );
        assertEq(
            _usds.balanceOf(_alice) - _aliceUsdsBalanceBeforeTest,
            _COLLATERAL_CHANGE,
            "USDS balance increase"
        );
        assertEq(
            _custodyUsdsBalanceBeforeTest - _usds.balanceOf(address(_depositManager)),
            _COLLATERAL_CHANGE,
            "custody USDS decrease"
        );
        assertEq(
            _lens.getPosition(_USDS, _alice).depositedCollateral,
            _COLLATERAL - _COLLATERAL_CHANGE,
            "position collateral"
        );
        _assertGasRecorded(gasUsed);
    }

    function test_gasSnapshot_withdrawCollateral_allWithoutDebt() public {
        vm.startPrank(_bob);
        vm.startSnapshotGas(_snapshotName("withdrawCollateral.allWithoutDebt"));
        IBurnerLoansCollateral.WithdrawPreview memory result = _collateral.withdrawCollateral(
            _USDS,
            _COLLATERAL,
            _bob,
            _bob
        );
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(result.returnToken, _USDS, "withdrawal token");
        assertEq(result.returnAmount, _COLLATERAL, "withdrawal amount");
        assertEq(result.remainingDepositedCollateral, 0, "remaining collateral");
        // Resulting collateral and debt are both zero, so health is max uint256 without PRICE.
        assertEq(result.resultingHealthFactor, type(uint256).max, "debt-free health factor");
        assertEq(
            _usds.balanceOf(_bob) - _bobUsdsBalanceBeforeTest,
            _COLLATERAL,
            "USDS balance increase"
        );
        assertEq(
            _custodyUsdsBalanceBeforeTest - _usds.balanceOf(address(_depositManager)),
            _COLLATERAL,
            "custody USDS decrease"
        );
        assertEq(_lens.getPosition(_USDS, _bob).depositedCollateral, 0, "position collateral");
        _assertGasRecorded(gasUsed);
    }

    function test_gasSnapshot_borrow_first() public {
        vm.startPrank(_bob);
        vm.startSnapshotGas(_snapshotName("borrow.first"));
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            _USDS,
            _DEBT,
            _bob,
            _bob,
            type(uint256).max,
            address(0)
        );
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertGt(result.fee, 0, "borrow fee");
        assertEq(result.resultingDebtOhm, _DEBT, "resulting debt");
        assertGt(result.maturity, block.timestamp, "maturity");
        // collateralValueUsd = floor(4_000e18 * 0.999819106666666666e18 / 1e18)
        //                    = 3_999_276_426_666_666_664_000 (18 decimals)
        // debtValueUsd = ceil(100e9 * 20.097127953802461330e18 / 1e9)
        //              = 2_009_712_795_380_246_133_000 (18 decimals)
        // marketRequirementUsd = ceil(debtValueUsd * 10_000 / 8_500)
        //                      = 2_364_367_994_564_995_450_589
        // backingRequirementUsd = ceil(ceil(100e9 * 1e18 / 1e9) * 12_500 / 10_000)
        //                       = 125e18
        // requiredCollateralUsd = 2_364_367_994_564_995_450_589
        // health = floor(collateralValueUsd * 1e18 / requiredCollateralUsd)
        //        = 1_691_477_991_522_409_896
        assertEq(result.resultingHealthFactor, _HEALTH_AFTER_BORROW, "resulting health factor");
        assertEq(_ohm.balanceOf(_bob) - _bobOhmBalanceBeforeTest, _DEBT, "OHM balance increase");
        assertEq(_lens.getPosition(_USDS, _bob).debtOhm, _DEBT, "position debt");
        assertEq(_core.totalActiveDebtOhm(), 2 * _DEBT, "total active debt");
        _assertGasRecorded(gasUsed);
    }

    function test_gasSnapshot_repay_partial() public {
        vm.startPrank(_alice);
        vm.startSnapshotGas(_snapshotName("repay.partial"));
        (uint256 remainingDebt, uint256 healthFactor) = _debt.repay(_USDS, _REPAYMENT, _alice);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(remainingDebt, _DEBT - _REPAYMENT, "remaining debt");
        // collateralValueUsd = floor(4_000e18 * 0.999819106666666666e18 / 1e18)
        //                    = 3_999_276_426_666_666_664_000 (18 decimals)
        // debtValueUsd = ceil(60e9 * 20.097127953802461330e18 / 1e9)
        //              = 1_205_827_677_228_147_679_800 (18 decimals)
        // marketRequirementUsd = ceil(debtValueUsd * 10_000 / 8_500)
        //                      = 1_418_620_796_738_997_270_353
        // backingRequirementUsd = ceil(ceil(60e9 * 1e18 / 1e9) * 12_500 / 10_000)
        //                       = 75e18
        // requiredCollateralUsd = 1_418_620_796_738_997_270_353
        // health = floor(collateralValueUsd * 1e18 / requiredCollateralUsd)
        //        = 2_819_129_985_870_683_161
        assertEq(healthFactor, _HEALTH_AFTER_REPAYMENT, "resulting health factor");
        assertEq(
            _aliceOhmBalanceBeforeTest - _ohm.balanceOf(_alice),
            _REPAYMENT,
            "OHM balance decrease"
        );
        assertEq(_lens.getPosition(_USDS, _alice).debtOhm, _DEBT - _REPAYMENT, "position debt");
        assertEq(_core.totalActiveDebtOhm(), _DEBT - _REPAYMENT, "total active debt");
        _assertGasRecorded(gasUsed);
    }

    function test_gasSnapshot_extend_oneTerm() public {
        vm.startPrank(_alice);
        vm.startSnapshotGas(_snapshotName("extend.oneTerm"));
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            _USDS,
            _alice,
            1,
            type(uint256).max,
            address(0)
        );
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertGt(result.fee, 0, "extension fee");
        assertEq(result.maturity, _aliceMaturity + _TERM_LENGTH, "extended maturity");
        // Collateral and debt are unchanged from the borrow case, so the independently derived
        // inputs remain collateralValueUsd = 3_999_276_426_666_666_664_000 and
        // requiredCollateralUsd = max(2_364_367_994_564_995_450_589, 125e18).
        // health = floor(collateralValueUsd * 1e18 / requiredCollateralUsd)
        //        = 1_691_477_991_522_409_896
        assertEq(result.healthFactor, _HEALTH_AFTER_BORROW, "resulting health factor");
        IBurnerLoansCore.Position memory positionAfter = _lens.getPosition(_USDS, _alice);
        assertEq(positionAfter.debtOhm, _DEBT, "position debt");
        assertEq(positionAfter.maturity, result.maturity, "position maturity");
        _assertGasRecorded(gasUsed);
    }

    // seize
    // given one active position is unhealthy under the backing requirement
    //  when a keeper seizes the position
    //   then it records the production PRICE or fresh-cache seizure cost
    function test_gasSnapshot_seize_single() public {
        _backingOracle.setBacking(40e18);
        address[] memory borrowers = new address[](1);
        borrowers[0] = _alice;

        vm.startSnapshotGas(_snapshotName("seize.single"));
        (address tokenOut, uint256 keeperReward, uint256 collateralToTreasury) = _liquidation.seize(
            _USDS,
            borrowers
        );
        uint256 gasUsed = vm.stopSnapshotGas();

        assertEq(keeperReward, 0, "keeper reward");
        assertEq(tokenOut, _USDS, "seizure output token");
        assertEq(collateralToTreasury, _COLLATERAL, "collateral routed to Treasury");
        IBurnerLoansCore.Position memory positionAfter = _lens.getPosition(_USDS, _alice);
        assertEq(positionAfter.debtOhm, 0, "position debt");
        assertEq(positionAfter.depositedCollateral, 0, "position collateral");
        assertEq(_core.totalActiveDebtOhm(), 0, "total active debt");
        _assertGasRecorded(gasUsed);
    }

    function _assertPinnedPriceConfiguration() internal view {
        (uint8 major, uint8 minor) = OlympusPricev1_2(address(_price)).VERSION();
        assertEq(major, 1, "PRICE major version");
        assertEq(minor, 2, "PRICE minor version");
        assertEq(_price.getPrice(_OHM), _PINNED_OHM_USD_PRICE, "pinned OHM price");
        assertEq(_price.getPrice(_USDS), _PINNED_USDS_USD_PRICE, "pinned USDS price");

        IPRICEv2.Asset memory ohmAsset = _price.getAssetData(_OHM);
        IPRICEv2.Asset memory usdsAsset = _price.getAssetData(_USDS);
        IPRICEv2.Component[] memory ohmFeeds = abi.decode(ohmAsset.feeds, (IPRICEv2.Component[]));
        IPRICEv2.Component[] memory usdsFeeds = abi.decode(usdsAsset.feeds, (IPRICEv2.Component[]));
        assertEq(ohmFeeds.length, 4, "OHM production feed count");
        assertEq(usdsFeeds.length, 3, "USDS production feed count");
    }

    function _snapshotName(string memory action_) internal pure virtual returns (string memory) {
        return string.concat("BurnerLoans.livePrice.", action_);
    }

    function _deployAndConfigureBurnerLoans() internal {
        OlympusFixedTermLoan floan = new OlympusFixedTermLoan(_kernel);
        ReceiptTokenManager receiptTokenManager = new ReceiptTokenManager();
        _depositManager = new DepositManager(address(_kernel), address(receiptTokenManager));
        _backingOracle = new MockBackingOracle(_BACKING_PER_OHM_USD);
        _core = new BurnerLoansCore(_kernel, _ohm, _depositManager);
        _inventory = new BurnerLoansInventory(_kernel, _ohm, address(_core));
        _burnerLoansConfig = new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
        _payout = new BurnerLoansPayout(_kernel, address(_core));
        _risk = new BurnerLoansRisk(
            _kernel,
            _ohm,
            address(_backingOracle),
            address(0),
            0,
            address(_core)
        );
        _collateral = new BurnerLoansCollateral(_kernel, _core);
        _debt = new BurnerLoansDebt(_kernel, _core);
        _liquidation = new BurnerLoansSeize(_kernel, _core);
        _lens = new BurnerLoansLens(address(_core));
        // The pinned module is the full PRICEv2 implementation with a VERSION=(1,2)
        // compatibility wrapper. Risk requires major 2. Override that metadata only;
        // live feeds, strategy, price storage and measured price calls remain unchanged.
        vm.mockCall(
            address(_price),
            abi.encodeWithSelector(IVersioned.VERSION.selector),
            abi.encode(uint8(2), uint8(0))
        );

        address kernelExecutor = _kernel.executor();
        vm.startPrank(kernelExecutor);
        _kernel.executeAction(Actions.InstallModule, address(floan));
        _kernel.executeAction(Actions.ActivatePolicy, address(_depositManager));
        _kernel.executeAction(Actions.ActivatePolicy, address(_inventory));
        _kernel.executeAction(Actions.ActivatePolicy, address(_core));
        _kernel.executeAction(Actions.ActivatePolicy, address(_burnerLoansConfig));
        _kernel.executeAction(Actions.ActivatePolicy, address(_payout));
        _kernel.executeAction(Actions.ActivatePolicy, address(_risk));
        _kernel.executeAction(Actions.ActivatePolicy, address(_collateral));
        _kernel.executeAction(Actions.ActivatePolicy, address(_debt));
        _kernel.executeAction(Actions.ActivatePolicy, address(_liquidation));
        vm.stopPrank();

        RolesAdmin rolesAdmin = RolesAdmin(_ROLES_ADMIN);
        assertEq(rolesAdmin.admin(), _ROLES_ADMIN_ADMIN, "RolesAdmin admin");
        vm.startPrank(_ROLES_ADMIN_ADMIN);
        rolesAdmin.grantRole(ADMIN_ROLE, address(this));
        rolesAdmin.grantRole("deposit_operator", address(_core));
        rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(_collateral));
        rolesAdmin.grantRole(BL_DEBT_POLICY_ROLE, address(_debt));
        rolesAdmin.grantRole(BL_LIQUIDATION_POLICY_ROLE, address(_liquidation));
        rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, address(this));
        vm.stopPrank();

        _core.setConfigOperator(address(_burnerLoansConfig));
        _payout.enable("");
        _core.setPayout(address(_payout));
        _risk.enable("");
        _core.setRisk(address(_risk));
        _inventory.setConfigOperator(address(_burnerLoansConfig));
        _inventory.enable("");
        _core.setInventory(address(_inventory));

        _depositManager.enable("");
        _depositManager.setOperatorName(address(_core), "brn");
        _core.enable("");
        _burnerLoansConfig.enable("");
        _collateral.enable("");
        _debt.enable("");
        _liquidation.enable("");

        _depositManager.addAsset(_usds, IERC4626(address(0)), type(uint256).max, 0);
        uint256 receiptTokenId = _depositManager.addAssetPeriod(
            _usds,
            LoanParameters._DEPOSIT_PERIOD,
            address(_core)
        );
        assertGt(receiptTokenId, 0, "USDS receipt token ID");

        _inventory.setGlobalDebtCap(_GLOBAL_DEBT_CAP);
        _burnerLoansConfig.addAsset(
            _USDS,
            _ASSET_DEBT_CAP,
            _defaultRiskConfig(),
            _defaultFeeConfig(),
            false
        );
    }

    function _defaultRiskConfig()
        internal
        pure
        returns (IBurnerLoansRisk.AssetRiskConfigInput memory)
    {
        return
            IBurnerLoansRisk.AssetRiskConfigInput({
                maxLtvBps: 8_500,
                backingMultiplierBps: 12_500,
                keeperRewardBps: _KEEPER_REWARD_BPS,
                termLength: _TERM_LENGTH,
                maxMaturityHorizon: 90 days,
                maxKeeperReward: 1_000e18
            });
    }

    function _defaultFeeConfig() internal pure returns (IBurnerLoansRisk.AssetFeeConfig memory) {
        return
            IBurnerLoansRisk.AssetFeeConfig({
                baseFeeBps: 25,
                kinkBps: 8_000,
                preKinkSlopeBps: _PRE_KINK_SLOPE_BPS,
                postKinkSlopeBps: 900
            });
    }

    function _fundAndApprove(address account_) internal {
        deal(_USDS, account_, 20_000e18, true);
        vm.startPrank(account_);
        assertTrue(
            _usds.approve(address(_core), type(uint256).max),
            "USDS approval should succeed"
        );
        assertTrue(_ohm.approve(address(_core), type(uint256).max), "OHM approval should succeed");
        vm.stopPrank();
    }

    function _deposit(address account_, uint128 amount_) internal {
        vm.prank(account_);
        (uint256 depositedAmount, uint256 resultingCollateral, uint256 healthFactor) = _collateral
            .depositCollateral(_USDS, amount_, account_);
        assertEq(depositedAmount, amount_, "setup deposited amount");
        assertEq(resultingCollateral, amount_, "setup resulting collateral");
        assertEq(healthFactor, type(uint256).max, "setup debt-free health factor");
    }

    function _borrow(address account_, uint128 amount_) internal returns (uint48 maturity) {
        vm.prank(account_);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            _USDS,
            amount_,
            account_,
            account_,
            type(uint256).max,
            address(0)
        );
        assertEq(_ohm.balanceOf(account_), amount_, "setup borrowed principal");
        assertGt(result.fee, 0, "setup borrow fee");
        assertEq(result.resultingDebtOhm, amount_, "setup resulting debt");
        assertGt(result.maturity, block.timestamp, "setup maturity");
        // For 4_000e18 collateral and 100e9 debt, the pinned-price working shown in
        // test_gasSnapshot_borrow_first yields health = 1_691_477_991_522_409_896.
        assertEq(result.resultingHealthFactor, _HEALTH_AFTER_BORROW, "setup health factor");
        return result.maturity;
    }

    function _assertGasRecorded(uint256 gasUsed_) internal pure {
        assertGt(gasUsed_, 0, "gas snapshot should record a positive value");
    }
}

contract BurnerLoansFreshPriceCacheForkGasTest is BurnerLoansLivePriceForkGasTest {
    uint48 internal constant _MAX_CACHE_AGE = 1 days;

    PriceCache internal _priceCache;

    function setUp() public override {
        super.setUp();

        _priceCache = new PriceCache(_kernel, _price.decimals(), "USD");
        address kernelExecutor = _kernel.executor();
        vm.prank(kernelExecutor);
        _kernel.executeAction(Actions.ActivatePolicy, address(_priceCache));

        _priceCache.enable("");
        _risk.setPriceCache(address(_priceCache));
        _risk.setPriceCacheMaxAge(_MAX_CACHE_AGE);
        _priceCache.cachePrice(_OHM, _USDS);
    }

    function _snapshotName(string memory action_) internal pure override returns (string memory) {
        return string.concat("BurnerLoans.freshPriceCache.", action_);
    }
}
// forge-lint: disable-end(multi-contract-file)
