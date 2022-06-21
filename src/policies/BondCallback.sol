// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";

import {IBondCallback} from "interfaces/IBondCallback.sol";
import {IBondAggregator} from "interfaces/IBondAggregator.sol";
import {OlympusTreasury} from "modules/TRSRY.sol";
import {OlympusMinter} from "modules/MINTR.sol";
import {OlympusAuthority} from "modules/AUTHR.sol";
import {Kernel, Policy} from "../Kernel.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

/// @title Olympus Bond Callback
contract BondCallback is Policy, Auth, IBondCallback {
    using TransferHelper for ERC20;

    /* ========== ERRORS ========== */

    error Callback_MarketNotSupported(uint256 id);
    error Callback_TokensNotReceived();

    /* ========== STATE VARIABLES ========== */

    mapping(address => mapping(uint256 => bool)) public approvedMarkets;
    mapping(uint256 => uint256[2]) internal _amountsPerMarket;
    mapping(ERC20 => uint256) public priorBalances;

    IBondAggregator public aggregator;
    OlympusTreasury public TRSRY;
    OlympusMinter public MINTR;
    ERC20 public ohm;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        Kernel kernel_,
        IBondAggregator aggregator_,
        ERC20 ohm_
    ) Policy(kernel_) Auth(address(kernel_), Authority(address(0))) {
        aggregator = aggregator_;
        ohm = ohm_;
    }

    /* ========== FRAMEWORK CONFIGURATION ========== */

    function configureReads() external override onlyKernel {
        setAuthority(Authority(getModuleAddress("AUTHR")));
        TRSRY = OlympusTreasury(getModuleAddress("TRSRY"));
        MINTR = OlympusMinter(getModuleAddress("MINTR"));
    }

    function requestRoles()
        external
        view
        override
        onlyKernel
        returns (Kernel.Role[] memory roles)
    {
        roles = new Kernel.Role[](2);
        roles[0] = TRSRY.BANKER();
        roles[1] = MINTR.MINTER();
    }

    /* ========== WHITELISTING ========== */

    /// @inheritdoc IBondCallback
    function whitelist(address teller_, uint256 id_)
        external
        override
        requiresAuth
    {
        approvedMarkets[teller_][id_] = true;
    }

    /* ========== CALLBACK ========== */

    /// @inheritdoc IBondCallback
    function callback(
        uint256 id_,
        uint256 inputAmount_,
        uint256 outputAmount_
    ) external override {
        /// Confirm that the teller and market id are whitelisted
        if (!approvedMarkets[msg.sender][id_])
            revert Callback_MarketNotSupported(id_);

        // Get tokens for market
        (, , ERC20 payoutToken, ERC20 quoteToken, , ) = aggregator
            .getAuctioneer(id_)
            .getMarketInfoForPurchase(id_);

        // Check that quoteTokens were transferred prior to the call
        if (
            quoteToken.balanceOf(address(this)) !=
            priorBalances[quoteToken] + inputAmount_
        ) revert Callback_TokensNotReceived();

        // Handle payout
        if (quoteToken == payoutToken && quoteToken == ohm) {
            // If OHM-OHM bond, only mint the difference and transfer back to teller
            uint256 toMint = outputAmount_ - inputAmount_;
            MINTR.mintOhm(address(this), toMint);

            // Transfer payoutTokens to sender
            payoutToken.safeTransfer(msg.sender, outputAmount_);
        } else if (quoteToken == ohm) {
            /// If inverse bond (buying ohm), transfer payout tokens to sender
            TRSRY.withdrawReserves(msg.sender, payoutToken, outputAmount_);
        } else {
            // Else (selling ohm), mint OHM to sender
            MINTR.mintOhm(msg.sender, outputAmount_);
        }

        /// Store amounts in/out
        /// @dev updated after internal call so previous balances are available to check against
        priorBalances[quoteToken] = quoteToken.balanceOf(address(this));
        priorBalances[payoutToken] = payoutToken.balanceOf(address(this));
        _amountsPerMarket[id_][0] += inputAmount_;
        _amountsPerMarket[id_][1] += outputAmount_;
    }

    /* ========== WITHDRAW TOKENS ========== */

    /// @notice         Send tokens to the TRSRY in a batch
    /// @param tokens_  Array of tokens to send
    function batchToTreasury(ERC20[] memory tokens_) external requiresAuth {
        ERC20 token;
        uint256 balance;
        uint256 len = tokens_.length;
        for (uint256 i; i < len; i++) {
            token = tokens_[i];
            balance = token.balanceOf(address(this));
            token.transfer(address(TRSRY), balance);
            priorBalances[token] = token.balanceOf(address(this));
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @inheritdoc IBondCallback
    function amountsForMarket(uint256 id_)
        external
        view
        override
        returns (uint256 in_, uint256 out_)
    {
        uint256[2] memory marketAmounts = _amountsPerMarket[id_];
        return (marketAmounts[0], marketAmounts[1]);
    }
}
