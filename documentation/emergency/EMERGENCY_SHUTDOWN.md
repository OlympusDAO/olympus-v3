# Emergency Shutdown Instructions

This document provides information on how to shut down the Olympus protocol in the event of an emergency.

Currently the contracts in the protocol have differing approaches and access controles for shutdown procedures. Efforts have started to standardise the functions and roles, but will take time.

## Role Assignment

The assignment of roles can be viewed at any time on the [Protocol Visualizer](https://olympus-protocol-visualizer.up.railway.app).

## Contract Addresses

Addresses are provided in the sections below, but effort should be made to check the address in [env.json](../../src/scripts/env.json), in case it has not been updated here.

## CCIP Bridge

See [BRIDGE_CCIP](../BRIDGE_CCIP.md) for detailed instructions on how to shut down the components of the CCIP bridge.

## LayerZero Bridge

Bridging OHM between EVM chains is currently handled by the [LayerZero bridge](../../src/policies/CrossChainBridge.sol). Transactions can be paused by calling the following:

- Function: `setBridgeStatus(bool)`
- Required role: `bridge_admin` (DAO MS, OCG Timelock)
- Address: `0x45e563c39cDdbA8699A90078F42353A57509543a`
- [ABI](abis/cross_chain_bridge.json)

## TRSRY

Withdrawals from the TRSRY module can be stopped by calling the [Emergency policy](../../src/policies/Emergency.sol):

- Function: `shutdownWithdrawals()`
- Required role: `emergency_shutdown` (DAO MS, Emergency MS, OCG Timelock)
- Address: `0x9229b0b6FA4A58D67Eb465567DaA2c6A34714A75`
- [ABI](abis/emergency.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

## MINTR

OHM minting by the MINTR can be stopped by calling the [Emergency policy](../../src/policies/Emergency.sol):

- Function: `shutdownMinting()`
- Required role: `emergency_shutdown` (DAO MS, Emergency MS, OCG Timelock)
- Address: `0x9229b0b6FA4A58D67Eb465567DaA2c6A34714A75`
- [ABI](abis/emergency.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

## Cooler v2

### Borrows

Borrows can be paused on the Cooler V2 contract ([MonoCooler](../../src/policies/cooler/MonoCooler.sol)):

- Function: `setBorrowPaused(bool)`
- Required role: `admin` (OCG Timelock) or `emergency` (OCG Timelock or Emergency MS)
- Address: `0xdb591Ea2e5Db886dA872654D58f6cc584b68e7cC`
- [ABI](abis/cooler_v2.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

### Composites

The [composites periphery contract](../../src/periphery/CoolerComposites.sol) can be disabled using the following:

- Function: `disable(bytes)` (empty bytes is fine)
- Required role: currently owned by the DAO MS
- Address: `0x6593768feBF9C95aC857Fb7Ef244D5738D1C57Fd`
- [ABI](abis/periphery_enabler.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

### Migrator

The [migrator periphery contract](../../src/periphery/CoolerV2Migrator.sol) can be disabled using the following:

- Function: `disable(bytes)` (empty bytes is fine)
- Required role: currently owned by the DAO MS
- Address: `0xE045BD0A0d85E980AA152064C06EAe6B6aE358D2`
- [ABI](abis/periphery_enabler.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

### Liquidations

Liquidations can be paused on the Cooler V2 contract ([MonoCooler](../../src/policies/cooler/MonoCooler.sol)):

- Function: `setLiquidationsPaused(bool)`
- Required role: `admin` (OCG Timelock) or `emergency` (OCG Timelock or Emergency MS)
- Address: `0xdb591Ea2e5Db886dA872654D58f6cc584b68e7cC`
- [ABI](abis/cooler_v2.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

## Emission Manager

The [EmissionManager policy](../../src/policies/EmissionManager.sol) can be shut down using the following:

- Function: `shutdown()`
- Required role: `emergency_shutdown` (DAO MS, Emergency MS, OCG Timelock)
- Address: `0x50f441a3387625bDA8B8081cE3fd6C04CC48C0A2`
- [ABI](abis/emission_manager.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

## Yield Repurchase Facility

The [YieldRepurchaseFacility policy](../../src/policies/YieldRepurchaseFacility.sol) can be shut down using the following:

- Function: `shutdown(ERC20[])`
- Required role: `loop_daddy` (DAO MS, OCG Timelock)
- Address: `0x271e35a8555a62F6bA76508E85dfD76D580B0692`
- [ABI](abis/yield_repurchase_facility.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

The `shutdown()` function takes an array of tokens that will be transferred into the TRSRY module. A zero-length array can be provided.

## Heart

The [Heart policy](../../src/policies/Heart.sol) can be shut down using the following:

- Function: `deactivate()`
- Required role: `heart_admin` (DAO MS, OCG Timelock)
- Address: `0xf7602c0421c283a2fc113172ebdf64c30f21654d`
- [ABI](abis/heart.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

## Bond Manager

The [BondManager policy](../../src/policies/BondManager.sol) can be used to stop the bond callback from minting more OHM. It also closes the market.

- Function: `emergencyShutdownFixedExpiryMarket(uint256 marketId)`
- Required role: `bondmanager_admin` (DAO MS)
- Address: `0xf577c77ee3578c7F216327F41B5D7221EaD2B2A3`
- [ABI](abis/bond_manager.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

## Reserve Migrator

The [ReserveMigrator policy](../../src/policies/ReserveMigrator.sol) can be shut down using the following:

- Function: `deactivate()`
- Required role: `reserve_migrator_admin` (DAO MS, OCG Timelock)
- Address: `0x986b99579BEc7B990331474b66CcDB94Fa2419F5`
- [ABI](abis/reserve_migrator.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)
