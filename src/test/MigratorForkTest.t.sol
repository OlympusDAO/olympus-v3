// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IgOHM} from "src/interfaces/IgOHM.sol";
import {IStaking} from "src/interfaces/IStaking.sol";
import {ERC20} from "@openzeppelin-5.3.0/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin-5.3.0/access/Ownable.sol";
import {Burner} from "src/policies/Burner.sol";
import {Kernel, Actions} from "src/Kernel.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ERC20 as SolmateERC20} from "solmate/tokens/ERC20.sol";

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

    event ChangeActivated(MANAGING indexed managing, address activated, bool result);
    event ChangeQueued(MANAGING indexed managing, address queued);
    event CreateDebt(address indexed debtor, address indexed token, uint256 amount, uint256 value);
    event Deposit(address indexed token, uint256 amount, uint256 value);
    event OwnershipPulled(address indexed previousOwner, address indexed newOwner);
    event OwnershipPushed(address indexed previousOwner, address indexed newOwner);
    event RepayDebt(address indexed debtor, address indexed token, uint256 amount, uint256 value);
    event ReservesAudited(uint256 indexed totalReserves);
    event ReservesManaged(address indexed token, uint256 amount);
    event ReservesUpdated(uint256 indexed totalReserves);
    event RewardsMinted(address indexed caller, address indexed recipient, uint256 amount);
    event Withdrawal(address indexed token, uint256 amount, uint256 value);

    function LiquidityDepositorQueue(address) external view returns (uint256);

    function LiquidityManagerQueue(address) external view returns (uint256);

    function LiquidityTokenQueue(address) external view returns (uint256);

    function OHM() external view returns (address);

    function ReserveManagerQueue(address) external view returns (uint256);

    function auditReserves() external;

    function blocksNeededForQueue() external view returns (uint256);

    function bondCalculator(address) external view returns (address);

    function debtorBalance(address) external view returns (uint256);

    function debtorQueue(address) external view returns (uint256);

    function debtors(uint256) external view returns (address);

    function deposit(
        uint256 _amount,
        address _token,
        uint256 _profit
    ) external returns (uint256 send_);

    function excessReserves() external view returns (uint256);

    function incurDebt(uint256 _amount, address _token) external;

    function isDebtor(address) external view returns (bool);

    function isLiquidityDepositor(address) external view returns (bool);

    function isLiquidityManager(address) external view returns (bool);

    function isLiquidityToken(address) external view returns (bool);

    function isReserveDepositor(address) external view returns (bool);

    function isReserveManager(address) external view returns (bool);

    function isReserveSpender(address) external view returns (bool);

    function isReserveToken(address) external view returns (bool);

    function isRewardManager(address) external view returns (bool);

    function liquidityDepositors(uint256) external view returns (address);

    function liquidityManagers(uint256) external view returns (address);

    function liquidityTokens(uint256) external view returns (address);

    function manage(address _token, uint256 _amount) external;

    function manager() external view returns (address);

    function mintRewards(address _recipient, uint256 _amount) external;

    function pullManagement() external;

    function pushManagement(address newOwner_) external;

    function queue(MANAGING _managing, address _address) external returns (bool);

    function renounceManagement() external;

    function repayDebtWithOHM(uint256 _amount) external;

    function repayDebtWithReserve(uint256 _amount, address _token) external;

    function reserveDepositorQueue(address) external view returns (uint256);

    function reserveDepositors(uint256) external view returns (address);

    function reserveManagers(uint256) external view returns (address);

    function reserveSpenderQueue(address) external view returns (uint256);

    function reserveSpenders(uint256) external view returns (address);

    function reserveTokenQueue(address) external view returns (uint256);

    function reserveTokens(uint256) external view returns (address);

    function rewardManagerQueue(address) external view returns (uint256);

    function rewardManagers(uint256) external view returns (address);

    function sOHM() external view returns (address);

    function sOHMQueue() external view returns (uint256);

    function toggle(
        MANAGING _managing,
        address _address,
        address _calculator
    ) external returns (bool);

    function totalDebt() external view returns (uint256);

    function totalReserves() external view returns (uint256);

    function valueOf(address _token, uint256 _amount) external view returns (uint256 value_);

    function withdraw(uint256 _amount, address _token) external;
}

interface OlympusTokenMigrator {
    enum TYPE {
        UNSTAKED,
        STAKED,
        WRAPPED
    }

    event AuthorityUpdated(address indexed authority);
    event Defunded(uint256 amount);
    event Funded(uint256 amount);
    event Migrated(address staking, address treasury);
    event TimelockStarted(uint256 block, uint256 end);

    function authority() external view returns (address);

    function bridgeBack(uint256 _amount, TYPE _to) external;

    function defund(address reserve) external;

    function gOHM() external view returns (address);

    function halt() external;

    function migrate(uint256 _amount, TYPE _from, TYPE _to) external;

    function migrateAll(TYPE _to) external;

    function migrateContracts(
        address _newTreasury,
        address _newStaking,
        address _newOHM,
        address _newsOHM,
        address _reserve
    ) external;

    function migrateLP(
        address pair,
        bool sushi,
        address token,
        uint256 _minA,
        uint256 _minB
    ) external;

    function migrateToken(address token) external;

    function newOHM() external view returns (address);

    function newStaking() external view returns (address);

    function newTreasury() external view returns (address);

    function ohmMigrated() external view returns (bool);

    function oldOHM() external view returns (address);

    function oldStaking() external view returns (address);

    function oldSupply() external view returns (uint256);

    function oldTreasury() external view returns (address);

    function oldsOHM() external view returns (address);

    function oldwsOHM() external view returns (address);

    function setAuthority(address _newAuthority) external;

    function setgOHM(address _gOHM) external;

    function shutdown() external view returns (bool);

    function startTimelock() external;

    function sushiRouter() external view returns (address);

    function timelockEnd() external view returns (uint256);

    function timelockLength() external view returns (uint256);

    function uniRouter() external view returns (address);

    function withdrawToken(address tokenAddress, uint256 amount, address recipient) external;
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

contract MigratorForkTest is Test {
    IERC20 public OHMv1;
    IERC20 public OHMv2;
    OlympusTreasury public treasury;
    OlympusTokenMigrator public migrator;
    IStaking public staking;
    IgOHM public gOHM;
    OwnedERC20 public antiOHM;
    Burner public burner;
    RolesAdmin public rolesAdmin;

    address public constant DAO_MS = 0x245cc372C84B3645Bf0Ffe6538620B04a217988B;
    address public constant TIMELOCK = 0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39;
    uint256 public constant BLOCKS_NEEDED_FOR_QUEUE = 6000;
    uint256 public constant BLOCK_NUMBER = 24070000;

    function setUp() public {
        vm.createSelectFork("mainnet", BLOCK_NUMBER);

        // Existing contracts
        OHMv1 = IERC20(0x383518188C0C6d7730D91b2c03a03C837814a899);
        OHMv2 = IERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
        treasury = OlympusTreasury(0x31F8Cc382c9898b273eff4e0b7626a6987C846E8);
        migrator = OlympusTokenMigrator(0x184f3FAd8618a6F458C16bae63F70C426fE784B3);
        staking = IStaking(0xB63cac384247597756545b500253ff8E607a8020);
        gOHM = IgOHM(0x0ab87046fBb341D058F17CBC4c1133F25a20a52f);
        rolesAdmin = RolesAdmin(0xb216d714d91eeC4F7120a732c11428857C659eC8);

        Kernel kernel = Kernel(0x2286d7f9639e8158FaD1169e76d1FbC38247f54b);

        // Create a dummy token
        antiOHM = new OwnedERC20("AntiOHM", "antiOHM", DAO_MS);

        // Deploy burner
        burner = new Burner(kernel, SolmateERC20(address(OHMv2)));

        // Install burner into the kernel
        vm.prank(DAO_MS);
        kernel.executeAction(Actions.ActivatePolicy, address(burner));
    }

    function test_migrate() public {
        console2.log("");
        console2.log("====== Setting up treasury...");

        // Add antiOHM as a reserve token
        console2.log("Adding antiOHM as a reserve token...");
        vm.prank(DAO_MS);
        treasury.queue(OlympusTreasury.MANAGING.RESERVETOKEN, address(antiOHM));

        // Confirm that Timelock is not a reward depositor
        assertFalse(
            treasury.isReserveDepositor(TIMELOCK),
            "Timelock should not be a reserve depositor"
        );

        // Add Timelock as a reserve depositor
        console2.log("Adding Timelock as a reserve depositor...");
        vm.prank(DAO_MS);
        treasury.queue(OlympusTreasury.MANAGING.RESERVEDEPOSITOR, TIMELOCK);

        // Warp forward to the timelock expiry
        console2.log("Warpping forward to the timelock expiry...");
        vm.roll(BLOCK_NUMBER + BLOCKS_NEEDED_FOR_QUEUE + 1);

        // Toggle antiOHM as a reserve token
        console2.log("Enabling antiOHM as a reserve token...");
        vm.prank(DAO_MS);
        treasury.toggle(OlympusTreasury.MANAGING.RESERVETOKEN, address(antiOHM), address(0));

        // Verify that antiOHM is a reserve token
        assertTrue(treasury.isReserveToken(address(antiOHM)), "antiOHM should be a reserve token");

        // Toggle Timelock as a reserve depositor
        console2.log("Enabling Timelock as a reserve depositor...");
        vm.prank(DAO_MS);
        treasury.toggle(OlympusTreasury.MANAGING.RESERVEDEPOSITOR, TIMELOCK, address(0));

        // Verify that Timelock is a reserve depositor
        assertTrue(treasury.isReserveDepositor(TIMELOCK), "Timelock should be a reserve depositor");

        console2.log("");
        console2.log("====== Minting OHM v1...");

        // Excess reserves is 65659757174924
        console2.log("Treasury excess reserves (18 dp):", treasury.excessReserves());

        // OHM valuation of antiOHM is 1:1 in OHM decimals
        assertEq(
            treasury.valueOf(address(antiOHM), 1e18),
            1e9,
            "OHM valuation of antiOHM should be 1:1 in OHM decimals"
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
        uint256 maxAntiOHM = maxOHM * 1e9;

        // Mint antiOHM to the Timelock
        vm.prank(DAO_MS);
        antiOHM.mint(TIMELOCK, maxAntiOHM);
        console2.log("maxAntiOHM (18 dp):", maxAntiOHM);

        // The following steps are performed by the Timelock
        // e.g. through an OCG proposal

        // Grant the timelock the burner_admin role
        console2.log("Granting the burner_admin role to the Timelock...");
        vm.prank(TIMELOCK);
        rolesAdmin.grantRole(bytes32("burner_admin"), TIMELOCK);

        // Add a burner category
        console2.log("Adding a burner category to the Timelock...");
        vm.prank(TIMELOCK);
        burner.addCategory("migration");

        // Approve antiOHM for the Timelock
        vm.prank(TIMELOCK);
        antiOHM.approve(address(treasury), maxAntiOHM);

        // Deposit antiOHM to the treasury
        vm.prank(TIMELOCK);
        treasury.deposit(maxAntiOHM, address(antiOHM), 0);

        // Verify that the Timelock has received OHM
        console2.log("OHM balance of Timelock (9 dp):", OHMv1.balanceOf(TIMELOCK));
        assertEq(OHMv1.balanceOf(TIMELOCK), maxOHM, "Timelock should have received 100 OHM");

        console2.log("");
        console2.log("====== Migrating OHM v1 to gOHM...");

        uint256 gOHMBalanceBefore = gOHM.balanceOf(TIMELOCK);
        console2.log("gOHM balance of Timelock before migration (18 dp):", gOHMBalanceBefore);

        // Approve the migrator to spend the OHM
        vm.prank(TIMELOCK);
        OHMv1.approve(address(migrator), maxOHM);

        // Migrate the OHM to the migrator
        vm.prank(TIMELOCK);
        migrator.migrate(
            maxOHM,
            OlympusTokenMigrator.TYPE.UNSTAKED,
            OlympusTokenMigrator.TYPE.WRAPPED
        );

        uint256 gOHMBalanceDifference = gOHM.balanceOf(TIMELOCK) - gOHMBalanceBefore;
        console2.log("gOHM balance difference of Timelock (18 dp):", gOHMBalanceDifference);

        // gOHM balance of migrator
        console2.log("gOHM balance of migrator (18 dp):", gOHM.balanceOf(address(migrator)));

        // OHM balance of Timelock
        console2.log("OHM balance of Timelock (9 dp):", OHMv1.balanceOf(TIMELOCK));

        // antiOHM balance of Timelock
        console2.log("antiOHM balance of Timelock (18 dp):", antiOHM.balanceOf(TIMELOCK));

        console2.log("");
        console2.log("====== Unstaking gOHM to OHM v2...");

        // Approve the staking contract to spend the gOHM
        vm.prank(TIMELOCK);
        gOHM.approve(address(staking), gOHMBalanceDifference);

        uint256 OHMv2BalanceBefore = OHMv2.balanceOf(TIMELOCK);
        uint256 OHMv2TotalSupplyBefore = OHMv2.totalSupply();
        console2.log("OHM v2 balance of Timelock before unstaking (9 dp):", OHMv2BalanceBefore);

        // Unstake the gOHM
        vm.prank(TIMELOCK);
        staking.unstake(TIMELOCK, gOHMBalanceDifference, false, false);

        uint256 OHMv2BalanceDifference = OHMv2.balanceOf(TIMELOCK) - OHMv2BalanceBefore;
        console2.log("OHM v2 balance difference of Timelock (9 dp):", OHMv2BalanceDifference);

        console2.log("");
        console2.log("====== Burning OHM v2...");

        // Approve the burner to spend the OHM v2
        console2.log("Approving the burner to spend the OHM v2...");
        vm.prank(TIMELOCK);
        OHMv2.approve(address(burner), OHMv2BalanceDifference);

        // Burn the OHM v2
        console2.log("Burning the OHM v2...");
        vm.prank(TIMELOCK);
        burner.burnFrom(TIMELOCK, OHMv2BalanceDifference, "migration");

        // Verify that the OHM v2 balance of the Timelock is 0
        console2.log("OHM v2 balance of Timelock (9 dp):", OHMv2.balanceOf(TIMELOCK));
        assertEq(OHMv2.balanceOf(TIMELOCK), 0, "OHM v2 balance of Timelock should be 0");

        // Verify that the OHM v2 total supply has decreased by the amount of the OHM v2 balance difference
        console2.log("OHM v2 total supply before unstaking (9 dp):", OHMv2TotalSupplyBefore);
        console2.log("OHM v2 total supply after unstaking (9 dp):", OHMv2.totalSupply());
        console2.log(
            "OHM v2 total supply difference (9 dp):",
            OHMv2TotalSupplyBefore - OHMv2.totalSupply()
        );
        assertEq(
            OHMv2.totalSupply(),
            OHMv2TotalSupplyBefore - OHMv2BalanceDifference,
            "OHM v2 total supply should have decreased by the amount of the OHM v2 balance difference"
        );

        // Cleanup
        // Revoke the burner_admin role
        console2.log("Revoking the burner_admin role from the Timelock...");
        vm.prank(TIMELOCK);
        rolesAdmin.revokeRole(bytes32("burner_admin"), TIMELOCK);
    }
}
