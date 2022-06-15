// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import "src/interfaces/IERC20.sol";

interface IsOHM is IERC20 {
    function rebase(uint256 profit_, uint256 epoch_) external returns (uint256);

    function circulatingSupply() external view returns (uint256);

    function index() external view returns (uint256);

    function balanceForGons(uint256 gons) external view returns (uint256);
}

interface IgOHM is IERC20 {
    function mint(address to_, uint256 amount_) external;

    function burn(address from_, uint256 amount_) external;

    function balanceFrom(uint256 amount_) external view returns (uint256);

    function balanceTo(uint256 amount_) external view returns (uint256);
}

interface IDistributor {
    function distribute() external;

    function retrieveBounty() external returns (uint256);
}

contract MockStaking {
    struct Epoch {
        uint256 length;
        uint256 number;
        uint256 end;
        uint256 distribute;
    }

    struct Claim {
        uint256 deposit;
        uint256 gons;
        uint256 expiry;
        bool lock;
    }

    IERC20 public OHM;
    IsOHM public sOHM;
    IgOHM public gOHM;

    Epoch public epoch;

    IDistributor public distributor;

    mapping(address => Claim) public warmupInfo;
    uint256 public warmupPeriod;
    uint256 private gonsInWarmup;

    constructor(
        address ohm_,
        address sohm_,
        address gohm_,
        uint256 epochLength_,
        uint256 firstEpochNumber_,
        uint256 firstEpochTime_
    ) {
        OHM = IERC20(ohm_);
        sOHM = IsOHM(sohm_);
        gOHM = IgOHM(gohm_);

        epoch = Epoch({
            length: epochLength_,
            number: firstEpochNumber_,
            end: firstEpochTime_,
            distribute: 0
        });
    }

    /// Setters

    function setOHM(address ohm_) public {
        OHM = IERC20(ohm_);
    }

    function setSOHM(address sohm_) public {
        sOHM = IsOHM(sohm_);
    }

    function setGOHM(address gohm_) public {
        gOHM = IgOHM(gohm_);
    }

    function setEpoch(
        uint256 length_,
        uint256 number_,
        uint256 end_,
        uint256 distribute_
    ) public {
        epoch.length = length_;
        epoch.number = number_;
        epoch.end = end_;
        epoch.distribute = distribute_;
    }

    function setDistributor(address distributor_) public {
        distributor = IDistributor(distributor_);
    }

    function setWarmup(
        address user_,
        uint256 deposit_,
        uint256 gons_,
        uint256 expiry_,
        bool lock_
    ) public {
        warmupInfo[user_].deposit = deposit_;
        warmupInfo[user_].gons = gons_;
        warmupInfo[user_].expiry = expiry_;
        warmupInfo[user_].lock = lock_;
    }

    function setWarmupPeriod(uint256 period_) public {
        warmupPeriod = period_;
    }

    function setGonsInWarmup(uint256 gons_) public {
        gonsInWarmup = gons_;
    }

    /// Interaction Functions

    function stake(
        address to_,
        uint256 amount_,
        bool rebasing_,
        bool claim_
    ) external returns (uint256) {
        OHM.transferFrom(msg.sender, address(this), amount_);
        amount_ = amount_ + rebase();
        if (claim_) {
            // Do nothing, not relevant for a mock to test Distributor
        }
        return _send(to_, amount_, rebasing_);
    }

    function claim(address to_, bool rebasing_) public returns (uint256) {}

    function forfeit() external returns (uint256) {}

    function toggleLock() external {
        warmupInfo[msg.sender].lock = !warmupInfo[msg.sender].lock;
    }

    function unstake(
        address to_,
        uint256 amount_,
        bool trigger_,
        bool rebasing_
    ) external returns (uint256 amount) {
        uint256 bounty;
        if (trigger_) bounty = rebase();

        if (rebasing_) {
            sOHM.transferFrom(msg.sender, address(this), amount_);
            amount = amount_ + bounty;
        } else {
            gOHM.burn(msg.sender, amount_);
            amount = gOHM.balanceFrom(amount_) + bounty;
        }

        OHM.transfer(to_, amount);
    }

    function wrap(address to_, uint256 amount_)
        external
        returns (uint256 gBalance_)
    {
        sOHM.transferFrom(msg.sender, address(this), amount_);
        gBalance_ = gOHM.balanceTo(amount_);
        gOHM.mint(to_, gBalance_);
    }

    function unwrap(address to_, uint256 amount_)
        external
        returns (uint256 sBalance_)
    {
        gOHM.burn(msg.sender, amount_);
        sBalance_ = gOHM.balanceFrom(amount_);
        sOHM.transfer(to_, sBalance_);
    }

    function rebase() public returns (uint256) {
        uint256 bounty;
        if (epoch.end <= block.timestamp) {
            sOHM.rebase(epoch.distribute, epoch.number);

            epoch.end = epoch.end + epoch.length;
            epoch.number = epoch.number + 1;

            distributor.distribute();
            bounty = distributor.retrieveBounty();

            uint256 balance = OHM.balanceOf(address(this));
            uint256 staked = sOHM.circulatingSupply();
            if (balance <= staked + bounty) {
                epoch.distribute = 0;
            } else {
                epoch.distribute = balance - staked - bounty;
            }
        }

        return bounty;
    }

    /// Internal Functions

    function _send(
        address to_,
        uint256 amount_,
        bool rebasing_
    ) internal returns (uint256) {
        if (rebasing_) {
            sOHM.transfer(to_, amount_);
            return amount_;
        } else {
            gOHM.mint(to_, gOHM.balanceTo(amount_));
            return gOHM.balanceTo(amount_);
        }
    }

    /// View Functions

    function index() public view returns (uint256) {
        return sOHM.index();
    }

    function supplyInWarmup() public view returns (uint256) {
        return sOHM.balanceForGons(gonsInWarmup);
    }

    function secondsToNextEpoch() external view returns (uint256) {
        return epoch.end - block.timestamp;
    }
}
