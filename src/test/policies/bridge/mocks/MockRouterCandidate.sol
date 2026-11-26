// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/// @dev The length of the `OversizedReturn` answer of `MockRouterCandidate`, in bytes: 256 KiB.
///      Returning it costs 8192 words of memory, 3 * 8192 + 8192^2 / 512 = 155,648 gas, which a
///      caller probing under a bounded gas budget cannot afford to forward.
uint256 constant OVERSIZED_RETURN_LENGTH = 262144;

/// @notice Router candidate with a configurable answer to the `typeAndVersion()` probe.
/// @dev    The probe is served from the fallback so the raw return data length is controlled
///         exactly: a valid version string, an explicit revert, return data below 64 bytes,
///         the ABI encoding of the empty string (exactly 64 bytes), undecodable data above
///         64 bytes, or an answer so large that producing it exhausts a bounded probe budget.
///         The fallback only reads state, so it also serves static calls.
contract MockRouterCandidate {
    enum ReturnMode {
        ValidVersion,
        Reverting,
        ShortReturn,
        EmptyString,
        LongGarbage,
        OversizedReturn
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
        // The typed fallback returns the bytes directly. Expanding to 256 KiB exceeds the
        // probe's gas budget.
        if (currentMode == ReturnMode.OversizedReturn) {
            // Allocate only for this mode. A raw assembly return can cause Solar to reserve
            // this memory before any branch, exhausting the probe even for a short reply.
            return new bytes(OVERSIZED_RETURN_LENGTH);
        }
        // 96 bytes of data that does not decode as a string
        return
            abi.encodePacked(
                keccak256("garbage-one"),
                keccak256("garbage-two"),
                keccak256("garbage-three")
            );
    }
}
