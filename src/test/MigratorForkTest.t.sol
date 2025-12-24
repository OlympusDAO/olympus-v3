// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IgOHM} from "src/interfaces/IgOHM.sol";

interface OlympusERC20Token {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TWAPEpochChanged(uint256 previousTWAPEpochPeriod, uint256 newTWAPEpochPeriod);
    event TWAPOracleChanged(address indexed previousTWAPOracle, address indexed newTWAPOracle);
    event TWAPSourceAdded(address indexed newTWAPSource);
    event TWAPSourceRemoved(address indexed removedTWAPSource);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external view returns (bytes32);

    function _burnFrom(address account_, uint256 amount_) external;

    function addTWAPSource(address newTWAPSourceDexPool_) external;

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function burn(uint256 amount) external;

    function burnFrom(address account_, uint256 amount_) external;

    function changeTWAPEpochPeriod(uint256 newTWAPEpochPeriod_) external;

    function changeTWAPOracle(address newTWAPOracle_) external;

    function decimals() external view returns (uint8);

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

    function mint(address account_, uint256 amount_) external;

    function name() external view returns (string memory);

    function nonces(address owner) external view returns (uint256);

    function owner() external view returns (address);

    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function removeTWAPSource(address twapSourceToRemove_) external;

    function renounceOwnership() external;

    function setVault(address vault_) external returns (bool);

    function symbol() external view returns (string memory);

    function totalSupply() external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transferOwnership(address newOwner_) external;

    function twapEpochPeriod() external view returns (uint256);

    function twapOracle() external view returns (address);

    function vault() external view returns (address);
}

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

contract MigratorForkTest is Test {
    OlympusERC20Token public OHMv1;
    OlympusTreasury public treasury;
    OlympusTokenMigrator public migrator;
    IgOHM public gOHM;

    address public constant DAO_MS = 0x245cc372C84B3645Bf0Ffe6538620B04a217988B;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    uint256 public constant BLOCKS_NEEDED_FOR_QUEUE = 6000;
    uint256 public constant BLOCK_NUMBER = 24070000;

    function setUp() public {
        vm.createSelectFork("mainnet", BLOCK_NUMBER);

        OHMv1 = OlympusERC20Token(0x383518188C0C6d7730D91b2c03a03C837814a899);
        treasury = OlympusTreasury(0x31F8Cc382c9898b273eff4e0b7626a6987C846E8);
        migrator = OlympusTokenMigrator(0x184f3FAd8618a6F458C16bae63F70C426fE784B3);
        gOHM = IgOHM(0x0ab87046fBb341D058F17CBC4c1133F25a20a52f);
    }

    function test_migrate() public {
        // Confirm that DAO MS is not a reward manager
        assertFalse(treasury.isRewardManager(DAO_MS), "DAO MS should not be a reward manager");

        // Add DAO MS as a reserve depositor
        vm.prank(DAO_MS);
        treasury.queue(OlympusTreasury.MANAGING.RESERVEDEPOSITOR, DAO_MS);

        // Warp forward to the timelock expiry
        vm.roll(BLOCK_NUMBER + BLOCKS_NEEDED_FOR_QUEUE + 1);

        // Toggle DAO MS as a reserve depositor
        vm.prank(DAO_MS);
        treasury.toggle(OlympusTreasury.MANAGING.RESERVEDEPOSITOR, DAO_MS, address(0));

        // Verify that DAO MS is a reserve depositor
        assertTrue(treasury.isReserveDepositor(DAO_MS), "DAO MS should be a reserve depositor");

        // Excess reserves is 65659757174924
        console2.log("excess reserves (18 dp):", treasury.excessReserves());

        // OHM valuation of DAI is 1:1 in OHM decimals
        assertEq(
            treasury.valueOf(DAI, 1e18),
            1e9,
            "OHM valuation of DAI should be 1:1 in OHM decimals"
        );

        // OHMv1 old supply is 553483798713734 (9 dp)
        // OHMv1 total supply is 278651810168261 (9 dp)
        // The difference is what can be minted and migrated
        // Difference is 274831988545473 (274831.988545473 OHM)
        console2.log("OHMv1 oldSupply (9 dp):", migrator.oldSupply());
        console2.log("OHMv1 total supply (9 dp):", OHMv1.totalSupply());
        uint256 maxMintableOHM = migrator.oldSupply() - OHMv1.totalSupply();

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
        uint256 maxDAI = maxOHM * 1e9;

        // Deal DAI to the DAO MS
        deal(DAI, DAO_MS, maxDAI);
        console2.log("maxDAI (18 dp):", maxDAI);

        // Approve DAI for the DAO MS
        vm.prank(DAO_MS);
        IERC20(DAI).approve(address(treasury), maxDAI);

        // Deposit DAI to the treasury
        vm.prank(DAO_MS);
        treasury.deposit(maxDAI, DAI, 0);

        // Verify that the DAO MS has received OHM
        console2.log("OHM balance of DAO MS (9 dp):", OHMv1.balanceOf(DAO_MS));
        assertEq(OHMv1.balanceOf(DAO_MS), maxOHM, "DAO MS should have received 100 OHM");

        uint256 gOHMBalanceBefore = gOHM.balanceOf(DAO_MS);
        console2.log("gOHM balance of DAO MS before migration (18 dp):", gOHMBalanceBefore);

        // Approve the migrator to spend the OHM
        vm.prank(DAO_MS);
        OHMv1.approve(address(migrator), maxOHM);

        // Migrate the OHM to the migrator
        vm.prank(DAO_MS);
        migrator.migrate(
            maxOHM,
            OlympusTokenMigrator.TYPE.UNSTAKED,
            OlympusTokenMigrator.TYPE.WRAPPED
        );

        uint256 gOHMBalanceDifference = gOHM.balanceOf(DAO_MS) - gOHMBalanceBefore;
        console2.log("gOHM balance difference (18 dp):", gOHMBalanceDifference);

        // gOHM balance of migrator
        console2.log("gOHM balance of migrator (18 dp):", gOHM.balanceOf(address(migrator)));
    }
}
