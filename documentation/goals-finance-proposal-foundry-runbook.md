# goals.finance Proposal Foundry Runbook

This is the practical testinprod flow for submitting the goals.finance Convertible Deposit Market Configuration proposal with Foundry.

## Local Context

- Repo: `/home/ardor/workspace/olympus-v3`
- Env file: `.env.goals-proposer`
- Foundry keystore alias: `goals-finance-proposer`
- Proposer EOA: `0xddff9955b12A48329B5e2215a3BD36f410969650`
- Proposal file: `src/proposals/ConvertibleDepositMarketConfigProposal.sol`
- Proposal wrapper contract: `ConvertibleDepositMarketConfigProposalScript`
- Targeted test: `ConvertibleDepositMarketConfigProposalTest`

Do not submit against `ConvertibleDepositMarketConfigProposal` directly. The submit path should use the wrapper script contract, `ConvertibleDepositMarketConfigProposalScript`.

## 1. Load Env

```bash
cd /home/ardor/workspace/olympus-v3
export PATH="$HOME/.foundry/bin:$PATH"
set -a
source .env.goals-proposer
set +a
```

## 2. Run Final Targeted Test

```bash
forge test \
  --match-contract ConvertibleDepositMarketConfigProposalTest \
  --match-path 'src/test/proposals/ConvertibleDepositMarketConfigProposal.t.sol' \
  --fork-url "$RPC_URL" \
  -vvv
```

Expected result:

```text
1 passed, 0 failed
```

## 3. Check Proposer EOA

```bash
cast balance 0xddff9955b12A48329B5e2215a3BD36f410969650 --ether --rpc-url "$RPC_URL"
cast nonce 0xddff9955b12A48329B5e2215a3BD36f410969650 --rpc-url "$RPC_URL"
```

The EOA needs enough ETH for gas. On the last check it had `0.011902919786223560 ETH` and nonce `0`, but re-check before any real broadcast.

## 4. Print Proposal Inputs

```bash
src/scripts/proposals/printInputs.sh \
  --file src/proposals/ConvertibleDepositMarketConfigProposal.sol \
  --contract ConvertibleDepositMarketConfigProposalScript \
  --chain "$RPC_URL" \
  --env .env.goals-proposer
```

Review this output before submitting. It should describe the Governor proposal targets, values, signatures, calldatas, and proposal description.

## 5. Dry-Run Submission Path

```bash
src/scripts/proposals/submitProposal.sh \
  --file src/proposals/ConvertibleDepositMarketConfigProposal.sol \
  --contract ConvertibleDepositMarketConfigProposalScript \
  --chain "$RPC_URL" \
  --env .env.goals-proposer \
  --broadcast false
```

This should complete without broadcasting a transaction.

## 6. Real Submission

Only run this after explicit approval to broadcast.

```bash
src/scripts/proposals/submitProposal.sh \
  --file src/proposals/ConvertibleDepositMarketConfigProposal.sol \
  --contract ConvertibleDepositMarketConfigProposalScript \
  --chain "$RPC_URL" \
  --env .env.goals-proposer \
  --broadcast true
```

Foundry will use the local encrypted keystore account. If the password is not already provided through env, it will prompt for the keystore password.

## 7. After Broadcast

Capture:

- transaction hash
- receipt status
- block number
- proposal id, if emitted or printed
- proposer EOA nonce after broadcast

Then verify the transaction on mainnet and confirm the Governor proposal exists with the expected details.
