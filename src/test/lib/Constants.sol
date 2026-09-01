// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// The Ethereum mainnet block gas limit, 60_000_000 as of 2026-09-01.
//
// Forge cannot supply the value at runtime: `block.gaslimit` follows the `gas_limit` entry of
// foundry.toml, which this repository sets to the uint64 maximum so that heavy tests are not cut
// short. A test needing a realistic block budget imports this instead. A measurement compared
// against it is only meaningful under isolation, where each top-level call is charged as its own
// transaction.
uint256 constant ETHEREUM_BLOCK_GAS_LIMIT = 60_000_000;
