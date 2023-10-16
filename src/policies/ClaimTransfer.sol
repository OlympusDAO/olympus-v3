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

        // Approve pohm to spend DAI
        DAI.approve(pohm_, type(uint256).max);
    }

    // ========= CORE FUNCTIONS ========= //

    /// @notice Convert pOHM claim that can only be fully transfered to a new wallet to a fractionalized claim
    function fractionalizeClaim() external {
        (uint256 percent, uint256 gClaimed, uint256 max) = pohm.terms(msg.sender);
        fractionalizedTerms[msg.sender] = Term(percent, gClaimed, max);
        
        pohm.pullWalletChange(msg.sender); 
    }

    /// @notice Claim OHM from the pOHM contract via your fractionalized claim
    /// @param amount_ Amount of DAI to send to the pOHM contract
    function claim(uint256 amount_) external {
        uint256 toSend = (amount_ * 1e9) / 1e18;

        // Get fractionalized terms
        Term memory terms = fractionalizedTerms[msg.sender];
        uint256 circulatingSupply = pohm.getCirculatingSupply();
        uint256 accountClaimed = gOHM.balanceFrom(terms.gClaimed);

        // Perform checks
        uint256 max = (circulatingSupply * fractionalizedTerms[msg.sender].percent) / 1e6;
        max = max > terms.max ? terms.max : max;
        uint256 maxClaimable = max - accountClaimed;
        if (maxClaimable < toSend) revert CT_IllegalClaim();

        // Update fractionalized terms
        fractionalizedTerms[msg.sender].gClaimed += gOHM.balanceTo(toSend);

        DAI.transferFrom(msg.sender, address(this), amount_);
        pohm.claim(msg.sender, amount_);
    }

    // ========= TRANSFER FUNCTIONS ========= //

    /// @notice Approve a spender to spend a certain amount of your fractionalized claim (denominated in the `percent` value of a Term)
    /// @param spender_ Address of the spender
    /// @param amount_ Amount of your fractionalized claim to approve
    /// @return bool
    function approve(address spender_, uint256 amount_) external returns (bool) {
        allowance[msg.sender][spender_] = amount_;
        return true;
    }

    /// @notice Transfer a portion of your fractionalized claim to another address
    /// @param to_ Address of the recipient
    /// @param amount_ Amount of your fractionalized claim to transfer
    /// @return bool
    /// @dev    Transfering a portion of your claim should not result in the recipient getting a small amount of max claimable
    ///         OHM due to what you've already claimed. This function will adjust the max claimable amount to account for this.
    ///         That is, if you transfer 50% of your claim, the recipient will be able to claim 50% of the original max claimable OHM 
    function transfer(address to_, uint256 amount_) external returns (bool) {
        // Get fractionalized terms
        Term memory terms = fractionalizedTerms[msg.sender];

        uint256 gClaimedToTransfer = (amount_ * terms.gClaimed) / terms.percent;
        uint256 maxToTransfer = (amount_ * terms.max) / terms.percent;
        uint256 maxAdjustment = gOHM.balanceFrom(gClaimedToTransfer);
        maxToTransfer += maxAdjustment;

        // Balance updates
        fractionalizedTerms[msg.sender].percent -= amount_;
        fractionalizedTerms[msg.sender].gClaimed -= gClaimedToTransfer;
        fractionalizedTerms[msg.sender].max -= maxToTransfer;

        fractionalizedTerms[to_].percent += amount_;
        fractionalizedTerms[to_].gClaimed += gClaimedToTransfer;
        fractionalizedTerms[to_].max += maxToTransfer;

        return true;
    }

    /// @notice Transfer a portion of a fractionalized claim from another address to a recipient (must have approval)
    /// @param from_ Address of the sender
    /// @param to_ Address of the recipient
    /// @param amount_ Amount of the sender's fractionalized claim to transfer
    /// @return bool
    /// @dev    Transfering a portion of your claim should not result in the recipient getting a small amount of max claimable
    ///         OHM due to what you've already claimed. This function will adjust the max claimable amount to account for this.
    ///         That is, if you transfer 50% of your claim, the recipient will be able to claim 50% of the original max claimable OHM
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
        maxToTransfer += maxAdjustment;

        // Check that allowance is sufficient
        allowance[from_][msg.sender] -= amount_;
        
        // Balance updates
        fractionalizedTerms[from_].percent -= amount_;
        fractionalizedTerms[from_].gClaimed -= gClaimedToTransfer;
        fractionalizedTerms[from_].max -= maxToTransfer;

        fractionalizedTerms[to_].percent += amount_;
        fractionalizedTerms[to_].gClaimed += gClaimedToTransfer;
        fractionalizedTerms[to_].max += maxToTransfer;

        return true;
    }
}