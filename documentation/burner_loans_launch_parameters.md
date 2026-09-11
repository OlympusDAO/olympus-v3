# Burner Loans Launch Parameters

| Parameter                | USDS             | USDe             | Rationale                                                 |
| ------------------------ | ---------------- | ---------------- | --------------------------------------------------------- |
| New borrowing            | Enabled          | Enabled          | Approve both assets before launch                         |
| Borrow and extension fee | 0%               | 0%               | Base fee and both slopes are zero                         |
| Maximum LTV              | 85%              | 85%              | One-point buffer below Morpho's 86% LLTV tier             |
| Backing multiplier       | 125%             | 125%             | With max LTV, prevents borrowing below either requirement |
| Term                     | 30 days          | 30 days          | Fixed term; users may extend                              |
| Asset debt cap           | 50,000 OHM       | 50,000 OHM       | Limits launch exposure from each asset                    |
| Third-party reward       | 1%; max 100 USDS | 1%; max 100 USDe | Reasonable, capped incentive for third-party seizure      |

## External Collateral And Liquidation Precedents

The values below were reviewed on 27 August 2026. Platform parameters can change after this date.
Each platform uses different liquidation mechanics, so similar percentages do not always measure
the same risk boundary.

The following conversions make the comparison easier:

```text
recognized collateral value = oracle market value * collateral factor
collateral factor = 1 - haircut
implied collateral-to-debt ratio = 1 / liquidation LTV
```

### Lending And Borrowing Markets

| Platform and market                                                                                                                                         | Published limits                                                                                          | Collateral treatment                                                                                    | Relevance to Burner Loans                                                                                 |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| [Morpho Blue](https://docs.morpho.org/learn/concepts/blue/#governance-approved-lltv--irm)                                                                   | Governance-approved LLTV tiers include 77%, 86%, and 91.5%. A position with LTV above the selected LLTV is liquidatable. | The market oracle supplies collateral value. The LLTV contains the market-value buffer.                 | This is the closest structural precedent. The 85% launch limit is one point below the 86% tier.           |
| [Aave V3 Ethereum USDe onboarding](https://governance.aave.com/t/arfc-onboard-usde-to-aave-v3-on-ethereum/17690)                                            | 72% maximum LTV and 75% liquidation threshold.                                                            | Aave used isolation mode, a $40 million debt ceiling, market pricing, and a $1.04 oracle cap.           | This is a conservative admission case for uncorrelated USDe borrowing.                                    |
| [Aave V3 Ethereum USDe stablecoin E-Mode](https://governance.aave.com/t/direct-to-aip-remove-usde-debt-ceiling-and-introduce-usde-stablecoins-e-mode/21876) | 90% maximum LTV and 93% liquidation threshold.                                                            | The limits apply when USDe collateral supports specified stablecoin debt.                               | The higher limits depend on asset correlation and restricted debt eligibility.                            |
| [Aave V3 Ethereum USDS governance review](https://governance.aave.com/t/arfc-remove-usds-as-collateral-and-increase-rf-across-all-aave-instances/23426/5)   | The review recommended reducing maximum LTV from 75% to 0%.                                               | A zero limit removes collateral eligibility instead of applying a larger haircut.                       | This shows that eligibility, caps, and LTV are separate risk controls.                                    |
| [Hyperliquid portfolio margin pre-alpha](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/portfolio-margin)                                          | HYPE has a 50% LTV. Its liquidation threshold is 75% under Hyperliquid's formula.                         | HYPE supports USDC borrowing under low pre-alpha caps. Liquidation uses the complete portfolio account. | This is a direct LTV precedent, but the volatile collateral and portfolio model differ from Burner Loans. |

### Options And Perpetual Markets

Derivatives margin works differently from lending. No lender advances the full position notional as
principal. Margin secures future profit and loss on the derivative position. Initial and
maintenance percentages are therefore not LTVs.

| Platform and model                                                                                                       | Margin limits                                                                                                                | Collateral treatment                                                                                                                                 | Relevance to Burner Loans                                                                                  |
| ------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| [Derive standard margin](https://docs.derive.xyz/docs/standard-margin-1)                                                 | Perpetual initial margin is 10%. Maintenance margin is 6.5%.                                                                 | ETH receives 75% initial and 80% maintenance value. BTC receives 69.75% initial and 75% maintenance value. USDC depeg protection starts below $0.99. | Derive separates opening margin, maintenance margin, collateral haircuts, and stablecoin depeg protection. |
| [Deribit cross collateral](https://support.deribit.com/hc/en-us/articles/25944777203869-Cross-collateral-specifications) | The portfolio risk engine sets margin requirements instead of one loan LTV.                                                  | USDe has a 5% haircut, so 95% of its USD value supports margin. USDC has no haircut and USDT has 2%.                                                 | This is a direct precedent for discounting USDe collateral value.                                          |
| [Hyperliquid standard perpetuals](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/margining)                     | Initial margin equals position value divided by leverage. Maintenance margin is half the initial margin at maximum leverage. | Standard perpetuals use USDC margin. The system does not adjust USDC against USDT-denominated profit and loss.                                       | This is a derivatives margin precedent, not a lending LTV precedent.                                       |
| [Aevo cross collateral](https://docs.aevo.xyz/aevo-products/aevo-exchange/technical-architecture/collateral-framework)   | The account risk engine applies initial and maintenance margin requirements.                                                 | Collateral ratios are 100% for USDC, 99% for USDT, 90% for ETH and WBTC, and 85% for weETH.                                                          | This shows explicit discounts for collateral liquidity and conversion risk.                                |

### Application To Burner Loans

Burner Loans uses gross oracle value for USDS and USDe. It does not apply a separate collateral
haircut. Therefore, its implicit collateral factor is 100%, and the 85% maximum LTV supplies the
complete market-value buffer.

Morpho provides the closest direct parameter precedent. The 85% launch value is below Morpho's 86%
LLTV tier and requires approximately 117.65% collateral value for each unit of debt value.

Aave demonstrates that market context changes a suitable limit. Its initial USDe listing used a
75% liquidation threshold. Its correlated stablecoin E-Mode used a 93% threshold with restricted
debt assets. Burner Loans uses 85% between these two cases and also limits each asset to 50,000 OHM.

Derive, Deribit, Hyperliquid, and Aevo do not provide a direct loan-LTV benchmark. Their margin
systems still show two useful controls: separate opening and liquidation buffers, and explicit
collateral discounts. Burner Loans can add an asset-specific haircut later if stress tests show that
gross oracle value overstates realizable collateral value.

The backing multiplier has no direct equivalent in these platforms. It protects the liquid backing
per borrowed OHM when the OHM market price is low. It remains separate from maximum LTV and any
future collateral haircut.

## Maximum LTV Precedent

Morpho defines liquidation LTV as the maximum debt percentage supported by collateral value, and
its governance-approved tiers include 86%. See Morpho's
[collateral and LTV definition](https://docs.morpho.org/developers/borrow/concepts/ltv/) and
[approved LLTV table](https://docs.morpho.org/learn/concepts/blue/#governance-approved-lltv--irm).
Burner Loans uses the same intuitive direction: a higher `maxLtvBps` permits more debt for the same
collateral. The launch value rounds the 86% precedent down to 85%, adding one percentage point of
conservatism and producing this market-value requirement:

```text
implied collateral-to-debt ratio = 1 / 85% = 117.6470588...%
```

This ratio is derived from `maxLtvBps`; it is not a separately configured limit.

## Why The Backing Multiplier Is 125%

At 100%, the backing branch permits a borrower to originate a position with collateral equal to the
liquid backing of its borrowed OHM before considering seizure deductions. At 125%, the protected
backing requirement is 25% higher. The protocol then uses the larger of that requirement and the
85% maximum-LTV requirement.

Keeper rewards are calculated separately. A third-party caller receives the minimum of the
configured 1%, the 100-token cap, and collateral remaining above the 125% backing requirement.
Protocol seizure callers receive no product reward.

## Worked Normal And Stress Cases

The examples use 100 OHM debt, $10.00 backing per OHM, an 85% maximum LTV, a 125% backing
multiplier, and $1.00 collateral unless stated otherwise. Their exact base-unit calculations are
covered by named tests in `BurnerLoansMath.t.sol`.

### Market And Backing Branches

| OHM market price | Debt market value | Market requirement | Backing requirement | Required collateral | Test                                                                          |
| ---------------- | ----------------- | ------------------ | ------------------- | ------------------- | ----------------------------------------------------------------------------- |
| $12.00           | $1,200.00         | $1,411.77          | $1,250.00           | $1,411.77           | `test_requiredCollateralUsd_whenMarketBranchDominates_usesMaximumLtv`         |
| $10.00           | $1,000.00         | $1,176.48          | $1,250.00           | $1,250.00           | `test_requiredCollateralUsd_whenBackingBranchDominates_usesBackingMultiplier` |

Displayed values round up to two decimal places. The tests assert the exact integer arithmetic.

### Collateral Depeg Stress

A boundary position has 1,250 collateral tokens.

| Collateral price | Collateral value | Health factor | Value versus backing | Outcome                       | Test                                                                          |
| ---------------- | ---------------- | ------------- | -------------------- | ----------------------------- | ----------------------------------------------------------------------------- |
| $0.95            | $1,187.50        | 0.95          | 118.75%              | Seizable                      | `test_launchStress_givenFivePercentCollateralDepeg_healthIsNinetyFivePercent` |
| $0.80            | $1,000.00        | 0.80          | 100%                 | Covers liquid backing exactly | `test_launchStress_givenTwentyPercentCollateralDepeg_coversBackingExactly`    |

A collateral value below $1,000.00 does not cover the liquid backing of the borrowed OHM.

### Keeper Reward Stress

| Seized collateral | Configured reward | Backing surplus | Keeper receives | Treasury receives | Test                                                                        |
| ----------------- | ----------------- | --------------- | --------------- | ----------------- | --------------------------------------------------------------------------- |
| $1,300.00         | $13.00            | $50.00          | $13.00          | $1,287.00         | `test_launchStress_givenRewardBelowBackingSurplus_paysConfiguredOnePercent` |
| $1,255.00         | $12.55            | $5.00           | $5.00           | $1,250.00         | `test_launchStress_givenRewardAboveBackingSurplus_preservesBackingFloor`    |

See [Burner Loans](./burner_loans.md#health-pricing-and-fees) for the general health, pricing,
backing, and fee mechanics.
