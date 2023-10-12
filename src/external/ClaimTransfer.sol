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

    constructor() {}

    // ========= CORE FUNCTIONS ========= //

    function fractionalizeClaim() external {
        IPohm.Term memory terms = pohm.terms(msg.sender);
        fractionalizedTerms[msg.sender] = Term(terms.percent, terms.gClaimed, terms.max);
        
        pohm.pullWalletChange(msg.sender); 
    }

    function claim(address contract_) external {
        // todo
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