// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// Import External Dependencies
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/// Import Local Dependencies
import {Kernel, Policy} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY.sol";
import {OlympusMinter} from "src/modules/MINTR.sol";

/// Import interfaces
import "src/interfaces/Uniswap/IUniswapV2Pair.sol";

/// Define Inline Interfaces
interface IStaking {
    function unstake(
        address _to,
        uint256 _amount,
        bool _trigger,
        bool _rebasing
    ) external returns (uint256);
}

/// Define Inline Data Structures
struct Adjust {
    bool add; // whether to add or subtract from the reward rate
    uint256 rate; // the amount to add or subtract per epoch
    uint256 target; // the target rate to adjust the reward rate to
}

/// Define Custom Errors
error Distributor_InvalidConstruction();
error Distributor_NoRebaseOccurred();
error Distributor_OnlyStaking();
error Distributor_NotUnlocked();
error Distributor_SanityCheck();
error Distributor_AdjustmentLimit();
error Distributor_AdjustmentUnderflow();
error Distributor_NotPermissioned();

contract Distributor is Auth, Policy {
    /////////////////////////////////////////////////////////////////////////////////
    ///                          Module Dependencies                              ///
    /////////////////////////////////////////////////////////////////////////////////

    OlympusTreasury public TRSRY;
    OlympusMinter public MINTR;

    /////////////////////////////////////////////////////////////////////////////////
    ///                            System Variables                               ///
    /////////////////////////////////////////////////////////////////////////////////

    /// Olympus contract dependencies
    ERC20 private immutable ohm; // OHM Token
    address private immutable staking; // OHM Staking Contract

    /// Policy state
    Adjust public adjustment; // Information about adjusting reward rate
    address[] public pools; // Liquidity pools to receive rewards
    uint256 public rewardRate; // % to increase balances per epoch
    uint256 public bounty; // A bounty for keepers to call the triggerRebase() function
    bool private unlockRebase; // Restricts distribute() to only triggerRebase()

    /// Constants
    uint256 private constant DENOMINATOR = 1_000_000;

    constructor(
        address kernel_,
        address ohm_,
        address staking_,
        uint256 initialRate_
    ) Auth(kernel_, Authority(msg.sender)) Policy(Kernel(kernel_)) {
        if (
            kernel_ == address(0) ||
            ohm_ == address(0) ||
            staking_ == address(0) ||
            initialRate_ == 0
        ) revert Distributor_InvalidConstruction();

        ohm = ERC20(ohm_);
        staking = staking_;
        rewardRate = initialRate_;
    }

    /////////////////////////////////////////////////////////////////////////////////
    ///                     Default Framework Configuration                       ///
    /////////////////////////////////////////////////////////////////////////////////

    function configureReads() external virtual override onlyKernel {
        setAuthority(Authority(getModuleAddress("AUTHR")));
        MINTR = OlympusMinter(getModuleAddress("MINTR"));
        TRSRY = OlympusTreasury(payable(getModuleAddress("TRSRY")));
    }

    function requestRoles()
        external
        view
        virtual
        override
        returns (Kernel.Role[] memory roles)
    {
        roles = new Kernel.Role[](1);
        roles[0] = MINTR.MINTER();
    }

    /////////////////////////////////////////////////////////////////////////////////
    ///                            Public Functions                               ///
    /////////////////////////////////////////////////////////////////////////////////

    /// @notice Trigger rebases via distributor. There is an error in Staking's `stake` function
    ///         which pulls forward part of the rebase for the next epoch. This path triggers a
    ///         rebase by calling `unstake` (which does not have the issue). The patch also
    ///         restricts `distribute` to only be able to be called from a tx originating in this
    ///         function.
    function triggerRebase() external {
        unlockRebase = true;
        IStaking(staking).unstake(msg.sender, 0, true, true); // Give the caller the bounty OHM
        if (unlockRebase) revert Distributor_NoRebaseOccurred();
    }

    /////////////////////////////////////////////////////////////////////////////////
    ///                            Guarded Functions                              ///
    /////////////////////////////////////////////////////////////////////////////////

    /// @notice Send the epoch's reward to the staking contract, and mint rewards to Uniswap V2 pools.
    ///         This removes opportunity cost for liquidity providers by sending rebase rewards
    ///         directly into the liquidity pool.
    ///
    ///         NOTE: This does not add additional emissions (user could be staked instead and get the
    ///         same tokens).
    function distribute() external {
        if (msg.sender != staking) revert Distributor_OnlyStaking();
        if (!unlockRebase) revert Distributor_NotUnlocked();

        MINTR.mintOhm(staking, nextRewardFor(staking));

        uint256 poolLength = pools.length;
        for (uint256 i; i < poolLength; ) {
            address pool = pools[i];
            if (pool != address(0)) {
                MINTR.mintOhm(pool, nextRewardFor(pool));
                IUniswapV2Pair(pool).sync();
            }

            unchecked {
                i++;
            }
        }

        if (adjustment.rate != 0) {
            _adjust();
        }

        unlockRebase = false;
    }

    /// @notice Mints the bounty (if > 0) to the saking contract for distribution.
    /// @return uint256 The amount of OHM minted as a bounty.
    function retrieveBounty() external returns (uint256) {
        if (msg.sender != staking) revert Distributor_OnlyStaking();

        if (bounty > 0) MINTR.mintOhm(staking, bounty);

        return bounty;
    }

    /////////////////////////////////////////////////////////////////////////////////
    ///                            Internal Functions                             ///
    /////////////////////////////////////////////////////////////////////////////////

    function _adjust() internal {
        if (adjustment.add) {
            // if rate should increase
            rewardRate += adjustment.rate; // raise rate

            if (rewardRate >= adjustment.target) {
                // if target met
                adjustment.rate = 0; // turn off adjustment
                rewardRate = adjustment.target; // set to target
            }
        } else {
            // if rate should decrease
            if (rewardRate > adjustment.rate) {
                // protect from underflow
                rewardRate -= adjustment.rate; // lower rate
            } else {
                rewardRate = 0;
            }

            if (rewardRate <= adjustment.target) {
                // if target met
                adjustment.rate = 0; // turn off adjustment
                rewardRate = adjustment.target; // set to target
            }
        }
    }

    // TODO: Pull OHM supply and current reserves from Treasury, confirm we are not minting more than reserves
    function _checkExcessReserves(uint256 amount_) internal returns (bool) {}

    /////////////////////////////////////////////////////////////////////////////////
    ///                             View Functions                                ///
    /////////////////////////////////////////////////////////////////////////////////

    /// @notice Returns the next reward for the given address based on their OHM balance.
    /// @param  who_ The address to get the next reward for.
    /// @return uint256 The next reward for the given address.
    function nextRewardFor(address who_) public view returns (uint256) {
        return (ohm.balanceOf(who_) * rewardRate) / DENOMINATOR;
    }

    /////////////////////////////////////////////////////////////////////////////////
    ///                             Policy Functions                              ///
    /////////////////////////////////////////////////////////////////////////////////

    /// @notice Adjusts the bounty
    /// @param  bounty_ The new bounty amount.
    /// @dev    This function is only available to an authorized user.
    function setBounty(uint256 bounty_) external requiresAuth {
        bounty = bounty_;
    }

    /// @notice Sets the Uniswap V2 pools to be minted into
    /// @param  pools_ The array of Uniswap V2 pools.
    /// @dev    This function is only available to an authorized user.
    function setPools(address[] calldata pools_) external requiresAuth {
        pools = pools_;
    }

    /// @notice Removes a liquidity pool from the list of pools to be minted into
    /// @param  index_ The index in the pools array of the liquidity pool to remove.
    /// @param  pool_ The address of the liquidity pool to remove.
    /// @dev    This function is only available to an authorized user.
    function removePool(uint256 index_, address pool_) external requiresAuth {
        if (pools[index_] != pool_) revert Distributor_SanityCheck();
        pools[index_] = address(0);
    }

    /// @notice Adds a liquidity pool to the list of pools to be minted into
    /// @param  index_ The index in the pools array to add the liquidity pool to.
    /// @param  pool_ The address of the liquidity pool to add.
    function addPool(uint256 index_, address pool_) external requiresAuth {
        // we want to overwrite slots where possible
        if (pools[index_] == address(0)) {
            pools[index_] = pool_;
        } else {
            // if the passed in slot is not empty, push to the end
            pools.push(pool_);
        }
    }

    /// @notice Sets an adjustment to the reward rate.
    /// @param  add_ If reward rate should increase
    /// @param  rate_ Amount to add or decrease reward rate by
    /// @param  target_ Target reward rate
    function setAdjustment(
        bool add_,
        uint256 rate_,
        uint256 target_
    ) external requiresAuth {
        if (rate_ > (rewardRate * 25) / 1000)
            revert Distributor_AdjustmentLimit();
        if (!add_ && rate_ > rewardRate)
            revert Distributor_AdjustmentUnderflow();

        adjustment = Adjust({add: add_, rate: rate_, target: target_});
    }
}
