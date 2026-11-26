// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracleConfigTimelock} from "src/policies/interfaces/IBackingOracleConfigTimelock.sol";
import {IOperator} from "src/policies/interfaces/IOperator.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";
import {IReserveMigrator} from "src/policies/interfaces/IReserveMigrator.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IYieldRepo} from "src/policies/interfaces/IYieldRepo.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansConfigTimelock.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansInventoryConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansPayoutConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansPayoutConfigTimelock.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansRiskConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansRiskConfigTimelock.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";
import {IBurnerLoansYieldClaimerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaimerTask.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IBurnerLoansActivator} from "src/proposals/helpers/interfaces/IBurnerLoansActivator.sol";

// Libraries
import {toSubKeycode} from "src/Submodules.sol";
import {SafeCall} from "src/libraries/SafeCall.sol";
import {BL_COLLATERAL_POLICY_ROLE, BL_DEBT_POLICY_ROLE, BL_LIQUIDATION_POLICY_ROLE, BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE, BURNER_LOANS_SEIZER_ROLE, DEPOSIT_OPERATOR_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {SimplePriceFeedStrategy} from "src/modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RevenueDistributorTask} from "src/policies/RevenueDistributorTask.sol";
import {Kernel, Module, Policy, toKeycode} from "src/Kernel.sol";
import {BurnerLoansSeizerTask} from "src/policies/burnerloans/BurnerLoansSeizerTask.sol";

/// @notice Executes the reviewed Burner Loans launch using temporary governance authority.
/// @dev Deployment, module installation and policy activation precede this contract's one-use launch.
///      Governance populates the separately deployed backing oracle and admits missing USDe
///      PRICE support before activation; existing OHM and USDS price configurations are retained.
contract BurnerLoansActivator is IBurnerLoansActivator, IERC165 {
    /// @dev OHM principal uses 9 decimals; both collateral assets and vault accounting use 18.
    uint128 internal constant ASSET_DEBT_CAP = 50_000e9; // 50,000 OHM per market.
    uint128 internal constant GLOBAL_DEBT_CAP = 100_000e9; // 100,000 OHM across all markets.
    uint256 internal constant DEPOSIT_CAP = 10_000_000e18; // 10 million collateral tokens.
    uint256 internal constant MINIMUM_DEPOSIT = 1e18; // One collateral token.
    uint8 internal constant DEPOSIT_PERIOD = 1; // One month.
    string internal constant OPERATOR_NAME = "brn";

    uint48 internal constant PRICE_CACHE_MAX_AGE = 300; // 300 seconds (five minutes).
    uint16 internal constant MAX_LTV_BPS = 8500; // 85% maximum loan-to-value.
    uint16 internal constant BACKING_MULTIPLIER_BPS = 12500; // 125% of OHM backing.
    uint16 internal constant KEEPER_REWARD_BPS = 100; // 1% of seized collateral.
    uint16 internal constant FEE_KINK_BPS = 8000; // 80% utilization.
    uint48 internal constant TERM_LENGTH = 30 days;
    uint48 internal constant MATURITY_HORIZON = 90 days;
    uint128 internal constant MAX_KEEPER_REWARD = 100e18; // 100 collateral tokens.
    uint16 internal constant SEIZER_CHECK_LIMIT = 100; // Check at most 100 borrowers per run.
    uint8 internal constant SEIZER_SEIZE_LIMIT = 25; // Seize at most 25 borrowers per run.
    uint32 internal constant SEIZER_GAS_LIMIT = 10_000_000; // Ten million execution gas.
    uint32 internal constant TASK_GAS_LIMIT = 1_000_000; // One million execution gas per task.
    uint32 internal constant TASK_MINIMUM_GAS = 250_000; // Minimum gas before attempting a task.
    uint32 internal constant TASK_GAS_RESERVE = 100_000; // Gas retained by each task wrapper.
    uint256 internal constant SEIZER_TASK_INDEX = 3; // After custody and reserve preparation.
    uint256 internal constant YIELD_TASK_INDEX = 4; // Collect yield after seizure.
    uint256 internal constant DISTRIBUTOR_TASK_INDEX = 5; // Distribute revenue before Operator.
    uint16 internal constant BASELINE_HEART_TASK_COUNT = 6;
    // Two offsets, two lengths, and one word per task and selector.
    uint16 internal constant BASELINE_HEART_TASKS_RETURN_BYTES =
        32 * (4 + 2 * BASELINE_HEART_TASK_COUNT);
    uint256 internal constant REQUIRED_ROLE_COUNT = 8;
    uint256 internal constant USDE_FEED_COUNT = 3;
    uint8 internal constant COLLATERAL_DECIMALS = 18;
    address internal constant USDE_USD_FEED = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;
    address internal constant USDE_REDSTONE_FEED = 0xbC5FBcf58CeAEa19D523aBc76515b9AEFb5cfd58;
    address internal constant USDE_API3_FEED = 0x22a35f4BDD167EAF7Cbf0C0Dc0C2001071714cc6;
    uint48 internal constant USDE_API3_MAX_AGE = 25 hours; // 24-hour heartbeat plus one-hour grace.
    uint48 internal constant USDE_FEED_MAX_AGE = 1 days; // 86,400 seconds.
    uint256 internal constant USDE_EXPECTED_PRICE = 1e18; // $1 in 18-decimal PRICE units.
    uint16 internal constant USDE_PRICE_TOLERANCE_BPS = 100; // 1% admission tolerance.
    uint16 internal constant USDE_PRICE_DEVIATION_BPS = 100; // Exclude feeds more than 1% from the benchmark.
    uint256 internal constant INITIAL_BACKING = 1199e16; // $11.99 per OHM, 18 decimals.

    /// @inheritdoc IBurnerLoansActivator
    // Keep the immutable public getter named timelock() as declared by the interface.
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    address public immutable override timelock;
    /// @inheritdoc IBurnerLoansActivator
    bool public override isActivated;
    address internal immutable _KERNEL;
    address internal immutable _OHM;
    address internal immutable _FLOAN;
    address internal immutable _DEPOSIT_MANAGER;
    address internal immutable _DEPOSIT_MANAGER_TIMELOCK;
    address internal immutable _CORE;
    address internal immutable _AUTH;
    address internal immutable _CONFIG;
    address internal immutable _INVENTORY;
    address internal immutable _PAYOUT;
    address internal immutable _RISK;
    address internal immutable _COLLATERAL;
    address internal immutable _DEBT;
    address internal immutable _SEIZE;
    address internal immutable _LENS;
    address internal immutable _SEIZER_TASK;
    address internal immutable _YIELD_CLAIMER_TASK;
    address internal immutable _CONFIG_TIMELOCK;
    address internal immutable _RISK_TIMELOCK;
    address internal immutable _PAYOUT_TIMELOCK;
    address internal immutable _INVENTORY_TIMELOCK;
    address internal immutable _PRICE_CONFIG;
    address internal immutable _PRICE_CACHE;
    address internal immutable _REVENUE_DISTRIBUTOR;
    address internal immutable _REVENUE_DISTRIBUTOR_TIMELOCK;
    address internal immutable _REVENUE_DISTRIBUTOR_TASK;
    address internal immutable _HEART;
    bytes32 internal immutable _HEART_TASKS_HASH;
    address internal immutable _USDS;
    address internal immutable _USDE;
    address internal immutable _SUSDS;
    address internal immutable _SUSDE;
    address internal immutable _BACKING_ORACLE;
    address internal immutable _BACKING_ORACLE_TIMELOCK;

    /// @notice Binds the already-deployed graph without requiring it to be installed or active yet.
    /// @dev Reverts for a zero timelock, missing code, inconsistent Kernel/Core identities or invalid vault bindings.
    /// @param timelock_ Sole governance executor allowed to launch.
    /// @param deployment_ Reviewed deployment graph and external asset/oracle dependencies.
    constructor(address timelock_, Deployment memory deployment_) {
        if (timelock_ == address(0)) revert BurnerLoansActivator_InvalidDeployment(timelock_);
        timelock = timelock_;
        _KERNEL = deployment_.kernel;
        _OHM = deployment_.ohm;
        _FLOAN = deployment_.floan;
        _DEPOSIT_MANAGER = deployment_.depositManager;
        _DEPOSIT_MANAGER_TIMELOCK = deployment_.depositManagerTimelock;
        _CORE = deployment_.core;
        _AUTH = deployment_.auth;
        _CONFIG = deployment_.config;
        _INVENTORY = deployment_.inventory;
        _PAYOUT = deployment_.payout;
        _RISK = deployment_.risk;
        _COLLATERAL = deployment_.collateral;
        _DEBT = deployment_.debt;
        _SEIZE = deployment_.seize;
        _LENS = deployment_.lens;
        _SEIZER_TASK = deployment_.seizerTask;
        _YIELD_CLAIMER_TASK = deployment_.yieldClaimerTask;
        _CONFIG_TIMELOCK = deployment_.configTimelock;
        _RISK_TIMELOCK = deployment_.riskTimelock;
        _PAYOUT_TIMELOCK = deployment_.payoutTimelock;
        _INVENTORY_TIMELOCK = deployment_.inventoryTimelock;
        _PRICE_CONFIG = deployment_.priceConfig;
        _PRICE_CACHE = deployment_.priceCache;
        _REVENUE_DISTRIBUTOR = deployment_.revenueDistributor;
        _REVENUE_DISTRIBUTOR_TIMELOCK = deployment_.revenueDistributorTimelock;
        _REVENUE_DISTRIBUTOR_TASK = deployment_.revenueDistributorTask;
        _HEART = deployment_.heart;
        _USDS = deployment_.usds;
        _USDE = deployment_.usde;
        _SUSDS = deployment_.susds;
        _SUSDE = deployment_.susde;
        _BACKING_ORACLE = deployment_.backingOracle;
        _BACKING_ORACLE_TIMELOCK = deployment_.backingOracleTimelock;
        _validateBindings();
        // Reviewed mainnet baseline at block 25,973,712. Zero selects execute().
        address[] memory tasks = new address[](BASELINE_HEART_TASK_COUNT);
        tasks[0] = 0xEBDe552D851DD6Dfd3D360C596D3F4aF6e5F9678; // ConvertibleDepositFacility
        tasks[1] = 0x986b99579BEc7B990331474b66CcDB94Fa2419F5; // ReserveMigrator
        tasks[2] = 0xcA6cd4F0a0033f8C20cF68d6dF277E7001a386f9; // ReserveWrapper
        tasks[3] = 0x6417F206a0a6628Da136C0Faa39026d0134D2b52; // Operator
        tasks[4] = 0x271e35a8555a62F6bA76508E85dfD76D580B0692; // YieldRepurchaseFacility
        tasks[5] = 0xA61b846D5D8b757e3d541E0e4F80390E28f0B6Ff; // EmissionManager
        bytes4[] memory selectors = new bytes4[](BASELINE_HEART_TASK_COUNT);
        selectors[1] = IReserveMigrator.migrate.selector;
        selectors[3] = IOperator.operate.selector;
        selectors[4] = IYieldRepo.endEpoch.selector;
        _HEART_TASKS_HASH = keccak256(abi.encode(tasks, selectors));
    }

    /// @dev Enumerates policies used by on-chain launch checks.
    function _policies() internal view returns (address[] memory targets) {
        targets = new address[](22);
        targets[0] = _DEPOSIT_MANAGER;
        targets[1] = _CORE;
        targets[2] = _CONFIG;
        targets[3] = _INVENTORY;
        targets[4] = _PAYOUT;
        targets[5] = _RISK;
        targets[6] = _COLLATERAL;
        targets[7] = _DEBT;
        targets[8] = _SEIZE;
        targets[9] = _SEIZER_TASK;
        targets[10] = _YIELD_CLAIMER_TASK;
        targets[11] = _CONFIG_TIMELOCK;
        targets[12] = _RISK_TIMELOCK;
        targets[13] = _PAYOUT_TIMELOCK;
        targets[14] = _INVENTORY_TIMELOCK;
        targets[15] = _PRICE_CACHE;
        targets[16] = _REVENUE_DISTRIBUTOR;
        targets[17] = _REVENUE_DISTRIBUTOR_TASK;
        targets[18] = _REVENUE_DISTRIBUTOR_TIMELOCK;
        targets[19] = _BACKING_ORACLE;
        targets[20] = _BACKING_ORACLE_TIMELOCK;
        targets[21] = _DEPOSIT_MANAGER_TIMELOCK;
    }

    // Kernel activation alone does not initialize a policy. Require a fresh, disabled graph
    // so this fixed launch cannot overwrite configuration from an earlier enablement.
    // forge-lint: disable-next-item(calls-loop,require-revert-in-loop)
    function _validatePrerequisites() private view {
        // Recheck deployment identities at execution: the proposal may wait in governance.
        _validateBindings();
        Kernel installedKernel = Kernel(_KERNEL);
        address[] memory targets = _policies();
        // Every launch policy, including cache, distributor and tasks, must be Kernel-active
        // but never enabled. This prevents overwriting an already initialized configuration.
        for (uint256 i; i < targets.length; ++i) {
            if (
                !installedKernel.isPolicyActive(Policy(targets[i])) ||
                IEnabler(targets[i]).isEnabled() ||
                IEnablerV2(targets[i]).lastTransitionAt() != 0
            ) revert BurnerLoansActivator_InvalidPrerequisite(targets[i]);
        }
        // Heart must already be operational so the launch can extend its existing task list.
        address heart = _HEART;
        if (!installedKernel.isPolicyActive(Policy(heart)) || !IEnabler(heart).isEnabled())
            revert BurnerLoansActivator_InvalidPrerequisite(heart);
        // Copy one extra byte so trailing data cannot pass the exact reviewed payload hash.
        (bool success, bytes memory tasks) = SafeCall.safeStaticCall(
            heart,
            gasleft(),
            BASELINE_HEART_TASKS_RETURN_BYTES + 1,
            abi.encodeCall(IPeriodicTaskManager.getPeriodicTasks, ())
        );
        if (!success || keccak256(tasks) != _HEART_TASKS_HASH)
            revert BurnerLoansActivator_InvalidPrerequisite(heart);
        // PRICE admission needs the existing configuration policy active and enabled even
        // when USDe is already registered and no addAsset call would otherwise exercise it.
        if (
            !installedKernel.isPolicyActive(Policy(_PRICE_CONFIG)) ||
            !IEnabler(_PRICE_CONFIG).isEnabled()
        ) revert BurnerLoansActivator_InvalidPrerequisite(_PRICE_CONFIG);
        // The installed loan ledger must be the exact module fixed in Core's deployment.
        if (
            address(installedKernel.getModuleForKeycode(toKeycode("FLOAN"))) != _FLOAN ||
            IBurnerLoansCore(_CORE).floan() != _FLOAN
        ) revert BurnerLoansActivator_InvalidPrerequisite(_FLOAN);
        // Only an empty market/custody deployment is eligible for these fixed launch settings.
        if (
            IBurnerLoansCore(_CORE).getAssetCount() != 0 ||
            IDepositManager(_DEPOSIT_MANAGER).getConfiguredAssets().length != 0
        ) revert BurnerLoansActivator_InvalidPrerequisite(_CORE);
        // OHM and USDS retain their reviewed PRICE configurations; launch adds only missing USDe.
        IPRICEv2 price = IPRICEv2(address(installedKernel.getModuleForKeycode(toKeycode("PRICE"))));
        if (!price.isAssetApproved(_OHM) || !price.isAssetApproved(_USDS))
            revert BurnerLoansActivator_InvalidPrerequisite(address(price));
    }

    /// @inheritdoc IBurnerLoansActivator
    /// @dev Reverts for any caller other than the bound timelock, replay or failed prerequisite/target call.
    ///      The one-use flag and every target mutation roll back if any later launch operation fails.
    function activate() external {
        if (msg.sender != timelock) revert BurnerLoansActivator_NotTimelock(msg.sender);
        if (isActivated) revert BurnerLoansActivator_AlreadyActivated();
        // Set the replay guard before any external call. A later failure reverts this flag
        // together with all configuration; the proposal then also rolls back the ADMIN grant.
        isActivated = true;
        _validatePrerequisites();
        _validateRoles();
        // PRICE admission precedes custody and market registration, which consume its support.
        _addUsdeToPrice();
        _enableAndBind();
        // USDS supports synchronous underlying withdrawals; USDe must exit as sUSDe shares.
        // Custody and lending use the same output mode for each market.
        _configureAsset(_USDS, _SUSDS, false);
        _configureAsset(_USDE, _SUSDE, true);
        IBurnerLoansInventory(_INVENTORY).setGlobalDebtCap(GLOBAL_DEBT_CAP);
        // Add automation only after both markets and their funding capacity are ready.
        _configureTasks();
        // The OCG proposal revokes our temporary ADMIN after this call returns. No operational
        // role is granted to this helper, and isActivated prevents it from launching again.
        emit Activated(msg.sender);
    }

    // All settlement, custody and automation authority must be installed before any launch mutation.
    // forge-lint: disable-next-item(calls-loop,require-revert-in-loop)
    function _validateRoles() private view {
        ROLESv1 roles = ROLESv1(address(Kernel(_KERNEL).getModuleForKeycode(toKeycode("ROLES"))));
        address[REQUIRED_ROLE_COUNT] memory holders = [
            address(this),
            _CORE,
            _COLLATERAL,
            _DEBT,
            _SEIZE,
            _YIELD_CLAIMER_TASK,
            _SEIZER_TASK,
            _HEART
        ];
        bytes32[REQUIRED_ROLE_COUNT] memory required = [
            ADMIN_ROLE,
            DEPOSIT_OPERATOR_ROLE,
            BL_COLLATERAL_POLICY_ROLE,
            BL_DEBT_POLICY_ROLE,
            BL_LIQUIDATION_POLICY_ROLE,
            BL_YIELD_CLAIMER_ROLE,
            BURNER_LOANS_SEIZER_ROLE,
            HEART_ROLE
        ];
        for (uint256 i; i < holders.length; ++i) {
            if (!roles.hasRole(holders[i], required[i]))
                revert BurnerLoansActivator_InvalidPrerequisite(holders[i]);
        }
    }

    function _addUsdeToPrice() private {
        IPRICEv2 price = IPRICEv2(address(Kernel(_KERNEL).getModuleForKeycode(toKeycode("PRICE"))));
        // Preserve a prior admission. Adding a new feed validates its live answer; neither
        // path warms PriceCache, whose pairs refresh when lending operations need them.
        if (price.isAssetApproved(_USDE)) return;
        address[USDE_FEED_COUNT] memory sources = [
            USDE_USD_FEED,
            USDE_REDSTONE_FEED,
            USDE_API3_FEED
        ];
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](USDE_FEED_COUNT);
        IPriceConfigv2.PriceFeedExpectation[]
            memory expectations = new IPriceConfigv2.PriceFeedExpectation[](USDE_FEED_COUNT);
        for (uint256 i; i < sources.length; ++i) {
            feeds[i] = IPRICEv2.Component({
                target: toSubKeycode("PRICE.CHAINLINK"), // All three providers expose the Chainlink ABI.
                selector: ChainlinkPriceFeeds.getOneFeedPrice.selector,
                params: abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams({
                        feed: AggregatorV2V3Interface(sources[i]),
                        updateThreshold: i == 2 ? USDE_API3_MAX_AGE : USDE_FEED_MAX_AGE
                    })
                )
            });
            expectations[i] = IPriceConfigv2.PriceFeedExpectation({
                expectedPrice: USDE_EXPECTED_PRICE,
                toleranceBps: USDE_PRICE_TOLERANCE_BPS
            });
        }
        // Match USDS: discard failed/outlying sources, then average at least two valid prices.
        // Prices use 18 decimals; the deviation parameter is 100 basis points (1%).
        IPRICEv2.Component memory strategy = IPRICEv2.Component({
            target: toSubKeycode("PRICE.SIMPLESTRATEGY"),
            selector: SimplePriceFeedStrategy.getAveragePriceExcludingDeviations.selector,
            params: abi.encode(USDE_PRICE_DEVIATION_BPS, true)
        });
        IPriceConfigv2(_PRICE_CONFIG).addAsset(
            _USDE, // Underlying collateral asset to price.
            false, // Do not store a moving average.
            false, // Do not use a moving average in price resolution.
            0, // Moving-average duration: unused, in seconds.
            0, // Last observation timestamp: no observation history is seeded.
            new uint256[](0), // No historical observations.
            strategy, // Strict average after excluding 1% deviations.
            feeds, // Independent Chainlink, RedStone and API3 USDe/USD feeds.
            expectations // Admission-time expected price and tolerance for that feed.
        );
    }

    function _enableAndBind() private {
        // Only governance ADMIN can choose the backing controller and initialize backing.
        // Risk must see a populated, enabled oracle before any lending service is enabled.
        IConfigOperator(_BACKING_ORACLE).setConfigOperator(_BACKING_ORACLE_TIMELOCK);
        IEnabler(_BACKING_ORACLE).enable(abi.encode(INITIAL_BACKING));
        IEnabler(_BACKING_ORACLE_TIMELOCK).enable("");
        // Bind operational services and their independent delayed configuration authorities.
        // Auth has no independent lifecycle or roles; selecting it installs Core authorization.
        IBurnerLoansCore(_CORE).setAuth(_AUTH);
        IConfigOperator(_CORE).setConfigOperator(_CONFIG);
        IConfigOperator(_RISK).setConfigOperator(_RISK_TIMELOCK);
        IConfigOperator(_INVENTORY).setConfigOperator(_INVENTORY_TIMELOCK);
        IConfigOperator(_PAYOUT).setConfigOperator(_PAYOUT_TIMELOCK);
        // Enable shared pricing and revenue routing before the lending services.
        IEnabler(_PRICE_CACHE).enable("");
        IEnabler(_REVENUE_DISTRIBUTOR).enable("");
        IConfigOperator(_REVENUE_DISTRIBUTOR).setConfigOperator(_REVENUE_DISTRIBUTOR_TIMELOCK);
        // Empty recipient routes and zero repurchase share allocate all receipts to Treasury.
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        IRevenueDistributor(_REVENUE_DISTRIBUTOR).setAssetRoutes(_USDS, 0, routes);
        IRevenueDistributor(_REVENUE_DISTRIBUTOR).setAssetRoutes(_SUSDS, 0, routes);
        IRevenueDistributor(_REVENUE_DISTRIBUTOR).setAssetRoutes(_USDE, 0, routes);
        IRevenueDistributor(_REVENUE_DISTRIBUTOR).setAssetRoutes(_SUSDE, 0, routes);
        // Enable custody and services before Core, then its action policies.
        IEnabler(_DEPOSIT_MANAGER).enable("");
        IConfigOperator(_DEPOSIT_MANAGER).setConfigOperator(_DEPOSIT_MANAGER_TIMELOCK);
        IEnabler(_INVENTORY).enable("");
        IEnabler(_PAYOUT).enable("");
        IEnabler(_RISK).enable("");
        IBurnerLoansRisk(_RISK).setPriceCache(_PRICE_CACHE);
        IBurnerLoansRisk(_RISK).setPriceCacheMaxAge(PRICE_CACHE_MAX_AGE);
        IBurnerLoansPayout(_PAYOUT).setRevenueDistributor(_REVENUE_DISTRIBUTOR);
        IBurnerLoansPayout(_PAYOUT).setSendFeesToDistributor(true);
        IBurnerLoansPayout(_PAYOUT).setSendYieldToDistributor(true);
        IBurnerLoansCore(_CORE).setInventory(_INVENTORY);
        IBurnerLoansCore(_CORE).setPayout(_PAYOUT);
        IBurnerLoansCore(_CORE).setRisk(_RISK);
        // Core's enable hook checks its selected services; actions can be enabled afterwards.
        IEnabler(_CORE).enable("");
        IEnabler(_CONFIG).enable("");
        IConfigOperator(_CONFIG).setConfigOperator(_CONFIG_TIMELOCK);
        IEnabler(_COLLATERAL).enable("");
        IEnabler(_DEBT).enable("");
        IEnabler(_SEIZE).enable("");
        IDepositManager(_DEPOSIT_MANAGER).setOperatorName(_CORE, OPERATOR_NAME);
    }

    // The receipt token ID returned by addAssetPeriod is not needed by the launch.
    // forge-lint: disable-next-item(unused-return)
    function _configureAsset(address asset_, address vault_, bool shares_) private {
        // Register shared custody first, then its Core-specific receipt period, then the
        // lending market. Config verifies this custody route when admitting the market
        // and stores originationsEnabled = true for the newly registered asset.
        IDepositManagerV1_1(_DEPOSIT_MANAGER).addAsset(
            IERC20(asset_), // Underlying token held on behalf of deposit operators.
            IERC4626(vault_), // Vault that receives the underlying deposits.
            DEPOSIT_CAP, // Aggregate credited-principal cap, in 18-decimal asset units.
            MINIMUM_DEPOSIT, // Minimum deposit, in 18-decimal asset units.
            shares_ // Require share withdrawals for sUSDe; allow underlying for sUSDS.
        );
        // Config admission below validates this registered period.
        IDepositManager(_DEPOSIT_MANAGER).addAssetPeriod(
            IERC20(asset_), // Collateral asset for the receipt-token route.
            DEPOSIT_PERIOD, // Deposit period, in months.
            _CORE // Operator whose deposits and liabilities use this route.
        );
        IBurnerLoansConfig(_CONFIG).addAsset(
            asset_, // Underlying collateral token for this lending market.
            ASSET_DEBT_CAP, // Maximum market principal, in 9-decimal OHM units.
            _riskConfig(), // LTV, backing, term and keeper-reward limits.
            _feeConfig(), // Zero-fee utilization curve at launch.
            shares_ // Match the withdrawal mode configured in custody above.
        );
    }

    function _configureTasks() private {
        // Arm each selected configuration timelock after its target has been enabled.
        IEnabler(_DEPOSIT_MANAGER_TIMELOCK).enable("");
        IEnabler(_CONFIG_TIMELOCK).enable("");
        IEnabler(_RISK_TIMELOCK).enable("");
        IEnabler(_PAYOUT_TIMELOCK).enable("");
        IEnabler(_INVENTORY_TIMELOCK).enable("");
        IEnabler(_REVENUE_DISTRIBUTOR_TIMELOCK).enable("");
        // Limit the keeper's scan to the two admitted markets and apply explicit gas budgets.
        IBurnerLoansSeizerTask(_SEIZER_TASK).addAsset(_USDS);
        IBurnerLoansSeizerTask(_SEIZER_TASK).addAsset(_USDE);
        IBurnerLoansSeizerTask(_SEIZER_TASK).setScanLimits(SEIZER_CHECK_LIMIT, SEIZER_SEIZE_LIMIT);
        IBurnerLoansSeizerTask(_SEIZER_TASK).setExecutionGasLimit(SEIZER_GAS_LIMIT);
        IBurnerLoansYieldClaimerTask(_YIELD_CLAIMER_TASK).setExecutionGasLimit(TASK_GAS_LIMIT);
        IBurnerLoansYieldClaimerTask(_YIELD_CLAIMER_TASK).setMinimumGasToAttempt(TASK_MINIMUM_GAS);
        IBurnerLoansYieldClaimerTask(_YIELD_CLAIMER_TASK).setGasReserve(TASK_GAS_RESERVE);
        IEnabler(_SEIZER_TASK).enable("");
        IEnabler(_YIELD_CLAIMER_TASK).enable("");
        RevenueDistributorTask(_REVENUE_DISTRIBUTOR_TASK).setExecutionGasLimit(TASK_GAS_LIMIT);
        RevenueDistributorTask(_REVENUE_DISTRIBUTOR_TASK).setMinimumGasToAttempt(TASK_MINIMUM_GAS);
        RevenueDistributorTask(_REVENUE_DISTRIBUTOR_TASK).setGasReserve(TASK_GAS_RESERVE);
        IEnabler(_REVENUE_DISTRIBUTOR_TASK).enable("");
        // New indexes 3/4/5: finish custody/reserve preparation, then seize defaults,
        // collect yield and distribute revenue immediately before Operator operates.
        // Mainnet baseline at block 25,973,712; existing selectors remain unchanged:
        // Task                            Existing index -> Revised index
        // ConvertibleDepositFacility                 0   -> 0
        // ReserveMigrator                            1   -> 1
        // ReserveWrapper                             2   -> 2
        // BurnerLoansSeizerTask                     new  -> 3
        // BurnerLoansYieldClaimerTask               new  -> 4
        // RevenueDistributorTask                   new  -> 5
        // Operator                                   3   -> 6
        // YieldRepurchaseFacility                    4   -> 7
        // EmissionManager                            5   -> 8
        IPeriodicTaskManager(_HEART).addPeriodicTaskAtIndex(
            _SEIZER_TASK, // Task to insert into Heart.
            bytes4(0), // Use its default execute() selector.
            SEIZER_TASK_INDEX // Insert here, shifting subsequent tasks one position right.
        );
        IPeriodicTaskManager(_HEART).addPeriodicTaskAtIndex(
            _YIELD_CLAIMER_TASK, // Task to insert into Heart.
            bytes4(0), // Use its default execute() selector.
            YIELD_TASK_INDEX // Insert here, shifting subsequent tasks one position right.
        );
        IPeriodicTaskManager(_HEART).addPeriodicTaskAtIndex(
            _REVENUE_DISTRIBUTOR_TASK, // Task to insert into Heart.
            bytes4(0), // Use its default execute() selector.
            DISTRIBUTOR_TASK_INDEX // Insert here, shifting subsequent tasks one position right.
        );
    }

    // The fixed launch graph requires each policy to report the bound Kernel.
    // forge-lint: disable-next-item(calls-loop)
    function _validateBindings() private view {
        _deployed(_KERNEL);
        _deployed(_OHM);
        _deployed(_FLOAN);
        _deployed(_LENS);
        _deployed(_AUTH);
        _deployed(_HEART);
        _deployed(_USDS);
        _deployed(_USDE);
        _deployed(_SUSDS);
        _deployed(_SUSDE);
        _deployed(_PRICE_CONFIG);
        _bound(address(Policy(_PRICE_CONFIG).kernel()) == _KERNEL, _PRICE_CONFIG);
        address[] memory targets = _policies();
        for (uint256 i; i < targets.length; ++i) {
            _deployed(targets[i]);
            _bound(address(Policy(targets[i]).kernel()) == _KERNEL, targets[i]);
        }
        _bound(
            address(IBackingOracleConfigTimelock(_BACKING_ORACLE_TIMELOCK).backingOracle()) ==
                _BACKING_ORACLE,
            _BACKING_ORACLE_TIMELOCK
        );
        _bound(
            address(IDepositManagerConfigTimelock(_DEPOSIT_MANAGER_TIMELOCK).depositManager()) ==
                _DEPOSIT_MANAGER,
            _DEPOSIT_MANAGER_TIMELOCK
        );
        _bound(address(Policy(_HEART).kernel()) == _KERNEL, _HEART);
        _bound(
            RevenueDistributorTask(_REVENUE_DISTRIBUTOR_TASK).distributor() == _REVENUE_DISTRIBUTOR,
            _REVENUE_DISTRIBUTOR_TASK
        );
        _bound(
            address(
                IRevenueDistributorConfigTimelock(_REVENUE_DISTRIBUTOR_TIMELOCK).distributor()
            ) == _REVENUE_DISTRIBUTOR,
            _REVENUE_DISTRIBUTOR_TIMELOCK
        );
        _bound(address(Module(_FLOAN).kernel()) == _KERNEL, _FLOAN);
        _bound(
            IBurnerLoansCore(_CORE).ohm() == _OHM &&
                IBurnerLoansCore(_CORE).depositManager() == _DEPOSIT_MANAGER,
            _CORE
        );
        _bound(IBurnerLoansInventory(_INVENTORY).ohm() == _OHM, _INVENTORY);
        _bound(
            IBurnerLoansRisk(_RISK).ohm() == _OHM &&
                IBurnerLoansRisk(_RISK).backingOracle() == _BACKING_ORACLE,
            _RISK
        );
        address[10] memory coreBound = [
            _AUTH,
            _CONFIG,
            _INVENTORY,
            _PAYOUT,
            _RISK,
            _COLLATERAL,
            _DEBT,
            _SEIZE,
            _LENS,
            _YIELD_CLAIMER_TASK
        ];
        for (uint256 i; i < coreBound.length; ++i) {
            _bound(IBurnerLoansCoreBound(coreBound[i]).core() == _CORE, coreBound[i]);
        }
        _bound(
            address(IBurnerLoansConfigTimelock(_CONFIG_TIMELOCK).burnerLoans()) == _CONFIG,
            _CONFIG_TIMELOCK
        );
        _bound(
            address(IBurnerLoansRiskConfigTimelock(_RISK_TIMELOCK).risk()) == _RISK,
            _RISK_TIMELOCK
        );
        _bound(
            address(IBurnerLoansPayoutConfigTimelock(_PAYOUT_TIMELOCK).payout()) == _PAYOUT,
            _PAYOUT_TIMELOCK
        );
        _bound(
            address(IBurnerLoansInventoryConfigTimelock(_INVENTORY_TIMELOCK).inventory()) ==
                _INVENTORY,
            _INVENTORY_TIMELOCK
        );
        _bound(address(IBurnerLoansSeizerTask(_SEIZER_TASK).seize()) == _SEIZE, _SEIZER_TASK);
        _bound(BurnerLoansSeizerTask(_SEIZER_TASK).lens() == _LENS, _SEIZER_TASK);
        _bound(
            IERC4626(_SUSDS).asset() == _USDS &&
                IERC4626(_SUSDE).asset() == _USDE &&
                _USDS != _USDE,
            _DEPOSIT_MANAGER
        );
        _bound(
            IERC20(_OHM).decimals() == 9 &&
                IERC20(_USDS).decimals() == COLLATERAL_DECIMALS &&
                IERC20(_USDE).decimals() == COLLATERAL_DECIMALS,
            _CORE
        );
    }

    function _riskConfig() private pure returns (IBurnerLoansRisk.AssetRiskConfigInput memory) {
        return
            IBurnerLoansRisk.AssetRiskConfigInput({
                maxLtvBps: MAX_LTV_BPS, // Maximum loan-to-value ratio, in basis points.
                backingMultiplierBps: BACKING_MULTIPLIER_BPS, // Backing valuation multiplier, in basis points.
                keeperRewardBps: KEEPER_REWARD_BPS, // Seizure reward rate, in basis points.
                termLength: TERM_LENGTH, // Initial loan term, in seconds.
                maxMaturityHorizon: MATURITY_HORIZON, // Maximum maturity horizon, in seconds.
                maxKeeperReward: MAX_KEEPER_REWARD // Reward cap, in 18-decimal collateral units.
            });
    }

    function _feeConfig() private pure returns (IBurnerLoansRisk.AssetFeeConfig memory) {
        return
            IBurnerLoansRisk.AssetFeeConfig({
                baseFeeBps: 0, // Base fee at zero utilization, in basis points.
                kinkBps: FEE_KINK_BPS, // Utilization kink, in basis points.
                preKinkSlopeBps: 0, // Fee slope below the kink, in basis points.
                postKinkSlopeBps: 0 // Fee slope above the kink, in basis points.
            });
    }

    // Every address in the fixed policy graph must have code before its metadata is read.
    // forge-lint: disable-next-item(require-revert-in-loop)
    function _deployed(address target_) private view {
        if (target_.code.length == 0) revert BurnerLoansActivator_InvalidDeployment(target_);
    }

    // A failed binding must abort validation, including checks of the fixed policy list.
    // forge-lint: disable-next-item(require-revert-in-loop)
    function _bound(bool valid_, address target_) private pure {
        if (!valid_) revert BurnerLoansActivator_InvalidDeployment(target_);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId_) external pure returns (bool) {
        return
            interfaceId_ == type(IBurnerLoansActivator).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId;
    }
}
