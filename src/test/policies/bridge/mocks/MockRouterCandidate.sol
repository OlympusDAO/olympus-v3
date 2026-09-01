// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/// @notice Router candidate with a configurable answer to the `typeAndVersion()` probe.
/// @dev    The probe is served from the fallback so the raw return data length is controlled
///         exactly: a valid version string, an explicit revert, return data below 64 bytes,
///         the ABI encoding of the empty string (exactly 64 bytes) or undecodable data above
///         64 bytes. The fallback only reads state, so it also serves static calls.
contract MockRouterCandidate {
    enum ReturnMode {
        ValidVersion,
        Reverting,
        ShortReturn,
        EmptyString,
        LongGarbage
    }

    error MockRouterCandidate_Reverting();

    ReturnMode public mode;

    function setMode(ReturnMode mode_) external {
        mode = mode_;
    }

    fallback(bytes calldata) external returns (bytes memory) {
        ReturnMode currentMode = mode;
        if (currentMode == ReturnMode.Reverting) revert MockRouterCandidate_Reverting();
        if (currentMode == ReturnMode.ValidVersion) return abi.encode("MockRouterCandidate 1.0.0");
        // 32 bytes: below the 64-byte minimum of an ABI-encoded string
        if (currentMode == ReturnMode.ShortReturn) return abi.encodePacked(uint256(32));
        // 64 bytes: the ABI encoding of the empty string
        if (currentMode == ReturnMode.EmptyString) return abi.encode("");
        // 96 bytes of data that does not decode as a string
        return
            abi.encodePacked(
                keccak256("garbage-one"),
                keccak256("garbage-two"),
                keccak256("garbage-three")
            );
    }
}
