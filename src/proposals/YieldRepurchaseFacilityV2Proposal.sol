// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity ^0.8.24;

// Proposal code, run off-chain by forge to build and check the proposal: calls in loops are
// simulated rather than paid for on-chain, and a failed check is meant to abort the run.
// forge-lint: disable-start(calls-loop,require-revert-in-loop)

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Script
import {ProposalScript} from "src/proposals/ProposalScript.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {BackingOracleConfigLib} from "src/scripts/ops/lib/BackingOracleConfigLib.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";
import {YieldRepurchaseFacilityV2ConfigLib} from "src/scripts/ops/lib/YieldRepurchaseFacilityV2ConfigLib.sol";

// Interfaces
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IYieldRepoV1} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepoV1.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2Config} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Config.sol";
import {IYieldRepurchaseFacilityV2View} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2View.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IYieldRepurchaseFacilityV2Activator} from "src/proposals/interfaces/IYieldRepurchaseFacilityV2Activator.sol";

// Constants
import {ADMIN_ROLE, BACKING_ADMIN_ROLE, EMERGENCY_ROLE, YRF_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Policy, toKeycode} from "src/Kernel.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {fromSubKeycode} from "src/Submodules.sol";

// The proposal and the script that submits it share one file, like the other proposals here
// forge-lint: disable-start(multi-contract-file)

/// @title YieldRepurchaseFacilityV2Proposal
/// @notice OCG proposal that migrates the Yield Repurchase Facility from v1.2 to the multi-asset
///         YieldRepurchaseFacilityV2: it brings the facility, its configuration policy, its
///         config timelock and the BackingOracle with its config timelock into service, moves
///         the running weekly cycle of the YieldRepurchaseFacility v1.2 into the facility, and
///         delegates the operation of the stack to the DAO MS.
///
///         The launch itself is one call of the deployed `YieldRepurchaseFacilityV2Activator`,
///         which checks its preconditions when it executes and reverts with a named error when
///         one does not hold. The other actions grant and revoke roles: `yrf_admin` and
///         `backing_admin` for the DAO MS, the `admin` and `loop_daddy` roles of the activator
///         for the duration of its call, and the revocation of `loop_daddy` from the DAO MS and
///         the OCG timelock. The role actions for the DAO MS and the OCG timelock are
///         conditional on the live state, so a role that is already granted or revoked is not
///         touched; the grants and revocations for the activator are always included, and the
///         build rejects an activator that holds either role.
///
///         The build fails closed on everything that would make the launch impossible or
///         different from the reviewed one: an address missing from the registry, an activator
///         that is bound to other contracts than the registry records or that carries other
///         launch values than `env.json` declares, an activator that is activated or holds a
///         role, an OCG timelock that does not hold `admin` or does not administer RolesAdmin,
///         and a failing `checkPreconditions` of the activator.
///
///         Assumes:
///         - The BackingOracle, the BackingOracleConfigTimelock, the
///           YieldRepurchaseFacilityV2Config, the YieldRepurchaseFacilityV2ConfigTimelock, the
///           YieldRepurchaseFacilityV2 and the YieldRepurchaseFacilityV2Activator have been
///           deployed on Ethereum mainnet and recorded in `src/proposals/addresses.json` and
///           `src/scripts/env.json`.
///         - The DAO MS has run `YieldRepurchaseFacilityV2SetupBatch.setupKernel`: the five
///           policies are active in the Kernel and have never been enabled.
///         - The Safe that owns the Bond Protocol auctioneer has authorized the facility as a
///           market callback (`YieldRepurchaseFacilityV2SetupBatch.setCallbackAuthStatus`).
///         - The OCG timelock holds the `admin` role and administers RolesAdmin.
///         - The YieldRepurchaseFacility v1.2 is running: it is not shut down and is a periodic
///           task of the Heart.
///         - `olympus.config.YieldRepurchaseFacilityV2` and `olympus.config.BackingOracle` in
///           `src/scripts/env.json` carry the values the activator was deployed with.
contract YieldRepurchaseFacilityV2Proposal is GovernorBravoProposal {
    // ========== ERRORS ========== //

    /// @notice Thrown when the address registry records no address under a name.
    /// @param name The registry name.
    error YieldRepurchaseFacilityV2Proposal_AddressNotRecorded(string name);

    /// @notice Thrown when an address read from the chain or from `env.json` differs from the
    ///         expected one.
    /// @param field The name of the compared field.
    /// @param actual The value read.
    /// @param expected The expected value.
    error YieldRepurchaseFacilityV2Proposal_AddressMismatch(
        string field,
        address actual,
        address expected
    );

    /// @notice Thrown when a numeric value differs from the expected one.
    /// @param name The name of the compared value.
    /// @param actual The value read.
    /// @param expected The expected value.
    error YieldRepurchaseFacilityV2Proposal_ParameterMismatch(
        string name,
        uint256 actual,
        uint256 expected
    );

    /// @notice Thrown when a flag differs from the expected one.
    /// @param name The name of the compared flag.
    /// @param actual The value read.
    /// @param expected The expected value.
    error YieldRepurchaseFacilityV2Proposal_FlagMismatch(string name, bool actual, bool expected);

    /// @notice Thrown when the recorded activator holds no code or does not advertise
    ///         `IYieldRepurchaseFacilityV2Activator` through ERC165.
    /// @param activator The recorded activator.
    error YieldRepurchaseFacilityV2Proposal_InvalidActivator(address activator);

    /// @notice Thrown when `env.json` does not declare exactly the two assets of the launch,
    ///         the sUSDS vault and the sUSDe vault.
    /// @param declaredCount The number of declared assets.
    /// @param sUsdsDeclared Whether the sUSDS vault is declared.
    /// @param sUsdeDeclared Whether the sUSDe vault is declared.
    error YieldRepurchaseFacilityV2Proposal_AssetSetMismatch(
        uint256 declaredCount,
        bool sUsdsDeclared,
        bool sUsdeDeclared
    );

    /// @notice Thrown when `env.json` declares an asset of the launch with `enabled: false`.
    /// @param name The `env.json` name of the asset.
    error YieldRepurchaseFacilityV2Proposal_AssetDeclaredDisabled(string name);

    /// @notice Thrown when `SUSDE_NEXT_YIELD` exceeds the largest next yield the activator
    ///         accepts.
    /// @param nextYield The value of `SUSDE_NEXT_YIELD`, in USDe (18 decimals).
    /// @param maximum The largest next yield the activator accepts, in USDe (18 decimals).
    error YieldRepurchaseFacilityV2Proposal_NextYieldTooHigh(uint256 nextYield, uint256 maximum);

    /// @notice Thrown when an account does not hold a required role.
    /// @param role The role.
    /// @param account The account.
    error YieldRepurchaseFacilityV2Proposal_MissingRole(bytes32 role, address account);

    /// @notice Thrown when an account holds a role it must not hold.
    /// @param role The role.
    /// @param account The account.
    error YieldRepurchaseFacilityV2Proposal_UnexpectedRole(bytes32 role, address account);

    /// @notice Thrown when a policy is not active in the Kernel.
    /// @param policy The policy.
    error YieldRepurchaseFacilityV2Proposal_PolicyNotActive(address policy);

    /// @notice Thrown when a policy is not enabled.
    /// @param policy The policy.
    error YieldRepurchaseFacilityV2Proposal_PolicyNotEnabled(address policy);

    /// @notice Thrown when a vault of the launch is not registered in the facility after
    ///         execution.
    /// @param vault The vault.
    error YieldRepurchaseFacilityV2Proposal_VaultNotRegistered(address vault);

    /// @notice Thrown when the seeding window of the facility is open after execution.
    error YieldRepurchaseFacilityV2Proposal_CycleNotSeeded();

    /// @notice Thrown when the YieldRepurchaseFacility v1.2 is not shut down after execution.
    error YieldRepurchaseFacilityV2Proposal_V1NotShutDown();

    /// @notice Thrown when the YieldRepurchaseFacility v1.2 holds a token balance after
    ///         execution.
    /// @param token The token.
    /// @param balance The balance.
    error YieldRepurchaseFacilityV2Proposal_V1BalanceLeft(address token, uint256 balance);

    /// @notice Thrown when the YieldRepurchaseFacility v1.2 is a periodic task of the Heart
    ///         after execution.
    error YieldRepurchaseFacilityV2Proposal_V1StillHeartTask();

    /// @notice Thrown when USDe is not registered in the PRICE module after execution.
    /// @param usde The USDe token.
    error YieldRepurchaseFacilityV2Proposal_UsdeNotRegistered(address usde);

    // ========== CONSTANTS ========== //

    /// @notice The next yield the sUSDe vault is registered with, in USDe (18 decimals): the
    ///         amount the first weekly reset of the facility withdraws from the treasury into
    ///         the buyback pool of the vault. The value is encoded into the calldata of the
    ///         `activate` action.
    /// @dev One week of yield at 4% a year on the USDe value of the sUSDe shares the treasury
    ///      holds, each division rounded down. Read at mainnet block 26,400,405:
    ///      - `sUSDe.previewRedeem(sUSDe.balanceOf(TRSRY))` = 27,281,582.294757285410552626 USDe
    ///        (27281582294757285410552626, 18 decimals).
    ///      - value * 400 / 10,000 = 1091263291790291416422105 (18 decimals, a year at 4%).
    ///      - / 52 = 20985832534428681085040 (18 decimals, one week).
    ///
    ///      The activator rejects a value above its `MAX_SUSDE_NEXT_YIELD` (100,000 USDe).
    // TODO Recompute the value on a fresh block before the proposal is submitted. Then update
    // the derivation above, the block, the treasury value and the next yield in the
    // description, and the runbook.
    uint256 public constant SUSDE_NEXT_YIELD = 20_985_832_534_428_681_085_040;

    /// @notice The role `shutdown` of the YieldRepurchaseFacility v1.2 is gated to.
    bytes32 internal constant _LOOP_DADDY_ROLE = "loop_daddy";

    /// @notice The number of assets the launch registers: the sUSDS vault and the sUSDe vault.
    uint256 internal constant _ASSET_COUNT = 2;

    /// @notice The keycode of the PRICE submodule the activator registers the USDe/USD feed
    ///         with.
    bytes20 internal constant _CHAINLINK_SUBMODULE = "PRICE.CHAINLINK";

    string internal constant _ENV_PATH = "./src/scripts/env.json";

    string internal constant _ORACLE_NAME = "olympus-policy-backing-oracle";
    string internal constant _ORACLE_TIMELOCK_NAME =
        "olympus-policy-backing-oracle-config-timelock";
    string internal constant _CONFIG_NAME = "olympus-policy-yieldrepurchasefacility-config-1_0";
    string internal constant _CONFIG_TIMELOCK_NAME =
        "olympus-policy-yieldrepurchasefacility-config-timelock-1_0";
    string internal constant _FACILITY_NAME = "olympus-policy-yieldrepurchasefacility-2_0";
    string internal constant _ACTIVATOR_NAME =
        "olympus-proposal-yieldrepurchasefacility-v2-activator";
    string internal constant _YIELD_REPO_V1_NAME = "olympus-policy-yieldrepurchasefacility-1_2";
    string internal constant _HEART_NAME = "olympus-policy-heart-1_7";
    string internal constant _PRICE_CONFIG_NAME = "olympus-policy-price-config-2_0";

    // ========== DATA STRUCTURES ========== //

    /// @dev The contracts and accounts the proposal acts on, resolved from the address registry.
    struct Contracts {
        IYieldRepurchaseFacilityV2Activator activator;
        address oracle;
        address oracleTimelock;
        address config;
        address configTimelock;
        address facility;
        address yieldRepoV1;
        address heart;
        address priceConfig;
        ROLESv1 roles;
        RolesAdmin rolesAdmin;
        address ohm;
        address usds;
        address sUsds;
        address usde;
        address sUsde;
        address daoMS;
        address emergencyMS;
        address ocgTimelock;
    }

    // ========== STATE ========== //

    Kernel internal _kernel;

    // The state below is read before the actions run (`_afterDeploy`), and `_validate`
    // compares the end state with it.

    /// @notice The index of the YieldRepurchaseFacility v1.2 among the periodic tasks of the
    ///         Heart.
    uint256 internal _heartTaskIndex;

    /// @notice The number of periodic tasks of the Heart.
    uint256 internal _heartTaskCount;

    /// @notice The USDS balance of the YieldRepurchaseFacility v1.2, in USDS (18 decimals).
    uint256 internal _v1UsdsBalance;

    /// @notice The sUSDS balance of the YieldRepurchaseFacility v1.2, in shares (18 decimals).
    uint256 internal _v1SUsdsShares;

    /// @notice Whether USDe was registered in the PRICE module, in which case the activator
    ///         does not register it.
    bool internal _usdeRegisteredBefore;

    // ========== PROPOSAL ========== //

    function id() public pure override returns (uint256) {
        return 20;
    }

    function name() public pure override returns (string memory) {
        return "Yield Repurchase Facility V2 - Migration";
    }

    // solhint-disable quotes
    function description() public pure override returns (string memory) {
        return
            string.concat(
                _descriptionPreamble(),
                _descriptionParameters(),
                _descriptionSteps(),
                _descriptionAuthority()
            );
    }

    function _descriptionPreamble() private pure returns (string memory) {
        return
            string.concat(
                "# Yield Repurchase Facility V2 - Migration\n",
                "\n",
                "This proposal replaces the Yield Repurchase Facility v1.2 with the multi-asset Yield Repurchase Facility V2 (the V2 facility). The V2 facility continues the weekly buyback cycle of v1.2 on the sUSDS held by the treasury, and adds the sUSDe held by the treasury as a second source of yield. For each OHM that it buys and burns, the V2 facility withdraws a backing value from the treasury. A separate BackingOracle policy serves this value, instead of the constant of v1.2. The V2 facility opens no bond market while the OHM price in USDS is below the backing value.\n",
                "\n",
                "## Justification\n",
                "\n",
                "The Yield Repurchase Facility v1.2 draws yield from one vault, sUSDS, and values the backing of the OHM it burns at a constant of 11.33 USDS per OHM that only a redeployment can change. The treasury also holds sUSDe, whose yield is not used for buybacks today. The V2 facility registers each yield-bearing vault as an asset with its own share of yield routed to buybacks, opens one Bond Protocol market per asset each day, and reads the backing value from the BackingOracle, which the DAO MS can update through a timelock within a limit of 10% per update.\n",
                "\n",
                "The migration happens inside one call, so the buybacks are not interrupted: the epoch counter, the stored next yield, the yield snapshots and the unspent funds of v1.2 are carried over, and the V2 facility takes the position of v1.2 among the periodic tasks of the Heart.\n",
                "\n",
                // TODO Add the links to the audit report, the implementation PR, and the OIP and RFC
                // forum posts, as the other proposals do.
                "## Resources\n",
                "\n",
                "- Operator documentation: `documentation/yield_repurchase_facility_v2_launch_runbook.md` in the olympus-v3 repository.\n",
                "- Contracts: `src/policies/YieldRepurchaseFacility/`, `src/policies/BackingOracle.sol`, `src/policies/BackingOracleConfigTimelock.sol`, `src/proposals/YieldRepurchaseFacilityV2Activator.sol`.\n",
                "- Backing oracle documentation: `documentation/backing_oracle.md` in the olympus-v3 repository.\n",
                "\n",
                "## Assumptions\n",
                "\n",
                "- BackingOracle, BackingOracleConfigTimelock, YieldRepurchaseFacilityV2Config, YieldRepurchaseFacilityV2ConfigTimelock, YieldRepurchaseFacilityV2 and the one-use YieldRepurchaseFacilityV2Activator have been deployed on Ethereum mainnet.\n",
                "- The DAO MS has activated the five policies in the Kernel. None of them has been enabled. The V2 facility and YieldRepurchaseFacilityV2Config do not name each other yet, and neither YieldRepurchaseFacilityV2Config nor the BackingOracle names a config operator.\n",
                "- The Safe that owns the Bond Protocol auctioneer has authorized the V2 facility as a market callback.\n",
                "- The OCG timelock holds the `admin` role and administers RolesAdmin.\n",
                "- The Yield Repurchase Facility v1.2 is running and is a periodic task of the Heart.\n",
                "- The Chainlink USDe/USD feed has been updated within the last 24 hours and reports a price within 1% of 1 USD, unless USDe is already registered in the PRICE module.\n",
                "\n",
                "The proposal script checks the assumption about the OCG timelock before submission. The activator checks the other assumptions on chain when the proposal executes. If one does not hold, the execution reverts with an error naming it, nothing changes, and the proposal stays queued: it can be executed again until the 1-day grace period of the OCG timelock ends.\n"
            );
    }

    function _descriptionParameters() private pure returns (string memory) {
        return
            string.concat(
                "\n",
                "## Launch Parameters\n",
                "\n",
                "Percentages are scaled by 1e18 on chain; the raw values are given in parentheses.\n",
                "\n",
                "- Backing value of the BackingOracle: 12.04 USDS per OHM (12040000000000000000).\n",
                "- Initial discount: a bond market opens with a bid 3% below the OHM price of the PRICE module (30000000000000000).\n",
                "- Maximum price premium: a bond market pays at most 10% above the OHM price of the PRICE module for one OHM (100000000000000000).\n",
                "- sUSDS (0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD): the backing vault. The V2 facility burns the purchased OHM against withdrawals from this vault, and the yield of this vault (the backing yield) includes the interest of the Clearinghouses below. 100% of its yield is routed to buybacks (1000000000000000000); its markets pay out USDS. It continues the accounting of v1.2: the stored next yield and the yield snapshots of v1.2 are read when the proposal executes.\n",
                "- sUSDe (0x9D39A5DE30e57443BfF2A8307A4256c8797A3497): 100% of its yield is routed to buybacks (1000000000000000000); its markets pay out sUSDe shares, since sUSDe cannot be redeemed without a cooldown. Its first weekly withdrawal is 20,985.83 USDe (20985832534428681085040): one week of yield at 4% a year on 27,281,582.29 USDe, the value of the sUSDe that the treasury held at mainnet block 26,400,405. The activator rejects a value above 100,000 USDe (100000000000000000000000). Later withdrawals follow the yield the vault actually accrues.\n",
                "- Clearinghouse v1 (0xD6A6E8d9e82534bD65821142fcCd91ec9cF31880), which lends DAI: included in the backing yield, receivables offset 0. A receivables offset is an amount that the V2 facility deducts from the receivables of a Clearinghouse before it calculates the interest.\n",
                "- Clearinghouse v1.1 (0xE6343ad0675C9b8D3f32679ae6aDbA0766A2ab4c), which lends DAI: included in the backing yield, receivables offset 0.\n",
                "- Clearinghouse v1.2 (0x1e094fE00E13Fd06D64EeA4FB3cD912893606fE0), which lends USDS: not included explicitly, since a Clearinghouse that lends USDS counts toward the backing yield by default; receivables offset 0.\n",
                "- USDe price feed registered in the PRICE module, unless USDe is already registered: Chainlink USDe/USD (0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961), rejected when older than 86400 seconds, and accepted at registration within 100 basis points of 1 USD (1000000000000000000).\n",
                "\n",
                "The epoch counter of v1.2 and the funds it holds (its USDS, and its sUSDS at the redemption value) are read when the proposal executes: v1.2 is shut down, which returns the funds to the treasury, and the same value is withdrawn into the buyback pool of the sUSDS vault, so the remaining days of the running week are funded as they were. The OHM that v1.2 holds at that moment is burned without a treasury withdrawal, so its backing stays in the treasury.\n"
            );
    }

    function _descriptionSteps() private pure returns (string memory) {
        return
            string.concat(
                "\n",
                "## Proposal Steps\n",
                "\n",
                "Steps 1, 2, 8 and 9 are included only if the live state requires them; the others are always included.\n",
                "\n",
                "1. Grant the `yrf_admin` role to the DAO MS.\n",
                "2. Grant the `backing_admin` role to the DAO MS.\n",
                "3. Grant the `admin` role to the activator.\n",
                "4. Grant the `loop_daddy` role to the activator, which the shutdown of v1.2 requires.\n",
                "5. Call the activator, which in one call:\n",
                "   - Registers USDe in the PRICE module, if USDe is not registered.\n",
                "   - Names the BackingOracleConfigTimelock as the config operator of the BackingOracle, enables the timelock, and enables the oracle with the backing value above.\n",
                "   - Binds YieldRepurchaseFacilityV2Config (the configuration policy) and the V2 facility to each other, enables the configuration policy, names YieldRepurchaseFacilityV2ConfigTimelock as its config operator, and enables that timelock.\n",
                "   - Enables the V2 facility with the discount and the premium above.\n",
                "   - Reads the state of v1.2 and shuts v1.2 down.\n",
                "   - Registers sUSDS and sUSDe.\n",
                "   - Includes Clearinghouse v1 and Clearinghouse v1.1.\n",
                "   - Seeds the running week.\n",
                "   - Replaces v1.2 with the V2 facility at the same position among the periodic tasks of the Heart.\n",
                "6. Revoke the `admin` role from the activator.\n",
                "7. Revoke the `loop_daddy` role from the activator.\n",
                "8. Revoke the `loop_daddy` role from the DAO MS.\n",
                "9. Revoke the `loop_daddy` role from the OCG timelock.\n",
                "\n",
                "The activator can be called once and only by the OCG timelock. It holds its two roles only between steps 3 and 7, which execute in one transaction together with every other step.\n"
            );
    }

    function _descriptionAuthority() private pure returns (string memory) {
        return
            string.concat(
                "\n",
                "## Authority Model\n",
                "\n",
                "After this proposal:\n",
                "\n",
                "- The OCG timelock holds `admin`: it alone can register or remove a vault, change which vault is the backing vault or whether a vault's markets pay out shares, include a Clearinghouse or lower a receivables offset, replace the bond auctioneer, the backing oracle or the configuration policy of the V2 facility, and restart the V2 facility after the grace period of a disable has passed. It can also set the backing value without the timelock, within the same 10% limit, and make each change that the DAO MS queues without the delay.\n",
                "- The DAO MS holds `yrf_admin`: it queues typed changes on YieldRepurchaseFacilityV2ConfigTimelock (the yield share of a vault, the discount and the premium, an increase of a receivables offset, a decrease of a stored next yield, the exclusion of a Clearinghouse, enabling and disabling a vault), which anyone can execute after a delay of 1 day and within 3 days after that. It can re-enable the V2 facility, the configuration policy and the timelock within 5 days after a disable, set the gas limit of a step of the V2 facility, rescue tokens that are not part of a buyback pool, and cancel the changes that it queued.\n",
                "- The DAO MS holds `backing_admin`: it queues updates of the backing value on BackingOracleConfigTimelock, which anyone can execute after a delay of 1 day and within 7 days after that; the oracle limits each update to 10% of the current value. It can re-enable the oracle and its timelock within 7 days after a disable, and cancel the updates that it queued.\n",
                "- The Emergency MS holds `emergency`: it can disable any of the five policies, return the funds held by the V2 facility to the treasury while the V2 facility is disabled, and cancel a queued action.\n",
                "- Nobody holds `loop_daddy`, so v1.2 cannot be initialized again.\n",
                "\n",
                "## Next Steps\n",
                "\n",
                "The following are not part of this proposal:\n",
                "\n",
                "- The DAO MS deactivates the Yield Repurchase Facility v1.2 in the Kernel (`YieldRepurchaseFacilityV2SetupBatch.deactivateV1`).\n",
                "- The emergency configuration of the protocol (`documentation/emergency/emergency-config.json` in the olympus-v3 repository) is updated by a change of the repository: the entry of the V2 facility is recorded, and the entry of v1.2 is retired.\n"
            );
    }

    // solhint-enable quotes

    function _deploy(Addresses addresses, address) internal override {
        _kernel = Kernel(_recorded(addresses, "olympus-kernel"));
    }

    /// @dev Reads the state the launch moves before any action runs: the periodic task slot
    ///      of the YieldRepurchaseFacility v1.2, its USDS and sUSDS balances, and whether USDe
    ///      is registered in the PRICE module. `_validate` compares the end state with it.
    function _afterDeploy(Addresses addresses, address) internal override {
        address yieldRepoV1 = _recorded(addresses, _YIELD_REPO_V1_NAME);
        IPeriodicTaskManager heart = IPeriodicTaskManager(_recorded(addresses, _HEART_NAME));
        _heartTaskIndex = heart.getPeriodicTaskIndex(yieldRepoV1);
        _heartTaskCount = heart.getPeriodicTaskCount();

        _v1UsdsBalance = IERC20(_recorded(addresses, "external-tokens-usds")).balanceOf(
            yieldRepoV1
        );
        _v1SUsdsShares = IERC20(_recorded(addresses, "external-tokens-susds")).balanceOf(
            yieldRepoV1
        );
        _usdeRegisteredBefore = _price().isAssetApproved(
            _recorded(addresses, "external-tokens-usde")
        );
    }

    function _build(Addresses addresses) internal override {
        Contracts memory c = _contracts(addresses);
        // The file is read once: every read of it stays allocated in the memory of this frame
        string memory env = _readEnv();

        // Preconditions: the activator against the registry and against env.json, its roles
        // and its state, the authority of the OCG timelock, the state of the chain
        _requireActivatorBindings(c, env);
        _requireActivatorParameters(c, env);
        _requireNoRole(c.roles, ADMIN_ROLE, address(c.activator));
        _requireNoRole(c.roles, _LOOP_DADDY_ROLE, address(c.activator));
        _requireRole(c.roles, ADMIN_ROLE, c.ocgTimelock);
        _requireAddress("RolesAdmin admin", c.rolesAdmin.admin(), c.ocgTimelock);
        _requireAddress(
            "RolesAdmin kernel",
            address(Policy(address(c.rolesAdmin)).kernel()),
            address(_kernel)
        );
        // Reverts with the named error of the activator for the first precondition of the
        // launch that the live state does not meet, which includes an activated activator
        c.activator.checkPreconditions();

        // 1-2. Grant the operational roles to the DAO MS (conditional): ROLES rejects the
        // grant of a role that is already held
        _pushGrant(c, YRF_ADMIN_ROLE, c.daoMS, "Grant yrf_admin role to the DAO MS");
        _pushGrant(c, BACKING_ADMIN_ROLE, c.daoMS, "Grant backing_admin role to the DAO MS");

        // 3-4. Grant the two roles of the launch to the activator, which holds neither
        _pushAction(
            address(c.rolesAdmin),
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, ADMIN_ROLE, address(c.activator)),
            "Grant admin role to the activator"
        );
        _pushAction(
            address(c.rolesAdmin),
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                _LOOP_DADDY_ROLE,
                address(c.activator)
            ),
            "Grant loop_daddy role to the activator"
        );

        // 5. Launch. The activator checks its preconditions again at execution and reverts
        // the whole proposal with a named error when one no longer holds.
        _pushAction(
            address(c.activator),
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator.activate.selector,
                SUSDE_NEXT_YIELD
            ),
            "Activate the YieldRepurchaseFacilityV2 stack and migrate from v1.2"
        );

        // 6-7. Revoke both roles from the activator
        _pushAction(
            address(c.rolesAdmin),
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                ADMIN_ROLE,
                address(c.activator)
            ),
            "Revoke admin role from the activator"
        );
        _pushAction(
            address(c.rolesAdmin),
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                _LOOP_DADDY_ROLE,
                address(c.activator)
            ),
            "Revoke loop_daddy role from the activator"
        );

        // 8-9. Revoke loop_daddy from its known holders (conditional): ROLES rejects the
        // revocation of a role that is not held
        _pushRevoke(c, _LOOP_DADDY_ROLE, c.daoMS, "Revoke loop_daddy role from the DAO MS");
        _pushRevoke(
            c,
            _LOOP_DADDY_ROLE,
            c.ocgTimelock,
            "Revoke loop_daddy role from the OCG timelock"
        );
    }

    /// @notice Adds a grant of the role to the account unless the account holds it.
    function _pushGrant(
        Contracts memory c,
        bytes32 role_,
        address account_,
        string memory description_
    ) internal {
        if (c.roles.hasRole(account_, role_)) return;
        _pushAction(
            address(c.rolesAdmin),
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, role_, account_),
            description_
        );
    }

    /// @notice Adds a revocation of the role from the account when the account holds it.
    function _pushRevoke(
        Contracts memory c,
        bytes32 role_,
        address account_,
        string memory description_
    ) internal {
        if (!c.roles.hasRole(account_, role_)) return;
        _pushAction(
            address(c.rolesAdmin),
            abi.encodeWithSelector(RolesAdmin.revokeRole.selector, role_, account_),
            description_
        );
    }

    function _run(Addresses addresses, address) internal override {
        _simulateActions(
            address(_kernel),
            _recorded(addresses, "olympus-governor"),
            _recorded(addresses, "olympus-legacy-gohm"),
            _recorded(addresses, "proposer")
        );
    }

    /// @dev The end state is compared with the getters of the activator, with
    ///      `SUSDE_NEXT_YIELD`, with the state of the YieldRepurchaseFacility v1.2 whose epoch
    ///      counter, stored next yield and yield snapshots its shutdown leaves in place, and
    ///      with the state `_afterDeploy` read before the actions ran. The snapshots of the
    ///      sUSDe vault and the funds of the sUSDS buyback pool are compared with the values
    ///      the vaults report, which holds in the block of the execution.
    function _validate(Addresses addresses, address) internal view override {
        Contracts memory c = _contracts(addresses);
        IYieldRepurchaseFacilityV2Activator.LaunchParameters memory parameters = c
            .activator
            .launchParameters();

        _requireFlag("activator isActivated", c.activator.isActivated(), true);
        _validateLifecycle(c);
        _validateBindings(c);
        _validateParameters(c, parameters);
        _validateCycle(c);
        _validateAssets(c, parameters);
        _validateFunds(c);
        _validateClearinghouses(c, parameters);
        _validateV1(c);
        _validateHeart(c);
        _validateRoles(c, _recorded(addresses, "proposer"));
        _validateUsde(c);
    }

    // ========== BUILD HELPERS ========== //

    /// @notice Reverts unless the recorded activator is the launcher of the recorded contracts:
    ///         it advertises the activator interface, accepts the OCG timelock as its caller,
    ///         and reports every contract and token under the address the registry records,
    ///         and the price feed `env.json` declares.
    function _requireActivatorBindings(Contracts memory c, string memory env_) internal view {
        address activator = address(c.activator);
        // The checker reads an address without code, a reverting query and a malformed answer
        // as an interface that is not supported
        if (
            !ERC165Checker.supportsInterface(
                activator,
                type(IYieldRepurchaseFacilityV2Activator).interfaceId
            )
        ) revert YieldRepurchaseFacilityV2Proposal_InvalidActivator(activator);

        _requireAddress("activator timelock", c.activator.timelock(), c.ocgTimelock);

        IYieldRepurchaseFacilityV2Activator.Deployment memory d = c.activator.deployment();
        _requireAddress("activator kernel", d.kernel, address(_kernel));
        _requireAddress("activator backingOracle", d.backingOracle, c.oracle);
        _requireAddress(
            "activator backingOracleConfigTimelock",
            d.backingOracleConfigTimelock,
            c.oracleTimelock
        );
        _requireAddress("activator config", d.config, c.config);
        _requireAddress("activator configTimelock", d.configTimelock, c.configTimelock);
        _requireAddress("activator facility", d.facility, c.facility);
        _requireAddress("activator yieldRepoV1", d.yieldRepoV1, c.yieldRepoV1);
        _requireAddress("activator heart", d.heart, c.heart);
        _requireAddress("activator priceConfig", d.priceConfig, c.priceConfig);
        _requireAddress(
            "activator usdeUsdPriceFeed",
            d.usdeUsdPriceFeed,
            YieldRepurchaseFacilityV2ConfigLib.usdeUsdPriceFeed(env_, _chain())
        );
        _requireAddress("activator ohm", d.ohm, c.ohm);
        _requireAddress("activator usds", d.usds, c.usds);
        _requireAddress("activator sUsds", d.sUsds, c.sUsds);
        _requireAddress("activator usde", d.usde, c.usde);
        _requireAddress("activator sUsde", d.sUsde, c.sUsde);
    }

    /// @notice Reverts unless the launch values of the activator are the ones `env.json`
    ///         declares: the backing, the bond market parameters, the two assets with their
    ///         shares and payout modes, and the Clearinghouses in the declared order.
    /// @dev `env.json` has to declare exactly the sUSDS vault and the sUSDe vault, both
    ///      enabled, with the sUSDS vault as the backing vault: the activator registers these
    ///      two and nothing else.
    function _requireActivatorParameters(Contracts memory c, string memory env_) internal view {
        IYieldRepurchaseFacilityV2Activator.LaunchParameters memory parameters = c
            .activator
            .launchParameters();
        YieldRepurchaseFacilityV2ConfigLib.DesiredConfig
            memory desired = YieldRepurchaseFacilityV2ConfigLib.desiredConfig(env_, _chain());

        _requireParameter(
            "activator backing",
            parameters.backing,
            BackingOracleConfigLib.desiredBacking(env_, _chain())
        );
        _requireParameter(
            "activator initialDiscount",
            parameters.initialDiscount,
            desired.parameters.initialDiscount
        );
        _requireParameter(
            "activator maxPricePremium",
            parameters.maxPricePremium,
            desired.parameters.maxPricePremium
        );
        uint256 maxNextYield = c.activator.MAX_SUSDE_NEXT_YIELD();
        if (SUSDE_NEXT_YIELD > maxNextYield)
            revert YieldRepurchaseFacilityV2Proposal_NextYieldTooHigh(
                SUSDE_NEXT_YIELD,
                maxNextYield
            );

        (
            bool sUsdsDeclared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory sUsds
        ) = YieldRepurchaseFacilityV2ConfigLib.findAsset(desired.assets, c.sUsds);
        (
            bool sUsdeDeclared,
            YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory sUsde
        ) = YieldRepurchaseFacilityV2ConfigLib.findAsset(desired.assets, c.sUsde);
        if (desired.assets.length != _ASSET_COUNT || !sUsdsDeclared || !sUsdeDeclared)
            revert YieldRepurchaseFacilityV2Proposal_AssetSetMismatch(
                desired.assets.length,
                sUsdsDeclared,
                sUsdeDeclared
            );
        _requireAddress("env.json backingVault", desired.backingVault, c.sUsds);
        _requireAssetParameters("sUsds", parameters.sUsds, sUsds);
        _requireAssetParameters("sUsde", parameters.sUsde, sUsde);

        _requireParameter(
            "activator clearinghouses length",
            parameters.clearinghouses.length,
            desired.clearinghouses.length
        );
        for (uint256 i = 0; i < desired.clearinghouses.length; ++i) {
            IYieldRepurchaseFacilityV2Activator.ClearinghouseParameters memory actual = parameters
                .clearinghouses[i];
            YieldRepurchaseFacilityV2ConfigLib.DesiredClearinghouse memory expected = desired
                .clearinghouses[i];
            string memory field = string.concat("activator clearinghouses[", vm.toString(i), "]");
            _requireAddress(
                string.concat(field, " address"),
                actual.clearinghouse,
                expected.clearinghouse
            );
            _requireFlag(string.concat(field, " included"), actual.included, expected.included);
            _requireParameter(string.concat(field, " offset"), actual.offset, expected.offset);
        }
    }

    /// @notice Reverts unless the launch values of an asset are the declared ones and the
    ///         asset is declared enabled.
    function _requireAssetParameters(
        string memory field_,
        IYieldRepurchaseFacilityV2Activator.AssetParameters memory actual_,
        YieldRepurchaseFacilityV2ConfigLib.DesiredAsset memory expected_
    ) internal pure {
        if (!expected_.enabled)
            revert YieldRepurchaseFacilityV2Proposal_AssetDeclaredDisabled(expected_.name);
        _requireParameter(
            string.concat("activator ", field_, " yieldBuybackShare"),
            actual_.yieldBuybackShare,
            expected_.yieldBuybackShare
        );
        _requireFlag(
            string.concat("activator ", field_, " sellShares"),
            actual_.sellShares,
            expected_.sellShares
        );
    }

    // ========== VALIDATION HELPERS ========== //

    function _validateLifecycle(Contracts memory c) internal view {
        address[5] memory policies = [
            c.oracle,
            c.oracleTimelock,
            c.config,
            c.configTimelock,
            c.facility
        ];
        for (uint256 i = 0; i < policies.length; ++i) {
            if (!_kernel.isPolicyActive(Policy(policies[i])))
                revert YieldRepurchaseFacilityV2Proposal_PolicyNotActive(policies[i]);
            if (!IEnabler(policies[i]).isEnabled())
                revert YieldRepurchaseFacilityV2Proposal_PolicyNotEnabled(policies[i]);
        }
    }

    function _validateBindings(Contracts memory c) internal view {
        _requireAddress(
            "YieldRepurchaseFacilityV2Config facility",
            IYieldRepurchaseFacilityV2Config(c.config).facility(),
            c.facility
        );
        _requireAddress(
            "YieldRepurchaseFacilityV2 configurator",
            IYieldRepurchaseFacilityV2View(c.facility).configurator(),
            c.config
        );
        _requireAddress(
            "YieldRepurchaseFacilityV2Config configOperator",
            IConfigOperator(c.config).configOperator(),
            c.configTimelock
        );
        _requireAddress(
            "BackingOracle configOperator",
            IConfigOperator(c.oracle).configOperator(),
            c.oracleTimelock
        );
        _requireAddress(
            "YieldRepurchaseFacilityV2 backingOracle",
            IYieldRepurchaseFacilityV2View(c.facility).backingOracle(),
            c.oracle
        );
    }

    function _validateParameters(
        Contracts memory c,
        IYieldRepurchaseFacilityV2Activator.LaunchParameters memory parameters_
    ) internal view {
        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(c.facility);
        _requireParameter(
            "BackingOracle backing",
            IBackingOracle(c.oracle).backing(),
            parameters_.backing
        );
        _requireParameter(
            "YieldRepurchaseFacilityV2 initialDiscount",
            facility.initialDiscount(),
            parameters_.initialDiscount
        );
        _requireParameter(
            "YieldRepurchaseFacilityV2 maxPricePremium",
            facility.maxPricePremium(),
            parameters_.maxPricePremium
        );
    }

    /// @notice Reverts unless the facility registers exactly the two vaults of the launch with
    ///         the launch values: the sUSDS vault as the backing vault with the next yield and
    ///         the snapshots of the YieldRepurchaseFacility v1.2, and the sUSDe vault with
    ///         `SUSDE_NEXT_YIELD` and the snapshots the vault reports.
    function _validateAssets(
        Contracts memory c,
        IYieldRepurchaseFacilityV2Activator.LaunchParameters memory parameters_
    ) internal view {
        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(c.facility);
        IYieldRepoV1 yieldRepoV1 = IYieldRepoV1(c.yieldRepoV1);

        address[] memory vaults = facility.getVaults();
        _requireParameter("YieldRepurchaseFacilityV2 vault count", vaults.length, _ASSET_COUNT);
        if (vaults[0] != c.sUsds && vaults[1] != c.sUsds)
            revert YieldRepurchaseFacilityV2Proposal_VaultNotRegistered(c.sUsds);
        if (vaults[0] != c.sUsde && vaults[1] != c.sUsde)
            revert YieldRepurchaseFacilityV2Proposal_VaultNotRegistered(c.sUsde);
        _requireAddress("YieldRepurchaseFacilityV2 backingVault", facility.backingVault(), c.sUsds);

        IYieldRepurchaseFacilityV2.ReserveAsset memory sUsds = facility.getAssetConfig(c.sUsds);
        _requireAsset("sUSDS", sUsds, parameters_.sUsds);
        _requireParameter("sUSDS nextYield", sUsds.nextYield, yieldRepoV1.nextYield());
        _requireParameter(
            "sUSDS lastReserveBalance",
            sUsds.lastReserveBalance,
            yieldRepoV1.lastReserveBalance()
        );
        _requireParameter(
            "sUSDS lastConversionRate",
            sUsds.lastConversionRate,
            yieldRepoV1.lastConversionRate()
        );

        IYieldRepurchaseFacilityV2.ReserveAsset memory sUsde = facility.getAssetConfig(c.sUsde);
        address treasury = address(_kernel.getModuleForKeycode(toKeycode("TRSRY")));
        _requireAsset("sUSDe", sUsde, parameters_.sUsde);
        _requireParameter("sUSDe nextYield", sUsde.nextYield, SUSDE_NEXT_YIELD);
        // Reserve value of the treasury shares, rounded down by the vault
        _requireParameter(
            "sUSDe lastReserveBalance",
            sUsde.lastReserveBalance,
            IERC4626(c.sUsde).previewRedeem(IERC20(c.sUsde).balanceOf(treasury))
        );
        // Reserve value of one whole share (10 ** share decimals), rounded down by the vault
        _requireParameter(
            "sUSDe lastConversionRate",
            sUsde.lastConversionRate,
            IERC4626(c.sUsde).previewRedeem(10 ** IERC20(c.sUsde).decimals())
        );
    }

    function _requireAsset(
        string memory name_,
        IYieldRepurchaseFacilityV2.ReserveAsset memory asset_,
        IYieldRepurchaseFacilityV2Activator.AssetParameters memory parameters_
    ) internal pure {
        _requireFlag(string.concat(name_, " isAssetEnabled"), asset_.isAssetEnabled, true);
        _requireFlag(
            string.concat(name_, " sellShares"),
            asset_.sellShares,
            parameters_.sellShares
        );
        _requireParameter(
            string.concat(name_, " yieldBuybackShare"),
            asset_.yieldBuybackShare,
            parameters_.yieldBuybackShare
        );
    }

    /// @notice Reverts unless the facility resumes the weekly cycle at the epoch counter of the
    ///         YieldRepurchaseFacility v1.2 and its seeding window is closed.
    function _validateCycle(Contracts memory c) internal view {
        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(c.facility);
        _requireParameter(
            "YieldRepurchaseFacilityV2 epoch",
            facility.epoch(),
            IYieldRepoV1(c.yieldRepoV1).epoch()
        );
        if (facility.isCycleSeedable()) revert YieldRepurchaseFacilityV2Proposal_CycleNotSeeded();
    }

    /// @notice Reverts unless the buyback pool of the sUSDS vault holds the funds the
    ///         YieldRepurchaseFacility v1.2 held before the actions ran, and neither vault
    ///         carries unfunded yield.
    /// @dev The funds of v1.2 are its USDS balance plus the USDS value of its sUSDS shares.
    ///      The facility withdraws the shares that cover that value from the treasury, and
    ///      carries what the treasury does not cover as unfunded yield.
    function _validateFunds(Contracts memory c) internal view {
        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(c.facility);

        // USDS (18 decimals) + USDS value of the shares (18 decimals), rounded down by the
        // vault -> USDS (18 decimals)
        uint256 funds = _v1UsdsBalance + IERC4626(c.sUsds).previewRedeem(_v1SUsdsShares);
        // The shares that cover the funds (18 decimals), rounded up by the vault. The facility
        // is seeded with no buyback pool when v1.2 held nothing
        uint256 expectedShares = funds == 0 ? 0 : IERC4626(c.sUsds).previewWithdraw(funds);
        _requireParameter(
            "sUSDS buyback pool shares",
            IERC20(c.sUsds).balanceOf(c.facility),
            expectedShares
        );
        _requireParameter("sUSDS unfundedYield", facility.getAssetConfig(c.sUsds).unfundedYield, 0);
        _requireParameter("sUSDe unfundedYield", facility.getAssetConfig(c.sUsde).unfundedYield, 0);
    }

    /// @notice Reverts unless USDe is registered in the PRICE module and, when the activator
    ///         registered it, with the registration of the activator: one feed, read through
    ///         the Chainlink submodule from the USDe/USD feed of the activator with its update
    ///         threshold, and no moving average.
    /// @dev A registration that preceded the proposal is not the one of the activator and is
    ///      not compared. The expected price and its tolerance are checked by the PriceConfig
    ///      v2 policy at the registration and are not stored.
    function _validateUsde(Contracts memory c) internal view {
        IPRICEv2 price = _price();
        if (!price.isAssetApproved(c.usde))
            revert YieldRepurchaseFacilityV2Proposal_UsdeNotRegistered(c.usde);
        if (_usdeRegisteredBefore) return;

        IPRICEv2.Asset memory asset = price.getAssetData(c.usde);
        _requireFlag("USDe storeMovingAverage", asset.storeMovingAverage, false);
        _requireFlag("USDe useMovingAverage", asset.useMovingAverage, false);

        IPRICEv2.Component[] memory feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        _requireParameter("USDe feed count", feeds.length, 1);
        // The keycode (20 bytes) and the selector (4 bytes) are compared as numbers
        _requireParameter(
            "USDe feed submodule",
            uint256(uint160(fromSubKeycode(feeds[0].target))),
            uint256(uint160(_CHAINLINK_SUBMODULE))
        );
        _requireParameter(
            "USDe feed selector",
            uint256(uint32(feeds[0].selector)),
            uint256(uint32(ChainlinkPriceFeeds.getOneFeedPrice.selector))
        );
        ChainlinkPriceFeeds.OneFeedParams memory params = abi.decode(
            feeds[0].params,
            (ChainlinkPriceFeeds.OneFeedParams)
        );
        _requireAddress(
            "USDe feed",
            address(params.feed),
            c.activator.deployment().usdeUsdPriceFeed
        );
        _requireParameter(
            "USDe feed updateThreshold",
            params.updateThreshold,
            c.activator.USDE_FEED_UPDATE_THRESHOLD()
        );
    }

    function _validateClearinghouses(
        Contracts memory c,
        IYieldRepurchaseFacilityV2Activator.LaunchParameters memory parameters_
    ) internal view {
        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(c.facility);
        for (uint256 i = 0; i < parameters_.clearinghouses.length; ++i) {
            IYieldRepurchaseFacilityV2Activator.ClearinghouseParameters memory entry = parameters_
                .clearinghouses[i];
            string memory field = string.concat("Clearinghouse ", vm.toString(entry.clearinghouse));
            _requireFlag(
                string.concat(field, " included"),
                facility.isClearinghouseIncluded(entry.clearinghouse),
                entry.included
            );
            _requireParameter(
                string.concat(field, " offset"),
                facility.clearinghouseOffset(entry.clearinghouse),
                entry.offset
            );
        }
    }

    /// @notice Reverts unless the YieldRepurchaseFacility v1.2 is shut down and holds no USDS,
    ///         sUSDS or OHM.
    function _validateV1(Contracts memory c) internal view {
        if (!IYieldRepoV1(c.yieldRepoV1).isShutdown())
            revert YieldRepurchaseFacilityV2Proposal_V1NotShutDown();
        address[3] memory tokens = [c.usds, c.sUsds, c.ohm];
        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 balance = IERC20(tokens[i]).balanceOf(c.yieldRepoV1);
            if (balance != 0)
                revert YieldRepurchaseFacilityV2Proposal_V1BalanceLeft(tokens[i], balance);
        }
    }

    /// @notice Reverts unless the facility holds the periodic task slot the
    ///         YieldRepurchaseFacility v1.2 held before the actions ran, without a custom
    ///         selector, and the number of periodic tasks is unchanged.
    function _validateHeart(Contracts memory c) internal view {
        IPeriodicTaskManager heart = IPeriodicTaskManager(c.heart);
        if (heart.hasPeriodicTask(c.yieldRepoV1))
            revert YieldRepurchaseFacilityV2Proposal_V1StillHeartTask();
        _requireParameter(
            "Heart periodic task count",
            heart.getPeriodicTaskCount(),
            _heartTaskCount
        );
        (address task, bytes4 customSelector) = heart.getPeriodicTaskAtIndex(_heartTaskIndex);
        _requireAddress("Heart periodic task at the index of v1.2", task, c.facility);
        _requireParameter(
            "Heart custom selector of the facility",
            uint256(uint32(customSelector)),
            0
        );
    }

    function _validateRoles(Contracts memory c, address proposer_) internal view {
        _requireRole(c.roles, ADMIN_ROLE, c.ocgTimelock);
        _requireRole(c.roles, EMERGENCY_ROLE, c.emergencyMS);
        _requireRole(c.roles, YRF_ADMIN_ROLE, c.daoMS);
        _requireRole(c.roles, BACKING_ADMIN_ROLE, c.daoMS);
        _requireNoRole(c.roles, ADMIN_ROLE, address(c.activator));
        // ROLES keeps no enumeration of role holders, so only known addresses can be sampled
        // here; the guarantee that loop_daddy is unassigned anywhere is procedural: this
        // proposal revokes it from the two holders recorded on chain and from the activator.
        address[7] memory noLoopDaddy = [
            address(c.activator),
            c.daoMS,
            c.ocgTimelock,
            c.emergencyMS,
            c.facility,
            c.yieldRepoV1,
            proposer_
        ];
        for (uint256 i = 0; i < noLoopDaddy.length; ++i) {
            _requireNoRole(c.roles, _LOOP_DADDY_ROLE, noLoopDaddy[i]);
        }
    }

    function _requireRole(ROLESv1 roles_, bytes32 role_, address account_) internal view {
        if (!roles_.hasRole(account_, role_))
            revert YieldRepurchaseFacilityV2Proposal_MissingRole(role_, account_);
    }

    function _requireNoRole(ROLESv1 roles_, bytes32 role_, address account_) internal view {
        if (roles_.hasRole(account_, role_))
            revert YieldRepurchaseFacilityV2Proposal_UnexpectedRole(role_, account_);
    }

    function _requireAddress(
        string memory field_,
        address actual_,
        address expected_
    ) internal pure {
        if (actual_ != expected_)
            revert YieldRepurchaseFacilityV2Proposal_AddressMismatch(field_, actual_, expected_);
    }

    function _requireParameter(
        string memory name_,
        uint256 actual_,
        uint256 expected_
    ) internal pure {
        if (actual_ != expected_)
            revert YieldRepurchaseFacilityV2Proposal_ParameterMismatch(name_, actual_, expected_);
    }

    function _requireFlag(string memory name_, bool actual_, bool expected_) internal pure {
        if (actual_ != expected_)
            revert YieldRepurchaseFacilityV2Proposal_FlagMismatch(name_, actual_, expected_);
    }

    // ========== INTERNAL HELPERS ========== //

    function _contracts(Addresses addresses) internal view returns (Contracts memory c) {
        c.activator = IYieldRepurchaseFacilityV2Activator(_recorded(addresses, _ACTIVATOR_NAME));
        c.oracle = _recorded(addresses, _ORACLE_NAME);
        c.oracleTimelock = _recorded(addresses, _ORACLE_TIMELOCK_NAME);
        c.config = _recorded(addresses, _CONFIG_NAME);
        c.configTimelock = _recorded(addresses, _CONFIG_TIMELOCK_NAME);
        c.facility = _recorded(addresses, _FACILITY_NAME);
        c.yieldRepoV1 = _recorded(addresses, _YIELD_REPO_V1_NAME);
        c.heart = _recorded(addresses, _HEART_NAME);
        c.priceConfig = _recorded(addresses, _PRICE_CONFIG_NAME);
        c.roles = ROLESv1(_recorded(addresses, "olympus-module-roles"));
        c.rolesAdmin = RolesAdmin(_recorded(addresses, "olympus-policy-roles-admin"));
        c.ohm = _recorded(addresses, "olympus-legacy-ohm");
        c.usds = _recorded(addresses, "external-tokens-usds");
        c.sUsds = _recorded(addresses, "external-tokens-susds");
        c.usde = _recorded(addresses, "external-tokens-usde");
        c.sUsde = _recorded(addresses, "external-tokens-susde");
        c.daoMS = _recorded(addresses, "olympus-multisig-dao");
        c.emergencyMS = _recorded(addresses, "olympus-multisig-emergency");
        c.ocgTimelock = _recorded(addresses, "olympus-timelock");
    }

    /// @notice Returns the address the registry records under the name.
    /// @dev The registry reverts for a name it does not hold and for a name recorded with the
    ///      zero address, the placeholder of a contract that is not deployed yet; both are
    ///      reported with the error below.
    function _recorded(
        Addresses addresses_,
        string memory name_
    ) internal view returns (address recorded) {
        try addresses_.getAddress(name_) returns (address value) {
            return value;
        } catch {
            revert YieldRepurchaseFacilityV2Proposal_AddressNotRecorded(name_);
        }
    }

    /// @notice Reads `env.json`, the desired-state source that the build compares the launch
    ///         values of the activator with.
    function _readEnv() internal view virtual returns (string memory env) {
        // The path is the constant `_ENV_PATH`: the tracked `env.json` and nothing else is read
        // forge-lint: disable-next-line(unsafe-cheatcode)
        return vm.readFile(_ENV_PATH);
    }

    function _chain() internal view returns (string memory chain) {
        return ChainUtils._getChainName(block.chainid);
    }

    function _price() internal view returns (IPRICEv2 price) {
        return IPRICEv2(address(_kernel.getModuleForKeycode(toKeycode("PRICE"))));
    }
}

contract YieldRepurchaseFacilityV2ProposalScript is ProposalScript {
    constructor() ProposalScript(new YieldRepurchaseFacilityV2Proposal()) {}
}

// forge-lint: disable-end(multi-contract-file)

// forge-lint: disable-end(calls-loop,require-revert-in-loop)
