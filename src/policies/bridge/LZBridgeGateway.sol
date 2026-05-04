// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.30;

/// Peer management, endpoint send/receive, and enforced-option logic ported from
/// @layerzerolabs/oapp-evm v0.4.1 (OAppCore, OAppSender, OAppReceiver, OAppOptionsType3).
/// Reimplemented inline rather than inherited because those contracts assume OZ Ownable,
/// which is incompatible with the Bophades Kernel RBAC model.
/// RateLimiter is the only oapp-evm contract inherited directly (no Ownable dependency).
/// _outflow() and _inflow() are overridden to make rate limiting opt-in per EID.
///
/// Ported logic (~ = identical, -> = differs):
///
///   OAppCore:         peers, setPeer(), _getPeerOrRevert(), setDelegate() ~
///                     -> Endpoint stored as `address`, cast at each call site.
///   OAppReceiver:     lzReceive(), allowInitializePath(), nextNonce() ~
///                     -> Routes via _decodeAndRoute() instead of virtual _lzReceive().
///   OAppSender:       estimateSendFee() <- _quote(); burnAndSend() <- _lzSend()
///                     -> msg.value forwarded directly; no _payNative()/_payLzToken().
///   OAppOptionsType3: enforcedOptions, setEnforcedOptions(), _combineOptions(),
///                     _assertOptionsType3() ~
///                     -> Adds _assertOptionsType3Calldata() for calldata inputs.
///
/// Not ported: oAppVersion() (-> IVersioned), isComposeMsgSender(), _payNative()/_payLzToken().
/// Access control: onlyOwner -> the ROLES module.

// Interfaces
import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";
import {ILayerZeroEndpointV2, MessagingParams, MessagingFee, MessagingReceipt, Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {ILayerZeroReceiver} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroReceiver.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {ILZEndpointV2Admin} from "src/policies/interfaces/ILZEndpointV2Admin.sol";

// Contracts
import {RateLimiter} from "@lz-oapp-evm-0.4.1/oapp/utils/RateLimiter.sol";
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";

/// @title LZBridgeGateway
/// @notice Infrastructure policy handling LayerZero V2 endpoint communication for cross-chain
///         OHM transfers.
///         Performs OHM mint/burn via MINTR, manages peers, enforces options and rate limits,
///         tracks bridged supply on canonical chains, and bounds inflow minting to previously burned OHM via mint approval.
contract LZBridgeGateway is
    Policy,
    PolicyEnabler,
    RateLimiter,
    IVersioned,
    ILZEndpointV2Admin,
    ILayerZeroReceiver,
    ILZBridgeGateway
{
    // ========= CONSTANTS ========= //

    /// @notice Role required for LayerZero endpoint configuration and bridged supply setting.
    bytes32 internal constant _BRIDGE_ADMIN_ROLE = "bridge_admin";

    /// @notice Role required to call burnAndSend (granted to periphery facilitator contracts).
    bytes32 internal constant _BRIDGE_FACILITATOR_ROLE = "bridge_facilitator";

    /// @inheritdoc ILZBridgeGateway
    uint8 public constant override MSG_BRIDGE_OHM = 1;

    /// @notice Expected byte length of an ABI-encoded (address, uint256) bridge payload.
    uint256 internal constant _BRIDGE_OHM_DATA_LENGTH = 64;

    /// @notice Minimum ABI-encoded length for (uint8, bytes): 32 + 32 offset + 32 length.
    uint256 internal constant _MIN_PAYLOAD_LENGTH = 96;

    /// @notice Type 3 option type identifier.
    uint16 internal constant _OPTION_TYPE_3 = 3;

    // ========= MODIFIERS ========= //

    /// @notice Modifier that reverts if the caller does not have the bridge_admin or admin role.
    modifier onlyBridgeAdminOrAdmin() {
        if (!ROLES.hasRole(msg.sender, _BRIDGE_ADMIN_ROLE) && !_isAdmin(msg.sender))
            revert PolicyAdmin.NotAuthorised();
        _;
    }

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
    uint256 public override bridgedSupply;

    /// @inheritdoc ILZBridgeGateway
    bool public override isReceiveEnabled;

    /// @inheritdoc ILZBridgeGateway
    mapping(uint32 eid_ => bytes32) public override peers;

    /// @inheritdoc ILZBridgeGateway
    mapping(uint32 eid_ => mapping(uint16 msgType_ => bytes)) public override enforcedOptions;

    // ========= INITIALIZATION & POLICY SETUP ========= //

    /// @dev Reverts if:
    ///      - The kernel address is the zero address.
    ///      - The LZ endpoint address is the zero address.
    constructor(Kernel kernel_, address lzEndpoint_, bool isCanonical_) Policy(kernel_) {
        _requireNonzeroAddress(address(kernel_), "kernel");
        _requireNonzeroAddress(lzEndpoint_, "lzEndpoint");

        LZ_ENDPOINT = lzEndpoint_;
        IS_CANONICAL = isCanonical_;

        // PolicyEnabler starts disabled; must be explicitly enabled after configuration.
        // Gateway is always authorized to call endpoint functions.
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("ROLES");

        MINTRv1 mintr = MINTRv1(getModuleAddress(dependencies[0]));
        ROLESv1 roles = ROLESv1(getModuleAddress(dependencies[1]));

        // Ensure modules are using the expected major version
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
        permissions = new Permissions[](4);
        Keycode kc = MINTR.KEYCODE();
        permissions[0] = Permissions({keycode: kc, funcSelector: MINTRv1.mintOhm.selector});
        permissions[1] = Permissions({keycode: kc, funcSelector: MINTRv1.burnOhm.selector});
        permissions[2] = Permissions({
            keycode: kc,
            funcSelector: MINTRv1.increaseMintApproval.selector
        });
        permissions[3] = Permissions({
            keycode: kc,
            funcSelector: MINTRv1.decreaseMintApproval.selector
        });
    }

    /// forge-lint: disable-next-item(mixed-case-function)
    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========= POLICY ENABLER ========= //

    /// @dev Sets isReceiveEnabled to true when the gateway is enabled.
    function _enable(bytes calldata) internal override {
        if (!isReceiveEnabled) _setIsReceiveEnabled(true);
    }

    /// @dev Resets isReceiveEnabled to false when the gateway is disabled.
    function _disable(bytes calldata) internal override {
        if (isReceiveEnabled) _setIsReceiveEnabled(false);
    }

    // ========= OHM BRIDGING ========= //

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the `bridge_facilitator` role.
    ///      - The gateway is not enabled.
    ///      - The recipient address is the zero address.
    ///      - No peer exists for the destination endpoint ID.
    ///      - The rate limit would be exceeded.
    function burnAndSend(
        uint32 dstEid_,
        address to_,
        uint256 amount_,
        address payable refundAddress_,
        bytes calldata extraOptions_
    ) external payable override onlyEnabled onlyRole(_BRIDGE_FACILITATOR_ROLE) {
        // Note: zero-amount validation is the facilitator's responsibility
        _requireNonzeroAddress(to_, "to");

        bytes32 peer = _getPeerOrRevert(dstEid_);

        _outflow(dstEid_, amount_); // Rate limit outflow

        // Track bridged supply on canonical chain
        if (IS_CANONICAL) {
            bridgedSupply += amount_;
            emit BridgedSupplyIncreased(amount_);

            // Pre-fund mint approval so future inflow can mint without JIT self approval.
            // Bounds the canonical inflow mint to the amount of OHM actually burned via outflow.
            MINTR.increaseMintApproval(address(this), amount_);
        }

        // Burn OHM held by the gateway (transferred here by the facilitator)
        // solhint-disable-next-line no-unused-vars
        IERC20(ohm).approve(address(MINTR), amount_);
        MINTR.burnOhm(address(this), amount_);

        // Encode and send the bridge message
        bytes memory payload = abi.encode(MSG_BRIDGE_OHM, abi.encode(to_, amount_));
        bytes memory options = _combineOptions(dstEid_, MSG_BRIDGE_OHM, extraOptions_);

        MessagingReceipt memory receipt = ILayerZeroEndpointV2(LZ_ENDPOINT).send{value: msg.value}(
            MessagingParams({
                dstEid: dstEid_,
                receiver: peer,
                message: payload,
                options: options,
                payInLzToken: false
            }),
            refundAddress_
        );
        emit Sent(msg.sender, amount_, dstEid_, receipt.guid);
    }

    // ========= FEE ESTIMATION ========= //

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The recipient address is zero.
    ///      - No peer exists for the destination endpoint ID.
    function estimateSendFee(
        uint32 dstEid_,
        address to_,
        uint256 amount_,
        bytes calldata extraOptions_
    ) external view override returns (MessagingFee memory fee) {
        _requireNonzeroAddress(to_, "to");
        bytes32 peer = _getPeerOrRevert(dstEid_);
        bytes memory payload = abi.encode(MSG_BRIDGE_OHM, abi.encode(to_, amount_));
        bytes memory options = _combineOptions(dstEid_, MSG_BRIDGE_OHM, extraOptions_);

        return
            ILayerZeroEndpointV2(LZ_ENDPOINT).quote(
                MessagingParams({
                    dstEid: dstEid_,
                    receiver: peer,
                    message: payload,
                    options: options,
                    payInLzToken: false
                }),
                address(this)
            );
    }

    // ========= LZ RECEIVE FUNCTIONS (ILayerZeroReceiver) ========= //

    /// @inheritdoc ILayerZeroReceiver
    /// @dev Reverts if:
    ///      - Receiving is not enabled (isReceiveEnabled is false).
    ///      - The caller is not the LayerZero endpoint.
    ///      - The origin sender is not the configured peer for the source endpoint ID.
    ///      - No peer is configured for the source endpoint ID.
    ///      - The message payload is shorter than the minimum encoded length.
    ///      - The message type is not MSG_BRIDGE_OHM.
    ///      - The bridge data payload has an unexpected length.
    ///      - (Canonical) The bridged supply would underflow.
    function lzReceive(
        Origin calldata origin_,
        bytes32 guid_,
        bytes calldata message_,
        address,
        bytes calldata
    ) external payable override {
        if (!isReceiveEnabled) revert LZBridgeGateway_ReceiveNotEnabled();
        if (msg.sender != LZ_ENDPOINT) revert LZBridgeGateway_OnlyEndpoint();
        if (_getPeerOrRevert(origin_.srcEid) != origin_.sender)
            revert LZBridgeGateway_OnlyPeer(origin_.srcEid, origin_.sender);

        _decodeAndRoute(origin_.srcEid, guid_, message_);
    }

    /// @inheritdoc ILayerZeroReceiver
    function allowInitializePath(Origin calldata origin_) external view override returns (bool) {
        return peers[origin_.srcEid] != bytes32(0) && peers[origin_.srcEid] == origin_.sender;
    }

    /// @inheritdoc ILayerZeroReceiver
    function nextNonce(uint32, bytes32) external pure override returns (uint64) {
        return 0; // Unordered delivery
    }

    // ========= ADMIN FUNCTIONS ========= //

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the admin role.
    function setPeer(uint32 eid_, bytes32 peer_) external override onlyAdminRole {
        peers[eid_] = peer_;
        emit PeerSet(eid_, peer_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the emergency or admin role.
    ///      - The gateway is currently enabled.
    ///      - The value is already in the desired state.
    function setIsReceiveEnabled(
        bool isReceiveEnabled_
    ) external override onlyEmergencyOrAdminRole {
        if (isEnabled) revert LZBridgeGateway_ReceiveControlOnlyWhenDisabled();
        if (isReceiveEnabled == isReceiveEnabled_)
            revert LZBridgeGateway_ReceiveAlreadyInDesiredState();
        _setIsReceiveEnabled(isReceiveEnabled_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_admin or admin role.
    function setDelegate(address delegate_) external override onlyBridgeAdminOrAdmin {
        ILayerZeroEndpointV2(LZ_ENDPOINT).setDelegate(delegate_);
        emit DelegateSet(delegate_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_admin or admin role.
    ///      - IS_CANONICAL is false.
    function increaseBridgedSupply(uint256 amount_) external override onlyBridgeAdminOrAdmin {
        _requireCanonical();

        bridgedSupply += amount_;
        MINTR.increaseMintApproval(address(this), amount_);

        emit BridgedSupplyForciblyIncreased(amount_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_admin or admin role.
    ///      - IS_CANONICAL is false.
    ///      - The bridged supply would underflow.
    function decreaseBridgedSupply(uint256 amount_) external override onlyBridgeAdminOrAdmin {
        _requireCanonical();

        if (bridgedSupply < amount_)
            revert LZBridgeGateway_BridgedSupplyUnderflow(bridgedSupply, amount_);
        unchecked {
            bridgedSupply -= amount_;
        }
        MINTR.decreaseMintApproval(address(this), amount_);

        emit BridgedSupplyForciblyDecreased(amount_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the admin role.
    ///      - Any option entry is not Type 3 format.
    function setEnforcedOptions(
        EnforcedOptionParam[] calldata enforcedOptions_
    ) external override onlyAdminRole {
        for (uint256 i = 0; i < enforcedOptions_.length; ++i) {
            _assertOptionsType3(enforcedOptions_[i].options);
            enforcedOptions[enforcedOptions_[i].eid][
                enforcedOptions_[i].msgType
            ] = enforcedOptions_[i].options;
        }
        emit EnforcedOptionsSet(enforcedOptions_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_admin or admin role.
    function setRateLimits(
        RateLimitConfig[] calldata rateLimitConfigs_
    ) external override onlyBridgeAdminOrAdmin {
        _setRateLimits(rateLimitConfigs_);
    }

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_admin or admin role.
    function resetRateLimits(uint32[] calldata eids_) external override onlyBridgeAdminOrAdmin {
        _resetRateLimits(eids_);
    }

    // ========= LZ ENDPOINT CONFIG ========= //

    /// @inheritdoc ILZEndpointV2Admin
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_admin or admin role.
    function setSendLibrary(uint32 eid_, address lib_) external override onlyBridgeAdminOrAdmin {
        ILayerZeroEndpointV2(LZ_ENDPOINT).setSendLibrary(address(this), eid_, lib_);
    }

    /// @inheritdoc ILZEndpointV2Admin
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_admin or admin role.
    function setReceiveLibrary(
        uint32 eid_,
        address lib_,
        uint256 gracePeriod_
    ) external override onlyBridgeAdminOrAdmin {
        ILayerZeroEndpointV2(LZ_ENDPOINT).setReceiveLibrary(
            address(this),
            eid_,
            lib_,
            gracePeriod_
        );
    }

    /// @inheritdoc ILZEndpointV2Admin
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_admin or admin role.
    function setReceiveLibraryTimeout(
        uint32 eid_,
        address lib_,
        uint256 expiry_
    ) external override onlyBridgeAdminOrAdmin {
        ILayerZeroEndpointV2(LZ_ENDPOINT).setReceiveLibraryTimeout(
            address(this),
            eid_,
            lib_,
            expiry_
        );
    }

    /// @inheritdoc ILZEndpointV2Admin
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_admin or admin role.
    function setEndpointConfig(
        address lib_,
        SetConfigParam[] calldata params_
    ) external override onlyBridgeAdminOrAdmin {
        ILayerZeroEndpointV2(LZ_ENDPOINT).setConfig(address(this), lib_, params_);
    }

    // ========= LZ MESSAGE MANAGEMENT ========= //

    /// @inheritdoc ILZEndpointV2Admin
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_admin or admin role.
    function skip(
        uint32 srcEid_,
        bytes32 sender_,
        uint64 nonce_
    ) external override onlyBridgeAdminOrAdmin {
        ILayerZeroEndpointV2(LZ_ENDPOINT).skip(address(this), srcEid_, sender_, nonce_);
    }

    /// @inheritdoc ILZEndpointV2Admin
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_admin or admin role.
    function nilify(
        uint32 srcEid_,
        bytes32 sender_,
        uint64 nonce_,
        bytes32 payloadHash_
    ) external override onlyBridgeAdminOrAdmin {
        ILayerZeroEndpointV2(LZ_ENDPOINT).nilify(
            address(this),
            srcEid_,
            sender_,
            nonce_,
            payloadHash_
        );
    }

    /// @inheritdoc ILZEndpointV2Admin
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_admin or admin role.
    function burn(
        uint32 srcEid_,
        bytes32 sender_,
        uint64 nonce_,
        bytes32 payloadHash_
    ) external override onlyBridgeAdminOrAdmin {
        ILayerZeroEndpointV2(LZ_ENDPOINT).burn(
            address(this),
            srcEid_,
            sender_,
            nonce_,
            payloadHash_
        );
    }

    /// @inheritdoc ILZEndpointV2Admin
    /// @dev Reverts if:
    ///      - The caller does not have the bridge_admin or admin role.
    function clear(
        Origin calldata origin_,
        bytes32 guid_,
        bytes calldata message_
    ) external override onlyBridgeAdminOrAdmin {
        ILayerZeroEndpointV2(LZ_ENDPOINT).clear(address(this), origin_, guid_, message_);
    }

    // ========= VIEW FUNCTIONS ========= //

    /// @inheritdoc ILZBridgeGateway
    /// @dev Reverts if:
    ///      - Extra options are provided but are not Type 3 format.
    ///      - Extra options have length 1 (insufficient for Type 3 prefix).
    function combineOptions(
        uint32 eid_,
        uint16 msgType_,
        bytes calldata extraOptions_
    ) external view override returns (bytes memory) {
        return _combineOptions(eid_, msgType_, extraOptions_);
    }

    // ========= ERC165 ========= //

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(PolicyEnabler) returns (bool) {
        return
            interfaceId == type(ILZBridgeGateway).interfaceId ||
            interfaceId == type(ILZEndpointV2Admin).interfaceId ||
            interfaceId == type(ILayerZeroReceiver).interfaceId ||
            interfaceId == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // ========= RATE LIMITER OVERRIDE ========= //

    /// @dev Skips rate limiting for unconfigured EIDs (limit == 0 && window == 0),
    ///      making rate limiting opt-in rather than mandatory.
    function _outflow(uint32 _dstEid, uint256 _amount) internal override {
        RateLimit storage rl = rateLimits[_dstEid];
        if (rl.limit == 0 && rl.window == 0) return;
        super._outflow(_dstEid, _amount);
    }

    /// @dev Skips inflow accounting when no outflow is tracked for this EID.
    ///      For unconfigured EIDs (where _outflow is also skipped), amountInFlight is always 0.
    ///      For configured EIDs, avoids a redundant write when all outflow has been settled.
    function _inflow(uint32 _srcEid, uint256 _amount) internal override {
        if (rateLimits[_srcEid].amountInFlight == 0) return;
        super._inflow(_srcEid, _amount);
    }

    // ========= PRIVATE FUNCTIONS ========= //

    function _setIsReceiveEnabled(bool isReceiveEnabled_) private {
        isReceiveEnabled = isReceiveEnabled_;
        emit IsReceiveEnabledSet(isReceiveEnabled_);
    }

    /// @notice Decodes the message type from the payload and routes to the appropriate handler.
    function _decodeAndRoute(uint32 srcEid_, bytes32 guid_, bytes calldata payload_) private {
        if (payload_.length < _MIN_PAYLOAD_LENGTH) revert LZBridgeGateway_InvalidPayload();
        (uint8 msgType, bytes memory data) = abi.decode(payload_, (uint8, bytes));

        if (msgType == MSG_BRIDGE_OHM) {
            _receiveBridgeOhm(srcEid_, guid_, data);
        } else {
            revert LZBridgeGateway_InvalidMessageType(msgType);
        }
    }

    /// @notice Processes a received OHM bridge message.
    /// @dev On canonical chains, decrements bridgedSupply and mints from pre-funded approval
    ///      (set during outflow). On non-canonical chains, uses JIT self approval.
    function _receiveBridgeOhm(uint32 srcEid_, bytes32 guid_, bytes memory data_) private {
        if (data_.length != _BRIDGE_OHM_DATA_LENGTH) revert LZBridgeGateway_InvalidPayload();
        (address to, uint256 amount) = abi.decode(data_, (address, uint256));

        _requireNonzeroAddress(to, "to");

        // Track bridged supply on canonical chain
        if (IS_CANONICAL) {
            if (bridgedSupply < amount)
                revert LZBridgeGateway_BridgedSupplyUnderflow(bridgedSupply, amount);
            unchecked {
                bridgedSupply -= amount;
            }
            emit BridgedSupplyDecreased(amount);
            // Approval already exists from outflow, no JIT needed
        } else {
            // Non-canonical: JIT self approval
            MINTR.increaseMintApproval(address(this), amount);
        }

        _inflow(srcEid_, amount); // Rate limit inflow

        MINTR.mintOhm(to, amount);

        emit Received(to, amount, srcEid_, guid_);
    }

    function _getPeerOrRevert(uint32 eid_) private view returns (bytes32) {
        bytes32 peer = peers[eid_];
        if (peer == bytes32(0)) revert LZBridgeGateway_NoPeer(eid_);
        return peer;
    }

    function _requireCanonical() private view {
        if (!IS_CANONICAL) revert LZBridgeGateway_NotCanonical();
    }

    function _requireNonzeroAddress(address address_, string memory parameter_) private pure {
        if (address_ == address(0)) revert LZBridgeGateway_InvalidAddress(parameter_);
    }

    // ========= ENFORCED OPTIONS (composed from OAppOptionsType3) ========= //

    /// @notice Combines enforced options with caller-provided extra options.
    function _combineOptions(
        uint32 eid_,
        uint16 msgType_,
        bytes calldata extraOptions_
    ) internal view returns (bytes memory) {
        bytes memory enforced = enforcedOptions[eid_][msgType_];

        // No enforced options, pass whatever the caller supplied
        if (enforced.length == 0) return extraOptions_;

        // No caller options, return enforced
        if (extraOptions_.length == 0) return enforced;

        // Caller provided extra options must be Type 3
        if (extraOptions_.length >= 2) {
            _assertOptionsType3Calldata(extraOptions_);
            // Strip the 2-byte Type 3 prefix from extra options before concatenation
            return bytes.concat(enforced, extraOptions_[2:]);
        }

        // Invalid options
        revert LZBridgeGateway_InvalidOptions(extraOptions_);
    }

    /// @notice Validates that options bytes begin with the Type 3 prefix.
    /// @dev Assembly pattern from OAppOptionsType3._assertOptionsType3() (@layerzerolabs/oapp-evm v0.4.1).
    function _assertOptionsType3(bytes memory options_) internal pure {
        uint16 optionsType;
        assembly {
            optionsType := mload(add(options_, 2))
        }
        if (optionsType != _OPTION_TYPE_3) revert LZBridgeGateway_InvalidOptions(options_);
    }

    /// @notice Validates that calldata options bytes begin with the Type 3 prefix.
    function _assertOptionsType3Calldata(bytes calldata options_) internal pure {
        uint16 optionsType = uint16(bytes2(options_[:2]));
        if (optionsType != _OPTION_TYPE_3) revert LZBridgeGateway_InvalidOptions(options_);
    }
}
