// SPDX-License-Identifier: agpl-3.0

pragma solidity ^0.8.0;

library ReaperMathUtils {
    /**
     * @notice For doing an unchecked increment of an index for gas optimization purposes
     * @param _i - The number to increment
     * @return The incremented number
     */
    function uncheckedInc(uint256 _i) internal pure returns (uint256) {
        unchecked {
            return _i + 1;
        }
    }
}