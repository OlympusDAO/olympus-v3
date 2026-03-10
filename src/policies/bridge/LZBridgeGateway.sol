// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.30;

// Interfaces
import {ILayerZeroUserApplicationConfig} from "@layer-zero-endpoint-v1-1.1.0/lzApp/interfaces/ILayerZeroUserApplicationConfig.sol";
import {ILayerZeroEndpoint} from "@layer-zero-endpoint-v1-1.1.0/lzApp/interfaces/ILayerZeroEndpoint.sol";
import {ILayerZeroReceiver} from "@layer-zero-endpoint-v1-1.1.0/lzApp/interfaces/ILayerZeroReceiver.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Libraries
import {BytesLib} from "@layer-zero-endpoint-v1-1.1.0/libraries/BytesLib.sol";

// Contracts
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title LZBridgeGateway
/// @notice Infrastructure policy handling LayerZero endpoint communication for cross-chain
///         OHM transfers.
///         Performs OHM mint/burn via MINTR, manages trusted remotes, and enforces a bridged
///         supply cap on canonical (mainnet) chains.
contract LZBridgeGateway is
    Policy,
    PolicyEnabler,
    IVersioned,
    ILayerZeroReceiver,
    ILayerZeroUserApplicationConfig,
    ILZBridgeGateway
{
    using BytesLib for bytes;

    // ========= CONSTANTS ========= //

    /// @notice Role required for LayerZero endpoint configuration and bridged supply setting.
    bytes32 private constant _BRIDGE_ADMIN_ROLE = "bridge_admin";

    /// @inheritdoc ILZBridgeGateway
    uint8 public constant override MSG_BRIDGE_OHM = 1;

    /// @notice Placeholder for the ZRO token payment address (unused).
    address private constant _ZRO_PAYMENT_ADDRESS = address(0);

    /// @notice Expected byte length of an ABI-encoded (address, uint256) bridge payload.
    uint256 private constant _BRIDGE_OHM_DATA_LENGTH = 64;

    /// @notice Byte length of an EVM address, used to extract the remote address from a trusted path.
    uint256 private constant _EVM_ADDRESS_LENGTH = 20;

    // ========= IMMUTABLES ========= //

    /// @inheritdoc ILZBridgeGateway
    address public immutable override LZ_ENDPOINT;

    /// @inheritdoc ILZBridgeGateway
    bool public immutable override IS_CANONICAL;

    // ========= STATE ========= //

    /// @notice Bophades module for minting and burning OHM.
    MINTRv1 public MINTR;

    /// @inheritdoc ILZBridgeGateway
    address public override ohm;

    /// @inheritdoc ILZBridgeGateway
    address public override facilitator;

    /// @inheritdoc ILZBridgeGateway
    address public override precrime; // Currently unused

    /// @inheritdoc ILZBridgeGateway
    uint256 public override bridgedSupply;

    /// @inheritdoc ILZBridgeGateway
    uint256 public override bridgedSupplyCap;

    /// @inheritdoc ILZBridgeGateway
    /// @dev path = abi.encodePacked(remoteAddress, localAddress).
    mapping(uint16 chainId_ => bytes path) public override trustedRemoteLookup;

    /// @inheritdoc ILZBridgeGateway
    mapping(uint16 chainId_ => mapping(bytes srcAddress_ => mapping(uint64 nonce_ => bytes32 payloadHash)))
        public
        override failedMessages; // Used for retry

    // ========= INITIALIZATION & POLICY SETUP ========= //

    constructor(
        Kernel kernel_,
        address lzEndpoint_,
        bool isCanonical_,
        address facilitator_
    ) Policy(kernel_) {
        _requireNonzeroAddress(address(kernel_), "kernel");
        _requireNonzeroAddress(lzEndpoint_, "lzEndpoint");

        LZ_ENDPOINT = lzEndpoint_;
        IS_CANONICAL = isCanonical_;

        _setFacilitator(facilitator_);

        // Disabled by default
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("ROLES");

        MINTRv1 mintr = MINTRv1(getModuleAddress(dependencies[0]));
        ROLESv1 roles = ROLESv1(getModuleAddress(dependencies[1]));

        // Ensure modules are using the expected major version. Modules should be sorted in alphabetical order.
        (uint8 major, ) = mintr.VERSION();
        if (major != 1) revert Policy_WrongModuleVersion(abi.encode([1, 1]));
        (major, ) = roles.VERSION();
        if (major != 1) revert Policy_WrongModuleVersion(abi.encode([1, 1]));

        MINTR = mintr;
        ROLES = roles;

        // Set OHM from MINTR
        ohm = address(MINTR.ohm());
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](3);
        Keycode kc = MINTR.KEYCODE();
        permissions[0] = Permissions({keycode: kc, funcSelector: MINTRv1.mintOhm.selector});
        permissions[1] = Permissions({keycode: kc, funcSelector: MINTRv1.burnOhm.selector});
        permissions[2] = Permissions({
            keycode: kc,
            funcSelector: MINTRv1.increaseMintApproval.selector
        });
    }

    /// forge-lint: disable-next-item(mixed-case-function)
    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========= MODIFIERS ========= //

    modifier onlyFacilitator() {
        _onlyFacilitator();
        _;
    }

    function _onlyFacilitator() internal view {
        if (msg.sender != facilitator) revert LZBridgeGateway_OnlyFacilitator();
    }

    // ========= OHM BRIDGING ========= //

    /// @inheritdoc ILZBridgeGateway
    function burnAndSend(
        uint16 dstChainId_,
        address to_,
        uint256 amount_,
        address payable refundAddress_,
        bytes calldata adapterParams_
    ) external payable override onlyEnabled onlyFacilitator {
        // Warning. amount_ == 0 should be ensured by the facilitator
        _requireNonzeroAddress(to_, "to");

        bytes memory trustedRemote = trustedRemoteLookup[dstChainId_];
        if (trustedRemote.length == 0) revert LZBridgeGateway_DestinationNotTrusted();

        // Track bridged supply on canonical chain
        if (IS_CANONICAL) {
            uint256 newSupply = bridgedSupply + amount_;
            if (newSupply > bridgedSupplyCap)
                revert LZBridgeGateway_BridgedSupplyCapExceeded(newSupply, bridgedSupplyCap);
            bridgedSupply = newSupply;
            emit BridgedSupplyIncreased(amount_);
        }

        // Burn OHM held by the gateway (transferred here by the facilitator)
        // solhint-disable-next-line no-unused-vars
        IERC20(ohm).approve(address(MINTR), amount_);
        MINTR.burnOhm(address(this), amount_);

        // Encode and send the bridge message
        bytes memory payload = abi.encode(MSG_BRIDGE_OHM, abi.encode(to_, amount_));
        // solhint-disable-next-line
        ILayerZeroEndpoint(LZ_ENDPOINT).send{value: msg.value}(
            dstChainId_,
            trustedRemote,
            payload,
            refundAddress_,
            _ZRO_PAYMENT_ADDRESS,
            adapterParams_
        );
    }

    // ========= FEE ESTIMATION ========= //

    /// @inheritdoc ILZBridgeGateway
    function estimateSendFee(
        uint16 dstChainId_,
        address to_,
        uint256 amount_,
        bytes calldata adapterParams_
    ) external view override returns (uint256 nativeFee, uint256 zroFee) {
        bytes memory payload = abi.encode(MSG_BRIDGE_OHM, abi.encode(to_, amount_));
        return
            ILayerZeroEndpoint(LZ_ENDPOINT).estimateFees(
                dstChainId_,
                address(this),
                payload,
                false,
                adapterParams_
            );
    }

    // ========= LZ RECEIVE FUNCTIONS ========= //

    /// @inheritdoc ILayerZeroReceiver
    function lzReceive(
        uint16 srcChainId_,
        bytes calldata srcAddress_,
        uint64 nonce_,
        bytes calldata payload_
    ) public override onlyEnabled {
        _requireCaller(LZ_ENDPOINT); // lzReceive must be called by the endpoint for security
        _validateTrustedRemote(srcChainId_, srcAddress_);

        try this.receiveMessage(srcChainId_, srcAddress_, nonce_, payload_) {
            // Success
        } catch (bytes memory reason) {
            failedMessages[srcChainId_][srcAddress_][nonce_] = keccak256(payload_);
            emit MessageFailed(srcChainId_, srcAddress_, nonce_, payload_, reason);
        }
    }

    /// @inheritdoc ILZBridgeGateway
    function receiveMessage(
        uint16 srcChainId_,
        bytes memory,
        uint64,
        bytes memory payload_
    ) public override {
        _requireCaller(address(this)); // Restrict access to low-level call from lzReceive
        _decodeAndRoute(srcChainId_, payload_);
    }

    /// @inheritdoc ILZBridgeGateway
    function retryMessage(
        uint16 srcChainId_,
        bytes calldata srcAddress_,
        uint64 nonce_,
        bytes calldata payload_
    ) public override onlyEnabled {
        // Re-validate trusted remote
        _validateTrustedRemote(srcChainId_, srcAddress_);

        // Assert there is a message to retry
        bytes32 payloadHash = failedMessages[srcChainId_][srcAddress_][nonce_];
        if (payloadHash == bytes32(0)) revert LZBridgeGateway_NoStoredMessage();
        if (keccak256(payload_) != payloadHash) revert LZBridgeGateway_InvalidPayload();

        // Clear the stored message
        delete failedMessages[srcChainId_][srcAddress_][nonce_];

        _decodeAndRoute(srcChainId_, payload_);
        emit RetryMessageSuccess(srcChainId_, srcAddress_, nonce_, payloadHash);
    }

    // ========= ADMIN FUNCTIONS ========= //

    /// @inheritdoc ILZBridgeGateway
    function setFacilitator(address facilitator_) external override onlyAdminRole {
        _setFacilitator(facilitator_);
    }

    /// @inheritdoc ILZBridgeGateway
    function setBridgedSupplyCap(uint256 bridgedSupplyCap_) external override onlyAdminRole {
        _requireCanonical();
        bridgedSupplyCap = bridgedSupplyCap_;
        emit BridgedSupplyCapSet(bridgedSupplyCap_);
    }

    /// @inheritdoc ILZBridgeGateway
    function setTrustedRemote(
        uint16 remoteChainId_,
        address remoteAddress_
    ) external override onlyAdminRole {
        bytes memory path = remoteAddress_ != address(0)
            ? abi.encodePacked(remoteAddress_, address(this))
            : bytes("");
        trustedRemoteLookup[remoteChainId_] = path;
        emit TrustedRemoteSet(remoteChainId_, path);
    }

    /// @inheritdoc ILZBridgeGateway
    function setPrecrime(address precrime_) external override onlyAdminRole {
        precrime = precrime_;
        emit PrecrimeSet(precrime_);
    }

    /// @inheritdoc ILZBridgeGateway
    function setBridgedSupply(
        uint256 bridgedSupply_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        _requireCanonical();
        bridgedSupply = bridgedSupply_;
        emit BridgedSupplySet(bridgedSupply_);
    }

    /// @inheritdoc ILayerZeroUserApplicationConfig
    function setConfig(
        uint16 version_,
        uint16 chainId_,
        uint256 configType_,
        bytes calldata config_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpoint(LZ_ENDPOINT).setConfig(version_, chainId_, configType_, config_);
    }

    /// @inheritdoc ILayerZeroUserApplicationConfig
    function setSendVersion(uint16 version_) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpoint(LZ_ENDPOINT).setSendVersion(version_);
    }

    /// @inheritdoc ILayerZeroUserApplicationConfig
    function setReceiveVersion(uint16 version_) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpoint(LZ_ENDPOINT).setReceiveVersion(version_);
    }

    /// @inheritdoc ILayerZeroUserApplicationConfig
    /// @dev Clears the blocked payload at the endpoint level without executing it.
    ///
    ///      On canonical chains, `bridgedSupply` will NOT be decremented for the dropped message,
    ///      leaving it over-counted relative to actual supply.
    ///
    ///      Required recovery procedure:
    ///      1. Retrieve the blocked payload from the `PayloadStored` event on the LZ endpoint or via LayerZero Scan.
    ///      2. Decode `(uint8 msgType, bytes data)` from the payload, then decode
    ///         `(address to, uint256 amount)` from `data`.
    ///      3. Call `forceResumeReceive` to unblock the channel.
    ///      4. On canonical chains, call `setBridgedSupply(bridgedSupply - amount)` to correct
    ///         the supply accounting.
    ///      5. Compensate the user for the lost OHM via governance in any way.
    ///
    ///      Prefer `retryPayload` whenever possible.
    function forceResumeReceive(
        uint16 srcChainId_,
        bytes calldata srcAddress_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpoint(LZ_ENDPOINT).forceResumeReceive(srcChainId_, srcAddress_);
    }

    // ========= OTHER VIEW FUNCTIONS ========= //

    /// @inheritdoc ILZBridgeGateway
    function getConfig(
        uint16 version_,
        uint16 chainId_,
        address,
        uint256 configType_
    ) external view override returns (bytes memory) {
        return
            ILayerZeroEndpoint(LZ_ENDPOINT).getConfig(
                version_,
                chainId_,
                address(this),
                configType_
            );
    }

    /// @inheritdoc ILZBridgeGateway
    function getTrustedRemote(uint16 remoteChainId_) external view override returns (address) {
        bytes memory path = trustedRemoteLookup[remoteChainId_];
        if (path.length == 0) revert LZBridgeGateway_NoTrustedPath();

        // Extract the remote address (first 20 bytes of the path)
        return address(bytes20(path.slice(0, _EVM_ADDRESS_LENGTH)));
    }

    /// @inheritdoc ILZBridgeGateway
    function isTrustedRemote(
        uint16 srcChainId_,
        bytes calldata srcAddress_
    ) external view override returns (bool) {
        bytes memory trustedSource = trustedRemoteLookup[srcChainId_];
        if (srcAddress_.length == 0 || trustedSource.length == 0)
            revert LZBridgeGateway_TrustedRemoteUninitialized();
        return (srcAddress_.length == trustedSource.length &&
            keccak256(srcAddress_) == keccak256(trustedSource));
    }

    // ========= ERC165 ========= //

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(PolicyEnabler) returns (bool) {
        return
            interfaceId == type(ILZBridgeGateway).interfaceId ||
            interfaceId == type(ILayerZeroReceiver).interfaceId ||
            interfaceId == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // ========= PRIVATE FUNCTIONS ========= //

    /// @notice Decodes the message type from the payload and routes to the appropriate handler.
    function _decodeAndRoute(uint16 srcChainId_, bytes memory payload_) private {
        (uint8 msgType, bytes memory data) = abi.decode(payload_, (uint8, bytes));

        if (msgType == MSG_BRIDGE_OHM) {
            _receiveBridgeOhm(srcChainId_, data);
        } else {
            revert LZBridgeGateway_InvalidMessageType(msgType);
        }
    }

    /// @notice Processes a received OHM bridge message.
    /// @dev On canonical chains, decrements bridgedSupply. Mints OHM to the recipient.
    function _receiveBridgeOhm(uint16 srcChainId_, bytes memory data_) private {
        if (data_.length != _BRIDGE_OHM_DATA_LENGTH) revert LZBridgeGateway_InvalidPayload();
        (address to, uint256 amount) = abi.decode(data_, (address, uint256));

        // Track bridged supply on canonical chain
        if (IS_CANONICAL) {
            if (bridgedSupply < amount)
                revert LZBridgeGateway_BridgedSupplyUnderflow(bridgedSupply, amount);
            unchecked {
                bridgedSupply -= amount;
            }
            emit BridgedSupplyDecreased(amount);
        }

        MINTR.increaseMintApproval(address(this), amount);
        MINTR.mintOhm(to, amount);

        emit Received(to, amount, srcChainId_);
    }

    function _setFacilitator(address facilitator_) private {
        _requireNonzeroAddress(facilitator_, "facilitator");
        facilitator = facilitator_;
        emit FacilitatorSet(facilitator_);
    }

    /// @notice Validates that the source address matches the trusted remote for the given chain.
    function _validateTrustedRemote(uint16 srcChainId_, bytes calldata srcAddress_) private view {
        bytes memory trustedRemote = trustedRemoteLookup[srcChainId_];
        if (
            trustedRemote.length == 0 ||
            srcAddress_.length != trustedRemote.length ||
            keccak256(srcAddress_) != keccak256(trustedRemote)
        ) revert LZBridgeGateway_InvalidMessageSource();
    }

    function _requireCaller(address expected_) private view {
        if (msg.sender != expected_) revert LZBridgeGateway_InvalidCaller();
    }

    function _requireCanonical() private view {
        if (!IS_CANONICAL) revert LZBridgeGateway_NotCanonical();
    }

    function _requireNonzeroAddress(address address_, string memory parameter_) private pure {
        if (address_ == address(0)) revert LZBridgeGateway_InvalidAddress(parameter_);
    }
}
