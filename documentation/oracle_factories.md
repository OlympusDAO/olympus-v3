# Oracle Factories and Policies

## Purpose

Oracle factories provide gas-efficient, standardized oracle deployments for external protocol integrations. They serve as a single source of truth through the PRICE module and enable seamless integration with:

- **Chainlink** - Industry-standard price feeds
- **Morpho** - Lending protocol compatibility
- **ERC7726** - General lending oracle standard

### Key Benefits

- **Gas Efficiency**: Uses `ClonesWithImmutableArgs` pattern for minimal deployment cost
- **Upgrade Safety**: Oracles reference PRICE dynamically, inheriting upgrades automatically
- **Standardization**: Implements industry-standard interfaces for broad compatibility
- **Access Control**: Role-based deployment via `ORACLE_MANAGER_ROLE`

## Prerequisites

### PRICE v1.2 or Later (REQUIRED)

Oracle factory policies require:

- **PRICE v1.2+** (major=1, minor>=2) or **PRICE v2+** (major>=2)
- The PRICE module must support `IPRICEv2` interface

**Why this requirement exists**: Oracle factories call `PRICE.getPrice()` for token pairs. Earlier PRICE versions (v1.0, v1.1) do not support multi-asset pricing required by oracles.

### Dependencies

Before deploying oracle factories, ensure:

1. PRICE v1.2+ module is **installed and configured** with target assets
2. ROLES module is **installed** (for access control)
3. Kernel is **deployed** and accessible

## Oracle Types

### 1. ChainlinkOracleFactory

Deploys Chainlink-compatible oracles implementing `AggregatorV2V3Interface`.

**Implementation**: `ChainlinkOracleCloneable`

**Use Cases**:

- Protocols requiring Chainlink compatibility
- Standard price feed integrations

**Price Scaling**: `PRICE_DECIMALS` (typically 18 decimals)

**Interface**: Returns price as `latestRoundData()` with 18 decimal precision

### 2. MorphoOracleFactory

Deploys Morpho-compatible oracles implementing `IMorphoOracle`.

**Implementation**: `MorphoOracleCloneable`

**Use Cases**:

- Morpho lending protocol integration
- Collateral valuation for Morpho markets

**Price Scaling**: **36 decimals** (Morpho requirement)

**Special Logic**:

- Calculates scale factor: `10^(loanDecimals - collateralDecimals + 36)`
- Validates decimals bounds to prevent overflow

### 3. ERC7726Oracle

Standalone ERC7726-compliant oracle policy (not a factory).

**Implementation**: `ERC7726Oracle`

**Use Cases**:

- General lending protocols
- Protocols requiring bid/ask quotes
- Two-sided pricing with spread support

**Special Features**:

- `getQuote()` - Single-sided pricing
- `getQuotes()` - Bid/ask two-sided pricing
- Uses PRICE to calculate relative token prices

## Deployment Flow

### Overview

The complete deployment flow consists of three steps:

1. **Deploy Oracle Factories** - Deploy contracts to the blockchain
2. **MS Batch - Activate Policies** - Register policies with Kernel via DAO multisig
3. **OCG Proposal - Enable and Deploy** - Enable functionality and deploy initial oracles

**Important Distinction**:

- **"Activate"** (`kernel.executeAction(Actions.ActivatePolicy, address)`): Registers the policy contract with the Kernel module
- **"Enable"** (`IEnabler.enable()`): Turns on the policy's functionality via the PolicyEnabler pattern

### Step 1: Deploy Oracle Factories

Deploy the three oracle factory contracts.

**Prerequisites**:

- PRICE v1.2+ module must be installed and configured
- Kernel address in environment

**Deployment sequence**: `src/scripts/deploy/savedDeployments/oracle_factories_deploy.json`

**Deploy command**:

```bash
./shell/deployV3.sh \
  --account <wallet> \
  --sequence src/scripts/deploy/savedDeployments/oracle_factories_deploy.json \
  --chain mainnet \
  --broadcast true \
  --verify true
```

**What this deploys**:

1. `ChainlinkOracleFactory` - Factory for Chainlink-compatible oracles
2. `MorphoOracleFactory` - Factory for Morpho-compatible oracles
3. `ERC7726Oracle` - Standalone ERC7726-compliant oracle policy

**Post-deployment**:

- Update environment files with deployed addresses
- Addresses follow naming convention: `olympus.policies.{ContractName}`

### Step 2: MS Batch - Activate Policies

Activate the oracle factory policies in the Kernel via DAO multisig batch.

**Batch script**: `src/scripts/ops/batches/ConfigureOracles.sol`

**Prerequisites**:

- Oracle factories deployed
- Factory addresses in environment (`olympus.policies.ChainlinkOracleFactory`, etc.)

**Batch command**:

```bash
./shell/safeBatchV2.sh \
  --contract ConfigureOracles \
  --function configureOracles \
  --chain mainnet \
  --multisig true \
  --broadcast true
```

**What this batch does**:

- Activates `ChainlinkOracleFactory` via `kernel.executeAction(Actions.ActivatePolicy, address)`
- Activates `MorphoOracleFactory` via `kernel.executeAction(Actions.ActivatePolicy, address)`
- Activates `ERC7726Oracle` via `kernel.executeAction(Actions.ActivatePolicy, address)`
- Validates all policies are activated (post-batch validation)

**Post-batch state**:

- Policies are **activated** (registered with Kernel)
- Policies are **disabled** (functionality off until OCG enables them)

### Step 3: OCG Proposal - Enable and Deploy

Enable oracle policies and deploy initial oracles via On-Chain Governance proposal.

**Proposal template**: `src/proposals/OracleProposal.sol`

**Actions performed**:

1. Grant `admin` role to Timelock (if needed - required for `enable()` calls)
2. Grant `oracle_manager` role to DAO MS and Timelock
3. **Enable** ERC7726Oracle (`IEnabler.enable()`)
4. **Enable** ChainlinkOracleFactory (`IEnabler.enable()`)
5. **Enable** MorphoOracleFactory (`IEnabler.enable()`)
6. Deploy OHM/USDS Chainlink oracle (via `ChainlinkOracleFactory.createOracle()`)
7. Deploy OHM/USDS Morpho oracle (via `MorphoOracleFactory.createOracle()`)

**Proposal Submission**:

  ```bash
  src/scripts/proposals/submitProposal.sh \
    --file src/proposals/OracleProposal.sol \
    --contract OracleProposalScript \
    --account <wallet> \
    --chain mainnet \
    --broadcast true
  ```

  The proposal ID will be output after submission.

## Deploying New Oracles

After oracle factories are enabled, new oracles can be deployed by the `oracle_manager` role holders (DAO MS, Timelock).

### Requirements

- `oracle_manager` role (held by DAO MS and Timelock)
- PRICE module must have tokens configured
- Oracle factory must be enabled

### Deploy New Oracle

Use the pre-built batch script for oracle deployment.

**Batch script**: `src/scripts/ops/batches/DeployOracles.sol`

Create an args file (`oracle_args.json`) with the token addresses and expected price bounds:

```json
{
  "functions": [
    {
      "name": "deployChainlinkOracle",
      "args": {
        "baseToken": "0x...",
        "quoteToken": "0x...",
        "minPrice": "1000000000000000000",
        "maxPrice": "10000000000000000000"
      }
    }
  ]
}
```

**Deploy commands**:

```bash
# Deploy Chainlink oracle for a token pair
./shell/safeBatchV2.sh \
  --contract DeployOracles \
  --function deployChainlinkOracle \
  --chain mainnet \
  --multisig true \
  --broadcast true \
  --args oracle_args.json
```

```bash
# Deploy Morpho oracle for a token pair
./shell/safeBatchV2.sh \
  --contract DeployOracles \
  --function deployMorphoOracle \
  --chain mainnet \
  --multisig true \
  --broadcast true \
  --args oracle_args.json
```

**Available functions**:

- `deployChainlinkOracle` - Deploy a single Chainlink oracle
- `deployMorphoOracle` - Deploy a single Morpho oracle

**Args file parameters**:

- `baseToken` - The base token address
- `quoteToken` - The quote token address
- `minPrice` - Minimum expected price (18 decimals, for validation)
- `maxPrice` - Maximum expected price (18 decimals, for validation)

**Post-batch validation**: The batch script automatically validates:

- Oracle was deployed (via `getOracle()`)
- Oracle is enabled (via `isOracleEnabled()`)
- Oracle price is within specified bounds (via PRICE module)

## Architecture Benefits

- **Gas Efficiency**: `ClonesWithImmutableArgs` pattern minimizes deployment cost
- **Upgrade Safety**: Oracles reference PRICE dynamically, inheriting upgrades
- **Standardization**: Industry-standard interfaces for broad compatibility
- **Access Control**: Role-based deployment via ROLES module

## File Reference

| File | Purpose |
| ---- | ------- |
| `src/policies/price/BaseOracleFactory.sol` | Abstract base for all oracle factories |
| `src/policies/price/ChainlinkOracleFactory.sol` | Chainlink oracle factory |
| `src/policies/price/MorphoOracleFactory.sol` | Morpho oracle factory |
| `src/policies/price/ERC7726Oracle.sol` | ERC7726 oracle policy |
| `src/policies/price/ChainlinkOracleCloneable.sol` | Chainlink oracle implementation |
| `src/policies/price/MorphoOracleCloneable.sol` | Morpho oracle implementation |
| `src/policies/interfaces/price/IOracleFactory.sol` | Oracle factory interface |
| `src/policies/interfaces/price/IERC7726Oracle.sol` | ERC7726 oracle interface |
| `src/scripts/deploy/savedDeployments/oracle_factories_deploy.json` | Deployment sequence |
| `src/scripts/deploy/DeployV3.s.sol` | Deployment script (lines 873-919) |
| `shell/deployV3.sh` | Deployment shell script |
| `src/scripts/ops/batches/ConfigureOracles.sol` | MS batch for factory activation |
| `src/scripts/ops/batches/DeployOracles.sol` | MS batch for deploying new oracles |
| `shell/safeBatchV2.sh` | Batch execution shell script |
| `src/proposals/OracleProposal.sol` | OCG proposal template |
| `src/policies/utils/RoleDefinitions.sol` | ORACLE_MANAGER_ROLE definition |

## Troubleshooting

### Oracle Factory Not Activated

**Symptom**: `configureOracles` batch fails with "not activated"

**Solution**: Verify factory addresses are correct in environment and batch executes `ActivatePolicy` action

### PRICE Version Too Old

**Symptom**: `OracleFactory_UnsupportedModuleVersion` on deployment

**Solution**: Ensure PRICE v1.2+ is installed. Check version via `Module(priceAddress).VERSION()`

### Tokens Not Configured in PRICE

**Symptom**: `PRICE_AssetNotApproved` when creating oracle

**Solution**: Use PriceConfigv2 to add target assets to PRICE module before oracle deployment

### Oracle Creation Disabled

**Symptom**: `OracleFactory_CreationDisabled` when calling `createOracle()`

**Solution**: Call `enableCreation()` from `oracle_manager` role holder
