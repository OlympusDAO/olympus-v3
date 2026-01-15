// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.20;

// Libraries
import {Owned} from "@solmate-6.2.0/auth/Owned.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate-6.2.0/utils/SafeTransferLib.sol";

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

    bytes32 public constant MIGRATION_CATEGORY = "migration";

    /// @notice True if the activation has been performed
    bool public isActivated = false;

    event Activated(address caller);

    error AlreadyActivated();
    error InvalidParams(string reason);

    constructor(address owner_, address burner_, address tempOHM_) Owned(owner_) {
        if (owner_ == address(0)) revert InvalidParams("owner");
        if (burner_ == address(0)) revert InvalidParams("burner");
        if (tempOHM_ == address(0)) revert InvalidParams("tempOHM");

        BURNER = burner_;
        TEMPOHM = tempOHM_;
    }

    /// @notice Executes the migration process
    /// @dev    This function assumes:
    ///         - The "burner_admin" role has been granted to this contract
    ///         - The caller (owner) has approved tempOHM to this contract
    ///         - The caller (owner) has tempOHM balance
    ///
    ///         This function reverts if:
    ///         - The caller is not the owner
    ///         - The function has already been run
    function activate() external onlyOwner {
        // Revert if already activated
        if (isActivated) revert AlreadyActivated();

        // Step 1: Add burner category "migration"
        Burner(BURNER).addCategory(MIGRATION_CATEGORY);

        // Step 2: Deposit tempOHM to treasury
        {
            uint256 tempOHMBalance = ERC20(TEMPOHM).balanceOf(owner);
            if (tempOHMBalance == 0) revert InvalidParams("No tempOHM balance");
            _depositTempOHMToTreasury(tempOHMBalance);
        }

        // Step 3: Migrate OHMv1 to gOHM
        _migrateOHMv1ToGOHM();

        // Step 4: Unstake and burn remaining gOHM
        _unstakeAndBurn();

        // Mark as activated
        isActivated = true;
        emit Activated(msg.sender);
    }

    /// @notice Deposit tempOHM to treasury to receive OHMv1
    function _depositTempOHMToTreasury(uint256 tempOHMBalance) internal {
        // Transfer tempOHM from owner to this contract
        // Note: Owner must have approved tempOHM to this contract before calling activate()
        ERC20(TEMPOHM).safeTransferFrom(owner, address(this), tempOHMBalance);

        // Approve tempOHM for treasury
        ERC20(TEMPOHM).safeApprove(TREASURY, tempOHMBalance);

        // Deposit tempOHM to treasury (this mints OHMv1 to this contract)
        IOlympusTreasury(TREASURY).deposit(tempOHMBalance, TEMPOHM, 0);
    }

    /// @notice Migrate OHMv1 to gOHM via migrator
    function _migrateOHMv1ToGOHM() internal {
        uint256 ohmv1Balance = IERC20(OHMV1).balanceOf(address(this));
        IERC20(OHMV1).approve(MIGRATOR, ohmv1Balance);
        IOlympusTokenMigrator(MIGRATOR).migrate(
            ohmv1Balance,
            IOlympusTokenMigrator.TYPE.UNSTAKED,
            IOlympusTokenMigrator.TYPE.WRAPPED
        );
    }

    /// @notice Unstake gOHM to OHMv2 and burn
    function _unstakeAndBurn() internal {
        // Approve and unstake gOHM to OHMv2
        uint256 gohmAmount = IgOHM(GOHM).balanceOf(address(this));
        IERC20(GOHM).approve(STAKING, gohmAmount);
        IStaking(STAKING).unstake(address(this), gohmAmount, false, false);

        // Get OHMv2 balance and burn
        uint256 ohmv2Balance = IERC20(OHMV2).balanceOf(address(this));
        IERC20(OHMV2).approve(BURNER, ohmv2Balance);
        Burner(BURNER).burnFrom(address(this), ohmv2Balance, MIGRATION_CATEGORY);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
