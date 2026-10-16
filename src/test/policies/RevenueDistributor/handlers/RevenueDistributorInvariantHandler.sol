// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Invariant assertions and balance snapshots intentionally inspect a bounded set of destinations.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant)

// Libraries
import {Test} from "@forge-std-1.16.2/Test.sol";

// Contracts
import {Actions, Kernel, toKeycode} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {RevenueDistributorConfigTimelock} from "src/policies/RevenueDistributorConfigTimelock.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";

contract RevenueDistributorInvariantHandler is Test {
    struct Dependencies {
        Kernel kernel;
        RevenueDistributor distributor;
        RevenueDistributorConfigTimelock configTimelock;
        MockRevertingTransferToken asset;
        OlympusTreasury originalTreasury;
        OlympusTreasury replacementTreasury;
        MockYieldRepurchaseRecipient firstYieldRecipient;
        MockYieldRepurchaseRecipient secondYieldRecipient;
        address admin;
        address alice;
        address bob;
    }

    Kernel internal _kernel;
    RevenueDistributor internal _distributor;
    RevenueDistributorConfigTimelock internal _configTimelock;
    MockRevertingTransferToken internal _asset;
    OlympusTreasury internal _replacementTreasury;
    address internal _admin;
    address internal _expectedTreasury;
    address internal _expectedYieldRecipient;
    uint16 internal _expectedRepurchaseBps;
    IRevenueDistributor.AssetRoute[] internal _expectedRoutes;
    bool internal _expectedActive;
    address[] internal _tracked;
    address[] internal _fixedRecipients;
    mapping(address recipient => bool blocked) internal _blocked;
    mapping(address recipient => uint256 amount) internal _fixedPending;
    uint256 internal _treasuryPending;
    uint256 internal _yieldPending;
    uint256 internal _minted;

    constructor(Dependencies memory dependencies_) {
        _kernel = dependencies_.kernel;
        _distributor = dependencies_.distributor;
        _configTimelock = dependencies_.configTimelock;
        _asset = dependencies_.asset;
        _replacementTreasury = dependencies_.replacementTreasury;
        _admin = dependencies_.admin;
        _expectedTreasury = address(dependencies_.originalTreasury);
        _expectedYieldRecipient = address(dependencies_.firstYieldRecipient);
        _expectedRepurchaseBps = 2_000;
        _expectedRoutes.push(
            IRevenueDistributor.AssetRoute({recipient: dependencies_.alice, bps: 3_333})
        );
        _expectedRoutes.push(
            IRevenueDistributor.AssetRoute({
                recipient: address(dependencies_.replacementTreasury),
                bps: 1_667
            })
        );
        _expectedActive = true;

        _fixedRecipients.push(dependencies_.alice);
        _fixedRecipients.push(dependencies_.bob);
        _fixedRecipients.push(address(dependencies_.replacementTreasury));
        _tracked.push(dependencies_.alice);
        _tracked.push(dependencies_.bob);
        _tracked.push(address(dependencies_.originalTreasury));
        _tracked.push(address(dependencies_.replacementTreasury));
        _tracked.push(address(dependencies_.firstYieldRecipient));
        _tracked.push(address(dependencies_.secondYieldRecipient));

        // Seeded receipts are 100 base units of an 18-decimal token. Independent shares round down:
        // yield = floor(100 * 2,000 / 10,000) = 20;
        // Alice = floor(100 * 3,333 / 10,000) = 33;
        // replacement Treasury as a fixed recipient = floor(100 * 1,667 / 10,000) = 16;
        // the original Treasury receives the 31-unit residual, including rounding dust.
        _minted = 100;
        _yieldPending = 20;
        _fixedPending[dependencies_.alice] = 33;
        _fixedPending[address(dependencies_.replacementTreasury)] = 16;
        _treasuryPending = 31;
        for (uint256 i; i < _tracked.length; ++i) _blocked[_tracked[i]] = true;
    }

    function receiveRevenue(uint96 amount_) external {
        // Bound random receipts to 1e12 base units; the range includes small rounding cases.
        uint256 amount = uint256(amount_ % 1e12) + 1;
        _asset.mint(address(_distributor), amount);
        _minted += amount;
    }

    function setTransferFailure(uint8 recipientIndex_, bool blocked_) external {
        address recipient = _tracked[recipientIndex_ % _tracked.length];
        _asset.setTransferReverts(recipient, blocked_);
        _blocked[recipient] = blocked_;
    }

    function setRoute(uint8 route_) external {
        IRevenueDistributor.AssetRoute[] memory routes;
        uint8 selection = route_ % 4;
        if (selection == 0) {
            routes = new IRevenueDistributor.AssetRoute[](0);
        } else {
            routes = new IRevenueDistributor.AssetRoute[](1);
            routes[0] = IRevenueDistributor.AssetRoute({
                recipient: _fixedRecipients[selection - 1],
                bps: 3_333
            });
            // A module upgrade can make a historical fixed recipient the current Treasury.
            // New routes must omit that address, while old liabilities remain payable.
            if (routes[0].recipient == _expectedTreasury) return;
        }
        uint16 yieldBps = _expectedYieldRecipient == address(0) ? 0 : 2_000;
        _expectedRepurchaseBps = yieldBps;
        delete _expectedRoutes;
        for (uint256 i; i < routes.length; ++i) _expectedRoutes.push(routes[i]);
        _expectedActive = true;
        vm.prank(address(_configTimelock));
        _distributor.setAssetRoutes(address(_asset), yieldBps, routes);
    }

    function retireAsset() external {
        if (!_expectedActive) return;
        _expectedActive = false;
        _expectedRepurchaseBps = 0;
        delete _expectedRoutes;
        vm.prank(address(_configTimelock));
        _distributor.disableAssetRoutes(address(_asset));
    }

    function setYieldDestination(uint8 selection_) external {
        address recipient;
        if (selection_ % 3 == 1) recipient = _tracked[4];
        if (selection_ % 3 == 2) recipient = _tracked[5];
        if (recipient == address(0) && _expectedRepurchaseBps != 0) return;
        vm.prank(address(_configTimelock));
        _distributor.setYieldRecipient(recipient);
        _expectedYieldRecipient = recipient;
    }

    function upgradeTreasury() external {
        if (_expectedTreasury == address(_replacementTreasury)) return;
        _expectedTreasury = address(_replacementTreasury);
        vm.prank(_admin);
        _kernel.executeAction(Actions.UpgradeModule, address(_replacementTreasury));
    }

    function distribute() external {
        if (!_expectedActive) return;
        uint256 receipts = _asset.balanceOf(address(_distributor)) - ghostPending();
        uint16 yieldBps = _expectedRepurchaseBps;
        IRevenueDistributor.AssetRoute[] memory routes = _expectedRoutes;
        if (receipts != 0) {
            for (uint256 i; i < routes.length; ++i) {
                if (routes[i].recipient != _expectedTreasury) continue;
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IRevenueDistributor.RevenueDistributor_InvalidRecipient.selector,
                        routes[i].recipient
                    )
                );
                _distributor.distribute(address(_asset));
                return;
            }
        }
        uint256[] memory beforeBalances = _recipientBalances();
        // receipts are 18-decimal base units; each basis-point share rounds down to base units.
        if (receipts != 0) {
            uint256 allocated = (receipts * yieldBps) / 10_000;
            _yieldPending += allocated;
            for (uint256 i; i < routes.length; ++i) {
                uint256 share = (receipts * routes[i].bps) / 10_000;
                _fixedPending[routes[i].recipient] += share;
                allocated += share;
            }
            _treasuryPending += receipts - allocated;
        }
        // The mock token has no callback; reconcile delivered shares from balances after the call.
        // forge-lint: disable-next-line(reentrancy-no-eth)
        _distributor.distribute(address(_asset));
        _settleObservedTransfers(beforeBalances);
    }

    function retry(uint8 recipientIndex_) external {
        address recipient = _tracked[recipientIndex_ % _tracked.length];
        uint256 beforeBalance = _asset.balanceOf(recipient);
        _distributor.transferPendingPayout(address(_asset), recipient);
        uint256 delivered = _asset.balanceOf(recipient) - beforeBalance;
        if (delivered != 0) _settle(recipient, delivered);
    }

    function rescueFixed(uint8 recipientIndex_, uint256 amount_) external {
        address recipient = _fixedRecipients[recipientIndex_ % _fixedRecipients.length];
        uint256 available = _fixedPending[recipient];
        if (available == 0 || _blocked[_expectedTreasury]) return;
        uint256 amount = bound(amount_, 1, available);
        uint256 beforeBalance = _asset.balanceOf(_expectedTreasury);
        _fixedPending[recipient] -= amount;
        vm.prank(_admin);
        uint64 actionId = _configTimelock.queueRescuePendingPayout(
            address(_asset),
            recipient,
            _expectedTreasury,
            amount
        );
        vm.warp(block.timestamp + _configTimelock.timelockDelay());
        _configTimelock.executeQueuedAction(actionId);
        assertEq(
            _asset.balanceOf(_expectedTreasury) - beforeBalance,
            amount,
            "configured rescue transfers exactly its liability"
        );
    }

    function rescuePendingPayout(
        uint8 recipientIndex_,
        uint256 amount_,
        uint8 destinationIndex_
    ) external {
        address recipient = _tracked[recipientIndex_ % _tracked.length];
        uint256 available = _expectedFor(recipient);
        address destination = _tracked[destinationIndex_ % _tracked.length];
        if (available == 0 || _blocked[destination]) return;
        uint256 amount = bound(amount_, 1, available);
        uint256 beforeBalance = _asset.balanceOf(destination);
        uint256 remaining = amount;
        uint256 debit = remaining < _fixedPending[recipient] ? remaining : _fixedPending[recipient];
        _fixedPending[recipient] -= debit;
        remaining -= debit;
        address yieldDestination = _expectedYieldRecipient == address(0)
            ? _expectedTreasury
            : _expectedYieldRecipient;
        if (recipient == yieldDestination) {
            debit = remaining < _yieldPending ? remaining : _yieldPending;
            _yieldPending -= debit;
            remaining -= debit;
        }
        if (recipient == _expectedTreasury) _treasuryPending -= remaining;
        vm.prank(_admin);
        uint64 actionId = _configTimelock.queueRescuePendingPayout(
            address(_asset),
            recipient,
            destination,
            amount
        );
        vm.warp(block.timestamp + _configTimelock.timelockDelay());
        _configTimelock.executeQueuedAction(actionId);
        assertEq(
            _asset.balanceOf(destination) - beforeBalance,
            amount,
            "role rescue transfers exactly the selected part"
        );
    }

    function ghostPending() public view returns (uint256 total) {
        total = _treasuryPending + _yieldPending;
        for (uint256 i; i < _fixedRecipients.length; ++i)
            total += _fixedPending[_fixedRecipients[i]];
    }

    function assertAccounting() external view {
        assertEq(
            address(_kernel.getModuleForKeycode(toKeycode("TRSRY"))),
            _expectedTreasury,
            "Kernel Treasury matches the expected upgrade"
        );
        assertEq(
            _distributor.treasury(),
            _expectedTreasury,
            "distributor follows the Kernel Treasury"
        );
        assertEq(
            _distributor.yieldRecipient(),
            _expectedYieldRecipient,
            "selected yield recipient matches the expected destination"
        );
        IRevenueDistributor.AssetState expectedState = _expectedActive
            ? IRevenueDistributor.AssetState.Active
            : IRevenueDistributor.AssetState.Retired;
        assertEq(
            uint256(_distributor.assetState(address(_asset))),
            uint256(expectedState),
            "asset state matches route lifecycle"
        );
        (
            uint16 actualRepurchaseBps,
            IRevenueDistributor.AssetRoute[] memory actualRoutes
        ) = _distributor.getAssetDistribution(address(_asset));
        assertEq(actualRepurchaseBps, _expectedRepurchaseBps, "repurchase bps matches set route");
        assertEq(actualRoutes.length, _expectedRoutes.length, "configured route length matches");
        for (uint256 i; i < actualRoutes.length; ++i) {
            assertEq(
                actualRoutes[i].recipient,
                _expectedRoutes[i].recipient,
                "configured route recipient matches"
            );
            assertEq(actualRoutes[i].bps, _expectedRoutes[i].bps, "configured route bps matches");
        }
        uint256 pending = ghostPending();
        uint256 custody = _asset.balanceOf(address(_distributor));
        assertGe(custody, pending, "custody must cover every unpaid share");

        address[] memory listedAssets = _distributor.getPendingPayoutAssets();
        assertEq(listedAssets.length, pending == 0 ? 0 : 1, "pending asset index matches debt");
        if (pending != 0) assertEq(listedAssets[0], address(_asset), "pending asset is enumerated");

        address[] memory listedRecipients = _distributor.getPendingPayoutRecipients(
            address(_asset)
        );
        uint256 listedTotal;
        for (uint256 i; i < listedRecipients.length; ++i) {
            address recipient = listedRecipients[i];
            uint256 expected = _expectedFor(recipient);
            assertGt(expected, 0, "enumerated recipient has a liability");
            for (uint256 j; j < i; ++j) {
                assertTrue(listedRecipients[j] != recipient, "recipient is listed only once");
            }
            listedTotal += _distributor.pendingPayout(address(_asset), recipient);
        }
        assertEq(listedTotal, pending, "enumerated liabilities equal independent model");

        uint256 accountedSupply = custody;
        for (uint256 i; i < _tracked.length; ++i) {
            address recipient = _tracked[i];
            assertEq(
                _distributor.pendingPayout(address(_asset), recipient),
                _expectedFor(recipient),
                "recipient liability equals independent model"
            );
            accountedSupply += _asset.balanceOf(recipient);
        }
        assertEq(
            accountedSupply,
            _minted,
            "all minted revenue remains in custody or a destination"
        );
    }

    function _recipientBalances() internal view returns (uint256[] memory balances) {
        balances = new uint256[](_tracked.length);
        for (uint256 i; i < _tracked.length; ++i) balances[i] = _asset.balanceOf(_tracked[i]);
    }

    function _settleObservedTransfers(uint256[] memory beforeBalances_) internal {
        for (uint256 i; i < _tracked.length; ++i) {
            address recipient = _tracked[i];
            uint256 delivered = _asset.balanceOf(recipient) - beforeBalances_[i];
            if (delivered != 0) _settle(recipient, delivered);
        }
    }

    function _settle(address recipient_, uint256 delivered_) internal {
        assertEq(
            delivered_,
            _expectedFor(recipient_),
            "a successful transfer pays exactly what is owed"
        );
        delete _fixedPending[recipient_];
        if (recipient_ == _expectedTreasury) delete _treasuryPending;
        address yieldDestination = _expectedYieldRecipient;
        if (yieldDestination == address(0)) yieldDestination = _expectedTreasury;
        if (recipient_ == yieldDestination) delete _yieldPending;
    }

    function _expectedFor(address recipient_) internal view returns (uint256 amount) {
        amount = _fixedPending[recipient_];
        if (recipient_ == _expectedTreasury) amount += _treasuryPending;
        address yieldDestination = _expectedYieldRecipient;
        if (yieldDestination == address(0)) yieldDestination = _expectedTreasury;
        if (recipient_ == yieldDestination) amount += _yieldPending;
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant)
