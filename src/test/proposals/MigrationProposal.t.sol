// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin-5.3.0/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin-5.3.0/access/Ownable.sol";
import {Kernel, Actions} from "src/Kernel.sol";
import {Burner} from "src/policies/Burner.sol";
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
        migrationHelper = new MigrationHelper(
            timelock, // owner
            address(burner),
            address(treasury),
            address(migrator),
            0xB63cac384247597756545b500253ff8E607a8020, // staking from addresses.json
            0x0ab87046fBb341D058F17CBC4c1133F25a20a52f, // gohm from addresses.json
            address(OHMv1),
            address(OHMv2),
            address(tempOHM)
        );

        // ========== DAO MS SETUP STEPS ==========

        console2.log("");
        console2.log("====== Setting up treasury...");

        console2.log("block:", block.number);

        // Confirm that tempOHM is not a reserve token
        assertFalse(
            treasury.isReserveToken(address(tempOHM)),
            "tempOHM should not be a reserve token"
        );

        // Add tempOHM as a reserve token
        console2.log("Adding tempOHM as a reserve token...");
        vm.prank(DAO_MS);
        treasury.queue(OlympusTreasury.MANAGING.RESERVETOKEN, address(tempOHM));

        // Print the queue
        console2.log("reserveTokenQueue:", treasury.reserveTokenQueue(address(tempOHM)));

        // Confirm that MigrationHelper is not a reserve depositor
        assertFalse(
            treasury.isReserveDepositor(address(migrationHelper)),
            "MigrationHelper should not be a reserve depositor"
        );

        // Add MigrationHelper as a reserve depositor
        console2.log("Adding MigrationHelper as a reserve depositor...");
        vm.prank(DAO_MS);
        treasury.queue(OlympusTreasury.MANAGING.RESERVEDEPOSITOR, address(migrationHelper));

        // Warp forward to the timelock expiry
        console2.log("Warpping forward to the timelock expiry...");
        vm.roll(BLOCK + BLOCKS_NEEDED_FOR_QUEUE + 1);

        // Toggle tempOHM as a reserve token
        console2.log("Enabling tempOHM as a reserve token...");
        vm.prank(DAO_MS);
        treasury.toggle(OlympusTreasury.MANAGING.RESERVETOKEN, address(tempOHM), address(0));

        // Verify that tempOHM is a reserve token
        assertTrue(treasury.isReserveToken(address(tempOHM)), "tempOHM should be a reserve token");

        // Toggle MigrationHelper as a reserve depositor
        console2.log("Enabling MigrationHelper as a reserve depositor...");
        vm.prank(DAO_MS);
        treasury.toggle(
            OlympusTreasury.MANAGING.RESERVEDEPOSITOR,
            address(migrationHelper),
            address(0)
        );

        // Verify that MigrationHelper is a reserve depositor
        assertTrue(
            treasury.isReserveDepositor(address(migrationHelper)),
            "MigrationHelper should be a reserve depositor"
        );

        console2.log("");
        console2.log("====== Minting OHM v1...");

        // Excess reserves is 65659757174924
        console2.log("Treasury excess reserves (18 dp):", treasury.excessReserves());

        // OHM valuation of tempOHM is 1:1 in OHM decimals
        assertEq(
            treasury.valueOf(address(tempOHM), 1e18),
            1e9,
            "OHM valuation of tempOHM should be 1:1 in OHM decimals"
        );

        // OHMv1 old supply is 553483798713734 (9 dp)
        // OHMv1 total supply is 278651810168261 (9 dp)
        // The difference is what can be minted and migrated
        // Difference is 274831988545473 (274831.988545473 OHM)
        console2.log("OHMv1 oldSupply (9 dp):", migrator.oldSupply());
        console2.log("OHMv1 total supply (9 dp):", OHMv1.totalSupply());
        uint256 maxMintableOHM = migrator.oldSupply() - OHMv1.totalSupply();
        console2.log("maxMintableOHM (9 dp):", maxMintableOHM);

        // 1e9 OHM = 21403507467877949 gOHM (18 dp)
        // 274831988545473 OHM can be converted into how much gOHM?
        // 274831988545473 * 21403507467877949 / 1e18 = 5882368519244778449578 gOHM (18 dp)

        // Migrator gOHM balance is 4232050112844353034347 (18 dp)
        // maxMigrateableOHM * conversionRate = 4232050112844353034347
        // maxMigrateableOHM = 4232050112844353034347 / conversionRate = 4232050112844353034347 * 1e9 / 21403507467877949 = 197726943548656 OHM (9 dp) (197,726.9435486566)
        // In reality, the maxOHM is higher
        uint256 maxOHM = 197726943548656;
        // There seems to be some issue with calculations, as the maxOHM results in residual gOHM
        // 176481131518703773 * 1e9 / 21403507467877949
        // = 8245430417
        maxOHM += 8245430417;
        uint256 maxTempOHM = maxOHM * 1e9;

        // Mint tempOHM to the Timelock (MigrationHelper owner)
        vm.prank(DAO_MS);
        tempOHM.mint(TIMELOCK, maxTempOHM);
        console2.log("maxTempOHM (18 dp):", maxTempOHM);

        // ========== PROPOSAL SIMULATION ==========

        // Deploy proposal under test with tempOHM and MigrationHelper addresses
        MigrationProposal proposal = new MigrationProposal(
            address(tempOHM),
            address(migrationHelper)
        );

        // Set to true once the proposal has been submitted on-chain to enforce calldata matching
        hasBeenSubmitted = false;

        // Create TestSuite
        _setupSuite(address(proposal));

        // Update addresses with test-deployed contracts (needed for _build and _validate)
        addresses.addAddress("olympus-policy-burner", address(burner));

        // Set debug mode
        suite.setDebug(true);

        // Simulate the proposal
        _simulateProposal();
    }
}
