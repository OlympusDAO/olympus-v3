// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IVotes} from "@openzeppelin-5.7.0/governance/utils/IVotes.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IBondAuctioneer} from "src/interfaces/IBondAuctioneer.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";
import {IYieldRepoV1} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepoV1.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2Activator} from "src/proposals/interfaces/IYieldRepurchaseFacilityV2Activator.sol";

// Libraries
import {stdJson} from "@forge-std-1.16.2/StdJson.sol";
import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";
import {YieldRepurchaseFacilityV2EnvFixture} from "./YieldRepurchaseFacilityV2EnvFixture.sol";

// Constants
import {ADMIN_ROLE, BACKING_ADMIN_ROLE, EMERGENCY_ROLE, YRF_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {GovernorBravoDelegate} from "src/external/governance/GovernorBravoDelegate.sol";
import {Timelock} from "src/external/governance/Timelock.sol";
import {Actions, Kernel, Policy, toKeycode} from "src/Kernel.sol";
import {ModuleWithSubmodules, toSubKeycode} from "src/Submodules.sol";
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BackingOracle} from "src/policies/BackingOracle.sol";
import {BackingOracleConfigTimelock} from "src/policies/BackingOracleConfigTimelock.sol";
import {OlympusHeart} from "src/policies/Heart.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {YieldRepurchaseFacilityV2} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2.sol";
import {YieldRepurchaseFacilityV2Config} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Config.sol";
import {YieldRepurchaseFacilityV2ConfigTimelock} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2ConfigTimelock.sol";
import {YieldRepurchaseFacilityV2Lens} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Lens.sol";
import {YieldRepurchaseFacilityV2Activator} from "src/proposals/YieldRepurchaseFacilityV2Activator.sol";
import {ProposalTest} from "src/test/proposals/ProposalTest.sol";
import {YieldRepurchaseFacilityV2ProposalHarness, YieldRepurchaseFacilityV2ProposalSnapshotHarness} from "./YieldRepurchaseFacilityV2ProposalHarness.sol";

/// @notice The owner getter of the Bond Protocol auctioneer, which `IBondAuctioneer` does not
///         declare.
interface IBondAuctioneerOwner {
    function owner() external view returns (address);
}

/// @notice Shared rig of the fork suites of the YieldRepurchaseFacilityV2 launch: the launch
///         proposal and the activator on a mainnet fork, in the state the proposal is submitted
///         in.
/// @dev    The rig serves three stages of the rollout with one `setUp`:
///         - Before the deployment, the registry of `src/proposals/addresses.json` records the
///           stack with the zero address. `_prepareLaunchState` then deploys the five policies,
///           the lens and the activator in the test with the values of `env.json`, records
///           them in the registry, and performs the two batches that precede the proposal from
///           their owners: the DAO MS activates the policies in the Kernel, and the Safe that
///           owns the bond auctioneer authorizes the facility as a market callback.
///         - After the deployment, the registry records the deployed addresses.
///           `_prepareLaunchState` then deploys nothing and checks the live state with labelled
///           requires: a failure there means that the pin is not between the two batches and
///           the execution of the proposal, not that the proposal is broken.
///         - After the submission, `IS_SUBMITTED` is set together with `BLOCK`: the simulated
///           calldata is compared with the submitted proposal, and the proposal and the rig
///           read the snapshot of `env.json` taken at the submission. The tracked file is not
///           read at this stage, so it is free to move on.
///
///         Prices: every feed of every asset registered in the PRICE module at the pin is
///         pinned to its answer at the pin, at the call boundary between the module and its
///         feed submodule, so that the answers do not go stale while the suites move time. The
///         USDe/USD feed, which the launch registers, is mocked at the aggregator instead, with
///         a timestamp the suites control: the registration and the freshness check of the
///         Chainlink submodule run on it unchanged.
// solhint-disable-next-line max-states-count
abstract contract YieldRepurchaseFacilityV2ProposalRig is ProposalTest {
    using stdJson for string;

    // ========== FORK PIN ========== //

    /// @notice The mainnet block of 2026-10-23 the suites fork, the pin of
    ///         `CCIPTokenPoolConfigProposal.t.sol`. At this block the stack is not deployed, the
    ///         DAO MS is the Kernel executor, the OCG timelock holds `admin` and administers
    ///         RolesAdmin, the YieldRepurchaseFacility v1.2 is running at epoch 11 as the fifth
    ///         of the six periodic tasks of the Heart, the DAO MS and the OCG timelock hold
    ///         `loop_daddy`, USDe is not registered in the PRICE module, and the USDe/USD feed
    ///         was updated 7,692 seconds before.
    /// @dev The simulation of the proposal rolls the block number forward by two voting delays
    ///      and one voting period of the governor, about 93,600 blocks. On a fork block whose
    ///      cache is empty, the first call after a roll then reads the block hash history
    ///      contract of EIP-2935 (a ring of 8,191 slots) through the RPC one slot at a time,
    ///      about four reads a second in the run of 2026-11-12 with Forge 1.9.0, and the
    ///      suites do not finish within minutes; later runs are served from the fork cache of
    ///      the block. The pin is shared with the CCIP proposal suite, so that both use one
    ///      cache.
    uint256 public constant BLOCK = 26_256_437;

    /// @notice Whether proposal 20 is on chain at `BLOCK`. Set it together with `BLOCK` when
    ///         the proposal is submitted, and refresh the snapshot of `env.json` that
    ///         `YieldRepurchaseFacilityV2ProposalSnapshotHarness` reads.
    bool public constant IS_SUBMITTED = false;

    /// @dev The OCG proposal id. Must match `YieldRepurchaseFacilityV2Proposal.id()`.
    uint256 internal constant _PROPOSAL_ID = 20;

    /// @dev The proposal name and the first line of its description.
    string internal constant _PROPOSAL_NAME = "Yield Repurchase Facility V2 - Migration";

    string internal constant _ENV_PATH = "./src/scripts/env.json";
    string internal constant _CHAIN = "mainnet";

    // ========== REGISTRY NAMES ========== //

    string internal constant _ORACLE_NAME = "olympus-policy-backing-oracle";
    string internal constant _ORACLE_TIMELOCK_NAME =
        "olympus-policy-backing-oracle-config-timelock";
    string internal constant _CONFIG_NAME = "olympus-policy-yieldrepurchasefacility-config-1_0";
    string internal constant _CONFIG_TIMELOCK_NAME =
        "olympus-policy-yieldrepurchasefacility-config-timelock-1_0";
    string internal constant _FACILITY_NAME = "olympus-policy-yieldrepurchasefacility-2_0";
    string internal constant _LENS_NAME = "olympus-periphery-yieldrepurchasefacility-lens";
    string internal constant _ACTIVATOR_NAME =
        "olympus-proposal-yieldrepurchasefacility-v2-activator";

    // ========== CONSTANTS ========== //

    bytes32 internal constant _LOOP_DADDY_ROLE = "loop_daddy";

    /// @dev The largest action list the proposal can build: four conditional role actions and
    ///      the five actions around the activator.
    uint256 internal constant _MAX_ACTION_COUNT = 9;

    uint256 internal constant _SELECTOR_BYTES = 4;
    uint256 internal constant _WORD_BYTES = 32;

    /// @dev One whole share or token of 18 decimals.
    uint256 internal constant _ONE = 1e18;

    // ========== ENVIRONMENT ========== //

    /// @notice The `env.json` the proposal reads: the tracked file before the submission, the
    ///         snapshot taken at the submission after it. The expected values of the suites
    ///         come from this string and from nothing else.
    string internal _env;

    /// @notice Whether the registry records the deployed stack, that is, whether the pin
    ///         follows the deployment.
    bool internal isStackRecorded;

    // ========== CONTRACTS ========== //

    YieldRepurchaseFacilityV2ProposalHarness internal proposal;

    Kernel internal kernel;
    ROLESv1 internal roles;
    RolesAdmin internal rolesAdmin;
    IPRICEv2 internal price;
    CHREGv1 internal chreg;
    OlympusHeart internal heart;
    GovernorBravoDelegate internal governor;
    IYieldRepoV1 internal yieldRepoV1;
    IBondAuctioneer internal bondAuctioneer;
    AggregatorV2V3Interface internal usdeUsdFeed;

    IERC20 internal ohm;
    IERC20 internal usds;
    IERC20 internal usde;
    IERC4626 internal sUsds;
    IERC4626 internal sUsde;

    BackingOracle internal backingOracle;
    BackingOracleConfigTimelock internal backingOracleConfigTimelock;
    YieldRepurchaseFacilityV2Config internal config;
    YieldRepurchaseFacilityV2ConfigTimelock internal configTimelock;
    YieldRepurchaseFacilityV2 internal facility;
    YieldRepurchaseFacilityV2Activator internal activator;

    // ========== ADDRESSES ========== //

    address internal treasury;
    address internal priceConfig;
    address internal daoMS;
    address internal emergencyMS;
    address internal ocgTimelock;
    address internal proposer;
    address internal keeper;

    /// @notice The answer of the USDe/USD feed at the pin, in the decimals of the feed.
    int256 internal usdeFeedAnswer;

    // ========== DATA STRUCTURES ========== //

    /// @notice One expected proposal action.
    struct ExpectedAction {
        address target;
        bytes data;
        string label;
    }

    /// @notice The state of the YieldRepurchaseFacility v1.2 and of the treasury that the
    ///         launch reads or moves.
    struct LaunchInputs {
        uint48 epoch;
        uint256 nextYield;
        uint256 lastReserveBalance;
        uint256 lastConversionRate;
        uint256 v1Usds;
        uint256 v1SUsdsShares;
        uint256 v1Ohm;
        uint256 poolSeed;
        uint256 treasuryUsds;
        uint256 treasurySUsdsShares;
        uint256 treasurySUsdeShares;
        uint256 ohmSupply;
        uint256 heartTaskIndex;
        uint256 heartTaskCount;
    }

    // ========== SETUP ========== //

    function setUp() public virtual {
        // The call selects the fork; its id is not needed afterwards
        // forge-lint: disable-next-line(unused-return)
        vm.createSelectFork(_RPC_ALIAS, BLOCK);

        // ========== PROPOSAL SETUP ========== //

        // Once the proposal is on chain, it reads the snapshot of the desired state taken at
        // the submission, and the framework compares the simulated calldata with the
        // submitted one
        proposal = IS_SUBMITTED
            ? new YieldRepurchaseFacilityV2ProposalSnapshotHarness()
            : new YieldRepurchaseFacilityV2ProposalHarness();
        vm.label(address(proposal), "YieldRepurchaseFacilityV2ProposalHarness");
        hasBeenSubmitted = IS_SUBMITTED;
        // The rig expects what the proposal reads
        _env = proposal.readEnv();

        _setupSuite(address(proposal));

        // ========== LOAD LIVE ADDRESSES ========== //

        // `Addresses` labels every entry it loads from `src/proposals/addresses.json`, so the
        // live contracts below are already named in traces
        kernel = Kernel(addresses.getAddress("olympus-kernel"));
        roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        rolesAdmin = RolesAdmin(addresses.getAddress("olympus-policy-roles-admin"));
        heart = OlympusHeart(addresses.getAddress("olympus-policy-heart-1_7"));
        governor = GovernorBravoDelegate(addresses.getAddress("olympus-governor"));
        yieldRepoV1 = IYieldRepoV1(
            addresses.getAddress("olympus-policy-yieldrepurchasefacility-1_2")
        );
        priceConfig = addresses.getAddress("olympus-policy-price-config-2_0");
        ohm = IERC20(addresses.getAddress("olympus-legacy-ohm"));
        usds = IERC20(addresses.getAddress("external-tokens-usds"));
        sUsds = IERC4626(addresses.getAddress("external-tokens-susds"));
        usde = IERC20(addresses.getAddress("external-tokens-usde"));
        sUsde = IERC4626(addresses.getAddress("external-tokens-susde"));
        daoMS = addresses.getAddress("olympus-multisig-dao");
        emergencyMS = addresses.getAddress("olympus-multisig-emergency");
        ocgTimelock = addresses.getAddress("olympus-timelock");
        proposer = addresses.getAddress("proposer");
        keeper = makeAddr("keeper");

        price = IPRICEv2(address(kernel.getModuleForKeycode(toKeycode("PRICE"))));
        vm.label(address(price), "PRICE");
        treasury = address(kernel.getModuleForKeycode(toKeycode("TRSRY")));
        vm.label(treasury, "TRSRY");
        chreg = CHREGv1(address(kernel.getModuleForKeycode(toKeycode("CHREG"))));
        vm.label(address(chreg), "CHREG");
        usdeUsdFeed = AggregatorV2V3Interface(
            YieldRepurchaseFacilityV2ConfigLib.usdeUsdPriceFeed(_env, _CHAIN)
        );
        vm.label(address(usdeUsdFeed), "usdeUsdPriceFeed");

        // ========== PRICES ========== //

        _pinRegisteredPrices();
        // Only the answer is taken from the live round
        // forge-lint: disable-next-line(unused-return)
        (, usdeFeedAnswer, , , ) = usdeUsdFeed.latestRoundData();
        // The round is dated in the future, at the time the proposal executes. The simulation
        // of the proposal warps by the timelock delay between the build and the execution and
        // leaves the test no point in between to date the answer again, and the Chainlink
        // submodule rejects only an answer older than its threshold, so this answer passes
        // the checks of the build and of the execution. A live feed reports no round from the
        // future: the tests of the freshness check date the answer themselves.
        _setUsdeFeed(
            usdeFeedAnswer,
            vm.getBlockTimestamp() + Timelock(payable(ocgTimelock)).delay()
        );

        // ========== THE STATE BEFORE THE PROPOSAL ========== //

        _requireLiveState();
        _prepareLaunchState();
    }

    // ========== THE STATE BEFORE THE PROPOSAL ========== //

    /// @notice Brings the fork to the state the proposal is submitted in, by the means the
    ///         registry calls for: a registry without the stack means that the pin precedes
    ///         the deployment, so the stack is deployed and prepared in the test; a registry
    ///         with the stack means that the pin follows the deployment and the two batches
    ///         before the proposal, so the live state is checked instead.
    function _prepareLaunchState() internal {
        isStackRecorded = _recordedOrZero(_FACILITY_NAME) != address(0);
        require(
            isStackRecorded || !IS_SUBMITTED,
            "rig: a submitted proposal implies a recorded stack"
        );
        if (!isStackRecorded) {
            // The deployment in the test stands in for the deployment sequence, which reads the
            // auctioneer from the tracked env.json; the proposal does not read this key
            // forge-lint: disable-next-line(unsafe-cheatcode)
            string memory trackedEnv = vm.readFile(_ENV_PATH);
            bondAuctioneer = IBondAuctioneer(
                trackedEnv.readAddress(
                    "$.current.mainnet.external.bond-protocol.BondFixedTermAuctioneer"
                )
            );
            vm.label(address(bondAuctioneer), "BondFixedTermAuctioneer");
            _deployStack();
            _activateStackAsDaoMS();
            _authorizeCallbackAsAuctioneerOwner();
            return;
        }

        backingOracle = BackingOracle(addresses.getAddress(_ORACLE_NAME));
        backingOracleConfigTimelock = BackingOracleConfigTimelock(
            addresses.getAddress(_ORACLE_TIMELOCK_NAME)
        );
        config = YieldRepurchaseFacilityV2Config(addresses.getAddress(_CONFIG_NAME));
        configTimelock = YieldRepurchaseFacilityV2ConfigTimelock(
            addresses.getAddress(_CONFIG_TIMELOCK_NAME)
        );
        facility = YieldRepurchaseFacilityV2(addresses.getAddress(_FACILITY_NAME));
        activator = YieldRepurchaseFacilityV2Activator(addresses.getAddress(_ACTIVATOR_NAME));
        // The deployed facility names its auctioneer
        bondAuctioneer = IBondAuctioneer(facility.bondAuctioneer());
        vm.label(address(bondAuctioneer), "BondFixedTermAuctioneer");
        _requireRecordedState();
    }

    /// @notice Deploys the stack and the activator the way the deployment sequences do, with
    ///         the parameters of `env.json`, and records them in the registry.
    function _deployStack() internal {
        YieldRepurchaseFacilityV2EnvFixture.State memory state = _desired();

        backingOracle = new BackingOracle(kernel);
        backingOracleConfigTimelock = new BackingOracleConfigTimelock(kernel, backingOracle);
        config = new YieldRepurchaseFacilityV2Config(kernel, state.config.parameters.gracePeriod);
        configTimelock = new YieldRepurchaseFacilityV2ConfigTimelock(
            kernel,
            address(config),
            state.config.parameters.timelockDelay,
            state.config.parameters.gracePeriod
        );
        facility = new YieldRepurchaseFacilityV2(
            kernel,
            address(ohm),
            address(backingOracle),
            address(bondAuctioneer),
            state.config.parameters.gracePeriod,
            state.config.parameters.stepGasLimit
        );
        YieldRepurchaseFacilityV2Lens lens = new YieldRepurchaseFacilityV2Lens(address(facility));
        activator = new YieldRepurchaseFacilityV2Activator(
            ocgTimelock,
            _deploymentOf(),
            _launchParametersOf(state)
        );

        // `Addresses` labels each address it records
        addresses.addAddress(_ORACLE_NAME, address(backingOracle));
        addresses.addAddress(_ORACLE_TIMELOCK_NAME, address(backingOracleConfigTimelock));
        addresses.addAddress(_CONFIG_NAME, address(config));
        addresses.addAddress(_CONFIG_TIMELOCK_NAME, address(configTimelock));
        addresses.addAddress(_FACILITY_NAME, address(facility));
        addresses.addAddress(_LENS_NAME, address(lens));
        addresses.addAddress(_ACTIVATOR_NAME, address(activator));
    }

    /// @notice The DAO MS batch that precedes the proposal: the Kernel executor activates the
    ///         five policies.
    function _activateStackAsDaoMS() internal {
        Kernel rigKernel = kernel;
        address[5] memory policies = _stackPolicies();
        vm.startPrank(daoMS);
        for (uint256 i = 0; i < policies.length; ++i) {
            rigKernel.executeAction(Actions.ActivatePolicy, policies[i]);
        }
        vm.stopPrank();
    }

    /// @notice The batch of the Safe that owns the bond auctioneer: it authorizes the facility
    ///         as a market callback.
    function _authorizeCallbackAsAuctioneerOwner() internal {
        _setCallbackAuthStatus(true);
    }

    function _setCallbackAuthStatus(bool status_) internal {
        IBondAuctioneer auctioneer = bondAuctioneer;
        address facilityAddress = address(facility);
        vm.prank(IBondAuctioneerOwner(address(bondAuctioneer)).owner());
        auctioneer.setCallbackAuthStatus(facilityAddress, status_);
    }

    /// @notice The live state every suite depends on. A failure here means that mainnet has
    ///         moved past the assumptions of the pin, not that the proposal is broken.
    function _requireLiveState() internal view {
        require(kernel.executor() == daoMS, "live: the DAO MS should be the Kernel executor");
        require(
            rolesAdmin.admin() == ocgTimelock,
            "live: the OCG timelock should administer RolesAdmin"
        );
        require(
            roles.hasRole(ocgTimelock, ADMIN_ROLE),
            "live: the OCG timelock should hold the admin role"
        );
        require(
            roles.hasRole(emergencyMS, EMERGENCY_ROLE),
            "live: the Emergency MS should hold the emergency role"
        );
        require(
            kernel.isPolicyActive(Policy(address(heart))) && heart.isEnabled(),
            "live: the Heart should be active and enabled"
        );
        require(
            !yieldRepoV1.isShutdown(),
            "live: v1.2 should not be shut down (the pin should precede the execution)"
        );
        require(
            heart.hasPeriodicTask(address(yieldRepoV1)),
            "live: v1.2 should be a periodic task of the Heart (the pin should precede the execution)"
        );
        require(
            IERC4626(address(sUsds)).asset() == address(usds) &&
                IERC4626(address(sUsde)).asset() == address(usde),
            "live: the recorded vaults should hold the recorded reserves"
        );
    }

    /// @notice The recorded deployment every suite depends on once the stack is deployed: the
    ///         contracts carry code, the two batches before the proposal have run, and the
    ///         proposal has not executed.
    function _requireRecordedState() internal view {
        address[5] memory policies = _stackPolicies();
        for (uint256 i = 0; i < policies.length; ++i) {
            require(policies[i].code.length != 0, "live: a recorded policy should carry code");
            require(
                kernel.isPolicyActive(Policy(policies[i])),
                "live: the recorded policies should be active (the pin should follow setupKernel)"
            );
            require(
                !IEnabler(policies[i]).isEnabled() &&
                    IEnablerV2(policies[i]).lastTransitionAt() == 0,
                "live: the recorded policies should never have been enabled (the pin should precede the execution)"
            );
        }
        require(
            address(activator).code.length != 0,
            "live: the recorded activator should carry code"
        );
        require(
            !activator.isActivated(),
            "live: the activator should not be activated (the pin should precede the execution)"
        );
        require(
            bondAuctioneer.callbackAuthorized(address(facility)),
            "live: the facility should be a market callback (the pin should follow setCallbackAuthStatus)"
        );
    }

    function _stackPolicies() internal view returns (address[5] memory policies) {
        policies = [
            address(backingOracle),
            address(backingOracleConfigTimelock),
            address(config),
            address(configTimelock),
            address(facility)
        ];
    }

    /// @notice The address the registry records under the name, or zero when it records none
    ///         or the zero placeholder.
    function _recordedOrZero(string memory name_) internal view returns (address recorded) {
        try addresses.getAddress(name_) returns (address value) {
            return value;
        } catch {
            return address(0);
        }
    }

    // ========== DESIRED STATE ========== //

    /// @notice The desired state of the launch that the `env.json` of the proposal declares.
    function _desired() internal view returns (YieldRepurchaseFacilityV2EnvFixture.State memory) {
        return YieldRepurchaseFacilityV2EnvFixture.read(_env, _CHAIN);
    }

    /// @notice The contracts of the launch, as the deployment sequence binds the activator.
    function _deploymentOf()
        internal
        view
        returns (IYieldRepurchaseFacilityV2Activator.Deployment memory deployment)
    {
        deployment.kernel = address(kernel);
        deployment.backingOracle = address(backingOracle);
        deployment.backingOracleConfigTimelock = address(backingOracleConfigTimelock);
        deployment.config = address(config);
        deployment.configTimelock = address(configTimelock);
        deployment.facility = address(facility);
        deployment.yieldRepoV1 = address(yieldRepoV1);
        deployment.heart = address(heart);
        deployment.priceConfig = priceConfig;
        deployment.bondAuctioneer = address(bondAuctioneer);
        deployment.usdeUsdPriceFeed = address(usdeUsdFeed);
        deployment.ohm = address(ohm);
        deployment.usds = address(usds);
        deployment.sUsds = address(sUsds);
        deployment.usde = address(usde);
        deployment.sUsde = address(sUsde);
    }

    /// @notice The launch values a desired state declares, as the deployment sequence passes
    ///         them to the activator.
    function _launchParametersOf(
        YieldRepurchaseFacilityV2EnvFixture.State memory state_
    )
        internal
        view
        returns (IYieldRepurchaseFacilityV2Activator.LaunchParameters memory parameters)
    {
        (
            bool sUsdsDeclared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory sUsdsAsset
        ) = YieldRepurchaseFacilityV2ConfigLib.findAsset(state_.config.assets, address(sUsds));
        (
            bool sUsdeDeclared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory sUsdeAsset
        ) = YieldRepurchaseFacilityV2ConfigLib.findAsset(state_.config.assets, address(sUsde));
        require(sUsdsDeclared && sUsdeDeclared, "env: mainnet should declare sUSDS and sUSDe");

        parameters.backing = state_.backing;
        parameters.initialDiscount = state_.config.parameters.initialDiscount;
        parameters.maxPricePremium = state_.config.parameters.maxPricePremium;
        parameters.sUsds = IYieldRepurchaseFacilityV2Activator.AssetParameters({
            yieldBuybackShare: sUsdsAsset.yieldBuybackShare,
            sellShares: sUsdsAsset.sellShares
        });
        parameters.sUsde = IYieldRepurchaseFacilityV2Activator.AssetParameters({
            yieldBuybackShare: sUsdeAsset.yieldBuybackShare,
            sellShares: sUsdeAsset.sellShares
        });
        parameters
            .clearinghouses = new IYieldRepurchaseFacilityV2Activator.ClearinghouseParameters[](
            state_.config.clearinghouses.length
        );
        for (uint256 i = 0; i < state_.config.clearinghouses.length; ++i) {
            parameters.clearinghouses[i] = IYieldRepurchaseFacilityV2Activator
                .ClearinghouseParameters({
                    clearinghouse: state_.config.clearinghouses[i].clearinghouse,
                    included: state_.config.clearinghouses[i].included,
                    offset: state_.config.clearinghouses[i].offset
                });
        }
    }

    // ========== PRICES ========== //

    /// @notice Pins every feed of every asset registered in the PRICE module to its answer at
    ///         the pin, at the call the module makes to the feed submodule.
    /// @dev A feed that does not answer at the pin is left alone: the price of its asset then
    ///      fails as it does on mainnet.
    function _pinRegisteredPrices() internal {
        address[] memory assets = price.getAssets();
        uint8 priceDecimals = price.decimals();
        for (uint256 i = 0; i < assets.length; ++i) {
            IPRICEv2.Component[] memory feeds = abi.decode(
                price.getAssetData(assets[i]).feeds,
                (IPRICEv2.Component[])
            );
            for (uint256 j = 0; j < feeds.length; ++j) {
                address submodule = address(
                    ModuleWithSubmodules(address(price)).getSubmoduleForKeycode(feeds[j].target)
                );
                // The exact payload the PRICE module sends to the submodule
                bytes memory payload = abi.encodeWithSelector(
                    feeds[j].selector,
                    assets[i],
                    priceDecimals,
                    feeds[j].params
                );
                // A raw read so that a feed that fails at the pin is skipped, not fatal
                // forge-lint: disable-next-item(low-level-calls)
                // solhint-disable-next-line avoid-low-level-calls
                (bool ok, bytes memory answer) = submodule.staticcall(payload);
                if (!ok || answer.length != _WORD_BYTES) continue;
                vm.mockCall(submodule, payload, answer);
            }
        }
    }

    /// @notice Mocks the latest round of the USDe/USD aggregator.
    /// @param answer_ The answer, in the decimals of the feed.
    /// @param updatedAt_ The timestamp of the round.
    function _setUsdeFeed(int256 answer_, uint256 updatedAt_) internal {
        vm.mockCall(
            address(usdeUsdFeed),
            abi.encodeWithSelector(usdeUsdFeed.latestRoundData.selector),
            abi.encode(uint80(1), answer_, updatedAt_, updatedAt_, uint80(1))
        );
    }

    /// @notice Registers USDe in the PRICE module before the launch, from the DAO MS, which
    ///         holds `price_admin` at the pin: one Chainlink feed, no strategy and no moving
    ///         average, like the registration of the activator.
    /// @param updateThreshold_ The update threshold of the feed, in seconds.
    function _registerUsdeAsDaoMS(uint48 updateThreshold_) internal {
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component({
            target: toSubKeycode("PRICE.CHAINLINK"),
            selector: ChainlinkPriceFeeds.getOneFeedPrice.selector,
            params: abi.encode(
                ChainlinkPriceFeeds.OneFeedParams({
                    feed: usdeUsdFeed,
                    updateThreshold: updateThreshold_
                })
            )
        });
        IPriceConfigv2.PriceFeedExpectation[]
            memory expectations = new IPriceConfigv2.PriceFeedExpectation[](1);
        expectations[0] = IPriceConfigv2.PriceFeedExpectation({
            expectedPrice: activator.USDE_EXPECTED_PRICE(),
            toleranceBps: activator.USDE_PRICE_TOLERANCE_BPS()
        });
        IPRICEv2.Component memory strategy;
        IPriceConfigv2 rigPriceConfig = IPriceConfigv2(priceConfig);
        address usdeAddress = address(usde);
        vm.prank(daoMS);
        rigPriceConfig.addAsset(
            usdeAddress,
            false,
            false,
            0,
            0,
            new uint256[](0),
            strategy,
            feeds,
            expectations
        );
    }

    // ========== HEART ========== //

    /// @notice Moves to the time of the next beat of the Heart and dates the USDe/USD answer
    ///         at that time.
    function _warpToNextBeat() internal {
        vm.warp(uint256(heart.lastBeat()) + heart.frequency());
        _setUsdeFeed(usdeFeedAnswer, vm.getBlockTimestamp());
    }

    /// @notice Beats the Heart at the current time.
    function _beatNow() internal {
        OlympusHeart rigHeart = heart;
        vm.prank(keeper);
        rigHeart.beat();
    }

    /// @notice Moves to the next beat of the Heart and beats.
    function _beat() internal {
        _warpToNextBeat();
        _beatNow();
    }

    // ========== LAUNCH INPUTS ========== //

    /// @notice Reads what the launch reads of the YieldRepurchaseFacility v1.2, and the
    ///         balances the launch moves.
    function _launchInputs() internal view returns (LaunchInputs memory inputs) {
        inputs.epoch = yieldRepoV1.epoch();
        inputs.nextYield = yieldRepoV1.nextYield();
        inputs.lastReserveBalance = yieldRepoV1.lastReserveBalance();
        inputs.lastConversionRate = yieldRepoV1.lastConversionRate();
        inputs.v1Usds = usds.balanceOf(address(yieldRepoV1));
        inputs.v1SUsdsShares = IERC20(address(sUsds)).balanceOf(address(yieldRepoV1));
        inputs.v1Ohm = ohm.balanceOf(address(yieldRepoV1));
        // USDS (18 decimals) + USDS value of the sUSDS shares (18 decimals, rounded down by the
        // vault) -> USDS (18 decimals)
        inputs.poolSeed = inputs.v1Usds + sUsds.previewRedeem(inputs.v1SUsdsShares);
        inputs.treasuryUsds = usds.balanceOf(treasury);
        inputs.treasurySUsdsShares = IERC20(address(sUsds)).balanceOf(treasury);
        inputs.treasurySUsdeShares = IERC20(address(sUsde)).balanceOf(treasury);
        inputs.ohmSupply = ohm.totalSupply();
        inputs.heartTaskIndex = heart.getPeriodicTaskIndex(address(yieldRepoV1));
        inputs.heartTaskCount = heart.getPeriodicTaskCount();
    }

    // ========== END STATE ========== //

    /// @notice Asserts the end state of the launch against the inputs read before it: v1.2 is
    ///         shut down and empty, the facility continues its weekly cycle with its funds,
    ///         both vaults are registered, and the facility holds the Heart slot of v1.2.
    /// @dev The values the launch reads from the vaults are compared with the values the
    ///      vaults report now, so the assertion holds in the block of the launch.
    /// @param inputs_ The state read before the launch.
    /// @param sUsdeNextYield_ The next yield the sUSDe vault was registered with.
    function _assertMigrated(LaunchInputs memory inputs_, uint256 sUsdeNextYield_) internal view {
        // v1.2: shut down and empty, its OHM (9 decimals) burned
        assertTrue(yieldRepoV1.isShutdown(), "v1.2 should be shut down");
        assertEq(usds.balanceOf(address(yieldRepoV1)), 0, "v1.2 should hold no USDS");
        assertEq(
            IERC20(address(sUsds)).balanceOf(address(yieldRepoV1)),
            0,
            "v1.2 should hold no sUSDS"
        );
        assertEq(ohm.balanceOf(address(yieldRepoV1)), 0, "v1.2 should hold no OHM");
        assertEq(
            ohm.totalSupply(),
            inputs_.ohmSupply - inputs_.v1Ohm,
            "the OHM of v1.2 should be burned"
        );

        // The sUSDS vault continues the accounting of v1.2
        IYieldRepurchaseFacilityV2.ReserveAsset memory sUsdsAsset = facility.getAssetConfig(
            address(sUsds)
        );
        assertEq(facility.backingVault(), address(sUsds), "sUSDS should be the backing vault");
        assertEq(sUsdsAsset.nextYield, inputs_.nextYield, "sUSDS: nextYield of v1.2");
        assertEq(
            sUsdsAsset.lastReserveBalance,
            inputs_.lastReserveBalance,
            "sUSDS: lastReserveBalance of v1.2"
        );
        assertEq(
            sUsdsAsset.lastConversionRate,
            inputs_.lastConversionRate,
            "sUSDS: lastConversionRate of v1.2"
        );
        assertEq(sUsdsAsset.unfundedYield, 0, "sUSDS: the treasury should cover the seed");

        // The sUSDe vault starts from the snapshots the vault reports in the block of the
        // launch: the reserve value of the treasury shares and of one whole share (1e18),
        // both rounded down by the vault
        IYieldRepurchaseFacilityV2.ReserveAsset memory sUsdeAsset = facility.getAssetConfig(
            address(sUsde)
        );
        assertEq(sUsdeAsset.nextYield, sUsdeNextYield_, "sUSDe: nextYield of the call");
        assertEq(
            sUsdeAsset.lastReserveBalance,
            sUsde.previewRedeem(inputs_.treasurySUsdeShares),
            "sUSDe: lastReserveBalance should be the value of the treasury shares"
        );
        assertEq(
            sUsdeAsset.lastConversionRate,
            sUsde.previewRedeem(_ONE),
            "sUSDe: lastConversionRate should be the value of one whole share"
        );

        // The weekly cycle resumes where v1.2 stopped
        assertEq(
            facility.epoch(),
            inputs_.epoch,
            "the facility should resume at the epoch of v1.2"
        );
        assertFalse(facility.isCycleSeedable(), "the seeding window should be closed");

        // Funds. The seed is the USDS of v1.2 plus the USDS value of its sUSDS shares at the
        // launch (18 decimals, rounded down by the vault), and it withdraws the shares that
        // cover it, rounded up by the vault: previewWithdraw(poolSeed) shares (18 decimals).
        uint256 poolSeed = inputs_.v1Usds + sUsds.previewRedeem(inputs_.v1SUsdsShares);
        uint256 seedShares = poolSeed == 0 ? 0 : sUsds.previewWithdraw(poolSeed);
        assertEq(
            IERC20(address(sUsds)).balanceOf(address(facility)),
            seedShares,
            "the facility should hold the shares that cover the funds of v1.2"
        );
        assertEq(
            usds.balanceOf(treasury),
            inputs_.treasuryUsds + inputs_.v1Usds,
            "the treasury should receive the USDS of v1.2"
        );
        // treasury sUSDS = before + shares of v1.2 - shares of the seed (18 decimals)
        assertEq(
            IERC20(address(sUsds)).balanceOf(treasury),
            inputs_.treasurySUsdsShares + inputs_.v1SUsdsShares - seedShares,
            "the treasury should give up only the shares of the seed"
        );
        assertEq(
            IERC20(address(sUsde)).balanceOf(treasury),
            inputs_.treasurySUsdeShares,
            "the treasury sUSDe should not move"
        );

        // The Heart slot
        assertEq(
            heart.getPeriodicTaskCount(),
            inputs_.heartTaskCount,
            "the number of periodic tasks should not change"
        );
        (address task, bytes4 selector) = heart.getPeriodicTaskAtIndex(inputs_.heartTaskIndex);
        assertEq(task, address(facility), "the facility should take the slot of v1.2");
        assertEq(selector, bytes4(0), "the facility should be called through execute()");
        assertFalse(heart.hasPeriodicTask(address(yieldRepoV1)), "v1.2 should not be a task");

        assertTrue(activator.isActivated(), "the activator should be activated");
    }

    // ========== EXPECTED ACTIONS ========== //

    /// @notice The action list the proposal must build, derived from the live state the way
    ///         the proposal derives it, so that a re-pin does not invalidate the assertion.
    /// @param sUsdeNextYield_ The next yield of the sUSDe vault that the `activate` action
    ///        carries.
    function _expectedActions(
        uint256 sUsdeNextYield_
    ) internal view returns (ExpectedAction[] memory expected) {
        ExpectedAction[_MAX_ACTION_COUNT] memory buffer;
        uint256 count = 0;
        address rolesAdminAddress = address(rolesAdmin);
        address activatorAddress = address(activator);

        if (!roles.hasRole(daoMS, YRF_ADMIN_ROLE)) {
            buffer[count++] = ExpectedAction({
                target: rolesAdminAddress,
                data: abi.encodeWithSelector(RolesAdmin.grantRole.selector, YRF_ADMIN_ROLE, daoMS),
                label: "grant yrf_admin to the DAO MS"
            });
        }
        if (!roles.hasRole(daoMS, BACKING_ADMIN_ROLE)) {
            buffer[count++] = ExpectedAction({
                target: rolesAdminAddress,
                data: abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    BACKING_ADMIN_ROLE,
                    daoMS
                ),
                label: "grant backing_admin to the DAO MS"
            });
        }
        buffer[count++] = ExpectedAction({
            target: rolesAdminAddress,
            data: abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                ADMIN_ROLE,
                activatorAddress
            ),
            label: "grant admin to the activator"
        });
        buffer[count++] = ExpectedAction({
            target: rolesAdminAddress,
            data: abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                _LOOP_DADDY_ROLE,
                activatorAddress
            ),
            label: "grant loop_daddy to the activator"
        });
        buffer[count++] = ExpectedAction({
            target: activatorAddress,
            data: abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator.activate.selector,
                sUsdeNextYield_
            ),
            label: "activate"
        });
        buffer[count++] = ExpectedAction({
            target: rolesAdminAddress,
            data: abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                ADMIN_ROLE,
                activatorAddress
            ),
            label: "revoke admin from the activator"
        });
        buffer[count++] = ExpectedAction({
            target: rolesAdminAddress,
            data: abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                _LOOP_DADDY_ROLE,
                activatorAddress
            ),
            label: "revoke loop_daddy from the activator"
        });
        if (roles.hasRole(daoMS, _LOOP_DADDY_ROLE)) {
            buffer[count++] = ExpectedAction({
                target: rolesAdminAddress,
                data: abi.encodeWithSelector(
                    RolesAdmin.revokeRole.selector,
                    _LOOP_DADDY_ROLE,
                    daoMS
                ),
                label: "revoke loop_daddy from the DAO MS"
            });
        }
        if (roles.hasRole(ocgTimelock, _LOOP_DADDY_ROLE)) {
            buffer[count++] = ExpectedAction({
                target: rolesAdminAddress,
                data: abi.encodeWithSelector(
                    RolesAdmin.revokeRole.selector,
                    _LOOP_DADDY_ROLE,
                    ocgTimelock
                ),
                label: "revoke loop_daddy from the OCG timelock"
            });
        }

        expected = new ExpectedAction[](count);
        for (uint256 i = 0; i < count; ++i) {
            expected[i] = buffer[i];
        }
    }

    /// @notice Asserts that the proposal built exactly the expected actions, in order.
    function _assertBuiltActions(ExpectedAction[] memory expected_) internal view {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = proposal
            .getProposalActions();
        assertEq(targets.length, expected_.length, "The built action count should match");
        assertLe(
            targets.length,
            _MAX_ACTION_COUNT,
            "The proposal should never build more than nine actions"
        );
        for (uint256 i = 0; i < expected_.length; ++i) {
            assertEq(
                targets[i],
                expected_[i].target,
                string.concat("target: ", expected_[i].label)
            );
            assertEq(
                payloads[i],
                expected_[i].data,
                string.concat("payload: ", expected_[i].label)
            );
            assertEq(values[i], 0, string.concat("value: ", expected_[i].label));
        }
    }

    function _selectorOf(bytes memory payload_) internal pure returns (bytes4 selector) {
        require(payload_.length >= _SELECTOR_BYTES, "the payload should carry a selector");
        return
            bytes4(
                (uint32(uint8(payload_[0])) << 24) |
                    (uint32(uint8(payload_[1])) << 16) |
                    (uint32(uint8(payload_[2])) << 8) |
                    uint32(uint8(payload_[3]))
            );
    }

    /// @notice The index of the first built action whose payload carries the selector.
    function _actionIndexOf(bytes4 selector_) internal view returns (uint256 index) {
        // Only the payloads are inspected; the build test asserts the targets and the values
        // forge-lint: disable-next-line(unused-return)
        (, , bytes[] memory payloads) = proposal.getProposalActions();
        for (uint256 i = 0; i < payloads.length; ++i) {
            if (_selectorOf(payloads[i]) == selector_) return i;
        }
        revert("the built actions carry no such selector");
    }

    // ========== REPLAY ========== //

    /// @notice Replays the built actions from the OCG timelock the way the timelock of the
    ///         governor sends them, one plain call each, and asserts that every action before
    ///         `failingIndex_` succeeds and that the action at `failingIndex_` fails with
    ///         `revertData_`. A `failingIndex_` equal to the action count replays every action
    ///         and expects no failure.
    function _replay(uint256 failingIndex_, bytes memory revertData_) internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = proposal
            .getProposalActions();
        assertLe(failingIndex_, targets.length, "The failing index should not pass the list");
        for (uint256 i = 0; i < targets.length && i <= failingIndex_; ++i) {
            assertEq(values[i], 0, string.concat("action ", vm.toString(i + 1), " sends no value"));
            address target = targets[i];
            bytes memory payload = payloads[i];
            vm.prank(ocgTimelock);
            // The timelock of the governor sends every action as a plain call, so does the replay
            // forge-lint: disable-next-item(low-level-calls)
            // solhint-disable-next-line avoid-low-level-calls
            (bool ok, bytes memory data) = target.call(payload);
            if (i < failingIndex_) {
                assertTrue(ok, string.concat("action ", vm.toString(i + 1), " should succeed"));
                continue;
            }
            assertFalse(ok, string.concat("action ", vm.toString(i + 1), " should fail"));
            assertEq(
                data,
                revertData_,
                string.concat("action ", vm.toString(i + 1), " should revert with the named error")
            );
        }
    }

    /// @notice Replays every built action from the OCG timelock and expects each to succeed.
    function _replayAll() internal {
        // Only the count is read here; `_replay` reads the actions again
        // forge-lint: disable-next-line(unused-return)
        (address[] memory targets, , ) = proposal.getProposalActions();
        _replay(targets.length, "");
    }

    // ========== GOVERNOR ========== //

    /// @notice Takes the built proposal through the governor up to the point where it can be
    ///         executed: proposes it, activates it, votes for it, queues it and passes the
    ///         timelock delay. The steps are the ones the simulator of the proposal takes.
    /// @return proposalId The id the governor assigned.
    function _queueOnGovernor() internal returns (uint256 proposalId) {
        GovernorBravoDelegate rigGovernor = governor;
        address gohm = addresses.getAddress("olympus-legacy-gohm");
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = proposal
            .getProposalActions();
        string memory description = proposal.description();

        // The proposer needs the larger of the proposal threshold and the high risk quorum
        uint256 quorumVotes = rigGovernor.getHighRiskQuorumVotes();
        uint256 thresholdVotes = rigGovernor.getProposalThresholdVotes();
        deal(gohm, proposer, quorumVotes > thresholdVotes ? quorumVotes : thresholdVotes);
        vm.prank(proposer);
        IVotes(gohm).delegate(proposer);
        vm.roll(vm.getBlockNumber() + 1);

        vm.prank(proposer);
        proposalId = rigGovernor.propose(
            targets,
            values,
            new string[](targets.length),
            payloads,
            description
        );

        vm.roll(vm.getBlockNumber() + rigGovernor.votingDelay() + 1);
        vm.prank(proposer);
        rigGovernor.activate(proposalId);

        vm.roll(vm.getBlockNumber() + rigGovernor.votingDelay() + 1);
        vm.prank(proposer);
        rigGovernor.castVote(proposalId, 1);

        vm.roll(vm.getBlockNumber() + rigGovernor.votingPeriod());
        rigGovernor.queue(proposalId);

        skip(Timelock(payable(ocgTimelock)).delay());
    }

    // ========== ROLE HELPERS ========== //

    /// @notice Grants the role from the admin of RolesAdmin unless the account holds it.
    function _grantRole(bytes32 role_, address account_) internal {
        if (roles.hasRole(account_, role_)) return;
        RolesAdmin rigRolesAdmin = rolesAdmin;
        vm.prank(rigRolesAdmin.admin());
        rigRolesAdmin.grantRole(role_, account_);
    }

    /// @notice Revokes the role from the admin of RolesAdmin when the account holds it.
    function _revokeRole(bytes32 role_, address account_) internal {
        if (!roles.hasRole(account_, role_)) return;
        RolesAdmin rigRolesAdmin = rolesAdmin;
        vm.prank(rigRolesAdmin.admin());
        rigRolesAdmin.revokeRole(role_, account_);
    }

    /// @notice Shuts the YieldRepurchaseFacility v1.2 down from a holder of `loop_daddy`,
    ///         without a token to transfer.
    function _shutdownV1(address caller_) internal {
        IYieldRepoV1 rigV1 = yieldRepoV1;
        vm.prank(caller_);
        rigV1.shutdown(new address[](0));
    }

    // ========== STRING HELPERS ========== //

    function _startsWith(
        string memory value_,
        string memory prefix_
    ) internal pure returns (bool starts) {
        bytes memory value = bytes(value_);
        bytes memory prefix = bytes(prefix_);
        if (value.length < prefix.length) return false;
        for (uint256 i = 0; i < prefix.length; ++i) {
            if (value[i] != prefix[i]) return false;
        }
        return true;
    }
}
