// SPDX-License-Identifier: agpl-3.0

pragma solidity ^0.8.0;

import "./IMultiFeeDistribution.sol";

interface IOnwardIncentivesController {
    function handleAction(
        address _token,
        address _user,
        uint256 _balance,
        uint256 _totalSupply
    ) external;
}

interface IChefIncentivesController {
    // Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    // Info about token emissions for a given time period.
    struct EmissionPoint {
        uint128 startTimeOffset;
        uint128 rewardsPerSecond;
    }

    // Info of each pool.
    struct PoolInfo {
        uint256 totalSupply;
        uint256 allocPoint; // How many allocation points assigned to this pool.
        uint256 lastRewardTime; // Last second that reward distribution occurs.
        uint256 accRewardPerShare; // Accumulated rewards per share, times 1e12. See below.
        IOnwardIncentivesController onwardIncentives;
    }

    function addPool(address _token, uint256 _allocPoint) external;

    function batchUpdateAllocPoint(address[] calldata _tokens, uint256[] calldata _allocPoints) external;

    function claim(address _user, address[] calldata _tokens) external;

    function claimReceiver(address) external view returns (address);

    function claimableReward(address _user, address[] calldata _tokens) external view returns (uint256[] memory);

    function emissionSchedule(uint256) external view returns (EmissionPoint memory);

    function handleAction(
        address _user,
        uint256 _balance,
        uint256 _totalSupply
    ) external;

    function maxMintableTokens() external view returns (uint256);

    function mintedTokens() external view returns (uint256);

    function owner() external view returns (address);

    function poolConfigurator() external view returns (address);

    function poolInfo(address) external view returns (PoolInfo memory);

    function poolLength() external view returns (uint256);

    function registeredTokens(uint256) external view returns (address);

    function renounceOwnership() external;

    function rewardMinter() external view returns (IMultiFeeDistribution);

    function rewardsPerSecond() external view returns (uint256);

    function setClaimReceiver(address _user, address _receiver) external;

    function setOnwardIncentives(address _token, IOnwardIncentivesController _incentives) external;

    function start() external;

    function startTime() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);

    function transferOwnership(address newOwner) external;

    function userInfo(address, address) external view returns (UserInfo memory);
}
