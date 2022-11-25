// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../interfaces/IUniswapV2Router02.sol";
import "../libraries/Babylonian.sol";
import "../libraries/SafeERC20Minimal.sol";

abstract contract UniMixin {
    using SafeERC20Minimal for IERC20Minimal;

    /**
     * @dev Helper function to swap tokens given an {_amount}, swap {_path}, and {_router}.
     */
    function _swapUni(uint256 _amount, address[] memory _path, address _router) internal {
        if (_path.length < 2 || _amount == 0) {
            return;
        }

        uint256 amountOut = IUniswapV2Router02(_router).getAmountsOut(_amount, _path)[_path.length - 1];
        if (amountOut == 0) {
            return;
        }

        IERC20Minimal(_path[0])._safeIncreaseAllowance(_router, _amount);
        IUniswapV2Router02(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount, 0, _path, address(this), block.timestamp
        );
    }

    /**
     * @dev Core harvest function. Adds more liquidity using {lpToken0} and {lpToken1}.
     */
    function _addLiquidityUni(address _lpToken0, address _lpToken1, address _router) internal {
        uint256 lp0Bal = IERC20Minimal(_lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20Minimal(_lpToken1).balanceOf(address(this));

        if (lp0Bal != 0 && lp1Bal != 0) {
            IERC20Minimal(_lpToken0)._safeIncreaseAllowance(_router, lp0Bal);
            IERC20Minimal(_lpToken1)._safeIncreaseAllowance(_router, lp1Bal);
            IUniswapV2Router02(_router).addLiquidity(
                _lpToken0, _lpToken1, lp0Bal, lp1Bal, 0, 0, address(this), block.timestamp
            );
        }
    }

    function _getSwapAmountUni(uint256 _investmentA, uint256 _reserveA, uint256 _reserveB, address _router)
        internal
        pure
        returns (uint256 swapAmount)
    {
        uint256 halfInvestment = _investmentA / 2;
        uint256 nominator = IUniswapV2Router02(_router).getAmountOut(halfInvestment, _reserveA, _reserveB);
        uint256 denominator =
            IUniswapV2Router02(_router).quote(halfInvestment, _reserveA + halfInvestment, _reserveB - nominator);
        swapAmount = _investmentA - (Babylonian.sqrt(halfInvestment * halfInvestment * nominator / denominator));
    }
}
