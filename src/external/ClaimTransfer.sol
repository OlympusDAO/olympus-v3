// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Import dependencies
import {IPohm} from "policies/interfaces/IPohm.sol";
import {IgOHM} from "interfaces/IgOHM.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

// Import libraries
import {TransferHelper} from "libraries/TransferHelper.sol";

contract ClaimTransfer {
    using TransferHelper for ERC20;

    // ========= ERRORS ========= //

    error CT_IllegalClaim();

    // ========= DATA STRUCTURES ========= //

    struct Term {
        uint256 percent; // PRECISION = 1_000_000 (i.e. 5000 = 0.5%)
        uint256 gClaimed; // Rebase agnostic # of tokens claimed
        uint256 max; // Maximum nominal OHM amount claimable
    }

    // ========= STATE VARIABLES ========= //

    // Olympus Contracts
    IPohm public pohm;

    // Tokens
    ERC20 public OHM;
    ERC20 public DAI;
    IgOHM public gOHM;

    // Accounting
    mapping(address => Term) public fractionalizedTerms;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(
        address pohm_,
        address ohm_,
        address dai_,
        address gohm_
    ) {
        pohm = IPohm(pohm_);
        OHM = ERC20(ohm_);
        DAI = ERC20(dai_);
        gOHM = IgOHM(gohm_);
    }

    // ========= CORE FUNCTIONS ========= //

    function fractionalizeClaim() external {
        (uint256 percent, uint256 gClaimed, uint256 max) = pohm.terms(msg.sender);
        fractionalizedTerms[msg.sender] = Term(percent, gClaimed, max);
        
        pohm.pullWalletChange(msg.sender); 
    }

    function claim(uint256 amount_) external {
        uint256 toSend = (amount_ * 1e9) / 1e18;

        // Get fractionalized terms
        Term memory terms = fractionalizedTerms[msg.sender];
        (, uint256 gClaimedBefore,) = pohm.terms(address(this));
        uint256 circulatingSupply = pohm.getCirculatingSupply();
        uint256 accountClaimed = gOHM.balanceFrom(terms.gClaimed);

        // Perform checks
        uint256 max = (circulatingSupply * fractionalizedTerms[msg.sender].percent) / 1e6;
        max = max > terms.max ? terms.max : max;
        uint256 maxClaimable = max - accountClaimed;
        if ((terms.max - accountClaimed) < toSend) revert CT_IllegalClaim();

        // Update fractionalized terms
        fractionalizedTerms[msg.sender].gClaimed += gOHM.balanceTo(toSend);

        DAI.transferFrom(msg.sender, address(this), amount_);
        pohm.claim(msg.sender, amount_);
    }

    // ========= TRANSFER FUNCTIONS ========= //

    function approve(address spender_, uint256 amount_) external returns (bool) {
        allowance[msg.sender][spender_] = amount_;
        return true;
    }

    function transfer(address to_, uint256 amount_) external returns (bool) {
        // Get fractionalized terms
        Term memory terms = fractionalizedTerms[msg.sender];

        uint256 gClaimedToTransfer = (amount_ * terms.gClaimed) / terms.percent;
        uint256 maxToTransfer = (amount_ * terms.max) / terms.percent;
        uint256 maxAdjustment = gOHM.balanceFrom(gClaimedToTransfer);

        // Balance updates
        fractionalizedTerms[msg.sender].percent -= amount_;
        fractionalizedTerms[msg.sender].gClaimed -= gClaimedToTransfer;
        fractionalizedTerms[msg.sender].max -= maxToTransfer + maxAdjustment;

        fractionalizedTerms[to_].percent += amount_;
        fractionalizedTerms[to_].gClaimed += gClaimedToTransfer;
        fractionalizedTerms[to_].max += maxToTransfer + maxAdjustment;

        return true;
    }

    function transferFrom(
        address from_,
        address to_,
        uint256 amount_
    ) external returns (bool) {
        // Get fractionalized terms
        Term memory terms = fractionalizedTerms[from_];

        uint256 gClaimedToTransfer = (amount_ * terms.gClaimed) / terms.percent;
        uint256 maxToTransfer = (amount_ * terms.max) / terms.percent;
        uint256 maxAdjustment = gOHM.balanceFrom(gClaimedToTransfer);

        // Check that allowance is sufficient
        allowance[from_][msg.sender] -= amount_;
        
        // Balance updates
        fractionalizedTerms[from_].percent -= amount_;
        fractionalizedTerms[from_].gClaimed -= gClaimedToTransfer;
        fractionalizedTerms[from_].max -= maxToTransfer + maxAdjustment;

        fractionalizedTerms[to_].percent += amount_;
        fractionalizedTerms[to_].gClaimed += gClaimedToTransfer;
        fractionalizedTerms[to_].max += maxToTransfer + maxAdjustment;

        return true;
    }
}