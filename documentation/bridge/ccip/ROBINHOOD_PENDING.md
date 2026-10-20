# Robinhood Chain: pending items

Robinhood Chain (chain ID 4663, CCIP selector `6180753054346818345`) is the fifth burn/mint chain of the CCIP rollout (`RUNBOOK.md`, "Non-Ethereum rollout"), routed to mainnet, Arbitrum and Base. Its desired state is declared in `src/scripts/env.json`, but its Olympus stack is not deployed yet. This file lists what is still open and is removed once everything in it is done.

## Placeholders in `current.robinhood` of `env.json`

| Key | Filled by |
| --- | --- |
| `olympus.Kernel`, `olympus.legacy.OHM`, `olympus.modules.OlympusMinter`, `olympus.modules.OlympusRoles`, `olympus.policies.RolesAdmin` | the Olympus stack deployment on Robinhood Chain (the contracts of the other burn/mint chains: a 9-decimal `OlympusERC20Token`, MINTR, ROLES, RolesAdmin), recorded by hand |
| `olympus.multisig.dao` | the local DAO MS, a Safe (Safe 1.3.0 and 1.4.1 carry code on Robinhood Chain; the Safe config service lists chain 4663), recorded by hand |
| `olympus.multisig.emergency` | the Emergency MS on Robinhood Chain, recorded by hand (open question below) |
| `olympus.policies.CCIPBurnMintTokenPool`, `olympus.policies.CCIPTokenPoolConfig`, `olympus.policies.CCIPTokenPoolConfigTimelock`, `olympus.periphery.CCIPCrossChainBridge` | `./shell/deployV3.sh --sequence src/scripts/deploy/savedDeployments/ccip_full_not_mainnet.json --chain robinhood` (`RUNBOOK.md`, "Deployment") |

The other values of the block are real: `external.ccip` (`Router 1.2.0` `0x06fC836c...`, `ARMProxy 1.0.0` `0xe8464c35...`, `TokenAdminRegistry 1.5.0` `0x1912C3cF...`, read from the chain on 2026-10-19 and again on 2026-10-20 and matching the Chainlink CCIP Directory), the three routes with their limits and `periphery` blocks, and the config parameters.

## Fail-closed state, by design

With the `robinhood` routes declared on mainnet, Arbitrum and Base, every run that resolves them fails closed on the zero Robinhood OHM, pool or periphery, on those three chains as well as on Robinhood Chain: the readiness report, `CCIPNonEthereumSetupBatch.setup` and `finalize`, `CCIPRouteReconcileBatch.reconcileRoutes`, `CCIPBridgeBatch.reconcileTrustedRemotes` and the build of proposal 19. No check is softened to make a run pass; the three addresses are recorded first.

## Requests to Chainlink

1. **OHM administrator.** Propose the local DAO MS as the OHM administrator in the Robinhood `TokenAdminRegistry` (`0x1912C3cF...`, owned by a Chainlink timelock with a 3-hour delay). The Robinhood OHM has neither `owner()` nor `getCCIPAdmin()`, so no self-service path of `RegistryModuleOwnerCustom` applies and only the registry owner proposes. Sent once the OHM and the DAO MS exist. The registry step of the rollout then reduces to `CCIPTokenPoolBatch.acceptAdminRole` from the DAO MS.
2. **Fee budget entries** (`destGasOverhead >= 175000`, `RUNBOOK.md` step 0), five in all. Mainnet to Robinhood (mainnet OHM), Arbitrum to Robinhood (Arbitrum OHM) and Base to Robinhood (Base OHM) can be requested now. Robinhood to Arbitrum and Robinhood to Base name the Robinhood OHM and follow its deployment. Robinhood to mainnet needs none.

## Open questions

- **Emergency MS.** The address of the other chains, `0xa8A6ff2606b24F61AFA986381D8991DFcCCd2D55`, has no code on Robinhood Chain (read 2026-10-20). Either it is deployed there at the same address or another Safe is; the chosen address goes into `olympus.multisig.emergency` before the setup batch, which grants it `emergency`.
- **`safe-utils` gap.** The pinned `safe-utils` 0.0.17 maps neither chain ID 4663 nor 80094 (Berachain), so `getProposeTransactionsTargetAndData` reverts with `MultiSendCallOnlyNotFound` before a batch is signed: every batch built on `BatchScriptV2` for a multisig owner on Robinhood Chain is blocked until the dependency is bumped (upstream `main` maps both), through `safeBatchV2.sh` and through the direct `forge script` entry points alike, `acceptAdminRole` from the DAO MS in step 1 included.

## Rollout steps for Robinhood Chain (`RUNBOOK.md`, "Non-Ethereum rollout")

0. The fee budget entries above.
1. Registry: `CCIPTokenPoolBatch.acceptAdminRole` from the DAO MS, once Chainlink has proposed it.
2. Deploy `ccip_full_not_mainnet.json` with `--chain robinhood`; record the four addresses (the deploy script writes them).
3. Ownership handover from the deployer: `CCIPTokenPoolBatch.transferTokenPoolOwnershipToConfig`, `CCIPBridgeBatch.transferOwnership`.
4. Funding on mainnet, unchanged by Robinhood Chain: its supply is not part of `minimumPoolBacking` and stays out of `shell/calc_bridged_supply.sh`. Check first that the Robinhood OHM holds no supply: `cast call <OHM> 'totalSupply()(uint256)' --rpc-url robinhood` must print `0`.
5. Readiness gate green on mainnet and the five burn/mint chains, then the proposal.
6. `setup` during the voting window (Robinhood Chain records no legacy bridge; the batch skips that step).
7. Vote, queue, execute.
8. `finalize`.
9. `CCIPBridgeBatch.reconcileTrustedRemotes`, then `CCIPBridgeBatch.enable`.

## Checks that wait for the stack

| Check | Command |
| --- | --- |
| The readiness report on Robinhood Chain, and the re-run on mainnet, Arbitrum and Base (red today on the Robinhood routes) | `./shell/ccip/check_rollout_readiness.sh` |
| The cold OHM delivery sequence on Robinhood Chain, the first mint at zero supply (about 160,140 gas expected, the Optimism figure with the same contracts, under the 175,000 budget) | a `robinhood` suite in `src/test/policies/bridge/CCIPBurnMintTokenPoolDeliveryGasFork.t.sol`, then `forge test --mp src/test/policies/bridge/CCIPBurnMintTokenPoolDeliveryGasFork.t.sol -vv` |
| The fee budget reads with Robinhood Chain as the source (its lanes toward Arbitrum and Base) | the Robinhood lines of the readiness report above (`checkReadiness` prints one line per outgoing lane) |
| A no-broadcast `setup` on a Robinhood fork (an Anvil fork of the `robinhood` alias on `localhost:8545`) | `./shell/safeBatchV2.sh --contract CCIPNonEthereumSetupBatch --function setup --multisig true --account <cast account> --chain robinhood --broadcast false --fork true` |
| The Anvil rehearsal of Robinhood Chain and of the chains whose routes it joins | `./shell/ccip/anvil-deployment/run-l2.sh --chain robinhood`, `./shell/ccip/anvil-deployment/run-ethereum.sh`, `./shell/ccip/anvil-deployment/run-l2.sh --chain arbitrum`, `./shell/ccip/anvil-deployment/run-l2.sh --chain base` |
| The proposal build against the real `env.json` | `./src/scripts/proposals/printInputs.sh --file src/proposals/CCIPTokenPoolConfigProposal.sol --contract CCIPTokenPoolConfigProposalScript --chain mainnet` |

Sources: the chain reads named above (`cast call` against the `robinhood` alias of `foundry.toml`); the Chainlink CCIP Directory, Robinhood Chain mainnet (<https://docs.chain.link/ccip/directory/mainnet/chain/robinhood-mainnet>); the Robinhood docs (<https://docs.robinhood.com/chain/>); the Safe config service (<https://safe-config.safe.global/api/v1/chains/4663/>).
