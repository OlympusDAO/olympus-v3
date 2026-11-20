// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @notice Factory interface used to reproduce the published communal reader on the historical fork.
interface IApi3ReaderProxyV1Factory {
    /// @notice Deploys the deterministic reader for a dAPI, application and metadata tuple.
    /// @param dapiName_ Null-padded dAPI name, such as USDe/USD.
    /// @param dappId_ Reader application ID; one selects the communal reader.
    /// @param metadata_ Optional reader metadata; empty for this communal reader.
    /// @return proxy The deterministic deployed reader address.
    function deployApi3ReaderProxyV1(
        bytes32 dapiName_,
        uint256 dappId_,
        bytes calldata metadata_
    ) external returns (address proxy);
}
