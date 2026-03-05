# PRICE v1.2 Configuration

This file contains detailed configuration information for the PRICE v1.2 module upgrade. It should help auditors in assessing risks related to price feed configuration.

## Overview

PRICE v1.2 configures 4 assets with multi-feed price resolution:

| Asset | Address                                                                                | Feeds   | Strategy                 | Store MA | Use MA | MA Duration     |
| ----- | -------------------------------------------------------------------------------------- | ------- | ------------------------ | -------- | ------ | --------------- |
| USDS  | [0xdC0...84F](https://etherscan.io/address/0xdC035D45d973E3EC169d2276DDab16f1e407384F) | 3 feeds | Deviation filtering (1%) | No       | No     | 0               |
| sUSDS | [0xa39...fbD](https://etherscan.io/address/0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD) | 1 feed  | None                     | No       | No     | 0               |
| wETH  | [0xc02...cc2](https://etherscan.io/address/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2) | 4 feeds | Deviation filtering (2%) | No       | No     | 0               |
| OHM   | [0x64a...1d5](https://etherscan.io/address/0x64aa3364f17a4d01c6f1751fd97c2bd3d7e7f1d5) | 2 feeds | Average (strict mode)    | Yes      | No     | 604800 (7 days) |

## Asset Configuration Details

### USDS

**Price Feeds:**

| Feed               | Type      | Address/Feed ID                                                                        | Update Threshold      | Additional Params               |
| ------------------ | --------- | -------------------------------------------------------------------------------------- | --------------------- | ------------------------------- |
| Chainlink USDS-USD | Chainlink | [0xfF4...19b](https://etherscan.io/address/0xfF30586cD0F29eD462364C7e81375FC0C71219b1) | 86,400 sec (24 hours) | -                               |
| Chainlink DAI-USD  | Chainlink | [0xAed...eE9](https://etherscan.io/address/0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9) | 86,400 sec (24 hours) | -                               |
| Pyth USDS-USD      | Pyth      | `0x5c50e4bb79...c66e83a5` (bytes32)                                                    | 86,400 sec (24 hours) | Max confidence: 0.01e18 ($0.01) |

**Strategy:**

- Function: `SimplePriceFeedStrategy.getAveragePriceExcludingDeviations()`
- Deviation threshold: 1% (100 basis points)
- Strict mode: Enabled (requires 2+ valid values)

**Moving Average:** Not stored, not used

**Rationale:** USDS pricing uses 3 independent sources with tight deviation filtering (1%) to detect any manipulation or misconfiguration. DAI-USD provides redundancy since USDS is a DAI variant.

### sUSDS

**Price Feeds:**

| Feed               | Type    | Address/Feed ID   | Update Threshold | Additional Params          |
| ------------------ | ------- | ----------------- | ---------------- | -------------------------- |
| ERC4626 Conversion | ERC4626 | Derived from USDS | N/A              | Uses underlying USDS price |

**Strategy:** None (single feed, no aggregation needed)

**Moving Average:** Not stored, not used

**Rationale:** sUSDS is an ERC4626 wrapper around USDS. The price is derived from the underlying USDS price multiplied by the conversion rate (`convertToAssets()`).

### wETH

**Price Feeds:**

| Feed              | Type              | Address/Feed ID                                                                                                                                                                  | Update Threshold   | Additional Params                |
| ----------------- | ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------ | -------------------------------- |
| Chainlink ETH-USD | Chainlink         | [0x5f4...5419](https://etherscan.io/address/0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419)                                                                                          | 3,600 sec (1 hour) | -                                |
| RedStone ETH-USD  | RedStone          | [0x67F...6Dc4](https://etherscan.io/address/0x67F6838e58859d612E4ddF04dA396d6DABB66Dc4)                                                                                          | 3,600 sec (1 hour) | -                                |
| Pyth ETH-USD      | Pyth              | `0xff61491a9...002a84b5` (bytes32)                                                                                                                                               | 3,600 sec (1 hour) | Max confidence: 10e18 ($10)      |
| ETH-BTC × BTC-USD | Chainlink derived | [0xAc5...4e99](https://etherscan.io/address/0xAc559F25B1619171CbC396a50854A3240b6A4e99) × [0xF40...88c](https://etherscan.io/address/0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c) | 3,600 sec (1 hour) | Function: `getTwoFeedPriceMul()` |

**Strategy:**

- Function: `SimplePriceFeedStrategy.getAveragePriceExcludingDeviations()`
- Deviation threshold: 2% (200 basis points)
- Strict mode: Enabled (requires 2+ valid values)

**Moving Average:** Not stored, not used

**Rationale:** wETH pricing uses 4 independent sources with moderate deviation filtering (2%) to balance fault tolerance with price responsiveness. The derived ETH-BTC × BTC-USD feed provides a 4th independent path using different Chainlink aggregators.

### OHM

**Price Feeds:**

| Feed           | Type       | Address/Feed ID                                                                          | Observation Window | Additional Params |
| -------------- | ---------- | ---------------------------------------------------------------------------------------- | ------------------ | ----------------- |
| OHM/WETH TWAP  | Uniswap V3 | [0x8805...8598](https://etherscan.io/address/0x88051b0eea095007d3bef21ab287be961f3d8598) | 1,800 sec (30 min) | 0.3% fee pool     |
| OHM/sUSDS TWAP | Uniswap V3 | [0x0858...a755](https://etherscan.io/address/0x0858e2b0f9d75f7300b38d64482ac2c8df06a755) | 1,800 sec (30 min) | 1% fee pool       |

**Strategy:**

- Function: `SimplePriceFeedStrategy.getAveragePrice()`
- Strict mode: Enabled (requires 2 values)

**Moving Average:**

- Stored: Yes (21 observations)
- Used: No (stored for future use only)
- Duration: 604,800 seconds (7 days)
- Observation frequency: 28,800 seconds (8 hours)
- Initial value: Populated with 21 observations at deployment time

**Rationale:** OHM pricing uses 2 completely independent paths (wETH and sUSDS) to reduce the impact from manipulation of any single price feed. The 30-minute TWAP window reduces manipulation risk from flash attacks. Moving average is stored but not used in price calculation (reserved for future enhancements).

## Price Feed Parameters

### Update Threshold

The **update threshold** is the maximum number of seconds that can elapse since the last price feed update before the price is considered stale.

| Asset      | Update Threshold      |
| ---------- | --------------------- |
| USDS feeds | 86,400 sec (24 hours) |
| wETH feeds | 3,600 sec (1 hour)    |

**Behavior:** If a feed's last update is older than this threshold, the feed returns zero and is excluded from price calculation.

### Observation Window

The **observation window** is used only for Uniswap V3 price feeds to calculate a Time-Weighted Average Price (TWAP).

| Asset     | Observation Window |
| --------- | ------------------ |
| OHM/WETH  | 1,800 sec (30 min) |
| OHM/sUSDS | 1,800 sec (30 min) |

**Behavior:** TWAP is calculated by averaging price observations within the window. A longer window = more manipulation resistance but slower price updates.

### Max Confidence Interval (Pyth Only)

The **max confidence interval** sets the maximum acceptable confidence interval for a Pyth price.

| Asset    | Max Confidence  |
| -------- | --------------- |
| USDS-USD | 0.01e18 ($0.01) |
| ETH-USD  | 10e18 ($10)     |

**Behavior:** If `priceData.conf > maxConfidence`, the feed reverts with `Pyth_FeedConfidenceExcessive`. This prevents using prices with high uncertainty.

## Configuration Implementation

The complete configuration implementation is in the batch script:

- **[ConfigurePriceV1_2.sol](../../src/scripts/ops/batches/ConfigurePriceV1_2.sol)** - PRICE configuration batch script

This script:

1. Upgrades PRICE module to v1.2
2. Activates PriceConfigv2 policy
3. Installs 5 submodules (ChainlinkPriceFeeds, PythPriceFeeds, UniswapV3Price, ERC4626Price, SimplePriceFeedStrategy)
4. Configures 4 assets (USDS, sUSDS, wETH, OHM)
5. Validates prices are within reasonable bounds after batch execution

## Deployment and Rollout

For the complete deployment process, including rollout steps and activation procedures, see:

- **[PRICE v1 → v1.2 Upgrade Rollout](../../documentation/price_v1_upgrade.md)** - Complete deployment and configuration process

## Pyth Price Update Requirements

Pyth price feeds require regular updates to remain valid. The [pyth-price-pusher](https://github.com/OlympusDAO/pyth-price-pusher) tool manages automated updates.

**Feed IDs:**

- USDS-USD: `0x5c50e4bb799...56c66e83a5`
- ETH-USD: `0xff61491a9...2a84b5`

**Update frequency:** Recommended every 30-60 seconds for best security

**Failure mode:** If Pyth prices are not updated within the `updateThreshold` period, the feed returns zero and is excluded. If strict mode requires 2+ values and insufficient feeds remain, price resolution fails.

**Note:** For Oracle Factory policies (Chainlink, Morpho, ERC7726) that enable external protocol integration, see the [README.md](./README.md#oracle-architecture-for-external-protocols) section for architecture and sequence diagrams.

## Price Validation Bounds

The configuration script includes price validation bounds to catch misconfigured feeds:

| Asset | Min Price | Max Price |
| ----- | --------- | --------- |
| USDS  | 0.99e18   | 1.01e18   |
| sUSDS | 1.06e18   | 1.10e18   |
| wETH  | 1,500e18  | 2,100e18  |
| OHM   | 17e18     | 22e18     |

**Validation:** Called after batch execution to verify prices are within reasonable bounds. If any price is out of range, the batch fails.

## Moving Average Initialization

OHM moving average is pre-populated with 21 observations at deployment:

**Parameters:**

- Duration: 604,800 seconds (7 days)
- Observation frequency: 28,800 seconds (8 hours)
- Number of observations: 21
- Initial value: Current OHM price (from args file)

**Storage:** Observations stored in a ring buffer in PRICE module

**Update:** Called via `PRICE.storePrice()` every 8 hours

## Risk Considerations

### Price Feed Failure Modes

1. **Single feed failure:** Excluded from calculation, remaining feeds provide price
2. **Multiple feed failure:** If strict mode requires 2+ values and <2 valid, price resolution fails
3. **All feed failure:** PRICE reverts

### Protocol Impact

If PRICE fails to resolve prices:

- **Heart:** Cannot beat (requires OHM price for range calculations)
- **Operator:** Cannot perform market operations (requires OHM price)
- **YRF/EM:** Cannot execute buy/sell (requires OHM price)

### Mitigations

1. **Redundant feeds:** 3-4 independent sources per asset
2. **Strict mode:** Ensures sufficient valid data before accepting price
3. **Deviation filtering:** Excludes outliers or manipulated feeds
4. **Automated Pyth updates:** pyth-price-pusher tool ensures Pyth feeds remain current
5. **Price validation:** Bounds checking in deployment script catches misconfigurations

## Additional Configuration Files

- [PRICE Configuration](../../documentation/price.md) - Complete price configuration documentation
- [PRICE v1 → v1.2 Upgrade Rollout](../../documentation/price_v1_upgrade.md) - Deployment and configuration process
- [RFC: Improving Resilience of Price Feeds](../../documentation/rfc/rfc-improving-resilience-of-price-feeds.md) - Rationale and specifications
- [ConfigurePriceV1_2.sol](../../src/scripts/ops/batches/ConfigurePriceV1_2.sol) - Batch script implementation
