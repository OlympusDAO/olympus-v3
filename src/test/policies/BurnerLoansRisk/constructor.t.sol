// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskConstructorTest is BurnerLoansRiskTest {
    error TokenReadFailed();

    // Scenarios: BLRISK-CONSTRUCTOR-P07.
    function test_whenDeployed_thenPricingBindingsEmitEvents(
        address caller_,
        bool useCache_,
        uint48 age_
    ) public {
        address cache = useCache_ ? address(_cache) : address(0);
        vm.expectEmit(true, false, false, true);
        emit IBurnerLoansRisk.BackingOracleSet(address(_oracle));
        vm.expectEmit(true, false, false, true);
        emit IBurnerLoansRisk.PriceCacheSet(cache);
        vm.expectEmit(false, false, false, true);
        emit IBurnerLoansRisk.PriceCacheMaxAgeSet(age_);
        _assertDeployment(
            _deploy(IERC20(address(_ohm)), address(_oracle), cache, age_, caller_),
            address(_ohm),
            cache,
            age_
        );
    }

    // Scenarios: BLRISK-CONSTRUCTOR-P07.
    function test_whenInitialPricingBindingsUseBoundaryValues_thenEventsEmit() public {
        test_whenDeployed_thenPricingBindingsEmitEvents(address(this), false, 0);
        test_whenDeployed_thenPricingBindingsEmitEvents(address(this), true, type(uint48).max);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I15.
    function test_whenOhmDecimalsResponseIsOversized_reverts(
        uint16 length_,
        address caller_
    ) public {
        uint256 length = bound(length_, 33, type(uint16).max);
        _rejectDecimalsResponse(new bytes(length), caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I15.
    function test_whenOhmDecimalsOversizedResponseBoundaries_reverts(address caller_) public {
        _rejectDecimalsResponse(new bytes(33), caller_);
        _rejectDecimalsResponse(new bytes(64), caller_);
        _rejectDecimalsResponse(new bytes(type(uint16).max), caller_);
    }

    function _deploy(
        IERC20 ohm_,
        address oracle_,
        address cache_,
        uint48 age_,
        address caller_
    ) private returns (BurnerLoansRisk deployed) {
        vm.prank(caller_);
        deployed = new BurnerLoansRisk(_kernel, ohm_, oracle_, cache_, age_, address(this));
    }

    function _assertDeployment(
        BurnerLoansRisk deployed_,
        address token_,
        address cache_,
        uint48 age_
    ) private view {
        assertEq(deployed_.ohm(), token_, "immutable OHM");
        address boundCore = deployed_.core();
        assertEq(boundCore, address(this), "Immutable compatible Core binding");
        assertEq(address(deployed_.kernel()), address(_kernel), "Kernel binding");
        assertEq(deployed_.configOperator(), address(0), "no initial operator");
        assertEq(deployed_.backingOracle(), address(_oracle), "oracle binding");
        assertEq(deployed_.priceCache(), cache_, "cache binding");
        assertEq(deployed_.priceCacheMaxAge(), age_, "exact age");
        assertFalse(deployed_.isEnabled(), "initially disabled");
        assertEq(deployed_.lastTransitionAt(), 0, "never transitioned");
        assertFalse(_kernel.isPolicyActive(deployed_), "deployment does not activate policy");
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I14.
    function test_whenCoreBindingIsZero_reverts(address caller_) public {
        vm.expectCall(
            address(0),
            abi.encodeCall(IERC165.supportsInterface, (type(IERC165).interfaceId)),
            uint64(0)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_InvalidCore.selector,
                address(0)
            )
        );
        vm.prank(caller_);
        new BurnerLoansRisk(
            _kernel,
            IERC20(address(_ohm)),
            address(_oracle),
            address(0),
            0,
            address(0)
        );
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I09.
    function test_whenZeroOhm_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoansRisk_InvalidOhm.selector, address(0))
        );
        _deploy(IERC20(address(0)), address(_oracle), address(0), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I10.
    function test_whenEoaOhm_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_InvalidOhm.selector,
                address(0xBEEF)
            )
        );
        _deploy(IERC20(address(0xBEEF)), address(_oracle), address(0), 0, caller_);
    }

    function _rejectDecimals(uint8 decimals_, address caller_) private {
        MockERC20 token = new MockERC20("Token", "T", decimals_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_InvalidOhm.selector,
                address(token)
            )
        );
        _deploy(IERC20(address(token)), address(_oracle), address(0), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I11.
    function test_whenOhmPrecisionIsUnsupported_reverts(uint8 decimals_, address caller_) public {
        _rejectDecimals(uint8(bound(decimals_, 37, type(uint8).max)), caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I11.
    function test_whenOhmPrecisionBoundaries_reverts(address caller_) public {
        _rejectDecimals(37, caller_);
        _rejectDecimals(type(uint8).max, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-P02.
    function test_whenOhmDecimalsRevert_reverts(address caller_) public {
        vm.mockCallRevert(
            address(_ohm),
            abi.encodeCall(IERC20.decimals, ()),
            abi.encodeWithSelector(TokenReadFailed.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_InvalidOhm.selector,
                address(_ohm)
            )
        );
        _deploy(IERC20(address(_ohm)), address(_oracle), address(0), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I03.
    function test_whenZeroOracle_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBackingOracle.selector,
                address(0)
            )
        );
        _deploy(IERC20(address(_ohm)), address(0), address(0), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I04.
    function test_whenEoaOracle_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBackingOracle.selector,
                address(0xBEEF)
            )
        );
        _deploy(IERC20(address(_ohm)), address(0xBEEF), address(0), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I05.
    function test_whenMissingOracleInterface_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBackingOracle.selector,
                address(_cache)
            )
        );
        _deploy(IERC20(address(_ohm)), address(_cache), address(0), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D01.
    function test_whenRevertingOracleERC165_reverts(address caller_) public {
        vm.mockCallRevert(
            address(_oracle),
            abi.encodeWithSelector(IERC165.supportsInterface.selector),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBackingOracle.selector,
                address(_oracle)
            )
        );
        _deploy(IERC20(address(_ohm)), address(_oracle), address(0), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D04.
    function test_whenMalformedOracleERC165_reverts(address caller_) public {
        vm.mockCall(
            address(_oracle),
            abi.encodeWithSelector(IERC165.supportsInterface.selector),
            hex"01"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBackingOracle.selector,
                address(_oracle)
            )
        );
        _deploy(IERC20(address(_ohm)), address(_oracle), address(0), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D12.
    function test_whenMissingOracleEnabler_reverts(address caller_) public {
        vm.mockCall(
            address(_oracle),
            abi.encodeCall(IERC165.supportsInterface, (type(IEnabler).interfaceId)),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBackingOracle.selector,
                address(_oracle)
            )
        );
        _deploy(IERC20(address(_ohm)), address(_oracle), address(0), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I07.
    function test_whenMissingCacheInterface_reverts(address caller_) public {
        _cache.setInterfaceSupport(type(IPriceCache).interfaceId, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidPriceCache.selector,
                address(_cache)
            )
        );
        _deploy(IERC20(address(_ohm)), address(_oracle), address(_cache), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D02.
    function test_whenMissingCacheEnabler_reverts(address caller_) public {
        _cache.setInterfaceSupport(type(IEnabler).interfaceId, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidPriceCache.selector,
                address(_cache)
            )
        );
        _deploy(IERC20(address(_ohm)), address(_oracle), address(_cache), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D03.
    function test_whenCacheKernelDiffers_reverts(address caller_) public {
        vm.mockCall(
            address(_cache),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0xBAD))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_cache),
                address(_kernel),
                address(0xBAD)
            )
        );
        _deploy(IERC20(address(_ohm)), address(_oracle), address(_cache), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-P06.
    function test_givenVersionGetterReverts_whenDeployed(address caller_) public {
        vm.mockCallRevert(
            address(_cache),
            abi.encodeWithSignature("VERSION()"),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        _assertDeployment(
            _deploy(IERC20(address(_ohm)), address(_oracle), address(_cache), 0, caller_),
            address(_ohm),
            address(_cache),
            0
        );
    }

    function _rejectDecimalsResponse(bytes memory response_, address caller_) private {
        vm.mockCall(address(_ohm), abi.encodeCall(IERC20.decimals, ()), response_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_InvalidOhm.selector,
                address(_ohm)
            )
        );
        _deploy(IERC20(address(_ohm)), address(_oracle), address(0), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I12.
    function test_whenOhmDecimalsResponseIsShort_reverts(uint8 length_, address caller_) public {
        _rejectDecimalsResponse(new bytes(bound(length_, 0, 31)), caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I12.
    function test_whenOhmDecimalsResponseBoundaries_reverts(address caller_) public {
        _rejectDecimalsResponse(hex"", caller_);
        _rejectDecimalsResponse(hex"00", caller_);
        _rejectDecimalsResponse(new bytes(31), caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I13.
    function test_whenOhmDecimalsResponseIsNoncanonical_reverts(
        uint256 word_,
        address caller_
    ) public {
        _rejectDecimalsResponse(abi.encode(bound(word_, 256, type(uint256).max)), caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I13.
    function test_whenOhmDecimalsWordBoundaries_reverts(address caller_) public {
        _rejectDecimalsResponse(abi.encode(uint256(256)), caller_);
        _rejectDecimalsResponse(abi.encode(type(uint256).max), caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-P04.
    function test_whenNoCoreIsDeployed_reverts(address caller_) public {
        address core = address(0xBEEF);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoansRisk_InvalidCore.selector, core)
        );
        vm.prank(caller_);
        new BurnerLoansRisk(_kernel, IERC20(address(_ohm)), address(_oracle), address(0), 1, core);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I06.
    function test_whenNoCache(address caller_) public {
        _assertDeployment(
            _deploy(IERC20(address(_ohm)), address(_oracle), address(0), 1, caller_),
            address(_ohm),
            address(0),
            1
        );
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I08.
    function test_whenZeroAge(address caller_) public {
        _assertDeployment(
            _deploy(IERC20(address(_ohm)), address(_oracle), address(_cache), 0, caller_),
            address(_ohm),
            address(_cache),
            0
        );
    }

    // Scenarios: BLRISK-CONSTRUCTOR-N01.
    function test_whenCacheAgeIsPositive(uint48 age_, address caller_) public {
        uint48 age = uint48(bound(age_, 1, type(uint48).max));
        _assertDeployment(
            _deploy(IERC20(address(_ohm)), address(_oracle), address(_cache), age, caller_),
            address(_ohm),
            address(_cache),
            age
        );
    }

    // Scenarios: BLRISK-CONSTRUCTOR-N01.
    function test_whenCacheAgeEndpoints(address caller_) public {
        _assertDeployment(
            _deploy(IERC20(address(_ohm)), address(_oracle), address(_cache), 1, caller_),
            address(_ohm),
            address(_cache),
            1
        );
        _assertDeployment(
            _deploy(
                IERC20(address(_ohm)),
                address(_oracle),
                address(_cache),
                type(uint48).max,
                caller_
            ),
            address(_ohm),
            address(_cache),
            type(uint48).max
        );
    }

    function _precision(uint8 decimals_, address caller_) private {
        MockERC20 token = new MockERC20("Token", "T", decimals_);
        BurnerLoansRisk deployed = _deploy(
            IERC20(address(token)),
            address(_oracle),
            address(0),
            0,
            caller_
        );
        _assertDeployment(deployed, address(token), address(0), 0);
        _kernel.executeAction(Actions.ActivatePolicy, address(deployed));
        deployed.enable("");
        _market.debtToken = address(token);
        _market.debtDecimals = decimals_;
        _mockMarket();
        // One whole OHM always needs $1 collateral regardless of token precision.
        assertEq(
            deployed.health(_prices(), _MARKET, 1e6, 10 ** uint256(decimals_)),
            1e18,
            "stored OHM precision used"
        );
    }

    // Scenarios: BLRISK-CONSTRUCTOR-N02.
    function test_whenOhmDecimalsAreSupported(uint8 decimals_, address caller_) public {
        _precision(uint8(bound(decimals_, 0, 36)), caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-N02.
    function test_whenOhmPrecisionEndpoints(address caller_) public {
        _precision(0, caller_);
        _precision(1, caller_);
        _precision(9, caller_);
        _precision(36, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-L01.
    function test_givenCache10_whenDeployed(address caller_) public {
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(true)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(false));
        _assertDeployment(
            _deploy(IERC20(address(_ohm)), address(_oracle), address(_cache), 0, caller_),
            address(_ohm),
            address(_cache),
            0
        );
    }

    // Scenarios: BLRISK-CONSTRUCTOR-L02.
    function test_givenCache01_whenDeployed(address caller_) public {
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(false)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(true));
        _assertDeployment(
            _deploy(IERC20(address(_ohm)), address(_oracle), address(_cache), 0, caller_),
            address(_ohm),
            address(_cache),
            0
        );
    }

    // Scenarios: BLRISK-CONSTRUCTOR-L03.
    function test_givenCache00_whenDeployed(address caller_) public {
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(false)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(false));
        _assertDeployment(
            _deploy(IERC20(address(_ohm)), address(_oracle), address(_cache), 0, caller_),
            address(_ohm),
            address(_cache),
            0
        );
    }

    // Scenarios: BLRISK-CONSTRUCTOR-L04.
    function test_givenCache11_whenDeployed(address caller_) public {
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(true)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(true));
        _assertDeployment(
            _deploy(IERC20(address(_ohm)), address(_oracle), address(_cache), 0, caller_),
            address(_ohm),
            address(_cache),
            0
        );
    }

    // Scenarios: BLRISK-CONSTRUCTOR-P08.
    function test_whenReferralStateInitiallyEmpty(address referrer_) public view {
        assertEq(_risk.referralFeeBps(), 0, "referral share starts at zero");
        assertFalse(_risk.isReferrerAllowed(address(0)), "zero is never whitelisted");
        assertFalse(_risk.isReferrerAllowed(referrer_), "no embedded partner list");
    }

    // Scenarios: BLRISK-CONSTRUCTOR-K03.
    function test_givenMalformedCoreKernel_whenDeployed_reverts(
        address caller_,
        bytes memory data_
    ) public {
        vm.assume(data_.length != 32);
        vm.mockCall(address(this), abi.encodeWithSignature("kernel()"), data_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(this)
            )
        );
        _deploy(IERC20(address(_ohm)), address(_oracle), address(0), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-K03.
    function test_givenMalformedCoreKernelBoundaries_whenDeployed_reverts(address caller_) public {
        bytes[6] memory responses = [
            new bytes(0),
            new bytes(1),
            new bytes(31),
            new bytes(33),
            new bytes(64),
            abi.encode(type(uint256).max)
        ];
        // Every response must fail with the same owned error and preserve state.
        // forge-lint: disable-next-line(calls-loop)
        for (uint256 i; i < responses.length; ++i) {
            vm.mockCall(address(this), abi.encodeWithSignature("kernel()"), responses[i]);
            vm.expectRevert(
                abi.encodeWithSelector(
                    PolicyDependency.PolicyDependency_InvalidDependency.selector,
                    address(this)
                )
            );
            _deploy(IERC20(address(_ohm)), address(_oracle), address(0), 0, caller_);
        }
    }

    // Scenarios: BLRISK-CONSTRUCTOR-K01.
    function test_givenDifferentCoreKernel_whenDeployed_reverts(address caller_) public {
        address otherKernel = address(new Kernel());
        vm.mockCall(address(this), abi.encodeWithSignature("kernel()"), abi.encode(otherKernel));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(this),
                address(_kernel),
                otherKernel
            )
        );
        _deploy(IERC20(address(_ohm)), address(_oracle), address(0), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-K02.
    function test_givenRevertingCoreKernel_whenDeployed_reverts(
        address caller_,
        bytes memory data_
    ) public {
        vm.mockCallRevert(address(this), abi.encodeWithSignature("kernel()"), data_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(this)
            )
        );
        _deploy(IERC20(address(_ohm)), address(_oracle), address(0), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I20.
    function test_givenMissingCoreInterface_whenDeployed_reverts(address caller_) public {
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCall(address(this), probe, abi.encode(false));
        vm.mockCallRevert(address(this), abi.encodeWithSignature("kernel()"), hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_InvalidCore.selector,
                address(this)
            )
        );
        _deploy(IERC20(address(_ohm)), address(_oracle), address(0), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I21.
    function test_givenRevertingCoreInterface_whenDeployed_reverts(address caller_) public {
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCallRevert(
            address(this),
            probe,
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_InvalidCore.selector,
                address(this)
            )
        );
        _deploy(IERC20(address(_ohm)), address(_oracle), address(0), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-I22.
    function test_givenMalformedCoreInterface_whenDeployed_reverts(address caller_) public {
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCall(address(this), probe, hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_InvalidCore.selector,
                address(this)
            )
        );
        _deploy(IERC20(address(_ohm)), address(_oracle), address(0), 0, caller_);
    }

    // Scenarios: BLRISK-CONSTRUCTOR-K05, BLRISK-CONSTRUCTOR-P05.
    function test_givenCoreLifecycle_whenCompatible(bool active_, bool enabled_) public {
        _mockCoreReadiness(active_, enabled_);
        _assertDeployment(
            _deploy(IERC20(address(_ohm)), address(_oracle), address(_cache), 1, address(this)),
            address(_ohm),
            address(_cache),
            1
        );
    }

    // Scenarios: BLRISK-CONSTRUCTOR-K05.
    function test_whenCoreLifecycleSeeds() public {
        _expectNoCoreReadinessReads();
        for (uint8 flags; flags < 4; ++flags) {
            uint256 checkpoint = vm.snapshotState();
            test_givenCoreLifecycle_whenCompatible(flags & 1 != 0, flags & 2 != 0);
            assertTrue(vm.revertToState(checkpoint), "Restores lifecycle seed state");
        }
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D13.
    function test_givenBackingForeignKernel_whenAdmitted_reverts() public {
        vm.mockCall(
            address(_oracle),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0xBAD))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_oracle),
                address(_kernel),
                address(0xBAD)
            )
        );
        _deploy(IERC20(address(_ohm)), address(_oracle), address(0), 0, address(this));
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D14.
    function test_givenBackingMalformedKernel_whenAdmitted_reverts() public {
        vm.mockCall(
            address(_oracle),
            abi.encodeWithSignature("kernel()"),
            abi.encode(type(uint256).max)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_oracle)
            )
        );
        _deploy(IERC20(address(_ohm)), address(_oracle), address(0), 0, address(this));
    }

    // Scenarios: BLRISK-CONSTRUCTOR-D15.
    function test_givenUnversionedBacking_whenDeployed() public {
        assertFalse(
            _oracle.supportsInterface(type(IVersioned).interfaceId),
            "fixture oracle has no version interface"
        );
        _assertDeployment(
            _deploy(IERC20(address(_ohm)), address(_oracle), address(0), 0, address(this)),
            address(_ohm),
            address(0),
            0
        );
    }
}
