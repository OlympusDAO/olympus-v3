// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {ILayerZeroUserApplicationConfig} from "layer-zero/interfaces/ILayerZeroUserApplicationConfig.sol";
import {ILayerZeroEndpoint} from "layer-zero/interfaces/ILayerZeroEndpoint.sol";
import {ILayerZeroReceiver} from "layer-zero/interfaces/ILayerZeroReceiver.sol";
import {BytesLib} from "layer-zero/util/BytesLib.sol";

import {RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";

import "src/Kernel.sol";

/// @notice Message bridge for cross-chain OHM transfers.
/// @dev Uses LayerZero as communication protocol.
/// @dev Each chain needs to `setTrustedRemoteAddress` for each remote address
///      it intends to receive from.
contract CrossChainBridge is Policy, RolesConsumer, ILayerZeroReceiver, ILayerZeroUserApplicationConfig {
    using BytesLib for bytes;

    // Bridge errors
    error Bridge_InsufficientAmount();
    error Bridge_InvalidCaller();
    error Bridge_InvalidMessageSource();
    error Bridge_NoStoredMessage();
    error Bridge_InvalidPayload();
    error Bridge_DestinationNotTrusted();
    error Bridge_MinGasLimitNotSet();
    error Bridge_GasLimitTooLow();
    error Bridge_InvalidMinGas();
    error Bridge_InvalidAdapterParams();
    error Bridge_NoTrustedPath();

    // Bridge-specific events
    event BridgeTransferred(address sender_, uint256 amount_, uint16 dstChain_);
    event BridgeReceived(address receiver_, uint256 amount_, uint16 srcChain_);

    // LZ app events
    event MessageFailed(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes _payload, bytes _reason);
    event RetryMessageSuccess(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes32 _payloadHash);
    event SetPrecrime(address precrime);
    event SetTrustedRemote(uint16 _remoteChainId, bytes _path);
    event SetTrustedRemoteAddress(uint16 _remoteChainId, bytes _remoteAddress);
    event SetMinDstGas(uint16 _dstChainId, uint16 _type, uint _minDstGas);

    // Modules
    MINTRv1 public MINTR;

    ILayerZeroEndpoint public immutable lzEndpoint;
    ERC20 ohm;

    // NOTE: Currently only used on mainnet
    bool public counterEnabled;

    /// @notice Count of how much OHM has been bridged offchain
    uint256 public offchainOhmCounter;

    // LZ app state
    mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) public failedMessages;
    mapping(uint16 => mapping(uint16 => uint)) public minDstGasLookup;
    mapping(uint16 => bytes) public trustedRemoteLookup;
    address public precrime;

    //============================================================================================//
    //                                        POLICY SETUP                                        //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        address endpoint_,
        bool enableCounter_
    ) Policy(kernel_) {
        lzEndpoint = ILayerZeroEndpoint(endpoint_);
        counterEnabled = enableCounter_;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("ROLES");

        MINTR = MINTRv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));

        ohm = ERC20(address(MINTR.ohm()));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](4);
        permissions[0] = Permissions(MINTR.KEYCODE(), MINTR.mintOhm.selector);
        permissions[1] = Permissions(MINTR.KEYCODE(), MINTR.burnOhm.selector);
        permissions[2] = Permissions(MINTR.KEYCODE(), MINTR.increaseMintApproval.selector);
        permissions[3] = Permissions(MINTR.KEYCODE(), MINTR.decreaseMintApproval.selector);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @notice Send OHM to an eligible chain
    function sendOhm(address to_, uint256 amount_, uint16 dstChainId_) external payable {
        if (ohm.balanceOf(msg.sender) < amount_) revert Bridge_InsufficientAmount();

        if (counterEnabled) offchainOhmCounter += amount_;
        // TODO check then set gas here?
        // TODO uint256 gas = _checkGasLimit(dstChainId_, 

        bytes memory payload = abi.encode(to_, amount_);

        MINTR.burnOhm(msg.sender, amount_);

        _sendMessage(
            dstChainId_,
            payload,
            payable(msg.sender),
            address(0x0),
            bytes(""),
            msg.value
        );

        emit BridgeTransferred(msg.sender, amount_, dstChainId_);
    }

    // TODO receives info to mint to a user's wallet
    /// @notice Implementation of receiving an LZ message
    /// @dev    Function must be public to be called by low-level call
    function _receiveMessage(
        uint16 srcChainId_,
        bytes memory,
        uint64,
        bytes memory payload_
    ) public {
        // Needed f
        if (msg.sender != address(this)) revert Bridge_InvalidCaller();

        (address to, uint256 amount) = abi.decode(payload_, (address, uint256));

        if (counterEnabled) offchainOhmCounter -= amount;

        MINTR.increaseMintApproval(address(this), amount);
        MINTR.mintOhm(to, amount);

        emit BridgeReceived(to, amount, srcChainId_);
    }

    // ========= LZ Receive Functions ========= //

    /// @notice Function to be called by LZ endpoint when message is received.
    function lzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) public virtual override {
        // lzReceive must be called by the endpoint for security
        if (msg.sender != address(lzEndpoint)) revert Bridge_InvalidCaller();

        // Will still block the message pathway from (srcChainId, srcAddress).
        // Should not receive messages from untrusted remote.
        bytes memory trustedRemote = trustedRemoteLookup[_srcChainId];
        if (trustedRemote.length == 0 ||
            _srcAddress.length != trustedRemote.length ||
            keccak256(_srcAddress) != keccak256(trustedRemote)
        ) revert Bridge_InvalidMessageSource();

        // NOTE: Use low-level call to handle any errors. We trust the underlying receive
        // impl, so we are doing a regular call vs using ExcessivelySafeCall
        (bool success, bytes memory reason) = address(this).call(abi.encodeWithSelector(this._receiveMessage.selector, _srcChainId, _srcAddress, _nonce, _payload));
        
        // If message fails, store message for retry
        if (!success) {
            failedMessages[_srcChainId][_srcAddress][_nonce] = keccak256(_payload);
            emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload, reason);
        }
    }

    /// @notice Retry a failed receive message
    function retryMessage(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) public payable virtual {
        // Assert there is message to retry
        bytes32 payloadHash = failedMessages[_srcChainId][_srcAddress][_nonce];
        if (payloadHash == bytes32(0)) revert Bridge_NoStoredMessage();
        if (keccak256(_payload) != payloadHash) revert Bridge_InvalidPayload();

        // Clear the stored message
        failedMessages[_srcChainId][_srcAddress][_nonce] = bytes32(0);

        // Execute the message. revert if it fails again
        _receiveMessage(_srcChainId, _srcAddress, _nonce, _payload);

        emit RetryMessageSuccess(_srcChainId, _srcAddress, _nonce, payloadHash);
    }

    // ========= LZ Send Functions ========= //

    function _sendMessage(uint16 _dstChainId, bytes memory _payload, address payable _refundAddress, address _zroPaymentAddress, bytes memory _adapterParams, uint _nativeFee) internal virtual {
        bytes memory trustedRemote = trustedRemoteLookup[_dstChainId];
        if (trustedRemote.length == 0) revert Bridge_DestinationNotTrusted();

        lzEndpoint.send{value: _nativeFee}(
            _dstChainId,
            trustedRemote,
            _payload,
            _refundAddress,
            _zroPaymentAddress,
            _adapterParams
        );
    }

    function _checkGasLimit(uint16 _dstChainId, uint16 _type, bytes memory _adapterParams, uint _extraGas) internal view virtual {
        uint providedGasLimit = _getGasLimit(_adapterParams);
        uint minGasLimit = minDstGasLookup[_dstChainId][_type] + _extraGas;
        if (minGasLimit == 0) revert Bridge_MinGasLimitNotSet();
        if (providedGasLimit < minGasLimit) revert Bridge_GasLimitTooLow();
    }

    function _getGasLimit(bytes memory _adapterParams) internal pure virtual returns (uint gasLimit) {
        if (_adapterParams.length < 34) revert Bridge_InvalidAdapterParams();
        assembly {
            gasLimit := mload(add(_adapterParams, 34))
        }
    }

    // ========= LZ UserApplication config ========= //

    /// @notice Generic config for LayerZero User Application
    function setConfig(uint16 _version, uint16 _chainId, uint _configType, bytes calldata _config) external override onlyRole("bridge_admin") {
        lzEndpoint.setConfig(_version, _chainId, _configType, _config);
    }

    /// @notice Set send version of endpoint to be used by LayerZero User Application
    function setSendVersion(uint16 _version) external override onlyRole("bridge_admin") {
        lzEndpoint.setSendVersion(_version);
    }

    /// @notice Set receive version of endpoint to be used by LayerZero User Application
    function setReceiveVersion(uint16 _version) external override onlyRole("bridge_admin") {
        lzEndpoint.setReceiveVersion(_version);
    }

    // TODO IDK
    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external override onlyRole("bridge_admin") {
        lzEndpoint.forceResumeReceive(_srcChainId, _srcAddress);
    }

    /// @notice Sets the trusted path for the cross-chain communication
    /// @dev    _path = abi.encodePacked(remoteAddress, localAddress)
    function setTrustedRemote(uint16 _srcChainId, bytes calldata _path) external onlyRole("bridge_admin") {
        trustedRemoteLookup[_srcChainId] = _path;
        emit SetTrustedRemote(_srcChainId, _path);
    }

    /// @notice Convenience function for setting trusted paths between EVM addresses
    function setTrustedRemoteAddress(uint16 _remoteChainId, bytes calldata _remoteAddress) external onlyRole("bridge_admin") {
        trustedRemoteLookup[_remoteChainId] = abi.encodePacked(_remoteAddress, address(this));
        emit SetTrustedRemoteAddress(_remoteChainId, _remoteAddress);
    }

    /// @notice Sets precrime address
    function setPrecrime(address _precrime) external onlyRole("bridge_admin") {
        precrime = _precrime;
        emit SetPrecrime(_precrime);
    }

    /// @notice Sets the minimum gas needed for a particular destination chain
    function setMinDstGas(uint16 _dstChainId, uint16 _packetType, uint _minGas) external onlyRole("bridge_admin") {
        if (_minGas == 0) revert Bridge_InvalidMinGas();
        minDstGasLookup[_dstChainId][_packetType] = _minGas;
        emit SetMinDstGas(_dstChainId, _packetType, _minGas);
    }

    // ========= View Functions ========= //

    function getConfig(uint16 _version, uint16 _chainId, address, uint _configType) external view returns (bytes memory) {
        return lzEndpoint.getConfig(_version, _chainId, address(this), _configType);
    }

    function getTrustedRemoteAddress(uint16 _remoteChainId) external view returns (bytes memory) {
        bytes memory path = trustedRemoteLookup[_remoteChainId];
        if (path.length == 0) revert Bridge_NoTrustedPath(); //, "LzApp: no trusted path record");
        return path.slice(0, path.length - 20); // the last 20 bytes should be address(this)
    }

    function isTrustedRemote(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (bool) {
        bytes memory trustedSource = trustedRemoteLookup[_srcChainId];
        return keccak256(trustedSource) == keccak256(_srcAddress);
    }
}
