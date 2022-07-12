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
- PRICE - [0x397c70E4e7A0bd720233a3f4376A5F8d41cc8b57](https://goerli.etherscan.io/address/0x397c70e4e7a0bd720233a3f4376a5f8d41cc8b57)
- RANGE - [0x47a22bd734885baE7E2e153E98e7137b0B96bEBD](https://goerli.etherscan.io/address/0x47a22bd734885bae7e2e153e98e7137b0b96bebd)
- INSTR - [0xeeB45a384ced4097Ad369d48590AeD8DDBC11257](https://goerli.etherscan.io/address/0xeeb45a384ced4097ad369d48590aed8ddbc11257)
- VOTES - [0xA7dBfcFE09ACCf66B56Fe05841618177AE188c5b](https://goerli.etherscan.io/address/0xa7dbfcfe09accf66b56fe05841618177ae188c5b)

#### Policies

- BondCallback - [0x76775f07B0dCd21DB304b6c5b14d57A2954ddAC6](https://goerli.etherscan.io/address/0x76775f07b0dcd21db304b6c5b14d57a2954ddac6)
- Heart - [0xDF1564f0815CdcA0f5cd2dF67411fC83D981B999](https://goerli.etherscan.io/address/0xdf1564f0815cdca0f5cd2df67411fc83d981b999)
- Operator - [0x84F334bf268821C5A8DB931105088f0369288B4c](https://goerli.etherscan.io/address/0x84f334bf268821c5a8db931105088f0369288b4c)
- PriceConfig - [0xA938A067e5008ec2f76557ad1AB100a4CD7Dfde2](https://goerli.etherscan.io/address/0xa938a067e5008ec2f76557ad1ab100a4cd7dfde2)
- Governance - [0xFEc5b1b96Ec2dA1494F5ad3D6E141Ce401c6C2D5](https://goerli.etherscan.io/address/0xfec5b1b96ec2da1494f5ad3d6e141ce401c6c2d5)
- VoterRegistration - [0x5d7221dA0cF85dEC1d5bC26BeE803C53B6B87355](https://goerli.etherscan.io/address/0x5d7221da0cf85dec1d5bc26bee803c53b6b87355)
- Auth Giver (Testnet Only) - [0x3714fDFc3b6918923e5b2AbAe0fcD74376Be45fc](https://goerli.etherscan.io/address/0x3714fdfc3b6918923e5b2abae0fcd74376be45fc)

#### Dependencies

- OHM Token - [0x0595328847AF962F951a4f8F8eE9A3Bf261e4f6b](https://goerli.etherscan.io/address/0x0595328847af962f951a4f8f8ee9a3bf261e4f6b)
- DAI Token - [0x41e38e70a36150D08A8c97aEC194321b5eB545A5](https://goerli.etherscan.io/address/0x41e38e70a36150d08a8c97aec194321b5eb545a5)
- WETH Token (for keeper rewards) - [0x0Bb7509324cE409F7bbC4b701f932eAca9736AB7](https://goerli.etherscan.io/address/0x0bb7509324ce409f7bbc4b701f932eaca9736ab7)
- Mock OHM/ETH Price Feed - [0x769435458365Fef4C14aCE998A0ff6AB29c376Ff](https://goerli.etherscan.io/address/0x769435458365fef4c14ace998a0ff6ab29c376ff)
- Mock DAI/ETH Price Feed - [0x63dC91F5efAbf0c49C5a0b1f573B23A4aD40e3aA](https://goerli.etherscan.io/address/0x63dc91f5efabf0c49c5a0b1f573b23a4ad40e3aa)
- Bond Auctioneer - [0x85A41eCdefAA441C71C94a47FDD04e4509a2944a](https://goerli.etherscan.io/address/0x85a41ecdefaa441c71c94a47fdd04e4509a2944a)
- Bond Teller - [0xb4Ff2D13D277dc2c7801F2b4525b6904BB9387B9](https://goerli.etherscan.io/address/0xb4ff2d13d277dc2c7801f2b4525b6904bb9387b9)
- Bond Aggregator - [0x2B33ABcb816AeE1BB38fa84537329955f79d900e](https://goerli.etherscan.io/address/0x2b33abcb816aee1bb38fa84537329955f79d900e)

#### Privileged Testnet Accounts

- Executor - 0x83D0f479732CC605225263F1AB7016309475aDd9 (PK: 71270e81b91f27d411b9c0cc7d75e2cc5c50df28a0a01e0fd7b432bff5a64ffe)
- Guardian - 0x19518E4D4E542f4b0Fc27366C23FaC7a0bA491Da (PK: 0882aadfaa5053e58924f45a7c68bc5f96c5260dfffc8eac20df816b968c2003)
- Policy - 0x2694C41588A5C92a0dcddBBB778fb18c5cE16D1D (PK: 2a944c921eb69bd6f1ecc289179a37a91d794d32928c8cd77e43915919933e56)
