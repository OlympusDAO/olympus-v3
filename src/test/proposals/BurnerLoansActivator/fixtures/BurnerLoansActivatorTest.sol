// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

// Interfaces
import {IERC20 as OZIERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IBurnerLoansActivator} from "src/proposals/interfaces/IBurnerLoansActivator.sol";

// Libraries
import {BL_COLLATERAL_POLICY_ROLE, BL_DEBT_POLICY_ROLE, BL_LIQUIDATION_POLICY_ROLE, BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE, BURNER_LOANS_SEIZER_ROLE, DEPOSIT_OPERATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansDeployHarness} from "./BurnerLoansDeployHarness.sol";
import {Test} from "@forge-std-1.16.2/Test.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";
import {PriceConfigv2} from "src/policies/price/PriceConfig.v2.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {BurnerLoansActivator} from "src/proposals/BurnerLoansActivator.sol";
import {MockPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockPeriodicTask.sol";
import {MockPeriodicTaskManager} from "src/test/bases/PeriodicTaskManager/MockPeriodicTaskManager.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockBackingOracle} from "src/test/mocks/MockBackingOracle.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";

/// @dev Real Burner Loans policies and custody, with a local price module and periodic-task manager.
abstract contract BurnerLoansActivatorTest is Test {
    Kernel internal _kernel;
    OlympusRoles internal _roles;
    RolesAdmin internal _rolesAdmin;
    MockERC20 internal _ohm;
    MockERC20 internal _usds;
    MockERC20 internal _usde;
    MockERC4626 internal _susds;
    MockERC4626 internal _susde;
    MockBackingOracle internal _oracle;
    MockPrice internal _price;
    MockPeriodicTaskManager internal _heart;
    MockPeriodicTask internal _existingTask;
    BurnerLoansDeployHarness internal _deployer;
    BurnerLoansActivator internal _activator;
    IBurnerLoansActivator.Deployment internal _graph;
    address internal _timelock = address(0x0C6);

    // Fixture setup deploys and activates the finite saved launch graph through trusted helpers.
    // forge-lint: disable-next-item(calls-loop)
    function setUp() public virtual {
        _kernel = new Kernel();
        _roles = new OlympusRoles(_kernel);
        _ohm = new MockERC20("OHM", "OHM", 9);
        _usds = new MockERC20("USDS", "USDS", 18);
        _usde = new MockERC20("USDe", "USDe", 18);
        _susds = new MockERC4626(OZIERC20(address(_usds)), "sUSDS", "sUSDS");
        _susde = new MockERC4626(OZIERC20(address(_usde)), "sUSDe", "sUSDe");
        _oracle = new MockBackingOracle(_kernel, 12e18);
        _price = new MockPrice(_kernel, 18, 8 hours);
        _heart = new MockPeriodicTaskManager(_kernel);
        _existingTask = new MockPeriodicTask();
        address deployerAddress = makeAddr("localDeployV3Harness");
        vm.etch(
            deployerAddress,
            vm.getDeployedCode("BurnerLoansDeployHarness.sol:BurnerLoansDeployHarness")
        );
        vm.allowCheatcodes(deployerAddress);
        _deployer = BurnerLoansDeployHarness(deployerAddress);
        string memory sequence = vm.readFile(
            "src/scripts/deploy/savedDeployments/burner_loans.json"
        );
        _deployer.loadSequence(sequence);
        _deployer.setDependency("olympus.Kernel", address(_kernel));
        _deployer.setDependency("olympus.legacy.OHM", address(_ohm));
        _deployer.setDependency("olympus.policies.BackingOracle", address(_oracle));
        _deployer.setDependency(
            "olympus.periphery.ReceiptTokenManager",
            address(new ReceiptTokenManager())
        );
        _deploySharedSequences();
        _deployer.loadSequence(sequence);
        string[] memory names = abi.decode(vm.parseJson(sequence, ".sequence[*].name"), (string[]));
        for (uint256 i; i < names.length; ++i) {
            if (keccak256(bytes(names[i])) == keccak256("BurnerLoansActivator")) continue;
            // Deployment results are recorded in the fixture registry and resolved below.
            // forge-lint: disable-next-line(unused-return)
            _deployer.deployNamed(names[i]);
        }
        _graph.kernel = address(_kernel);
        _graph.ohm = address(_ohm);
        _graph.floan = _deployer.resolve("olympus.modules.OlympusFixedTermLoan");
        _graph.depositManager = _policy("DepositManager");
        _graph.core = _policy("BurnerLoansCore");
        _graph.auth = _deployer.resolve("olympus.periphery.BurnerLoansAuth");
        _graph.config = _policy("BurnerLoansConfig");
        _graph.inventory = _policy("BurnerLoansInventory");
        _graph.payout = _policy("BurnerLoansPayout");
        _graph.risk = _policy("BurnerLoansRisk");
        _graph.collateral = _policy("BurnerLoansCollateral");
        _graph.debt = _policy("BurnerLoansDebt");
        _graph.seize = _policy("BurnerLoansSeize");
        _graph.lens = _deployer.resolve("olympus.periphery.BurnerLoansLens");
        _graph.seizerTask = _policy("BurnerLoansSeizerTask");
        _graph.yieldClaimerTask = _policy("BurnerLoansYieldClaimerTask");
        _graph.configTimelock = _policy("BurnerLoansConfigTimelock");
        _graph.riskTimelock = _policy("BurnerLoansRiskConfigTimelock");
        _graph.payoutTimelock = _policy("BurnerLoansPayoutConfigTimelock");
        _graph.inventoryTimelock = _policy("BurnerLoansInventoryConfigTimelock");
        _graph.priceConfig = address(new PriceConfigv2(_kernel));
        _graph.priceCache = _policy("PriceCache");
        _graph.revenueDistributor = _policy("RevenueDistributor");
        _graph.revenueDistributorTimelock = _policy("RevenueDistributorConfigTimelock");
        _graph.revenueDistributorTask = _policy("RevenueDistributorTask");
        _graph.heart = address(_heart);
        _graph.usds = address(_usds);
        _graph.usde = address(_usde);
        _graph.susds = address(_susds);
        _graph.susde = address(_susde);
        _graph.backingOracle = address(_oracle);
        _activator = new BurnerLoansActivator(_timelock, _graph);
        _rolesAdmin = new RolesAdmin(_kernel);
        _kernel.executeAction(Actions.InstallModule, address(_roles));
        _kernel.executeAction(
            Actions.InstallModule,
            address(new OlympusMinter(_kernel, address(_ohm)))
        );
        _kernel.executeAction(Actions.InstallModule, address(new OlympusTreasury(_kernel)));
        _kernel.executeAction(Actions.InstallModule, address(_price));
        _kernel.executeAction(Actions.InstallModule, _graph.floan);
        _kernel.executeAction(Actions.ActivatePolicy, address(_rolesAdmin));
        _kernel.executeAction(Actions.ActivatePolicy, _graph.priceConfig);
        _kernel.executeAction(Actions.ActivatePolicy, address(_oracle));
        address[] memory targets = _deployer.policies();
        for (uint256 i; i < targets.length; ++i)
            _kernel.executeAction(Actions.ActivatePolicy, targets[i]);
        _kernel.executeAction(Actions.ActivatePolicy, address(_heart));
        _rolesAdmin.grantRole(ADMIN_ROLE, address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, _timelock);
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_activator));
        _rolesAdmin.grantRole(DEPOSIT_OPERATOR_ROLE, _graph.core);
        _rolesAdmin.grantRole(BL_COLLATERAL_POLICY_ROLE, _graph.collateral);
        _rolesAdmin.grantRole(BL_DEBT_POLICY_ROLE, _graph.debt);
        _rolesAdmin.grantRole(BL_LIQUIDATION_POLICY_ROLE, _graph.seize);
        _rolesAdmin.grantRole(BL_YIELD_CLAIMER_ROLE, _graph.yieldClaimerTask);
        _rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, _graph.seizerTask);
        _heart.enable("");
        _heart.addPeriodicTask(address(_existingTask));
        _price.setPrice(address(_ohm), 20e18);
        _price.setPrice(address(_usds), 1e18);
        _price.setPrice(address(_usde), 1e18);
    }

    // Shared prerequisites use their own production deployment sequences.
    // forge-lint: disable-next-item(calls-loop)
    function _deploySharedSequences() private {
        string[3] memory files = [
            "deposit_manager_v1_1.json",
            "price_cache.json",
            "revenue_distributor.json"
        ];
        for (uint256 i; i < files.length; ++i) {
            string memory sequence = vm.readFile(
                string.concat("src/scripts/deploy/savedDeployments/", files[i])
            );
            _deployer.loadSequence(sequence);
            uint256 count = i < 2 ? 1 : 3;
            for (uint256 j; j < count; ++j) {
                string memory name = vm.parseJsonString(
                    sequence,
                    string.concat(".sequence[", vm.toString(j), "].name")
                );
                // The dispatcher retains each result for subsequent dependency resolution.
                // forge-lint: disable-next-line(unused-return)
                (address deployed, ) = _deployer.deployNamed(name);
                assertLe(deployed.code.length, 24_576, "Shared sequence entry fits EIP-170");
            }
        }
    }

    // Registry lookups are used by finite deployment/activation fixture loops.
    // forge-lint: disable-next-item(calls-loop)
    function _policy(string memory name_) internal view returns (address) {
        return _deployer.resolve(string.concat("olympus.policies.", name_));
    }

    function _activate() internal {
        vm.prank(_timelock);
        _activator.activate();
    }
}
