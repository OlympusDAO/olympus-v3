// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import {console2} from "forge-std/console2.sol";

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";
// Interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";
// Olympus Kernel, Modules, and Policies
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {CHREGv1} from "modules/CHREG/CHREG.v1.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {Clearinghouse} from "policies/Clearinghouse.sol";

/// @notice OIP_XXX proposal performs all the necessary steps to upgrade the Clearinghouse.
// solhint-disable-next-line contract-name-camelcase
contract OIP_XXX is GovernorBravoProposal {
    // Data struct to cache initial balances and used them in `_validate`.
    struct Cache {
        uint256 daiBalance;
        uint256 sdaiBalance;
    }

    // Cached balances
    Cache public cacheCH0;
    Cache public cacheTRSRY;

    // Kernel will be used in most proposals
    Kernel internal _kernel;

    // Returns the id of the proposal.
    function id() public pure override returns (uint256) {
        return 0;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "OIP_XXX";
    }

    // Provides a brief description of the proposal.
    function description() public pure override returns (string memory) {
        return "OIP-XXX: Upgrade the Clearinghouse";
    }

    // Deploys a vault contract and an ERC20 token contract.
    function _deploy(Addresses addresses, address) internal override {
        // Store the kernel address
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));

        // Deploy needed contracts
        Clearinghouse clearinghouse = new Clearinghouse({
            ohm_: addresses.getAddress("olympus-legacy-ohm"),
            gohm_: addresses.getAddress("olympus-legacy-gohm"),
            staking_: addresses.getAddress("olympus-legacy-staking"),
            sReserve_: addresses.getAddress("external-tokens-sdai"),
            coolerFactory_: addresses.getAddress("external-coolers-factory"),
            kernel_: address(_kernel)
        });
        console2.log("Clearinghouse V1.1 deployed at address: %s", address(clearinghouse));

        // Add deployed contracts to the address registry
        addresses.addAddress("olympus-policy-clearinghouse-v1.1", address(clearinghouse));
    }

    function _afterDeploy(Addresses addresses, address) internal override {
        // Get relevant olympus contracts
        address TRSRY = address(_kernel.getModuleForKeycode(toKeycode(bytes5("TRSRY"))));
        address clearinghouseV0 = addresses.getAddress("olympus-policy-clearinghouse");
        // Get relevant tokens
        IERC20 dai = IERC20(addresses.getAddress("external-tokens-dai"));
        IERC20 sdai = IERC20(addresses.getAddress("external-tokens-sdai"));

        // Cache initial balances and used them in `_validate`.
        cacheCH0 = Cache({
            daiBalance: dai.balanceOf(clearinghouseV0),
            sdaiBalance: sdai.balanceOf(clearinghouseV0)
        });
        cacheTRSRY = Cache({daiBalance: dai.balanceOf(TRSRY), sdaiBalance: sdai.balanceOf(TRSRY)});

        // Nothing to configure here, as in this case all the configuration actions require
        // system permissions and must be done in the _build() function.
    }

    // Sets up actions for the proposal, in this case, setting the MockToken to active.
    function _build(Addresses addresses) internal override {
        address clearinghouseV0 = addresses.getAddress("olympus-policy-clearinghouse");
        address clearinghouseV1 = addresses.getAddress("olympus-policy-clearinghouse-v1.1");

        // STEP 1: Pull funds out of Clearinghouse V0 and disable loan issuance.
        _pushAction(
            clearinghouseV0,
            abi.encodeWithSignature("emergencyShutdown()"),
            "Shutdown Clearinghouse V0 and return funds to TRSRY"
        );

        // NOTE: In its current form, OCG is limited to admin roles when it refers to interactions with
        //       exsting policies and modules. Nevertheless, the DAO MS is still the Kernel executor.
        //       Because of that, OCG can't interact (un/install policies/modules) with the Kernel, yet.

        // ALERT: Clearinghouses should not be deactivated via Kernel, as outstanding loans
        //        would not be able to be repaid because Kernel interactions would revert.

        // STEP 2: Activate Clearinghouse V1.1 at a Kernel level.
        _pushAction(
            address(_kernel),
            abi.encodeWithSignature(
                "executeAction(uint8,address)",
                Actions.ActivatePolicy,
                clearinghouseV1
            ),
            "Activate Clearinghouse V1.1 Policy on Kernel"
        );

        // STEP 3: Activate Clearinghouse V1.1 at a contract level.
        _pushAction(
            clearinghouseV1,
            abi.encodeWithSignature("activate()"),
            "Register Clearinghouse V1.1 on CHREG and activate"
        );
    }

    // Executes the proposal actions.
    function _run(Addresses addresses, address) internal override {
        // Simulates actions on TimelockController
        _simulateActions(
            address(_kernel),
            addresses.getAddress("olympus-governor"),
            addresses.getAddress("olympus-legacy-gohm"),
            addresses.getAddress("proposer")
        );
    }

    // Validates the post-execution state.
    function _validate(Addresses addresses, address) internal override {
        // Get relevant olympus contracts
        address TRSRY = address(_kernel.getModuleForKeycode(toKeycode(bytes5("TRSRY"))));
        address CHREG = address(_kernel.getModuleForKeycode(toKeycode(bytes5("CHREG"))));
        address clearinghouseV0 = addresses.getAddress("olympus-policy-clearinghouse");
        address clearinghouseV1 = addresses.getAddress("olympus-policy-clearinghouse-v1.1");
        // Get relevant tokens
        IERC20 dai = IERC20(addresses.getAddress("external-tokens-dai"));
        IERC4626 sdai = IERC4626(addresses.getAddress("external-tokens-sdai"));
        // Validate token balances
        assertEq(dai.balanceOf(clearinghouseV0), 0, "DAI balance of clearinghouse v1 should be 0");
        assertEq(
            sdai.balanceOf(clearinghouseV0),
            0,
            "sDAI balance of clearinghouse v1 should be 0"
        );
        assertEq(sdai.maxRedeem(clearinghouseV1), 0, "Max redeem should be 0"); // Should be 0 DAI since rebalance wasn't called
        assertEq(
            dai.balanceOf(TRSRY),
            cacheTRSRY.daiBalance + cacheCH0.daiBalance,
            "DAI balance of treasury should be correct"
        );
        assertEq(
            sdai.balanceOf(TRSRY),
            cacheTRSRY.sdaiBalance + cacheCH0.sdaiBalance - sdai.balanceOf(clearinghouseV1),
            "sDAI balance of treasury should be correct"
        );
        // Validate Clearinghouse state
        Clearinghouse CHv0 = Clearinghouse(clearinghouseV0);
        assertEq(CHv0.active(), false, "Clearinghouse v1 should be shutdown");
        // Validate Clearinghouse parameters
        Clearinghouse CHv1 = Clearinghouse(clearinghouseV1);
        assertEq(CHv1.active(), true, "Clearinghouse v1.1 should be active");
        assertEq(CHv1.INTEREST_RATE(), 5e15, "Interest rate should be correct");
        assertEq(CHv1.LOAN_TO_COLLATERAL(), 289292e16, "Loan to collateral should be correct");
        assertEq(CHv1.DURATION(), 121 days, "Duration should be correct");
        assertEq(CHv1.FUND_CADENCE(), 7 days, "Fund cadence should be correct");
        assertEq(CHv1.FUND_AMOUNT(), 18_000_000e18, "Fund amount should be correct");
        assertEq(CHv1.MAX_REWARD(), 1e17, "Max reward should be correct");
        // Validate Clearinghouse Registry state
        // The V0 Clearinghouse's emergencyShutdown function does NOT remove it from the registry.
        CHREGv1 CHRegistry = CHREGv1(CHREG);
        assertEq(CHRegistry.activeCount(), 2, "Active count should be correct");
        assertEq(CHRegistry.active(0), clearinghouseV0, "Clearinghouse v0 should be active");
        assertEq(CHRegistry.active(1), clearinghouseV1, "Clearinghouse v1.1 should be active");
        assertEq(CHRegistry.registryCount(), 2, "Registry count should be correct");
        assertEq(CHRegistry.registry(1), clearinghouseV0, "Clearinghouse v0 should be in registry");
        assertEq(
            CHRegistry.registry(2),
            clearinghouseV1,
            "Clearinghouse v1.1 should be in registry"
        );
    }
}
