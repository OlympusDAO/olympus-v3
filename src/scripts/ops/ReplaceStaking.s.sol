// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {Script, console2} from "forge-std/Script.sol";
import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";
import {Kernel, Actions, Policy, Keycode, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {CHREGv1} from "modules/CHREG/CHREG.v1.sol";

import {OlympusGovDelegation} from "modules/DLGTE/OlympusGovDelegation.sol";
import {DelegateEscrowFactory} from "src/external/cooler/DelegateEscrowFactory.sol";
import {CoolerLtvOracle} from "policies/cooler/CoolerLtvOracle.sol";
import {MonoCooler} from "policies/cooler/MonoCooler.sol";
import {Clearinghouse} from "policies/Clearinghouse.sol";
import {ZeroDistributor} from "policies/Distributor/ZeroDistributor.sol";
import {EmissionManager} from "policies/EmissionManager.sol";
import {Minter} from "policies/Minter.sol";
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {IStaking} from "interfaces/IStaking.sol";
import {IgOHM} from "interfaces/IgOHM.sol";

/// @title Replace Staking and Dependent Contracts
/// @notice Deploys new DLGTE module and all policies dependent on gOHM/Staking
/// @dev Must be run after VerifyLegacyStaking.s.sol has verified new legacy contracts
/// @dev Usage: forge script ReplaceStaking.s.sol --rpc-url $RPC_URL
contract ReplaceStaking is Script, WithEnvironment {
    using stdJson for string;

    // ========== CONFIGURATION ========== //

    uint256 constant SAMPLE_OHM_AMOUNT = 1_000 * 1e9; // 1,000 OHM (9 decimals) for testing staking
    bytes32 constant MINT_CATEGORY = "test";

    // ========== STATE ========== //

    // New legacy contract addresses (from env.json after VerifyLegacyStaking)
    address public newSOHM;
    address public newGOHM;
    address public newStaking;

    // Existing addresses from env.json
    address public kernel;
    address public executor;
    address public roles;
    address public mintr;
    address public chreg;
    address public minter;

    // Old policy addresses (for deactivation)
    address public oldMonoCooler;
    address public oldClearinghouse;
    address public oldZeroDistributor;
    address public oldEmissionManager;
    address public oldLtvOracle;
    address public oldDLGTE;

    // External addresses
    address public ohm;
    address public coolerFactory;
    address public sReserve; // sDAI or sUSDS
    address public reserve; // USDS
    address public bondAuctioneer;
    address public bondTeller;
    address public cdAuctioneer;
    address public delegateEscrowFactory;

    // New deployed addresses
    address public newDLGTE;
    address public newLtvOracle;
    address public newMonoCooler;
    address public newClearinghouse;
    address public newZeroDistributor;
    address public newEmissionManager;

    // Parameters queried from chain
    uint96 public interestRateWad;
    uint256 public minDebtRequired;

    // LTV Oracle parameters (queried from old contract)
    uint96 public initialOriginationLtv;
    uint96 public maxOriginationLtvDelta;
    uint32 public minOriginationLtvTargetTimeDelta;
    uint96 public maxOriginationLtvRateOfChange;
    uint16 public maxLiquidationLtvPremiumBps;
    uint16 public liquidationLtvPremiumBps;

    // ========== RUN ========== //

    /// @notice Main entry point - chain is determined automatically from block.chainid
    function run() external {
        string memory chainName = ChainUtils._getChainName(block.chainid);
        _loadEnv(chainName);
        _loadAddresses();
        _queryChainParameters();

        // Verify new legacy contracts are deployed
        _verifyLegacyContracts();

        vm.startBroadcast();

        // Phase 1: Deactivate old policies
        _deactivateOldPolicies();

        // Phase 2: Upgrade DLGTE module
        _upgradeDLGTE();

        // Phase 3: Deploy new policies
        _deployNewPolicies();

        // Phase 4: Activate new policies
        _activateNewPolicies();

        // Phase 5: Update ClearinghouseRegistry
        _updateClearinghouseRegistry();

        // Phase 6: Test staking (mint sample OHM and stake to gOHM)
        _testStaking();

        vm.stopBroadcast();

        // Phase 7: Update env.json
        _updateEnvJson();

        // Phase 8: Verify deployment
        _verifyDeployment();

        // Print summary
        _printSummary();
    }

    // ========== SETUP ========== //

    function _loadAddresses() internal {
        // New legacy addresses
        newSOHM = _envAddressNotZero("olympus.legacy.sOHM");
        newGOHM = _envAddressNotZero("olympus.legacy.gOHM");
        newStaking = _envAddressNotZero("olympus.legacy.Staking");

        // Core
        kernel = _envAddressNotZero("olympus.Kernel");
        executor = _envAddressNotZero("olympus.config.KernelExecutor");

        // Modules
        roles = _envAddressNotZero("olympus.modules.OlympusRoles");
        mintr = _envAddressNotZero("olympus.modules.OlympusMinter");
        chreg = _envAddressNotZero("olympus.modules.OlympusClearinghouseRegistry");
        oldDLGTE = _envAddressNotZero("olympus.modules.OlympusGovDelegation");

        // Policies
        minter = _envAddressNotZero("olympus.policies.Minter");
        oldMonoCooler = _envAddressNotZero("olympus.policies.CoolerV2");
        oldClearinghouse = _envAddressNotZero("olympus.policies.Clearinghouse");
        oldZeroDistributor = _envAddressNotZero("olympus.policies.ZeroDistributor");
        oldEmissionManager = _envAddressNotZero("olympus.policies.EmissionManager");
        oldLtvOracle = _envAddressNotZero("olympus.policies.CoolerV2LtvOracle");

        // External
        ohm = _envAddressNotZero("olympus.legacy.OHM");
        coolerFactory = _envAddressNotZero("external.cooler.CoolerFactory");
        sReserve = _envAddressNotZero("external.tokens.sDAI");
        reserve = _envAddressNotZero("external.tokens.USDS");
        bondAuctioneer = _envAddressNotZero("external.bond-protocol.BondFixedTermAuctioneer");
        bondTeller = _envAddressNotZero("external.bond-protocol.BondFixedTermTeller");
        cdAuctioneer = _envAddressNotZero("olympus.policies.ConvertibleDepositAuctioneer");
        delegateEscrowFactory = _envAddressNotZero("olympus.periphery.DelegateEscrowFactory");

        console2.log("Loaded addresses from env.json");
    }

    function _queryChainParameters() internal {
        // Query MonoCooler parameters
        interestRateWad = MonoCooler(oldMonoCooler).interestRateWad();
        minDebtRequired = MonoCooler(oldMonoCooler).minDebtRequired();

        // Query LTV Oracle parameters
        CoolerLtvOracle ltvOracle = CoolerLtvOracle(oldLtvOracle);
        initialOriginationLtv = ltvOracle.currentOriginationLtv();
        maxOriginationLtvDelta = ltvOracle.maxOriginationLtvDelta();
        minOriginationLtvTargetTimeDelta = ltvOracle.minOriginationLtvTargetTimeDelta();
        maxOriginationLtvRateOfChange = ltvOracle.maxOriginationLtvRateOfChange();
        maxLiquidationLtvPremiumBps = ltvOracle.maxLiquidationLtvPremiumBps();
        liquidationLtvPremiumBps = ltvOracle.liquidationLtvPremiumBps();

        console2.log("Queried chain parameters:");
        console2.log("  interestRateWad:", interestRateWad);
        console2.log("  minDebtRequired:", minDebtRequired);
        console2.log("  initialOriginationLtv:", initialOriginationLtv);
    }

    function _verifyLegacyContracts() internal view {
        uint256 index = IgOHM(newGOHM).index();
        require(index == 269238508004, "gOHM index not set correctly");
        console2.log("Legacy contracts verified - gOHM index:", index);
    }

    // ========== PHASE 1: DEACTIVATE OLD POLICIES ========== //

    function _deactivateOldPolicies() internal {
        console2.log("\n=== Phase 1: Deactivating Old Policies ===");

        Kernel(kernel).executeAction(Actions.DeactivatePolicy, oldMonoCooler);
        console2.log("Deactivated old MonoCooler:", oldMonoCooler);

        Kernel(kernel).executeAction(Actions.DeactivatePolicy, oldClearinghouse);
        console2.log("Deactivated old Clearinghouse:", oldClearinghouse);

        Kernel(kernel).executeAction(Actions.DeactivatePolicy, oldZeroDistributor);
        console2.log("Deactivated old ZeroDistributor:", oldZeroDistributor);

        Kernel(kernel).executeAction(Actions.DeactivatePolicy, oldEmissionManager);
        console2.log("Deactivated old EmissionManager:", oldEmissionManager);

        Kernel(kernel).executeAction(Actions.DeactivatePolicy, oldLtvOracle);
        console2.log("Deactivated old LtvOracle:", oldLtvOracle);
    }

    // ========== PHASE 2: UPGRADE DLGTE MODULE ========== //

    function _upgradeDLGTE() internal {
        console2.log("\n=== Phase 2: Upgrading DLGTE Module ===");

        OlympusGovDelegation dlgte = new OlympusGovDelegation(
            Kernel(kernel),
            newGOHM,
            DelegateEscrowFactory(delegateEscrowFactory)
        );
        newDLGTE = address(dlgte);
        console2.log("Deployed new DLGTE:", newDLGTE);

        Kernel(kernel).executeAction(Actions.UpgradeModule, newDLGTE);
        console2.log("Upgraded DLGTE in Kernel");
    }

    // ========== PHASE 3: DEPLOY NEW POLICIES ========== //

    function _deployNewPolicies() internal {
        console2.log("\n=== Phase 3: Deploying New Policies ===");

        // Deploy CoolerLtvOracle
        _deployLtvOracle();

        // Deploy MonoCooler
        _deployMonoCooler();

        // Deploy Clearinghouse
        _deployClearinghouse();

        // Deploy ZeroDistributor
        _deployZeroDistributor();

        // Deploy EmissionManager
        _deployEmissionManager();
    }

    function _deployLtvOracle() internal {
        console2.log("\n--- Deploying CoolerLtvOracle ---");

        CoolerLtvOracle ltvOracle = new CoolerLtvOracle(
            kernel, // kernel_
            newGOHM, // collateralToken_ (gOHM)
            reserve, // debtToken_ (USDS)
            initialOriginationLtv, // initialOriginationLtv_
            maxOriginationLtvDelta, // maxOriginationLtvDelta_
            minOriginationLtvTargetTimeDelta, // minOriginationLtvTargetTimeDelta_
            maxOriginationLtvRateOfChange, // maxOriginationLtvRateOfChange_
            maxLiquidationLtvPremiumBps, // maxLiquidationLtvPremiumBps_
            liquidationLtvPremiumBps // liquidationLtvPremiumBps_
        );
        newLtvOracle = address(ltvOracle);
        console2.log("Deployed CoolerLtvOracle:", newLtvOracle);
    }

    function _deployMonoCooler() internal {
        console2.log("\n--- Deploying MonoCooler ---");

        MonoCooler cooler = new MonoCooler(
            ohm, // ohm_
            newGOHM, // gohm_
            newStaking, // staking_
            kernel, // kernel_
            newLtvOracle, // ltvOracle_
            interestRateWad, // interestRateWad_
            minDebtRequired // minDebtRequired_
        );
        newMonoCooler = address(cooler);
        console2.log("Deployed MonoCooler:", newMonoCooler);
    }

    function _deployClearinghouse() internal {
        console2.log("\n--- Deploying Clearinghouse ---");

        Clearinghouse ch = new Clearinghouse(
            ohm, // ohm_
            newGOHM, // gohm_
            newStaking, // staking_
            sReserve, // sReserve_ (sDAI)
            coolerFactory, // coolerFactory_
            kernel // kernel_
        );
        newClearinghouse = address(ch);
        console2.log("Deployed Clearinghouse:", newClearinghouse);
    }

    function _deployZeroDistributor() internal {
        console2.log("\n--- Deploying ZeroDistributor ---");

        ZeroDistributor zd = new ZeroDistributor(
            newStaking // staking_
        );
        newZeroDistributor = address(zd);
        console2.log("Deployed ZeroDistributor:", newZeroDistributor);
    }

    function _deployEmissionManager() internal {
        console2.log("\n--- Deploying EmissionManager ---");

        EmissionManager em = new EmissionManager(
            Kernel(kernel), // kernel_
            ohm, // ohm_
            newGOHM, // gohm_
            reserve, // reserve_ (USDS)
            sReserve, // sReserve_ (sDAI)
            bondAuctioneer, // bondAuctioneer_
            cdAuctioneer, // cdAuctioneer_
            bondTeller // teller_
        );
        newEmissionManager = address(em);
        console2.log("Deployed EmissionManager:", newEmissionManager);
    }

    // ========== PHASE 4: ACTIVATE NEW POLICIES ========== //

    function _activateNewPolicies() internal {
        console2.log("\n=== Phase 4: Activating New Policies ===");

        Kernel(kernel).executeAction(Actions.ActivatePolicy, newLtvOracle);
        console2.log("Activated new LtvOracle:", newLtvOracle);

        Kernel(kernel).executeAction(Actions.ActivatePolicy, newMonoCooler);
        console2.log("Activated new MonoCooler:", newMonoCooler);

        Kernel(kernel).executeAction(Actions.ActivatePolicy, newClearinghouse);
        console2.log("Activated new Clearinghouse:", newClearinghouse);

        Kernel(kernel).executeAction(Actions.ActivatePolicy, newZeroDistributor);
        console2.log("Activated new ZeroDistributor:", newZeroDistributor);

        Kernel(kernel).executeAction(Actions.ActivatePolicy, newEmissionManager);
        console2.log("Activated new EmissionManager:", newEmissionManager);
    }

    // ========== PHASE 5: UPDATE CLEARINGHOUSE REGISTRY ========== //

    function _updateClearinghouseRegistry() internal {
        console2.log("\n=== Phase 5: Updating ClearinghouseRegistry ===");

        // Deactivate old Clearinghouse
        CHREGv1(chreg).deactivateClearinghouse(oldClearinghouse);
        console2.log("Deactivated old Clearinghouse in registry:", oldClearinghouse);

        // Activate new Clearinghouse
        CHREGv1(chreg).activateClearinghouse(newClearinghouse);
        console2.log("Activated new Clearinghouse in registry:", newClearinghouse);
    }

    // ========== PHASE 6: TEST STAKING ========== //

    function _testStaking() internal {
        console2.log("\n=== Phase 6: Testing Staking ===");

        address deployer = msg.sender;
        console2.log("Deployer address:", deployer);

        // Ensure mint category exists
        Minter minterContract = Minter(minter);
        if (!minterContract.categoryApproved(MINT_CATEGORY)) {
            console2.log("Adding mint category:", vm.toString(MINT_CATEGORY));
            minterContract.addCategory(MINT_CATEGORY);
        } else {
            console2.log("Mint category already exists:", vm.toString(MINT_CATEGORY));
        }

        // Mint sample OHM to deployer
        minterContract.mint(deployer, SAMPLE_OHM_AMOUNT, MINT_CATEGORY);
        console2.log("Minted", SAMPLE_OHM_AMOUNT / 1e9, "OHM to deployer");

        // Approve Staking to spend OHM
        OlympusERC20Token(ohm).approve(newStaking, SAMPLE_OHM_AMOUNT);
        console2.log("Approved Staking to spend OHM");

        // Get initial gOHM balance
        uint256 initialGOHMBalance = ERC20(newGOHM).balanceOf(deployer);
        console2.log("Initial gOHM balance:", initialGOHMBalance);

        // Stake OHM to get gOHM (claim = false, rebasing = true to get gOHM)
        uint256 stakedAmount = IStaking(newStaking).stake(
            deployer, // to_
            SAMPLE_OHM_AMOUNT, // amount_
            false, // claim_ (don't claim from warmup)
            true // rebasing_ (get gOHM, not sOHM)
        );
        console2.log("Staked OHM, received gOHM:", stakedAmount);

        // Verify gOHM balance increased
        uint256 finalGOHMBalance = ERC20(newGOHM).balanceOf(deployer);
        console2.log("Final gOHM balance:", finalGOHMBalance);
        require(finalGOHMBalance > initialGOHMBalance, "Staking failed - no gOHM received");

        console2.log("OK: Staking verified - OHM can be staked to gOHM");
    }

    // ========== PHASE 7: UPDATE ENV.JSON ========== //

    function _updateEnvJson() internal {
        console2.log("\n=== Phase 7: Updating env.json ===");

        _writeToEnv("olympus.modules.OlympusGovDelegation", newDLGTE);
        _writeToEnv("olympus.policies.CoolerV2LtvOracle", newLtvOracle);
        _writeToEnv("olympus.policies.CoolerV2", newMonoCooler);
        _writeToEnv("olympus.policies.Clearinghouse", newClearinghouse);
        _writeToEnv("olympus.policies.ZeroDistributor", newZeroDistributor);
        _writeToEnv("olympus.policies.EmissionManager", newEmissionManager);

        console2.log("env.json updated successfully");
    }

    // ========== PHASE 8: VERIFY DEPLOYMENT ========== //

    function _verifyDeployment() internal view {
        console2.log("\n=== Phase 8: Verifying Deployment ===");

        // Verify sOHM index
        uint256 sOHMIndex = IgOHM(newSOHM).index();
        require(sOHMIndex == 269238508004, "sOHM index mismatch");
        console2.log("OK: sOHM index:", sOHMIndex);

        // Verify gOHM index
        uint256 gOHMIndex = IgOHM(newGOHM).index();
        require(gOHMIndex == 269238508004, "gOHM index mismatch");
        console2.log("OK: gOHM index:", gOHMIndex);

        // Verify new MonoCooler is active
        bool monoCoolerActive = Kernel(kernel).isPolicyActive(Policy(newMonoCooler));
        require(monoCoolerActive, "New MonoCooler not active");
        console2.log("OK: New MonoCooler is active");

        // Verify old MonoCooler is deactivated
        bool oldMonoCoolerActive = Kernel(kernel).isPolicyActive(Policy(oldMonoCooler));
        require(!oldMonoCoolerActive, "Old MonoCooler still active");
        console2.log("OK: Old MonoCooler is deactivated");

        // Verify new Clearinghouse is active
        bool clearhinghouseActive = Kernel(kernel).isPolicyActive(Policy(newClearinghouse));
        require(clearhinghouseActive, "New Clearinghouse not active");
        console2.log("OK: New Clearinghouse is active");

        console2.log("\nAll verifications passed!");
    }

    function _writeToEnv(string memory key_, address value_) internal {
        string[] memory inputs = new string[](3);
        inputs[0] = "./src/scripts/deploy/write_deployment.sh";
        inputs[1] = string.concat("current.", chain, ".", key_);
        inputs[2] = vm.toString(value_);
        vm.ffi(inputs);
    }

    // ========== SUMMARY ========== //

    function _printSummary() internal view {
        console2.log("\n========================================");
        console2.log("         DEPLOYMENT SUMMARY");
        console2.log("========================================");
        console2.log("\nLegacy Contracts:");
        console2.log("  sOHM:     ", newSOHM);
        console2.log("  gOHM:     ", newGOHM);
        console2.log("  Staking:  ", newStaking);
        console2.log("\nModule:");
        console2.log("  DLGTE:    ", newDLGTE);
        console2.log("\nPolicies:");
        console2.log("  LtvOracle:       ", newLtvOracle);
        console2.log("  MonoCooler:      ", newMonoCooler);
        console2.log("  Clearinghouse:   ", newClearinghouse);
        console2.log("  ZeroDistributor: ", newZeroDistributor);
        console2.log("  EmissionManager: ", newEmissionManager);
        console2.log("========================================");
    }
}
