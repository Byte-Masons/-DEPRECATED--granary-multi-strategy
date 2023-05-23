// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface ISwapErrors {
    event SwapFailed(address router, uint256 amount, uint256 minAmountOut, address from, address to);
    event GetAmountsOutFailed(address router, uint256 amount, address from, address to);
}
