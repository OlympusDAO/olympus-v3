# Olympus Bophades

Use yarn build to refresh deps.

Set up a foundry config in foundry.toml.

## SRC Directory Structure

```ml
├─ external - "External contracts needed for core functionality"
├─ interfaces - "Standard interfaces"
├─ libraries - "Libraries"
├─ modules - "Default framework modules"
│  ├─ AUTHR
│  ├─ INSTR
│  ├─ MINTR
│  ├─ PRICE
│  ├─ RANGE
│  ├─ TRSRY
├─ policies - "Default framework policies"
├─ test - "General test utilities and mocks/larps"
```

## Deployments

### Goerli Testnet

-   Kernel - [0xDb7cf68154bd422dF5196D90285ceA057786b4c3](https://goerli.etherscan.io/address/0xDb7cf68154bd422dF5196D90285ceA057786b4c3)

#### Modules

-   TRSRY - [0xD8C59cFe5afbDB83D904E56D379028a2f6A07a2D](https://goerli.etherscan.io/address/0xD8C59cFe5afbDB83D904E56D379028a2f6A07a2D)
-   MINTR - [0xa192fFBF73858831a137DD098a706139Ca96AbD5](https://goerli.etherscan.io/address/0xa192fFBF73858831a137DD098a706139Ca96AbD5)
-   PRICE - [0x9cdb21200774E6C94B71653da213DcE6c1a31F72](https://goerli.etherscan.io/address/0x9cdb21200774E6C94B71653da213DcE6c1a31F72)
-   RANGE - [0x446f06f8Df7d5f627B073c6349b948B95c1f9185](https://goerli.etherscan.io/address/0x446f06f8Df7d5f627B073c6349b948B95c1f9185)
-   ROLES - [0xe9a9d80CE3eE32FFf7279dce4c2962eC8098f71B](https://goerli.etherscan.io/address/0xe9a9d80CE3eE32FFf7279dce4c2962eC8098f71B)

#### Policies

-   BondCallback - [0xC1545804Fb804fdC7756e8e40c91B7581b2a2856](https://goerli.etherscan.io/address/0xC1545804Fb804fdC7756e8e40c91B7581b2a2856)
-   Heart - [0xf3B2Df0F05C344DAc837e104fd20e77168DAc556](https://goerli.etherscan.io/address/0xf3B2Df0F05C344DAc837e104fd20e77168DAc556)
-   Operator - [0x8C9Dc385790ee7a20289B7ED98CdaC499D3aef9D](https://goerli.etherscan.io/address/0x8C9Dc385790ee7a20289B7ED98CdaC499D3aef9D)
-   PriceConfig - [0x58f06599748155bCd7aE2d1e28e09A5a841a0D82](https://goerli.etherscan.io/address/0x58f06599748155bCd7aE2d1e28e09A5a841a0D82)
-   TreasuryCustodian - [0x3DAE418f8B6382b3d3d0cb9008924BA83D2e0E87](https://goerli.etherscan.io/address/0x3DAE418f8B6382b3d3d0cb9008924BA83D2e0E87)
-   Distributor - [0x2716a1451BDE2B011f0D10ad6599e411d54Ec491](https://goerli.etherscan.io/address/0x2716a1451BDE2B011f0D10ad6599e411d54Ec491)
-   RolesAdmin - [0x54FfCA586cD1B01E96a5682DF93a55d7Ef91EFF0](https://goerli.etherscan.io/address/0x54FfCA586cD1B01E96a5682DF93a55d7Ef91EFF0)
-   Emergency - [0x196a59fB453da942f062Be4407D923129c759435](https://goerli.etherscan.io/address/0x196a59fB453da942f062Be4407D923129c759435)
-   Faucet (Testnet only) - [0xA247156a39169c0FAFf979F57361CC734e82e3d0](https://goerli.etherscan.io/address/0xA247156a39169c0FAFf979F57361CC734e82e3d0)

#### Dependencies

-   OHM Token - [0x0595328847AF962F951a4f8F8eE9A3Bf261e4f6b](https://goerli.etherscan.io/address/0x0595328847af962f951a4f8f8ee9a3bf261e4f6b)
-   DAI Token - [0x41e38e70a36150D08A8c97aEC194321b5eB545A5](https://goerli.etherscan.io/address/0x41e38e70a36150d08a8c97aec194321b5eb545a5)
-   OHM-DAI Balancer LP Pool - [0xd8833594420dB3D6589c1098dbDd073f52419Dba](https://goerli.etherscan.io/address/0xd8833594420dB3D6589c1098dbDd073f52419Dba)
-   WETH Token (for keeper rewards) - [0x0Bb7509324cE409F7bbC4b701f932eAca9736AB7](https://goerli.etherscan.io/address/0x0bb7509324ce409f7bbc4b701f932eaca9736ab7)
-   Mock OHM/ETH Price Feed - [0x022710a589C9796dce59A0C52cA4E36f0a5e991A](https://goerli.etherscan.io/address/0x022710a589c9796dce59a0c52ca4e36f0a5e991a)
-   Mock DAI/ETH Price Feed - [0xdC8E4eD326cFb730a759312B6b1727C6Ef9ca233](https://goerli.etherscan.io/address/0xdc8e4ed326cfb730a759312b6b1727c6ef9ca233)
-   Bond Auctioneer - [0x007F7A1cb838A872515c8ebd16bE4b14Ef43a222](https://goerli.etherscan.io/address/0x007F7A1cb838A872515c8ebd16bE4b14Ef43a222)
-   Bond Teller - [0x007F7735baF391e207E3aA380bb53c4Bd9a5Fed6](https://goerli.etherscan.io/address/0x007F7735baF391e207E3aA380bb53c4Bd9a5Fed6)
-   Bond Aggregator - [0x007A66A2a13415DB3613C1a4dd1C942A285902d1](https://goerli.etherscan.io/address/0x007A66A2a13415DB3613C1a4dd1C942A285902d1)

#### Privileged Testnet Accounts (Multi-sigs)

-   Executor - 0x84C0C005cF574D0e5C602EA7b366aE9c707381E0
-   Guardian - 0x84C0C005cF574D0e5C602EA7b366aE9c707381E0
-   Policy - 0x3dC18017cf8d8F4219dB7A8B93315fEC2d15B8a7
-   Emergency - 0x3dC18017cf8d8F4219dB7A8B93315fEC2d15B8a7
