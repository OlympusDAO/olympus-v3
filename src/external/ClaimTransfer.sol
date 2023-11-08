// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Import dependencies
import {IPohm} from "policies/interfaces/IPohm.sol";
import {IgOHM} from "interfaces/IgOHM.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

// Import libraries
import {TransferHelper} from "libraries/TransferHelper.sol";

/// @title Olympus Claim Transfer Contract
/// @dev This contract is used to fractionalize pOHM claims and transfer portions of a user's claim to other addresses
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

        // Get fractionalized terms and validate claim
        Term memory terms = fractionalizedTerms[msg.sender];
        pohm.validateClaim(amount_, IPohm.Term({percent: terms.percent, gClaimed: terms.gClaimed, max: terms.max}));

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
    /// @dev    Transferring a portion of your claim transfers both based on the percentage and claimable amount of OHM.
    ///         The recipient will receive a claimable amount of OHM commensurate to the percentage of the sender's max claim
    ///         ignoring what the sender has already claimed. Say the sender has a percent of 10_000 and a max claim of 100 OHM.
    ///         They claim 10 OHM, leaving 90 OHM claimable. If they transfer 50% of their claim (5_000), the recipient gets a
    ///         max value of 55 and the commensurate gClaimed so they have a true claimable amount of 50 OHM. The sender's
    ///         fractionalized claim is updated to reflect the transfer.
    function transfer(address to_, uint256 amount_) external returns (bool) {
        // Transfer
        _transfer(msg.sender, to_, amount_);

        return true;
    }

    /// @notice Transfer a portion of a fractionalized claim from another address to a recipient (must have approval)
    /// @param from_ Address of the sender
    /// @param to_ Address of the recipient
    /// @param amount_ Amount of the sender's fractionalized claim to transfer
    /// @return bool
    /// @dev    Transferring a portion of your claim transfers both based on the percentage and claimable amount of OHM.
    ///         The recipient will receive a claimable amount of OHM commensurate to the percentage of the sender's max claim
    ///         ignoring what the sender has already claimed. Say the sender has a percent of 10_000 and a max claim of 100 OHM.
    ///         They claim 10 OHM, leaving 90 OHM claimable. If they transfer 50% of their claim (5_000), the recipient gets a
    ///         max value of 55 and the commensurate gClaimed so they have a true claimable amount of 50 OHM. The sender's
    ///         fractionalized claim is updated to reflect the transfer.
    function transferFrom(
        address from_,
        address to_,
        uint256 amount_
    ) external returns (bool) {
        // Check that allowance is sufficient
        allowance[from_][msg.sender] -= amount_;

        // Transfer
        _transfer(from_, to_, amount_);

        return true;
    }

    // ========= INTERNAL FUNCTIONS ========= //

    function _transfer(address from_, address to_, uint256 amount_) internal {
        // Get fractionalized terms
        Term memory terms = fractionalizedTerms[from_];

        uint256 gClaimedToTransfer = (amount_ * terms.gClaimed) / terms.percent;
        uint256 maxToTransfer = (amount_ * terms.max) / terms.percent;
        uint256 maxAdjustment = gOHM.balanceFrom(gClaimedToTransfer);
        maxToTransfer += maxAdjustment;

        // Balance updates
        fractionalizedTerms[from_].percent -= amount_;
        fractionalizedTerms[from_].gClaimed -= gClaimedToTransfer;
        fractionalizedTerms[from_].max -= maxToTransfer;

        fractionalizedTerms[to_].percent += amount_;
        fractionalizedTerms[to_].gClaimed += gClaimedToTransfer;
        fractionalizedTerms[to_].max += maxToTransfer;
    }
}