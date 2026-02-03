// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.20;

// Libraries
import {Owned} from "@solmate-6.2.0/auth/Owned.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate-6.2.0/utils/SafeTransferLib.sol";
import {ERC20Burnable} from "@openzeppelin-5.3.0/token/ERC20/extensions/ERC20Burnable.sol";

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IgOHM} from "src/interfaces/IgOHM.sol";
import {IStaking} from "src/interfaces/IStaking.sol";
import {Burner} from "src/policies/Burner.sol";
import {IOlympusTokenMigrator} from "src/interfaces/IOlympusTokenMigrator.sol";
import {IOlympusTreasury} from "src/interfaces/IOlympusTreasury.sol";

/// @notice Single-use contract to execute OHM v1 migration to OHM v2 and burn
contract MigrationProposalHelper is Owned {
    using SafeTransferLib for ERC20;

    // Hardcoded legacy contract addresses (mainnet)
    address public constant TREASURY = 0x31F8Cc382c9898b273eff4e0b7626a6987C846E8;
    address public constant MIGRATOR = 0x184f3FAd8618a6F458C16bae63F70C426fE784B3;
    address public constant STAKING = 0xB63cac384247597756545b500253ff8E607a8020;
    address public constant GOHM = 0x0ab87046fBb341D058F17CBC4c1133F25a20a52f;
    address public constant OHMV1 = 0x383518188C0C6d7730D91b2c03a03C837814a899;
    address public constant OHMV2 = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;

    // Immutable contract addresses (variable)
    address public immutable BURNER;
    address public immutable TEMPOHM;

    /// @notice Admin address that can update the OHM v1 migration limit
    address public immutable ADMIN;

    /// @notice Maximum amount of OHM v1 to migrate (1e9 decimals)
    uint256 public OHMv1ToMigrate;

    bytes32 public constant MIGRATION_CATEGORY = "migration";

    /// @notice True if the activation has been performed
    bool public isActivated = false;

    // =========  EVENTS  ========= //

    event Activated(address caller);
    event OHMv1ToMigrateUpdated(uint256 newMax);
    event Rescued(address indexed token, address indexed to, uint256 amount);

    // =========  ERRORS  ========= //

    error AlreadyActivated();
    error InvalidParams(string reason);
    error Unauthorized();

    // =========  CONSTRUCTOR  ========= //

    constructor(
        address owner_,
        address admin_,
        address burner_,
        address tempOHM_,
        uint256 OHMv1ToMigrate_
    ) Owned(owner_) {
        if (owner_ == address(0)) revert InvalidParams("owner");
        if (admin_ == address(0)) revert InvalidParams("admin");
        if (burner_ == address(0)) revert InvalidParams("burner");
        if (tempOHM_ == address(0)) revert InvalidParams("tempOHM");

        BURNER = burner_;
        TEMPOHM = tempOHM_;
        ADMIN = admin_;
        OHMv1ToMigrate = OHMv1ToMigrate_;
    }

    function _onlyOwnerOrAdmin() internal view {
        if (msg.sender != owner && msg.sender != ADMIN) revert Unauthorized();
    }

    /// @notice Modifier to restrict access to owner or admin
    modifier onlyOwnerOrAdmin() {
        _onlyOwnerOrAdmin();
        _;
    }

    /// @notice Set the maximum OHM v1 to migrate
    /// @dev    Only callable by owner or admin. Updates the migration limit.
    /// @param maxOHMv1_ The new maximum OHM v1 amount (1e9 decimals)
    function setOHMv1ToMigrate(uint256 maxOHMv1_) external onlyOwnerOrAdmin {
        OHMv1ToMigrate = maxOHMv1_;
        emit OHMv1ToMigrateUpdated(maxOHMv1_);
    }

    /// @notice Rescue accidentally sent tokens
    /// @dev    Only callable by owner or admin. Sweeps entire token balance to caller.
    /// @param token_ The ERC20 token to rescue
    function rescue(IERC20 token_) external onlyOwnerOrAdmin {
        if (address(token_) == address(0)) revert InvalidParams("token");
        uint256 balance = token_.balanceOf(address(this));
        if (balance == 0) revert InvalidParams("balance");
        ERC20(address(token_)).safeTransfer(msg.sender, balance);
        emit Rescued(address(token_), msg.sender, balance);
    }

    /// @notice Calculate the amount of tempOHM to deposit
    /// @dev    This is based on the OHMv1ToMigrate amount, converted to 1e18 decimals
    function getTempOHMToDeposit() public view returns (uint256) {
        return OHMv1ToMigrate * 1e9;
    }

    /// @notice Executes the migration process
    /// @dev    This function assumes:
    ///         - The "burner_admin" role has been granted to this contract
    ///         - The caller (owner) has approved tempOHM to this contract
    ///         - The caller (owner) has tempOHM balance
    ///
    ///         Any tempOHM in excess of OHMv1ToMigrate * 1e9 will be burned.
    ///         This is intentional: tempOHM has no utility after migration completes.
    ///
    ///         This function reverts if:
    ///         - The caller is not the owner
    ///         - The function has already been run
    function activate() external onlyOwner {
        // Set isActivated first (CEI: state change before external calls)
        // This prevents re-entrancy and ensures function only runs once
        if (isActivated) revert AlreadyActivated();
        isActivated = true;

        // Step 1: Add burner category "migration" if it doesn't exist
        if (!Burner(BURNER).categoryApproved(MIGRATION_CATEGORY)) {
            Burner(BURNER).addCategory(MIGRATION_CATEGORY);
        }

        // Step 2: Deposit tempOHM to treasury, receive OHM v1
        uint256 ohmV1Minted = _depositTempOHMToTreasury();

        // Step 3: Migrate OHMv1 to gOHM (uses returned amount, not balance)
        _migrateOHMv1ToGOHM(ohmV1Minted);

        // Step 4: Unstake and burn remaining gOHM
        _unstakeAndBurn();

        // Step 5: Burn any excess tempOHM and OHM v1 in this contract
        _burnExcess();

        emit Activated(msg.sender);
    }

    /// @notice Transfer all tempOHM from owner and deposit the calculated amount to treasury
    /// @dev    Transfers ALL tempOHM from owner but deposits only getTempOHMToDeposit().
    ///         Excess is burned by _burnExcess() (tempOHM has no post-migration utility).
    /// @return ohmV1Minted The amount of OHM v1 minted from the deposit
    function _depositTempOHMToTreasury() internal returns (uint256 ohmV1Minted) {
        // Transfer all of the tempOHM from the owner to this contract
        ERC20(TEMPOHM).safeTransferFrom(owner, address(this), ERC20(TEMPOHM).balanceOf(owner));

        // Calculate tempOHM to deposit (convert OHM v1 limit from 1e9 to 1e18)
        uint256 tempOHMToDeposit = getTempOHMToDeposit();

        // Approve spending of tempOHM by treasury
        ERC20(TEMPOHM).safeApprove(TREASURY, tempOHMToDeposit);

        // Deposit tempOHM to treasury (this mints OHMv1 to this contract)
        // Use the return value from deposit for precision
        ohmV1Minted = IOlympusTreasury(TREASURY).deposit(tempOHMToDeposit, TEMPOHM, 0);
    }

    /// @notice Migrate OHMv1 to gOHM via migrator
    /// @param ohmV1Amount The amount of OHM v1 to migrate
    function _migrateOHMv1ToGOHM(uint256 ohmV1Amount) internal {
        // Don't early exit - zero amount indicates a problem
        if (ohmV1Amount == 0) revert InvalidParams("Zero OHM v1 amount to migrate");

        ERC20(OHMV1).safeApprove(MIGRATOR, ohmV1Amount);
        IOlympusTokenMigrator(MIGRATOR).migrate(
            ohmV1Amount,
            IOlympusTokenMigrator.TYPE.UNSTAKED,
            IOlympusTokenMigrator.TYPE.WRAPPED
        );
    }

    /// @notice Burn any excess tempOHM and OHM v1 remaining after migration
    /// @dev    Intentional cleanup: tempOHM has no utility after gOHM migration.
    ///         Also burns any OHM v1 left from partial migration failures.
    function _burnExcess() internal {
        // Burn excess tempOHM
        uint256 excessTempOHM = ERC20(TEMPOHM).balanceOf(address(this));
        if (excessTempOHM > 0) {
            ERC20Burnable(TEMPOHM).burn(excessTempOHM);
        }

        // Burn excess OHM v1
        uint256 excessOHMv1 = IERC20(OHMV1).balanceOf(address(this));
        if (excessOHMv1 > 0) {
            ERC20Burnable(address(OHMV1)).burn(excessOHMv1);
        }
    }

    /// @notice Unstake gOHM to OHMv2 and burn
    function _unstakeAndBurn() internal {
        // Approve and unstake gOHM to OHMv2
        uint256 gohmAmount = IgOHM(GOHM).balanceOf(address(this));
        ERC20(GOHM).safeApprove(STAKING, gohmAmount);
        IStaking(STAKING).unstake(address(this), gohmAmount, false, false);

        // Get OHMv2 balance and burn
        uint256 ohmv2Balance = IERC20(OHMV2).balanceOf(address(this));
        ERC20(OHMV2).safeApprove(BURNER, ohmv2Balance);
        Burner(BURNER).burnFrom(address(this), ohmv2Balance, MIGRATION_CATEGORY);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
