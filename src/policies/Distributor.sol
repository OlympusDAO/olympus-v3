// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// Import External Dependencies
import "solmate/auth/Auth.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/// Import Local Dependencies
import {Kernel, Policy} from "src/Kernel.sol";
import "src/modules/TRSRY.sol";
import "src/modules/MINTR.sol";
import "src/interfaces/IStaking.sol";
import "src/interfaces/Uniswap/IUniswapV2Pair.sol";

/// Define Inline Types
struct Adjust {
    bool add; // whether to add or subtract from the reward rate
    uint256 rate; // the amount to add or subtract per epoch
    uint256 target; // the target rate to adjust the reward rate to
}

/// Define Custom Errors
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
        // Add in 0 address checks
        ohm = ERC20(ohm_);
        staking = staking_;
        rewardRate = initialRate_;
    }

    /////////////////////////////////////////////////////////////////////////////////
    ///                     Default Framework Configuration                       ///
    /////////////////////////////////////////////////////////////////////////////////

    function configureReads() external virtual override onlyKernel {
        setAuthority(Authority(getModuleAddress("AUTHR")));
        TRSRY = OlympusTreasury(payable(getModuleAddress("TRSRY")));
    }

    function requestWrites()
        external
        pure
        virtual
        override
        returns (bytes5[] memory permissions)
    {
        permissions = new bytes5[](2);
        permissions[1] = "MINTR";
    }

    /////////////////////////////////////////////////////////////////////////////////
    ///                            Public Functions                               ///
    /////////////////////////////////////////////////////////////////////////////////

    function triggerRebase() external {
        unlockRebase = true;
        IStaking(staking).unstake(msg.sender, 0, true, true); // Give the caller the bounty OHM
        if (unlockRebase) revert Distributor_NoRebaseOccurred();
    }

    /////////////////////////////////////////////////////////////////////////////////
    ///                            Guarded Functions                              ///
    /////////////////////////////////////////////////////////////////////////////////

    function distribute() external {
        if (msg.sender != staking) revert Distributor_OnlyStaking();
        if (!unlockRebase) revert Distributor_NotUnlocked();

        MINTR.mintOhm(address(TRSRY), nextRewardFor(staking));

        for (uint256 i; i < pools.length; ) {
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

    function retrieveBounty() external returns (uint256) {
        if (msg.sender != staking) revert Distributor_OnlyStaking();

        /// If the distributor bounty is >0, mint it for the staking contract
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

    function nextRewardFor(address who_) public view returns (uint256) {
        return (ohm.balanceOf(who_) * rewardRate) / DENOMINATOR;
    }

    /////////////////////////////////////////////////////////////////////////////////
    ///                             Policy Functions                              ///
    /////////////////////////////////////////////////////////////////////////////////

    function setBounty(uint256 bounty_) external requiresAuth {
        bounty = bounty_;
    }

    function setPools(address[] calldata pools_) external requiresAuth {
        pools = pools_;
    }

    function removePool(uint256 index_, address pool_) external requiresAuth {
        if (pools[index_] != pool_) revert Distributor_SanityCheck();
        pools[index_] = address(0);
    }

    function addPool(uint256 index_, address pool_) external requiresAuth {
        // we want to overwrite slots where possible
        if (pools[index_] == address(0)) {
            pools[index_] = pool_;
        } else {
            // if the passed in slot is not empty, push to the end
            pools.push(pool_);
        }
    }

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
