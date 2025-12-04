# PRICE Configuration

## Justification

The Olympus protocol currently relies on two price feeds, Chainlink OHM-ETH and Chainlink ETH-USD, in order to determine the price of OHM. If there were to be any mis-configuration or mis-reporting in either of those price feeds, the protocol’s automated operations (YRF and EM) could buy or sell OHM in a market that does not support it.

## Objective

Replace the existing PRICE v1 module with a backwards-compatible PRICE v2 module that can support multiple price feeds per asset, and strategies to resolve the price from the multiple price feeds. This will increase resilience in adverse conditions.

## Assets

| Asset | Address   | Price Feeds   | Strategy  | Store MA | Use MA | MA Duration   |
| ----- | --------- | ------------- | --------- | -------- | ------ | ------------- |
| USDS  | [0xdC0...84F](https://etherscan.io/address/0xdC035D45d973E3EC169d2276DDab16f1e407384F) | [Chainlink DAI-USD](https://etherscan.io/address/0xaed0c38402a5d19df6e4c03f4e2dced6e29c1ee9) <br />[Chainlink USDS-USD](https://etherscan.io/address/0xfF30586cD0F29eD462364C7e81375FC0C71219b1) | `getAveragePrice()` | No      | No    | 0 |
| sUSDS | [0xa39...fbD](https://etherscan.io/address/0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD) | ERC4626 Submodule | None         | No    | No     | 0 |
| wETH  | [0xc02...cc2](https://etherscan.io/address/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2) | [Chainlink ETH-USD](https://etherscan.io/address/0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419)<br /> [RedStone ETH-USD](https://etherscan.io/address/0x67F6838e58859d612E4ddF04dA396d6DABB66Dc4)   | `getAveragePrice()` | No      | No    | 0 |
| OHM   | [0x64a...1d5](https://etherscan.io/address/0x64aa3364f17a4d01c6f1751fd97c2bd3d7e7f1d5) | [Uniswap V3 OHM/WETH](https://etherscan.io/address/0x88051b0eea095007d3bef21ab287be961f3d8598) <br /> [Uniswap V3 OHM/sUSDS](https://etherscan.io/address/0x0858e2b0f9d75f7300b38d64482ac2c8df06a755) | `getAveragePrice()`      | No       | No     | 0 |

- Ultimately, price resolution for all assets into USD will be reliant on Chainlink or Redstone oracles.
- The price of OHM will be determined by completely separate paths - USDS and wETH, to reduce the impact from the manipulation of price feeds.

### wETH Price Resolution

```mermaid
sequenceDiagram
    participant User
    participant WETH
    participant CL_ETH as Chainlink ETH-USD
    participant RS_ETH as RedStone ETH-USD

    User->>WETH: getPrice(wETH)

    Note over WETH: Strategy: getAveragePrice

    par Chainlink ETH-USD Path
        WETH->>CL_ETH: latestRoundData()
        CL_ETH-->>WETH: ETH-USD price
    and RedStone ETH-USD Path
        WETH->>RS_ETH: latestRoundData()
        RS_ETH-->>WETH: ETH-USD price
    end

    Note over WETH: Average: (CL_ETH + RS_ETH) / 2
    WETH-->>User: wETH price
```

### USDS Price Resolution

```mermaid
sequenceDiagram
    participant User
    participant USDS
    participant CL_DAI as Chainlink DAI-USD
    participant CL_USDS as Chainlink USDS-USD

    User->>USDS: getPrice(USDS)

    Note over USDS: Strategy: getAveragePrice

    par Chainlink DAI-USD Path
        USDS->>CL_DAI: latestRoundData()
        CL_DAI-->>USDS: DAI-USD price
    and Chainlink USDS-USD Path
        USDS->>CL_USDS: latestRoundData()
        CL_USDS-->>USDS: USDS-USD price
    end

    Note over USDS: Average: (CL_DAI + CL_USDS) / 2
    USDS-->>User: USDS price
```

### OHM Price Resolution

```mermaid
sequenceDiagram
    participant User
    participant OHM
    participant OHM_WETH_Pool as OHM/wETH Pool
    participant OHM_SUSDS_Pool as OHM/sUSDS Pool
    participant WETH
    participant CL_ETH as Chainlink ETH-USD
    participant RS_ETH as RedStone ETH-USD
    participant SUSDS
    participant ERC4626 as ERC4626 Submodule
    participant USDS
    participant CL_DAI as Chainlink DAI-USD
    participant CL_USDS as Chainlink USDS-USD

    User->>OHM: getPrice(OHM)

    Note over OHM: Strategy: getAveragePrice

    par OHM/wETH Path
        OHM->>OHM_WETH_Pool: getPrice(OHM/wETH)
        OHM_WETH_Pool->>WETH: getPrice(wETH)

        Note over WETH: Strategy: getAveragePrice

        par Chainlink ETH-USD Path
            WETH->>CL_ETH: latestRoundData()
            CL_ETH-->>WETH: ETH-USD price
        and RedStone ETH-USD Path
            WETH->>RS_ETH: latestRoundData()
            RS_ETH-->>WETH: ETH-USD price
        end

        Note over WETH: Average: (CL_ETH + RS_ETH) / 2
        WETH-->>OHM_WETH_Pool: wETH price
        OHM_WETH_Pool-->>OHM: OHM/wETH price
    and OHM/sUSDS Path
        OHM->>OHM_SUSDS_Pool: getPrice(OHM/sUSDS)
        OHM_SUSDS_Pool->>SUSDS: getPrice(sUSDS)

        Note over SUSDS: Strategy: ERC4626

        SUSDS->>ERC4626: getPriceFromUnderlying(sUSDS)
        ERC4626->>USDS: getPrice(USDS)

        Note over USDS: Strategy: getAveragePrice

        par Chainlink DAI-USD Path
            USDS->>CL_DAI: latestRoundData()
            CL_DAI-->>USDS: DAI-USD price
        and Chainlink USDS-USD Path
            USDS->>CL_USDS: latestRoundData()
            CL_USDS-->>USDS: USDS-USD price
        end

        Note over USDS: Average: (CL_DAI + CL_USDS) / 2
        USDS-->>ERC4626: USDS price
        Note over ERC4626: Calculate: USDS price × conversion rate
        ERC4626-->>SUSDS: sUSDS price
        SUSDS-->>OHM_SUSDS_Pool: sUSDS price
        OHM_SUSDS_Pool-->>OHM: OHM/sUSDS price
    end

    Note over OHM: Average: (OHM/wETH + OHM/sUSDS) / 2
    OHM-->>User: OHM price
```
