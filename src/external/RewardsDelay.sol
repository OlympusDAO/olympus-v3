// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;

// // interface IGDAO is IERC20 {
// //     function mint(address account_, uint256 amount_) external;
// //     function burn(uint256 amount) external;
// //     function burnFrom(address account_, uint256 amount_) external;
// // }


// contract RewardsDelay is Ownable {
//     struct UserInfo {
//         uint256 amount; // How many LP tokens the user has provided.
//         uint256 rewardDebt; // Reward debt. See explanation below.
//         uint256 lockEndedTimestamp;
//         //
//         //   pending reward = (user.amount * pool.accRewardPerShare) - user.rewardDebt
//         //
//         // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
//         //   1. The pool's `accRewardPerShare` (and `lastRewardBlock`) gets updated.
//         //   2. User receives the pending reward sent to his/her address.
//         //   3. User's `amount` gets updated.
//         //   4. User's `rewardDebt` gets updated.
//     }

//     struct PoolInfo {
//         IERC20 lpToken; // Address of LP token contract.
//         uint256 allocPoint; // How many allocation points assigned to this pool. Rewards to distribute per block.
//         uint256 lastRewardBlock; // Last block number that Rewards distribution occurs.
//         uint256 accRewardPerShare; // Accumulated Rewards per share.
//     }
// }