// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
// solhint-disable one-contract-per-file
pragma solidity >=0.8.20;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Script
import {ProposalScript} from "src/proposals/ProposalScript.sol";

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";

// Modules
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

// Policies
import {EmissionManager} from "src/policies/EmissionManager.sol";

// Kernel
import {Kernel} from "src/Kernel.sol";

interface IConvertibleDepositAuctioneerPendingChanges {
    struct PendingDepositPeriodChange {
        uint8 depositPeriod;
        bool enable;
    }

    function getPendingDepositPeriodChanges()
        external
        view
        returns (PendingDepositPeriodChange[] memory);
}

/// @notice OCG proposal that configures the retuned USDS convertible deposit market.
contract ConvertibleDepositRetuningProposal is GovernorBravoProposal {
    error ValidationFailed(string reason);

    Kernel internal _kernel;

    bytes32 internal constant ADMIN_ROLE = "admin";

    uint8 internal constant TARGET_PERIOD = 3;
    uint8 internal constant LEGACY_PERIOD = 6;
    uint16 internal constant RECLAIM_RATE = 9000;
    uint16 internal constant LEGACY_RECLAIM_RATE = 9900;

    uint256 internal constant MINIMUM_BID = 100e18;
    uint256 internal constant MIN_PRICE_SCALAR = 1.1e18;
    uint256 internal constant TARGET_BASE_EMISSIONS_RATE = 1_000_000;
    uint256 internal constant TICK_SIZE = 10_000_000_000_000;
    uint24 internal constant TICK_STEP = 10010;

    // Returns the id of the proposal.
    function id() public pure override returns (uint256) {
        return 0;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "Convertible Deposit Retuning";
    }

    // Implementation review link is included in the exact on-chain description.
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Convertible Deposit Parameter Adjustments\n\n",
                "This proposal lowers the entry barrier, shortens the term offered to new depositors and moderates auction allocation.\n\n",
                "| Parameter | Proposed configuration |\n",
                "| --- | --- |\n",
                "| New deposit term | 3 months; stop offering new 6-month auctions |\n",
                "| Early reclaim | 90% for 3-month receipts |\n",
                "| Minimum bid | 100 USDS |\n",
                "| Standard auction tick | 10,000 OHM |\n",
                "| Price step per tick | 0.10% |\n",
                "| Base emission rate | 0.10% |\n",
                "| Minimum conversion-price scalar | 110% of the market-price input, unchanged |\n",
                "| Minimum premium | 50%, unchanged |\n",
                "| Tick-size base | 2x, unchanged |\n",
                "| USDS deposit cap | 60 million USDS, unchanged |\n\n",
                "The three-month early reclaim rate applies to existing receipts reclaimed after implementation. This change does not alter the amount or redemption date of redemptions already underway, nor apply an early-reclaim discount to full redemption. Existing six-month positions and their 99% reclaim setting remain unchanged.\n\n",
                "The base emission rate controls auction pacing; it is not a hard issuance cap. Auction-period changes and the scheduled base-rate adjustment take effect at the next EmissionManager auction update, which occurs every third heartbeat.\n\n",
                "## Implementation review\n\n",
                "Implementation and tests: [OlympusDAO/olympus-v3 PR #343](https://github.com/OlympusDAO/olympus-v3/pull/343)."
            );
    }

    // No deploy actions needed
    function _deploy(Addresses addresses, address) internal override {
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address deployer) internal override {}

    // Sets up actions for the proposal.
    function _build(Addresses addresses) internal override {
        address depositManager = addresses.getAddress("olympus-policy-deposit-manager-1_0");
        address cdFacility = addresses.getAddress(
            "olympus-policy-convertible-deposit-facility-1_0"
        );
        address cdAuctioneer = addresses.getAddress(
            "olympus-policy-convertible-deposit-auctioneer-1_0"
        );
        address emissionManager = addresses.getAddress("olympus-policy-emissionmanager-1_2");
        address usds = addresses.getAddress("external-tokens-USDS");

        _configureDepositManagerAssetPeriod(depositManager, cdFacility, usds);
        _reconcileAuctioneerDepositPeriods(cdAuctioneer);
        _requireUnchangedLegacyReclaimRate(cdFacility, usds);
        _configureReclaimRate(cdFacility, usds);
        _configureMinimumBid(cdAuctioneer);
        _configureTickStep(cdAuctioneer);
        _validateUnchangedControls(depositManager, cdAuctioneer, emissionManager, usds);
        _configureBaseRateTarget(emissionManager);
        _configureEmissionTickSize(emissionManager);
    }

    function _configureDepositManagerAssetPeriod(
        address depositManager,
        address cdFacility,
        address usds
    ) internal {
        IDepositManager.AssetPeriodStatus memory status = IDepositManager(depositManager)
            .isAssetPeriod(IERC20(usds), TARGET_PERIOD, cdFacility);

        if (!status.isConfigured) {
            _pushAction(
                depositManager,
                abi.encodeWithSelector(
                    IDepositManager.addAssetPeriod.selector,
                    IERC20(usds),
                    TARGET_PERIOD,
                    cdFacility
                ),
                "Add USDS 3-month DepositManager asset period"
            );
        } else if (!status.isEnabled) {
            _pushAction(
                depositManager,
                abi.encodeWithSelector(
                    IDepositManager.enableAssetPeriod.selector,
                    IERC20(usds),
                    TARGET_PERIOD,
                    cdFacility
                ),
                "Enable USDS 3-month DepositManager asset period"
            );
        }
    }

    function _reconcileAuctioneerDepositPeriods(address cdAuctioneer) internal {
        uint8[] memory knownPeriods = _getAuctioneerKnownPeriods(cdAuctioneer);

        for (uint256 i = 0; i < knownPeriods.length; i++) {
            uint8 period = knownPeriods[i];
            (, bool isPendingEnabled) = IConvertibleDepositAuctioneer(cdAuctioneer)
                .isDepositPeriodEnabled(period);

            if (period != TARGET_PERIOD && isPendingEnabled) {
                _pushAction(
                    cdAuctioneer,
                    abi.encodeWithSelector(
                        IConvertibleDepositAuctioneer.disableDepositPeriod.selector,
                        period
                    ),
                    "Disable non-target CD auctioneer deposit period"
                );
            }
        }

        (, bool targetPeriodPendingEnabled) = IConvertibleDepositAuctioneer(cdAuctioneer)
            .isDepositPeriodEnabled(TARGET_PERIOD);

        if (!targetPeriodPendingEnabled) {
            _pushAction(
                cdAuctioneer,
                abi.encodeWithSelector(
                    IConvertibleDepositAuctioneer.enableDepositPeriod.selector,
                    TARGET_PERIOD
                ),
                "Enable 3-month CD auctioneer deposit period"
            );
        }
    }

    function _getAuctioneerKnownPeriods(
        address cdAuctioneer
    ) internal view returns (uint8[] memory knownPeriods) {
        uint8[] memory currentEnabledPeriods = IConvertibleDepositAuctioneer(cdAuctioneer)
            .getDepositPeriods();
        IConvertibleDepositAuctioneerPendingChanges.PendingDepositPeriodChange[]
            memory pendingChanges = IConvertibleDepositAuctioneerPendingChanges(cdAuctioneer)
                .getPendingDepositPeriodChanges();

        uint256 knownPeriodCount;
        uint8[] memory knownPeriodsBuffer = new uint8[](
            currentEnabledPeriods.length + pendingChanges.length
        );

        for (uint256 i = 0; i < currentEnabledPeriods.length; i++) {
            uint8 period = currentEnabledPeriods[i];
            if (_containsPeriod(knownPeriodsBuffer, period)) continue;

            knownPeriodsBuffer[knownPeriodCount] = period;
            knownPeriodCount++;
        }

        for (uint256 i = 0; i < pendingChanges.length; i++) {
            uint8 period = pendingChanges[i].depositPeriod;
            if (_containsPeriod(knownPeriodsBuffer, period)) continue;

            knownPeriodsBuffer[knownPeriodCount] = period;
            knownPeriodCount++;
        }

        knownPeriods = new uint8[](knownPeriodCount);
        for (uint256 i = 0; i < knownPeriodCount; i++) {
            knownPeriods[i] = knownPeriodsBuffer[i];
        }
    }

    function _containsPeriod(uint8[] memory periods, uint8 period) internal pure returns (bool) {
        for (uint256 i = 0; i < periods.length; i++) {
            if (periods[i] == period) return true;
        }

        return false;
    }

    function _requireUnchangedLegacyReclaimRate(address cdFacility, address usds) internal view {
        uint16 currentReclaimRate = IDepositFacility(cdFacility).getAssetPeriodReclaimRate(
            IERC20(usds),
            LEGACY_PERIOD
        );
        if (currentReclaimRate != LEGACY_RECLAIM_RATE)
            revert ValidationFailed("6-month reclaim rate changed");
    }

    function _configureReclaimRate(address cdFacility, address usds) internal {
        uint16 currentReclaimRate = IDepositFacility(cdFacility).getAssetPeriodReclaimRate(
            IERC20(usds),
            TARGET_PERIOD
        );
        if (currentReclaimRate != RECLAIM_RATE) {
            _pushAction(
                cdFacility,
                abi.encodeWithSelector(
                    IDepositFacility.setAssetPeriodReclaimRate.selector,
                    IERC20(usds),
                    TARGET_PERIOD,
                    RECLAIM_RATE
                ),
                "Set USDS 3-month CD reclaim rate to 90%"
            );
        }
    }

    function _configureMinimumBid(address cdAuctioneer) internal {
        uint256 currentMinimumBid = IConvertibleDepositAuctioneer(cdAuctioneer).getMinimumBid();

        if (currentMinimumBid != MINIMUM_BID) {
            _pushAction(
                cdAuctioneer,
                abi.encodeWithSelector(
                    IConvertibleDepositAuctioneer.setMinimumBid.selector,
                    MINIMUM_BID
                ),
                "Set CD auctioneer minimum bid"
            );
        }
    }

    function _configureTickStep(address cdAuctioneer) internal {
        if (IConvertibleDepositAuctioneer(cdAuctioneer).getTickStep() != TICK_STEP) {
            _pushAction(
                cdAuctioneer,
                abi.encodeWithSelector(
                    IConvertibleDepositAuctioneer.setTickStep.selector,
                    TICK_STEP
                ),
                "Set CD auction tick step"
            );
        }
    }

    function _validateUnchangedControls(
        address depositManager,
        address cdAuctioneer,
        address emissionManager,
        address usds
    ) internal view {
        if (EmissionManager(emissionManager).minPriceScalar() != MIN_PRICE_SCALAR)
            revert ValidationFailed("Minimum price scalar changed");
        if (EmissionManager(emissionManager).minimumPremium() != 0.5e18)
            revert ValidationFailed("Minimum premium changed");
        if (IConvertibleDepositAuctioneer(cdAuctioneer).getTickSizeBase() != 2e18)
            revert ValidationFailed("Tick-size base changed");
        if (
            IAssetManager(depositManager).getAssetConfiguration(IERC20(usds)).depositCap !=
            60_000_000e18
        ) revert ValidationFailed("USDS deposit cap changed");
    }

    function _configureBaseRateTarget(address emissionManager) internal {
        uint256 currentBaseEmissionsRate = EmissionManager(emissionManager).baseEmissionRate();
        (uint256 currentChangeBy, uint48 currentDaysLeft, bool currentAddition) = EmissionManager(
            emissionManager
        ).rateChange();

        if (currentBaseEmissionsRate == TARGET_BASE_EMISSIONS_RATE) {
            if (currentDaysLeft != 0) {
                _pushAction(
                    emissionManager,
                    abi.encodeWithSelector(EmissionManager.changeBaseRate.selector, 0, 0, false),
                    "Clear pending base emissions rate change"
                );
            }
            return;
        }

        bool add = TARGET_BASE_EMISSIONS_RATE > currentBaseEmissionsRate;
        uint256 changeBy = add
            ? TARGET_BASE_EMISSIONS_RATE - currentBaseEmissionsRate
            : currentBaseEmissionsRate - TARGET_BASE_EMISSIONS_RATE;
        uint48 forNumBeats = 1;

        if (
            currentChangeBy == changeBy && currentDaysLeft == forNumBeats && currentAddition == add
        ) {
            return;
        }

        _pushAction(
            emissionManager,
            abi.encodeWithSelector(
                EmissionManager.changeBaseRate.selector,
                changeBy,
                forNumBeats,
                add
            ),
            "Schedule base emissions rate target"
        );
    }

    function _configureEmissionTickSize(address emissionManager) internal {
        if (EmissionManager(emissionManager).tickSize() != TICK_SIZE) {
            _pushAction(
                emissionManager,
                abi.encodeWithSelector(EmissionManager.setTickSize.selector, TICK_SIZE),
                "Set CD tick size"
            );
        }
    }

    // Executes the proposal actions.
    function _run(Addresses addresses, address) internal override {
        _simulateActions(
            address(_kernel),
            addresses.getAddress("olympus-governor"),
            addresses.getAddress("olympus-legacy-gohm"),
            addresses.getAddress("proposer")
        );
    }

    // Validates the post-execution state.
    function _validate(Addresses addresses, address) internal view override {
        address depositManager = addresses.getAddress("olympus-policy-deposit-manager-1_0");
        address cdFacility = addresses.getAddress(
            "olympus-policy-convertible-deposit-facility-1_0"
        );
        address cdAuctioneer = addresses.getAddress(
            "olympus-policy-convertible-deposit-auctioneer-1_0"
        );
        address emissionManager = addresses.getAddress("olympus-policy-emissionmanager-1_2");
        address usds = addresses.getAddress("external-tokens-USDS");
        address timelock = addresses.getAddress("olympus-timelock");

        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        if (!roles.hasRole(timelock, ADMIN_ROLE))
            revert ValidationFailed("Timelock lacks admin role");

        IDepositManager.AssetPeriodStatus memory status = IDepositManager(depositManager)
            .isAssetPeriod(IERC20(usds), TARGET_PERIOD, cdFacility);
        if (!status.isConfigured)
            revert ValidationFailed("DepositManager 3-month period is not configured");
        if (!status.isEnabled)
            revert ValidationFailed("DepositManager 3-month period is not enabled");

        _validateAuctioneerDepositPeriods(cdAuctioneer);

        if (
            !(IDepositFacility(cdFacility).getAssetPeriodReclaimRate(IERC20(usds), TARGET_PERIOD) ==
                RECLAIM_RATE)
        ) revert ValidationFailed("3-month reclaim rate is incorrect");
        if (
            !(IDepositFacility(cdFacility).getAssetPeriodReclaimRate(IERC20(usds), LEGACY_PERIOD) ==
                LEGACY_RECLAIM_RATE)
        ) revert ValidationFailed("6-month reclaim rate changed");
        if (IConvertibleDepositAuctioneer(cdAuctioneer).getMinimumBid() != MINIMUM_BID)
            revert ValidationFailed("Minimum bid is incorrect");
        if (IConvertibleDepositAuctioneer(cdAuctioneer).getTickStep() != TICK_STEP)
            revert ValidationFailed("Tick step is incorrect");
        if (EmissionManager(emissionManager).minPriceScalar() != MIN_PRICE_SCALAR)
            revert ValidationFailed("Min price scalar is incorrect");
        if (EmissionManager(emissionManager).tickSize() != TICK_SIZE)
            revert ValidationFailed("Tick size is incorrect");

        _validateUnchangedControls(depositManager, cdAuctioneer, emissionManager, usds);
        _validateBaseRateTarget(emissionManager);
    }

    function _validateAuctioneerDepositPeriods(address cdAuctioneer) internal view {
        uint8[] memory knownPeriods = _getAuctioneerKnownPeriods(cdAuctioneer);

        for (uint256 i = 0; i < knownPeriods.length; i++) {
            uint8 period = knownPeriods[i];
            (, bool isPendingEnabled) = IConvertibleDepositAuctioneer(cdAuctioneer)
                .isDepositPeriodEnabled(period);

            if (period == TARGET_PERIOD) {
                if (!isPendingEnabled)
                    revert ValidationFailed("3-month auctioneer period is not pending-enabled");
            } else {
                if (isPendingEnabled)
                    revert ValidationFailed("Non-target auctioneer period is pending-enabled");
            }
        }

        (, bool targetPeriodPendingEnabled) = IConvertibleDepositAuctioneer(cdAuctioneer)
            .isDepositPeriodEnabled(TARGET_PERIOD);
        if (!targetPeriodPendingEnabled)
            revert ValidationFailed("3-month auctioneer period is not pending-enabled");
    }

    function _validateBaseRateTarget(address emissionManager) internal view {
        uint256 currentBaseEmissionsRate = EmissionManager(emissionManager).baseEmissionRate();
        (uint256 changeBy, uint48 daysLeft, bool addition) = EmissionManager(emissionManager)
            .rateChange();

        if (currentBaseEmissionsRate == TARGET_BASE_EMISSIONS_RATE) {
            if (daysLeft != 0)
                revert ValidationFailed("Base emissions rate target has stale pending change");
            return;
        }

        if (daysLeft != 1)
            revert ValidationFailed("Base emissions rate change duration is not 1 beat");

        if (addition) {
            if (currentBaseEmissionsRate + changeBy != TARGET_BASE_EMISSIONS_RATE)
                revert ValidationFailed("Base emissions rate increase does not reach target");
        } else {
            if (changeBy > currentBaseEmissionsRate)
                revert ValidationFailed("Base emissions rate change underflows");
            if (currentBaseEmissionsRate - changeBy != TARGET_BASE_EMISSIONS_RATE)
                revert ValidationFailed("Base emissions rate decrease does not reach target");
        }
    }
}

contract ConvertibleDepositRetuningProposalScript is ProposalScript {
    constructor() ProposalScript(new ConvertibleDepositRetuningProposal()) {}
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
