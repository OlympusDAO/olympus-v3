// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(screaming-snake-case-immutable)
// solhint-disable immutable-vars-naming
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ClonesWithImmutableArgs} from "clones/ClonesWithImmutableArgs.sol";

import {Cooler} from "./Cooler.sol";

/// @title  Cooler Loans Factory.
/// @notice The Cooler Factory creates new Cooler escrow contracts.
/// @dev    This contract uses Clones (https://github.com/wighawag/clones-with-immutable-args)
///         to save gas on deployment.
contract CoolerFactory {
    using ClonesWithImmutableArgs for address;

    // --- ERRORS ----------------------------------------------------

    error NotFromFactory();
    error DecimalsNot18();

    // --- EVENTS ----------------------------------------------------

    /// @notice A global event when a new loan request is created.
    event RequestLoan(address indexed cooler, address collateral, address debt, uint256 reqID);
    /// @notice A global event when a loan request is rescinded.
    event RescindRequest(address indexed cooler, uint256 reqID);
    /// @notice A global event when a loan request is fulfilled.
    event ClearRequest(address indexed cooler, uint256 reqID, uint256 loanID);
    /// @notice A global event when a loan is repaid.
    event RepayLoan(address indexed cooler, uint256 loanID, uint256 amount);
    /// @notice A global event when a loan is extended.
    event ExtendLoan(address indexed cooler, uint256 loanID, uint8 times);
    /// @notice A global event when the collateral of defaulted loan is claimed.
    event DefaultLoan(address indexed cooler, uint256 loanID, uint256 amount);

    // -- STATE VARIABLES --------------------------------------------

    /// @notice Cooler reference implementation (deployed on creation to clone from).
    Cooler public immutable coolerImplementation;

    /// @notice Mapping to validate deployed coolers.
    mapping(address => bool) public created;

    /// @notice Mapping to prevent duplicate coolers.
    mapping(address => mapping(ERC20 => mapping(ERC20 => address))) private coolerFor;

    /// @notice Mapping to query Coolers for Collateral-Debt pair.
    mapping(ERC20 => mapping(ERC20 => address[])) public coolersFor;

    // --- INITIALIZATION --------------------------------------------

    constructor() {
        coolerImplementation = new Cooler();
    }

    // --- DEPLOY NEW COOLERS ----------------------------------------

    /// @notice creates a new Escrow contract for collateral and debt tokens.
    /// @param  collateral_ the token given as collateral.
    /// @param  debt_ the token to be lent. Interest is denominated in debt tokens.
    /// @return cooler address of the contract.
    function generateCooler(ERC20 collateral_, ERC20 debt_) external returns (address cooler) {
        // Return address if cooler exists.
        cooler = coolerFor[msg.sender][collateral_][debt_];

        // Otherwise generate new cooler.
        if (cooler == address(0)) {
            if (collateral_.decimals() != 18 || debt_.decimals() != 18) revert DecimalsNot18();
            // Clone the cooler implementation.
            bytes memory coolerData = abi.encodePacked(
                msg.sender, // owner
                address(collateral_), // collateral
                address(debt_), // debt
                address(this) // factory
            );
            cooler = address(coolerImplementation).clone(coolerData);

            // Update storage accordingly.
            coolerFor[msg.sender][collateral_][debt_] = cooler;
            coolersFor[collateral_][debt_].push(cooler);
            created[cooler] = true;
        }
    }

    // --- EMIT EVENTS -----------------------------------------------

    /// @notice Ensure that the called is a Cooler.
    modifier onlyFromFactory() {
        if (!created[msg.sender]) revert NotFromFactory();
        _;
    }

    /// @notice Emit a global event when a new loan request is created.
    function logRequestLoan(uint256 reqID_) external onlyFromFactory {
        emit RequestLoan(
            msg.sender,
            address(Cooler(msg.sender).collateral()),
            address(Cooler(msg.sender).debt()),
            reqID_
        );
    }

    /// @notice Emit a global event when a loan request is rescinded.
    function logRescindRequest(uint256 reqID_) external onlyFromFactory {
        emit RescindRequest(msg.sender, reqID_);
    }

    /// @notice Emit a global event when a loan request is fulfilled.
    function logClearRequest(uint256 reqID_, uint256 loanID_) external onlyFromFactory {
        emit ClearRequest(msg.sender, reqID_, loanID_);
    }

    /// @notice Emit a global event when a loan is repaid.
    function logRepayLoan(uint256 loanID_, uint256 repayment_) external onlyFromFactory {
        emit RepayLoan(msg.sender, loanID_, repayment_);
    }

    /// @notice Emit a global event when a loan is extended.
    function logExtendLoan(uint256 loanID_, uint8 times_) external onlyFromFactory {
        emit ExtendLoan(msg.sender, loanID_, times_);
    }

    /// @notice Emit a global event when the collateral of defaulted loan is claimed.
    function logDefaultLoan(uint256 loanID_, uint256 collateral_) external onlyFromFactory {
        emit DefaultLoan(msg.sender, loanID_, collateral_);
    }

    // --- AUX FUNCTIONS ---------------------------------------------

    /// @notice Getter function to get an existing cooler for a given user <> collateral <> debt combination.
    function getCoolerFor(
        address user_,
        address collateral_,
        address debt_
    ) public view returns (address) {
        return coolerFor[user_][ERC20(collateral_)][ERC20(debt_)];
    }
}
/// forge-lint: disable-end(screaming-snake-case-immutable)
