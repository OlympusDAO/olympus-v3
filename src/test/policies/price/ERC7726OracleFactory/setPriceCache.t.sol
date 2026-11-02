// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {MockNonPriceCache} from "src/test/mocks/MockNonPriceCache.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";
import {ERC7726OracleFactoryTest} from "./ERC7726OracleFactoryTest.sol";

contract ERC7726OracleFactorySetPriceCacheTest is ERC7726OracleFactoryTest {
    // Scenarios: ERC7726-CACHE-P01.
    function test_whenCallerIsAdmin_setsPriceCache(bool reenabled_) public givenFactoryIsEnabled {
        _reenableFactoryIfNeeded(reenabled_);
        MockPriceCache cache = _newCache();

        vm.expectEmit(true, false, false, true, address(factory));
        emit IERC7726OracleFactory.PriceCacheSet(address(cache));

        vm.prank(admin);
        factory.setPriceCache(address(cache));

        assertEq(factory.getPriceCache(), address(cache), "Price cache should be updated");
    }

    // Scenarios: ERC7726-CACHE-I01.
    function test_whenPriceCacheAddressIsZero_reverts() public givenFactoryIsEnabled {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726OracleFactory.ERC7726OracleFactory_InvalidPriceCache.selector,
                address(0)
            )
        );
        factory.setPriceCache(address(0));
    }

    // Scenarios: ERC7726-CACHE-A01.
    function test_whenCallerIsOracleManager_reverts() public givenFactoryIsEnabled {
        MockPriceCache cache = _newCache();

        vm.prank(oracleManager);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        factory.setPriceCache(address(cache));
    }

    // Scenarios: ERC7726-CACHE-A02.
    function test_whenCallerIsNotAdmin_reverts(address caller_) public givenFactoryIsEnabled {
        vm.assume(caller_ != admin);

        MockPriceCache cache = _newCache();

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        factory.setPriceCache(address(cache));
    }

    // Scenarios: ERC7726-CACHE-I02.
    function test_whenPriceCacheDoesNotImplementIPriceCache_reverts() public givenFactoryIsEnabled {
        MockNonPriceCache nonPriceCache = new MockNonPriceCache();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726OracleFactory.ERC7726OracleFactory_InvalidPriceCache.selector,
                address(nonPriceCache)
            )
        );
        factory.setPriceCache(address(nonPriceCache));
    }

    // Scenarios: ERC7726-CACHE-I03.
    function test_whenPriceCacheUsesDifferentKernel_reverts() public givenFactoryIsEnabled {
        MockPriceCache cache = new MockPriceCache(makeAddr("DIFFERENT_KERNEL"));

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(cache),
                address(kernel),
                makeAddr("DIFFERENT_KERNEL")
            )
        );
        factory.setPriceCache(address(cache));
    }

    // Scenarios: ERC7726-CACHE-L02, ERC7726-CACHE-I04.
    function test_whenPriceCacheUnchanged_reverts(bool reenabled_) public givenFactoryIsEnabled {
        _reenableFactoryIfNeeded(reenabled_);

        bytes memory interfaceCall = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IPriceCache).interfaceId)
        );
        bytes memory kernelCall = abi.encodeWithSelector(bytes4(0xd4aae0c4)); // kernel()
        vm.mockCallRevert(address(priceCache), interfaceCall, hex"deadbeef");
        vm.mockCallRevert(address(priceCache), kernelCall, hex"deadbeef");
        vm.expectCall(address(priceCache), interfaceCall, uint64(0));
        vm.expectCall(address(priceCache), kernelCall, uint64(0));
        vm.recordLogs();

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726OracleFactory.ERC7726OracleFactory_UnchangedAddress.selector,
                address(priceCache)
            )
        );
        vm.prank(admin);
        factory.setPriceCache(address(priceCache));

        assertEq(factory.getPriceCache(), address(priceCache), "Cache pointer unchanged");
        assertTrue(factory.isEnabled(), "Factory remains enabled");
        assertEq(kernel.isPolicyActive(factory), true, "Factory membership unchanged");
        assertEq(vm.getRecordedLogs().length, 0, "Unchanged selection emits no logs");
    }

    // Scenarios: ERC7726-CACHE-L03.
    function test_givenInactive_whenPriceCacheUnchanged_revertsActivityFirst(
        bool reenabled_
    ) public givenFactoryIsEnabled {
        _reenableFactoryIfNeeded(reenabled_);
        kernel.executeAction(Actions.DeactivatePolicy, address(factory));

        bytes memory interfaceCall = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IPriceCache).interfaceId)
        );
        bytes memory kernelCall = abi.encodeWithSelector(bytes4(0xd4aae0c4)); // kernel()
        vm.mockCallRevert(address(priceCache), interfaceCall, hex"deadbeef");
        vm.mockCallRevert(address(priceCache), kernelCall, hex"deadbeef");
        vm.expectCall(address(priceCache), interfaceCall, uint64(0));
        vm.expectCall(address(priceCache), kernelCall, uint64(0));
        vm.recordLogs();

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726OracleFactory.ERC7726OracleFactory_PolicyNotActive.selector
            )
        );
        vm.prank(admin);
        factory.setPriceCache(address(priceCache));

        assertEq(factory.getPriceCache(), address(priceCache), "Cache pointer unchanged");
        assertTrue(factory.isEnabled(), "Factory remains enabled");
        assertEq(kernel.isPolicyActive(factory), false, "Factory membership unchanged");
        assertEq(vm.getRecordedLogs().length, 0, "Unchanged selection emits no logs");
    }

    // Scenarios: ERC7726-CACHE-A03.
    function test_whenCallerIsNotAdmin_whenPriceCacheUnchanged_reverts(
        address caller_
    ) public givenFactoryIsEnabled {
        vm.assume(caller_ != admin);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        factory.setPriceCache(address(priceCache));
        assertEq(factory.getPriceCache(), address(priceCache), "Unauthorized call preserves cache");
    }

    // Scenarios: ERC7726-CACHE-L01.
    function test_givenDisabled_whenPriceCacheUnchanged_reverts(address caller_) public {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        factory.setPriceCache(address(priceCache));
        assertEq(factory.getPriceCache(), address(priceCache), "Disabled call preserves cache");
    }

    function _reenableFactoryIfNeeded(bool reenabled_) internal {
        if (reenabled_) {
            _disableFactory();
            _enableFactory();
        }
    }

    function _newCache() internal returns (MockPriceCache cache_) {
        cache_ = new MockPriceCache(address(kernel));
    }

    // Scenarios: ERC7726-CACHE-L04.
    function test_givenInactive_whenAnyCallerChangesFactory_revertsActivityFirst(
        address caller_,
        bool enabled_
    ) public {
        if (enabled_) _enableFactory();
        vm.prank(kernel.executor());
        kernel.executeAction(Actions.DeactivatePolicy, address(factory));
        vm.expectRevert(IERC7726OracleFactory.ERC7726OracleFactory_PolicyNotActive.selector);
        vm.prank(caller_);
        factory.setPriceCache(address(priceCache));
        assertEq(factory.getPriceCache(), address(priceCache), "Disabled call preserves cache");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
