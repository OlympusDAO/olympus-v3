// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

// Fork-only setup calls trusted VM/registry helpers; its bookkeeping is not a production entry point.
// forge-lint: disable-start(reentrancy-no-eth)

// Interfaces
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IBurnerLoansActivator} from "src/proposals/interfaces/IBurnerLoansActivator.sol";

// Libraries
import {fromSubKeycode, toSubKeycode} from "src/Submodules.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ContinuouslyUpdatedFeed} from "./ContinuouslyUpdatedFeed.sol";
import {Actions, Kernel, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansActivator} from "src/proposals/BurnerLoansActivator.sol";
import {BurnerLoansProposal} from "src/proposals/BurnerLoansProposal.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {BurnerLoansDeployHarness} from "src/test/proposals/BurnerLoansActivator/fixtures/BurnerLoansDeployHarness.sol";
import {ProposalTest} from "src/test/proposals/ProposalTest.sol";

/// @dev Real mainnet Kernel, PRICE v1.2, Heart, tokens, vaults and Governor. The deployed Burner
///      Loans graph uses the saved deployment sequence and a pre-populated real BackingOracle.
///      External-feed publication cadence is adapted. No launch role, PRICE asset or custody market is seeded.
abstract contract BurnerLoansForkTest is ProposalTest {
    uint256 internal constant _BLOCK = 25_973_712;
    address internal constant _USDE_FEED = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;
    IBurnerLoansActivator.Deployment internal _graph;
    BurnerLoansActivator internal _activator;
    BurnerLoansProposal internal _proposal;
    BurnerLoansDeployHarness internal _deployer;
    Kernel internal _kernel;
    IPRICEv2 internal _price;
    ROLESv1 internal _roles;
    IBurnerLoansCore internal _core;
    IBurnerLoansCollateral internal _collateral;
    IBurnerLoansDebt internal _debt;
    IBurnerLoansInventory internal _inventory;
    IBurnerLoansLens internal _lens;
    address internal _dao;
    address internal _timelock;
    address internal _emergency;
    bytes32 internal _ohmConfiguration;
    bytes32 internal _usdsConfiguration;
    address[] internal _existingHeartTasks;
    bytes4[] internal _existingHeartSelectors;

    function setUp() public virtual {
        // The selected fork is used immediately; its numeric ID is not needed.
        // forge-lint: disable-next-item(unused-return)
        vm.createSelectFork(_RPC_ALIAS, _BLOCK);
        _proposal = new BurnerLoansProposal();
        hasBeenSubmitted = false;
        _setupSuite(address(_proposal));
        suite.setDebug(false);
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
        _price = IPRICEv2(address(_kernel.getModuleForKeycode(toKeycode("PRICE"))));
        _roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        _dao = addresses.getAddress("olympus-multisig-dao");
        _timelock = addresses.getAddress("olympus-timelock");
        _emergency = addresses.getAddress("olympus-multisig-emergency");
        (uint8 major, uint8 minor) = IVersioned(address(_price)).VERSION();
        assertEq(major, 1, "Real PRICE major is not spoofed");
        assertEq(minor, 2, "Real PRICE minor is not spoofed");
        // Only the pinned answer is witnessed here; feed timestamps are adapted below.
        // forge-lint: disable-next-item(unused-return)
        (, int256 answer, , , ) = AggregatorV2V3Interface(_USDE_FEED).latestRoundData();
        assertEq(answer, 99_976_373, "Witness the pinned USDe feed before timestamp adaptation");
        _deployGraph();
        _registerGraph();
        _core = IBurnerLoansCore(_graph.core);
        _collateral = IBurnerLoansCollateral(_graph.collateral);
        _debt = IBurnerLoansDebt(_graph.debt);
        _inventory = IBurnerLoansInventory(_graph.inventory);
        _lens = IBurnerLoansLens(_graph.lens);
        _prepareKernel();
        assertFalse(_price.isAssetApproved(_graph.usde), "Fixture does not admit USDe to PRICE");
        assertEq(_core.getAssetCount(), 0, "Fixture does not configure lending markets");
        assertFalse(IEnabler(_graph.core).isEnabled(), "Fixture does not enable Core");
        assertFalse(_roles.hasRole(_dao, BURNER_LOANS_ADMIN_ROLE), "Proposal owns DAO role grant");
        _ohmConfiguration = keccak256(abi.encode(_price.getAssetData(_graph.ohm)));
        _usdsConfiguration = keccak256(abi.encode(_price.getAssetData(_graph.usds)));
        (address[] memory tasks, bytes4[] memory selectors) = IPeriodicTaskManager(_graph.heart)
            .getPeriodicTasks();
        _existingHeartTasks = tasks;
        _existingHeartSelectors = selectors;
        _adaptAssetFeeds(_graph.ohm);
        _adaptAssetFeeds(_graph.usds);
        _adaptFeed(_USDE_FEED);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        // The expected disabled-state revert returns no deposit result.
        // forge-lint: disable-next-item(unused-return)
        _collateral.depositCollateral(_graph.usds, 1e18, address(this));
        // The existing simulator changes the Kernel executor to the governance timelock. This
        // is simulator preparation, not an action contained in the launch proposal.
        _simulateProposal();
    }

    // The saved Burner Loans fixture sequence requires ordered real constructor calls.
    // forge-lint: disable-next-item(calls-loop)
    function _deployGraph() private {
        // This test-only dispatcher embeds every creation bytecode and exceeds EIP-3860.
        // It has no constructor/immutable initialization; all consumed state is seeded below.
        // Its inherited IS_SCRIPT marker is unused. Each production sequence entry still runs
        // its actual constructor normally, without replacing production code or metadata.
        address dispatcher = makeAddr("forkDeploymentDispatcher");
        vm.etch(
            dispatcher,
            vm.getDeployedCode("BurnerLoansDeployHarness.sol:BurnerLoansDeployHarness")
        );
        vm.allowCheatcodes(dispatcher);
        _deployer = BurnerLoansDeployHarness(dispatcher);
        string memory sequence = vm.readFile(
            "src/scripts/deploy/savedDeployments/burner_loans.json"
        );
        _deployer.loadSequence(sequence);
        _deployer.setDependency("olympus.Kernel", address(_kernel));
        _deployer.setDependency("olympus.legacy.OHM", addresses.getAddress("olympus-legacy-ohm"));
        // Deploy and prepare the shared oracle through its separate production sequence.
        string memory oracleSequence = vm.readFile(
            "src/scripts/deploy/savedDeployments/backing_oracle.json"
        );
        _deployer.loadSequence(oracleSequence);
        // Only addresses are needed; the dispatcher records the deployment keys.
        // forge-lint: disable-next-line(unused-return)
        (address oracle, ) = _deployer.deployNamed("BackingOracle");
        // The immutable queue address is consumed below, not its recorded key.
        // forge-lint: disable-next-line(unused-return)
        (address oracleQueue, ) = _deployer.deployNamed("BackingOracleConfigTimelock");
        vm.startPrank(_kernel.executor());
        _kernel.executeAction(Actions.ActivatePolicy, oracle);
        _kernel.executeAction(Actions.ActivatePolicy, oracleQueue);
        vm.stopPrank();
        vm.startPrank(_timelock);
        IConfigOperator(oracle).setConfigOperator(oracleQueue);
        IEnabler(oracle).enable(abi.encode(uint256(12e18)));
        IEnabler(oracleQueue).enable("");
        vm.stopPrank();
        _deployer.setDependency(
            "olympus.policies.OlympusHeart",
            addresses.getAddress("olympus-policy-heart-1_7")
        );
        _deployer.setDependency("olympus.governance.Timelock", _timelock);
        _deployer.setDependency(
            "olympus.policies.OlympusPriceConfigV2",
            addresses.getAddress("olympus-policy-price-config-2_0")
        );
        _deployer.setDependency(
            "external.tokens.USDS",
            addresses.getAddress("external-tokens-usds")
        );
        _deployer.setDependency(
            "external.tokens.USDe",
            addresses.getAddress("external-tokens-usde")
        );
        _deployer.setDependency(
            "external.tokens.sUSDS",
            addresses.getAddress("external-tokens-susds")
        );
        _deployer.setDependency(
            "external.tokens.sUSDe",
            addresses.getAddress("external-tokens-susde")
        );
        _deployer.setDependency(
            "olympus.periphery.ReceiptTokenManager",
            0xD98B5b2E4D5d6Cd554115DE19EfB7A9084BEddd1
        );
        _deploySharedSequences();
        _deployer.loadSequence(sequence);
        string[] memory names = abi.decode(vm.parseJson(sequence, ".sequence[*].name"), (string[]));
        for (uint256 i; i < names.length; ++i) {
            // The deployment key is recorded by the harness; this loop needs only the deployed address.
            // forge-lint: disable-next-item(unused-return)
            (address deployed, ) = _deployer.deployNamed(names[i]);
            assertLe(deployed.code.length, 24_576, "Production sequence entry fits EIP-170");
        }
        _activator = BurnerLoansActivator(
            _deployer.resolve("olympus.proposals.BurnerLoansActivator")
        );
        _graph = _deployer.deployment();
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

    function _registerGraph() private {
        addresses.addAddress("olympus-module-floan", _graph.floan);
        addresses.addAddress("olympus-policy-price-cache", _graph.priceCache);
        addresses.addAddress("olympus-policy-revenue-distributor", _graph.revenueDistributor);
        addresses.addAddress(
            "olympus-policy-revenue-distributor-config-timelock",
            _graph.revenueDistributorTimelock
        );
        addresses.addAddress(
            "olympus-policy-revenue-distributor-task",
            _graph.revenueDistributorTask
        );

        addresses.addAddress("olympus-policy-deposit-manager", _graph.depositManager);
        addresses.addAddress("olympus-policy-burner-loans-core", _graph.core);
        addresses.addAddress("olympus-policy-burner-loans-config", _graph.config);
        addresses.addAddress("olympus-policy-burner-loans-inventory", _graph.inventory);
        addresses.addAddress("olympus-policy-burner-loans-payout", _graph.payout);
        addresses.addAddress("olympus-policy-burner-loans-risk", _graph.risk);
        addresses.addAddress("olympus-policy-burner-loans-collateral", _graph.collateral);
        addresses.addAddress("olympus-policy-burner-loans-debt", _graph.debt);
        addresses.addAddress("olympus-policy-burner-loans-seize", _graph.seize);
        addresses.addAddress("olympus-periphery-burner-loans-auth", _graph.auth);
        addresses.addAddress("olympus-periphery-burner-loans-lens", _graph.lens);
        addresses.addAddress("olympus-policy-burner-loans-seizer-task", _graph.seizerTask);
        addresses.addAddress(
            "olympus-policy-burner-loans-yield-claimer-task",
            _graph.yieldClaimerTask
        );
        addresses.addAddress("olympus-policy-burner-loans-config-timelock", _graph.configTimelock);
        addresses.addAddress(
            "olympus-policy-burner-loans-risk-config-timelock",
            _graph.riskTimelock
        );
        addresses.addAddress(
            "olympus-policy-burner-loans-payout-config-timelock",
            _graph.payoutTimelock
        );
        addresses.addAddress(
            "olympus-policy-burner-loans-inventory-config-timelock",
            _graph.inventoryTimelock
        );
        addresses.addAddress("olympus-proposal-burner-loans-activator", address(_activator));
        addresses.addAddress(
            "olympus-policy-backing-oracle-config-timelock",
            _deployer.resolve("olympus.policies.BackingOracleConfigTimelock")
        );
        addresses.addAddress("olympus-policy-backing-oracle", _graph.backingOracle);
    }

    // The integration fixture prepares Kernel membership directly before executing governance.
    // forge-lint: disable-next-item(calls-loop)
    function _prepareKernel() private {
        address[] memory policies = _deployer.policies();
        vm.startPrank(_kernel.executor());
        _kernel.executeAction(Actions.InstallModule, _graph.floan);
        for (uint256 i; i < policies.length; ++i)
            _kernel.executeAction(Actions.ActivatePolicy, policies[i]);
        vm.stopPrank();
    }

    function _adaptAssetFeeds(address asset_) private {
        IPRICEv2.Component[] memory feeds = abi.decode(
            _price.getAssetData(asset_).feeds,
            (IPRICEv2.Component[])
        );
        for (uint256 i; i < feeds.length; ++i) {
            if (fromSubKeycode(feeds[i].target) != fromSubKeycode(toSubKeycode("PRICE.CHAINLINK")))
                continue;
            if (feeds[i].params.length == 64) {
                (address feed, ) = abi.decode(feeds[i].params, (address, uint48));
                _adaptFeed(feed);
            } else if (feeds[i].params.length == 128) {
                (address first, , address second, ) = abi.decode(
                    feeds[i].params,
                    (address, uint48, address, uint48)
                );
                _adaptFeed(first);
                _adaptFeed(second);
            }
        }
    }

    // Finite fixture feed lists use trusted read-only feeds and test-only cadence adapters.
    // forge-lint: disable-next-item(calls-loop)
    function _adaptFeed(address feed_) private {
        // The adapter preserves round identifiers and price while replacing publication timestamps.
        // forge-lint: disable-next-item(unused-return)
        (uint80 round, int256 answer, , , uint80 answered) = AggregatorV2V3Interface(feed_)
            .latestRoundData();
        assertGt(answer, 0, "External feed adapter preserves a positive witnessed answer");
        ContinuouslyUpdatedFeed adapter = new ContinuouslyUpdatedFeed(round, answer, answered);
        vm.mockFunction(feed_, address(adapter), abi.encodeWithSignature("latestRoundData()"));
    }

    function _assertHeartOrder() internal view {
        (address[] memory tasks, bytes4[] memory selectors) = IPeriodicTaskManager(_graph.heart)
            .getPeriodicTasks();
        assertEq(
            tasks.length,
            _existingHeartTasks.length + 3,
            "Heart retains all previous tasks plus three launch tasks"
        );
        assertEq(tasks[0], _graph.seizerTask, "Seizer precedes yield collection");
        assertEq(tasks[1], _graph.yieldClaimerTask, "Yield collection precedes distribution");
        assertEq(tasks[2], _graph.revenueDistributorTask, "Distributor follows yield collection");
        for (uint256 i; i < _existingHeartTasks.length; ++i) {
            assertEq(
                tasks[i + 3],
                _existingHeartTasks[i],
                "Existing task relative order is preserved"
            );
            assertEq(
                selectors[i + 3],
                _existingHeartSelectors[i],
                "Existing custom task selector is preserved"
            );
        }
    }
}

// forge-lint: disable-end(reentrancy-no-eth)
