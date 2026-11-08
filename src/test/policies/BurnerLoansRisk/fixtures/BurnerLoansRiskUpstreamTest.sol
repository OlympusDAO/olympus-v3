// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "src/test/policies/BurnerLoansRiskConfigTimelock/BurnerLoansRiskConfigTimelockTest.sol";

/// @dev Real Core/Config/controller identities; Risk remains active and locally enabled.
abstract contract BurnerLoansRiskUpstreamTest is BurnerLoansRiskConfigTimelockTest {
    struct UpstreamState {
        bool controllerActive;
        bool controllerEnabled;
        bool configActive;
        bool configEnabled;
        bool coreActive;
        bool coreEnabled;
    }

    function _setUpstreamState(UpstreamState memory state_) internal {
        _setState(_timelock, state_.controllerActive, state_.controllerEnabled);
        _setState(_config, state_.configActive, state_.configEnabled);
        _setState(_core, state_.coreActive, state_.coreEnabled);
        _forbidMetadata(address(_timelock), abi.encodeWithSignature("kernel()"));
        _forbidMetadata(address(_timelock), abi.encodeWithSignature("isEnabled()"));
        _forbidMetadata(address(_config), abi.encodeWithSignature("kernel()"));
        _forbidMetadata(address(_config), abi.encodeWithSignature("isEnabled()"));
        _forbidMetadata(address(_config), abi.encodeWithSignature("facility()"));
        _forbidMetadata(address(_config), abi.encodeWithSignature("configOperator()"));
        _forbidMetadata(address(_core), abi.encodeWithSignature("kernel()"));
        _forbidMetadata(address(_core), abi.encodeWithSignature("isEnabled()"));
        _forbidMetadata(address(_core), abi.encodeWithSignature("risk()"));
        _forbidMetadata(address(_core), abi.encodeWithSignature("configOperator()"));
    }

    function _forbidMetadata(address target_, bytes memory call_) private {
        vm.mockCallRevert(target_, call_, hex"deadbeef");
    }

    function _expectNoUpstreamMetadataCalls() internal {
        vm.expectCall(address(_timelock), abi.encodeWithSignature("kernel()"), uint64(0));
        vm.expectCall(address(_timelock), abi.encodeWithSignature("isEnabled()"), uint64(0));
        vm.expectCall(address(_config), abi.encodeWithSignature("kernel()"), uint64(0));
        vm.expectCall(address(_config), abi.encodeWithSignature("isEnabled()"), uint64(0));
        vm.expectCall(address(_config), abi.encodeWithSignature("facility()"), uint64(0));
        vm.expectCall(address(_config), abi.encodeWithSignature("configOperator()"), uint64(0));
        vm.expectCall(address(_core), abi.encodeWithSignature("kernel()"), uint64(0));
        vm.expectCall(address(_core), abi.encodeWithSignature("isEnabled()"), uint64(0));
        vm.expectCall(address(_core), abi.encodeWithSignature("risk()"), uint64(0));
        vm.expectCall(address(_core), abi.encodeWithSignature("configOperator()"), uint64(0));
    }

    function _upstreamState(uint8 bits_) internal pure returns (UpstreamState memory) {
        return
            UpstreamState(
                (bits_ & 1) != 0,
                (bits_ & 2) != 0,
                (bits_ & 4) != 0,
                (bits_ & 8) != 0,
                (bits_ & 16) != 0,
                (bits_ & 32) != 0
            );
    }

    function _unaffectedAccounting() internal view returns (bytes32) {
        uint32 market = _core.marketId(address(_asset));
        bytes32 marketState = keccak256(
            abi.encode(
                _floan.getMarket(market),
                _floan.getMarketConfigData(market),
                _floan.getMarketPrincipalDue(market)
            )
        );
        bytes32 custody = keccak256(
            abi.encode(
                _asset.balanceOf(address(_core)),
                _asset.balanceOf(address(_payout)),
                _payout.pendingReferralFee(address(_asset), _recipient)
            )
        );
        return keccak256(abi.encode(marketState, custody));
    }
}
