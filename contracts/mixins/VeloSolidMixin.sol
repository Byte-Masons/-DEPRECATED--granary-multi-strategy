// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IVeloRouter.sol";
import "../interfaces/IVeloPair.sol";
import "../interfaces/ISwapErrors.sol";
import "../libraries/Babylonian.sol";

abstract contract VeloSolidMixin is ISwapErrors {
    using SafeERC20 for IERC20;

    /// @dev tokenA => (tokenB => veloSwapPath config): returns best path to swap
    ///         tokenA to tokenB
    mapping(address => mapping(address => address[])) public veloSwapPaths;

    /// @dev Helper function to swap {_from} to {_to} given an {_amount}.
    function _swapVelo(address _from, address _to, uint256 _amount, uint256 _minAmountOut, address _router) internal {
        if (_from == _to || _amount == 0) {
            return;
        }
        address[] storage path = veloSwapPaths[_from][_to];
        require(path.length >= 2, "Missing path for swap");

        uint256 output;
        bool useStable;
        IVeloRouter router = IVeloRouter(_router);
        IVeloRouter.route[] memory routes = new IVeloRouter.route[](path.length - 1);
        uint256 prevRouteOutput = _amount;

        for (uint256 i = 0; i < routes.length; i++) {
            try router.getAmountOut(prevRouteOutput, path[i], path[i + 1]) returns (
                uint256 tmpOutput, bool tmpUseStable
            ) {
                output = tmpOutput;
                useStable = tmpUseStable;
            } catch {}

            if (output == 0) {
                emit GetAmountsOutFailed(_router, prevRouteOutput, path[i], path[i + 1]);
                return;
            }

            routes[i] = IVeloRouter.route({from: path[i], to: path[i + 1], stable: useStable});
            prevRouteOutput = output;
            output = 0;
        }

        IERC20(_from).safeIncreaseAllowance(_router, _amount);
        try router.swapExactTokensForTokens(_amount, _minAmountOut, routes, address(this), block.timestamp) {}
        catch {
            emit SwapFailed(_router, _amount, _minAmountOut, routes[0].from, routes[routes.length - 1].to);
        }
    }

    function _getSwapAmountVelo(IVeloPair pair, uint256 investmentA, uint256 reserveA, uint256 reserveB, address tokenA)
        internal
        view
        returns (uint256 swapAmount)
    {
        uint256 halfInvestment = investmentA / 2;
        uint256 numerator = pair.getAmountOut(halfInvestment, tokenA);
        uint256 denominator = _quoteLiquidity(halfInvestment, reserveA + halfInvestment, reserveB - numerator);
        swapAmount = investmentA - Babylonian.sqrt((halfInvestment * halfInvestment * numerator) / denominator);
    }

    // Copied from Velodrome's Router since it's an internal function in there
    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function _quoteLiquidity(uint256 amountA, uint256 reserveA, uint256 reserveB)
        internal
        pure
        returns (uint256 amountB)
    {
        require(amountA > 0, "Router: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "Router: INSUFFICIENT_LIQUIDITY");
        amountB = (amountA * reserveB) / reserveA;
    }

    /// @dev Update {SwapPath} for a specified pair of tokens.
    function _updateVeloSwapPath(address _tokenIn, address _tokenOut, address[] calldata _path) internal {
        require(
            _tokenIn != _tokenOut && _path.length >= 2 && _path[0] == _tokenIn && _path[_path.length - 1] == _tokenOut
        );
        veloSwapPaths[_tokenIn][_tokenOut] = _path;
    }

    // Be sure to permission this in implementation
    function updateVeloSwapPath(address _tokenIn, address _tokenOut, address[] calldata _path) external virtual;
}
