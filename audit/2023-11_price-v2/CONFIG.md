# Configuration

This file contains details on how the PRICE module will be configured. It should help auditors in assessing risks.

A Solidity-based batch script system is used to add contract calls into a batch for a Safe Multi-sig. The function is `addToBatch()`, which you will see used routinely below.

## PRICE Configuration

PriceConfig v2 (not in scope in this audit, and not in the current repository) is a permissioned policy that simply forwards on the call to the PRICE module.

For example:

```solidity
/// @notice Configure a new asset on the PRICE module
/// @dev see PRICEv2 for more details on caching behavior when no moving average is stored and component interface
/// @param asset_ The address of the asset to add
/// @param storeMovingAverage_ Whether to store the moving average for this asset
/// @param useMovingAverage_ Whether to use the moving average as part of the price resolution strategy for this asset
/// @param movingAverageDuration_ The duration of the moving average in seconds, only used if `storeMovingAverage_` is true
/// @param lastObservationTime_ The timestamp of the last observation
/// @param observations_ The array of observations to add - the number of observations must match the moving average duration divided by the PRICEv2 observation frequency
/// @param strategy_ The price resolution strategy to use for this asset
/// @param feeds_ The array of price feeds to use for this asset
function addAssetPrice(
    address asset_,
    bool storeMovingAverage_,
    bool useMovingAverage_,
    uint32 movingAverageDuration_,
    uint48 lastObservationTime_,
    uint256[] memory observations_,
    PRICEv2.Component memory strategy_,
    PRICEv2.Component[] memory feeds_
) external onlyRole("priceconfig_policy") {
    PRICE.addAsset(
        asset_,
        storeMovingAverage_,
        useMovingAverage_,
        movingAverageDuration_,
        lastObservationTime_,
        observations_,
        strategy_,
        feeds_
    );
}
```

Here is how PRICE v2 will be configured:

```solidity
        // 3. Upgrade the PRICE module to v2
        // Requires that Operator is deactivated
        console2.log("Upgrading PRICE module to v2");
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.UpgradeModule, priceV2)
        );

        // 4. Activate PriceConfigV2 policy
        console2.log("Activating PriceConfigV2 policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                priceConfigV2
            )
        );

        // 4a. Disable PriceConfigV1 policy (superseded by PriceConfigV2)
        console2.log("Deactivating PriceConfigV1 policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                priceConfigV1
            )
        );

        // 5. Set roles for new policy access control
        // PriceConfigV2 policy
        //     - Give DAO MS the priceconfig_admin role
        //     - Give DAO MS the priceconfig_policy role
        //     - Give Policy MS the priceconfig_policy role
        console2.log("Granting admin role for PriceConfigV2 policy");
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("priceconfig_admin"),
                daoMS
            )
        );
        console2.log("Granting policy role for PriceConfigV2 policy");
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("priceconfig_policy"),
                daoMS
            )
        );
        console2.log("Granting policy role for PriceConfigV2 policy");
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("priceconfig_policy"),
                policyMS
            )
        );

        // 6. Install submodules on PRICEv2
        //     - Install BalancerPoolTokenPrice submodule
        //     - Install BunniPrice submodule
        //     - Install ChainlinkPriceFeeds submodule
        //     - Install ERC4626Price submodule
        //     - Install UniswapV2PoolTokenPrice submodule
        //     - Install UniswapV3Price submodule
        //     - Install SimplePriceFeedStrategy submodule
        console2.log("Installing BalancerPoolTokenPrice submodule");
        addToBatch(
            priceConfigV2,
            abi.encodeWithSelector(PriceConfigV2.installSubmodule.selector, balancerPoolTokenPrice)
        );
        console2.log("Installing BunniPrice submodule");
        addToBatch(
            priceConfigV2,
            abi.encodeWithSelector(PriceConfigV2.installSubmodule.selector, bunniPrice)
        );
        console2.log("Installing ChainlinkPriceFeeds submodule");
        addToBatch(
            priceConfigV2,
            abi.encodeWithSelector(PriceConfigV2.installSubmodule.selector, chainlinkPriceFeeds)
        );
        console2.log("Installing ERC4626Price submodule");
        addToBatch(
            priceConfigV2,
            abi.encodeWithSelector(PriceConfigV2.installSubmodule.selector, erc4626Price)
        );
        console2.log("Installing UniswapV2PoolTokenPrice submodule");
        addToBatch(
            priceConfigV2,
            abi.encodeWithSelector(PriceConfigV2.installSubmodule.selector, uniswapV2PoolTokenPrice)
        );
        console2.log("Installing UniswapV3Price submodule");
        addToBatch(
            priceConfigV2,
            abi.encodeWithSelector(PriceConfigV2.installSubmodule.selector, uniswapV3Price)
        );
        console2.log("Installing SimplePriceFeedStrategy submodule");
        addToBatch(
            priceConfigV2,
            abi.encodeWithSelector(PriceConfigV2.installSubmodule.selector, simplePriceFeedStrategy)
        );

        // ==================== SECTION 2: PRICE v2 Configuration ==================== //

        // This Policy MS batch:
        // 1. Configures DAI on PRICE
        // 2. Configures sDAI on PRICE
        // 3. Configure WETH on PRICE
        // 4. Configure veFXS on PRICE
        // 5. Configure FXS on PRICE
        // 6. Configure USDC on PRICE
        // 7. Configure OHM on PRICE

        // 0. Load variables from the JSON file
        // TODO final values need to be added
        string memory argData = vm.readFile("./src/scripts/ops/batches/RBSv2Install_3_RBS.json");
        uint256 daiLastObsTime_ = argData.readUint(".daiLastObsTime");
        uint256[] memory daiObs_ = argData.readUintArray(".daiObs"); // 7 days * 24 hours / 8 hours = 21 observations
        uint256 usdcLastObsTime_ = argData.readUint(".usdcLastObsTime");
        uint256[] memory usdcObs_ = argData.readUintArray(".usdcObs"); // 7 days * 24 hours / 8 hours = 21 observations
        uint256 wethLastObsTime_ = argData.readUint(".wethLastObsTime");
        uint256[] memory wethObs_ = argData.readUintArray(".wethObs"); // 7 days * 24 hours / 8 hours = 21 observations

        // 1. Configure DAI price feed and moving average data on PRICE
        // - Uses the Chainlink price feed with the standard observation window
        // - Uses the Uniswap V3 pool TWAP with the configured observation window
        // - Configures PRICE to track a moving average
        // - The price will be the average of the above three
        {
            PRICEv2.Component[] memory daiFeeds = new PRICEv2.Component[](2);
            {
                daiFeeds[0] = PRICEv2.Component(
                    toSubKeycode("PRICE.CHAINLINK"),
                    ChainlinkPriceFeeds.getOneFeedPrice.selector,
                    abi.encode(
                        ChainlinkPriceFeeds.OneFeedParams(
                            AggregatorV2V3Interface(daiUsdPriceFeed),
                            DEFAULT_TWAP_OBSERVATION_WINDOW
                        )
                    )
                );
                daiFeeds[1] = PRICEv2.Component(
                    toSubKeycode("PRICE.UNIV3"),
                    UniswapV3Price.getTokenTWAP.selector,
                    abi.encode(
                        UniswapV3Price.UniswapV3Params({
                            pool: IUniswapV3Pool(daiUsdcUniV3Pool),
                            observationWindowSeconds: twapObservationWindow, // This is shorter, as it is compared against reserves
                            maxDeviationBps: twapMaxDeviationBps
                        })
                    )
                );
            }

            console2.log("Adding DAI price feed to PRICE");
            addToBatch(
                priceConfigV2,
                abi.encodeWithSelector(
                    PriceConfigV2.addAssetPrice.selector,
                    dai,
                    true, // store moving average
                    true, // use the moving average as part of price strategy
                    DEFAULT_TWAP_OBSERVATION_WINDOW, // moving average window
                    daiLastObsTime_,
                    daiObs_,
                    PRICEv2.Component(
                        toSubKeycode("PRICE.SIMPLESTRATEGY"),
                        SimplePriceFeedStrategy.getAveragePrice.selector,
                        abi.encode(0)
                    ),
                    daiFeeds
                )
            );
        }

        // 2. Configure sDAI price feed and moving average data on PRICE
        // - Uses the DAI price to determine the sDAI price
        {
            uint256[] memory sdaiObs_ = new uint256[](0);
            PRICEv2.Component[] memory sdaiFeeds = new PRICEv2.Component[](1);
            sdaiFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.ERC4626"),
                ERC4626Price.getPriceFromUnderlying.selector,
                abi.encode(0)
            );
            console2.log("Adding sDAI price feed to PRICE");
            addToBatch(
                priceConfigV2,
                abi.encodeWithSelector(
                    PriceConfigV2.addAssetPrice.selector,
                    sdai,
                    false, // don't store moving average
                    false, // don't use the moving average as part of price strategy
                    0, // 0 day moving average
                    0,
                    sdaiObs_,
                    PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                    sdaiFeeds
                )
            );
        }

        // 3. Configure WETH price feed and moving average data on PRICE
        // - Uses the Chainlink price feed with the standard observation window
        // - Uses the Uniswap V3 pool TWAP with the configured observation window
        // - Configures PRICE to track a moving average
        // - The price will be the average of the above three
        {
            PRICEv2.Component[] memory wethFeeds = new PRICEv2.Component[](2);
            wethFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams(
                        AggregatorV2V3Interface(ethUsdPriceFeed),
                        DEFAULT_TWAP_OBSERVATION_WINDOW
                    )
                )
            );
            wethFeeds[1] = PRICEv2.Component(
                toSubKeycode("PRICE.UNIV3"),
                UniswapV3Price.getTokenTWAP.selector,
                abi.encode(
                    UniswapV3Price.UniswapV3Params({
                        pool: IUniswapV3Pool(wethUsdcUniV3Pool),
                        observationWindowSeconds: twapObservationWindow, // This is shorter, as it is compared against reserves
                        maxDeviationBps: twapMaxDeviationBps
                    })
                )
            );
            console2.log("Adding WETH price feed to PRICE");
            addToBatch(
                priceConfigV2,
                abi.encodeWithSelector(
                    PriceConfigV2.addAssetPrice.selector,
                    weth,
                    true, // store moving average
                    true, // use the moving average as part of price strategy
                    DEFAULT_TWAP_OBSERVATION_WINDOW, // moving average
                    wethLastObsTime_,
                    wethObs_,
                    PRICEv2.Component(
                        toSubKeycode("PRICE.SIMPLESTRATEGY"),
                        SimplePriceFeedStrategy.getAveragePrice.selector,
                        abi.encode(0)
                    ),
                    wethFeeds
                )
            );
        }

        // 4. Configure veFXS price feed and moving average data on PRICE
        // - Uses the Chainlink price feed with the standard observation window
        {
            uint256[] memory veFXSObs_ = new uint256[](0);
            PRICEv2.Component[] memory veFXSFeeds = new PRICEv2.Component[](1);
            veFXSFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams(
                        AggregatorV2V3Interface(fxsUsdPriceFeed),
                        DEFAULT_TWAP_OBSERVATION_WINDOW
                    )
                )
            );
            console2.log("Adding veFXS price feed to PRICE");
            addToBatch(
                priceConfigV2,
                abi.encodeWithSelector(
                    PriceConfigV2.addAssetPrice.selector,
                    veFXS,
                    false, // don't store moving average
                    false, // don't use the moving average as part of price strategy
                    0, // moving average
                    0,
                    veFXSObs_,
                    PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                    veFXSFeeds
                )
            );
        }

        // 5. Configure FXS price feed and moving average data on PRICE
        // - Uses the Chainlink price feed with the standard observation window
        {
            uint256[] memory fxsObs_ = new uint256[](0);
            PRICEv2.Component[] memory fxsFeeds = new PRICEv2.Component[](1);
            fxsFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams(
                        AggregatorV2V3Interface(fxsUsdPriceFeed),
                        DEFAULT_TWAP_OBSERVATION_WINDOW
                    )
                )
            );
            console2.log("Adding FXS price feed to PRICE");
            addToBatch(
                priceConfigV2,
                abi.encodeWithSelector(
                    PriceConfigV2.addAssetPrice.selector,
                    fxs,
                    false, // don't store moving average
                    false, // don't use the moving average as part of price strategy
                    0, // moving average
                    0,
                    fxsObs_,
                    PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                    fxsFeeds
                )
            );
        }

        // 6. Configure USDC price feed and moving average data on PRICE
        // - Uses the Chainlink price feed with the standard observation window
        // - Configures PRICE to track a moving average
        // - The price will be the average of the above two
        {
            PRICEv2.Component[] memory usdcFeeds = new PRICEv2.Component[](1);
            usdcFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.CHAINLINK"),
                ChainlinkPriceFeeds.getOneFeedPrice.selector,
                abi.encode(
                    ChainlinkPriceFeeds.OneFeedParams(
                        AggregatorV2V3Interface(usdcUsdPriceFeed),
                        DEFAULT_TWAP_OBSERVATION_WINDOW
                    )
                )
            );
            console2.log("Adding USDC price feed to PRICE");
            addToBatch(
                priceConfigV2,
                abi.encodeWithSelector(
                    PriceConfigV2.addAssetPrice.selector,
                    usdc,
                    true, // store moving average
                    true, // use the moving average as part of price strategy
                    DEFAULT_TWAP_OBSERVATION_WINDOW, // moving average
                    usdcLastObsTime_,
                    usdcObs_,
                    PRICEv2.Component(
                        toSubKeycode("PRICE.SIMPLESTRATEGY"),
                        SimplePriceFeedStrategy.getAveragePrice.selector,
                        abi.encode(0)
                    ),
                    usdcFeeds
                )
            );
        }

        // 7. Configure OHM on PRICE
        // - Uses a TWAP from the Uniswap V3 pool with the configured observation window
        {
            PRICEv2.Component[] memory ohmFeeds = new PRICEv2.Component[](1);
            ohmFeeds[0] = PRICEv2.Component(
                toSubKeycode("PRICE.UNIV3"),
                UniswapV3Price.getTokenTWAP.selector,
                abi.encode(
                    UniswapV3Price.UniswapV3Params({
                        pool: IUniswapV3Pool(ohmWethUniV3Pool),
                        observationWindowSeconds: twapObservationWindow, // This is shorter, as it is compared against reserves
                        maxDeviationBps: twapMaxDeviationBps
                    })
                )
            );

            console2.log("Adding OHM price feed to PRICE");
            addToBatch(
                priceConfigV2,
                abi.encodeWithSelector(
                    PriceConfigV2.addAssetPrice.selector,
                    ohm,
                    false, // store moving average
                    false, // use the moving average as part of price strategy
                    0, // moving average
                    0,
                    new uint256[](0),
                    PRICEv2.Component(toSubKeycode(bytes20(0)), bytes4(0), abi.encode(0)), // no price strategy
                    ohmFeeds
                )
            );
        }
```
