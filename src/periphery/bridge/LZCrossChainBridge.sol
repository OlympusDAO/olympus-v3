// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.30;

// Interfaces
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {MessagingFee, MessagingReceipt} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.3.0/token/ERC20/utils/SafeERC20.sol";
import {Owned} from "@solmate-6.2.0/auth/Owned.sol";
import {Errors} from "src/libraries/Errors.sol";

// Contracts
import {EnablerV2} from "src/libraries/EnablerV2.sol";
import {ReEnabler} from "src/libraries/ReEnabler.sol";
import {ReEnablerGracePeriod} from "src/libraries/ReEnablerGracePeriod.sol";
import {Rescueable} from "../../bases/Rescueable.sol";

/// @title LZCrossChainBridge
/// @notice Sends OHM to other chains using LayerZero V2.
/// @dev It is a periphery contract, as it does not require any privileged access to the
///      Olympus protocol. The user approves this contract for OHM, then calls sendOhm().
///      OHM is transferred to the gateway, which burns it and sends a LayerZero message.
///
///      Authorization for the lifecycle entry points follows two roles:
///      - `enable`, `disable`, `setGateway`, and `setReEnabler` are restricted to the owner.
///      - `reEnable` is restricted to the configured `reEnabler`, which is set in the
///        constructor and may be updated or cleared by the owner via `setReEnabler`.
///        A re-enable additionally requires that the grace window since the last transition
///        has not yet elapsed.
contract LZCrossChainBridge is
    Owned,
    IVersioned,
    ReEnablerGracePeriod,
    ILZCrossChainBridge,
    Rescueable
{
    using SafeERC20 for IERC20;

    /// @inheritdoc ILZCrossChainBridge
    address public immutable override OHM;

    /// @inheritdoc ILZCrossChainBridge
    address public override gateway;

    /// @inheritdoc ILZCrossChainBridge
    address public override reEnabler;

    constructor(
        address ohm_,
        address owner_,
        address gateway_,
        address reEnabler_,
        uint32 grace_
    ) Owned(owner_) ReEnablerGracePeriod(grace_) {
        _requireNonzeroAddress(ohm_, "ohm");
        _requireNonzeroAddress(owner_, "owner");

        OHM = ohm_;
        _setGateway(gateway_);
        _setReEnabler(reEnabler_);

        // EnablerV2 starts disabled; the bridge must be explicitly enabled after
        // configuration.
    }

    /// forge-lint: disable-next-item(mixed-case-function)
    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /// @inheritdoc ILZCrossChainBridge
    /// @dev Reverts if:
    ///      - The bridge is not enabled.
    ///      - `amount_` is zero.
    ///      - The user has insufficient OHM balance or approval.
    ///      - The gateway reverts (e.g. no peer configured, rate limit exceeded, gateway not enabled).
    function sendOhm(
        uint32 dstEid_,
        address to_,
        uint256 amount_
    ) external payable override givenEnabled {
        _requireNonzeroAddress(to_, "to");
        if (amount_ == 0) revert LZCrossChainBridge_InsufficientAmount();

        // Transfer OHM from the user to the gateway
        IERC20(OHM).safeTransferFrom(msg.sender, gateway, amount_);

        // Gateway burns and sends via LayerZero
        MessagingReceipt memory receipt = ILZBridgeGateway(gateway).burnAndSend{value: msg.value}(
            dstEid_,
            to_,
            amount_,
            payable(msg.sender),
            bytes("")
        );

        emit Bridged(msg.sender, amount_, dstEid_, receipt.fee.nativeFee, msg.value);
    }

    /// @inheritdoc ILZCrossChainBridge
    /// @dev Reverts if:
    ///      - The caller is not the owner.
    ///      - `gateway_` is the zero address.
    function setGateway(address gateway_) external override onlyOwner {
        _setGateway(gateway_);
    }

    /// @inheritdoc Rescueable
    function _authorizeRescue() internal view override onlyOwner {}

    /// @inheritdoc ILZCrossChainBridge
    function setReEnabler(address reEnabler_) external override onlyOwner {
        _setReEnabler(reEnabler_);
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
    ) public view override(ReEnablerGracePeriod, Rescueable) returns (bool) {
        return
            interfaceId == type(ILZCrossChainBridge).interfaceId ||
            interfaceId == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @inheritdoc EnablerV2
    function _authorizeEnable(bytes calldata) internal view override {
        _onlyOwner();
    }

    /// @inheritdoc EnablerV2
    function _authorizeDisable(bytes calldata) internal view override {
        _onlyOwner();
    }

    /// @inheritdoc ReEnabler
    /// @dev Reverts if `msg.sender` is not the configured re-enabler. The check also rejects calls when no re-enabler
    ///      has been set (i.e. `reEnabler == address(0)`).
    function _authorizeReEnable() internal view override {
        if (msg.sender != reEnabler) revert Errors.Unauthorized(msg.sender, "reEnabler");
    }

    function _onlyOwner() private view {
        // String literal for consistency with solmate's Owned.onlyOwner modifier
        // solhint-disable-next-line gas-custom-errors
        if (msg.sender != owner) revert("UNAUTHORIZED");
    }

    function _setGateway(address gateway_) private {
        _requireNonzeroAddress(gateway_, "gateway");
        gateway = gateway_;
        emit GatewaySet(gateway_);
    }

    function _setReEnabler(address reEnabler_) private {
        reEnabler = reEnabler_;
        emit ReEnablerSet(reEnabler_);
    }

    function _requireNonzeroAddress(address address_, string memory parameter_) private pure {
        if (address_ == address(0)) revert LZCrossChainBridge_InvalidAddress(parameter_);
    }
}
