// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

// Libraries
import {Owned} from "@solmate-6.2.0/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IgOHM} from "src/interfaces/IgOHM.sol";
import {IStaking} from "src/interfaces/IStaking.sol";
import {Burner} from "src/policies/Burner.sol";

interface OlympusTreasury {
    function deposit(
        uint256 _amount,
        address _token,
        uint256 _profit
    ) external returns (uint256 send_);
}

interface OlympusTokenMigrator {
    enum TYPE {
        UNSTAKED,
        STAKED,
        WRAPPED
    }

    function migrate(uint256 _amount, TYPE _from, TYPE _to) external;
}

/// @notice Single-use contract to execute OHM v1 migration to OHM v2 and burn
contract MigrationHelper is Owned {
    using SafeTransferLib for ERC20;

    // Immutable contract addresses
    address public immutable BURNER;
    address public immutable TREASURY;
    address public immutable MIGRATOR;
    address public immutable STAKING;
    address public immutable GOHM;
    address public immutable OHMV1;
    address public immutable OHMV2;
    address public immutable TEMPOHM;

    bytes32 public constant MIGRATION_CATEGORY = "migration";

    /// @notice True if the activation has been performed
    bool public isActivated = false;

    event Activated(address caller);
    error AlreadyActivated();
    error InvalidParams(string reason);

    constructor(
        address owner_,
        address burner_,
        address treasury_,
        address migrator_,
        address staking_,
        address gohm_,
        address ohmv1_,
        address ohmv2_,
        address tempOHM_
    ) Owned(owner_) {
        if (owner_ == address(0)) revert InvalidParams("owner");
        if (burner_ == address(0)) revert InvalidParams("burner");
        if (treasury_ == address(0)) revert InvalidParams("treasury");
        if (migrator_ == address(0)) revert InvalidParams("migrator");
        if (staking_ == address(0)) revert InvalidParams("staking");
        if (gohm_ == address(0)) revert InvalidParams("gohm");
        if (ohmv1_ == address(0)) revert InvalidParams("ohmv1");
        if (ohmv2_ == address(0)) revert InvalidParams("ohmv2");
        if (tempOHM_ == address(0)) revert InvalidParams("tempOHM");

        BURNER = burner_;
        TREASURY = treasury_;
        MIGRATOR = migrator_;
        STAKING = staking_;
        GOHM = gohm_;
        OHMV1 = ohmv1_;
        OHMV2 = ohmv2_;
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

        // Get tempOHM balance from owner (Timelock)
        uint256 tempOHMBalance = ERC20(TEMPOHM).balanceOf(owner);
        if (tempOHMBalance == 0) revert InvalidParams("No tempOHM balance");

        // Step 1: Add burner category "migration"
        Burner(BURNER).addCategory(MIGRATION_CATEGORY);

        // Step 2: Transfer tempOHM from owner to this contract
        // Note: Owner must have approved tempOHM to this contract before calling activate()
        ERC20(TEMPOHM).safeTransferFrom(owner, address(this), tempOHMBalance);

        // Step 3: Approve tempOHM for treasury
        ERC20(TEMPOHM).safeApprove(TREASURY, tempOHMBalance);

        // Step 4: Deposit tempOHM to treasury (this mints OHMv1 to this contract)
        OlympusTreasury(TREASURY).deposit(tempOHMBalance, TEMPOHM, 0);

        // Step 5: Get OHMv1 balance received from treasury
        uint256 ohmv1Balance = IERC20(OHMV1).balanceOf(address(this));

        // Step 6: Approve OHMv1 for migrator
        IERC20(OHMV1).approve(MIGRATOR, ohmv1Balance);

        // Step 7: Migrate OHMv1 to gOHM (via migrator)
        OlympusTokenMigrator(MIGRATOR).migrate(
            ohmv1Balance,
            OlympusTokenMigrator.TYPE.UNSTAKED,
            OlympusTokenMigrator.TYPE.WRAPPED
        );

        // Step 8: Get gOHM balance received from migration
        uint256 gohmBalance = IgOHM(GOHM).balanceOf(address(this));

        // Step 9: Approve gOHM for staking
        IERC20(GOHM).approve(STAKING, gohmBalance);

        // Step 10: Unstake gOHM to OHMv2
        IStaking(STAKING).unstake(address(this), gohmBalance, false, false);

        // Step 11: Get OHMv2 balance received from unstaking
        uint256 ohmv2Balance = IERC20(OHMV2).balanceOf(address(this));

        // Step 12: Approve OHMv2 for burner
        IERC20(OHMV2).approve(BURNER, ohmv2Balance);

        // Step 13: Burn OHMv2 with category "migration"
        Burner(BURNER).burnFrom(address(this), ohmv2Balance, MIGRATION_CATEGORY);

        // Mark as activated
        isActivated = true;
        emit Activated(msg.sender);
    }
}
