// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

// The malformed remote values of each scenario are written beside the scenario they shape
// forge-lint: disable-start(literal-instead-of-constant)

import {Base58} from "@base58-solidity-1.0.3/Base58.sol";
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";
import {CCIPConfigLibTest} from "src/test/scripts/ops/lib/CCIPConfigLib/CCIPConfigLibTest.sol";

contract CCIPConfigLibTests_desiredRoutes is CCIPConfigLibTest {
    // ========== HELPERS ========== //

    function _read(
        string memory entries_
    ) internal view returns (CCIPConfigLib.DesiredRoute[] memory routes) {
        return harness.desiredRoutes(_envWithRoutes(entries_), LOCAL_CHAIN);
    }

    function _evmRoute(string memory extra_) internal pure returns (string memory entry) {
        return _entry(EVM_CHAIN, _routeBlock(extra_));
    }

    function _svmRoute(string memory extra_) internal pure returns (string memory entry) {
        return _entry(SVM_CHAIN, _routeBlock(extra_));
    }

    function _tokenOverride(bytes memory value_) internal pure returns (string memory extra) {
        return string.concat(',"remoteToken":"', vm.toString(value_), '"');
    }

    function _poolsOverride(bytes[] memory values_) internal pure returns (string memory extra) {
        extra = ',"remotePools":[';
        for (uint256 i; i < values_.length; ++i) {
            // A fixture builder: the cheatcode formats each entry of the JSON array
            // forge-lint: disable-next-line(calls-loop)
            extra = string.concat(extra, i == 0 ? '"' : ',"', vm.toString(values_[i]), '"');
        }
        extra = string.concat(extra, "]");
    }

    function _single(bytes memory value_) internal pure returns (bytes[] memory values) {
        values = new bytes[](1);
        values[0] = value_;
    }

    /// @notice A 32-byte value with the given numeric value.
    function _word(uint256 value_) internal pure returns (bytes memory word) {
        return abi.encode(value_);
    }

    function _expectRevertShape(
        string memory label_,
        string memory remoteChain_,
        bytes memory value_
    ) internal {
        _expectRevertMessage(
            string.concat(
                "CCIPConfigLib: the ",
                label_,
                " of route ",
                remoteChain_,
                " is not a left-padded EVM address at or above ",
                vm.toString(MIN_EVM_REMOTE_ADDRESS),
                ": ",
                vm.toString(value_)
            )
        );
    }

    function _expectRevertLength(
        string memory label_,
        string memory remoteChain_,
        uint256 length_
    ) internal {
        _expectRevertMessage(
            string.concat(
                "CCIPConfigLib: the ",
                label_,
                " of route ",
                remoteChain_,
                " is ",
                vm.toString(length_),
                " bytes long, expected 32"
            )
        );
    }

    // ========== REMOTE TOKEN OVERRIDE: EVM SHAPE ========== //

    // when the remote token override toward the EVM chain carries dirty high bytes
    //   [X] it reverts naming the route and the field
    function test_whenEvmRemoteTokenHasDirtyHighBytes_reverts() public {
        bytes memory value = _word(uint256(uint160(remoteOhm)) | (1 << 160));

        _expectRevertShape("remote token", EVM_CHAIN, value);
        _read(_evmRoute(_tokenOverride(value)));
    }

    // when the remote token override toward the EVM chain is one below the precompile bound
    //   [X] it reverts
    function test_whenEvmRemoteTokenIsBelowBound_reverts() public {
        bytes memory value = _word(MIN_EVM_REMOTE_ADDRESS - 1);

        _expectRevertShape("remote token", EVM_CHAIN, value);
        _read(_evmRoute(_tokenOverride(value)));
    }

    // when the remote token override toward the EVM chain is 32 zero bytes
    //   [X] it reverts with the shape message, since the length is right
    function test_whenEvmRemoteTokenIsZeroWord_reverts() public {
        bytes memory value = _word(0);

        _expectRevertShape("remote token", EVM_CHAIN, value);
        _read(_evmRoute(_tokenOverride(value)));
    }

    // when the remote token override toward the EVM chain is anywhere below the bound
    //   [X] it reverts
    function test_whenEvmRemoteTokenIsInLowerInvalidInterval_reverts(uint256 value_) public {
        // The invalid interval is [0, MIN_EVM_REMOTE_ADDRESS - 1]
        bytes memory value = _word(bound(value_, 0, MIN_EVM_REMOTE_ADDRESS - 1));

        _expectRevertShape("remote token", EVM_CHAIN, value);
        _read(_evmRoute(_tokenOverride(value)));
    }

    // when the remote token override toward the EVM chain exceeds an address by one
    //   [X] it reverts
    function test_whenEvmRemoteTokenExceedsAddress_reverts() public {
        bytes memory value = _word(uint256(type(uint160).max) + 1);

        _expectRevertShape("remote token", EVM_CHAIN, value);
        _read(_evmRoute(_tokenOverride(value)));
    }

    // when the remote token override toward the EVM chain is anywhere above an address
    //   [X] it reverts
    function test_whenEvmRemoteTokenIsInUpperInvalidInterval_reverts(uint256 value_) public {
        // The invalid interval is [type(uint160).max + 1, type(uint256).max]
        bytes memory value = _word(
            bound(value_, uint256(type(uint160).max) + 1, type(uint256).max)
        );

        _expectRevertShape("remote token", EVM_CHAIN, value);
        _read(_evmRoute(_tokenOverride(value)));
    }

    // when the remote token override toward the EVM chain is 20 bytes
    //   [X] it reverts with the length message
    function test_whenEvmRemoteTokenIs20Bytes_reverts() public {
        bytes memory value = abi.encodePacked(remoteOhm);

        _expectRevertLength("remote token", EVM_CHAIN, 20);
        _read(_evmRoute(_tokenOverride(value)));
    }

    // when the remote token override toward the EVM chain is the precompile bound
    //   [X] it reads the override
    function test_whenEvmRemoteTokenIsBound() public view {
        bytes memory value = _word(MIN_EVM_REMOTE_ADDRESS);

        CCIPConfigLib.DesiredRoute[] memory routes = _read(_evmRoute(_tokenOverride(value)));

        assertEq(routes[0].remoteToken, value, "remoteToken");
    }

    // when the remote token override toward the EVM chain is the largest address
    //   [X] it reads the override
    function test_whenEvmRemoteTokenIsMaxAddress() public view {
        bytes memory value = _word(type(uint160).max);

        CCIPConfigLib.DesiredRoute[] memory routes = _read(_evmRoute(_tokenOverride(value)));

        assertEq(routes[0].remoteToken, value, "remoteToken");
    }

    // when the remote token override toward the EVM chain is anywhere in the address range
    //   [X] it reads the override
    function test_whenEvmRemoteTokenIsInValidInterval(uint256 value_) public view {
        // The valid interval is [MIN_EVM_REMOTE_ADDRESS, type(uint160).max]
        bytes memory value = _word(bound(value_, MIN_EVM_REMOTE_ADDRESS, type(uint160).max));

        CCIPConfigLib.DesiredRoute[] memory routes = _read(_evmRoute(_tokenOverride(value)));

        assertEq(routes[0].remoteToken, value, "remoteToken");
    }

    // given the default remote token of the EVM chain is in the precompile range
    //   [X] it reverts naming the route and the field, since the defaults are checked too
    function test_givenDefaultEvmRemoteTokenIsBelowBound_reverts() public {
        // casting to 'uint160' is safe because the value is below the 1024 bound
        // forge-lint: disable-next-line(unsafe-typecast)
        remoteOhm = address(uint160(MIN_EVM_REMOTE_ADDRESS - 1));

        _expectRevertShape("remote token", EVM_CHAIN, abi.encode(remoteOhm));
        _read(_evmRoute(""));
    }

    // ========== REMOTE POOLS OVERRIDE: EVM SHAPE ========== //

    // when a remote pool override toward the EVM chain carries dirty high bytes
    //   [X] it reverts naming the route and the field
    function test_whenEvmRemotePoolHasDirtyHighBytes_reverts() public {
        bytes memory value = _word(uint256(uint160(remotePool)) | (1 << 200));

        _expectRevertShape("remote pool", EVM_CHAIN, value);
        _read(_evmRoute(_poolsOverride(_single(value))));
    }

    // when a remote pool override toward the EVM chain is below the precompile bound
    //   [X] it reverts
    function test_whenEvmRemotePoolIsBelowBound_reverts() public {
        bytes memory value = _word(MIN_EVM_REMOTE_ADDRESS - 1);

        _expectRevertShape("remote pool", EVM_CHAIN, value);
        _read(_evmRoute(_poolsOverride(_single(value))));
    }

    // when the second of two remote pool overrides toward the EVM chain is malformed
    //   [X] it reverts naming the field
    function test_whenSecondEvmRemotePoolIsMalformed_reverts() public {
        bytes[] memory values = new bytes[](2);
        values[0] = abi.encode(remotePool);
        values[1] = _word(uint256(type(uint160).max) + 1);

        _expectRevertShape("remote pool", EVM_CHAIN, values[1]);
        _read(_evmRoute(_poolsOverride(values)));
    }

    // when a remote pool override toward the EVM chain is 31 bytes
    //   [X] it reverts with the length message
    function test_whenEvmRemotePoolIs31Bytes_reverts() public {
        bytes memory value = new bytes(31);

        _expectRevertLength("remote pool", EVM_CHAIN, 31);
        _read(_evmRoute(_poolsOverride(_single(value))));
    }

    // given the default remote pool of the EVM chain is in the precompile range
    //   [X] it reverts naming the route and the field, since the defaults are checked too
    function test_givenDefaultEvmRemotePoolIsBelowBound_reverts() public {
        // casting to 'uint160' is safe because the value is below the 1024 bound
        // forge-lint: disable-next-line(unsafe-typecast)
        remotePool = address(uint160(MIN_EVM_REMOTE_ADDRESS - 1));

        _expectRevertShape("remote pool", EVM_CHAIN, abi.encode(remotePool));
        _read(_evmRoute(""));
    }

    // when the remote pools override is empty
    //   [X] it reverts
    function test_whenRemotePoolsOverrideIsEmpty_reverts() public {
        _expectRevertMessage("CCIPConfigLib: no remote pools for route remote");
        _read(_evmRoute(',"remotePools":[]'));
    }

    // when two clean remote pool overrides are declared toward the EVM chain
    //   [X] it reads both in order
    function test_whenTwoEvmRemotePools() public {
        bytes[] memory values = new bytes[](2);
        values[0] = abi.encode(remotePool);
        values[1] = abi.encode(makeAddr("secondRemotePool"));

        CCIPConfigLib.DesiredRoute[] memory routes = _read(_evmRoute(_poolsOverride(values)));

        assertEq(routes[0].remotePools.length, 2, "remotePools.length");
        assertEq(routes[0].remotePools[0], values[0], "remotePools[0]");
        assertEq(routes[0].remotePools[1], values[1], "remotePools[1]");
    }

    // ========== OVERRIDES TOWARD THE SVM CHAIN ========== //

    // when the remote token override toward the SVM chain carries non-zero high bytes
    //   [X] it reads the override, since an SVM value is any 32 bytes
    function test_whenSvmRemoteTokenHasHighBytes() public view {
        bytes memory value = _word(type(uint256).max);

        CCIPConfigLib.DesiredRoute[] memory routes = _read(_svmRoute(_tokenOverride(value)));

        assertEq(routes[0].remoteToken, value, "remoteToken");
    }

    // when a remote pool override toward the SVM chain is below the EVM bound
    //   [X] it reads the override
    function test_whenSvmRemotePoolIsBelowEvmBound() public view {
        bytes memory value = _word(1);

        CCIPConfigLib.DesiredRoute[] memory routes = _read(
            _svmRoute(_poolsOverride(_single(value)))
        );

        assertEq(routes[0].remotePools.length, 1, "remotePools.length");
        assertEq(routes[0].remotePools[0], value, "remotePools[0]");
    }

    // when the remote token override toward the SVM chain is 33 bytes
    //   [X] it reverts with the length message
    function test_whenSvmRemoteTokenIs33Bytes_reverts() public {
        bytes memory value = new bytes(33);

        _expectRevertLength("remote token", SVM_CHAIN, 33);
        _read(_svmRoute(_tokenOverride(value)));
    }

    // ========== LIMITS ========== //

    // when the outbound limiter is disabled
    //   [X] it reverts
    function test_whenOutboundLimiterIsDisabled_reverts() public {
        string memory entry = _entry(
            EVM_CHAIN,
            _routeBlockWithLimits(
                _limitBlock(false, 0, 0),
                _limitBlock(true, IN_CAPACITY, IN_RATE),
                ""
            )
        );

        _expectRevertMessage("CCIPConfigLib: outbound rate limit of route remote is disabled");
        _read(entry);
    }

    // when the inbound limiter is the containment pair
    //   [X] it reverts
    function test_whenInboundLimiterIsContainmentPair_reverts() public {
        string memory entry = _entry(
            EVM_CHAIN,
            _routeBlockWithLimits(
                _limitBlock(true, OUT_CAPACITY, OUT_RATE),
                _limitBlock(true, 2, 1),
                ""
            )
        );

        _expectRevertMessage(
            "CCIPConfigLib: inbound rate limit of route remote is the disabled rate limiter configuration of the containment functions"
        );
        _read(entry);
    }

    // ========== DEFAULTS ========== //

    // given no routes key
    //   [X] it returns no route
    function test_givenNoRoutesKey() public view {
        CCIPConfigLib.DesiredRoute[] memory routes = harness.desiredRoutes(
            _envWithConfig(GRACE_PERIOD, TIMELOCK_DELAY),
            LOCAL_CHAIN
        );

        assertEq(routes.length, 0, "routes.length");
    }

    // given an EVM route without overrides
    //   [X] it reads the selector, the ABI-encoded OHM and burn/mint pool and both limits
    function test_givenEvmRouteWithoutOverrides() public view {
        CCIPConfigLib.DesiredRoute[] memory routes = _read(_evmRoute(""));

        assertEq(routes.length, 1, "routes.length");
        assertEq(routes[0].remoteChain, EVM_CHAIN, "remoteChain");
        assertEq(routes[0].chainSelector, EVM_SELECTOR, "chainSelector");
        assertTrue(routes[0].enabled, "enabled");
        assertEq(routes[0].remoteToken, abi.encode(remoteOhm), "remoteToken");
        assertEq(routes[0].remotePools.length, 1, "remotePools.length");
        assertEq(routes[0].remotePools[0], abi.encode(remotePool), "remotePools[0]");
        _assertConfig(routes[0].outbound, true, OUT_CAPACITY, OUT_RATE, "outbound");
        _assertConfig(routes[0].inbound, true, IN_CAPACITY, IN_RATE, "inbound");
    }

    // given an SVM route without overrides
    //   [X] it reads the base58 mint and pool as 32 packed bytes
    function test_givenSvmRouteWithoutOverrides() public view {
        CCIPConfigLib.DesiredRoute[] memory routes = _read(_svmRoute(""));

        assertEq(routes.length, 1, "routes.length");
        assertEq(routes[0].chainSelector, SVM_SELECTOR, "chainSelector");
        assertEq(routes[0].remoteToken, Base58.decodeFromString(SVM_OHM), "remoteToken");
        assertEq(routes[0].remoteToken.length, 32, "remoteToken.length");
        assertEq(routes[0].remotePools.length, 1, "remotePools.length");
        assertEq(routes[0].remotePools[0], Base58.decodeFromString(SVM_POOL), "remotePools[0]");
        assertEq(routes[0].remotePools[0].length, 32, "remotePools[0].length");
    }

    // given a route marked for removal
    //   [X] it reads the name, the selector and the marker and nothing else
    function test_givenRouteMarkedForRemoval() public view {
        CCIPConfigLib.DesiredRoute[] memory routes = _read(_entry(EVM_CHAIN, _removalBlock("")));

        assertEq(routes.length, 1, "routes.length");
        assertEq(routes[0].remoteChain, EVM_CHAIN, "remoteChain");
        assertEq(routes[0].chainSelector, EVM_SELECTOR, "chainSelector");
        assertFalse(routes[0].enabled, "enabled");
        assertEq(routes[0].remoteToken.length, 0, "remoteToken.length");
        assertEq(routes[0].remotePools.length, 0, "remotePools.length");
        _assertConfig(routes[0].outbound, false, 0, 0, "outbound");
    }

    // given two routes declared out of name order
    //   [X] it returns them sorted by name
    function test_givenTwoRoutes() public view {
        CCIPConfigLib.DesiredRoute[] memory routes = _read(
            _entries(_svmRoute(""), _evmRoute(""))
        );

        assertEq(routes.length, 2, "routes.length");
        assertEq(routes[0].remoteChain, EVM_CHAIN, "routes[0].remoteChain");
        assertEq(routes[1].remoteChain, SVM_CHAIN, "routes[1].remoteChain");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
