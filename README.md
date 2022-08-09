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

-   Kernel - [0x773fa2A1399A413a878ff8f0266B9b5E9d0068d6](https://goerli.etherscan.io/address/0x773fa2A1399A413a878ff8f0266B9b5E9d0068d6)

#### Modules

-   TRSRY - [0x76C000C37E916a8241BF5f3f37cfF2324D528eF5](https://goerli.etherscan.io/address/0x76c000c37e916a8241bf5f3f37cff2324d528ef5)
-   MINTR - [0x5a2bD88E0F4a99Bd7415f9a5587f4F60860025ee](https://goerli.etherscan.io/address/0x5a2bd88e0f4a99bd7415f9a5587f4f60860025ee)
-   PRICE - [0xB474ea1f90A01403505B8376463e15d20F113a33](https://goerli.etherscan.io/address/0xb474ea1f90a01403505b8376463e15d20f113a33)
-   RANGE - [0x6eeeEa308BfA538e88c9CC7c037143EEb9479A4E](https://goerli.etherscan.io/address/0x6eeeea308bfa538e88c9cc7c037143eeb9479a4e)
-   INSTR - [0x8754EF3C5875AE26db83f425241f8B20Df825Bf4](https://goerli.etherscan.io/address/0x8754EF3C5875AE26db83f425241f8B20Df825Bf4)
-   VOTES - [0x6dff42cd22a4c6dae0efb7a6f0fce704ebb9430c](https://goerli.etherscan.io/address/0x6dff42cd22a4c6dae0efb7a6f0fce704ebb9430c)

#### Policies

-   BondCallback - [0xdff3e45D4BE6B354384D770Fd63DDF90eA788d13](https://goerli.etherscan.io/address/0xdff3e45D4BE6B354384D770Fd63DDF90eA788d13)
-   Heart - [0x015aD76f273011829B951eFe16A0477D06e8c40F](https://goerli.etherscan.io/address/0x015aD76f273011829B951eFe16A0477D06e8c40F)
-   Operator - [0x532AC8804b233846645C1Cd53D3005604F5eC1c3](https://goerli.etherscan.io/address/0x532ac8804b233846645c1cd53d3005604f5ec1c3)
-   PriceConfig - [0x76FBaD8323f47e87c1646B70f2F53857aAF11D24](https://goerli.etherscan.io/address/0x76fbad8323f47e87c1646b70f2f53857aaf11d24)
-   Governance - [0x22cf79623513F39c8FA08C3ccC9B68c45a9E8623](https://goerli.etherscan.io/address/0x22cf79623513f39c8fa08c3ccc9b68c45a9e8623)
-   VoterRegistration - [0xbfE57606e7fc2d900CEDAaAeae1922E4293e64E1](https://goerli.etherscan.io/address/0xbfE57606e7fc2d900CEDAaAeae1922E4293e64E1)
-   Faucet (Testnet only) - [0xA247156a39169c0FAFf979F57361CC734e82e3d0](https://goerli.etherscan.io/address/0xA247156a39169c0FAFf979F57361CC734e82e3d0)

#### Dependencies

-   OHM Token - [0x0595328847AF962F951a4f8F8eE9A3Bf261e4f6b](https://goerli.etherscan.io/address/0x0595328847af962f951a4f8f8ee9a3bf261e4f6b)
-   DAI Token - [0x41e38e70a36150D08A8c97aEC194321b5eB545A5](https://goerli.etherscan.io/address/0x41e38e70a36150d08a8c97aec194321b5eb545a5)
-   WETH Token (for keeper rewards) - [0x0Bb7509324cE409F7bbC4b701f932eAca9736AB7](https://goerli.etherscan.io/address/0x0bb7509324ce409f7bbc4b701f932eaca9736ab7)
-   Mock OHM/ETH Price Feed - [0x022710a589C9796dce59A0C52cA4E36f0a5e991A](https://goerli.etherscan.io/address/0x022710a589c9796dce59a0c52ca4e36f0a5e991a)
-   Mock DAI/ETH Price Feed - [0xdC8E4eD326cFb730a759312B6b1727C6Ef9ca233](https://goerli.etherscan.io/address/0xdc8e4ed326cfb730a759312b6b1727c6ef9ca233)
-   Bond Auctioneer - [0xaE73A94b94F6E7aca37f4c79C4b865F1AF06A68b](https://goerli.etherscan.io/address/0xae73a94b94f6e7aca37f4c79c4b865f1af06a68b)
-   Bond Teller - [0x36211a11f2DaC433Ae34Be898b173942b334dBD5](https://goerli.etherscan.io/address/0x36211a11f2dac433ae34be898b173942b334dbd5)
-   Bond Aggregator - [0xB4860B2c12C6B894B64471dFb5a631ff569e220e](https://goerli.etherscan.io/address/0xb4860b2c12c6b894b64471dfb5a631ff569e220e)

#### Privileged Testnet Accounts

-   Executor - 0x83D0f479732CC605225263F1AB7016309475aDd9 (PK: 71270e81b91f27d411b9c0cc7d75e2cc5c50df28a0a01e0fd7b432bff5a64ffe)
-   Guardian - 0x19518E4D4E542f4b0Fc27366C23FaC7a0bA491Da (PK: 0882aadfaa5053e58924f45a7c68bc5f96c5260dfffc8eac20df816b968c2003)
-   Policy - 0x2694C41588A5C92a0dcddBBB778fb18c5cE16D1D (PK: 2a944c921eb69bd6f1ecc289179a37a91d794d32928c8cd77e43915919933e56)
