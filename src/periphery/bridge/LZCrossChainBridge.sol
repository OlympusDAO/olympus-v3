// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.30;

// Interfaces
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {MessagingFee} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.3.0/token/ERC20/utils/SafeERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";

// Contracts
import {PeripheryEnabler} from "src/periphery/PeripheryEnabler.sol";

/// @title LZCrossChainBridge
/// @notice Sends OHM to other chains using LayerZero V2.
/// @dev It is a periphery contract, as it does not require any privileged access to the
///      Olympus protocol. The user approves this contract for OHM, then calls sendOhm().
///      OHM is transferred to the gateway, which burns it and sends a LayerZero message.
contract LZCrossChainBridge is Owned, PeripheryEnabler, IVersioned, ILZCrossChainBridge {
    using SafeERC20 for IERC20;

    /// @inheritdoc ILZCrossChainBridge
    address public immutable override OHM;

    /// @inheritdoc ILZCrossChainBridge
    address public override gateway;

    constructor(address ohm_, address owner_) Owned(owner_) {
        _requireNonzeroAddress(ohm_, "ohm");
        _requireNonzeroAddress(owner_, "owner");

        OHM = ohm_;

        // PeripheryEnabler starts disabled; must be explicitly enabled after configuration.
    }

    /// forge-lint: disable-next-item(mixed-case-function)
    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /// @inheritdoc ILZCrossChainBridge
    function sendOhm(
        uint32 dstEid_,
        address to_,
        uint256 amount_
    ) external payable override onlyEnabled {
        if (amount_ == 0) revert LZCrossChainBridge_InsufficientAmount();

        // Transfer OHM from the user to the gateway
        IERC20(OHM).safeTransferFrom(msg.sender, gateway, amount_);

        // Gateway burns and sends via LayerZero
        ILZBridgeGateway(gateway).burnAndSend{value: msg.value}(
            dstEid_,
            to_,
            amount_,
            payable(msg.sender),
            bytes("")
        );

        emit Bridged(msg.sender, amount_, dstEid_, msg.value);
    }

    /// @inheritdoc ILZCrossChainBridge
    function setGateway(address gateway_) external override onlyOwner {
        _requireNonzeroAddress(gateway_, "gateway");

        gateway = gateway_;
        emit GatewaySet(gateway_);
    }

    /// @inheritdoc ILZCrossChainBridge
    function estimateSendFee(
        uint32 dstEid_,
        address to_,
        uint256 amount_
    ) external view override returns (MessagingFee memory fee) {
        return ILZBridgeGateway(gateway).estimateSendFee(dstEid_, to_, amount_, bytes(""));
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(PeripheryEnabler) returns (bool) {
        return
            interfaceId == type(ILZCrossChainBridge).interfaceId ||
            interfaceId == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @inheritdoc PeripheryEnabler
    function _enable(bytes calldata) internal override {}

    /// @inheritdoc PeripheryEnabler
    function _disable(bytes calldata) internal override {}

    /// @inheritdoc PeripheryEnabler
    function _onlyOwner() internal view override {
        // String literal for consistency with solmate's Owned.onlyOwner modifier
        // solhint-disable-next-line gas-custom-errors
        if (msg.sender != owner) revert("UNAUTHORIZED");
    }

    function _requireNonzeroAddress(address address_, string memory parameter_) private pure {
        if (address_ == address(0)) revert LZCrossChainBridge_InvalidAddress(parameter_);
    }
}
