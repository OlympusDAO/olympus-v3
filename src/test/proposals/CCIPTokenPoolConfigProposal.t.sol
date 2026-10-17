// SPDX-License-Identifier: UNLICENSED
// solhint-disable one-contract-per-file
// The rig, the two suites and the two proposal harnesses belong to one file: the harnesses
// exist only for these suites, and splitting them would hide that. The labelled preconditions
// of the rig fail on the first bad entry of a route or lane loop, which is the point of a
// precondition, so the loop-revert note is suppressed file-wide.
// forge-lint: disable-start(multi-contract-file, require-revert-in-loop)
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPLockReleaseTokenPool} from "src/external/bridge/ICCIPLockReleaseTokenPool.sol";
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenAdminRegistry} from "src/external/bridge/ICCIPTokenAdminRegistry.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ICCIPFeeOnRamp15, ICCIPFeeOnRampConfig, ICCIPFeeQuoter20, ICCIPFeeRouter, ICCIPFeeTypeAndVersion} from "src/scripts/ops/lib/CCIPFeeBudgetLib.sol";

// Libraries
import {stdJson} from "@forge-std-1.16.2/StdJson.sol";
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";
import {CCIPFeeBudgetLib} from "src/scripts/ops/lib/CCIPFeeBudgetLib.sol";

// Constants
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, BRIDGE_RATE_LIMITER_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Owned} from "@solmate-6.2.0/auth/Owned.sol";
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {CCIPTokenPoolConfig} from "src/policies/bridge/CCIPTokenPoolConfig.sol";
import {CCIPTokenPoolConfigTimelock} from "src/policies/bridge/CCIPTokenPoolConfigTimelock.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {CCIPTokenPoolConfigProposal} from "src/proposals/CCIPTokenPoolConfigProposal.sol";
import {ProposalTest} from "./ProposalTest.sol";

/// @notice Shared rig of the `CCIPTokenPoolConfigProposal` suites: a mainnet fork pinned at a
///         block that still satisfies every live precondition of the rollout, the config pair
///         deployed over the live lock/release pool and registered with the proposal simulator's
///         address registry, the Phase B batch and the pool funding as replayable steps, and the
///         OHM fee entries the build requires stubbed on the live fee contracts.
/// @dev    The proposal instance the suites run is `CCIPTokenPoolConfigProposalHarness`, which
///         patches the counterpart burn/mint pools of `env.json` in memory (see its NatSpec).
///         The rig itself reads the tracked `env.json` for every other desired-state value, so
///         the assertions follow the file rather than repeating its numbers.
///
///         Live preconditions are checked with labelled requires: a failure there means mainnet
///         has moved past the pin, not that the proposal is broken.
abstract contract CCIPTokenPoolConfigProposalTest is ProposalTest {
    using stdJson for string;

    // ========== FORK PIN ========== //

    /// @notice A mainnet block of 2026-09-04, the pin of the `CCIPFeeBudgetLib` fork suite, so
    ///         both suites share the cached RPC responses. At this block the DAO MS is still the
    ///         Kernel executor, the pool owner and the OHM administrator, the OCG timelock holds
    ///         `admin`, the pool serves the Solana route only and carries no rate limit admin,
    ///         and the three ramp generations in scope are live (`OnRamp 2.0.0` toward Arbitrum
    ///         and Optimism, `OnRamp 1.6.0` toward Base, `EVM2EVMOnRamp 1.5.0` toward
    ///         Berachain), so the fee stub exercises every dispatch branch of the reader.
    uint256 public constant BLOCK = 25_903_191;

    /// @dev The OCG proposal id. Must match `CCIPTokenPoolConfigProposal.id()`.
    uint256 internal constant _PROPOSAL_ID = 19;

    /// @dev The proposal name and the first line of its description.
    string internal constant _PROPOSAL_NAME = "CCIP Bridge Activation";

    /// @dev The `env.json` names of the four burn/mint chains this proposal opens, in the remote
    ///      chain name order that `CCIPConfigLib.desiredRoutes` sorts into.
    uint256 internal constant _NEW_ROUTE_COUNT = 4;

    /// @dev The largest action list the proposal can build.
    uint256 internal constant _MAX_ACTION_COUNT = 12;

    /// @dev The path of the desired-state file, as the proposal reads it.
    string internal constant _ENV_PATH = "./src/scripts/env.json";

    /// @dev The data availability byte count of the stubbed OHM fee entry, as the Anvil
    ///      rehearsal writes it. Only `destGasOverhead` and `isEnabled` are read by the budget
    ///      check, so the other fields carry neutral values.
    uint32 internal constant _STUB_DEST_BYTES_OVERHEAD = 32;

    /// @dev The width of an ABI word, in bytes.
    uint256 internal constant _WORD_BYTES = 32;

    /// @dev The width of a function selector, in bytes.
    uint256 internal constant _SELECTOR_BYTES = 4;

    /// @dev The rate limits of the live route that no `env.json` declaration covers, in OHM base
    ///      units. Enabled with `0 < rate < capacity`, the only shape the pool accepts.
    uint128 internal constant _UNDECLARED_ROUTE_CAPACITY = 1_000;
    uint128 internal constant _UNDECLARED_ROUTE_RATE = 1;

    /// @dev Solana rate limits that `env.json` does not declare, in OHM base units. Both buckets
    ///      stay enabled with `0 < rate < capacity`, so the declared-and-enabled check passes and
    ///      the field comparison is what fails.
    uint128 internal constant _DRIFTED_OUTBOUND_CAPACITY = 9_000_000_000_000;
    uint128 internal constant _DRIFTED_OUTBOUND_RATE = 1_000_000;
    uint128 internal constant _DRIFTED_INBOUND_CAPACITY = 8_000_000_000_000;
    uint128 internal constant _DRIFTED_INBOUND_RATE = 900_000;

    // ========== DEPLOYMENT TOGGLES ========== //

    /// @dev False while `src/proposals/addresses.json` records the zero address for both config
    ///      policies: `setUp` deploys them over the live pool and registers them. Set to true
    ///      once they are deployed on Ethereum and recorded, and `setUp` reads them instead.
    bool public constant IS_CONTRACTS_DEPLOYED = false;

    // ========== ENVIRONMENT ========== //

    /// @notice The tracked `env.json`, as the rig reads it. The proposal reads the patched copy.
    string internal _env;

    // ========== CONTRACTS ========== //

    CCIPTokenPoolConfigProposalHarness internal proposal;
    CCIPTokenPoolConfig internal config;
    CCIPTokenPoolConfigTimelock internal timelock;

    Kernel internal kernel;
    RolesAdmin internal rolesAdmin;
    ROLESv1 internal roles;
    ICCIPTokenAdminRegistry internal registry;
    ICCIPTokenPoolAdmin internal pool;
    IERC20 internal ohm;

    // ========== ADDRESSES ========== //

    address internal bridge;
    address internal daoMS;
    address internal emergencyMS;
    address internal ocgTimelock;
    address internal proposer;

    /// @notice The stand-in for the counterpart burn/mint pools, which are not deployed yet. The
    ///         four routes share it, since nothing requires their remote pools to differ.
    address internal placeholderPool;

    // ========== DESIRED STATE (env.json) ========== //

    uint64 internal solanaSelector;
    uint256 internal minimumPoolBacking;
    uint32 internal gracePeriod;
    uint48 internal timelockDelay;
    address internal desiredRebalancer;
    address internal desiredRateLimitAdmin;

    /// @notice One declared route of the mainnet pool, resolved to the values the proposal
    ///         builds its `addChain` action from.
    struct RouteSpec {
        string name;
        uint64 chainSelector;
        bytes remoteToken;
        bytes remotePool;
        ICCIPRateLimiter.Config outbound;
        ICCIPRateLimiter.Config inbound;
    }

    /// @notice The four routes the proposal opens, in remote chain name order.
    RouteSpec[] internal newRoutes;

    /// @notice One expected proposal action.
    struct ExpectedAction {
        address target;
        bytes data;
        string label;
    }

    // ========== SETUP ========== //

    function setUp() public virtual {
        vm.createSelectFork(_RPC_ALIAS, BLOCK);
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        _env = vm.readFile(_ENV_PATH);

        // ========== PROPOSAL SETUP ========== //

        placeholderPool = makeAddr("counterpartBurnMintPool");
        proposal = new CCIPTokenPoolConfigProposalHarness(placeholderPool);
        vm.label(address(proposal), "CCIPTokenPoolConfigProposalHarness");

        // Set to true once the proposal has been submitted on-chain, so that the framework
        // checks the simulated calldata against the submitted one.
        hasBeenSubmitted = false;

        _setupSuite(address(proposal));

        // ========== LOAD LIVE ADDRESSES ========== //

        // `Addresses` labels every entry it loads from `src/proposals/addresses.json`, so the
        // live contracts below are already named in traces.
        kernel = Kernel(addresses.getAddress("olympus-kernel"));
        roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        rolesAdmin = RolesAdmin(addresses.getAddress("olympus-policy-roles-admin"));
        registry = ICCIPTokenAdminRegistry(
            addresses.getAddress("external-ccip-token-admin-registry")
        );
        pool = ICCIPTokenPoolAdmin(
            addresses.getAddress("olympus-periphery-ccip-lock-release-token-pool")
        );
        ohm = IERC20(addresses.getAddress("olympus-legacy-ohm"));
        bridge = addresses.getAddress("olympus-periphery-ccip-cross-chain-bridge");
        daoMS = addresses.getAddress("olympus-multisig-dao");
        emergencyMS = addresses.getAddress("olympus-multisig-emergency");
        ocgTimelock = addresses.getAddress("olympus-timelock");
        proposer = addresses.getAddress("proposer");

        // ========== LOAD THE DESIRED STATE ========== //

        // casting to 'uint32' and 'uint48' is safe because the declared grace period and
        // timelock delay are second counts far below their type maxima, and the config policy
        // and its timelock take the same widths
        // forge-lint: disable-next-line(unsafe-typecast)
        gracePeriod = uint32(_envUint("mainnet", "olympus.config.CCIPTokenPoolConfig.gracePeriod"));
        // forge-lint: disable-next-item(unsafe-typecast)
        timelockDelay = uint48(
            _envUint("mainnet", "olympus.config.CCIPTokenPoolConfig.timelockDelay")
        );
        desiredRebalancer = _envAddress("mainnet", "olympus.config.CCIPTokenPoolConfig.rebalancer");
        desiredRateLimitAdmin = _env.readAddress(
            "$.current.mainnet.olympus.config.CCIPTokenPoolConfig.rateLimitAdmin"
        );
        minimumPoolBacking = _envUint("mainnet", "olympus.config.CCIP.minimumPoolBacking");
        solanaSelector = _envChainSelector("solana");

        // ========== CONDITIONAL DEPLOYMENT ========== //

        if (IS_CONTRACTS_DEPLOYED) {
            config = CCIPTokenPoolConfig(
                addresses.getAddress("olympus-policy-ccip-token-pool-config")
            );
            timelock = CCIPTokenPoolConfigTimelock(
                addresses.getAddress("olympus-policy-ccip-token-pool-config-timelock")
            );
        } else {
            require(
                addresses._addresses("olympus-policy-ccip-token-pool-config", block.chainid) ==
                    address(0),
                "live: addresses.json should record no CCIPTokenPoolConfig"
            );
            require(
                addresses._addresses(
                    "olympus-policy-ccip-token-pool-config-timelock",
                    block.chainid
                ) == address(0),
                "live: addresses.json should record no CCIPTokenPoolConfigTimelock"
            );

            config = new CCIPTokenPoolConfig(kernel, address(pool), gracePeriod);
            vm.label(address(config), "CCIPTokenPoolConfig");
            timelock = new CCIPTokenPoolConfigTimelock(
                kernel,
                address(config),
                timelockDelay,
                gracePeriod
            );
            vm.label(address(timelock), "CCIPTokenPoolConfigTimelock");

            addresses.addAddress(
                "olympus-policy-ccip-token-pool-config",
                address(config),
                block.chainid
            );
            addresses.addAddress(
                "olympus-policy-ccip-token-pool-config-timelock",
                address(timelock),
                block.chainid
            );
        }

        // ========== LIVE PRECONDITIONS ========== //

        _requireLiveState();

        // ========== ROUTE SPECS AND THE PATCHED ENVIRONMENT ========== //

        string[_NEW_ROUTE_COUNT] memory names = ["arbitrum", "base", "berachain", "optimism"];
        for (uint256 i = 0; i < names.length; ++i) {
            newRoutes.push(
                RouteSpec({
                    name: names[i],
                    chainSelector: _envChainSelector(names[i]),
                    remoteToken: abi.encode(_envAddress(names[i], "olympus.legacy.OHM")),
                    remotePool: abi.encode(placeholderPool),
                    outbound: _envRouteLimit(names[i], "outboundRateLimit"),
                    inbound: _envRouteLimit(names[i], "inboundRateLimit")
                })
            );
        }

        _requirePatchedEnvRoutes();

        // ========== OHM FEE BUDGETS ========== //

        _stubOhmFeeEntries("");
        _requireOhmFeeBudgets("");
    }

    // ========== ENVIRONMENT READERS ========== //

    function _envAddress(
        string memory chain_,
        string memory key_
    ) internal view returns (address value) {
        return _env.readAddress(string.concat("$.current.", chain_, ".", key_));
    }

    function _envUint(
        string memory chain_,
        string memory key_
    ) internal view returns (uint256 value) {
        return _env.readUint(string.concat("$.current.", chain_, ".", key_));
    }

    function _envChainSelector(string memory chain_) internal view returns (uint64 selector) {
        // casting to 'uint64' is safe because CCIP chain selectors are uint64 values
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint64(_envUint(chain_, "external.ccip.ChainSelector"));
    }

    /// @notice One directional rate limiter configuration of a mainnet route declaration.
    function _envRouteLimit(
        string memory remoteChain_,
        string memory direction_
    ) internal view returns (ICCIPRateLimiter.Config memory limit) {
        string memory prefix = string.concat(
            "$.current.mainnet.olympus.config.CCIP.routes.",
            remoteChain_,
            ".",
            direction_
        );
        return
            ICCIPRateLimiter.Config({
                isEnabled: _env.readBool(string.concat(prefix, ".isEnabled")),
                // casting to 'uint128' is safe because the declared limits are OHM base units
                // far below the uint128 maximum, the width the pool buckets carry
                // forge-lint: disable-next-line(unsafe-typecast)
                capacity: uint128(_env.readUint(string.concat(prefix, ".capacity"))),
                // forge-lint: disable-next-line(unsafe-typecast)
                rate: uint128(_env.readUint(string.concat(prefix, ".rate")))
            });
    }

    // ========== LIVE PRECONDITIONS ========== //

    /// @notice The live state every suite depends on. A failure here means the pin is stale or
    ///         the rollout has advanced on mainnet, not that a proposal step regressed.
    function _requireLiveState() internal view {
        require(kernel.executor() == daoMS, "live: the DAO MS should be the Kernel executor");
        require(pool.owner() == daoMS, "live: the DAO MS should own the pool");
        require(
            CCIPConfigLib.pendingOwner(address(pool)) == address(0),
            "live: the pool should carry no pending owner"
        );
        require(pool.getToken() == address(ohm), "live: the pool should serve OHM");
        require(
            pool.getRateLimitAdmin() == address(0),
            "live: the pool should carry no rate limit admin"
        );
        require(
            rolesAdmin.admin() == ocgTimelock,
            "live: the OCG timelock should administer RolesAdmin"
        );
        require(
            roles.hasRole(ocgTimelock, ADMIN_ROLE),
            "live: the OCG timelock should hold the admin role"
        );
        require(
            roles.hasRole(emergencyMS, EMERGENCY_ROLE),
            "live: the Emergency MS should hold the emergency role"
        );
        require(
            Owned(bridge).owner() == daoMS,
            "live: the DAO MS should own the CCIPCrossChainBridge periphery"
        );

        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = registry.getTokenConfig(
            address(ohm)
        );
        require(
            tokenConfig.administrator == daoMS,
            "live: the DAO MS should administer OHM in the registry"
        );
        require(
            tokenConfig.pendingAdministrator == address(0),
            "live: no OHM administrator transfer should be pending"
        );
        require(
            tokenConfig.tokenPool == address(pool),
            "live: the registry should point at the pool"
        );

        uint64[] memory liveSelectors = pool.getSupportedChains();
        require(liveSelectors.length == 1, "live: the pool should serve exactly one route");
        require(
            liveSelectors[0] == solanaSelector,
            "live: the only route of the pool should be the Solana one"
        );
    }

    /// @notice Proves the harness patch before the suites rely on it: the four counterpart pools
    ///         of the patched environment resolve to the labelled placeholder. A fragment that no
    ///         longer matches the file reaches this as a zero address instead.
    function _requirePatchedEnvRoutes() internal view {
        CCIPConfigLib.DesiredRoute[] memory desired = CCIPConfigLib.desiredRoutes(
            proposal.readEnv(),
            "mainnet"
        );
        require(
            desired.length == _NEW_ROUTE_COUNT + 1,
            "patch: mainnet should declare the four new routes and the Solana one"
        );

        bytes memory expectedPool = abi.encode(placeholderPool);
        for (uint256 i = 0; i < newRoutes.length; ++i) {
            CCIPConfigLib.DesiredRoute memory route = _findDesiredRoute(
                desired,
                newRoutes[i].chainSelector
            );
            require(
                route.remotePools.length == 1,
                string.concat(
                    "patch: route ",
                    newRoutes[i].name,
                    " should resolve exactly one remote pool"
                )
            );
            require(
                keccak256(route.remotePools[0]) == keccak256(expectedPool),
                string.concat(
                    "patch: route ",
                    newRoutes[i].name,
                    " should resolve the placeholder as its remote pool"
                )
            );
        }
    }

    function _findDesiredRoute(
        CCIPConfigLib.DesiredRoute[] memory desired_,
        uint64 chainSelector_
    ) internal pure returns (CCIPConfigLib.DesiredRoute memory route) {
        for (uint256 i = 0; i < desired_.length; ++i) {
            if (desired_[i].chainSelector == chainSelector_) return desired_[i];
        }
        revert("patch: the declared route is missing from the patched environment");
    }

    // ========== OHM FEE BUDGET STUBS ========== //

    /// @notice Writes an enabled OHM fee entry of the required budget on every mainnet lane
    ///         toward a burn/mint chain, except `skipChain_`. The entry is stubbed on the
    ///         contract the reader queries, resolved per lane exactly as the reader resolves it:
    ///         the `FeeQuoter 2.x` named by word zero of an `OnRamp` dynamic config, or the
    ///         dedicated `EVM2EVMOnRamp 1.5` of a legacy lane. The generation of a lane is never
    ///         hardcoded: Chainlink moves lanes between generations without notice.
    function _stubOhmFeeEntries(string memory skipChain_) internal {
        string[_NEW_ROUTE_COUNT] memory names = ["arbitrum", "base", "berachain", "optimism"];
        for (uint256 i = 0; i < names.length; ++i) {
            if (_sameString(names[i], skipChain_)) continue;
            _stubOhmFeeEntry(names[i]);
        }
    }

    function _stubOhmFeeEntry(string memory remoteChain_) internal {
        address ohmAddress = address(ohm);
        uint64 destSelector = _envChainSelector(remoteChain_);
        (address onRamp, CCIPFeeBudgetLib.TypeAndVersion memory version) = _laneOnRamp(
            remoteChain_
        );

        if (_sameString(version.family, "EVM2EVMOnRamp")) {
            vm.mockCall(
                onRamp,
                abi.encodeCall(ICCIPFeeOnRamp15.getTokenTransferFeeConfig, (ohmAddress)),
                abi.encode(
                    ICCIPFeeOnRamp15.TokenTransferFeeConfig({
                        minFeeUSDCents: 0,
                        maxFeeUSDCents: 0,
                        deciBps: 0,
                        destGasOverhead: CCIPFeeBudgetLib.OHM_MIN_DEST_GAS_OVERHEAD,
                        destBytesOverhead: _STUB_DEST_BYTES_OVERHEAD,
                        aggregateRateLimitEnabled: false,
                        isEnabled: true
                    })
                )
            );
            return;
        }

        address feeQuoter = _laneFeeQuoter(onRamp, remoteChain_);
        vm.mockCall(
            feeQuoter,
            abi.encodeCall(ICCIPFeeQuoter20.getTokenTransferFeeConfig, (destSelector, ohmAddress)),
            abi.encode(
                ICCIPFeeQuoter20.TokenTransferFeeConfig({
                    feeUSDCents: 0,
                    destGasOverhead: CCIPFeeBudgetLib.OHM_MIN_DEST_GAS_OVERHEAD,
                    destBytesOverhead: _STUB_DEST_BYTES_OVERHEAD,
                    isEnabled: true
                })
            )
        );
    }

    /// @notice The on-ramp of a mainnet lane and its parsed `typeAndVersion`.
    function _laneOnRamp(
        string memory remoteChain_
    ) internal view returns (address onRamp, CCIPFeeBudgetLib.TypeAndVersion memory version) {
        address router = _envAddress("mainnet", "external.ccip.Router");
        onRamp = ICCIPFeeRouter(router).getOnRamp(_envChainSelector(remoteChain_));
        require(
            onRamp != address(0),
            string.concat("live: the mainnet router should serve a lane to ", remoteChain_)
        );

        bool parsed = false;
        (version, parsed) = CCIPFeeBudgetLib.parseTypeAndVersion(
            ICCIPFeeTypeAndVersion(onRamp).typeAndVersion()
        );
        require(
            parsed,
            string.concat(
                "live: the on-ramp of the lane mainnet -> ",
                remoteChain_,
                " should report a parseable typeAndVersion"
            )
        );
        require(
            _sameString(version.family, "OnRamp") || _sameString(version.family, "EVM2EVMOnRamp"),
            string.concat(
                "live: unsupported on-ramp family on the lane mainnet -> ",
                remoteChain_,
                ": ",
                version.raw
            )
        );
    }

    /// @notice The fee quoter of an `OnRamp` lane: word zero of its raw dynamic config, whose
    ///         length differs by generation.
    function _laneFeeQuoter(
        address onRamp_,
        string memory remoteChain_
    ) internal view returns (address feeQuoter) {
        // The return is measured by hand because its length differs by generation
        // solhint-disable-next-line avoid-low-level-calls
        // forge-lint: disable-next-item(low-level-calls)
        (bool ok, bytes memory data) = onRamp_.staticcall(
            abi.encodeCall(ICCIPFeeOnRampConfig.getDynamicConfig, ())
        );
        require(
            ok && data.length >= _WORD_BYTES,
            string.concat(
                "live: the on-ramp of the lane mainnet -> ",
                remoteChain_,
                " should answer getDynamicConfig()"
            )
        );
        feeQuoter = abi.decode(data, (address));
        require(
            feeQuoter != address(0),
            string.concat(
                "live: the on-ramp of the lane mainnet -> ",
                remoteChain_,
                " should name a fee quoter"
            )
        );
    }

    /// @notice Proves the stubs answer the reader the proposal calls, before any build runs.
    function _requireOhmFeeBudgets(string memory skipChain_) internal view {
        string[_NEW_ROUTE_COUNT] memory names = ["arbitrum", "base", "berachain", "optimism"];
        for (uint256 i = 0; i < names.length; ++i) {
            if (_sameString(names[i], skipChain_)) continue;
            (uint32 overhead, bool isTokenEntry, ) = CCIPFeeBudgetLib.readOhmDestGasOverhead(
                _env,
                "mainnet",
                names[i]
            );
            require(
                isTokenEntry,
                string.concat(
                    "stub: the lane mainnet -> ",
                    names[i],
                    " should read back an enabled OHM token entry"
                )
            );
            require(
                overhead == CCIPFeeBudgetLib.OHM_MIN_DEST_GAS_OVERHEAD,
                string.concat(
                    "stub: the lane mainnet -> ",
                    names[i],
                    " should read back the required OHM delivery gas budget"
                )
            );
        }
    }

    /// @notice The revert message `CCIPFeeBudgetLib.requireOhmFeeBudget` raises on a lane whose
    ///         applicable budget is the chain default, built from the live read so that it holds
    ///         at any pin and at any lane generation.
    function _missingOhmFeeEntryMessage(
        string memory remoteChain_
    ) internal view returns (string memory message) {
        (uint32 overhead, bool isTokenEntry, string memory source) = CCIPFeeBudgetLib
            .readOhmDestGasOverhead(_env, "mainnet", remoteChain_);
        require(
            !isTokenEntry,
            string.concat(
                "stub: the lane mainnet -> ",
                remoteChain_,
                " should carry no OHM token entry here"
            )
        );
        return
            string.concat(
                "CCIPFeeBudgetLib: the OHM delivery gas budget of the lane mainnet -> ",
                remoteChain_,
                " has no enabled OHM token entry (the applicable value is the chain default ",
                vm.toString(overhead),
                "; ",
                source,
                "); request an enabled OHM fee entry of at least ",
                vm.toString(uint256(CCIPFeeBudgetLib.OHM_MIN_DEST_GAS_OVERHEAD)),
                " from Chainlink before opening the route"
            );
    }

    // ========== ROLLOUT STEPS ========== //

    /// @notice The Kernel half of the Phase B batch.
    function _activatePolicies() internal {
        address configAddress = address(config);
        address timelockAddress = address(timelock);
        vm.startPrank(daoMS);
        kernel.executeAction(Actions.ActivatePolicy, configAddress);
        kernel.executeAction(Actions.ActivatePolicy, timelockAddress);
        vm.stopPrank();
    }

    /// @notice The registry half of the Phase B batch: a nomination, not a transfer.
    function _nominateRegistryAdmin() internal {
        address ohmAddress = address(ohm);
        address nominee = ocgTimelock;
        vm.prank(daoMS);
        registry.transferAdminRole(ohmAddress, nominee);
    }

    /// @notice The pool half of the Phase B batch: a proposal, not a transfer.
    function _proposePoolOwnership() internal {
        address configAddress = address(config);
        vm.prank(daoMS);
        pool.transferOwnership(configAddress);
    }

    /// @notice The whole Phase B batch (`CCIPTokenPoolConfigBatch.prepareHandover`).
    function _runPhaseB() internal {
        _activatePolicies();
        _proposePoolOwnership();
        _nominateRegistryAdmin();
    }

    /// @notice The funding step (`CCIPTokenPoolBatch.fundPool`): the DAO MS transfers the
    ///         shortfall in real OHM, never a mint.
    function _fundPoolToMinimumBacking() internal {
        uint256 balance = ohm.balanceOf(address(pool));
        if (balance >= minimumPoolBacking) return;

        uint256 deficit = minimumPoolBacking - balance;
        require(
            ohm.balanceOf(daoMS) >= deficit,
            "live: the DAO MS should hold enough OHM to fund the pool"
        );
        address poolAddress = address(pool);
        vm.prank(daoMS);
        bool funded = ohm.transfer(poolAddress, deficit);
        assertTrue(funded, "The funding transfer should succeed");
    }

    // ========== POOL MUTATIONS (the DAO MS is still the owner before execution) ========== //

    function _daoSetSolanaRateLimits(
        ICCIPRateLimiter.Config memory outbound_,
        ICCIPRateLimiter.Config memory inbound_
    ) internal {
        uint64 selector = solanaSelector;
        vm.prank(daoMS);
        pool.setChainRateLimiterConfig(selector, outbound_, inbound_);
    }

    function _daoAddRoute(ICCIPTokenPoolAdmin.ChainUpdate memory update_) internal {
        uint64[] memory removals = new uint64[](0);
        ICCIPTokenPoolAdmin.ChainUpdate[] memory additions = new ICCIPTokenPoolAdmin.ChainUpdate[](
            1
        );
        additions[0] = update_;
        vm.prank(daoMS);
        pool.applyChainUpdates(removals, additions);
    }

    function _daoRemoveRoute(uint64 chainSelector_) internal {
        uint64[] memory removals = new uint64[](1);
        removals[0] = chainSelector_;
        ICCIPTokenPoolAdmin.ChainUpdate[] memory additions = new ICCIPTokenPoolAdmin.ChainUpdate[](
            0
        );
        vm.prank(daoMS);
        pool.applyChainUpdates(removals, additions);
    }

    /// @notice Solana rate limits that `env.json` does not declare, for the drift gates.
    function _driftedSolanaLimits()
        internal
        pure
        returns (ICCIPRateLimiter.Config memory outbound, ICCIPRateLimiter.Config memory inbound)
    {
        outbound = ICCIPRateLimiter.Config({
            isEnabled: true,
            capacity: _DRIFTED_OUTBOUND_CAPACITY,
            rate: _DRIFTED_OUTBOUND_RATE
        });
        inbound = ICCIPRateLimiter.Config({
            isEnabled: true,
            capacity: _DRIFTED_INBOUND_CAPACITY,
            rate: _DRIFTED_INBOUND_RATE
        });
    }

    // ========== EXPECTED ACTIONS ========== //

    /// @notice The action list the proposal must build, derived from the live state the way the
    ///         proposal derives it, so that a re-pin does not invalidate the assertion.
    /// @dev    One branch per conditional action of the proposal, in the proposal's own order.
    ///         Splitting the chain would hide that correspondence, which is the point of the
    ///         assertion, so the complexity note is suppressed rather than refactored away.
    // forge-lint: disable-next-item(cyclomatic-complexity)
    function _expectedActions() internal view returns (ExpectedAction[] memory expected) {
        ExpectedAction[_MAX_ACTION_COUNT] memory buffer;
        uint256 count = 0;

        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = registry.getTokenConfig(
            address(ohm)
        );
        if (tokenConfig.administrator != ocgTimelock) {
            buffer[count++] = ExpectedAction({
                target: address(registry),
                data: abi.encodeWithSelector(
                    ICCIPTokenAdminRegistry.acceptAdminRole.selector,
                    address(ohm)
                ),
                label: "accept the OHM administrator role"
            });
        }
        if (!roles.hasRole(daoMS, BRIDGE_ADMIN_ROLE)) {
            buffer[count++] = ExpectedAction({
                target: address(rolesAdmin),
                data: abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    BRIDGE_ADMIN_ROLE,
                    daoMS
                ),
                label: "grant bridge_admin to the DAO MS"
            });
        }
        if (!config.isEnabled()) {
            buffer[count++] = ExpectedAction({
                target: address(config),
                data: abi.encodeWithSelector(IEnabler.enable.selector, ""),
                label: "enable CCIPTokenPoolConfig"
            });
        }
        if (pool.owner() != address(config)) {
            buffer[count++] = ExpectedAction({
                target: address(config),
                data: abi.encodeWithSelector(ICCIPTokenPoolConfig.acceptPoolOwnership.selector),
                label: "accept the pool ownership"
            });
        }
        if (config.configOperator() != address(timelock)) {
            buffer[count++] = ExpectedAction({
                target: address(config),
                data: abi.encodeWithSelector(
                    IConfigOperator.setConfigOperator.selector,
                    address(timelock)
                ),
                label: "set the config operator"
            });
        }
        if (ICCIPLockReleaseTokenPool(address(pool)).getRebalancer() != desiredRebalancer) {
            buffer[count++] = ExpectedAction({
                target: address(config),
                data: abi.encodeWithSelector(
                    ICCIPTokenPoolConfig.setRebalancer.selector,
                    desiredRebalancer
                ),
                label: "set the rebalancer"
            });
        }
        if (pool.getRateLimitAdmin() != desiredRateLimitAdmin) {
            buffer[count++] = ExpectedAction({
                target: address(config),
                data: abi.encodeWithSelector(
                    ICCIPTokenPoolConfig.setRateLimitAdmin.selector,
                    desiredRateLimitAdmin
                ),
                label: "set the native rate limit admin"
            });
        }
        if (!timelock.isEnabled()) {
            buffer[count++] = ExpectedAction({
                target: address(timelock),
                data: abi.encodeWithSelector(IEnabler.enable.selector, ""),
                label: "enable CCIPTokenPoolConfigTimelock"
            });
        }
        for (uint256 i = 0; i < newRoutes.length; ++i) {
            if (pool.isSupportedChain(newRoutes[i].chainSelector)) continue;
            buffer[count++] = ExpectedAction({
                target: address(config),
                data: abi.encodeWithSelector(
                    ICCIPTokenPoolConfig.addChain.selector,
                    _toChainUpdate(newRoutes[i])
                ),
                label: string.concat("add the ", newRoutes[i].name, " route")
            });
        }

        expected = new ExpectedAction[](count);
        for (uint256 i = 0; i < count; ++i) {
            expected[i] = buffer[i];
        }
    }

    function _toChainUpdate(
        RouteSpec memory spec_
    ) internal pure returns (ICCIPTokenPoolAdmin.ChainUpdate memory update) {
        bytes[] memory remotePools = new bytes[](1);
        remotePools[0] = spec_.remotePool;
        return
            ICCIPTokenPoolAdmin.ChainUpdate({
                remoteChainSelector: spec_.chainSelector,
                remotePoolAddresses: remotePools,
                remoteTokenAddress: spec_.remoteToken,
                outboundRateLimiterConfig: spec_.outbound,
                inboundRateLimiterConfig: spec_.inbound
            });
    }

    /// @notice The arguments of an encoded call, without its four-byte selector.
    function _callArguments(bytes memory payload_) internal pure returns (bytes memory args) {
        require(payload_.length >= _SELECTOR_BYTES, "the payload should carry a selector");
        args = new bytes(payload_.length - _SELECTOR_BYTES);
        for (uint256 i = 0; i < args.length; ++i) {
            args[i] = payload_[i + _SELECTOR_BYTES];
        }
    }

    function _selectorOf(bytes memory payload_) internal pure returns (bytes4 selector) {
        require(payload_.length >= _SELECTOR_BYTES, "the payload should carry a selector");
        return
            bytes4(
                (uint32(uint8(payload_[0])) << 24) |
                    (uint32(uint8(payload_[1])) << 16) |
                    (uint32(uint8(payload_[2])) << 8) |
                    uint32(uint8(payload_[3]))
            );
    }

    // ========== ROUTE OBSERVATION ========== //

    /// @notice The configuration fields of a bucket, without the fill level and the refill
    ///         timestamp, so a digest stays stable across skipped time.
    function _toConfig(
        ICCIPRateLimiter.TokenBucket memory bucket_
    ) internal pure returns (ICCIPRateLimiter.Config memory limit) {
        return
            ICCIPRateLimiter.Config({
                isEnabled: bucket_.isEnabled,
                capacity: bucket_.capacity,
                rate: bucket_.rate
            });
    }

    /// @notice Digest of one route: the remote token, the accepted remote pools and both bucket
    ///         configurations. Fill levels and refill timestamps are excluded on purpose.
    function _routeDigest(uint64 chainSelector_) internal view returns (bytes32 digest) {
        return
            keccak256(
                abi.encode(
                    pool.getRemoteToken(chainSelector_),
                    pool.getRemotePools(chainSelector_),
                    _toConfig(pool.getCurrentOutboundRateLimiterState(chainSelector_)),
                    _toConfig(pool.getCurrentInboundRateLimiterState(chainSelector_))
                )
            );
    }

    function _assertConfigEq(
        ICCIPRateLimiter.Config memory actual_,
        ICCIPRateLimiter.Config memory expected_,
        string memory label_
    ) internal pure {
        assertEq(actual_.isEnabled, expected_.isEnabled, string.concat(label_, ": isEnabled"));
        assertEq(actual_.capacity, expected_.capacity, string.concat(label_, ": capacity"));
        assertEq(actual_.rate, expected_.rate, string.concat(label_, ": rate"));
    }

    // ========== STRING HELPERS ========== //

    function _sameString(string memory a_, string memory b_) internal pure returns (bool same) {
        return keccak256(bytes(a_)) == keccak256(bytes(b_));
    }

    function _startsWith(
        string memory value_,
        string memory prefix_
    ) internal pure returns (bool starts) {
        bytes memory value = bytes(value_);
        bytes memory prefix = bytes(prefix_);
        if (value.length < prefix.length) return false;
        for (uint256 i = 0; i < prefix.length; ++i) {
            if (value[i] != prefix[i]) return false;
        }
        return true;
    }

    // ========== REVERT EXPECTATION HELPERS ========== //

    function _expectRevertPolicyNotActive(address policy_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPTokenPoolConfigProposal.CCIPTokenPoolConfigProposal_PolicyNotActive.selector,
                policy_
            )
        );
    }

    function _expectRevertPolicyNotEnabled(address policy_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPTokenPoolConfigProposal.CCIPTokenPoolConfigProposal_PolicyNotEnabled.selector,
                policy_
            )
        );
    }

    function _expectRevertPendingMismatch(
        string memory field_,
        address pending_,
        address expected_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPTokenPoolConfigProposal.CCIPTokenPoolConfigProposal_PendingMismatch.selector,
                field_,
                pending_,
                expected_
            )
        );
    }

    function _expectRevertAddressMismatch(
        string memory field_,
        address actual_,
        address expected_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPTokenPoolConfigProposal.CCIPTokenPoolConfigProposal_AddressMismatch.selector,
                field_,
                actual_,
                expected_
            )
        );
    }

    function _expectRevertMissingRole(bytes32 role_, address account_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPTokenPoolConfigProposal.CCIPTokenPoolConfigProposal_MissingRole.selector,
                role_,
                account_
            )
        );
    }

    function _expectRevertRoleNotUnassigned(bytes32 role_, address account_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPTokenPoolConfigProposal.CCIPTokenPoolConfigProposal_RoleNotUnassigned.selector,
                role_,
                account_
            )
        );
    }

    function _expectRevertRouteDrift(string memory remoteChain_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPTokenPoolConfigProposal.CCIPTokenPoolConfigProposal_RouteDrift.selector,
                remoteChain_
            )
        );
    }

    function _expectRevertMissingRouteSetMismatch(uint256 missing_, uint256 expected_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPTokenPoolConfigProposal
                    .CCIPTokenPoolConfigProposal_MissingRouteSetMismatch
                    .selector,
                missing_,
                expected_
            )
        );
    }
}

/// @notice The build stage: the proposal's `_deploy` and `_build` called directly on the
///         harness, with no simulation, so that every fail-closed precondition of `_build` can
///         be proved on the state that leaves exactly that precondition unmet.
/// @dev    Forge restores the post-`setUp` state before every test, so the harness starts each
///         test with an empty action list. Every negative test either reverts before the first
///         `_pushAction` or unwinds the pushes it made, so no action state leaks between tests.
contract CCIPTokenPoolConfigProposalTests_build is CCIPTokenPoolConfigProposalTest {
    function setUp() public virtual override {
        super.setUp();

        // The action dump of `getProposalActions` belongs to the simulation, not to the direct
        // build calls of this suite.
        proposal.setDebug(false);
    }

    // ========== STATE MODIFIERS ========== //

    modifier givenPoliciesActivated() {
        _activatePolicies();
        _;
    }

    // Named per Phase B half so that the partial-batch tests read as branching-tree conditions
    // forge-lint: disable-next-item(modifier-used-only-once)
    modifier givenRegistryNominated() {
        _nominateRegistryAdmin();
        _;
    }

    // forge-lint: disable-next-item(modifier-used-only-once)
    modifier givenPoolOwnershipProposed() {
        _proposePoolOwnership();
        _;
    }

    modifier givenPhaseBComplete() {
        _runPhaseB();
        _;
    }

    modifier givenPoolFunded() {
        _fundPoolToMinimumBacking();
        _;
    }

    // ========== ERROR CONDITIONS ========== //

    // given the tracked env.json records no counterpart burn/mint pools
    //   when the proposal is built
    //     [X] the desired-state reader reverts before any proposal check

    function test_givenPhaseBComplete_givenPoolFunded_givenCounterpartPoolsUnrecorded_reverts()
        public
        givenPhaseBComplete
        givenPoolFunded
    {
        // A zero placeholder makes the harness return the tracked file unchanged
        CCIPTokenPoolConfigProposalHarness unpatched = new CCIPTokenPoolConfigProposalHarness(
            address(0)
        );
        vm.label(address(unpatched), "unpatchedProposalHarness");
        unpatched.deploy(addresses, address(this));

        vm.expectRevert(
            bytes(
                "CCIPConfigLib: zero address for .current.arbitrum.olympus.policies.CCIPBurnMintTokenPool"
            )
        );
        unpatched.build(addresses);
    }

    // given Phase B has not run
    //   when the proposal is built
    //     [X] it reverts with PolicyNotActive naming the config policy

    function test_givenPhaseBNotRun_givenPoolFunded_reverts() public givenPoolFunded {
        proposal.deploy(addresses, address(this));

        _expectRevertPolicyNotActive(address(config));
        proposal.build(addresses);
    }

    // given both policies are active and the pool ownership is proposed
    //   given the OHM administrator role was never nominated
    //     when the proposal is built
    //       [X] it reverts with PendingMismatch on the OHM administrator

    function test_givenPoliciesActivated_givenPoolOwnershipProposed_givenPoolFunded_reverts()
        public
        givenPoliciesActivated
        givenPoolOwnershipProposed
        givenPoolFunded
    {
        proposal.deploy(addresses, address(this));

        _expectRevertPendingMismatch("OHM administrator", address(0), ocgTimelock);
        proposal.build(addresses);
    }

    // given both policies are active and the OHM administrator role is nominated
    //   given the pool ownership was never proposed
    //     when the proposal is built
    //       [X] it reverts with PendingMismatch on the pool owner

    function test_givenPoliciesActivated_givenRegistryNominated_givenPoolFunded_reverts()
        public
        givenPoliciesActivated
        givenRegistryNominated
        givenPoolFunded
    {
        proposal.deploy(addresses, address(this));

        _expectRevertPendingMismatch("pool owner", address(0), address(config));
        proposal.build(addresses);
    }

    // given Phase B is complete
    //   given the OCG timelock does not hold the admin role
    //     when the proposal is built
    //       [X] it reverts with MissingRole

    function test_givenPhaseBComplete_givenPoolFunded_givenAdminRoleRevoked_reverts()
        public
        givenPhaseBComplete
        givenPoolFunded
    {
        proposal.deploy(addresses, address(this));

        RolesAdmin rigRolesAdmin = rolesAdmin;
        address holder = ocgTimelock;
        vm.prank(rigRolesAdmin.admin());
        rigRolesAdmin.revokeRole(ADMIN_ROLE, holder);

        _expectRevertMissingRole(ADMIN_ROLE, ocgTimelock);
        proposal.build(addresses);
    }

    // given Phase B is complete
    //   given the pool holds less than the minimum backing
    //     when the proposal is built
    //       [X] it reverts with BackingTooLow naming the live balance and the minimum

    function test_givenPhaseBComplete_givenPoolNotFunded_reverts() public givenPhaseBComplete {
        proposal.deploy(addresses, address(this));

        uint256 liveBalance = ohm.balanceOf(address(pool));
        assertLt(liveBalance, minimumPoolBacking, "The live pool balance should be short");

        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPTokenPoolConfigProposal.CCIPTokenPoolConfigProposal_BackingTooLow.selector,
                liveBalance,
                minimumPoolBacking
            )
        );
        proposal.build(addresses);
    }

    // given Phase B is complete and the pool is funded
    //   given the first burn/mint lane carries no enabled OHM fee entry
    //     when the proposal is built
    //       [X] the fee budget reader reverts naming the lane and the applicable chain default

    function test_givenPhaseBComplete_givenPoolFunded_givenLaneWithoutOhmFeeEntry_reverts()
        public
        givenPhaseBComplete
        givenPoolFunded
    {
        proposal.deploy(addresses, address(this));

        // Arbitrum is the first burn/mint route in remote chain name order, so its lane is the
        // one the build reaches first.
        vm.clearMockedCalls();
        _stubOhmFeeEntries("arbitrum");
        _requireOhmFeeBudgets("arbitrum");

        vm.expectRevert(bytes(_missingOhmFeeEntryMessage("arbitrum")));
        proposal.build(addresses);
    }

    // given Phase B is complete and the pool is funded
    //   given the live Solana route carries rate limits that env.json does not declare
    //     when the proposal is built
    //       [X] it reverts with RouteDrift naming the Solana route

    function test_givenPhaseBComplete_givenPoolFunded_givenSolanaRouteDrifted_reverts()
        public
        givenPhaseBComplete
        givenPoolFunded
    {
        proposal.deploy(addresses, address(this));

        (
            ICCIPRateLimiter.Config memory outbound,
            ICCIPRateLimiter.Config memory inbound
        ) = _driftedSolanaLimits();
        _daoSetSolanaRateLimits(outbound, inbound);

        _expectRevertRouteDrift("solana");
        proposal.build(addresses);
    }

    // given Phase B is complete and the pool is funded
    //   given one bucket of the live Solana route is disabled
    //     when the proposal is built
    //       [X] it reverts with RouteLimiterDisabled before the drift comparison runs

    function test_givenPhaseBComplete_givenPoolFunded_givenSolanaRouteLimiterDisabled_reverts()
        public
        givenPhaseBComplete
        givenPoolFunded
    {
        proposal.deploy(addresses, address(this));

        ICCIPRateLimiter.Config memory inbound = _toConfig(
            pool.getCurrentInboundRateLimiterState(solanaSelector)
        );
        _daoSetSolanaRateLimits(
            ICCIPRateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inbound
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPTokenPoolConfigProposal
                    .CCIPTokenPoolConfigProposal_RouteLimiterDisabled
                    .selector,
                solanaSelector
            )
        );
        proposal.build(addresses);
    }

    // given Phase B is complete and the pool is funded
    //   given the pool serves a route that env.json does not declare
    //     when the proposal is built
    //       [X] it reverts with RouteUndeclared naming the selector

    function test_givenPhaseBComplete_givenPoolFunded_givenUndeclaredLiveRoute_reverts()
        public
        givenPhaseBComplete
        givenPoolFunded
    {
        proposal.deploy(addresses, address(this));

        uint64 undeclaredSelector = 1_234_567_890_123_456_789;
        bytes[] memory remotePools = new bytes[](1);
        remotePools[0] = abi.encode(makeAddr("undeclaredRemotePool"));
        _daoAddRoute(
            ICCIPTokenPoolAdmin.ChainUpdate({
                remoteChainSelector: undeclaredSelector,
                remotePoolAddresses: remotePools,
                remoteTokenAddress: abi.encode(makeAddr("undeclaredRemoteToken")),
                outboundRateLimiterConfig: ICCIPRateLimiter.Config({
                    isEnabled: true,
                    capacity: _UNDECLARED_ROUTE_CAPACITY,
                    rate: _UNDECLARED_ROUTE_RATE
                }),
                inboundRateLimiterConfig: ICCIPRateLimiter.Config({
                    isEnabled: true,
                    capacity: _UNDECLARED_ROUTE_CAPACITY,
                    rate: _UNDECLARED_ROUTE_RATE
                })
            })
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPTokenPoolConfigProposal.CCIPTokenPoolConfigProposal_RouteUndeclared.selector,
                undeclaredSelector
            )
        );
        proposal.build(addresses);
    }

    // given Phase B is complete and the pool is funded
    //   given one of the four expected routes was added directly beforehand
    //     when the proposal is built
    //       [X] it reverts with MissingRouteSetMismatch rather than building a smaller proposal

    function test_givenPhaseBComplete_givenPoolFunded_givenExpectedRouteAlreadyAdded_reverts()
        public
        givenPhaseBComplete
        givenPoolFunded
    {
        proposal.deploy(addresses, address(this));

        // Exactly the env.json declaration, so the drift comparison passes and the missing-set
        // check is what fails.
        _daoAddRoute(_toChainUpdate(newRoutes[0]));

        _expectRevertMissingRouteSetMismatch(_NEW_ROUTE_COUNT - 1, _NEW_ROUTE_COUNT);
        proposal.build(addresses);
    }

    // given Phase B is complete and the pool is funded
    //   given a declared route outside the four expected ones is missing from the pool
    //     when the proposal is built
    //       [X] it reverts with UnexpectedMissingRoute naming that route

    function test_givenPhaseBComplete_givenPoolFunded_givenSolanaRouteRemoved_reverts()
        public
        givenPhaseBComplete
        givenPoolFunded
    {
        proposal.deploy(addresses, address(this));

        _daoRemoveRoute(solanaSelector);

        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPTokenPoolConfigProposal
                    .CCIPTokenPoolConfigProposal_UnexpectedMissingRoute
                    .selector,
                "solana"
            )
        );
        proposal.build(addresses);
    }

    // given Phase B is complete and the pool is funded
    //   given env.json declares a rebalancer other than the OCG timelock
    //     when the proposal is built
    //       [X] it reverts with AddressMismatch naming the env.json key

    function test_givenPhaseBComplete_givenPoolFunded_givenEnvDeclaresAnotherRebalancer_reverts()
        public
        givenPhaseBComplete
        givenPoolFunded
    {
        CCIPTokenPoolConfigProposalRebalancerHarness drifted = new CCIPTokenPoolConfigProposalRebalancerHarness(
                placeholderPool
            );
        vm.label(address(drifted), "rebalancerDriftProposalHarness");
        drifted.deploy(addresses, address(this));

        _expectRevertAddressMismatch(
            "olympus.config.CCIPTokenPoolConfig.rebalancer",
            drifted.FOREIGN_REBALANCER(),
            ocgTimelock
        );
        drifted.build(addresses);
    }

    // given Phase B is complete and the pool is funded
    //   given the config policy reports a version other than 1.0
    //     when the proposal is built
    //       [X] it reverts with VersionMismatch

    function test_givenPhaseBComplete_givenPoolFunded_givenConfigReportsAnotherVersion_reverts()
        public
        givenPhaseBComplete
        givenPoolFunded
    {
        proposal.deploy(addresses, address(this));

        vm.mockCall(
            address(config),
            abi.encodeWithSelector(IVersioned.VERSION.selector),
            abi.encode(uint8(2), uint8(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPTokenPoolConfigProposal.CCIPTokenPoolConfigProposal_VersionMismatch.selector,
                address(config),
                uint8(2),
                uint8(0)
            )
        );
        proposal.build(addresses);
    }

    // given Phase B is complete and the pool is funded
    //   given the config policy does not advertise the liquidity container interface
    //     when the proposal is built
    //       [X] it reverts with NotLiquidityContainer naming the pool

    function test_givenPhaseBComplete_givenPoolFunded_givenPoolIsNotALiquidityContainer_reverts()
        public
        givenPhaseBComplete
        givenPoolFunded
    {
        proposal.deploy(addresses, address(this));

        vm.mockCall(
            address(config),
            abi.encodeWithSelector(ICCIPTokenPoolConfig.isLiquidityContainer.selector),
            abi.encode(false)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPTokenPoolConfigProposal
                    .CCIPTokenPoolConfigProposal_NotLiquidityContainer
                    .selector,
                address(pool)
            )
        );
        proposal.build(addresses);
    }

    // ========== SUCCESS CONDITIONS ========== //

    // given the proposal contract
    //   [X] it reports the OCG proposal id and the proposal name

    function test_proposalId() public view {
        assertEq(proposal.id(), _PROPOSAL_ID, "The proposal id should be 19");
        assertEq(proposal.name(), _PROPOSAL_NAME, "The proposal name should be the rollout name");
    }

    // given the proposal contract
    //   [X] its description is non-empty and opens with the proposal name as an H1

    function test_proposalDescription() public view {
        string memory description = proposal.description();
        assertGt(bytes(description).length, 0, "The description should not be empty");
        assertTrue(
            _startsWith(description, string.concat("# ", _PROPOSAL_NAME, "\n")),
            "The description should open with the proposal name as an H1"
        );
    }

    // given Phase B is complete and the pool is funded
    //   when the proposal is built
    //     [X] it builds the action list the live state calls for, and no more
    //     [X] the conditional actions the live state already satisfies are absent
    //     [X] each addChain action carries the env.json declaration of its route

    function test_givenPhaseBComplete_givenPoolFunded_whenBuilt()
        public
        givenPhaseBComplete
        givenPoolFunded
    {
        proposal.deploy(addresses, address(this));

        ExpectedAction[] memory expected = _expectedActions();
        proposal.build(addresses);

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = proposal
            .getProposalActions();

        assertEq(targets.length, expected.length, "The built action count should match");
        assertLe(
            targets.length,
            _MAX_ACTION_COUNT,
            "The proposal should never build more than twelve actions"
        );
        for (uint256 i = 0; i < expected.length; ++i) {
            assertEq(targets[i], expected[i].target, string.concat("target: ", expected[i].label));
            assertEq(payloads[i], expected[i].data, string.concat("payload: ", expected[i].label));
            assertEq(values[i], 0, string.concat("value: ", expected[i].label));
        }

        // The live state has converged on the two conditional writes the same-value rule of the
        // config policy would reject, so neither is built.
        assertTrue(
            roles.hasRole(daoMS, BRIDGE_ADMIN_ROLE),
            "The DAO MS should already hold bridge_admin at this pin"
        );
        assertEq(
            pool.getRateLimitAdmin(),
            desiredRateLimitAdmin,
            "The pool should already carry the declared rate limit admin at this pin"
        );

        // The four route actions carry the declared route, field by field
        uint256 routeActionOffset = expected.length - _NEW_ROUTE_COUNT;
        for (uint256 i = 0; i < newRoutes.length; ++i) {
            bytes memory payload = payloads[routeActionOffset + i];
            assertEq(
                _selectorOf(payload),
                ICCIPTokenPoolConfig.addChain.selector,
                string.concat("selector: add the ", newRoutes[i].name, " route")
            );
            ICCIPTokenPoolAdmin.ChainUpdate memory update = abi.decode(
                _callArguments(payload),
                (ICCIPTokenPoolAdmin.ChainUpdate)
            );
            string memory label = string.concat("route ", newRoutes[i].name);
            assertEq(
                update.remoteChainSelector,
                newRoutes[i].chainSelector,
                string.concat(label, ": chain selector")
            );
            assertEq(
                update.remoteTokenAddress,
                newRoutes[i].remoteToken,
                string.concat(label, ": remote token")
            );
            assertEq(
                update.remotePoolAddresses.length,
                1,
                string.concat(label, ": remote pool count")
            );
            assertEq(
                update.remotePoolAddresses[0],
                newRoutes[i].remotePool,
                string.concat(label, ": remote pool")
            );
            _assertConfigEq(
                update.outboundRateLimiterConfig,
                newRoutes[i].outbound,
                string.concat(label, ": outbound")
            );
            _assertConfigEq(
                update.inboundRateLimiterConfig,
                newRoutes[i].inbound,
                string.concat(label, ": inbound")
            );
        }
    }
}

/// @notice The execution stage: the whole rollout, then the proposal run through the governor by
///         the simulator, then the end state, the `_validate` gates, the rebuild and the steady
///         state the wiring must serve.
contract CCIPTokenPoolConfigProposalTests_execution is CCIPTokenPoolConfigProposalTest {
    /// @notice The Solana route digest captured before the proposal executes.
    bytes32 internal _solanaDigestBefore;

    function setUp() public virtual override {
        super.setUp();

        _runPhaseB();
        _fundPoolToMinimumBacking();
        _solanaDigestBefore = _routeDigest(solanaSelector);

        suite.setDebug(true);
        _simulateProposal();

        // Re-read addresses in case the simulation updated them
        addresses = suite.addresses();
    }

    // ========== END STATE ========== //

    // given the proposal has executed
    //   [X] both policies are active and enabled
    //   [X] the config policy owns the pool with no pending owner, and the timelock is its operator
    //   [X] the pool rebalancer and rate limit admin match env.json
    //   [X] the OCG timelock administers OHM with no pending administrator and the same pool
    //   [X] the roles are allocated as the authority model declares
    //   [X] the grace periods and the timelock delay match env.json
    //   [X] the pool serves the Solana route and the four new ones, each at capacity
    //   [X] the pool backing covers the declared minimum
    //   [X] the periphery owner is untouched

    function test_proposalEndState() public view {
        // Lifecycle
        assertTrue(kernel.isPolicyActive(config), "CCIPTokenPoolConfig should be active");
        assertTrue(kernel.isPolicyActive(timelock), "CCIPTokenPoolConfigTimelock should be active");
        assertTrue(config.isEnabled(), "CCIPTokenPoolConfig should be enabled");
        assertTrue(timelock.isEnabled(), "CCIPTokenPoolConfigTimelock should be enabled");

        // Pool authority
        assertEq(pool.owner(), address(config), "The config policy should own the pool");
        assertEq(
            CCIPConfigLib.pendingOwner(address(pool)),
            address(0),
            "No pool ownership transfer should stay pending"
        );
        assertEq(
            config.configOperator(),
            address(timelock),
            "The timelock should be the config operator"
        );
        assertEq(
            ICCIPLockReleaseTokenPool(address(pool)).getRebalancer(),
            desiredRebalancer,
            "The pool rebalancer should match env.json"
        );
        assertEq(
            desiredRebalancer,
            ocgTimelock,
            "env.json should declare the OCG timelock as the rebalancer"
        );
        assertEq(
            pool.getRateLimitAdmin(),
            desiredRateLimitAdmin,
            "The native rate limit admin should match env.json"
        );
        assertEq(
            desiredRateLimitAdmin,
            address(0),
            "env.json should declare no native rate limit admin"
        );

        // Registry
        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = registry.getTokenConfig(
            address(ohm)
        );
        assertEq(tokenConfig.administrator, ocgTimelock, "The OCG timelock should administer OHM");
        assertEq(
            tokenConfig.pendingAdministrator,
            address(0),
            "No OHM administrator transfer should stay pending"
        );
        assertEq(tokenConfig.tokenPool, address(pool), "The registered pool should be unchanged");

        // Roles
        assertTrue(roles.hasRole(ocgTimelock, ADMIN_ROLE), "The OCG timelock should hold admin");
        assertTrue(roles.hasRole(daoMS, BRIDGE_ADMIN_ROLE), "The DAO MS should hold bridge_admin");
        assertTrue(
            roles.hasRole(emergencyMS, EMERGENCY_ROLE),
            "The Emergency MS should hold emergency"
        );
        address[6] memory noRateLimiter = [
            daoMS,
            emergencyMS,
            ocgTimelock,
            address(config),
            address(timelock),
            proposer
        ];
        for (uint256 i = 0; i < noRateLimiter.length; ++i) {
            assertFalse(
                roles.hasRole(noRateLimiter[i], BRIDGE_RATE_LIMITER_ROLE),
                "bridge_rate_limiter should stay unassigned"
            );
        }

        // Parameters
        assertEq(
            config.gracePeriod(),
            gracePeriod,
            "The config grace period should match env.json"
        );
        assertEq(
            timelock.gracePeriod(),
            gracePeriod,
            "The timelock grace period should match env.json"
        );
        assertEq(
            timelock.timelockDelay(),
            timelockDelay,
            "The timelock delay should match env.json"
        );

        // Routes
        uint64[] memory liveSelectors = pool.getSupportedChains();
        assertEq(
            liveSelectors.length,
            _NEW_ROUTE_COUNT + 1,
            "The pool should serve the Solana route and the four new ones"
        );
        assertTrue(
            pool.isSupportedChain(solanaSelector),
            "The pool should still serve the Solana route"
        );
        for (uint256 i = 0; i < newRoutes.length; ++i) {
            RouteSpec memory spec = newRoutes[i];
            string memory label = string.concat("route ", spec.name);
            assertTrue(
                pool.isSupportedChain(spec.chainSelector),
                string.concat(label, ": should exist")
            );
            assertEq(
                pool.getRemoteToken(spec.chainSelector),
                spec.remoteToken,
                string.concat(label, ": remote token")
            );
            bytes[] memory remotePools = pool.getRemotePools(spec.chainSelector);
            assertEq(remotePools.length, 1, string.concat(label, ": remote pool count"));
            assertEq(remotePools[0], spec.remotePool, string.concat(label, ": remote pool"));

            ICCIPRateLimiter.TokenBucket memory outbound = pool.getCurrentOutboundRateLimiterState(
                spec.chainSelector
            );
            ICCIPRateLimiter.TokenBucket memory inbound = pool.getCurrentInboundRateLimiterState(
                spec.chainSelector
            );
            _assertConfigEq(_toConfig(outbound), spec.outbound, string.concat(label, ": outbound"));
            _assertConfigEq(_toConfig(inbound), spec.inbound, string.concat(label, ": inbound"));
            assertEq(
                outbound.tokens,
                spec.outbound.capacity,
                string.concat(label, ": the outbound bucket should start full")
            );
            assertEq(
                inbound.tokens,
                spec.inbound.capacity,
                string.concat(label, ": the inbound bucket should start full")
            );
            assertFalse(
                config.isChainDisabled(spec.chainSelector),
                string.concat(label, ": should not be contained")
            );
        }

        // Backing and periphery
        assertGe(
            ohm.balanceOf(address(pool)),
            minimumPoolBacking,
            "The pool backing should cover the declared minimum"
        );
        assertEq(
            Owned(bridge).owner(),
            daoMS,
            "The DAO MS should still own the CCIPCrossChainBridge periphery"
        );

        // A documented side effect of the simulator, not of the proposal: `_simulateActions`
        // moves the Kernel executor to the OCG timelock for the run.
        assertEq(
            kernel.executor(),
            ocgTimelock,
            "The simulator should have moved the Kernel executor to the OCG timelock"
        );
    }

    // given the proposal has executed
    //   [X] the pre-existing Solana route is byte-identical to its pre-proposal state

    function test_givenExecuted_solanaRouteIsUnchanged() public view {
        assertEq(
            _routeDigest(solanaSelector),
            _solanaDigestBefore,
            "The Solana route should survive the proposal untouched"
        );
    }

    // given the proposal has executed
    //   when the proposal validates the state
    //     [X] it passes

    function test_givenExecuted_whenValidated() public view {
        proposal.validate(addresses, proposer);
    }

    // ========== VALIDATION GATES ========== //

    // given the proposal has executed
    //   given bridge_rate_limiter is granted to the DAO MS
    //     when the proposal validates the state
    //       [X] it reverts with RoleNotUnassigned

    function test_givenExecuted_givenBridgeRateLimiterGranted_whenValidated_reverts() public {
        RolesAdmin rigRolesAdmin = rolesAdmin;
        address grantee = daoMS;
        vm.prank(rigRolesAdmin.admin());
        rigRolesAdmin.grantRole(BRIDGE_RATE_LIMITER_ROLE, grantee);

        _expectRevertRoleNotUnassigned(BRIDGE_RATE_LIMITER_ROLE, daoMS);
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given the Emergency MS has disabled the config policy
    //     when the proposal validates the state
    //       [X] it reverts with PolicyNotEnabled

    function test_givenExecuted_givenConfigDisabled_whenValidated_reverts() public {
        CCIPTokenPoolConfig rigConfig = config;
        vm.prank(emergencyMS);
        rigConfig.disable("");

        _expectRevertPolicyNotEnabled(address(config));
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given the OCG timelock has revoked the config operator
    //     when the proposal validates the state
    //       [X] it reverts with AddressMismatch on the config operator

    function test_givenExecuted_givenConfigOperatorRevoked_whenValidated_reverts() public {
        CCIPTokenPoolConfig rigConfig = config;
        vm.prank(ocgTimelock);
        rigConfig.setConfigOperator(address(0));

        _expectRevertAddressMismatch("config operator", address(0), address(timelock));
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given the DAO MS has transferred the periphery away
    //     when the proposal validates the state
    //       [X] it reverts with AddressMismatch on the periphery owner

    function test_givenExecuted_givenPeripheryTransferred_whenValidated_reverts() public {
        address newOwner = makeAddr("peripheryAcquirer");
        Owned rigBridge = Owned(bridge);
        vm.prank(daoMS);
        rigBridge.transferOwnership(newOwner);

        _expectRevertAddressMismatch("CCIPCrossChainBridge owner", newOwner, daoMS);
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given the OCG timelock has changed the Solana rate limits directly
    //     when the proposal validates the state
    //       [X] it reverts with RouteDrift naming the Solana route

    function test_givenExecuted_givenSolanaRateLimitsChanged_whenValidated_reverts() public {
        CCIPTokenPoolConfig rigConfig = config;
        uint64 selector = solanaSelector;
        (
            ICCIPRateLimiter.Config memory outbound,
            ICCIPRateLimiter.Config memory inbound
        ) = _driftedSolanaLimits();
        vm.prank(ocgTimelock);
        rigConfig.setChainRateLimits(selector, outbound, inbound);

        _expectRevertRouteDrift("solana");
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given the OCG timelock has removed one of the new routes
    //     when the proposal validates the state
    //       [X] it reverts with RouteMissing naming that route

    function test_givenExecuted_givenRouteRemoved_whenValidated_reverts() public {
        CCIPTokenPoolConfig rigConfig = config;
        uint64 selector = newRoutes[0].chainSelector;
        vm.prank(ocgTimelock);
        rigConfig.removeChain(selector);

        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPTokenPoolConfigProposal.CCIPTokenPoolConfigProposal_RouteMissing.selector,
                newRoutes[0].name
            )
        );
        proposal.validate(addresses, proposer);
    }

    // given the proposal has executed
    //   given the OCG timelock has changed the timelock delay
    //     when the proposal validates the state
    //       [X] it reverts with ParameterMismatch naming the delay

    function test_givenExecuted_givenTimelockDelayChanged_whenValidated_reverts() public {
        CCIPTokenPoolConfigTimelock rigTimelock = timelock;
        uint48 newDelay = timelockDelay + 1 days;
        vm.prank(ocgTimelock);
        rigTimelock.setTimelockDelay(newDelay);

        vm.expectRevert(
            abi.encodeWithSelector(
                CCIPTokenPoolConfigProposal.CCIPTokenPoolConfigProposal_ParameterMismatch.selector,
                "CCIPTokenPoolConfigTimelock delay",
                uint256(newDelay),
                uint256(timelockDelay)
            )
        );
        proposal.validate(addresses, proposer);
    }

    // ========== REBUILD AND STEADY STATE ========== //

    // given the proposal has executed
    //   when the proposal is built again
    //     [X] it reverts with MissingRouteSetMismatch, since its routes now exist

    function test_givenExecuted_whenBuiltAgain_reverts() public {
        _expectRevertMissingRouteSetMismatch(0, _NEW_ROUTE_COUNT);
        proposal.build(addresses);
    }

    // given the proposal has executed
    //   when the DAO MS queues a rate limit change and the delay elapses
    //     [X] anyone executes it and the buckets carry the new configuration
    //   when the Emergency MS contains a route
    //     [X] the route reports as disabled

    function test_givenExecuted_steadyStateAuthorityServes() public {
        CCIPTokenPoolConfigTimelock rigTimelock = timelock;
        uint64 selector = solanaSelector;
        (
            ICCIPRateLimiter.Config memory outbound,
            ICCIPRateLimiter.Config memory inbound
        ) = _driftedSolanaLimits();

        vm.prank(daoMS);
        uint64 actionId = rigTimelock.queueSetChainRateLimits(selector, outbound, inbound);

        skip(uint256(rigTimelock.timelockDelay()) + 1);

        address executor = makeAddr("permissionlessExecutor");
        vm.prank(executor);
        rigTimelock.executeQueuedAction(actionId);

        _assertConfigEq(
            _toConfig(pool.getCurrentOutboundRateLimiterState(solanaSelector)),
            outbound,
            "steady state: the Solana outbound bucket"
        );
        _assertConfigEq(
            _toConfig(pool.getCurrentInboundRateLimiterState(solanaSelector)),
            inbound,
            "steady state: the Solana inbound bucket"
        );

        // Containment stays available to the Emergency MS
        CCIPTokenPoolConfig rigConfig = config;
        uint64 containedSelector = newRoutes[0].chainSelector;
        vm.prank(emergencyMS);
        rigConfig.disableChain(containedSelector);

        assertTrue(
            config.isChainDisabled(newRoutes[0].chainSelector),
            "steady state: the contained route should report as disabled"
        );
    }
}

/// @notice Test harness over `CCIPTokenPoolConfigProposal`: it exposes the internal lifecycle
///         hooks as external calls and patches the counterpart burn/mint pools of `env.json` in
///         memory.
/// @dev    The tracked `src/scripts/env.json` records the zero address for the
///         `CCIPBurnMintTokenPool` of Arbitrum, Base, Berachain and Optimism, so the desired
///         route reader fails closed on it before any proposal check runs. The proposal must not
///         be run against a mutated tracked file and must leave no file behind, so the override
///         reads the tracked file on every use, as the proposal does, and replaces the four
///         byte-identical zero entries with one labelled placeholder in the returned string.
///         Nothing is stored: `vm.readFile` and `vm.replace` are cheatcodes and the transient
///         string is freed with the call.
///
///         A zero `placeholderPool_` disables the patch, so that a test can prove that the
///         tracked file fails closed in the reader.
contract CCIPTokenPoolConfigProposalHarness is CCIPTokenPoolConfigProposal {
    /// @dev The exact line fragment of the prettier-formatted `env.json` that records an
    ///      undeployed counterpart pool. All four burn/mint chains carry it verbatim, and
    ///      nothing requires the remote pools of different routes to differ, so the four routes
    ///      share one placeholder.
    string internal constant _ZERO_POOL_FRAGMENT =
        '"CCIPBurnMintTokenPool": "0x0000000000000000000000000000000000000000"';

    string internal constant _POOL_KEY_FRAGMENT = '"CCIPBurnMintTokenPool": "';

    /// @notice The stand-in for the counterpart burn/mint pools, or the zero address to read the
    ///         tracked file unchanged.
    address public immutable PLACEHOLDER_POOL;

    // The zero address is a meaningful value here: it disables the patch
    // forge-lint: disable-next-item(missing-zero-check)
    constructor(address placeholderPool_) {
        PLACEHOLDER_POOL = placeholderPool_;
    }

    /// @notice The desired-state string the proposal reads, for the rig's own assertions.
    function readEnv() external view returns (string memory env) {
        return _readEnv();
    }

    function deploy(Addresses addresses_, address deployer_) external {
        _deploy(addresses_, deployer_);
    }

    function build(Addresses addresses_) external {
        _build(addresses_);
    }

    function validate(Addresses addresses_, address caller_) external view {
        _validate(addresses_, caller_);
    }

    /// @inheritdoc CCIPTokenPoolConfigProposal
    function _readEnv() internal view virtual override returns (string memory env) {
        string memory tracked = super._readEnv();
        if (PLACEHOLDER_POOL == address(0)) return tracked;

        string memory patched = vm.replace(
            tracked,
            _ZERO_POOL_FRAGMENT,
            string.concat(_POOL_KEY_FRAGMENT, vm.toString(PLACEHOLDER_POOL), '"')
        );
        require(
            keccak256(bytes(patched)) != keccak256(bytes(tracked)),
            "CCIPTokenPoolConfigProposalHarness: the counterpart pool fragment no longer matches env.json"
        );
        return patched;
    }
}

/// @notice The harness above with the declared rebalancer of the local chain replaced by a
///         foreign address, so that the build's `AddressMismatch` gate on
///         `olympus.config.CCIPTokenPoolConfig.rebalancer` can be proved without mutating the
///         tracked file. The replaced fragment is built from the value the file declares, so it
///         follows a change of the OCG timelock address.
contract CCIPTokenPoolConfigProposalRebalancerHarness is CCIPTokenPoolConfigProposalHarness {
    using stdJson for string;

    string internal constant _REBALANCER_KEY_FRAGMENT = '"rebalancer": "';

    /// @notice The rebalancer the patched environment declares instead of the OCG timelock.
    address public constant FOREIGN_REBALANCER = 0x000000000000000000000000000000000000dEaD;

    constructor(address placeholderPool_) CCIPTokenPoolConfigProposalHarness(placeholderPool_) {}

    /// @inheritdoc CCIPTokenPoolConfigProposalHarness
    function _readEnv() internal view override returns (string memory env) {
        string memory patched = super._readEnv();
        address declared = patched.readAddress(
            string.concat(".current.", _chain(), ".olympus.config.CCIPTokenPoolConfig.rebalancer")
        );

        string memory drifted = vm.replace(
            patched,
            string.concat(_REBALANCER_KEY_FRAGMENT, vm.toString(declared), '"'),
            string.concat(_REBALANCER_KEY_FRAGMENT, vm.toString(FOREIGN_REBALANCER), '"')
        );
        require(
            keccak256(bytes(drifted)) != keccak256(bytes(patched)),
            "CCIPTokenPoolConfigProposalRebalancerHarness: the rebalancer fragment no longer matches env.json"
        );
        return drifted;
    }
}
