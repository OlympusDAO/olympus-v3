# CCIP Migration Sequences

Diagrams for the two supported replacement procedures, on Ethereum and on a non-Ethereum EVM chain.

## Choosing a scenario

```mermaid
flowchart TD
    START["What is being replaced?"]
    START --> CFGONLY["Config policy and timelock"]
    START --> WITHPOOL["Token pool"]
    CFGONLY --> A["Scenario A<br/>Pool, registry, liquidity and routes untouched<br/>No Solana action"]
    WITHPOOL --> B["Scenario B<br/>Full triad, registry updated<br/>Solana pre-step required"]
    WITHPOOL --> NOTSUP["Pool alone is not supported:<br/>the config policy's pool address<br/>is fixed at construction"]
    NOTSUP -.-> B
```

## Scenario A on Ethereum

Config policy and timelock are replaced; the pool keeps its address, owner chain, liquidity, and routes. The new config policy is constructed with the existing pool address.

```mermaid
sequenceDiagram
    autonumber
    participant DAO as DAO Multisig
    participant OCG as OCG timelock
    participant K as Kernel
    participant OC as old Config
    participant OT as old Timelock
    participant NC as new Config
    participant NT as new Timelock
    participant P as LockRelease pool

    Note over DAO,P: Phase 1: DAO Multisig batch (Kernel executor)
    Note over DAO: deploy new Config and new Timelock
    DAO->>K: executeAction(ActivatePolicy, newConfig)
    DAO->>K: executeAction(ActivatePolicy, newTimelock)
    DAO->>OT: cancelQueuedAction(id) for anything that must not survive

    Note over DAO,P: Phase 2: OCG proposal, 7 actions, one transaction
    OCG->>OC: transferPoolOwnership(newConfig)
    OC->>P: transferOwnership(newConfig)
    OCG->>NC: enable("")
    OCG->>NC: acceptPoolOwnership()
    NC->>P: acceptOwnership()
    OCG->>NC: setConfigurator(newTimelock)
    OCG->>NT: enable("")
    OCG->>OC: disable("")
    OCG->>OT: disable("")

    Note over DAO,P: Phase 3: DAO Multisig batch
    DAO->>K: executeAction(DeactivatePolicy, oldConfig)
    DAO->>K: executeAction(DeactivatePolicy, oldTimelock)
```

`enable` precedes `acceptPoolOwnership` because admin functions are gated on the policy being enabled. `transferPoolOwnership` precedes `disable` on the old policy for the same reason.

## Scenario A on a non-Ethereum EVM chain

No OCG timelock exists, so the local DAO Multisig holds `admin` and is the Kernel executor. All three phases collapse into one batch.

```mermaid
sequenceDiagram
    autonumber
    participant DAO as local DAO Multisig
    participant K as Kernel
    participant OC as old Config
    participant OT as old Timelock
    participant NC as new Config
    participant NT as new Timelock
    participant P as BurnMint pool

    Note over DAO,P: Single batch, local DAO Multisig
    Note over DAO: deploy new Config and new Timelock
    DAO->>K: executeAction(ActivatePolicy, newConfig)
    DAO->>K: executeAction(ActivatePolicy, newTimelock)
    DAO->>OT: cancelQueuedAction(id) as needed
    DAO->>OC: transferPoolOwnership(newConfig)
    OC->>P: transferOwnership(newConfig)
    DAO->>NC: enable("")
    DAO->>NC: acceptPoolOwnership()
    NC->>P: acceptOwnership()
    DAO->>NC: setConfigurator(newTimelock)
    DAO->>NT: enable("")
    DAO->>OC: disable("")
    DAO->>OT: disable("")
    DAO->>K: executeAction(DeactivatePolicy, oldConfig)
    DAO->>K: executeAction(DeactivatePolicy, oldTimelock)
```

The pool is a policy here but is not replaced, so its Kernel state and MINTR permissions are untouched.

## Scenario B on Ethereum

Pool address changes, so liquidity moves and the registry is updated. An activator holding a temporary `admin` grant fits the sequence into the fifteen-action proposal limit.

```mermaid
sequenceDiagram
    autonumber
    participant DAO as DAO Multisig
    participant OCG as OCG timelock
    participant K as Kernel
    participant RA as RolesAdmin
    participant AC as Activator
    participant OC as old Config
    participant NC as new Config
    participant NT as new Timelock
    participant OP as old pool
    participant NP as new pool
    participant REG as TokenAdminRegistry

    Note over DAO,REG: Phase 1: deployment and DAO Multisig batch
    Note over DAO: deploy new pool (same OHM address), Config, Timelock, Activator
    DAO->>NP: transferOwnership(newConfig)
    DAO->>K: executeAction(ActivatePolicy, newConfig)
    DAO->>K: executeAction(ActivatePolicy, newTimelock)
    Note over DAO: on Solana: AppendRemotePoolAddresses(new Ethereum pool)

    Note over DAO,REG: Phase 2: OCG proposal, 4 actions, one transaction
    OCG->>RA: grantRole(admin, activator)
    OCG->>AC: activate()
    AC->>NC: enable("")
    AC->>NC: acceptPoolOwnership()
    NC->>NP: acceptOwnership()
    AC->>NC: addChain, addRemotePool, setChainRateLimits
    NC->>NP: configure each route
    AC->>OC: setRebalancer(newPool)
    OC->>OP: setRebalancer(newPool)
    AC->>NC: transferLiquidity(oldPool, balanceOf(oldPool))
    NC->>NP: transferLiquidity(oldPool, amount)
    NP->>OP: withdrawLiquidity(amount)
    OP-->>NP: OHM
    AC->>NC: setRebalancer(OCG timelock)
    AC->>NC: setConfigurator(newTimelock)
    AC->>NT: enable("")
    AC->>OC: disable("")
    OCG->>REG: setPool(OHM, newPool)
    OCG->>RA: revokeRole(admin, activator)

    Note over DAO,REG: Phase 3: DAO Multisig batch
    DAO->>K: executeAction(DeactivatePolicy, oldConfig)
    DAO->>K: executeAction(DeactivatePolicy, oldTimelock)
```

`setRebalancer` on the old pool must precede `transferLiquidity`, since `withdrawLiquidity` checks the rebalancer. Both must precede `disable` on the old config policy. `setPool` follows `activate()` so the registry points at the new pool only once it holds the liquidity; it is a separate action because the registry gates it on the OHM administrator, which is the OCG timelock rather than the activator. Removing the old pool from Solana's accepted list afterwards is unnecessary.

## Scenario B on a non-Ethereum EVM chain

The pool is a policy with MINTR permissions and its own lifecycle. There is no liquidity to move, and the local DAO Multisig holds every required authority, so no activator is needed. A mainnet step must come first.

```mermaid
sequenceDiagram
    autonumber
    participant ETH as Ethereum config path
    participant DAO as local DAO Multisig
    participant K as local Kernel
    participant OP as old pool
    participant NP as new pool
    participant OC as old Config
    participant NC as new Config
    participant NT as new Timelock
    participant REG as local TokenAdminRegistry

    Note over ETH,REG: Phase 1: on Ethereum, before the local batch
    ETH->>ETH: addRemotePool(localSelector, newLocalPool)

    Note over ETH,REG: Phase 2: single batch, local DAO Multisig
    Note over DAO: deploy new pool, Config, Timelock
    DAO->>NP: transferOwnership(newConfig)
    DAO->>K: executeAction(ActivatePolicy, newPool)
    DAO->>K: executeAction(ActivatePolicy, newConfig)
    DAO->>K: executeAction(ActivatePolicy, newTimelock)
    DAO->>NP: enable("")
    DAO->>NC: enable("")
    DAO->>NC: acceptPoolOwnership()
    NC->>NP: acceptOwnership()
    DAO->>NC: addChain, addRemotePool, setChainRateLimits
    NC->>NP: configure each route
    DAO->>NC: setConfigurator(newTimelock)
    DAO->>NT: enable("")
    DAO->>REG: setPool(OHM, newPool)
    DAO->>OP: disable("")
    DAO->>OC: disable("")
    DAO->>K: executeAction(DeactivatePolicy, oldPool)
    DAO->>K: executeAction(DeactivatePolicy, oldConfig)
    DAO->>K: executeAction(DeactivatePolicy, oldTimelock)

    Note over ETH,REG: Phase 3: on Ethereum, after messages from the old pool are executed
    ETH->>ETH: removeRemotePool(localSelector, oldLocalPool)
```

`ActivatePolicy` on the new pool grants its MINTR permissions and must precede `setPool`, or a registered pool would be unable to mint. `enable` on the new pool must also precede `setPool`, since `_burn` and `_mint` are gated on it. `setPool` must precede disabling the old pool, for the same two reasons applied in reverse. The Ethereum steps go through the config timelock or directly under `admin`.
