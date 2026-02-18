// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {PriceV2BaseTest} from "./PriceV2BaseTest.sol";

contract PriceV2UpdateAssetTest is PriceV2BaseTest {
    // given the caller is not permissioned
    //  [ ] it reverts - not permissioned
    // given the asset is not configured
    //  [ ] it reverts - not approved
    // when the price feed configuration is being updated
    //  when the number of price feeds is 0
    //   [ ] it reverts - there must be price feeds
    //  when the submodule of a price feed is not installed
    //   [ ] it reverts
    //  when the number of price feeds is 1
    //   when the moving average configuration is not being updated
    //    given the moving average is used
    //     when the strategy configuration is not being updated
    //      given the existing strategy configuration is empty
    //       not possible
    //      given the existing strategy configuration is not empty
    //       [ ] it replaces the price feed configuration
    //     when the strategy configuration is being updated
    //      when the updated strategy configuration is empty
    //       [ ] it reverts - strategy required
    //      when the updated strategy configuration is not empty
    //       [ ] it replaces the price feed configuration
    //       [ ] it replaces the strategy configuration
    //       [ ] it emits an AssetPriceFeedsUpdated event
    //       [ ] it emits an AssetStrategyUpdated event
    //    given the moving average is not used
    //     when the strategy configuration is not being updated
    //      given the existing strategy configuration is empty
    //       [ ] it replaces the price feed configuration
    //       [ ] it emits an AssetPriceFeedsUpdated event
    //      given the existing strategy configuration is not empty
    //       not possible
    //     when the strategy configuration is being updated
    //      when the updated strategy configuration is empty
    //       [ ] it replaces the price feed configuration
    //       [ ] it replaces the strategy configuration
    //       [ ] it emits an AssetPriceFeedsUpdated event
    //       [ ] it emits an AssetStrategyUpdated event
    //      when the updated strategy configuration is not empty
    //       [ ] it reverts - strategy not supported
    //   when the moving average configuration is being updated
    //    when the moving average is used
    //     when the strategy configuration is not being updated
    //      given the existing strategy configuration is empty
    //       [ ] it reverts - strategy required
    //      given the existing strategy configuration is not empty
    //       [ ] it replaces the price feed configuration
    //       [ ] it replaces the moving average configuration
    //       [ ] it emits an AssetPriceFeedsUpdated event
    //       [ ] it emits an AssetMovingAverageUpdated event
    //     when the strategy configuration is being updated
    //      when the updated strategy configuration is empty
    //       [ ] it reverts - strategy required
    //      when the updated strategy configuration is not empty
    //       [ ] it replaces the price feed configuration
    //       [ ] it replaces the moving average configuration
    //       [ ] it replaces the strategy configuration
    //       [ ] it emits an AssetPriceFeedsUpdated event
    //       [ ] it emits an AssetStrategyUpdated event
    //       [ ] it emits an AssetMovingAverageUpdated event
    //    when the moving average is not used
    //     when the strategy configuration is not being updated
    //      given the existing strategy configuration is empty
    //       [ ] it replaces the price feed configuration
    //       [ ] it replaces the moving average configuration
    //       [ ] it emits an AssetPriceFeedsUpdated event
    //       [ ] it emits an AssetMovingAverageUpdated event
    //      given the existing strategy configuration is not empty
    //       [ ] it reverts - strategy not supported
    //     when the strategy configuration is being updated
    //      when the updated strategy configuration is empty
    //       [ ] it replaces the price feed configuration
    //       [ ] it replaces the moving average configuration
    //       [ ] it replaces the strategy configuration
    //       [ ] it emits an AssetPriceFeedsUpdated event
    //       [ ] it emits an AssetStrategyUpdated event
    //       [ ] it emits an AssetMovingAverageUpdated event
    //      when the updated strategy configuration is not empty
    //       [ ] it reverts - strategy not supported
    //  when the number of price feeds is > 1
    //   when there are duplicate price feeds
    //    [ ] it reverts - duplicate price feed
    //   when the strategy configuration is not being updated
    //    given the existing strategy configuration is empty
    //     [ ] it reverts - strategy required
    //    given the existing strategy configuration is not empty
    //     [ ] it replaces the price feed configuration
    //     [ ] it emits an AssetPriceFeedsUpdated event
    //   when the strategy configuration is being updated
    //    when the updated strategy configuration is empty
    //     [ ] it reverts - strategy required
    //    when the updated strategy configuration is not empty
    //     [ ] it replaces the price feed configuration
    //     [ ] it replaces the strategy configuration
    //     [ ] it emits an AssetPriceFeedsUpdated event
    //     [ ] it emits an AssetStrategyUpdated event
    // when the asset strategy configuration is being updated
    //  given the strategy submodule is not installed
    //   [ ] it reverts
    //  when the submodule call reverts
    //   [ ] it reverts
    //  when the moving average configuration is being updated
    //   when useMovingAverage is true
    //    when the updated strategy configuration is empty
    //     [ ] it reverts - strategy required
    //    when the updated strategy configuration is not empty
    //     [ ] it replaces the strategy configuration
    //     [ ] it replaces the moving average configuration
    //     [ ] it emits an AssetStrategyUpdated event
    //     [ ] it emits an AssetMovingAverageUpdated event
    //   when useMovingAverage is false
    //    when the updated strategy configuration is empty
    //     given the number of price feeds is 1
    //      [ ] it replaces the strategy configuration
    //      [ ] it replaces the moving average configuration
    //      [ ] it emits an AssetStrategyUpdated event
    //      [ ] it emits an AssetMovingAverageUpdated event
    //     given the number of price feeds is > 1
    //      [ ] it reverts - strategy required
    //  when the moving average configuration is not being updated
    //   given useMovingAverage is true
    //    when the updated strategy configuration is empty
    //     [ ] it reverts - strategy required
    //    when the updated strategy configuration is not empty
    //     [ ] it replaces the strategy configuration
    //     [ ] it emits an AssetStrategyUpdated event
    //   given useMovingAverage is false
    //    when the updated strategy configuration is empty
    //     given the number of price feeds is 1
    //      [ ] it replaces the strategy configuration
    //      [ ] it emits an AssetStrategyUpdated event
    //     given the number of price feeds is > 1
    //      [ ] it reverts - strategy required
    // when the moving average configuration is being updated
    //  when the last observation time is in the future
    //   [ ] it reverts - invalid observation time
    //  when storeMovingAverage is true
    //   when the moving average duration is zero
    //    [ ] it reverts - invalid moving average duration
    //   when the moving average duration is not a multiple of the observation frequency
    //    [ ] it reverts - invalid moving average duration
    //   when the number of observations is not equal to duration / frequency
    //    [ ] it reverts - invalid observation count
    //   when there is a zero value observation
    //    [ ] it reverts - zero observation
    //   [ ] it replaces the moving average configuration
    //   [ ] it emits an AssetMovingAverageUpdated event
    //  when storeMovingAverage is false
    //   when useMovingAverage is true
    //    [ ] it reverts - storeMovingAverage required
    //   when the number of observations is > 1
    //    [ ] it reverts - invalid observation count
    //   when the number of observations is 1
    //    when the is a zero value observation
    //     [ ] it reverts - zero observation
    //    [ ] it stores the observation as the last price
    //    [ ] it replaces the moving average configuration
    //    [ ] it emits an AssetMovingAverageUpdated event
    //   when the number of observations is 0
    //    [ ] it stores the current price as the last price
    //    [ ] it replaces the moving average configuration
    //    [ ] it emits an AssetMovingAverageUpdated event
    // when getCurrentPrice fails
    //  [ ] it reverts
    // when the price feeds, strategy and moving average are not being updated
    //  [ ] it reverts
}
