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

### Mainnet

-   Kernel - [0x2286d7f9639e8158FaD1169e76d1FbC38247f54b](https://etherscan.io/address/0x2286d7f9639e8158FaD1169e76d1FbC38247f54b)

#### Modules

-   TRSRY - [0xa8687A15D4BE32CC8F0a8a7B9704a4C3993D9613](https://etherscan.io/address/0xa8687A15D4BE32CC8F0a8a7B9704a4C3993D9613)
-   MINTR - [0xa90bFe53217da78D900749eb6Ef513ee5b6a491e](https://etherscan.io/address/0xa90bFe53217da78D900749eb6Ef513ee5b6a491e)
-   PRICE - [0x9Ded6A8B099c57BBEb9F81b76400a5a9C63a6880](https://etherscan.io/address/0x9Ded6A8B099c57BBEb9F81b76400a5a9C63a6880)
-   RANGE - [0xb212D9584cfc56EFf1117F412Fe0bBdc53673954](https://etherscan.io/address/0xb212D9584cfc56EFf1117F412Fe0bBdc53673954)
-   ROLES - [0x6CAfd730Dc199Df73C16420C4fCAb18E3afbfA59](https://etherscan.io/address/0x6CAfd730Dc199Df73C16420C4fCAb18E3afbfA59)

#### Policies

-   BondCallback - [0xbf2B6E99B0E8D4c96b946c182132f5752eAa55C6](https://etherscan.io/address/0xbf2B6E99B0E8D4c96b946c182132f5752eAa55C6)
-   Operator - [0xbb47C3FFf4eF85703907d3ffca30de278b85df3f](https://etherscan.io/address/0xbb47C3FFf4eF85703907d3ffca30de278b85df3f)
-   Heart - [0xeaf46BD21dd9b263F28EEd7260a269fFba9ace6E](https://etherscan.io/address/0xeaf46BD21dd9b263F28EEd7260a269fFba9ace6E)
-   PriceConfig - [0x3019ff96bd8308D1B66846b795E0AeeFbDf14ba5](https://etherscan.io/address/0x3019ff96bd8308D1B66846b795E0AeeFbDf14ba5)
-   RolesAdmin - [0xb216d714d91eeC4F7120a732c11428857C659eC8](https://etherscan.io/address/0xb216d714d91eeC4F7120a732c11428857C659eC8)
-   TreasuryCustodian - [0xC9518AC915e46D707585116451Dc19c164513Ccf](https://etherscan.io/address/0xC9518AC915e46D707585116451Dc19c164513Ccf)
-   Distributor - [0x27e606fdb5C922F8213dC588A434BF7583697866](https://etherscan.io/address/0x27e606fdb5C922F8213dC588A434BF7583697866)
-   Emergency - [0x9229b0b6FA4A58D67Eb465567DaA2c6A34714A75](https://etherscan.io/address/0x9229b0b6FA4A58D67Eb465567DaA2c6A34714A75)

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
