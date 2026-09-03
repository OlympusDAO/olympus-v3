// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MockCCIPRouter} from "src/test/policies/bridge/mocks/MockCCIPRouter.sol";
import {MockRouterCandidate} from "src/test/policies/bridge/mocks/MockRouterCandidate.sol";

/// @notice Router candidate that answers the `typeAndVersion()` probe and also serves the ramp
///         lookups a token pool performs on its router.
/// @dev    `MockCCIPRouter` declares no `typeAndVersion()`, so a policy that probes a candidate
///         can never point a pool back at it. This mock adds the probe answer through a
///         fallback, reusing the return shapes of `MockRouterCandidate`, while inheriting the
///         on-ramp and off-ramp lookups. A stateful run can therefore install it as the pool's
///         router and keep exercising transfers afterwards. The fallback only reads state, so
///         it serves static calls; the inherited functions keep their own selectors and never
///         reach it.
contract MockVersionedCCIPRouter is MockCCIPRouter {
    error MockVersionedCCIPRouter_Reverting();

    MockRouterCandidate.ReturnMode public mode;

    function setMode(MockRouterCandidate.ReturnMode mode_) external {
        mode = mode_;
    }

    fallback(bytes calldata) external returns (bytes memory) {
        MockRouterCandidate.ReturnMode currentMode = mode;
        if (currentMode == MockRouterCandidate.ReturnMode.Reverting) {
            revert MockVersionedCCIPRouter_Reverting();
        }
        if (currentMode == MockRouterCandidate.ReturnMode.ValidVersion) {
            return abi.encode("MockVersionedCCIPRouter 1.0.0");
        }
        // 32 bytes: below the 64-byte minimum of an ABI-encoded string
        if (currentMode == MockRouterCandidate.ReturnMode.ShortReturn) {
            return abi.encodePacked(uint256(32));
        }
        // 64 bytes: the ABI encoding of the empty string
        if (currentMode == MockRouterCandidate.ReturnMode.EmptyString) return abi.encode("");
        // 96 bytes of data that does not decode as a string
        return
            abi.encodePacked(
                keccak256("versioned-garbage-one"),
                keccak256("versioned-garbage-two"),
                keccak256("versioned-garbage-three")
            );
    }
}
