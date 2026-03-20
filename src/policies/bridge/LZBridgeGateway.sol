// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.30;

// Interfaces
import {ILayerZeroEndpointV2, MessagingParams, MessagingFee, MessagingReceipt, Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";
import {ILayerZeroReceiver} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroReceiver.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {ILZEndpointV2Admin} from "src/policies/interfaces/ILZEndpointV2Admin.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Contracts
import {RateLimiter} from "@lz-oapp-evm-0.4.1/oapp/utils/RateLimiter.sol";
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title LZBridgeGateway
/// @notice Infrastructure policy handling LayerZero V2 endpoint communication for cross-chain
///         OHM transfers.
///         Performs OHM mint/burn via MINTR, manages peers, enforces options and rate limits,
///         tracks bridged supply, and enforces a bridged supply cap on canonical chains.
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

    /// @inheritdoc ILZBridgeGateway
    uint8 public constant override MSG_BRIDGE_OHM = 1;

    /// @notice Expected byte length of an ABI-encoded (address, uint256) bridge payload.
    uint256 internal constant _BRIDGE_OHM_DATA_LENGTH = 64;

    /// @notice Type 3 option type identifier.
    uint16 internal constant _OPTION_TYPE_3 = 3;

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
    uint256 public override bridgedSupply;

    /// @inheritdoc ILZBridgeGateway
    uint256 public override bridgedSupplyCap;

    /// @inheritdoc ILZBridgeGateway
    mapping(uint32 eid_ => bytes32) public override peers;

    /// @inheritdoc ILZBridgeGateway
    mapping(uint32 eid_ => mapping(uint16 msgType_ => bytes)) public override enforcedOptions;

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
        uint32 dstEid_,
        address to_,
        uint256 amount_,
        address payable refundAddress_,
        bytes calldata extraOptions_
    ) external payable override onlyEnabled onlyFacilitator {
        // Note: zero-amount validation is the facilitator's responsibility
        _requireNonzeroAddress(to_, "to");

        bytes32 peer = _getPeerOrRevert(dstEid_);

        _outflow(dstEid_, amount_); // Rate limit outflow

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
        bytes memory options = _combineOptions(dstEid_, MSG_BRIDGE_OHM, extraOptions_);

        MessagingReceipt memory receipt = ILayerZeroEndpointV2(LZ_ENDPOINT).send{value: msg.value}(
            MessagingParams(dstEid_, peer, payload, options, false),
            refundAddress_
        );
        emit Sent(msg.sender, amount_, dstEid_, receipt.guid);
    }

    // ========= FEE ESTIMATION ========= //

    /// @inheritdoc ILZBridgeGateway
    function estimateSendFee(
        uint32 dstEid_,
        address to_,
        uint256 amount_,
        bytes calldata extraOptions_
    ) external view override returns (MessagingFee memory fee) {
        bytes32 peer = _getPeerOrRevert(dstEid_);
        bytes memory payload = abi.encode(MSG_BRIDGE_OHM, abi.encode(to_, amount_));
        bytes memory options = _combineOptions(dstEid_, MSG_BRIDGE_OHM, extraOptions_);

        return
            ILayerZeroEndpointV2(LZ_ENDPOINT).quote(
                MessagingParams(dstEid_, peer, payload, options, false),
                address(this)
            );
    }

    // ========= LZ RECEIVE FUNCTIONS (ILayerZeroReceiver) ========= //

    /// @inheritdoc ILayerZeroReceiver
    function lzReceive(
        Origin calldata origin_,
        bytes32 guid_,
        bytes calldata message_,
        address,
        bytes calldata
    ) external payable override onlyEnabled {
        if (msg.sender != LZ_ENDPOINT) revert LZBridgeGateway_OnlyEndpoint();
        if (peers[origin_.srcEid] != origin_.sender)
            revert LZBridgeGateway_OnlyPeer(origin_.srcEid, origin_.sender);

        _decodeAndRoute(origin_.srcEid, guid_, message_);
    }

    /// @inheritdoc ILayerZeroReceiver
    function allowInitializePath(Origin calldata origin_) external view override returns (bool) {
        return peers[origin_.srcEid] == origin_.sender;
    }

    /// @inheritdoc ILayerZeroReceiver
    function nextNonce(uint32, bytes32) external pure override returns (uint64) {
        return 0; // Unordered delivery
    }

    // ========= ADMIN FUNCTIONS ========= //

    /// @inheritdoc ILZBridgeGateway
    function setPeer(uint32 eid_, bytes32 peer_) external override onlyAdminRole {
        peers[eid_] = peer_;
        emit PeerSet(eid_, peer_);
    }

    /// @inheritdoc ILZBridgeGateway
    function setDelegate(address delegate_) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpointV2(LZ_ENDPOINT).setDelegate(delegate_);
        emit DelegateSet(delegate_);
    }

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
    function setBridgedSupply(
        uint256 bridgedSupply_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        _requireCanonical();
        bridgedSupply = bridgedSupply_;
        emit BridgedSupplySet(bridgedSupply_);
    }

    /// @inheritdoc ILZBridgeGateway
    function setEnforcedOptions(
        EnforcedOptionParam[] calldata enforcedOptions_
    ) external override onlyAdminRole {
        for (uint256 i = 0; i < enforcedOptions_.length; i++) {
            _assertOptionsType3(enforcedOptions_[i].options);
            enforcedOptions[enforcedOptions_[i].eid][
                enforcedOptions_[i].msgType
            ] = enforcedOptions_[i].options;
        }
        emit EnforcedOptionsSet(enforcedOptions_);
    }

    /// @inheritdoc ILZBridgeGateway
    function setRateLimits(
        RateLimitConfig[] calldata rateLimitConfigs_
    ) external override onlyAdminRole {
        _setRateLimits(rateLimitConfigs_);
    }

    /// @inheritdoc ILZBridgeGateway
    function resetRateLimits(
        uint32[] calldata eids_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        _resetRateLimits(eids_);
    }

    // ========= LZ ENDPOINT CONFIG ========= //

    /// @inheritdoc ILZEndpointV2Admin
    function setSendLibrary(
        uint32 eid_,
        address lib_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpointV2(LZ_ENDPOINT).setSendLibrary(address(this), eid_, lib_);
    }

    /// @inheritdoc ILZEndpointV2Admin
    function setReceiveLibrary(
        uint32 eid_,
        address lib_,
        uint256 gracePeriod_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpointV2(LZ_ENDPOINT).setReceiveLibrary(
            address(this),
            eid_,
            lib_,
            gracePeriod_
        );
    }

    /// @inheritdoc ILZEndpointV2Admin
    function setReceiveLibraryTimeout(
        uint32 eid_,
        address lib_,
        uint256 expiry_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpointV2(LZ_ENDPOINT).setReceiveLibraryTimeout(
            address(this),
            eid_,
            lib_,
            expiry_
        );
    }

    /// @inheritdoc ILZEndpointV2Admin
    function setEndpointConfig(
        address lib_,
        SetConfigParam[] calldata params_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpointV2(LZ_ENDPOINT).setConfig(address(this), lib_, params_);
    }

    // ========= LZ MESSAGE MANAGEMENT ========= //

    /// @inheritdoc ILZEndpointV2Admin
    function skip(
        uint32 srcEid_,
        bytes32 sender_,
        uint64 nonce_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpointV2(LZ_ENDPOINT).skip(address(this), srcEid_, sender_, nonce_);
    }

    /// @inheritdoc ILZEndpointV2Admin
    function nilify(
        uint32 srcEid_,
        bytes32 sender_,
        uint64 nonce_,
        bytes32 payloadHash_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpointV2(LZ_ENDPOINT).nilify(
            address(this),
            srcEid_,
            sender_,
            nonce_,
            payloadHash_
        );
    }

    /// @inheritdoc ILZEndpointV2Admin
    function burn(
        uint32 srcEid_,
        bytes32 sender_,
        uint64 nonce_,
        bytes32 payloadHash_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpointV2(LZ_ENDPOINT).burn(
            address(this),
            srcEid_,
            sender_,
            nonce_,
            payloadHash_
        );
    }

    /// @inheritdoc ILZEndpointV2Admin
    function clear(
        Origin calldata origin_,
        bytes32 guid_,
        bytes calldata message_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpointV2(LZ_ENDPOINT).clear(address(this), origin_, guid_, message_);
    }

    // ========= VIEW FUNCTIONS ========= //

    /// @inheritdoc ILZBridgeGateway
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

    // ========= PRIVATE FUNCTIONS ========= //

    /// @notice Decodes the message type from the payload and routes to the appropriate handler.
    function _decodeAndRoute(uint32 srcEid_, bytes32 guid_, bytes calldata payload_) private {
        (uint8 msgType, bytes memory data) = abi.decode(payload_, (uint8, bytes));

        if (msgType == MSG_BRIDGE_OHM) {
            _receiveBridgeOhm(srcEid_, guid_, data);
        } else {
            revert LZBridgeGateway_InvalidMessageType(msgType);
        }
    }

    /// @notice Processes a received OHM bridge message.
    /// @dev On canonical chains, decrements bridgedSupply. Mints OHM to the recipient.
    function _receiveBridgeOhm(uint32 srcEid_, bytes32 guid_, bytes memory data_) private {
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

        _inflow(srcEid_, amount); // Rate limit inflow

        MINTR.increaseMintApproval(address(this), amount);
        MINTR.mintOhm(to, amount);

        emit Received(to, amount, srcEid_, guid_);
    }

    function _setFacilitator(address facilitator_) private {
        _requireNonzeroAddress(facilitator_, "facilitator");
        facilitator = facilitator_;
        emit FacilitatorSet(facilitator_);
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
