// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @notice External `pure` no-op used as an observation point for hooks that
///         must remain `view` themselves. A test harness installs an instance
///         and forwards a call to `note()` from inside a `view` hook; the
///         call lands as a STATICCALL with no on-chain effect, but the
///         `vm.expectCall` cheatcode still records it. This lets tests assert
///         both the fact and the multiplicity of the hook's invocation
///         without forcing the hook out of its `view` contract.
contract StaticCallProbe {
    function note() external pure {}
}
