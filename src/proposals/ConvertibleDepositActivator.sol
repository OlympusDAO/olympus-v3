// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

// Libraries
import {Owned} from "@solmate-6.2.0/auth/Owned.sol";

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {IEmissionManager} from "src/policies/interfaces/IEmissionManager.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IReserveMigrator} from "src/policies/interfaces/IReserveMigrator.sol";
import {IOperator} from "src/policies/interfaces/IOperator.sol";
import {IYieldRepo} from "src/policies/interfaces/IYieldRepo.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

/// @notice Single-use contract to activate the Convertible Deposits system
contract ConvertibleDepositActivator is Owned {
    // Existing contracts
    address public constant RESERVE_MIGRATOR = 0x986b99579BEc7B990331474b66CcDB94Fa2419F5;
    address public constant OPERATOR = 0x6417F206a0a6628Da136C0Faa39026d0134D2b52;
    address public constant YIELD_REPURCHASE_FACILITY = 0x271e35a8555a62F6bA76508E85dfD76D580B0692;

    // New contracts
    address public immutable DEPOSIT_MANAGER;
    address public immutable CD_FACILITY;
    address public immutable REDEMPTION_VAULT;
    address public immutable CD_AUCTIONEER;
    address public immutable EMISSION_MANAGER;
    address public immutable HEART;
    address public immutable RESERVE_WRAPPER;

    string public constant CD_NAME = "cdf";

    // Tokens
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;

    // Asset configuration
    uint256 public constant USDS_MAX_CAPACITY = 1_000_000e18; // 1M USDS
    uint256 public constant USDS_MIN_DEPOSIT = 1e18; // 1 USDS

    // Deposit periods (in months)
    uint8 public constant PERIOD_1M = 1;
    uint8 public constant PERIOD_2M = 2;
    uint8 public constant PERIOD_3M = 3;

    // Reclaim rate (in basis points)
    uint16 public constant RECLAIM_RATE = 90e2; // 90%

    // ConvertibleDepositAuctioneer initial parameters
    uint256 public constant CDA_INITIAL_TARGET = 0;
    uint256 public constant CDA_INITIAL_TICK_SIZE = 0;
    uint256 public constant CDA_INITIAL_MIN_PRICE = 0;
    uint24 public constant CDA_INITIAL_TICK_STEP_MULTIPLIER = 10075; // 0.75% increase
    uint8 public constant CDA_AUCTION_TRACKING_PERIOD = 7; // 7 days

    // EmissionManager parameters
    uint256 public constant EM_BASE_EMISSIONS_RATE = 200000; // 0.02%/day
    uint256 public constant EM_MINIMUM_PREMIUM = 1e18; // 100% premium
    uint256 public constant EM_BACKING = 11740000000000000000; // 11.74 USDS/OHM
    uint256 public constant EM_TICK_SIZE = 150e9; // 150 OHM
    uint256 public constant EM_MIN_PRICE_SCALAR = 1e18; // 100% min price multiplier
    uint48 public constant EM_RESTART_TIMEFRAME = 950400; // 11 days

    /// @notice True if the activation has been performed
    bool public isActivated = false;

    event Activated(address caller);
    error AlreadyActivated();
    error InvalidParams(string reason);

    constructor(
        address owner_,
        address depositManager_,
        address cdFacility_,
        address cdAuctioneer_,
        address redemptionVault_,
        address emissionManager_,
        address heart_,
        address reserveWrapper_
    ) Owned(owner_) {
        if (owner_ == address(0)) revert InvalidParams("owner");
        if (depositManager_ == address(0)) revert InvalidParams("depositManager");
        if (cdFacility_ == address(0)) revert InvalidParams("cdFacility");
        if (cdAuctioneer_ == address(0)) revert InvalidParams("cdAuctioneer");
        if (redemptionVault_ == address(0)) revert InvalidParams("redemptionVault");
        if (emissionManager_ == address(0)) revert InvalidParams("emissionManager");
        if (heart_ == address(0)) revert InvalidParams("heart");
        if (reserveWrapper_ == address(0)) revert InvalidParams("reserveWrapper");

        DEPOSIT_MANAGER = depositManager_;
        CD_FACILITY = cdFacility_;
        CD_AUCTIONEER = cdAuctioneer_;
        REDEMPTION_VAULT = redemptionVault_;
        EMISSION_MANAGER = emissionManager_;
        HEART = heart_;
        RESERVE_WRAPPER = reserveWrapper_;
    }

    function _activateContracts() internal {
        // 1. Enable DepositManager contract
        IEnabler(DEPOSIT_MANAGER).enable("");

        // 2. Set operator name on DepositManager for ConvertibleDepositFacility
        IDepositManager(DEPOSIT_MANAGER).setOperatorName(CD_FACILITY, CD_NAME);

        // 3. Enable ConvertibleDepositFacility contract
        IEnabler(CD_FACILITY).enable("");

        // 6. Authorize ConvertibleDepositFacility in DepositRedemptionVault
        IDepositRedemptionVault(REDEMPTION_VAULT).authorizeFacility(CD_FACILITY);

        // 7. Authorize DepositRedemptionVault in ConvertibleDepositFacility
        IDepositFacility(CD_FACILITY).authorizeOperator(REDEMPTION_VAULT);

        // 8. Enable DepositRedemptionVault
        IEnabler(REDEMPTION_VAULT).enable("");
    }

    function _configureAssets() internal {
        IDepositManager depositManager = IDepositManager(DEPOSIT_MANAGER);
        IERC20 usds = IERC20(USDS);

        // 1. Configure USDS in DepositManager
        depositManager.addAsset(usds, IERC4626(SUSDS), USDS_MAX_CAPACITY, USDS_MIN_DEPOSIT);

        // 2. Add USDS-1m/2m/3m to DepositManager
        depositManager.addAssetPeriod(usds, PERIOD_1M, CD_FACILITY);
        depositManager.addAssetPeriod(usds, PERIOD_2M, CD_FACILITY);
        depositManager.addAssetPeriod(usds, PERIOD_3M, CD_FACILITY);

        // 3. Set reclaim rates on ConvertibleDepositFacility
        IDepositFacility(CD_FACILITY).setAssetPeriodReclaimRate(usds, PERIOD_1M, RECLAIM_RATE);
        IDepositFacility(CD_FACILITY).setAssetPeriodReclaimRate(usds, PERIOD_2M, RECLAIM_RATE);
        IDepositFacility(CD_FACILITY).setAssetPeriodReclaimRate(usds, PERIOD_3M, RECLAIM_RATE);
    }

    function _configureAuction() internal {
        IConvertibleDepositAuctioneer cdAuctioneer = IConvertibleDepositAuctioneer(CD_AUCTIONEER);

        // 1. Enable USDS-1m/2m/3m in ConvertibleDepositAuctioneer
        cdAuctioneer.enableDepositPeriod(PERIOD_1M);
        cdAuctioneer.enableDepositPeriod(PERIOD_2M);
        cdAuctioneer.enableDepositPeriod(PERIOD_3M);

        // 2. Enable ConvertibleDepositAuctioneer (with disabled auction)
        bytes memory auctioneerParams = abi.encode(
            IConvertibleDepositAuctioneer.EnableParams({
                target: CDA_INITIAL_TARGET,
                tickSize: CDA_INITIAL_TICK_SIZE,
                minPrice: CDA_INITIAL_MIN_PRICE,
                tickStep: CDA_INITIAL_TICK_STEP_MULTIPLIER,
                auctionTrackingPeriod: CDA_AUCTION_TRACKING_PERIOD
            })
        );
        IEnabler(CD_AUCTIONEER).enable(auctioneerParams);

        // 3. Enable EmissionManager
        bytes memory emissionParams = abi.encode(
            IEmissionManager.EnableParams({
                baseEmissionsRate: EM_BASE_EMISSIONS_RATE,
                minimumPremium: EM_MINIMUM_PREMIUM,
                backing: EM_BACKING,
                tickSize: EM_TICK_SIZE,
                minPriceScalar: EM_MIN_PRICE_SCALAR,
                restartTimeframe: EM_RESTART_TIMEFRAME
            })
        );
        IEnabler(EMISSION_MANAGER).enable(emissionParams);
    }

    function _configurePeriodicTasks() internal {
        IPeriodicTaskManager taskManager = IPeriodicTaskManager(HEART);

        // 1. Enable ReserveWrapper
        IEnabler(RESERVE_WRAPPER).enable("");

        // 2. Add ReserveMigrator.migrate() to periodic tasks
        taskManager.addPeriodicTaskAtIndex(
            RESERVE_MIGRATOR,
            IReserveMigrator.migrate.selector,
            0 // First task
        );

        // 3. Add ReserveWrapper to periodic tasks
        taskManager.addPeriodicTask(RESERVE_WRAPPER);

        // 4. Add Operator.operate() to periodic tasks
        taskManager.addPeriodicTaskAtIndex(
            OPERATOR,
            IOperator.operate.selector,
            2 // Third task
        );

        // 5. Add YieldRepurchaseFacility.endEpoch() to periodic tasks
        taskManager.addPeriodicTaskAtIndex(
            YIELD_REPURCHASE_FACILITY,
            IYieldRepo.endEpoch.selector,
            3 // Fourth task
        );

        // 6. Add EmissionManager to periodic tasks
        taskManager.addPeriodicTask(EMISSION_MANAGER);

        // 7. Enable Heart
        IEnabler(HEART).enable("");
    }

    /// @notice Activates the Convertible Deposits system
    /// @dev    This function assumes:
    ///         - The "admin" role has been granted to the contract
    ///
    ///         This function reverts if:
    ///         - The caller is not the owner
    ///         - The function has already been run
    function activate() external onlyOwner {
        // Revert if already activated
        if (isActivated) revert AlreadyActivated();

        _activateContracts();
        _configureAssets();
        _configureAuction();
        _configurePeriodicTasks();

        // Mark as activated
        isActivated = true;
        emit Activated(msg.sender);
    }
}
