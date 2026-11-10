// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracleConfigTimelock} from "src/policies/interfaces/IBackingOracleConfigTimelock.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansConfigTimelock.sol";
import {IBurnerLoansInventoryConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol";
import {IBurnerLoansPayoutConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansPayoutConfigTimelock.sol";
import {IBurnerLoansRiskConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansRiskConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {fromSubKeycode, toSubKeycode} from "src/Submodules.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_INVENTORY_PROVIDER_ROLE, BACKING_ADMIN_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Policy} from "src/Kernel.sol";
import {BurnerLoansForkTest} from "./BurnerLoansProposal/fixtures/BurnerLoansForkTest.sol";

contract BurnerLoansProposalForkTest is BurnerLoansForkTest {
    // Scenarios: BLPF-P01.
    function test_givenPreparedMainnet_whenGovernanceExecutes() public view {
        assertTrue(_activator.isActivated(), "Governance activates the lending graph");
        assertTrue(_price.isAssetApproved(_graph.usde), "Governance admits USDe into PRICE");
        assertEq(_core.getAssetCount(), 2, "Governance configures both lending markets");
        (address selectedAuth, uint256 authEpoch) = _core.authConfig();
        assertEq(
            selectedAuth,
            addresses.getAddress("olympus-periphery-burner-loans-auth"),
            "Governance selects the deployed Auth"
        );
        assertEq(authEpoch, 1, "Governance installs Auth exactly once");
        assertEq(
            IPriceCache(_graph.priceCache).getCachedPrice(_graph.ohm, _graph.usde).updatedAt,
            0,
            "OCG leaves USDe cache cold"
        );
        assertTrue(
            _roles.hasRole(_dao, BURNER_LOANS_INVENTORY_PROVIDER_ROLE),
            "DAO inventory provider granted"
        );
        assertFalse(_roles.hasRole(address(_activator), ADMIN_ROLE), "Temporary ADMIN is removed");
        assertTrue(
            _roles.hasRole(_dao, BURNER_LOANS_ADMIN_ROLE),
            "DAO receives delegated operational authority"
        );
        assertEq(
            keccak256(abi.encode(_price.getAssetData(_graph.ohm))),
            _ohmConfiguration,
            "Existing OHM PRICE configuration is preserved"
        );
        assertEq(
            keccak256(abi.encode(_price.getAssetData(_graph.usds))),
            _usdsConfiguration,
            "Existing USDS PRICE configuration is preserved"
        );
        assertEq(
            IDepositManager(_graph.depositManager).getAssetConfiguration(IERC20(_graph.usds)).vault,
            _graph.susds,
            "Shared v1.1 custody registers USDS with sUSDS"
        );
        assertEq(
            IDepositManager(_graph.depositManager).getAssetConfiguration(IERC20(_graph.usde)).vault,
            _graph.susde,
            "Shared v1.1 custody registers USDe with sUSDe"
        );
        assertTrue(
            _roles.hasRole(_dao, BACKING_ADMIN_ROLE),
            "OCG delegates backing updates to DAO"
        );
        assertTrue(
            _roles.hasRole(_dao, REVENUE_DISTRIBUTOR_ADMIN_ROLE),
            "OCG delegates distributor configuration to DAO"
        );
        assertFalse(_roles.hasRole(_dao, ADMIN_ROLE), "DAO does not receive general ADMIN");
        _assertTimelocks();
        _assertPriceAdmission();
        _assertExistingHeartSnapshot();
        _assertHeartOrder();
    }

    // Read-only postconditions for the fixed six-queue deployment graph.
    // forge-lint: disable-next-item(calls-loop)
    function _assertTimelocks() private view {
        address backingQueue = addresses.getAddress(
            "olympus-policy-backing-oracle-config-timelock"
        );
        address[6] memory queues = [
            _graph.configTimelock,
            _graph.riskTimelock,
            _graph.payoutTimelock,
            _graph.inventoryTimelock,
            _graph.revenueDistributorTimelock,
            backingQueue
        ];
        address[6] memory targets = [
            _graph.config,
            _graph.risk,
            _graph.payout,
            _graph.inventory,
            _graph.revenueDistributor,
            _graph.backingOracle
        ];
        address[6] memory boundTargets = [
            address(IBurnerLoansConfigTimelock(queues[0]).burnerLoans()),
            address(IBurnerLoansRiskConfigTimelock(queues[1]).risk()),
            address(IBurnerLoansPayoutConfigTimelock(queues[2]).payout()),
            address(IBurnerLoansInventoryConfigTimelock(queues[3]).inventory()),
            IRevenueDistributorConfigTimelock(queues[4]).distributor(),
            address(IBackingOracleConfigTimelock(queues[5]).backingOracle())
        ];
        for (uint256 i; i < queues.length; ++i) {
            assertGt(queues[i].code.length, 0, "Timelock is deployed");
            assertEq(
                address(Policy(queues[i]).kernel()),
                address(_kernel),
                "Timelock belongs to launch Kernel"
            );
            assertTrue(_kernel.isPolicyActive(Policy(queues[i])), "Timelock is Kernel-active");
            assertEq(boundTargets[i], targets[i], "Timelock binds the intended target");
            assertTrue(
                _kernel.isPolicyActive(Policy(targets[i])),
                "Timelock target is Kernel-active"
            );
            assertEq(
                IConfigOperator(targets[i]).configOperator(),
                queues[i],
                "Target delegates configuration to its timelock"
            );
            assertTrue(IEnabler(queues[i]).isEnabled(), "Timelock is enabled after launch");
            assertTrue(IEnabler(targets[i]).isEnabled(), "Timelock target is enabled after launch");
        }
        assertEq(
            IConfigOperator(_graph.core).configOperator(),
            _graph.config,
            "Config routes its timelocked changes through Core"
        );
    }

    function _assertExistingHeartSnapshot() private view {
        address[6] memory expected = [
            addresses.getAddress("olympus-policy-convertible-deposit-facility-1_0"),
            addresses.getAddress("olympus-policy-reserve-migrator-1_0"),
            addresses.getAddress("olympus-policy-reserve-wrapper-1_0"),
            addresses.getAddress("olympus-policy-operator-1_5"),
            addresses.getAddress("olympus-policy-yieldrepurchasefacility-1_2"),
            addresses.getAddress("olympus-policy-emissionmanager-1_2")
        ];
        // Zero selects execute(); the explicit selectors are migrate(), operate() and endEpoch().
        bytes4[6] memory selectors = [
            bytes4(0),
            bytes4(0x8fd3ab80),
            bytes4(0),
            bytes4(0x7159a618),
            bytes4(0x0b9663db),
            bytes4(0)
        ];
        assertEq(
            _existingHeartTasks.length,
            expected.length,
            "Pinned Heart baseline has six tasks"
        );
        for (uint256 i; i < expected.length; ++i) {
            assertEq(
                _existingHeartTasks[i],
                expected[i],
                "Pinned Heart task retains its recorded index"
            );
            assertEq(
                _existingHeartSelectors[i],
                selectors[i],
                "Pinned Heart selector matches its recorded task"
            );
        }
    }

    function _assertPriceAdmission() private view {
        IPRICEv2.Asset memory asset = _price.getAssetData(_graph.usde);
        assertFalse(asset.storeMovingAverage, "USDe stores no moving average");
        assertFalse(asset.useMovingAverage, "USDe uses no moving average");
        IPRICEv2.Component[] memory feeds = abi.decode(asset.feeds, (IPRICEv2.Component[]));
        assertEq(feeds.length, 1, "USDe has one approved market-price feed");
        assertEq(
            fromSubKeycode(feeds[0].target),
            fromSubKeycode(toSubKeycode("PRICE.CHAINLINK")),
            "USDe uses the existing Chainlink submodule"
        );
        assertEq(feeds[0].selector, bytes4(0x8daf88ac), "USDe uses getOneFeedPrice");
        (address feed, uint48 maximumAge) = abi.decode(feeds[0].params, (address, uint48));
        assertEq(
            feed,
            0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961,
            "USDe uses the witnessed mainnet USD feed"
        );
        assertEq(maximumAge, 86_400, "USDe feed maximum age is one day");
        IPRICEv2.Component memory strategy = abi.decode(asset.strategy, (IPRICEv2.Component));
        assertEq(
            fromSubKeycode(strategy.target),
            bytes20(0),
            "Single-feed USDe uses no aggregation strategy"
        );
        // Only action targets are needed for the ordering and action-budget assertions.
        // forge-lint: disable-next-item(unused-return)
        (address[] memory targets, , ) = _proposal.getProposalActions();
        assertLe(targets.length, 15, "Actual proposal fits Governor action budget");
        for (uint256 i; i < targets.length; ++i) {
            assertTrue(
                targets[i] != 0x5c69f61D384e41b55699C3B10523Ed81c5ef9cbd,
                "PRICE admission is inside the atomic activator call"
            );
        }
    }
}
