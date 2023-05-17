// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import {ReaperStrategyGranary} from "./ReaperStrategyGranary.sol";
import {VeloSolidMixin} from "./mixins/VeloSolidMixin.sol";
import {BalMixin} from "./mixins/BalMixin.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

/**
 * @dev This strategy will deposit and leverage a token on Granary to maximize yield
 */
contract ReaperStrategyGranaryV2 is ReaperStrategyGranary, VeloSolidMixin, BalMixin {
    address public constant BEET_VAULT = 0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce;
    address public constant VELO_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    enum Exchange {
        Velodrome,
        Beethoven,
        UniV3,
        UniV2
    }

    struct Step {
        Exchange dex;
        address start;
        address end;
    }

    Step[] public stepsV2;

    function _balVault() internal view override returns (address) {
        return BEET_VAULT;
    }

    function updateVeloSwapPath(address _tokenIn, address _tokenOut, address[] calldata _path) external override {
        _atLeastRole(STRATEGIST);
        _updateVeloSwapPath(_tokenIn, _tokenOut, _path);
    }

    function updateBalSwapPoolID(address _tokenIn, address _tokenOut, bytes32 _poolID) external override {
        _atLeastRole(STRATEGIST);
        _updateBalSwapPoolID(_tokenIn, _tokenOut, _poolID);
    }

    /**
     * Only {ADMIN} or higher roles may set the array
     * of steps executed as part of harvest.
     */
    function setHarvestSteps(Step[] calldata _newSteps) external {
        _atLeastRole(ADMIN);
        delete stepsV2;

        uint256 numSteps = _newSteps.length;
        for (uint256 i = 0; i < numSteps; i++) {
            Step memory step = _newSteps[i];
            require(step.start != address(0));
            require(step.end != address(0));
            stepsV2.push(step);
        }
    }

    /**
     * @dev Core function of the strat, in charge of collecting and swapping rewards
     *      to produce more want.
     * @notice Assumes the deposit will take care of resupplying excess want.
     */
    function _harvestCore(uint256 _debt) internal virtual override returns (int256 roi, uint256 repayment) {
        _claimRewards();
        uint256 numSteps = stepsV2.length;
        for (uint256 i = 0; i < numSteps; i++) {
            Step storage step = stepsV2[i];
            IERC20Upgradeable startToken = IERC20Upgradeable(step.start);
            uint256 amount = startToken.balanceOf(address(this));
            if (amount == 0) {
                continue;
            }

            if (step.dex == Exchange.Velodrome) {
                _swapVelo(step.start, step.end, amount, 0, VELO_ROUTER);
            } else if (step.dex == Exchange.Beethoven) {
                _swapBal(step.start, step.end, amount, 0);
            } else if (step.dex == Exchange.UniV2) {
                address[] memory path = new address[](2);
                path[0] = step.start;
                path[0] = step.end;
                _swapUni(amount, path, UNI_ROUTER);
            }
        }

        uint256 allocated = IVault(vault).strategies(address(this)).allocated;
        uint256 totalAssets = balanceOf();
        uint256 toFree = MathUpgradeable.min(_debt, totalAssets);

        if (totalAssets > allocated) {
            uint256 profit = totalAssets - allocated;
            toFree += profit;
            roi = int256(profit);
        } else if (totalAssets < allocated) {
            roi = -int256(allocated - totalAssets);
        }

        (uint256 amountFreed, uint256 loss) = _liquidatePosition(toFree);
        repayment = MathUpgradeable.min(_debt, amountFreed);
        roi -= int256(loss);
    }
}
