# Asset Configuration

The purpose of this file is to list the assets that need to be configured for the PRICEv2, TRSRY and SPPLY modules.

## PRICE Configuration

This table reflects the asset prices that need to be resolved. There will be a combination of assets in the treasury (see [TRSRY Configuration](#trsry-configuration)) and underlying assets.

| Asset              | Address                                      | Price feeds                                                                                                                                                                                                   | Strategy selector   | Store MA | Use MA |
| ------------------ | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------- | -------- | ------ |
| DAI                | `0x6b175474e89094c44da98b954eedeac495271d0f` | `ChainlinkPriceFeeds.getOneFeedPrice()` - `0xaed0c38402a5d19df6e4c03f4e2dced6e29c1ee9` <br /> `UniswapV3Price.getTokenTWAP()` - `0x5777d92f208679db4b9778590fa3cab3ac9e2168` (DAI/USDC UniV3 pool, liq: $95m) | `getAveragePrice()` | Yes      | Yes    |
| sDAI               | `0x83f20f44975d03b1b09e64809b757c47f942beea` | `ERC4626Price.getPriceFromUnderlying()`                                                                                                                                                                       | None                | No       | No     |
| wETH-OHM UniV3 POL | TBD - determined at deployment-time          | `BunniPrice.getBunniTokenPrice()` - will be configured by BunniManager                                                                                                                                        | None                | No       | No     |
| wETH               | `0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2` | `ChainlinkPriceFeeds.getOneFeedPrice()` - `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419`, `UniswapV3Price.getTokenTWAP()` - `0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640` (wETH/USDC UniV3 pool, liq: $150m)     | `getAveragePrice()` | Yes      | Yes    |
| veFXS              | `0xc8418af6358ffdda74e09ca9cc3fe03ca6adc5b0` | `ChainlinkPriceFeeds.getOneFeedPrice()` - `0x6ebc52c8c1089be9eb3945c4350b68b8e4c2233f`                                                                                                                        | None                | No       | No     |
| FXS                | `0x3432b6a60d23ca0dfca7761b7ab56459d9c964d0` | `ChainlinkPriceFeeds.getOneFeedPrice()` - `0x6ebc52c8c1089be9eb3945c4350b68b8e4c2233f`                                                                                                                        | None                | No       | No     |
| OHM                | `0x64aa3364f17a4d01c6f1751fd97c2bd3d7e7f1d5` | `UniswapV3Price.getTokenTWAP()` - POL address (could be non-TWAP too)                                                                                                                                         | None                | No       | No     |
| USDC               | `0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48` | `ChainlinkPriceFeeds.getOneFeedPrice()` - `0x8fffffd4afb6115b954bd326cbe7b4ba576818f6`                                                                                                                        | None                | Yes      | Yes    |

Notes:

-   This assumes that the UniV3 POL has been migrated using the BunniManager policy, as the value of the position cannot be determined otherwise
-   This ignores assets worth under $1 million (per asset). As of 2023-11-27, the aggregate value is $638,177, 0.34% of liquid backing and $0.038692 in terms of liquid backing/OHM.
-   The table reflects the assets that are currently in the protocol treasury, as well as any underlying tokens (e.g. FXS for veFXS, wETH for POL).
-   Ultimately, price resolution for all assets into USD will be reliant on Chainlink. DAI, wETH and USDC (which are the major base assets relying on Chainlink) have secondary price feeds (where possible) and moving averages enable to reduce the impact from the manipulation of price feeds.

## TRSRY Configuration

This table reflects the asset balances that need to be tracked.

| Asset              | Address                                      | Locations                                                                     | Categories                                 |
| ------------------ | -------------------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------ |
| DAI                | `0x6b175474e89094c44da98b954eedeac495271d0f` | `TRSRY` <br /> Cooler Clearinghouse(s) via Registry                           | liquid, stable, reserves                   |
| sDAI               | `0x83f20f44975d03b1b09e64809b757c47f942beea` | `TRSRY` <br /> Cooler Clearinghouse(s) via Registry                           | liquid, stable, reserves                   |
| wETH               | `0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2` | `TRSRY`                                                                       | liquid, volatile, strategic                |
| wETH-OHM UniV3 POL | TBD - determined at deploy-time              | `TRSRY` <br /> `BunniHub` (configured by BunniManager)                        | liquid, volatile, protocol-owned-liquidity |
| veFXS              | `0xc8418af6358ffdda74e09ca9cc3fe03ca6adc5b0` | `TRSRY` <br /> veFXS Allocator - `0xde7b85f52577b113181921a7aa8fc0c22e309475` | illiquid, volatile, strategic              |
| FXS                | `0x3432b6a60d23ca0dfca7761b7ab56459d9c964d0` | `TRSRY` <br /> veFXS Allocator - `0xde7b85f52577b113181921a7aa8fc0c22e309475` | liquid, volatile, strategic                |

Notes:

-   This assumes that the DAI deposited in the DSR has been migrated into sDAI
-   This assumes that the UniV3 POL has been migrated using the BunniManager policy, as the value of the position cannot be determined otherwise

## SPPLY Configuration

This table reflects the OHM supply categories and locations that need to be tracked.

| Description         | Category                               | Locations                                    | Submodule                                |
| ------------------- | -------------------------------------- | -------------------------------------------- | ---------------------------------------- |
| wETH-OHM UniV3 POL  | `protocol-owned-liquidity`             | None                                         | BunniSupply (configured by BunniManager) |
| Manual Offset       | `protocol-owned-treasury`              | None                                         | MigrationOffsetSupply                    |
| DAO Working Capital | `dao`                                  | `0xf65a665d650b5de224f46d729e2bd0885eea9da5` | None                                     |
| Treasury MS         | `protocol-owned-treasury`              | `0x245cc372c84b3645bf0ffe6538620b04a217988b` | None                                     |
| Bricked Assets      | `protocol-owned-treasury`              | sOHM V2, gOHM, OHM                           | None                                     |
| BLV - Lido          | Category pre-configured with submodule | `0xafe729d57d2cc58978c2e01b4ec39c47fb7c4b23` | BLVaultSupply                            |
| BLV - LUSD          | Category pre-configured with submodule | `0xf451c45c7a26e2248a0ea02382579eb4858cada1` | BLVaultSupply                            |

Notes:

-   This assumes that burnable OHM has been burnt and no longer needs to be accounted for.
    -   Inverse Bond Depository - `0xba42be149e5260eba4b82418a6306f55d532ea47`
    -   Bond Manager - `0xf577c77ee3578c7f216327f41b5d7221ead2b2a3`
    -   Bond Depository - `0x9025046c6fb25fb39e720d97a8fd881ed69a1ef6`
-   Bricket assets refers to tokens that have been incorrectly deposited into token contracts and are no longer accessible, e.g. [sOHM in the sOHM contract](https://etherscan.io/address/0x04f2694c8fcee23e8fd0dfea1d4f5bb8c352111f)
