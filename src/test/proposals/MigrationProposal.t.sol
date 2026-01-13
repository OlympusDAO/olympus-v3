// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin-5.3.0/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin-5.3.0/access/Ownable.sol";
import {Kernel, Actions} from "src/Kernel.sol";
import {Burner} from "src/policies/Burner.sol";
import {LegacyMigrator} from "src/policies/LegacyMigrator.sol";
import {ERC20 as SolmateERC20} from "solmate/tokens/ERC20.sol";

// MigrationProposal imports
import {MigrationProposal} from "src/proposals/MigrationProposal.sol";
import {MigrationHelper} from "src/proposals/MigrationHelper.sol";

interface OlympusTreasury {
    enum MANAGING {
        RESERVEDEPOSITOR,
        RESERVESPENDER,
        RESERVETOKEN,
        RESERVEMANAGER,
        LIQUIDITYDEPOSITOR,
        LIQUIDITYTOKEN,
        LIQUIDITYMANAGER,
        DEBTOR,
        REWARDMANAGER,
        SOHM
    }

    function queue(MANAGING _managing, address _address) external returns (bool);

    function toggle(
        MANAGING _managing,
        address _address,
        address _calculator
    ) external returns (bool);

    function isReserveToken(address) external view returns (bool);

    function isReserveDepositor(address) external view returns (bool);

    function excessReserves() external view returns (uint256);

    function valueOf(address _token, uint256 _amount) external view returns (uint256 value_);

    function reserveTokenQueue(address) external view returns (uint256);
}

interface OlympusTokenMigrator {
    function oldSupply() external view returns (uint256);
}

contract OwnedERC20 is ERC20, Ownable {
    constructor(
        string memory name_,
        string memory symbol_,
        address initialOwner_
    ) ERC20(name_, symbol_) Ownable(initialOwner_) {}

    /// @notice Mint tokens to the specified address
    /// @dev    Only the owner can mint tokens
    function mint(address to, uint256 amount) public virtual onlyOwner {
        _mint(to, amount);
    }

    /// @notice Burn tokens from the specified address
    /// @dev    Caller needs allowance if burning from another address
    function burn(address from, uint256 amount) public virtual {
        // If the caller is not the token holder, spend the allowance (or revert)
        if (from != msg.sender) {
            _spendAllowance(from, msg.sender, amount);
        }

        // Burn the tokens
        _burn(from, amount);
    }
}

contract MigrationProposalTest is ProposalTest {
    /// @dev Block the migration should be executed at
    uint256 public constant BLOCK = 24070000;
    uint256 public constant BLOCKS_NEEDED_FOR_QUEUE = 6000;

    address public constant DAO_MS = 0x245cc372C84B3645Bf0Ffe6538620B04a217988B;
    address public constant TIMELOCK = 0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39;

    OlympusTreasury public treasury;
    OlympusTokenMigrator public migrator;
    OwnedERC20 public tempOHM;
    IERC20 public OHMv1;
    IERC20 public OHMv2;
    Burner public burner;
    MigrationHelper public migrationHelper;
    LegacyMigrator public legacyMigrator;

    address public constant HOLDER1 = address(0x1111111111111111111111111111111111111111);
    address public constant HOLDER2 = address(0x2222222222222222222222222222222222222222);
    uint256 public constant HOLDER1_BALANCE = 1000e9; // 1000 OHM (9 decimals)
    uint256 public constant HOLDER2_BALANCE = 5000e9; // 5000 OHM (9 decimals)

    function setUp() public virtual {
        // Mainnet fork at a fixed block prior to proposal execution to ensure deterministic state
        vm.createSelectFork(_RPC_ALIAS, BLOCK);

        // Existing contracts
        OHMv1 = IERC20(0x383518188C0C6d7730D91b2c03a03C837814a899);
        treasury = OlympusTreasury(0x31F8Cc382c9898b273eff4e0b7626a6987C846E8);
        migrator = OlympusTokenMigrator(0x184f3FAd8618a6F458C16bae63F70C426fE784B3);

        Kernel kernel = Kernel(0x2286d7f9639e8158FaD1169e76d1FbC38247f54b);

        // Create tempOHM token
        tempOHM = new OwnedERC20("TempOHM", "tempOHM", DAO_MS);
        vm.label(address(tempOHM), "tempOHM");

        // Deploy burner and install it into the kernel
        // Note: In production, the burner would already be deployed and activated
        OHMv2 = IERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
        burner = new Burner(kernel, SolmateERC20(address(OHMv2)));

        // Install burner into the kernel
        vm.prank(DAO_MS);
        kernel.executeAction(Actions.ActivatePolicy, address(burner));

        // ========== DEPLOY MIGRATION HELPER ==========

        // Deploy MigrationHelper (deployed separately, not by the proposal)
        // This needs to be deployed before treasury setup so it can be granted permissions
        address timelock = TIMELOCK;

        // Create test data for OHMv1 holders
        // In production, these would be the actual holder addresses and their recorded balances
        MigrationHelper.OHMv1Holder[] memory holders = new MigrationHelper.OHMv1Holder[](2);
        holders[0] = MigrationHelper.OHMv1Holder({
            holder: HOLDER1,
            recordedBalance: HOLDER1_BALANCE
        });
        holders[1] = MigrationHelper.OHMv1Holder({
            holder: HOLDER2,
            recordedBalance: HOLDER2_BALANCE
        });

        // Mint OHMv1 to holders before proposal execution
        // Use deal cheatcode to give them OHMv1 tokens
        deal(address(OHMv1), HOLDER1, HOLDER1_BALANCE);
        deal(address(OHMv1), HOLDER2, HOLDER2_BALANCE);

        // Deploy MigrationHelper
        migrationHelper = new MigrationHelper(
            timelock, // owner
            address(burner),
            address(tempOHM),
            holders
        );

        // ========== DEPLOY LEGACY MIGRATOR ==========

        // Deploy LegacyMigrator (pre-deployed, enabled via proposal)
        legacyMigrator = new LegacyMigrator(kernel, IERC20(address(OHMv1)));

        // Install LegacyMigrator into the kernel
        vm.prank(DAO_MS);
        kernel.executeAction(Actions.ActivatePolicy, address(legacyMigrator));

        // ========== NOTE: TREASURY SETUP ==========
        // Treasury permissions for tempOHM and MigrationHelper should be set up
        // separately via the MigrationSetup script before this proposal is executed.
        // This includes:
        // - Setting tempOHM as a reserve token
        // - Granting MigrationHelper permission to withdraw tempOHM
        // - Minting tempOHM to the Timelock for the gOHM burn
        //
        // For this test, we assume those steps have been completed via MigrationSetup.
        // In a real scenario, run:
        //   forge script MigrationSetup --sig "queue(...)" --broadcast
        //   (wait for timelock)
        //   forge script MigrationSetup --sig "toggle(...)" --broadcast

        // ========== PROPOSAL SIMULATION ==========

        // Deploy proposal under test (no constructor parameters needed)
        MigrationProposal proposal = new MigrationProposal();

        // Set to true once the proposal has been submitted on-chain to enforce calldata matching
        hasBeenSubmitted = false;

        // Create TestSuite
        _setupSuite(address(proposal));

        // Update addresses with test-deployed contracts (needed for _build and _validate)
        addresses.addAddress("olympus-policy-burner", address(burner));
        addresses.addAddress("olympus-policy-legacy-migrator", address(legacyMigrator));
        addresses.addAddress("olympus-policy-migration-helper", address(migrationHelper));
        addresses.addAddress("external.tokens.tempOHM", address(tempOHM));

        // Set debug mode
        suite.setDebug(true);

        // Simulate the proposal
        _simulateProposal();

        // ========== VERIFY MIGRATION HELPER ACTIVATION ==========
        _verifyMigrationHelperActivation();
    }

    /// @notice Helper function to verify MigrationHelper activation
    function _verifyMigrationHelperActivation() internal view {
        // Verify that MigrationHelper is marked as activated
        assertTrue(migrationHelper.isActivated(), "MigrationHelper should be activated");

        // Verify that the "migration" category was added to the burner
        bytes32 migrationCategory = migrationHelper.MIGRATION_CATEGORY();
        assertTrue(
            burner.categoryApproved(migrationCategory),
            "Migration category should be approved in Burner"
        );

        console2.log("");
        console2.log("====== Migration Helper Activation Verified ======");
        console2.log("MigrationHelper activated:", migrationHelper.isActivated());
        console2.log("Migration category approved:", burner.categoryApproved(migrationCategory));
    }
}
