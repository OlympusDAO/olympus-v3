// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import {LENDRv1} from "src/modules/LENDR/LENDR.v1.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1, RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";
import "src/Kernel.sol";

// Import internal dependencies
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

// Import external dependencies
import {AggregatorV3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
// TODO Import Balancer vault

// Import types
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title Olympus Single-Sided Liquidity Vault
contract SSLiquidityVault is Policy, ReentrancyGuard, RolesConsumer {
    // ========= ERRORS ========= //

    error SSLiquidityVault_InvalidConstruction();

    // ========= STATE ========= //

    // Modules
    LENDRv1 public LENDR;
    MINTRv1 public MINTR;

    // Tokens
    ERC20 public ohm;
    ERC20 public steth;

    // Liquidity Pool
    address public stethOhmPool; // stETH/OHM Balancer pool

    // Price Feeds
    AggregatorV3Interface public ohmEthPriceFeed; // OHM/ETH price feed
    AggregatorV3Interface public ethUsdPriceFeed; // ETH/USD price feed
    AggregatorV3Interface public stethUsdPriceFeed; // stETH/USD price feed

    // User State
    mapping(address => uint256) public stethDeposits; // User stETH deposits
    mapping(address => uint256) public ohmDebtOutstanding; // OHM debt outstanding
    mapping(address => uint256) public lpPositions; // User LP positions

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        address ohm_,
        address steth_,
        address stethOhmPool_,
        address ohmEthPriceFeed_,
        address ethUsdPriceFeed_,
        address stethUsdPriceFeed_
    ) Policy(kernel_) {
        if (
            address(kernel_) == address(0) ||
            ohm_ == address(0) ||
            steth_ == address(0) ||
            stethOhmPool_ == address(0) ||
            ohmEthPriceFeed_ == address(0) ||
            ethUsdPriceFeed_ == address(0) ||
            stethUsdPriceFeed_ == address(0)
        ) revert SSLiquidityVault_InvalidConstruction();

        // Set tokens
        ohm = ERC20(ohm_);
        steth = ERC20(steth_);

        // Set liquidity pool
        stethOhmPool = stethOhmPool_;

        // Set price feeds
        ohmEthPriceFeed = AggregatorV3Interface(ohmEthPriceFeed_);
        ethUsdPriceFeed = AggregatorV3Interface(ethUsdPriceFeed_);
        stethUsdPriceFeed = AggregatorV3Interface(stethUsdPriceFeed_);
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("LENDR");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("ROLES");

        LENDR = LENDRv1(getModuleAddress(dependencies[0]));
        MINTR = MINTRv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](6);
        permissions[0] = Permissions(MINTR.KEYCODE(), MINTR.mintOhm.selector);
        permissions[1] = Permissions(MINTR.KEYCODE(), MINTR.burnOhm.selector);
        permissions[2] = Permissions(MINTR.KEYCODE(), MINTR.increaseMintApproval.selector);
        permissions[3] = Permissions(MINTR.KEYCODE(), MINTR.decreaseMintApproval.selector);
        permissions[4] = Permissions(LENDR.KEYCODE(), LENDR.borrow.selector);
        permissions[5] = Permissions(LENDR.KEYCODE(), LENDR.repay.selector);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @dev    This needs to be nonReentrant since the contract only knows the amount of LP tokens it
    //          receives after an external interaction with the Balancer pool
    function depositAndLP(uint256 amount_) external nonReentrant returns (uint256) {
        // Calculate how much OHM the user needs to borrow
        uint256 ohmToBorrow = _valueCollateral(amount_);

        // Update state about user's deposits and borrows
        stethDeposits[msg.sender] += amount_;
        ohmDebtOutstanding[msg.sender] += ohmToBorrow;

        // Take stETH from user
        steth.transferFrom(msg.sender, address(this), amount_);

        // Borrow OHM
        LENDR.borrow(ohmToBorrow);
        MINTR.mintOhm(address(this), ohmToBorrow);

        // TODO Deposit stETH into Balancer pool

        // TODO Update user's LP position

        // TODO Return amount of LP tokens received
    }

    //============================================================================================//
    //                                     INTERNAL FUNCTIONS                                     //
    //============================================================================================//

    function _valueCollateral(uint256 amount_) internal view returns (uint256) {
        (, int256 stethPrice_, , , ) = stethUsdPriceFeed.latestRoundData();
        (, int256 ohmPrice_, , , ) = ohmEthPriceFeed.latestRoundData();
        (, int256 ethPrice_, , , ) = ethUsdPriceFeed.latestRoundData();

        uint256 ohmUsd = uint256((ohmPrice_ * ethPrice_) / 1e18);

        return (amount_ * uint256(stethPrice_)) / ohmUsd;
    }
}
