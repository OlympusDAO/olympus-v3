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

- Kernel - [0x64665B0429B21274d938Ed345e4520D1f5ABb9e7](https://goerli.etherscan.io/address/0x64665b0429b21274d938ed345e4520d1f5abb9e7)

#### Modules

- AUTHR - [0x247Bbb6aa0549C4F8F69aab6668e65fD548f0616](https://goerli.etherscan.io/address/0x247bbb6aa0549c4f8f69aab6668e65fd548f0616)
- TRSRY - [0x2544bF628804F13d7505E5874233e87308dC4dD2](https://goerli.etherscan.io/address/0x2544bf628804f13d7505e5874233e87308dc4dd2)
- MINTR - [0x578114a3686b305901B548cb11EefA82B404Ce39](https://goerli.etherscan.io/address/0x578114a3686b305901b548cb11eefa82b404ce39)
- PRICE - [0x8f17Fc892177219a6912d55c0521D79b83BE271e](https://goerli.etherscan.io/address/0x8f17fc892177219a6912d55c0521d79b83be271e)
- RANGE - [0x47a22bd734885baE7E2e153E98e7137b0B96bEBD](https://goerli.etherscan.io/address/0x47a22bd734885bae7e2e153e98e7137b0b96bebd)
- INSTR - [0xeeB45a384ced4097Ad369d48590AeD8DDBC11257](https://goerli.etherscan.io/address/0xeeb45a384ced4097ad369d48590aed8ddbc11257)
- VOTES - [0xA7dBfcFE09ACCf66B56Fe05841618177AE188c5b](https://goerli.etherscan.io/address/0xa7dbfcfe09accf66b56fe05841618177ae188c5b)

#### Policies

- BondCallback - [0x764E6578738E2606DBF3Be47746562F99380905c](https://goerli.etherscan.io/address/0x764e6578738e2606dbf3be47746562f99380905c)
- Heart - [0xcBdD34371f0404e96eEB59d8470e507EAbA961Aa](https://goerli.etherscan.io/address/0xcbdd34371f0404e96eeb59d8470e507eaba961aa)
- Operator - [0x0bFFdE707B76Abe13f77f52f6E359c846AE0680d](https://goerli.etherscan.io/address/0x0bffde707b76abe13f77f52f6e359c846ae0680d)
- PriceConfig - [0xA938A067e5008ec2f76557ad1AB100a4CD7Dfde2](https://goerli.etherscan.io/address/0xa938a067e5008ec2f76557ad1ab100a4cd7dfde2)
- Governance - [0xFEc5b1b96Ec2dA1494F5ad3D6E141Ce401c6C2D5](https://goerli.etherscan.io/address/0xfec5b1b96ec2da1494f5ad3d6e141ce401c6c2d5)
- VoterRegistration - [0x5d7221dA0cF85dEC1d5bC26BeE803C53B6B87355](https://goerli.etherscan.io/address/0x5d7221da0cf85dec1d5bc26bee803c53b6b87355)
- Auth Giver (Testnet Only) - [0x3714fDFc3b6918923e5b2AbAe0fcD74376Be45fc](https://goerli.etherscan.io/address/0x3714fdfc3b6918923e5b2abae0fcd74376be45fc)

#### Dependencies

- OHM Token - [0x0595328847AF962F951a4f8F8eE9A3Bf261e4f6b](https://goerli.etherscan.io/address/0x0595328847af962f951a4f8f8ee9a3bf261e4f6b)
- DAI Token - [0x41e38e70a36150D08A8c97aEC194321b5eB545A5](https://goerli.etherscan.io/address/0x41e38e70a36150d08a8c97aec194321b5eb545a5)
- WETH Token (for keeper rewards) - [0x0Bb7509324cE409F7bbC4b701f932eAca9736AB7](https://goerli.etherscan.io/address/0x0bb7509324ce409f7bbc4b701f932eaca9736ab7)
- Mock OHM/ETH Price Feed - [0x022710a589C9796dce59A0C52cA4E36f0a5e991A](https://goerli.etherscan.io/address/0x022710a589c9796dce59a0c52ca4e36f0a5e991a)
- Mock DAI/ETH Price Feed - [0xdC8E4eD326cFb730a759312B6b1727C6Ef9ca233](https://goerli.etherscan.io/address/0xdc8e4ed326cfb730a759312b6b1727c6ef9ca233)
- Bond Auctioneer - [0xaE73A94b94F6E7aca37f4c79C4b865F1AF06A68b](https://goerli.etherscan.io/address/0xae73a94b94f6e7aca37f4c79c4b865f1af06a68b)
- Bond Teller - [0x36211a11f2DaC433Ae34Be898b173942b334dBD5](https://goerli.etherscan.io/address/0x36211a11f2dac433ae34be898b173942b334dbd5)
- Bond Aggregator - [0xB4860B2c12C6B894B64471dFb5a631ff569e220e](https://goerli.etherscan.io/address/0xb4860b2c12c6b894b64471dfb5a631ff569e220e)

#### Privileged Testnet Accounts

- Executor - 0x83D0f479732CC605225263F1AB7016309475aDd9 (PK: 71270e81b91f27d411b9c0cc7d75e2cc5c50df28a0a01e0fd7b432bff5a64ffe)
- Guardian - 0x19518E4D4E542f4b0Fc27366C23FaC7a0bA491Da (PK: 0882aadfaa5053e58924f45a7c68bc5f96c5260dfffc8eac20df816b968c2003)
- Policy - 0x2694C41588A5C92a0dcddBBB778fb18c5cE16D1D (PK: 2a944c921eb69bd6f1ecc289179a37a91d794d32928c8cd77e43915919933e56)
