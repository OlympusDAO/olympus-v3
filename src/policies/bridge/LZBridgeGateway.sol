// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.30;

// Interfaces
import {ILayerZeroEndpointV2, MessagingParams, MessagingFee, Origin} from "@lz-evm-protocol-v2-3.0.142/interfaces/ILayerZeroEndpointV2.sol";
import {ILayerZeroReceiver} from "@lz-evm-protocol-v2-3.0.142/interfaces/ILayerZeroReceiver.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.142/interfaces/IMessageLibManager.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Contracts
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title LZBridgeGateway
/// @notice Infrastructure policy handling LayerZero V2 endpoint communication for cross-chain
///         OHM transfers.
///         Performs OHM mint/burn via MINTR, manages peers, and enforces a bridged
///         supply cap on canonical (mainnet) chains.
contract LZBridgeGateway is
    Policy,
    PolicyEnabler,
    IVersioned,
    ILayerZeroReceiver,
    ILZBridgeGateway
{
    // ========= CONSTANTS ========= //

    /// @notice Role required for LayerZero endpoint configuration and bridged supply setting.
    bytes32 private constant _BRIDGE_ADMIN_ROLE = "bridge_admin";

    /// @inheritdoc ILZBridgeGateway
    uint8 public constant override MSG_BRIDGE_OHM = 1;

    /// @notice Expected byte length of an ABI-encoded (address, uint256) bridge payload.
    uint256 private constant _BRIDGE_OHM_DATA_LENGTH = 64;

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
    mapping(uint32 eid_ => bytes32 peer) public override peers;

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
        uint32 dstEid_,
        address to_,
        uint256 amount_,
        address payable refundAddress_,
        bytes calldata options_
    ) external payable override onlyEnabled onlyFacilitator {
        // Warning. amount_ == 0 should be ensured by the facilitator
        _requireNonzeroAddress(to_, "to");

        bytes32 peer = peers[dstEid_];
        if (peer == bytes32(0)) revert LZBridgeGateway_DestinationNotTrusted();

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

        // Encode and send the bridge message via V2 endpoint
        bytes memory payload = abi.encode(MSG_BRIDGE_OHM, abi.encode(to_, amount_));
        // solhint-disable-next-line
        ILayerZeroEndpointV2(LZ_ENDPOINT).send{value: msg.value}(
            MessagingParams(dstEid_, peer, payload, options_, false),
            refundAddress_
        );
    }

    // ========= FEE ESTIMATION ========= //

    /// @inheritdoc ILZBridgeGateway
    function estimateSendFee(
        uint32 dstEid_,
        address to_,
        uint256 amount_,
        bytes calldata options_
    ) external view override returns (uint256 nativeFee, uint256 lzTokenFee) {
        bytes memory payload = abi.encode(MSG_BRIDGE_OHM, abi.encode(to_, amount_));
        MessagingFee memory fee = ILayerZeroEndpointV2(LZ_ENDPOINT).quote(
            MessagingParams(dstEid_, peers[dstEid_], payload, options_, false),
            address(this)
        );
        return (fee.nativeFee, fee.lzTokenFee);
    }

    // ========= LZ V2 RECEIVE FUNCTIONS ========= //

    /// @inheritdoc ILayerZeroReceiver
    function lzReceive(
        Origin calldata origin_,
        bytes32,
        bytes calldata message_,
        address,
        bytes calldata
    ) external payable override onlyEnabled {
        _requireCaller(LZ_ENDPOINT);
        if (peers[origin_.srcEid] != origin_.sender) revert LZBridgeGateway_InvalidMessageSource();
        _decodeAndRoute(origin_.srcEid, message_);
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
    function setPeer(uint32 eid_, address peerAddress_) external override onlyAdminRole {
        bytes32 peer = peerAddress_ != address(0)
            ? bytes32(uint256(uint160(peerAddress_)))
            : bytes32(0);
        peers[eid_] = peer;
        emit PeerSet(eid_, peer);
    }

    /// @inheritdoc ILZBridgeGateway
    function lzClear(
        Origin calldata origin_,
        bytes32 guid_,
        bytes calldata message_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpointV2(LZ_ENDPOINT).clear(address(this), origin_, guid_, message_);
        emit MessageCleared(origin_.srcEid, origin_.sender, origin_.nonce);
    }

    /// @inheritdoc ILZBridgeGateway
    function lzRetryReceive(
        Origin calldata origin_,
        bytes32 guid_,
        bytes calldata message_,
        bytes calldata extraData_
    ) external payable override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpointV2(LZ_ENDPOINT).lzReceive{value: msg.value}(
            origin_,
            address(this),
            guid_,
            message_,
            extraData_
        );
        emit MessageRetried(origin_.srcEid, origin_.sender, origin_.nonce);
    }

    /// @inheritdoc ILZBridgeGateway
    function lzSkip(
        uint32 srcEid_,
        bytes32 sender_,
        uint64 nonce_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpointV2(LZ_ENDPOINT).skip(address(this), srcEid_, sender_, nonce_);
        emit NonceSkipped(srcEid_, sender_, nonce_);
    }

    /// @inheritdoc ILZBridgeGateway
    function lzNilify(
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
        emit MessageNilified(srcEid_, sender_, nonce_);
    }

    /// @inheritdoc ILZBridgeGateway
    function lzBurn(
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
        emit MessageBurned(srcEid_, sender_, nonce_);
    }

    /// @inheritdoc ILZBridgeGateway
    function setSendLibrary(
        uint32 eid_,
        address lib_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        ILayerZeroEndpointV2(LZ_ENDPOINT).setSendLibrary(address(this), eid_, lib_);
    }

    /// @inheritdoc ILZBridgeGateway
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

    /// @inheritdoc ILZBridgeGateway
    function setLZConfig(
        address lib_,
        bytes calldata params_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        SetConfigParam[] memory configParams = abi.decode(params_, (SetConfigParam[]));
        ILayerZeroEndpointV2(LZ_ENDPOINT).setConfig(address(this), lib_, configParams);
    }

    /// @inheritdoc ILZBridgeGateway
    function setBridgedSupply(
        uint256 bridgedSupply_
    ) external override onlyRole(_BRIDGE_ADMIN_ROLE) {
        _requireCanonical();
        bridgedSupply = bridgedSupply_;
        emit BridgedSupplySet(bridgedSupply_);
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
    function _decodeAndRoute(uint32 srcEid_, bytes calldata payload_) private {
        (uint8 msgType, bytes memory data) = abi.decode(payload_, (uint8, bytes));

        if (msgType == MSG_BRIDGE_OHM) {
            _receiveBridgeOhm(srcEid_, data);
        } else {
            revert LZBridgeGateway_InvalidMessageType(msgType);
        }
    }

    /// @notice Processes a received OHM bridge message.
    /// @dev On canonical chains, decrements bridgedSupply. Mints OHM to the recipient.
    function _receiveBridgeOhm(uint32 srcEid_, bytes memory data_) private {
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

        emit Received(to, amount, srcEid_);
    }

    function _setFacilitator(address facilitator_) private {
        _requireNonzeroAddress(facilitator_, "facilitator");
        facilitator = facilitator_;
        emit FacilitatorSet(facilitator_);
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
