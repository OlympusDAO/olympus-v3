// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.15;

import {console2} from "forge-std/console2.sol";
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {WithEnvironment} from "../WithEnvironment.s.sol";
import {WithLayerZeroConstants} from "../WithLayerZeroConstants.sol";

// Libraries
import {SafeCast} from "src/libraries/SafeCast.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";

// Interfaces
import {ICCIPTokenAdminRegistry} from "src/external/bridge/ICCIPTokenAdminRegistry.sol";

// Contracts
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";

import {OlympusAuthority} from "src/external/OlympusAuthority.sol";
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";

import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {CCIPCrossChainBridge} from "src/periphery/bridge/CCIPCrossChainBridge.sol";
import {CrossChainBridge} from "src/policies/CrossChainBridge.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {Emergency} from "src/policies/Emergency.sol";
import {TreasuryCustodian} from "src/policies/TreasuryCustodian.sol";
import {Minter} from "src/policies/Minter.sol";
import {CCIPBurnMintTokenPool} from "src/policies/bridge/CCIPBurnMintTokenPool.sol";
import {CCIPTokenPoolConfig} from "src/policies/bridge/CCIPTokenPoolConfig.sol";
import {CCIPTokenPoolConfigTimelock} from "src/policies/bridge/CCIPTokenPoolConfigTimelock.sol";

/// @notice Deploys and configures a Bophades installation on another chain.
// solhint-disable gas-custom-errors
contract L2Deploy is WithEnvironment, WithLayerZeroConstants {
    error L2Deploy_InvalidVerificationInput();

    uint256 internal _ownershipFailures;
    string internal _deploymentAddresses;

    function _getDaoMultisig() internal view returns (address) {
        return _envAddressNotZero("olympus.multisig.dao");
    }

    function _getEmergencyMultisig() internal view returns (address) {
        return _envAddressNotZero("olympus.multisig.emergency");
    }

    function _endsWith(string memory str, string memory suffix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory suffixBytes = bytes(suffix);

        if (strBytes.length < suffixBytes.length) return false;

        for (uint256 i = 0; i < suffixBytes.length; i++) {
            if (strBytes[strBytes.length - suffixBytes.length + i] != suffixBytes[i]) return false;
        }

        return true;
    }

    function isTestnet(string calldata chain_) internal pure returns (bool) {
        // If the chain ends with sepolia, it is a testnet
        if (_endsWith(chain_, "sepolia")) {
            return true;
        }

        // If the chain ends with bartio, it is a testnet
        if (_endsWith(chain_, "bartio")) {
            return true;
        }

        return false;
    }

    /// @notice Compare two bytes arrays for equality
    /// @param a_ First bytes array
    /// @param b_ Second bytes array
    /// @return bool True if the arrays are equal, false otherwise
    function _bytesEqual(bytes memory a_, bytes memory b_) internal pure returns (bool) {
        // Check lengths first
        if (a_.length != b_.length) {
            return false;
        }

        // Compare each byte
        for (uint256 i = 0; i < a_.length; i++) {
            if (a_[i] != b_[i]) {
                return false;
            }
        }

        return true;
    }

    function grantRoles(string calldata chain_) external {
        _loadEnv(chain_);
        vm.startBroadcast();

        RolesAdmin rolesAdmin = RolesAdmin(_envAddressNotZero("olympus.policies.RolesAdmin"));
        OlympusMinter MINTR = OlympusMinter(_envAddressNotZero("olympus.modules.OlympusMinter"));
        OlympusAuthority auth = OlympusAuthority(
            _envAddressNotZero("olympus.legacy.OlympusAuthority")
        );

        console2.log("");
        console2.log("Granting roles");

        // Assign emergency roles
        {
            console2.log("Granting emergency roles to emergency multisig", _getEmergencyMultisig());
            rolesAdmin.grantRole("emergency_shutdown", _getEmergencyMultisig());
            rolesAdmin.grantRole("emergency_restart", _getEmergencyMultisig());
        }

        // TreasuryCustodian
        {
            console2.log("Granting custodian role to DAO multisig", _getDaoMultisig());
            rolesAdmin.grantRole("custodian", _getDaoMultisig());
        }

        // CrossChainBridge
        // The role is required for setup. It will be transferred to the multisig later
        if (_envAddress("olympus.policies.CrossChainBridge") != address(0)) {
            console2.log("Granting bridge admin role to deployer", msg.sender);
            rolesAdmin.grantRole("bridge_admin", msg.sender);
        }

        if (_envAddress("olympus.policies.CCIPBurnMintTokenPool") != address(0)) {
            console2.log("Granting CCIP pool admin role to DAO multisig", _getDaoMultisig());
            rolesAdmin.grantRole(ADMIN_ROLE, _getDaoMultisig());
            console2.log(
                "Granting CCIP pool emergency role to emergency multisig",
                _getEmergencyMultisig()
            );
            rolesAdmin.grantRole(EMERGENCY_ROLE, _getEmergencyMultisig());
        }

        {
            // OlympusAuthority vault
            console2.log("Granting OlympusAuthority vault role to MINTR", address(MINTR));
            auth.pushVault(address(MINTR), true);

            // OlympusAuthority guardian
            console2.log(
                "Granting OlympusAuthority guardian role to DAO multisig",
                _getDaoMultisig()
            );
            auth.pushGuardian(_getDaoMultisig(), true);

            // OlympusAuthority policy
            console2.log(
                "Granting OlympusAuthority policy role to DAO multisig",
                _getDaoMultisig()
            );
            auth.pushPolicy(_getDaoMultisig(), true);

            // OlympusAuthority governor
            console2.log(
                "Granting OlympusAuthority governor role to DAO multisig",
                _getDaoMultisig()
            );
            auth.pushGovernor(_getDaoMultisig(), true);
        }

        console2.log("Roles granted");

        vm.stopBroadcast();
    }

    /// @notice Deploys a new Bophades installation to a new chain
    /// @dev    Deploys the following contracts:
    ///         - OlympusAuthority
    ///         - OlympusERC20Token (OHM)
    ///         - Kernel
    ///         - OlympusMinter
    ///         - OlympusRoles
    ///         - OlympusTreasury
    ///         - RolesAdmin
    ///         - Emergency
    ///         - TreasuryCustodian
    ///         - CCIPBurnMintTokenPool
    ///         - CCIPCrossChainBridge
    ///         - CCIPTokenPoolConfig
    ///         - CCIPTokenPoolConfigTimelock
    ///         - Minter (testnet only)
    /// @dev    The CCIP pool, config policy and timelock are activated in the Kernel.
    ///         All four CCIP contracts remain disabled.
    ///         CCIP registration, routes and enabling are separate configuration steps.
    /// @param chain_ Chain key in env.json.
    /// @param shouldDeployOhm_ Deploy Authority and OHM instead of reusing the registry entries.
    /// @return addresses JSON registry keys and addresses, saved in the Forge broadcast for the wrapper.
    function deploy(
        string calldata chain_,
        bool shouldDeployOhm_
    ) external returns (string memory addresses) {
        _loadEnv(chain_);

        // Require CCIP infrastructure before starting any deployment transactions.
        address rmnProxy = _envAddressNotZero("external.ccip.RMN");
        address ccipRouter = _envAddressNotZero("external.ccip.Router");
        bool isTestnet_ = isTestnet(chain_);

        console2.log("");
        console2.log("Deploying to", chain_);
        console2.log("Is testnet:", isTestnet_);
        console2.log("Initial Kernel executor:", msg.sender);
        console2.log("CCIP Router:", ccipRouter);
        console2.log("CCIP RMN:", rmnProxy);

        vm.startBroadcast();

        OlympusAuthority auth;
        OlympusERC20Token ohm;
        if (shouldDeployOhm_) {
            // Keep deployer as vault in order to transfer minter role after OHM
            // token is deployed
            auth = new OlympusAuthority(
                msg.sender, // governor/owner, will be set to daoMultisig in grantRoles()
                msg.sender, // guardian, will be set to daoMultisig in grantRoles()
                msg.sender, // policy, will be set to daoMultisig in grantRoles()
                msg.sender // vault, will be set to MINTR in grantRoles()
            );
            ohm = new OlympusERC20Token(address(auth));
            _recordDeployment("olympus.legacy.OlympusAuthority", address(auth));
            _recordDeployment("olympus.legacy.OHM", address(ohm));
        } else {
            auth = OlympusAuthority(_envAddressNotZero("olympus.legacy.OlympusAuthority"));
            ohm = OlympusERC20Token(_envAddressNotZero("olympus.legacy.OHM"));
        }

        // Set addresses for dependencies
        Kernel kernel = new Kernel();
        _recordDeployment("olympus.Kernel", address(kernel));

        OlympusMinter MINTR = new OlympusMinter(kernel, address(ohm));
        _recordDeployment("olympus.modules.OlympusMinter", address(MINTR));

        OlympusRoles ROLES = new OlympusRoles(kernel);
        _recordDeployment("olympus.modules.OlympusRoles", address(ROLES));

        OlympusTreasury TRSRY = new OlympusTreasury(kernel);
        _recordDeployment("olympus.modules.OlympusTreasury", address(TRSRY));

        RolesAdmin rolesAdmin = new RolesAdmin(kernel);
        _recordDeployment("olympus.policies.RolesAdmin", address(rolesAdmin));

        Emergency emergency = new Emergency(kernel);
        _recordDeployment("olympus.policies.Emergency", address(emergency));

        TreasuryCustodian treasuryCustodian = new TreasuryCustodian(kernel);
        _recordDeployment("olympus.policies.TreasuryCustodian", address(treasuryCustodian));

        CCIPBurnMintTokenPool ccipTokenPool = new CCIPBurnMintTokenPool(
            address(kernel),
            address(ohm),
            rmnProxy,
            ccipRouter
        );
        _recordDeployment("olympus.policies.CCIPBurnMintTokenPool", address(ccipTokenPool));

        CCIPCrossChainBridge ccipBridge = new CCIPCrossChainBridge(
            address(ohm),
            ccipRouter,
            msg.sender
        );
        _recordDeployment("olympus.periphery.CCIPCrossChainBridge", address(ccipBridge));

        Minter minter;
        if (isTestnet_) {
            minter = new Minter(kernel);
            _recordDeployment("olympus.policies.Minter", address(minter));
        }

        // Execute actions on Kernel

        console2.log("");
        console2.log("Installing modules/policies in Kernel");

        // Install Modules
        kernel.executeAction(Actions.InstallModule, address(MINTR));
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.InstallModule, address(TRSRY));

        // Activate Policies
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(emergency));
        kernel.executeAction(Actions.ActivatePolicy, address(treasuryCustodian));
        kernel.executeAction(Actions.ActivatePolicy, address(ccipTokenPool));
        if (isTestnet_) {
            kernel.executeAction(Actions.ActivatePolicy, address(minter));
        }
        _deployCCIPConfig(kernel, address(ccipTokenPool));
        console2.log("Kernel actions complete");
        vm.stopBroadcast();

        console2.log("");
        console2.log("Deployments complete");
        console2.log("shell/L2/deploy.sh saves the returned addresses after broadcast succeeds");
        return _deploymentAddresses;
    }

    /// @dev Collect registry keys with the deployments, for the shared writer after broadcast.
    function _recordDeployment(string memory key_, address deployed_) internal {
        console2.log(key_, "deployed at:", deployed_);
        _deploymentAddresses = vm.serializeAddress("l2Deployment", key_, deployed_);
    }

    /// @dev Uses the same configuration keys as DeployV3's CCIP sequences.
    function _deployCCIPConfig(Kernel kernel_, address pool_) internal {
        uint32 gracePeriod = SafeCast.encodeUInt32(
            _envUintNotZero("olympus.config.CCIPTokenPoolConfig.gracePeriod")
        );
        uint48 timelockDelay = SafeCast.encodeUInt48(
            _envUintNotZero("olympus.config.CCIPTokenPoolConfig.timelockDelay")
        );

        CCIPTokenPoolConfig config = new CCIPTokenPoolConfig(kernel_, pool_, gracePeriod);
        _recordDeployment("olympus.policies.CCIPTokenPoolConfig", address(config));
        CCIPTokenPoolConfigTimelock timelock = new CCIPTokenPoolConfigTimelock(
            kernel_,
            address(config),
            timelockDelay,
            gracePeriod
        );
        _recordDeployment("olympus.policies.CCIPTokenPoolConfigTimelock", address(timelock));

        kernel_.executeAction(Actions.ActivatePolicy, address(config));
        console2.log("CCIPTokenPoolConfig activated in Kernel:", address(config));
        kernel_.executeAction(Actions.ActivatePolicy, address(timelock));
        console2.log("CCIPTokenPoolConfigTimelock activated in Kernel:", address(timelock));
        console2.log("Both policies remain operationally disabled until CCIP setup");
    }

    /// @notice Deploys a new CrossChainBridge
    function deployBridge(string calldata chain_) public {
        _loadEnv(chain_);

        address kernel = _envAddressNotZero("olympus.Kernel");
        address lzEndpoint = _envAddressNotZero("external.layerzero.endpoint");

        console2.log("Deploying bridge to", chain_);
        console2.log("Kernel:", kernel);
        console2.log("LZ Endpoint:", lzEndpoint);

        vm.startBroadcast();
        CrossChainBridge bridge = new CrossChainBridge(Kernel(kernel), lzEndpoint);
        vm.stopBroadcast();
        console2.log("Bridge deployed at:", address(bridge));
    }

    /// @notice Installs a deployed CrossChainbridge in the Kernel and grants the "bridge_admin" role to the caller.
    /// @dev    The caller must be the kernel executor
    function installBridge(string calldata chain_) public {
        _loadEnv(chain_);

        address kernel = _envAddressNotZero("olympus.Kernel");
        address rolesAdmin = _envAddressNotZero("olympus.policies.RolesAdmin");
        address crossChainBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");

        console2.log("Installing bridge in Kernel");
        console2.log("Kernel:", kernel);
        console2.log("RolesAdmin:", rolesAdmin);
        console2.log("CrossChainBridge:", crossChainBridge);

        vm.startBroadcast();
        Kernel(kernel).executeAction(Actions.ActivatePolicy, address(crossChainBridge));
        RolesAdmin(rolesAdmin).grantRole("bridge_admin", msg.sender);
        vm.stopBroadcast();

        console2.log("Bridge installed in Kernel");
    }

    /// @notice Configures a CrossChainBridge to trust messages from another bridge
    /// @dev    The caller must have the "bridge_admin" role
    ///
    ///         This should be run on the CrossChainBridge that will receive messages from the remote bridge
    function setupBridge(string calldata localChain_, string calldata remoteChain_) public {
        _loadEnv(localChain_);

        address localBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");
        address remoteBridge = _envAddressNotZero(
            remoteChain_,
            "olympus.policies.CrossChainBridge"
        );
        uint16 remoteLzChainId = _getRemoteEndpointId(remoteChain_);

        console2.log("Setting up bridge on chain", localChain_);
        console2.log("Remote chain:", remoteChain_);
        console2.log("Local bridge:", localBridge);
        console2.log("Remote bridge:", remoteBridge);
        console2.log("Remote LZ chain ID:", remoteLzChainId);

        vm.startBroadcast();
        CrossChainBridge(localBridge).setTrustedRemoteAddress(
            remoteLzChainId,
            abi.encodePacked(remoteBridge)
        );
        vm.stopBroadcast();

        console2.log("Bridge setup complete");
    }

    /// @notice Grants the "bridge_admin" role to an address
    /// @dev    The caller must be the role admin
    ///         This is unlikely to be needed, as deploy/installBridge will grant the role to the deployer and handOffToMultisig will grant it to the multisig
    function grantBridgeAdminRole(address rolesAdmin_, address to_) public {
        vm.startBroadcast();
        RolesAdmin(rolesAdmin_).grantRole("bridge_admin", to_);
        vm.stopBroadcast();
    }

    /// @notice Completes the handoff of the installation from the deployer to the multisig
    /// @dev    The caller must be the deployer
    function handoffToMultisig(string calldata chain_) public {
        _loadEnv(chain_);

        address daoMultisig = _getDaoMultisig();
        address kernel = _envAddressNotZero("olympus.Kernel");
        address rolesAdmin = _envAddressNotZero("olympus.policies.RolesAdmin");

        console2.log("Starting handoff to DAO multisig", daoMultisig);

        vm.startBroadcast();

        if (_envAddress("olympus.policies.CrossChainBridge") != address(0)) {
            console2.log("Removing bridge_admin role from deployer", msg.sender);
            RolesAdmin(rolesAdmin).revokeRole("bridge_admin", msg.sender);

            console2.log("Granting bridge_admin role to DAO multisig", daoMultisig);
            RolesAdmin(rolesAdmin).grantRole("bridge_admin", daoMultisig);
        }

        address ccipTokenPool = _envAddress("olympus.policies.CCIPBurnMintTokenPool");
        if (ccipTokenPool != address(0)) {
            console2.log("Proposing DAO multisig as CCIP pool owner", daoMultisig);
            CCIPBurnMintTokenPool(ccipTokenPool).transferOwnership(daoMultisig);
        }

        address ccipBridge = _envAddress("olympus.periphery.CCIPCrossChainBridge");
        if (ccipBridge != address(0)) {
            console2.log("Transferring CCIP bridge ownership to DAO multisig", daoMultisig);
            CCIPCrossChainBridge(ccipBridge).transferOwnership(daoMultisig);
        }

        // Propose DAO multisig as new admin
        console2.log("Proposing DAO multisig as new admin", daoMultisig);
        RolesAdmin(rolesAdmin).pushNewAdmin(daoMultisig);

        console2.log("Changing executor to multisig", daoMultisig);
        Kernel(kernel).executeAction(Actions.ChangeExecutor, daoMultisig);
        vm.stopBroadcast();

        console2.log("HANDOFF PENDING: DAO Safe acceptance is required");
        console2.log("shell/L2/handoff.sh creates the L2HandoffBatch.acceptHandoff Safe proposal");
        console2.log("Deployer retains pending-transfer authority until the DAO accepts");
        console2.log("After acceptance, run shell/L2/verify.sh --chain <chain>");
    }

    /// @notice Reports ownership and deployer access at the current RPC block without changing chain state.
    /// @dev Addresses come from env.json. The wrapper reads the deployer and ROLES creation block
    ///      from the saved broadcast receipts.
    ///      Every role granted since that block is checked, including roles outside the bootstrap list.
    ///      Returns false rather than reverting so Forge shows every failed check. The wrapper exits nonzero.
    /// @param chain_ Registry chain key.
    /// @param deployer_ Sender of the ROLES creation transaction.
    /// @param rolesCreationBlock_ Block containing the confirmed ROLES creation transaction.
    /// @return passed Whether the DAO handoff is complete and the deployer has no checked administrative access.
    function verifyOwnership(
        string calldata chain_,
        address deployer_,
        uint256 rolesCreationBlock_
    ) external returns (bool passed) {
        _loadEnv(chain_);
        address dao = _getDaoMultisig();
        if (
            deployer_ == address(0) ||
            deployer_ == dao ||
            deployer_ == _getEmergencyMultisig() ||
            rolesCreationBlock_ > block.number
        ) revert L2Deploy_InvalidVerificationInput();
        _ownershipFailures = 0;
        console2.log("=== L2 ownership and deployer access verification ===");
        console2.log("Deployer:", deployer_);
        console2.log("DAO Safe:", dao);
        console2.log("RPC block:", block.number);

        Kernel kernel = Kernel(_envAddressNotZero("olympus.Kernel"));
        OlympusRoles roles = OlympusRoles(_envAddressNotZero("olympus.modules.OlympusRoles"));
        address mintr = _envAddressNotZero("olympus.modules.OlympusMinter");
        _checkOwnership("Kernel executor is DAO Safe", kernel.executor() == dao);
        _checkOwnership(
            "Recorded ROLES is installed in Kernel",
            address(kernel.getModuleForKeycode(toKeycode("ROLES"))) == address(roles)
        );
        _checkOwnership(
            "Recorded MINTR is installed in Kernel",
            address(kernel.getModuleForKeycode(toKeycode("MINTR"))) == mintr
        );

        RolesAdmin rolesAdmin = RolesAdmin(_envAddressNotZero("olympus.policies.RolesAdmin"));
        _checkOwnership(
            "RolesAdmin uses the recorded Kernel and ROLES",
            address(rolesAdmin.kernel()) == address(kernel) &&
                address(rolesAdmin.ROLES()) == address(roles)
        );
        _checkOwnership("RolesAdmin admin is DAO Safe", rolesAdmin.admin() == dao);
        _checkOwnership("RolesAdmin has no pending admin", rolesAdmin.newAdmin() == address(0));
        _verifyAuthority(deployer_, dao, mintr);
        _verifyCCIPOwnership(deployer_, dao);
        _verifyDeployerRoles(roles, deployer_, rolesCreationBlock_);

        passed = _ownershipFailures == 0;
        console2.log("Failed ownership checks:", _ownershipFailures);
        console2.log(passed ? "OWNERSHIP VERIFICATION: PASS" : "OWNERSHIP VERIFICATION: FAIL");
    }

    function _verifyAuthority(address deployer_, address dao_, address mintr_) internal {
        OlympusAuthority auth = OlympusAuthority(
            _envAddressNotZero("olympus.legacy.OlympusAuthority")
        );
        OlympusERC20Token ohm = OlympusERC20Token(_envAddressNotZero("olympus.legacy.OHM"));
        _checkOwnership(
            "OHM uses the recorded Authority",
            address(ohm.authority()) == address(auth)
        );
        _checkOwnership(
            "Authority uses itself for access control",
            address(auth.authority()) == address(auth)
        );
        _checkOwnership("Authority governor is DAO Safe", auth.governor() == dao_);
        _checkOwnership("Authority guardian is DAO Safe", auth.guardian() == dao_);
        _checkOwnership("Authority policy is DAO Safe", auth.policy() == dao_);
        _checkOwnership("Authority vault is MINTR", auth.vault() == mintr_ && mintr_ != deployer_);
        _checkOwnership(
            "Authority pending governor is zero or DAO Safe",
            auth.newGovernor() == address(0) || auth.newGovernor() == dao_
        );
        _checkOwnership(
            "Authority pending guardian is zero or DAO Safe",
            auth.newGuardian() == address(0) || auth.newGuardian() == dao_
        );
        _checkOwnership(
            "Authority pending policy is zero or DAO Safe",
            auth.newPolicy() == address(0) || auth.newPolicy() == dao_
        );
        _checkOwnership(
            "Authority pending vault is zero or MINTR",
            auth.newVault() == address(0) || auth.newVault() == mintr_
        );
    }

    function _verifyCCIPOwnership(address deployer_, address dao_) internal {
        CCIPBurnMintTokenPool pool = CCIPBurnMintTokenPool(
            _envAddressNotZero("olympus.policies.CCIPBurnMintTokenPool")
        );
        address config = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfig");
        address timelock = _envAddressNotZero("olympus.policies.CCIPTokenPoolConfigTimelock");
        address kernel = _envAddressNotZero("olympus.Kernel");
        _checkOwnership(
            "CCIP policies use the recorded Kernel",
            address(pool.kernel()) == kernel &&
                address(CCIPTokenPoolConfig(config).kernel()) == kernel &&
                address(CCIPTokenPoolConfigTimelock(timelock).kernel()) == kernel
        );
        _checkOwnership(
            "Config and timelock are bound to the recorded pool",
            CCIPTokenPoolConfig(config).pool() == address(pool) &&
                CCIPTokenPoolConfigTimelock(timelock).config() == config
        );
        address poolOwner = pool.owner();
        address pendingOwner = CCIPConfigLib.pendingOwner(address(pool));
        console2.log("Pool owner:", poolOwner);
        console2.log("Pool pending owner:", pendingOwner);
        _checkOwnership(
            "Pool owner is DAO Safe or config policy",
            (poolOwner == dao_ || poolOwner == config) && poolOwner != deployer_
        );
        _checkOwnership(
            "Pool pending owner is zero or config policy",
            pendingOwner == address(0) || (pendingOwner == config && pendingOwner != deployer_)
        );
        address rateLimitAdmin = pool.getRateLimitAdmin();
        _checkOwnership(
            "Pool rate limit admin matches configuration and is not deployer",
            rateLimitAdmin == _envAddress("olympus.config.CCIPTokenPoolConfig.rateLimitAdmin") &&
                rateLimitAdmin != deployer_
        );
        _checkOwnership(
            "CCIP bridge owner is DAO Safe",
            CCIPCrossChainBridge(_envAddressNotZero("olympus.periphery.CCIPCrossChainBridge"))
                .owner() == dao_
        );
        address operator = CCIPTokenPoolConfig(config).configOperator();
        _checkOwnership(
            "Config operator is unset or timelock, not deployer",
            (operator == address(0) || operator == timelock) && operator != deployer_
        );

        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = ICCIPTokenAdminRegistry(
            _envAddressNotZero("external.ccip.TokenAdminRegistry")
        ).getTokenConfig(_envAddressNotZero("olympus.legacy.OHM"));
        _checkOwnership(
            "Token registry admin is unset or DAO Safe",
            tokenConfig.administrator == address(0) || tokenConfig.administrator == dao_
        );
        _checkOwnership(
            "Token registry pending admin is unset or DAO Safe",
            tokenConfig.pendingAdministrator == address(0) ||
                tokenConfig.pendingAdministrator == dao_
        );
    }

    function _verifyDeployerRoles(
        OlympusRoles roles_,
        address deployer_,
        uint256 fromBlock_
    ) internal {
        bytes32[] memory topics = new bytes32[](1);
        topics[0] = keccak256("RoleGranted(bytes32,address)");
        console2.log("Checking all ROLES grants from creation block:", fromBlock_);
        uint256 grants;
        bool noRoles = true;
        // Bound each RPC log query instead of relying on an unrestricted historical block range.
        for (uint256 start = fromBlock_; start <= block.number; ) {
            uint256 end = start + 999;
            if (end > block.number) end = block.number;
            Vm.EthGetLogs[] memory logs = vm.eth_getLogs(start, end, address(roles_), topics);
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics[2] != bytes32(uint256(uint160(deployer_)))) continue;
                ++grants;
                bytes32 role = logs[i].topics[1];
                console2.log("Historical deployer role:");
                console2.logBytes32(role);
                bool held = roles_.hasRole(deployer_, role);
                if (held) noRoles = false;
                _checkOwnership("Deployer no longer holds this role", !held);
            }
            start = end + 1;
        }
        console2.log("Historical grants to deployer checked:", grants);
        _checkOwnership("Deployer holds no ROLES roles", noRoles);
    }

    function _checkOwnership(string memory label_, bool passed_) internal {
        console2.log(string.concat(passed_ ? "[PASS] " : "[FAIL] ", label_));
        if (!passed_) ++_ownershipFailures;
    }

    function verifyBerachain(string calldata chain_) public {
        _loadEnv(chain_);

        OlympusERC20Token ohm = OlympusERC20Token(_envAddressNotZero("olympus.legacy.OHM"));
        OlympusAuthority olympusAuthority = OlympusAuthority(
            _envAddressNotZero("olympus.legacy.OlympusAuthority")
        );
        Kernel kernel = Kernel(_envAddressNotZero("olympus.Kernel"));
        OlympusMinter MINTR = OlympusMinter(_envAddressNotZero("olympus.modules.OlympusMinter"));
        OlympusRoles ROLES = OlympusRoles(_envAddressNotZero("olympus.modules.OlympusRoles"));
        RolesAdmin rolesAdmin = RolesAdmin(_envAddressNotZero("olympus.policies.RolesAdmin"));
        CrossChainBridge berachainBridge = CrossChainBridge(
            _envAddressNotZero("olympus.policies.CrossChainBridge")
        );
        CrossChainBridge mainnetBridge = CrossChainBridge(
            _envAddressNotZero("mainnet", "olympus.policies.CrossChainBridge")
        );

        console2.log("Verifying ownership of contracts");

        {
            console2.log("Verifying OHM and OlympusAuthority");
            require(
                address(ohm.authority()) == address(olympusAuthority),
                "OHM authority should be the OlympusAuthority"
            );
            require(
                olympusAuthority.governor() == _getDaoMultisig(),
                "OlympusAuthority governor should be the DAO multisig"
            );
            require(
                olympusAuthority.guardian() == _getDaoMultisig(),
                "OlympusAuthority guardian should be the DAO multisig"
            );
            require(
                olympusAuthority.policy() == _getDaoMultisig(),
                "OlympusAuthority policy should be the DAO multisig"
            );
            require(
                olympusAuthority.vault() == address(MINTR),
                "OlympusAuthority vault should be MINTR"
            );
        }

        {
            console2.log("Verifying Kernel");
            require(
                kernel.executor() == _getDaoMultisig(),
                "Kernel executor should be the DAO multisig"
            );
        }

        {
            console2.log("Verifying roles");
            require(
                rolesAdmin.admin() == _getDaoMultisig(),
                "RolesAdmin admin should be the DAO multisig"
            );
            require(
                ROLES.hasRole(_getEmergencyMultisig(), "emergency_shutdown") == true,
                "emergency_shutdown role should be granted to the emergency multisig"
            );
            require(
                ROLES.hasRole(_getEmergencyMultisig(), "emergency_restart") == true,
                "emergency_restart role should be granted to the emergency multisig"
            );
            require(
                ROLES.hasRole(_getDaoMultisig(), "custodian") == true,
                "custodian role should be granted to the DAO multisig"
            );
            require(
                ROLES.hasRole(_getDaoMultisig(), "bridge_admin") == true,
                "bridge_admin role should be granted to the DAO multisig"
            );
            require(
                ROLES.hasRole(0x1A5309F208f161a393E8b5A253de8Ab894A67188, "bridge_admin") == false,
                "bridge_admin role should not be granted to the Olympus deployer (0x1A5309F208f161a393E8b5A253de8Ab894A67188)"
            );
        }

        {
            console2.log("Verifying CrossChainBridge");
            require(
                _bytesEqual(
                    berachainBridge.getTrustedRemoteAddress(101),
                    abi.encodePacked(address(mainnetBridge))
                ),
                "Berachain CrossChainBridge should trust messages from the mainnet CrossChainBridge"
            );
        }
    }

    function verifyMainnet(string calldata chain_) public {
        _loadEnv(chain_);

        CrossChainBridge mainnetBridge = CrossChainBridge(
            _envAddressNotZero("mainnet", "olympus.policies.CrossChainBridge")
        );
        CrossChainBridge berachainBridge = CrossChainBridge(
            _envAddressNotZero("berachain", "olympus.policies.CrossChainBridge")
        );

        require(
            _bytesEqual(
                mainnetBridge.getTrustedRemoteAddress(362),
                abi.encodePacked(address(berachainBridge))
            ),
            "Mainnet CrossChainBridge should trust messages from the Berachain CrossChainBridge"
        );
    }
}
