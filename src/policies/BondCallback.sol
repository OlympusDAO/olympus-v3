// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {IBondCallback} from "interfaces/IBondCallback.sol";
import {IBondAggregator} from "interfaces/IBondAggregator.sol";
import {OlympusTreasury} from "modules/TRSRY.sol";
import {OlympusMinter} from "modules/MINTR.sol";
import {Operator} from "policies/Operator.sol";
import "src/Kernel.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

/// @title Olympus Bond Callback
contract BondCallback is Policy, ReentrancyGuard, IBondCallback {
    using TransferHelper for ERC20;

    error Callback_MarketNotSupported(uint256 id);
    error Callback_TokensNotReceived();
    error Callback_InvalidParams();

    mapping(address => mapping(uint256 => bool)) public approvedMarkets;
    mapping(uint256 => uint256[2]) internal _amountsPerMarket;
    mapping(ERC20 => uint256) public priorBalances;

    IBondAggregator public aggregator;
    OlympusTreasury public TRSRY;
    OlympusMinter public MINTR;
    Operator public operator;
    ERC20 public ohm;

    /*//////////////////////////////////////////////////////////////
                            POLICY INTERFACE
    //////////////////////////////////////////////////////////////*/

    constructor(
        Kernel kernel_,
        IBondAggregator aggregator_,
        ERC20 ohm_
    ) Policy(kernel_) {
        aggregator = aggregator_;
        ohm = ohm_;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("MINTR");

        TRSRY = OlympusTreasury(getModuleAddress(dependencies[0]));
        MINTR = OlympusMinter(getModuleAddress(dependencies[1]));

        // Approve MINTR for burning OHM (called here so that it is re-approved on updates)
        ohm.safeApprove(address(MINTR), type(uint256).max);
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        onlyKernel
        returns (Permissions[] memory requests)
    {
        Keycode TRSRY_KEYCODE = TRSRY.KEYCODE();
        Keycode MINTR_KEYCODE = MINTR.KEYCODE();

        requests = new Permissions[](4);
        requests[0] = Permissions(TRSRY_KEYCODE, TRSRY.setApprovalFor.selector);
        requests[1] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        requests[2] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        requests[3] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
    }

    /*//////////////////////////////////////////////////////////////
                               CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBondCallback
    function whitelist(address teller_, uint256 id_)
        external
        override
        onlyRole("callback_whitelist")
    {
        approvedMarkets[teller_][id_] = true;

        // Get payout tokens for market
        (, , ERC20 payoutToken, , , ) = aggregator.getAuctioneer(id_).getMarketInfoForPurchase(id_);

        /// If payout token is not OHM, request approval from TRSRY for withdrawals
        if (address(payoutToken) != address(ohm)) {
            TRSRY.setApprovalFor(address(this), payoutToken, type(uint256).max);
        }
    }

    /// @inheritdoc IBondCallback
    function callback(
        uint256 id_,
        uint256 inputAmount_,
        uint256 outputAmount_
    ) external override nonReentrant {
        /// Confirm that the teller and market id are whitelisted
        if (!approvedMarkets[msg.sender][id_]) revert Callback_MarketNotSupported(id_);

        // Get tokens for market
        (, , ERC20 payoutToken, ERC20 quoteToken, , ) = aggregator
            .getAuctioneer(id_)
            .getMarketInfoForPurchase(id_);

        // Check that quoteTokens were transferred prior to the call
        if (quoteToken.balanceOf(address(this)) < priorBalances[quoteToken] + inputAmount_)
            revert Callback_TokensNotReceived();

        // Handle payout
        if (quoteToken == payoutToken && quoteToken == ohm) {
            // If OHM-OHM bond, only mint the difference and transfer back to teller
            uint256 toMint = outputAmount_ - inputAmount_;
            MINTR.mintOhm(address(this), toMint);

            // Transfer payoutTokens to sender
            payoutToken.safeTransfer(msg.sender, outputAmount_);
        } else if (quoteToken == ohm) {
            // If inverse bond (buying ohm), transfer payout tokens to sender
            TRSRY.withdrawReserves(msg.sender, payoutToken, outputAmount_);

            // Burn OHM received from sender
            MINTR.burnOhm(address(this), inputAmount_);
        } else if (payoutToken == ohm) {
            // Else (selling ohm), mint OHM to sender
            MINTR.mintOhm(msg.sender, outputAmount_);
        } else {
            // Revert since this callback only handles OHM bonds
            revert Callback_MarketNotSupported(id_);
        }

        // Store amounts in/out.
        // Updated after internal call so previous balances are available to check against
        priorBalances[quoteToken] = quoteToken.balanceOf(address(this));
        priorBalances[payoutToken] = payoutToken.balanceOf(address(this));
        _amountsPerMarket[id_][0] += inputAmount_;
        _amountsPerMarket[id_][1] += outputAmount_;

        // Check if the market is deployed by range operator and update capacity if so
        operator.bondPurchase(id_, outputAmount_);
    }

    /// @notice Send tokens to the TRSRY in a batch
    /// @param  tokens_ - Array of tokens to send
    function batchToTreasury(ERC20[] memory tokens_) external onlyRole("callback_admin") {
        ERC20 token;
        uint256 balance;
        uint256 len = tokens_.length;
        for (uint256 i; i < len; ) {
            token = tokens_[i];
            balance = token.balanceOf(address(this));
            token.safeTransfer(address(TRSRY), balance);
            priorBalances[token] = token.balanceOf(address(this));

            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the operator contract for the callback to use to report bond purchases
    /// @notice Must be set before the callback is used
    /// @param  operator_ - Address of the Operator contract
    function setOperator(Operator operator_) external onlyRole("callback_admin") {
        if (address(operator_) == address(0)) revert Callback_InvalidParams();
        operator = operator_;
    }
}
