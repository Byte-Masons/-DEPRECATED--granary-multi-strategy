// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

// Common interface to be implemented by strategies that can use leverage
interface ILeverageable {
    /**
     * @dev This function is designed to be called by a keeper to set the desired
     *      leverage params within the strategy. The units of the parameters may vary
     *      from strategy to strategy: some strategies may use basis points, others may
     *      use ether precision. Moreover, not all parameters will apply to all strategies.
     *      Strategies are free to ignore parameters they don't care about.
     * @param targetLeverage the leverage/ltv to target
     * @param maxLeverage the maximum tolerable leverage/ltv
     * @param triggerHarvest whether to call the harvest function at the end
     */
    function setLeverage(
        uint256 targetLeverage,
        uint256 maxLeverage,
        bool triggerHarvest
    ) external;
}
