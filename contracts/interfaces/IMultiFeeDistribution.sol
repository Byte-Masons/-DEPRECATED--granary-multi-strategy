// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IMultiFeeDistribution {
    /* ========== STATE VARIABLES ========== */

    struct Reward {
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        // tracks already-added balances to handle accrued interest in aToken rewards
        // for the stakingToken this value is unused and will always be 0
        uint256 balance;
    }
    struct Balances {
        uint256 total;
        uint256 unlocked;
        uint256 locked;
        uint256 earned;
    }
    struct LockedBalance {
        uint256 amount;
        uint256 unlockTime;
    }
    struct RewardData {
        address token;
        uint256 amount;
    }

    /* ========== VIEWS ========== */

    function lastTimeRewardApplicable(address _rewardsToken) external view returns (uint256);

    function rewardPerToken(address _rewardsToken) external view returns (uint256);

    function getRewardForDuration(address _rewardsToken) external view returns (uint256);

    // Address and claimable amount of all reward tokens for the given account
    function claimableRewards(address account) external view returns (RewardData[] memory rewards);

    // Total balance of an account, including unlocked, locked and earned tokens
    function totalBalance(address user) external view returns (uint256 amount);

    // Total withdrawable balance for an account to which no penalty is applied
    function unlockedBalance(address user) external view returns (uint256 amount);

    // Information on the "earned" balances of a user
    // Earned balances may be withdrawn immediately for a 50% penalty
    function earnedBalances(address user) external view returns (uint256 total, LockedBalance[] memory earningsData);

    // Information on a user's locked balances
    function lockedBalances(address user)
        external
        view
        returns (
            uint256 total,
            uint256 unlockable,
            uint256 locked,
            LockedBalance[] memory lockData
        );

    // Final balance received and penalty balance paid by user upon calling exit
    function withdrawableBalance(address user) external view returns (uint256 amount, uint256 penaltyAmount);

    /* ========== MUTATIVE FUNCTIONS ========== */

    // Stake tokens to receive rewards
    // Locked tokens cannot be withdrawn for lockDuration and are eligible to receive stakingReward rewards
    function stake(uint256 amount, bool lock) external;

    // Mint new tokens
    // Minted tokens receive rewards normally but incur a 50% penalty when
    // withdrawn before lockDuration has passed.
    function mint(
        address user,
        uint256 amount,
        bool withPenalty
    ) external;

    // Withdraw staked tokens
    // First withdraws unlocked tokens, then earned tokens. Withdrawing earned tokens
    // incurs a 50% penalty which is distributed based on locked balances.
    function withdraw(uint256 amount) external;

    // Claim all pending staking rewards
    function getReward() external;

    // Withdraw full unlocked balance and claim pending rewards
    function exit() external;

    // Withdraw all currently locked tokens where the unlock time has passed
    function withdrawExpiredLocks() external;
}
