// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IYieldRepurchaseFacilityV2Activator} from "src/proposals/interfaces/IYieldRepurchaseFacilityV2Activator.sol";

// Mocks
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";

// Contracts
import {Actions, Kernel, Policy} from "src/Kernel.sol";
import {BackingOracle} from "src/policies/BackingOracle.sol";
import {BackingOracleConfigTimelock} from "src/policies/BackingOracleConfigTimelock.sol";
import {YieldRepurchaseFacilityV2Config} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Config.sol";
import {YieldRepurchaseFacilityV2Activator} from "src/proposals/YieldRepurchaseFacilityV2Activator.sol";
import {YieldRepurchaseFacilityV2ActivatorTest} from "./YieldRepurchaseFacilityV2ActivatorTest.sol";

/// @notice The constructor of the activator and the views of what it binds: `timelock`,
///         `deployment`, `launchParameters`, the constants and `supportsInterface`.
contract YieldRepurchaseFacilityV2ActivatorTests_constructor is
    YieldRepurchaseFacilityV2ActivatorTest
{
    /// @notice The number of contracts of `Deployment`.
    uint256 internal constant DEPLOYMENT_MEMBER_COUNT = 16;

    // ========== HELPERS ========== //

    /// @notice Returns the deployment of the rig with the member at `index_` replaced, and the
    ///         name the activator reports the member under.
    function _deploymentWith(
        uint256 index_,
        address value_
    )
        internal
        view
        returns (
            IYieldRepurchaseFacilityV2Activator.Deployment memory deployment,
            string memory parameter
        )
    {
        deployment = _deployment();
        if (index_ == 0) (deployment.kernel, parameter) = (value_, "kernel");
        else if (index_ == 1) (deployment.backingOracle, parameter) = (value_, "backingOracle");
        else if (index_ == 2)
            (deployment.backingOracleConfigTimelock, parameter) = (
                value_,
                "backingOracleConfigTimelock"
            );
        else if (index_ == 3) (deployment.config, parameter) = (value_, "config");
        else if (index_ == 4) (deployment.configTimelock, parameter) = (value_, "configTimelock");
        else if (index_ == 5) (deployment.facility, parameter) = (value_, "facility");
        else if (index_ == 6) (deployment.yieldRepoV1, parameter) = (value_, "yieldRepoV1");
        else if (index_ == 7) (deployment.heart, parameter) = (value_, "heart");
        else if (index_ == 8) (deployment.priceConfig, parameter) = (value_, "priceConfig");
        else if (index_ == 9) (deployment.bondAuctioneer, parameter) = (value_, "bondAuctioneer");
        else if (index_ == 10)
            (deployment.usdeUsdPriceFeed, parameter) = (value_, "usdeUsdPriceFeed");
        else if (index_ == 11) (deployment.ohm, parameter) = (value_, "ohm");
        else if (index_ == 12) (deployment.usds, parameter) = (value_, "usds");
        else if (index_ == 13) (deployment.sUsds, parameter) = (value_, "sUsds");
        else if (index_ == 14) (deployment.usde, parameter) = (value_, "usde");
        else (deployment.sUsde, parameter) = (value_, "sUsde");
    }

    function _construct(
        IYieldRepurchaseFacilityV2Activator.Deployment memory deployment_
    ) internal returns (YieldRepurchaseFacilityV2Activator) {
        return
            new YieldRepurchaseFacilityV2Activator(ocgTimelock, deployment_, _launchParameters());
    }

    // ========== ERROR CONDITIONS ========== //

    // when the timelock is the zero address
    //   [X] it reverts with ZeroAddress naming the timelock

    function test_whenTimelockIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_ZeroAddress
                    .selector,
                "timelock"
            )
        );
        new YieldRepurchaseFacilityV2Activator(address(0), _deployment(), _launchParameters());
    }

    // when a contract of the deployment is the zero address
    //   [X] it reverts with ZeroAddress naming the contract

    function test_whenDeploymentMemberIsZero_reverts() public {
        // Every member of the deployment, one at a time
        for (uint256 i = 0; i < DEPLOYMENT_MEMBER_COUNT; ++i) {
            (
                IYieldRepurchaseFacilityV2Activator.Deployment memory deployment,
                string memory parameter
            ) = _deploymentWith(i, address(0));

            vm.expectRevert(
                abi.encodeWithSelector(
                    IYieldRepurchaseFacilityV2Activator
                        .YieldRepurchaseFacilityV2Activator_ZeroAddress
                        .selector,
                    parameter
                )
            );
            _construct(deployment);
        }
    }

    // when a contract of the deployment holds no code
    //   [X] it reverts with NotAContract naming the contract and the address

    function test_whenDeploymentMemberHasNoCode_reverts() public {
        address account = makeAddr("accountWithoutCode");
        // Every member of the deployment, one at a time
        for (uint256 i = 0; i < DEPLOYMENT_MEMBER_COUNT; ++i) {
            (
                IYieldRepurchaseFacilityV2Activator.Deployment memory deployment,
                string memory parameter
            ) = _deploymentWith(i, account);

            vm.expectRevert(
                abi.encodeWithSelector(
                    IYieldRepurchaseFacilityV2Activator
                        .YieldRepurchaseFacilityV2Activator_NotAContract
                        .selector,
                    parameter,
                    account
                )
            );
            _construct(deployment);
        }
    }

    // when a listed Clearinghouse is the zero address
    //   [X] it reverts with ZeroAddress naming the Clearinghouse

    function test_whenClearinghouseIsZero_reverts() public {
        IYieldRepurchaseFacilityV2Activator.LaunchParameters
            memory parameters = _launchParameters();
        parameters.clearinghouses[1].clearinghouse = address(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_ZeroAddress
                    .selector,
                "clearinghouse"
            )
        );
        new YieldRepurchaseFacilityV2Activator(ocgTimelock, _deployment(), parameters);
    }

    // when a Clearinghouse is listed twice
    //   [X] it reverts with DuplicateClearinghouse naming the Clearinghouse

    function test_whenClearinghouseIsListedTwice_reverts() public {
        IYieldRepurchaseFacilityV2Activator.LaunchParameters
            memory parameters = _launchParameters();
        parameters.clearinghouses[2].clearinghouse = address(clearinghouseOne);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_DuplicateClearinghouse
                    .selector,
                address(clearinghouseOne)
            )
        );
        new YieldRepurchaseFacilityV2Activator(ocgTimelock, _deployment(), parameters);
    }

    // given a bound policy reports another Kernel
    //   [X] it reverts with BindingMismatch naming the policy, the reported Kernel and the bound one

    function test_givenPolicyReportsAnotherKernel_reverts() public {
        address otherKernel = address(new Kernel());
        vm.label(otherKernel, "otherKernel");
        // Every policy whose Kernel is compared, one at a time
        for (uint256 i = 0; i < KERNEL_BOUND_COUNT; ++i) {
            (address policy, string memory binding) = _kernelBound(i);
            vm.mockCall(
                policy,
                abi.encodeWithSelector(Policy(policy).kernel.selector),
                abi.encode(otherKernel)
            );

            _expectRevertBindingMismatch(binding, otherKernel, address(kernel));
            _construct(_deployment());

            vm.clearMockedCalls();
        }
    }

    // when the oracle timelock is bound to another oracle than the supplied one
    //   [X] it reverts with BindingMismatch naming the oracle of the timelock

    function test_whenOracleTimelockIsBoundToAnotherOracle_reverts() public {
        BackingOracle otherOracle = new BackingOracle(kernel);
        vm.label(address(otherOracle), "otherOracle");
        IYieldRepurchaseFacilityV2Activator.Deployment memory deployment = _deployment();
        deployment.backingOracle = address(otherOracle);

        _expectRevertBindingMismatch(
            "BackingOracleConfigTimelock backingOracle",
            address(backingOracle),
            address(otherOracle)
        );
        _construct(deployment);
    }

    // when the config timelock is bound to another configuration policy than the supplied one
    //   [X] it reverts with BindingMismatch naming the configuration policy of the timelock

    function test_whenConfigTimelockIsBoundToAnotherConfig_reverts() public {
        YieldRepurchaseFacilityV2Config otherConfig = new YieldRepurchaseFacilityV2Config(
            kernel,
            GRACE_PERIOD
        );
        vm.label(address(otherConfig), "otherConfig");
        IYieldRepurchaseFacilityV2Activator.Deployment memory deployment = _deployment();
        deployment.config = address(otherConfig);

        _expectRevertBindingMismatch(
            "YieldRepurchaseFacilityV2ConfigTimelock config",
            address(config),
            address(otherConfig)
        );
        _construct(deployment);
    }

    // when the facility reads another oracle than the supplied oracle pair
    //   [X] it reverts with BindingMismatch naming the oracle of the facility

    function test_whenFacilityReadsAnotherOracle_reverts() public {
        BackingOracle otherOracle = new BackingOracle(kernel);
        vm.label(address(otherOracle), "otherOracle");
        BackingOracleConfigTimelock otherTimelock = new BackingOracleConfigTimelock(
            kernel,
            otherOracle
        );
        vm.label(address(otherTimelock), "otherOracleTimelock");
        IYieldRepurchaseFacilityV2Activator.Deployment memory deployment = _deployment();
        deployment.backingOracle = address(otherOracle);
        deployment.backingOracleConfigTimelock = address(otherTimelock);

        _expectRevertBindingMismatch(
            "YieldRepurchaseFacilityV2 backingOracle",
            address(backingOracle),
            address(otherOracle)
        );
        _construct(deployment);
    }

    // when the facility creates its markets on another auctioneer than the supplied one
    //   [X] it reverts with BindingMismatch naming the auctioneer of the facility

    function test_whenFacilityUsesAnotherAuctioneer_reverts() public {
        address otherAuctioneer = address(_deployAuctioneer("otherAuctioneer"));
        IYieldRepurchaseFacilityV2Activator.Deployment memory deployment = _deployment();
        deployment.bondAuctioneer = otherAuctioneer;

        _expectRevertBindingMismatch(
            "YieldRepurchaseFacilityV2 bondAuctioneer",
            address(bondAuctioneer),
            otherAuctioneer
        );
        _construct(deployment);
    }

    // when the facility is bound to another OHM than the supplied one
    //   [X] it reverts with BindingMismatch naming the OHM of the facility

    function test_whenFacilityIsBoundToAnotherOhm_reverts() public {
        address otherOhm = address(new MockERC20("Other OHM", "oOHM", 9));
        vm.label(otherOhm, "otherOhm");
        IYieldRepurchaseFacilityV2Activator.Deployment memory deployment = _deployment();
        deployment.ohm = otherOhm;

        _expectRevertBindingMismatch("YieldRepurchaseFacilityV2 OHM", address(ohm), otherOhm);
        _construct(deployment);
    }

    // when v1.2 draws its yield from another vault than the supplied sUSDS vault
    //   [X] it reverts with BindingMismatch naming the vault of v1.2

    function test_whenV1UsesAnotherVault_reverts() public {
        address otherVault = address(new MockERC4626(usds, "Other vault", "oVLT"));
        vm.label(otherVault, "otherVault");
        IYieldRepurchaseFacilityV2Activator.Deployment memory deployment = _deployment();
        deployment.sUsds = otherVault;

        _expectRevertBindingMismatch(
            "YieldRepurchaseFacility v1.2 sReserve",
            address(sUsds),
            otherVault
        );
        _construct(deployment);
    }

    // when the asset of the sUSDS vault is not the supplied USDS
    //   [X] it reverts with BindingMismatch naming the asset of the vault

    function test_whenSUsdsAssetIsNotUsds_reverts() public {
        address otherToken = address(new MockERC20("Other token", "OTK", 18));
        vm.label(otherToken, "otherToken");
        IYieldRepurchaseFacilityV2Activator.Deployment memory deployment = _deployment();
        deployment.usds = otherToken;

        _expectRevertBindingMismatch("sUSDS asset", address(usds), otherToken);
        _construct(deployment);
    }

    // when the asset of the sUSDe vault is not the supplied USDe
    //   [X] it reverts with BindingMismatch naming the asset of the vault

    function test_whenSUsdeAssetIsNotUsde_reverts() public {
        address otherToken = address(new MockERC20("Other token", "OTK", 18));
        vm.label(otherToken, "otherToken");
        IYieldRepurchaseFacilityV2Activator.Deployment memory deployment = _deployment();
        deployment.usde = otherToken;

        _expectRevertBindingMismatch("sUSDe asset", address(usde), otherToken);
        _construct(deployment);
    }

    // ========== SUCCESS CONDITIONS ========== //

    // given the deployed stack
    //   [X] the activator reports the timelock, the deployment and the launch values it was built with
    //   [X] it is not activated
    //   [X] its bytecode fits the contract size limit

    function test_givenDeployedStack() public view {
        assertEq(activator.timelock(), ocgTimelock, "timelock should be the governance timelock");
        assertFalse(activator.isActivated(), "a deployed activator should not be activated");
        // The limit of EIP-170
        assertLe(address(activator).code.length, 24_576, "the activator should fit EIP-170");

        assertEq(
            keccak256(abi.encode(activator.deployment())),
            keccak256(abi.encode(_deployment())),
            "deployment() should return the constructor argument"
        );
        assertEq(
            keccak256(abi.encode(activator.launchParameters())),
            keccak256(abi.encode(_launchParameters())),
            "launchParameters() should return the constructor argument"
        );

        IYieldRepurchaseFacilityV2Activator.LaunchParameters memory parameters = activator
            .launchParameters();
        assertEq(parameters.backing, BACKING, "backing");
        assertEq(parameters.initialDiscount, INITIAL_DISCOUNT, "initialDiscount");
        assertEq(parameters.maxPricePremium, MAX_PRICE_PREMIUM, "maxPricePremium");
        assertEq(parameters.sUsds.yieldBuybackShare, SUSDS_YIELD_BUYBACK_SHARE, "sUSDS share");
        assertFalse(parameters.sUsds.sellShares, "sUSDS sellShares");
        assertEq(parameters.sUsde.yieldBuybackShare, SUSDE_YIELD_BUYBACK_SHARE, "sUSDe share");
        assertTrue(parameters.sUsde.sellShares, "sUSDe sellShares");
        assertEq(parameters.clearinghouses.length, 3, "Clearinghouse count");
        assertEq(
            parameters.clearinghouses[1].clearinghouse,
            address(clearinghouseTwo),
            "the Clearinghouses should keep the constructor order"
        );
        assertEq(parameters.clearinghouses[1].offset, CLEARINGHOUSE_TWO_OFFSET, "offset");
        assertTrue(parameters.clearinghouses[1].included, "included");
    }

    // given the deployed stack
    //   [X] the constants are the registration parameters of USDe and the cap of the sUSDe next yield

    function test_constants() public view {
        // 100,000 USDe (18 decimals)
        assertEq(activator.MAX_SUSDE_NEXT_YIELD(), 100_000e18, "MAX_SUSDE_NEXT_YIELD");
        // One day, in seconds
        assertEq(activator.USDE_FEED_UPDATE_THRESHOLD(), 86_400, "USDE_FEED_UPDATE_THRESHOLD");
        // 1 USD (18 decimals)
        assertEq(activator.USDE_EXPECTED_PRICE(), 1e18, "USDE_EXPECTED_PRICE");
        // 1%, in basis points
        assertEq(activator.USDE_PRICE_TOLERANCE_BPS(), 100, "USDE_PRICE_TOLERANCE_BPS");
    }

    // when the interface id is that of the activator interface or of ERC165
    //   [X] supportsInterface returns true
    // when the interface id is any other
    //   [X] supportsInterface returns false

    function test_supportsInterface(bytes4 interfaceId_) public view {
        bool expected = interfaceId_ == type(IYieldRepurchaseFacilityV2Activator).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId;
        assertEq(
            activator.supportsInterface(interfaceId_),
            expected,
            "supportsInterface should match the two advertised interfaces only"
        );
        assertTrue(
            activator.supportsInterface(type(IYieldRepurchaseFacilityV2Activator).interfaceId),
            "the activator interface should be advertised"
        );
        assertTrue(
            activator.supportsInterface(type(IERC165).interfaceId),
            "ERC165 should be advertised"
        );
        assertFalse(activator.supportsInterface(0xffffffff), "0xffffffff is never advertised");
    }

    // when no Clearinghouse is listed
    //   [X] it deploys with an empty list

    function test_whenNoClearinghouseIsListed() public {
        IYieldRepurchaseFacilityV2Activator.LaunchParameters
            memory parameters = _launchParameters();
        parameters
            .clearinghouses = new IYieldRepurchaseFacilityV2Activator.ClearinghouseParameters[](0);

        YieldRepurchaseFacilityV2Activator deployed = _deployActivator(_deployment(), parameters);

        assertEq(deployed.launchParameters().clearinghouses.length, 0, "the list should be empty");
    }

    // given the five policies are not active in the Kernel
    //   [X] it deploys: the constructor reads the bindings only

    function test_givenPoliciesNotActive() public {
        kernel.executeAction(Actions.DeactivatePolicy, address(backingOracle));
        kernel.executeAction(Actions.DeactivatePolicy, address(backingOracleConfigTimelock));
        kernel.executeAction(Actions.DeactivatePolicy, address(config));
        kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
        kernel.executeAction(Actions.DeactivatePolicy, address(facility));

        YieldRepurchaseFacilityV2Activator deployed = _deployActivator(
            _deployment(),
            _launchParameters()
        );

        assertEq(
            deployed.deployment().facility,
            address(facility),
            "the activator should bind an inactive stack"
        );
    }

    // when the launch values are arbitrary
    //   [X] it stores them as supplied: their bounds belong to the contracts that receive them

    function test_whenLaunchValuesAreArbitrary(
        uint256 backing_,
        uint256 initialDiscount_,
        uint256 maxPricePremium_,
        uint256 sUsdsShare_,
        uint256 sUsdeShare_,
        uint256 offset_
    ) public {
        IYieldRepurchaseFacilityV2Activator.LaunchParameters
            memory parameters = _launchParameters();
        parameters.backing = backing_;
        parameters.initialDiscount = initialDiscount_;
        parameters.maxPricePremium = maxPricePremium_;
        parameters.sUsds.yieldBuybackShare = sUsdsShare_;
        parameters.sUsde.yieldBuybackShare = sUsdeShare_;
        parameters.clearinghouses[0].offset = offset_;

        YieldRepurchaseFacilityV2Activator deployed = _deployActivator(_deployment(), parameters);

        assertEq(
            keccak256(abi.encode(deployed.launchParameters())),
            keccak256(abi.encode(parameters)),
            "launchParameters() should return the supplied values"
        );
    }
}
