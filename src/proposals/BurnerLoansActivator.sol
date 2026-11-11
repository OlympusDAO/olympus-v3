// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
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
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IBurnerLoansActivator} from "src/proposals/interfaces/IBurnerLoansActivator.sol";

// Libraries
import {toSubKeycode} from "src/Submodules.sol";
import {BL_COLLATERAL_POLICY_ROLE, BL_DEBT_POLICY_ROLE, BL_LIQUIDATION_POLICY_ROLE, BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE, BURNER_LOANS_SEIZER_ROLE, DEPOSIT_OPERATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RevenueDistributorTask} from "src/policies/RevenueDistributorTask.sol";
import {Kernel, Module, Policy, toKeycode} from "src/Kernel.sol";
import {BurnerLoansSeizerTask} from "src/policies/burnerloans/BurnerLoansSeizerTask.sol";

/// @notice Executes the reviewed Burner Loans launch using temporary governance authority.
/// @dev Deployment, module installation and policy activation precede this contract's one-use launch.
///      The separately deployed backing oracle is populated before launch. Governance admits missing USDe
///      PRICE support before activation; existing OHM and USDS price configurations are retained.
contract BurnerLoansActivator is IBurnerLoansActivator {
    /// @dev OHM principal uses 9 decimals; both collateral assets and vault accounting use 18.
    uint128 internal constant ASSET_DEBT_CAP = 50_000e9;
    uint128 internal constant GLOBAL_DEBT_CAP = 100_000e9;
    uint256 internal constant DEPOSIT_CAP = 10_000_000e18;
    uint256 internal constant MINIMUM_DEPOSIT = 1e18;
    uint8 internal constant DEPOSIT_PERIOD = 1;
    string internal constant OPERATOR_NAME = "brn";

    uint48 internal constant PRICE_CACHE_MAX_AGE = 300;
    uint16 internal constant MAX_LTV_BPS = 8500;
    uint16 internal constant BACKING_MULTIPLIER_BPS = 12500;
    uint16 internal constant KEEPER_REWARD_BPS = 100;
    uint16 internal constant FEE_KINK_BPS = 8000;
    uint48 internal constant TERM_LENGTH = 30 days;
    uint48 internal constant MATURITY_HORIZON = 90 days;
    uint128 internal constant MAX_KEEPER_REWARD = 100e18;
    uint16 internal constant SEIZER_CHECK_LIMIT = 100;
    uint8 internal constant SEIZER_SEIZE_LIMIT = 25;
    uint32 internal constant SEIZER_GAS_LIMIT = 10_000_000;
    uint32 internal constant TASK_GAS_LIMIT = 1_000_000;
    uint32 internal constant TASK_MINIMUM_GAS = 250_000;
    uint32 internal constant TASK_GAS_RESERVE = 100_000;
    uint256 internal constant SEIZER_TASK_INDEX = 0;
    uint256 internal constant YIELD_TASK_INDEX = 1;
    uint256 internal constant DISTRIBUTOR_TASK_INDEX = 2;
    address internal constant USDE_USD_FEED = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;
    uint48 internal constant USDE_FEED_MAX_AGE = 1 days;
    uint256 internal constant USDE_EXPECTED_PRICE = 1e18;
    uint16 internal constant USDE_PRICE_TOLERANCE_BPS = 100;

    /// @inheritdoc IBurnerLoansActivator
    address public immutable override timelock;
    /// @inheritdoc IBurnerLoansActivator
    bool public override isActivated;
    address internal immutable _kernel;
    address internal immutable _ohm;
    address internal immutable _floan;
    address internal immutable _depositManager;
    address internal immutable _core;
    address internal immutable _auth;
    address internal immutable _config;
    address internal immutable _inventory;
    address internal immutable _payout;
    address internal immutable _risk;
    address internal immutable _collateral;
    address internal immutable _debt;
    address internal immutable _seize;
    address internal immutable _lens;
    address internal immutable _seizerTask;
    address internal immutable _yieldClaimerTask;
    address internal immutable _configTimelock;
    address internal immutable _riskTimelock;
    address internal immutable _payoutTimelock;
    address internal immutable _inventoryTimelock;
    address internal immutable _priceConfig;
    address internal immutable _priceCache;
    address internal immutable _revenueDistributor;
    address internal immutable _revenueDistributorTimelock;
    address internal immutable _revenueDistributorTask;
    address internal immutable _heart;
    address internal immutable _usds;
    address internal immutable _usde;
    address internal immutable _susds;
    address internal immutable _susde;
    address internal immutable _backingOracle;

    /// @notice Binds the already-deployed graph without requiring it to be installed or active yet.
    /// @dev Reverts for a zero timelock, missing code, inconsistent Kernel/Core identities or invalid vault bindings.
    /// @param timelock_ Sole governance executor allowed to launch.
    /// @param deployment_ Reviewed deployment graph and external asset/oracle dependencies.
    constructor(address timelock_, Deployment memory deployment_) {
        if (timelock_ == address(0)) revert BurnerLoansActivator_InvalidDeployment(timelock_);
        timelock = timelock_;
        _kernel = deployment_.kernel;
        _ohm = deployment_.ohm;
        _floan = deployment_.floan;
        _depositManager = deployment_.depositManager;
        _core = deployment_.core;
        _auth = deployment_.auth;
        _config = deployment_.config;
        _inventory = deployment_.inventory;
        _payout = deployment_.payout;
        _risk = deployment_.risk;
        _collateral = deployment_.collateral;
        _debt = deployment_.debt;
        _seize = deployment_.seize;
        _lens = deployment_.lens;
        _seizerTask = deployment_.seizerTask;
        _yieldClaimerTask = deployment_.yieldClaimerTask;
        _configTimelock = deployment_.configTimelock;
        _riskTimelock = deployment_.riskTimelock;
        _payoutTimelock = deployment_.payoutTimelock;
        _inventoryTimelock = deployment_.inventoryTimelock;
        _priceConfig = deployment_.priceConfig;
        _priceCache = deployment_.priceCache;
        _revenueDistributor = deployment_.revenueDistributor;
        _revenueDistributorTimelock = deployment_.revenueDistributorTimelock;
        _revenueDistributorTask = deployment_.revenueDistributorTask;
        _heart = deployment_.heart;
        _usds = deployment_.usds;
        _usde = deployment_.usde;
        _susds = deployment_.susds;
        _susde = deployment_.susde;
        _backingOracle = deployment_.backingOracle;
        _validateBindings();
    }

    /// @dev Enumerates policies used by on-chain launch checks.
    function _policies() internal view returns (address[] memory targets) {
        targets = new address[](19);
        targets[0] = _depositManager;
        targets[1] = _core;
        targets[2] = _config;
        targets[3] = _inventory;
        targets[4] = _payout;
        targets[5] = _risk;
        targets[6] = _collateral;
        targets[7] = _debt;
        targets[8] = _seize;
        targets[9] = _seizerTask;
        targets[10] = _yieldClaimerTask;
        targets[11] = _configTimelock;
        targets[12] = _riskTimelock;
        targets[13] = _payoutTimelock;
        targets[14] = _inventoryTimelock;
        targets[15] = _priceCache;
        targets[16] = _revenueDistributor;
        targets[17] = _revenueDistributorTask;
        targets[18] = _revenueDistributorTimelock;
    }

    // Kernel activation alone does not initialize a policy. Require a fresh, disabled graph
    // so this fixed launch cannot overwrite configuration from an earlier enablement.
    // forge-lint: disable-next-item(calls-loop,require-revert-in-loop)
    function _validatePrerequisites() private view {
        _validateBindings();
        Kernel installedKernel = Kernel(_kernel);
        address[] memory targets = _policies();
        for (uint256 i; i < targets.length; ++i) {
            if (
                !installedKernel.isPolicyActive(Policy(targets[i])) ||
                IEnabler(targets[i]).isEnabled() ||
                IEnablerV2(targets[i]).lastTransitionAt() != 0
            ) revert BurnerLoansActivator_InvalidPrerequisite(targets[i]);
        }
        if (!installedKernel.isPolicyActive(Policy(_heart)) || !IEnabler(_heart).isEnabled())
            revert BurnerLoansActivator_InvalidPrerequisite(_heart);
        if (
            address(installedKernel.getModuleForKeycode(toKeycode("FLOAN"))) != _floan ||
            IBurnerLoansCore(_core).floan() != _floan
        ) revert BurnerLoansActivator_InvalidPrerequisite(_floan);
        if (
            IBurnerLoansCore(_core).getAssetCount() != 0 ||
            IDepositManager(_depositManager).getConfiguredAssets().length != 0
        ) revert BurnerLoansActivator_InvalidPrerequisite(_core);
        if (
            !installedKernel.isPolicyActive(Policy(_backingOracle)) ||
            !IEnabler(_backingOracle).isEnabled() ||
            IBackingOracle(_backingOracle).backing() == 0
        ) revert BurnerLoansActivator_InvalidPrerequisite(_backingOracle);
        IPRICEv2 price = IPRICEv2(address(installedKernel.getModuleForKeycode(toKeycode("PRICE"))));
        if (!price.isAssetApproved(_ohm) || !price.isAssetApproved(_usds))
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
        _admitUsde();
        _enableAndBind();
        // USDS supports synchronous underlying withdrawals; USDe must exit as sUSDe shares.
        // Custody and lending use the same output mode for each market.
        _configureAsset(_usds, _susds, false);
        _configureAsset(_usde, _susde, true);
        IBurnerLoansInventory(_inventory).setGlobalDebtCap(GLOBAL_DEBT_CAP);
        // Add automation only after both markets and their funding capacity are ready.
        _configureTasks();
        // The OCG proposal revokes our temporary ADMIN after this call returns. No operational
        // role is granted to this helper, and isActivated prevents it from launching again.
        emit Activated(msg.sender);
    }

    // All settlement, custody and automation authority must be installed before any launch mutation.
    // forge-lint: disable-next-item(calls-loop,require-revert-in-loop)
    function _validateRoles() private view {
        ROLESv1 roles = ROLESv1(address(Kernel(_kernel).getModuleForKeycode(toKeycode("ROLES"))));
        address[7] memory holders = [
            address(this),
            _core,
            _collateral,
            _debt,
            _seize,
            _yieldClaimerTask,
            _seizerTask
        ];
        bytes32[7] memory required = [
            ADMIN_ROLE,
            DEPOSIT_OPERATOR_ROLE,
            BL_COLLATERAL_POLICY_ROLE,
            BL_DEBT_POLICY_ROLE,
            BL_LIQUIDATION_POLICY_ROLE,
            BL_YIELD_CLAIMER_ROLE,
            BURNER_LOANS_SEIZER_ROLE
        ];
        for (uint256 i; i < holders.length; ++i) {
            if (!roles.hasRole(holders[i], required[i]))
                revert BurnerLoansActivator_InvalidPrerequisite(holders[i]);
        }
    }

    function _admitUsde() private {
        IPRICEv2 price = IPRICEv2(address(Kernel(_kernel).getModuleForKeycode(toKeycode("PRICE"))));
        // Preserve a prior admission. Adding a new feed validates its live answer; neither
        // path warms PriceCache, whose pairs refresh when lending operations need them.
        if (price.isAssetApproved(_usde)) return;
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component(
            toSubKeycode("PRICE.CHAINLINK"), // Installed PRICE feed-adapter submodule.
            ChainlinkPriceFeeds.getOneFeedPrice.selector, // Read one Chainlink feed.
            abi.encode(
                ChainlinkPriceFeeds.OneFeedParams(
                    AggregatorV2V3Interface(USDE_USD_FEED), // USDe/USD aggregator.
                    USDE_FEED_MAX_AGE // Maximum feed age, in seconds.
                )
            )
        );
        IPriceConfigv2.PriceFeedExpectation[]
            memory expectations = new IPriceConfigv2.PriceFeedExpectation[](1);
        expectations[0] = IPriceConfigv2.PriceFeedExpectation(
            USDE_EXPECTED_PRICE, // $1 in 18-decimal PRICE units.
            USDE_PRICE_TOLERANCE_BPS // Allowed deviation from that price, in basis points.
        );
        IPRICEv2.Component memory strategy; // Empty strategy: use the single feed directly.
        IPriceConfigv2(_priceConfig).addAsset(
            _usde, // Underlying collateral asset to price.
            false, // Do not store a moving average.
            false, // Do not use a moving average in price resolution.
            0, // Moving-average duration: unused, in seconds.
            0, // Last observation timestamp: no observation history is seeded.
            new uint256[](0), // No historical observations.
            strategy, // No multi-feed aggregation strategy.
            feeds, // The single USDe/USD feed configured above.
            expectations // Admission-time expected price and tolerance for that feed.
        );
    }

    function _enableAndBind() private {
        // Bind operational services and their independent delayed configuration authorities.
        // Auth has no independent lifecycle or roles; selecting it installs Core authorization.
        IBurnerLoansCore(_core).setAuth(_auth);
        IConfigOperator(_core).setConfigOperator(_config);
        IConfigOperator(_risk).setConfigOperator(_riskTimelock);
        IConfigOperator(_inventory).setConfigOperator(_inventoryTimelock);
        IConfigOperator(_payout).setConfigOperator(_payoutTimelock);
        // Enable shared pricing and revenue routing before the lending services.
        IEnabler(_priceCache).enable("");
        IEnabler(_revenueDistributor).enable("");
        IConfigOperator(_revenueDistributor).setConfigOperator(_revenueDistributorTimelock);
        // Empty recipient routes and zero repurchase share allocate all receipts to Treasury.
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        IRevenueDistributor(_revenueDistributor).setAssetRoutes(_usds, 0, routes);
        IRevenueDistributor(_revenueDistributor).setAssetRoutes(_usde, 0, routes);
        IRevenueDistributor(_revenueDistributor).setAssetRoutes(_susde, 0, routes);
        // Enable custody and services before Core, then its action policies.
        IEnabler(_depositManager).enable("");
        IEnabler(_inventory).enable("");
        IEnabler(_payout).enable("");
        IEnabler(_risk).enable("");
        IBurnerLoansRisk(_risk).setPriceCache(_priceCache);
        IBurnerLoansRisk(_risk).setPriceCacheMaxAge(PRICE_CACHE_MAX_AGE);
        IBurnerLoansPayout(_payout).setRevenueDistributor(_revenueDistributor);
        IBurnerLoansPayout(_payout).setSendFeesToDistributor(true);
        IBurnerLoansPayout(_payout).setSendYieldToDistributor(true);
        IBurnerLoansCore(_core).setInventory(_inventory);
        IBurnerLoansCore(_core).setPayout(_payout);
        IBurnerLoansCore(_core).setRisk(_risk);
        // Core's enable hook checks its selected services; actions can be enabled afterwards.
        IEnabler(_core).enable("");
        IEnabler(_config).enable("");
        IConfigOperator(_config).setConfigOperator(_configTimelock);
        IEnabler(_collateral).enable("");
        IEnabler(_debt).enable("");
        IEnabler(_seize).enable("");
        IDepositManager(_depositManager).setOperatorName(_core, OPERATOR_NAME);
    }

    // The receipt token ID returned by addAssetPeriod is not needed by the launch.
    // forge-lint: disable-next-item(unused-return)
    function _configureAsset(address asset_, address vault_, bool shares_) private {
        // Register shared custody first, then its Core-specific receipt period, then the
        // lending market. Config verifies this custody route when admitting the market.
        IDepositManagerV1_1(_depositManager).addAsset(
            IERC20(asset_), // Underlying token held on behalf of deposit operators.
            IERC4626(vault_), // Vault that receives the underlying deposits.
            DEPOSIT_CAP, // Aggregate credited-principal cap, in 18-decimal asset units.
            MINIMUM_DEPOSIT, // Minimum deposit, in 18-decimal asset units.
            shares_ // Require share withdrawals for sUSDe; allow underlying for sUSDS.
        );
        // Config admission below validates this registered period.
        IDepositManager(_depositManager).addAssetPeriod(
            IERC20(asset_), // Collateral asset for the receipt-token route.
            DEPOSIT_PERIOD, // Deposit period, in months.
            _core // Operator whose deposits and liabilities use this route.
        );
        IBurnerLoansConfig(_config).addAsset(
            asset_, // Underlying collateral token for this lending market.
            ASSET_DEBT_CAP, // Maximum market principal, in 9-decimal OHM units.
            _riskConfig(), // LTV, backing, term and keeper-reward limits.
            _feeConfig(), // Zero-fee utilization curve at launch.
            shares_ // Match the withdrawal mode configured in custody above.
        );
    }

    function _configureTasks() private {
        // Arm each selected configuration timelock after its target has been enabled.
        IEnabler(_configTimelock).enable("");
        IEnabler(_riskTimelock).enable("");
        IEnabler(_payoutTimelock).enable("");
        IEnabler(_inventoryTimelock).enable("");
        IEnabler(_revenueDistributorTimelock).enable("");
        // Limit the keeper's scan to the two admitted markets and apply explicit gas budgets.
        IBurnerLoansSeizerTask(_seizerTask).addAsset(_usds);
        IBurnerLoansSeizerTask(_seizerTask).addAsset(_usde);
        IBurnerLoansSeizerTask(_seizerTask).setScanLimits(SEIZER_CHECK_LIMIT, SEIZER_SEIZE_LIMIT);
        IBurnerLoansSeizerTask(_seizerTask).setExecutionGasLimit(SEIZER_GAS_LIMIT);
        IBurnerLoansYieldClaimerTask(_yieldClaimerTask).setExecutionGasLimit(TASK_GAS_LIMIT);
        IBurnerLoansYieldClaimerTask(_yieldClaimerTask).setMinimumGasToAttempt(TASK_MINIMUM_GAS);
        IBurnerLoansYieldClaimerTask(_yieldClaimerTask).setGasReserve(TASK_GAS_RESERVE);
        IEnabler(_seizerTask).enable("");
        IEnabler(_yieldClaimerTask).enable("");
        RevenueDistributorTask(_revenueDistributorTask).setExecutionGasLimit(TASK_GAS_LIMIT);
        RevenueDistributorTask(_revenueDistributorTask).setMinimumGasToAttempt(TASK_MINIMUM_GAS);
        RevenueDistributorTask(_revenueDistributorTask).setGasReserve(TASK_GAS_RESERVE);
        IEnabler(_revenueDistributorTask).enable("");
        // New indexes 0/1/2: seize defaults, collect yield, then distribute revenue.
        // Mainnet baseline at block 25,973,712; existing selectors remain unchanged:
        // Task                            Existing index -> Revised index
        // BurnerLoansSeizerTask                     new  -> 0
        // BurnerLoansYieldClaimerTask               new  -> 1
        // RevenueDistributorTask                   new  -> 2
        // ConvertibleDepositFacility                 0   -> 3
        // ReserveMigrator                            1   -> 4
        // ReserveWrapper                             2   -> 5
        // Operator                                   3   -> 6
        // YieldRepurchaseFacility                    4   -> 7
        // EmissionManager                            5   -> 8
        IPeriodicTaskManager(_heart).addPeriodicTaskAtIndex(
            _seizerTask, // Task to insert into Heart.
            bytes4(0), // Use its default execute() selector.
            SEIZER_TASK_INDEX // Insert here, shifting subsequent tasks one position right.
        );
        IPeriodicTaskManager(_heart).addPeriodicTaskAtIndex(
            _yieldClaimerTask, // Task to insert into Heart.
            bytes4(0), // Use its default execute() selector.
            YIELD_TASK_INDEX // Insert here, shifting subsequent tasks one position right.
        );
        IPeriodicTaskManager(_heart).addPeriodicTaskAtIndex(
            _revenueDistributorTask, // Task to insert into Heart.
            bytes4(0), // Use its default execute() selector.
            DISTRIBUTOR_TASK_INDEX // Insert here, shifting subsequent tasks one position right.
        );
    }

    // The fixed launch graph requires each policy to report the bound Kernel.
    // forge-lint: disable-next-item(calls-loop)
    function _validateBindings() private view {
        _deployed(_kernel);
        _deployed(_ohm);
        _deployed(_floan);
        _deployed(_lens);
        _deployed(_auth);
        _deployed(_heart);
        _deployed(_usds);
        _deployed(_usde);
        _deployed(_susds);
        _deployed(_susde);
        _deployed(_backingOracle);
        _deployed(_priceConfig);
        _bound(address(Policy(_priceConfig).kernel()) == _kernel, _priceConfig);
        address[] memory targets = _policies();
        for (uint256 i; i < targets.length; ++i) {
            _deployed(targets[i]);
            _bound(address(Policy(targets[i]).kernel()) == _kernel, targets[i]);
        }
        _bound(address(Policy(_backingOracle).kernel()) == _kernel, _backingOracle);
        _bound(address(Policy(_heart).kernel()) == _kernel, _heart);
        _bound(
            RevenueDistributorTask(_revenueDistributorTask).distributor() == _revenueDistributor,
            _revenueDistributorTask
        );
        _bound(
            address(IRevenueDistributorConfigTimelock(_revenueDistributorTimelock).distributor()) ==
                _revenueDistributor,
            _revenueDistributorTimelock
        );
        _bound(address(Module(_floan).kernel()) == _kernel, _floan);
        _bound(
            IBurnerLoansCore(_core).ohm() == _ohm &&
                IBurnerLoansCore(_core).depositManager() == _depositManager,
            _core
        );
        _bound(IBurnerLoansInventory(_inventory).ohm() == _ohm, _inventory);
        _bound(
            IBurnerLoansRisk(_risk).ohm() == _ohm &&
                IBurnerLoansRisk(_risk).backingOracle() == _backingOracle,
            _risk
        );
        _bound(IBurnerLoansCoreBound(_auth).core() == _core, _auth);
        _bound(IBurnerLoansCoreBound(_config).core() == _core, _config);
        _bound(IBurnerLoansCoreBound(_inventory).core() == _core, _inventory);
        _bound(IBurnerLoansCoreBound(_payout).core() == _core, _payout);
        _bound(IBurnerLoansCoreBound(_risk).core() == _core, _risk);
        _bound(IBurnerLoansCoreBound(_collateral).core() == _core, _collateral);
        _bound(IBurnerLoansCoreBound(_debt).core() == _core, _debt);
        _bound(IBurnerLoansCoreBound(_seize).core() == _core, _seize);
        _bound(IBurnerLoansCoreBound(_lens).core() == _core, _lens);
        _bound(IBurnerLoansCoreBound(_yieldClaimerTask).core() == _core, _yieldClaimerTask);
        _bound(
            address(IBurnerLoansConfigTimelock(_configTimelock).burnerLoans()) == _config,
            _configTimelock
        );
        _bound(
            address(IBurnerLoansRiskConfigTimelock(_riskTimelock).risk()) == _risk,
            _riskTimelock
        );
        _bound(
            address(IBurnerLoansPayoutConfigTimelock(_payoutTimelock).payout()) == _payout,
            _payoutTimelock
        );
        _bound(
            address(IBurnerLoansInventoryConfigTimelock(_inventoryTimelock).inventory()) ==
                _inventory,
            _inventoryTimelock
        );
        _bound(address(IBurnerLoansSeizerTask(_seizerTask).seize()) == _seize, _seizerTask);
        _bound(BurnerLoansSeizerTask(_seizerTask).lens() == _lens, _seizerTask);
        _bound(
            IERC4626(_susds).asset() == _usds &&
                IERC4626(_susde).asset() == _usde &&
                _usds != _usde,
            _depositManager
        );
        _bound(
            IERC20(_ohm).decimals() == 9 &&
                IERC20(_usds).decimals() == 18 &&
                IERC20(_usde).decimals() == 18,
            _core
        );
    }

    function _riskConfig() private pure returns (IBurnerLoansRisk.AssetRiskConfigInput memory) {
        return
            IBurnerLoansRisk.AssetRiskConfigInput(
                MAX_LTV_BPS, // Maximum loan-to-value ratio, in basis points.
                BACKING_MULTIPLIER_BPS, // Backing valuation multiplier, in basis points.
                KEEPER_REWARD_BPS, // Seizure reward rate, in basis points.
                TERM_LENGTH, // Initial loan term, in seconds.
                MATURITY_HORIZON, // Maximum maturity horizon, in seconds.
                MAX_KEEPER_REWARD // Reward cap, in 18-decimal collateral units.
            );
    }

    function _feeConfig() private pure returns (IBurnerLoansRisk.AssetFeeConfig memory) {
        return
            IBurnerLoansRisk.AssetFeeConfig(
                0, // Base fee at zero utilization, in basis points.
                FEE_KINK_BPS, // Utilization kink, in basis points.
                0, // Fee slope below the kink, in basis points.
                0 // Fee slope above the kink, in basis points.
            );
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
