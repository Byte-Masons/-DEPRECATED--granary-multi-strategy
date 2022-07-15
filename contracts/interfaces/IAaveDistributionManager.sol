// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.11;
pragma experimental ABIEncoderV2;

import {DistributionTypes} from "../library/DistributionTypes.sol";

interface IAaveDistributionManager {
    event AssetConfigUpdated(address indexed asset, uint256 emission);
    event AssetIndexUpdated(address indexed asset, uint256 index);
    event UserIndexUpdated(address indexed user, address indexed asset, uint256 index);
    event DistributionEndUpdated(uint256 newDistributionEnd);

    /**
     * @dev Sets the end date for the distribution
     * @param distributionEnd The end date timestamp
     **/
    function setDistributionEnd(uint256 distributionEnd, address rewardToken) external;

    /**
     * @dev Gets the end date for the distribution
     * @return The end of the distribution
     **/
    function getDistributionEnd(address rewardToken) external view returns (uint256);

    /**
     * @dev for backwards compatibility with the previous DistributionManager used
     * @return The end of the distribution
     **/
    function DISTRIBUTION_END(address rewardToken) external view returns (uint256);

    /**
     * @dev Returns the data of an user on a distribution
     * @param user Address of the user
     * @param asset The address of the reference asset of the distribution
     * @return The new index
     **/
    function getUserAssetData(
        address user,
        address asset,
        address rewardToken
    ) external view returns (uint256);

    /**
     * @dev Returns the configuration of the distribution for a certain asset
     * @param asset The address of the reference asset of the distribution
     * @return The asset index, the emission per second and the last updated timestamp
     **/
    function getAssetData(address asset, address rewardToken)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );
}
