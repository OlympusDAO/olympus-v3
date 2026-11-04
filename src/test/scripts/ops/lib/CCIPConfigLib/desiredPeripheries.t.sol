// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {SafeCast} from "src/libraries/SafeCast.sol";
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";
import {CCIPConfigLibTest} from "src/test/scripts/ops/lib/CCIPConfigLib/CCIPConfigLibTest.sol";

contract CCIPConfigLibTests_desiredPeripheries is CCIPConfigLibTest {
    // ========== HELPERS ========== //

    function _read(
        string memory entries_
    ) internal view returns (CCIPConfigLib.DesiredPeriphery[] memory peripheries) {
        return harness.desiredPeripheries(_envWithRoutes(entries_), LOCAL_CHAIN);
    }

    /// @notice An EVM periphery block with `extra_` appended inside the object.
    function _evmBlock(
        uint256 gasLimit_,
        string memory extra_
    ) internal pure returns (string memory extra) {
        return string.concat(',"periphery":{"gasLimit":', vm.toString(gasLimit_), extra_, "}");
    }

    /// @notice An SVM periphery block with the rig's receiver.
    function _svmBlock(uint256 gasLimit_) internal pure returns (string memory extra) {
        return
            string.concat(
                ',"periphery":{"gasLimit":',
                vm.toString(gasLimit_),
                ',"svmReceiver":"',
                vm.toString(SVM_RECEIVER),
                '"}'
            );
    }

    function _evmRouteWithBlock(
        uint256 gasLimit_
    ) internal pure returns (string memory entry) {
        return _entry(EVM_CHAIN, _routeBlock(_evmBlock(gasLimit_, "")));
    }

    function _expectRevertBelowFloor(uint256 gasLimit_) internal {
        _expectRevertMessage(
            string.concat(
                "CCIPConfigLib: the gas limit of the EVM periphery of route ",
                EVM_CHAIN,
                " is ",
                vm.toString(gasLimit_),
                ", below the floor of ",
                vm.toString(uint256(GAS_LIMIT_FLOOR))
            )
        );
    }

    // ========== EVM GAS LIMIT ========== //

    // when the EVM gas limit is one below the floor
    //   [X] it reverts naming the route and the floor
    function test_whenEvmGasLimitIsBelowFloor_reverts() public {
        _expectRevertBelowFloor(GAS_LIMIT_FLOOR - 1);
        _read(_evmRouteWithBlock(GAS_LIMIT_FLOOR - 1));
    }

    // when the EVM gas limit is zero
    //   [X] it reverts naming the route and the floor
    function test_whenEvmGasLimitIsZero_reverts() public {
        _expectRevertBelowFloor(0);
        _read(_evmRouteWithBlock(0));
    }

    // when the EVM gas limit is anywhere below the floor
    //   [X] it reverts
    function test_whenEvmGasLimitIsInInvalidInterval_reverts(uint32 gasLimit_) public {
        // The invalid interval is [0, GAS_LIMIT_FLOOR - 1]
        uint256 boundedGasLimit = bound(gasLimit_, 0, GAS_LIMIT_FLOOR - 1);

        _expectRevertBelowFloor(boundedGasLimit);
        _read(_evmRouteWithBlock(boundedGasLimit));
    }

    // when the EVM gas limit does not fit a uint32
    //   [X] it reverts with the cast overflow
    function test_whenEvmGasLimitExceedsUint32_reverts() public {
        uint256 gasLimit = uint256(type(uint32).max) + 1;

        vm.expectRevert(abi.encodeWithSelector(SafeCast.Overflow.selector, gasLimit));
        _read(_evmRouteWithBlock(gasLimit));
    }

    // when the EVM gas limit is the floor
    //   [X] it reads the block with the defaulted trusted remote
    function test_whenEvmGasLimitIsFloor() public view {
        CCIPConfigLib.DesiredPeriphery[] memory peripheries = _read(
            _evmRouteWithBlock(GAS_LIMIT_FLOOR)
        );

        assertEq(peripheries.length, 1, "peripheries.length");
        assertEq(peripheries[0].remoteChain, EVM_CHAIN, "remoteChain");
        assertEq(peripheries[0].chainSelector, EVM_SELECTOR, "chainSelector");
        assertTrue(peripheries[0].enabled, "enabled");
        assertFalse(peripheries[0].isSvm, "isSvm");
        assertEq(peripheries[0].gasLimit, GAS_LIMIT_FLOOR, "gasLimit");
        assertEq(peripheries[0].evmTrustedRemote, remoteBridge, "evmTrustedRemote");
        assertEq(peripheries[0].svmTrustedRemote, bytes32(0), "svmTrustedRemote");
    }

    // when the EVM gas limit is the largest uint32
    //   [X] it reads the block
    function test_whenEvmGasLimitIsMax() public view {
        CCIPConfigLib.DesiredPeriphery[] memory peripheries = _read(
            _evmRouteWithBlock(type(uint32).max)
        );

        assertEq(peripheries[0].gasLimit, type(uint32).max, "gasLimit");
    }

    // when the EVM gas limit is anywhere at or above the floor
    //   [X] it reads the block
    function test_whenEvmGasLimitIsInValidInterval(uint32 gasLimit_) public view {
        // The valid interval is [GAS_LIMIT_FLOOR, type(uint32).max]
        uint256 boundedGasLimit = bound(gasLimit_, GAS_LIMIT_FLOOR, type(uint32).max);

        CCIPConfigLib.DesiredPeriphery[] memory peripheries = _read(
            _evmRouteWithBlock(boundedGasLimit)
        );

        assertEq(peripheries[0].gasLimit, boundedGasLimit, "gasLimit");
    }

    // ========== TRUSTED REMOTE ========== //

    // when the EVM block overrides the trusted remote with the zero address
    //   [X] it reverts
    function test_whenEvmTrustedRemoteOverrideIsZero_reverts() public {
        string memory entry = _entry(
            EVM_CHAIN,
            _routeBlock(
                _evmBlock(
                    GAS_LIMIT_FLOOR,
                    ',"trustedRemote":"0x0000000000000000000000000000000000000000"'
                )
            )
        );

        _expectRevertMessage("CCIPConfigLib: zero trusted remote override for remote");
        _read(entry);
    }

    // when the EVM block overrides the trusted remote
    //   [X] it reads the override
    function test_whenEvmTrustedRemoteOverride() public {
        address trustedRemote = makeAddr("trustedRemote");
        string memory entry = _entry(
            EVM_CHAIN,
            _routeBlock(
                _evmBlock(
                    GAS_LIMIT_FLOOR,
                    string.concat(',"trustedRemote":"', vm.toString(trustedRemote), '"')
                )
            )
        );

        CCIPConfigLib.DesiredPeriphery[] memory peripheries = _read(entry);

        assertEq(peripheries[0].evmTrustedRemote, trustedRemote, "evmTrustedRemote");
    }

    // ========== SVM BLOCK ========== //

    // when the SVM block has no receiver
    //   [X] it reverts naming the key
    function test_whenSvmBlockHasNoReceiver_reverts() public {
        string memory entry = _entry(SVM_CHAIN, _routeBlock(_evmBlock(0, "")));

        _expectRevertMissingKey(
            ".current.local.olympus.config.CCIP.routes.solana.periphery.svmReceiver"
        );
        _read(entry);
    }

    // when the SVM gas limit is zero
    //   [X] it reads the token-only block
    function test_whenSvmGasLimitIsZero() public view {
        CCIPConfigLib.DesiredPeriphery[] memory peripheries = _read(
            _entry(SVM_CHAIN, _routeBlock(_svmBlock(0)))
        );

        assertEq(peripheries.length, 1, "peripheries.length");
        assertEq(peripheries[0].chainSelector, SVM_SELECTOR, "chainSelector");
        assertTrue(peripheries[0].enabled, "enabled");
        assertTrue(peripheries[0].isSvm, "isSvm");
        assertEq(peripheries[0].gasLimit, 0, "gasLimit");
        assertEq(peripheries[0].evmTrustedRemote, address(0), "evmTrustedRemote");
        assertEq(peripheries[0].svmTrustedRemote, SVM_RECEIVER, "svmTrustedRemote");
    }

    // when the SVM gas limit is below the EVM floor and not zero
    //   [X] it reads the block, since the floor applies to EVM blocks only
    function test_whenSvmGasLimitIsBelowEvmFloor() public view {
        CCIPConfigLib.DesiredPeriphery[] memory peripheries = _read(
            _entry(SVM_CHAIN, _routeBlock(_svmBlock(GAS_LIMIT_FLOOR - 1)))
        );

        assertEq(peripheries[0].gasLimit, GAS_LIMIT_FLOOR - 1, "gasLimit");
    }

    // ========== REMOVAL MARKERS ========== //

    // given the block is disabled
    //   [X] it reads the marker and no other field
    function test_givenBlockDisabled() public view {
        CCIPConfigLib.DesiredPeriphery[] memory peripheries = _read(
            _entry(EVM_CHAIN, _routeBlock(',"periphery":{"enabled":false}'))
        );

        assertEq(peripheries.length, 1, "peripheries.length");
        assertEq(peripheries[0].chainSelector, EVM_SELECTOR, "chainSelector");
        assertFalse(peripheries[0].enabled, "enabled");
        assertEq(peripheries[0].gasLimit, 0, "gasLimit");
        assertEq(peripheries[0].evmTrustedRemote, address(0), "evmTrustedRemote");
    }

    // given the route is marked for removal
    //   [X] it reads the marker, whatever the block says
    function test_givenRouteMarkedForRemoval() public view {
        CCIPConfigLib.DesiredPeriphery[] memory peripheries = _read(
            _entry(EVM_CHAIN, _removalBlock(_evmBlock(1, "")))
        );

        assertEq(peripheries.length, 1, "peripheries.length");
        assertFalse(peripheries[0].enabled, "enabled");
        assertEq(peripheries[0].gasLimit, 0, "gasLimit");
    }

    // ========== SELECTION ========== //

    // given no routes key
    //   [X] it returns no entry
    function test_givenNoRoutesKey() public view {
        CCIPConfigLib.DesiredPeriphery[] memory peripheries = harness.desiredPeripheries(
            _envWithConfig(GRACE_PERIOD, TIMELOCK_DELAY),
            LOCAL_CHAIN
        );

        assertEq(peripheries.length, 0, "peripheries.length");
    }

    // given a route without a periphery block next to one with a block
    //   [X] it returns the one with the block
    function test_givenRouteWithoutBlock() public view {
        CCIPConfigLib.DesiredPeriphery[] memory peripheries = _read(
            _entries(_entry(EVM_CHAIN, _routeBlock("")), _entry(SVM_CHAIN, _routeBlock(_svmBlock(0))))
        );

        assertEq(peripheries.length, 1, "peripheries.length");
        assertEq(peripheries[0].remoteChain, SVM_CHAIN, "remoteChain");
    }
}
