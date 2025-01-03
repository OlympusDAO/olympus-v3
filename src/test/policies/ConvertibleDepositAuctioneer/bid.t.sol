// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";

contract ConvertibleDepositAuctioneerBidTest is ConvertibleDepositAuctioneerTest {
    // when the contract is deactivated
    //  [ ] it reverts
    // when the contract has not been initialized
    //  [ ] it reverts
    // when the caller has not approved CDEPO to spend the bid token
    //  [ ] it reverts
    // when the "cd_auctioneer" role is not granted to the auctioneer contract
    //  [ ] it reverts
    // when the bid amount converted is 0
    //  [ ] it reverts
    // when the tick price is below the minimum price
    //  [ ] it does not go below the minimum price
    // when the bid is the first bid of the day
    //  when the convertible amount of OHM will exceed the day target
    //   [ ] it returns the amount of OHM that can be converted at the current tick price to fill but not exceed the target
    //  [ ] it resets the day's deposit and converted balances
    //  [ ] it updates the day's deposit balance
    //  [ ] it updates the day's converted balance
    //  [ ] it sets the lastUpdate to the current block timestamp
    // when the bid is not the first bid of the day
    //  when the convertible amount of OHM will exceed the day target
    //   [ ] it returns the amount of OHM that can be converted at the current tick price to fill but not exceed the target
    //  [ ] it does not reset the day's deposit and converted balances
    //  [ ] it updates the day's deposit balance
    //  [ ] it updates the day's converted balance
    //  [ ] it sets the lastUpdate to the current block timestamp
    // when the bid amount converted is less than the remaining tick capacity
    //  when the calculated deposit amount is 0
    //   [ ] it completes bidding and leaves a remainder of the bid token
    //  when the convertible amount of OHM will exceed the day target
    //   [ ] it returns the amount of OHM that can be converted at the current tick price to fill but not exceed the target
    //  [ ] it returns the amount of OHM that can be converted
    //  [ ] it issues CD terms with the current tick price and time to expiry
    //  [ ] it updates the day's deposit balance
    //  [ ] it updates the day's converted balance
    //  [ ] it deducts the converted amount from the tick capacity
    //  [ ] it does not update the tick price
    //  [ ] it sets the lastUpdate to the current block timestamp
    // when the bid amount converted is equal to the remaining tick capacity
    //  when the convertible amount of OHM will exceed the day target
    //   [ ] it returns the amount of OHM that can be converted at the current tick price to fill but not exceed the target
    //  when the tick step is > 1e18
    //   [ ] it returns the amount of OHM that can be converted using the current tick price
    //   [ ] it issues CD terms with the current tick price and time to expiry
    //   [ ] it updates the day's deposit balance
    //   [ ] it updates the day's converted balance
    //   [ ] it updates the tick capacity to the tick size
    //   [ ] it updates the tick price to be higher than the current tick price
    //   [ ] it sets the lastUpdate to the current block timestamp
    //  when the tick step is < 1e18
    //   [ ] it returns the amount of OHM that can be converted using the current tick price
    //   [ ] it issues CD terms with the current tick price and time to expiry
    //   [ ] it updates the day's deposit balance
    //   [ ] it updates the day's converted balance
    //   [ ] it updates the tick capacity to the tick size
    //   [ ] it updates the tick price to be lower than the current tick price
    //   [ ] it sets the lastUpdate to the current block timestamp
    //  when the tick step is = 1e18
    //   [ ] it returns the amount of OHM that can be converted using the current tick price
    //   [ ] it issues CD terms with the current tick price and time to expiry
    //   [ ] it updates the day's deposit balance
    //   [ ] it updates the day's converted balance
    //   [ ] it updates the tick capacity to the tick size
    //   [ ] the tick price is unchanged
    //   [ ] it sets the lastUpdate to the current block timestamp
    // when the bid amount converted is greater than the remaining tick capacity
    //  when the convertible amount of OHM will exceed the day target
    //   [ ] it returns the amount of OHM that can be converted at the current tick price to fill but not exceed the target
    //  when the tick step is > 1e18
    //   [ ] it returns the amount of OHM that can be converted at multiple prices
    //   [ ] it issues CD terms with the average price and time to expiry
    //   [ ] it updates the day's deposit balance
    //   [ ] it updates the day's converted balance
    //   [ ] it updates the tick capacity to the tick size minus the converted amount at the new tick price
    //   [ ] it updates the new tick price to be higher than the current tick price
    //   [ ] it sets the lastUpdate to the current block timestamp
    //  when the tick step is < 1e18
    //   [ ] it returns the amount of OHM that can be converted at multiple prices
    //   [ ] it issues CD terms with the average price and time to expiry
    //   [ ] it updates the day's deposit balance
    //   [ ] it updates the day's converted balance
    //   [ ] it updates the tick capacity to the tick size minus the converted amount at the new tick price
    //   [ ] it updates the new tick price to be lower than the current tick price
    //   [ ] it sets the lastUpdate to the current block timestamp
    //  when the tick step is = 1e18
    //   [ ] it returns the amount of OHM that can be converted at multiple prices
    //   [ ] it issues CD terms with the average price and time to expiry
    //   [ ] it updates the day's deposit balance
    //   [ ] it updates the day's converted balance
    //   [ ] it updates the tick capacity to the tick size minus the converted amount at the new tick price
    //   [ ] the tick price is unchanged
    //   [ ] it sets the lastUpdate to the current block timestamp
}
