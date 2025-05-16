// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.24;

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

/// @title ConfigureCCIPTokenPool
/// @notice Multi-sig batch to configure the CCIP bridge
///         This scripts is designed to define the desired configuration,
///         and the script will execute the necessary transactions to
///         configure the CCIP bridge to the desired state.
contract ConfigureCCIPTokenPool is OlyBatch {
    // Define the per-chain configuration
    // chain -> supported destination chains
    // chain -> token pool addresses
    // chain -> outbound rate limiter config
    // chain -> inbound rate limiter config
    // chain -> token address

    function configure(string calldata chain_) external {}
}
