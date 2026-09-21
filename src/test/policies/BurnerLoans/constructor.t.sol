// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Libraries
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {BurnerLoans} from "src/policies/BurnerLoans.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

// Scenario-specific contracts and fixtures have no cross-file consumers.
// forge-lint: disable-start(multi-contract-file)

contract BurnerLoansConstructorTest is BurnerLoansTest {
    event PriceCacheSet(address indexed priceCache);

    // constructor
    // given OHM address is zero
    //  when BurnerLoans is deployed
    //   then it reverts
    function test_constructor_givenOhmIsZero_reverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        new BurnerLoans(
            kernel,
            IERC20(address(0)),
            depositManager,
            IPriceCache(address(0)),
            backingOracle
        );
    }

    // constructor
    // given DepositManager address is zero
    //  when BurnerLoans is deployed
    //   then it reverts
    function test_constructor_givenDepositManagerIsZero_reverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        new BurnerLoans(
            kernel,
            IERC20(address(ohm)),
            IDepositManager(address(0)),
            IPriceCache(address(0)),
            backingOracle
        );
    }

    // constructor
    // given DepositManager does not implement the required interface
    //  when BurnerLoans is deployed
    //   then it reverts
    function test_constructor_givenDepositManagerDoesNotSupportInterface_reverts() public {
        MockInvalidDepositManager invalidDepositManager = new MockInvalidDepositManager();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(invalidDepositManager)
            )
        );
        new BurnerLoans(
            kernel,
            IERC20(address(ohm)),
            IDepositManager(address(invalidDepositManager)),
            IPriceCache(address(0)),
            backingOracle
        );
    }

    function test_constructor_givenDepositManagerSupportsOnlyV1_reverts() public {
        MockV1OnlyDepositManager v1OnlyDepositManager = new MockV1OnlyDepositManager();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(v1OnlyDepositManager)
            )
        );
        new BurnerLoans(
            kernel,
            IERC20(address(ohm)),
            IDepositManager(address(v1OnlyDepositManager)),
            IPriceCache(address(0)),
            backingOracle
        );
    }

    function test_givenDepositManagerOmitsAssetManagerV1_1_whenDeployed_reverts() public {
        MockDepositManagerWithoutAssetManagerV1_1 invalidDepositManager = new MockDepositManagerWithoutAssetManagerV1_1();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(invalidDepositManager)
            )
        );
        new BurnerLoans(
            kernel,
            IERC20(address(ohm)),
            IDepositManager(address(invalidDepositManager)),
            IPriceCache(address(0)),
            backingOracle
        );
    }

    // constructor
    // given DepositManager belongs to another Kernel
    //  when BurnerLoans is deployed
    //   then it rejects the cross-Kernel dependency
    function test_constructor_givenDepositManagerKernelMismatch_reverts() public {
        Kernel otherKernel = new Kernel();
        ReceiptTokenManager otherReceiptTokenManager = new ReceiptTokenManager();
        DepositManager otherDepositManager = new DepositManager(
            address(otherKernel),
            address(otherReceiptTokenManager)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_DepositManagerKernelMismatch.selector,
                address(kernel),
                address(otherKernel)
            )
        );
        new BurnerLoans(
            kernel,
            IERC20(address(ohm)),
            otherDepositManager,
            IPriceCache(address(0)),
            backingOracle
        );
    }

    // constructor
    // given backing oracle address is zero
    //  when BurnerLoans is deployed
    //   then it reverts
    function test_constructor_givenBackingOracleIsZero_reverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        new BurnerLoans(
            kernel,
            IERC20(address(ohm)),
            depositManager,
            IPriceCache(address(0)),
            IOlympusBackingOracle(address(0))
        );
    }

    // constructor
    // given backing oracle does not implement IOlympusBackingOracle
    //  when BurnerLoans is deployed
    //   then it reverts
    function test_constructor_givenBackingOracleDoesNotSupportInterface_reverts() public {
        MockInvalidBackingOracle invalidBackingOracle = new MockInvalidBackingOracle();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidBackingOracle.selector,
                address(invalidBackingOracle)
            )
        );
        new BurnerLoans(
            kernel,
            IERC20(address(ohm)),
            depositManager,
            IPriceCache(address(0)),
            IOlympusBackingOracle(address(invalidBackingOracle))
        );
    }

    // constructor
    // given PriceCache is zero
    //  when BurnerLoans is deployed
    //   then direct PRICE mode is configured
    function test_constructor_givenPriceCacheIsZero_setsDirectPriceMode() public view {
        assertEq(burnerLoans.priceCache(), address(0), "price cache");
        assertEq(address(burnerLoans.context().priceCache), address(0), "context price cache");
        assertEq(burnerLoans.context().priceCacheMaxAge, 0, "context max cache age");
    }

    // given PriceCache is active and enabled
    //  when the contract is constructed
    //   then it accepts the candidate
    function test_constructor_givenPriceCacheIsActiveAndEnabled_acceptsCandidate() public {
        vm.startPrank(admin);
        PriceCache candidate = _deployPriceCache(true, true);
        vm.stopPrank();

        _assertConstructorAcceptsPriceCache(candidate);
    }

    // given a PriceCache is configured
    //  when the contract is constructed
    //   then it emits the dependency event
    function test_constructor_givenPriceCache_emitsDependencyEvent() public {
        MockPriceCache candidate = new MockPriceCache(address(kernel));

        vm.expectEmit(true, false, false, true);
        emit PriceCacheSet(address(candidate));
        _deployBurnerLoansWithPriceCache(candidate);
    }

    // given PriceCache is active and disabled
    //  when the contract is constructed
    //   then it accepts the candidate
    function test_constructor_givenPriceCacheIsActiveAndDisabled_acceptsCandidate() public {
        vm.startPrank(admin);
        PriceCache candidate = _deployPriceCache(true, false);
        vm.stopPrank();

        _assertConstructorAcceptsPriceCache(candidate);
    }

    // given PriceCache is inactive
    //  when the contract is constructed
    //   then it accepts the candidate
    function test_constructor_givenPriceCacheIsInactive_acceptsCandidate() public {
        vm.prank(admin);
        PriceCache candidate = _deployPriceCache(false, false);

        _assertConstructorAcceptsPriceCache(candidate);
    }

    // given PriceCache is not a contract
    //  when the contract is constructed
    //   then the call reverts
    function test_constructor_givenPriceCacheIsNotAContract_reverts() public {
        address candidate = makeAddr("priceCache");

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidPriceCache.selector, candidate)
        );
        _deployBurnerLoansWithPriceCache(IPriceCache(candidate));
    }

    // given PriceCache does not support required interfaces
    //  when the contract is constructed
    //   then the call reverts
    function test_constructor_givenPriceCacheDoesNotSupportRequiredInterfaces_reverts() public {
        MockPriceCache candidate = new MockPriceCache(address(kernel));
        candidate.setInterfaceSupport(type(IVersioned).interfaceId, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidPriceCache.selector,
                address(candidate)
            )
        );
        _deployBurnerLoansWithPriceCache(candidate);
    }

    // given PriceCache belongs to another kernel
    //  when the contract is constructed
    //   then the call reverts
    function test_constructor_givenPriceCacheBelongsToAnotherKernel_reverts() public {
        Kernel otherKernel = new Kernel();
        MockPriceCache candidate = new MockPriceCache(address(otherKernel));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_PriceCacheKernelMismatch.selector,
                address(kernel),
                address(otherKernel)
            )
        );
        _deployBurnerLoansWithPriceCache(candidate);
    }

    // given PriceCache version is 1.0
    //  when the contract is constructed
    //   then it accepts the configuration
    function test_constructor_givenPriceCacheVersionIsOneZero_accepts() public {
        MockPriceCache candidate = new MockPriceCache(address(kernel));
        candidate.setVersion(1, 0);

        _assertConstructorAcceptsPriceCache(candidate);
    }

    // given PriceCache major version is unsupported
    //  when the contract is constructed
    //   then the call reverts
    function test_constructor_givenPriceCacheMajorVersionIsUnsupported_reverts() public {
        MockPriceCache candidate = new MockPriceCache(address(kernel));
        candidate.setVersion(2, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_UnsupportedPriceCacheVersion.selector,
                address(candidate),
                2,
                0
            )
        );
        _deployBurnerLoansWithPriceCache(candidate);
    }

    // constructor
    // given constructor parameters are valid
    //  when the deployed BurnerLoans instance is inspected
    //   then immutable dependencies and defaults are set
    function test_constructor_givenValidParams_setsImmutableDependencies() public view {
        assertEq(address(burnerLoans.context().ohm), address(ohm), "ohm");
        assertEq(
            address(burnerLoans.context().depositManager),
            address(depositManager),
            "deposit manager"
        );
        assertEq(
            burnerLoans.gracePeriod(),
            BurnerLoansConstants.REENABLE_GRACE_PERIOD,
            "reenable grace period"
        );
        assertEq(burnerLoans.backingOracle(), address(backingOracle), "backing oracle");
        assertEq(burnerLoans.inventory(), address(inventory), "configured inventory");
    }

    // constructor
    // given constructor parameters are valid
    //  when BurnerLoans is deployed
    //   then it emits the initial configuration
    function test_givenValidParams_whenDeployed() public {
        vm.expectEmit(false, false, false, true);
        emit IGracePeriod.GracePeriodSet(BurnerLoansConstants.REENABLE_GRACE_PERIOD);
        vm.expectEmit(true, false, false, true);
        emit PriceCacheSet(address(0));
        vm.expectEmit(true, false, false, true);
        emit IBurnerLoans.BackingOracleSet(address(backingOracle));

        new BurnerLoans(
            kernel,
            IERC20(address(ohm)),
            depositManager,
            IPriceCache(address(0)),
            backingOracle
        );
    }

    function _assertConstructorAcceptsPriceCache(IPriceCache candidate_) internal {
        BurnerLoans deployed = _deployBurnerLoansWithPriceCache(candidate_);

        assertEq(deployed.priceCache(), address(candidate_), "price cache getter");
        assertEq(
            address(deployed.context().priceCache),
            address(candidate_),
            "context price cache"
        );
        assertEq(deployed.context().priceCacheMaxAge, 0, "context max cache age");
    }

    function _deployBurnerLoansWithPriceCache(
        IPriceCache candidate_
    ) internal returns (BurnerLoans deployed_) {
        deployed_ = new BurnerLoans(
            kernel,
            IERC20(address(ohm)),
            depositManager,
            candidate_,
            backingOracle
        );
    }
}

contract MockInvalidDepositManager is IERC165 {
    function supportsInterface(bytes4) external pure returns (bool) {
        return false;
    }
}

contract MockV1OnlyDepositManager is IERC165 {
    function supportsInterface(bytes4 interfaceId_) external pure returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IDepositManager).interfaceId;
    }
}

contract MockDepositManagerWithoutAssetManagerV1_1 is IERC165 {
    function supportsInterface(bytes4 interfaceId_) external pure returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IDepositManager).interfaceId ||
            interfaceId_ == type(IDepositManagerV1_1).interfaceId;
    }
}

contract MockInvalidBackingOracle is IERC165 {
    function supportsInterface(bytes4) external pure returns (bool) {
        return false;
    }
}

contract MockInvalidInventory is IERC165 {
    function supportsInterface(bytes4) external pure returns (bool) {
        return false;
    }
}

// forge-lint: disable-end(multi-contract-file)
