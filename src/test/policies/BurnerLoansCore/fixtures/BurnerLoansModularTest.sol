// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Libraries
import {BL_COLLATERAL_POLICY_ROLE, BL_DEBT_POLICY_ROLE, BL_LIQUIDATION_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";
import {ADMIN_ROLE, DEPOSIT_OPERATOR_ROLE, BURNER_LOANS_INVENTORY_PROVIDER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusFixedTermLoan} from "src/modules/FLOAN/OlympusFixedTermLoan.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {BurnerLoansCollateral} from "src/policies/burnerloans/BurnerLoansCollateral.sol";
import {BurnerLoansConfig} from "src/policies/burnerloans/BurnerLoansConfig.sol";
import {BurnerLoansCore} from "src/policies/burnerloans/BurnerLoansCore.sol";
import {BurnerLoansPayout} from "src/policies/burnerloans/BurnerLoansPayout.sol";
import {BurnerLoansDebt} from "src/policies/burnerloans/BurnerLoansDebt.sol";
import {BurnerLoansInventory} from "src/policies/burnerloans/BurnerLoansInventory.sol";
import {BurnerLoansLens} from "src/policies/burnerloans/BurnerLoansLens.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";
import {BurnerLoansSeize} from "src/policies/burnerloans/BurnerLoansSeize.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockBackingOracle} from "src/test/mocks/MockBackingOracle.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";

/// @notice Real accounting fixture adapted from the existing Burner Loans spike checks.
/// @dev No legacy contract or composite is part of this deployment graph.
abstract contract BurnerLoansModularTest is Test {
    Kernel internal _kernel;
    RolesAdmin internal _rolesAdmin;
    OlympusRoles internal _roles;
    address internal _inventoryConfigurator = address(0x1C0F1C);
    OlympusFixedTermLoan internal _floan;
    BurnerLoansCore internal _core;
    BurnerLoansPayout internal _payout;
    BurnerLoansInventory internal _inventory;
    BurnerLoansConfig internal _config;
    BurnerLoansCollateral internal _collateral;
    BurnerLoansDebt internal _debt;
    BurnerLoansSeize internal _liquidation;
    BurnerLoansRisk internal _risk;
    BurnerLoansLens internal _lens;
    DepositManager internal _depositManager;
    MockPrice internal _price;
    MockERC20 internal _ohm;
    MockERC20 internal _asset;
    address internal _borrower = address(0xA11CE);
    address internal _recipient = address(0xB0B);

    function setUp() public virtual {
        _kernel = new Kernel();
        _ohm = new MockERC20("OHM", "OHM", 9);
        _asset = new MockERC20("USDS", "USDS", 6);
        _floan = new OlympusFixedTermLoan(_kernel);
        _roles = new OlympusRoles(_kernel);
        _price = new MockPrice(_kernel, 18, 8 hours);
        _rolesAdmin = new RolesAdmin(_kernel);
        _depositManager = new DepositManager(address(_kernel), address(new ReceiptTokenManager()));
        _core = new BurnerLoansCore(_kernel, IERC20(address(_ohm)), _depositManager);
        _payout = new BurnerLoansPayout(_kernel, address(_core));
        _inventory = new BurnerLoansInventory(_kernel, IERC20(address(_ohm)), address(_core));
        _config = new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
        MockBackingOracle oracle = new MockBackingOracle(_kernel, 1e18);
        _kernel.executeAction(Actions.ActivatePolicy, address(oracle));
        _risk = new BurnerLoansRisk(
            _kernel,
            IERC20(address(_ohm)),
            address(oracle),
            address(0),
            0,
            address(_core)
        );
        _lens = new BurnerLoansLens(address(_core));
        _collateral = new BurnerLoansCollateral(_kernel, _core);
        _debt = new BurnerLoansDebt(_kernel, _core);
        _liquidation = new BurnerLoansSeize(_kernel, _core);
        _kernel.executeAction(Actions.InstallModule, address(_floan));
        _kernel.executeAction(
            Actions.InstallModule,
            address(new OlympusMinter(_kernel, address(_ohm)))
        );
        _kernel.executeAction(Actions.InstallModule, address(_roles));
        _kernel.executeAction(Actions.InstallModule, address(new OlympusTreasury(_kernel)));
        _kernel.executeAction(Actions.InstallModule, address(_price));
        _kernel.executeAction(Actions.ActivatePolicy, address(_rolesAdmin));
        _kernel.executeAction(Actions.ActivatePolicy, address(_depositManager));
        _kernel.executeAction(Actions.ActivatePolicy, address(_risk));
        _kernel.executeAction(Actions.ActivatePolicy, address(_core));
        _kernel.executeAction(Actions.ActivatePolicy, address(_payout));
        _kernel.executeAction(Actions.ActivatePolicy, address(_inventory));
        _kernel.executeAction(Actions.ActivatePolicy, address(_config));
        _kernel.executeAction(Actions.ActivatePolicy, address(_collateral));
        _kernel.executeAction(Actions.ActivatePolicy, address(_debt));
        _kernel.executeAction(Actions.ActivatePolicy, address(_liquidation));
        _rolesAdmin.grantRole(ADMIN_ROLE, address(this));
        _rolesAdmin.grantRole("manager", address(this));
        _rolesAdmin.grantRole(DEPOSIT_OPERATOR_ROLE, address(_core));
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, address(_collateral));
        _rolesAdmin.grantRole(BL_DEBT_POLICY_ROLE, address(_debt));
        _rolesAdmin.grantRole(BL_LIQUIDATION_POLICY_ROLE, address(_liquidation));
        _core.setConfigOperator(address(_config));
        _inventory.enable("");
        _payout.enable("");
        _core.setInventory(address(_inventory));
        _inventory.setConfigOperator(_inventoryConfigurator);
        _core.setPayout(address(_payout));
        _risk.setConfigOperator(address(_config));
        _risk.enable("");
        _core.setRisk(address(_risk));
        IEnabler(address(_depositManager)).enable("");
        _core.enable("");
        _config.enable("");
        _collateral.enable("");
        _debt.enable("");
        _liquidation.enable("");
        _depositManager.setOperatorName(address(_core), "brn");
        _price.setPrice(address(_ohm), 1e18);
        _price.setPrice(address(_asset), 1e18);
        _admit(address(_asset));
        _inventory.setGlobalDebtCap(100_000e9);
        _asset.mint(_borrower, 10_000e6);
        vm.prank(_borrower);
        _asset.approve(address(_core), type(uint256).max);
    }

    function _admit(address token_) internal {
        _depositManager.addAsset(IERC20(token_), IERC4626(address(0)), type(uint256).max, 0);
        _depositManager.addAssetPeriod(
            IERC20(token_),
            LoanParameters._DEPOSIT_PERIOD,
            address(_core)
        );
        _config.addAsset(
            token_,
            100_000e9,
            IBurnerLoansRisk.AssetRiskConfigInput(8500, 12500, 100, 30 days, 90 days, 1000e6),
            IBurnerLoansRisk.AssetFeeConfig(25, 8000, 100, 900),
            false
        );
    }

    modifier givenDebtBearingPosition() {
        vm.startPrank(_borrower);
        _collateral.depositCollateral(address(_asset), 2000e6, _borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 100e6, address(0));
        vm.stopPrank();
        _;
    }

    /// @dev Registers and funds a previously unregistered Inventory provider for one test fixture.
    function _supplyInventory(address provider_, uint128 amount_) internal {
        _rolesAdmin.grantRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE, provider_);
        _ohm.mint(provider_, amount_);
        vm.startPrank(provider_);
        _ohm.approve(address(_inventory), amount_);
        _inventory.supply(amount_);
        vm.stopPrank();
    }

    function _referralReservesDigest(address asset_) internal view returns (bytes32) {
        address[] memory recipients = _payout.getPendingReferralRecipients(asset_);
        uint256[] memory amounts = new uint256[](recipients.length);
        for (uint256 i; i < recipients.length; ++i) {
            amounts[i] = _payout.pendingReferralFee(asset_, recipients[i]);
        }
        return keccak256(abi.encode(recipients, amounts));
    }
}
