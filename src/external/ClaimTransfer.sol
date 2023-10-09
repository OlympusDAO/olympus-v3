// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Import dependencies
import {ERC20} from "solmate/tokens/ERC20.sol";

// Import libraries
import {TransferHelper} from "libraries/TransferHelper.sol";

interface IClaimContract {
    struct Terms {
        uint256 percent;
        uint256 gClaimed;
        uint256 max;
    }

    function terms(address account_) external view returns (Terms memory);

    function pullWalletChange(address oldAddress_) external;
}

contract ClaimTransfer {
    using TransferHelper for ERC20;

    // ========= ERRORS ========= //

    error CT_UnapprovedClaimContract(address contract_);
    error CT_ClaimContractAlreadyExists(address contract_);

    // ========= DATA STRUCTURES ========= //

    struct ClaimContract {
        address claimToken;
        address depositToken;
        uint256 decimals;
    }

    // ========= STATE VARIABLES ========= //

    // Accounting
    mapping(address => ClaimContract) public claimContracts;
    mapping(address => mapping(address => mapping(address => uint256))) public allowance; // claimContract => owner => spender => allowance
    mapping(address => mapping(address => uint256)) public balanceOf; // claimContract => user => balance

    constructor() {}

    // ========= CORE FUNCTIONS ========= //

    function fractionalizeClaim(address contract_) external {
        if (claimContracts[contract_].claimToken == address(0)) revert CT_UnapprovedClaimContract(contract_);

        IClaimContract claimContract = IClaimContract(contract_);
        IClaimContract.Terms memory terms = claimContract.terms(msg.sender);

        balanceOf[contract_][msg.sender] += terms.percent;

        claimContract.pullWalletChange(msg.sender); 
    }

    function claim(address contract_) external {
        // todo
    }

    // ========= TRANSFER FUNCTIONS ========= //

    function transfer(address contract_, address to_, uint256 amount_) external {
        // Check that contract is valid
        if (claimContracts[contract_].claimToken == address(0)) revert CT_UnapprovedClaimContract(contract_);

        // Balance updates
        balanceOf[contract_][msg.sender] -= amount_;
        balanceOf[contract_][to_] += amount_;
    }

    function transferFrom(
        address contract_,
        address from_,
        address to_,
        uint256 amount_
    ) external {
        // Check that contract is valid
        if (claimContracts[contract_].claimToken == address(0)) revert CT_UnapprovedClaimContract(contract_);

        // Check that allowance is sufficient
        allowance[contract_][from_][msg.sender] -= amount_;
        
        // Balance updates
        balanceOf[contract_][from_] -= amount_;
        balanceOf[contract_][to_] += amount_;
    }

    // ========= ADMIN FUNCTIONS ========= //

    // TODO Add access control
    function addClaimContract(
        address contract_,
        address claimToken_,
        address depositToken_,
        uint256 decimals_
    ) external {
        // Check that contract is not already added
        if (claimContracts[contract_].claimToken != address(0)) revert CT_ClaimContractAlreadyExists(contract_);
        claimContracts[contract_] = ClaimContract(claimToken_, depositToken_, decimals_);
    }
}