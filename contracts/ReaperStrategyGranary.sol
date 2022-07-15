// SPDX-License-Identifier: MIT

import "./abstract/ReaperBaseStrategyv4.sol";
import "./interfaces/IAToken.sol";
import "./interfaces/IAaveProtocolDataProvider.sol";
import "./interfaces/IFlashLoanReceiver.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/ILendingPoolAddressesProvider.sol";
import "./interfaces/IRewardsController.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {FixedPointMathLib} from "./library/FixedPointMathLib.sol";

pragma solidity 0.8.11;

/**
 * @dev This strategy will deposit and leverage a token on Granary to maximize yield
 */
contract ReaperStrategyGranary is ReaperBaseStrategyv4, IFlashLoanReceiver {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using FixedPointMathLib for uint256;

    // 3rd-party contract addresses
    address public constant UNI_ROUTER = address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);
    address public constant ADDRESSES_PROVIDER_ADDRESS = address(0x8b9D58E2Dc5e9b5275b62b1F30b3c0AC87138130);
    address public constant DATA_PROVIDER = address(0x3132870d08f736505FF13B19199be17629085072);
    address public constant REWARDER = address(0x7780E1A8321BD58BBc76594Db494c7Bfe8e87040);

    // this strategy's configurable tokens
    IAToken public gWant;

    uint256 public targetLtv; // in hundredths of percent, 8000 = 80%
    uint256 public maxDeleverageLoopIterations;

    /**
     * 0 - no flash loan in progress
     * 1 - deposit()-related flash loan in progress
     */
    uint256 private flashLoanStatus;
    uint256 private constant NO_FL_IN_PROGRESS = 0;
    uint256 private constant DEPOSIT_FL_IN_PROGRESS = 1;

    // Misc constants
    uint16 private constant LENDER_REFERRAL_CODE_NONE = 0;
    uint256 private constant INTEREST_RATE_MODE_VARIABLE = 2;
    uint256 private constant DELEVER_SAFETY_ZONE = 9990;
    uint256 private constant MAX_WITHDRAW_SLIPPAGE_TOLERANCE = 200;

    /**
     * @dev Tokens Used:
     * {WFTM} - Required for liquidity routing when doing swaps.
     * {USDC} - For charging fees
     * {rewardTokens} - Array containing gWant + corresponding variable debt token,
     *                          used for vesting any oustanding unvested Geist tokens.
     */
    address public constant WFTM = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public constant OATH = address(0x21Ada0D2aC28C3A5Fa3cD2eE30882dA8812279B6);
    address public constant STADER = address(0x412a13C109aC30f0dB80AD3Bd1DeFd5D0A6c0Ac6);
    address public constant USDC = address(0x04068DA6C83AFCFA0e13ba15A6696662335D5B75);
    address public GRAIN;
    address[] public rewardTokens;

    /**
     * @dev Paths used to swap tokens:
     * {wftmToWantPath} - to swap {WFTM} to {want}
     * {wftmToUsdcPath} - Path we take to get from {WFTM} into {USDC}.
     */
    address[] public wftmToWantPath;
    address[] public wftmToUsdcPath;
    address[] public oathToWftmPath;
    address[] public staderToUsdcPath;
    address[] public usdcToWftmPath;
    address[] public grainToUsdcPath;

    uint256 public maxLtv; // in hundredths of percent, 8000 = 80%
    uint256 public minLeverageAmount;
    uint256 public constant LTV_SAFETY_ZONE = 9800;
    bool public isOathRewardActive;
    bool public isStaderRewardActive;
    bool public isGrainRewardActive;

    /**
     * @dev Initializes the strategy. Sets parameters, saves routes, and gives allowances.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address[] memory _feeRemitters,
        address[] memory _strategists,
        address[] memory _multisigRoles,
        IAToken _gWant,
        uint256 _targetLtv,
        uint256 _maxLtv
    ) public initializer {
        gWant = _gWant;
        want = _gWant.UNDERLYING_ASSET_ADDRESS();
        __ReaperBaseStrategy_init(_vault, want, _feeRemitters, _strategists, _multisigRoles);
        maxDeleverageLoopIterations = 10;
        minLeverageAmount = 1000;
        wftmToUsdcPath = [WFTM, USDC];
        oathToWftmPath = [OATH, WFTM];
        staderToUsdcPath = [STADER, USDC];
        usdcToWftmPath = [USDC, WFTM];

        if (address(want) == WFTM) {
            wftmToWantPath = [WFTM];
        } else {
            wftmToWantPath = [WFTM, address(want)];
        }

        (, , address vToken) = IAaveProtocolDataProvider(DATA_PROVIDER).getReserveTokensAddresses(address(want));
        rewardTokens = [address(_gWant), vToken];

        _safeUpdateTargetLtv(_targetLtv, _maxLtv);
    }

    function _adjustPosition(uint256 _debt) internal override {
        if (emergencyExit) {
            return;
        }

        uint256 wantBalance = balanceOfWant();
        if (wantBalance > _debt) {
            uint256 toReinvest = wantBalance - _debt;
            _deposit(toReinvest);
        }
    }

    function _liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 liquidatedAmount, uint256 loss)
    {
        uint256 wantBal = balanceOfWant();
        if (wantBal < _amountNeeded) {
            _withdraw(_amountNeeded - wantBal);
            liquidatedAmount = balanceOfWant();
        } else {
            liquidatedAmount = _amountNeeded;
        }

        if (_amountNeeded > liquidatedAmount) {
            loss = _amountNeeded - liquidatedAmount;
        }
    }

    function _liquidateAllPositions() internal override returns (uint256 amountFreed) {
        _delever(type(uint256).max);
        _withdrawUnderlying(balanceOfPool());
        return balanceOfWant();
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     * @notice Assumes the deposit will take care of the TVL rebalancing.
     * 1. Claims {SCREAM} from the comptroller.
     * 2. Swaps {SCREAM} to {WFTM}.
     * 3. Claims fees for the harvest caller and treasury.
     * 4. Swaps the {WFTM} token for {want}
     * 5. Deposits.
     */
    function _harvestCore(uint256 _debt)
        internal
        override
        returns (
            uint256 callerFee,
            int256 roi,
            uint256 repayment
        )
    {
        _claimRewards();
        uint256 usdcFee = _swapRewards();
        callerFee = _chargeFees(usdcFee);
        _convertWftmToWant();

        uint256 allocated = IVault(vault).strategies(address(this)).allocated;
        uint256 totalAssets = balanceOf();
        uint256 toFree = _debt;

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

    function ADDRESSES_PROVIDER() public pure override returns (ILendingPoolAddressesProvider) {
        return ILendingPoolAddressesProvider(ADDRESSES_PROVIDER_ADDRESS);
    }

    function LENDING_POOL() public view override returns (ILendingPool) {
        return ILendingPool(ADDRESSES_PROVIDER().getLendingPool());
    }

    function executeOperation(
        address[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        address initiator,
        bytes calldata
    ) external override returns (bool) {
        require(initiator == address(this), "!initiator");
        require(flashLoanStatus == DEPOSIT_FL_IN_PROGRESS, "invalid flashLoanStatus");
        flashLoanStatus = NO_FL_IN_PROGRESS;

        // simply deposit everything we have
        // lender will automatically open a variable debt position
        // since flash loan was requested with interest rate mode VARIABLE
        address lendingPoolAddress = ADDRESSES_PROVIDER().getLendingPool();
        IERC20Upgradeable(want).safeIncreaseAllowance(lendingPoolAddress, balanceOfWant());
        LENDING_POOL().deposit(address(want), balanceOfWant(), address(this), LENDER_REFERRAL_CODE_NONE);

        return true;
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     */
    function _deposit(uint256 toReinvest) internal {
        if (toReinvest != 0) {
            address lendingPoolAddress = ADDRESSES_PROVIDER().getLendingPool();
            IERC20Upgradeable(want).safeIncreaseAllowance(lendingPoolAddress, balanceOfWant());
            LENDING_POOL().deposit(want, toReinvest, address(this), LENDER_REFERRAL_CODE_NONE);
        }

        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        uint256 currentLtv = supply != 0 ? (borrow * PERCENT_DIVISOR) / supply : 0;

        if (currentLtv > maxLtv) {
            _delever(0);
        } else if (currentLtv < targetLtv) {
            _leverUpMax();
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }

        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        supply -= _amount;
        uint256 postWithdrawLtv = supply != 0 ? (borrow * PERCENT_DIVISOR) / supply : 0;

        if (postWithdrawLtv > maxLtv) {
            _delever(_amount);
            _withdrawUnderlying(_amount);
        } else if (postWithdrawLtv < targetLtv) {
            _withdrawUnderlying(_amount);
            _leverUpMax();
        } else {
            _withdrawUnderlying(_amount);
        }
    }

    /**
     * @dev Delevers by manipulating supply/borrow such that {_withdrawAmount} can
     *      be safely withdrawn from the pool afterwards.
     */
    function _delever(uint256 _withdrawAmount) internal {
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        uint256 realSupply = supply - borrow;
        uint256 newRealSupply = realSupply > _withdrawAmount ? realSupply - _withdrawAmount : 0;
        uint256 newBorrow = (newRealSupply * targetLtv) / (PERCENT_DIVISOR - targetLtv);

        require(borrow >= newBorrow, "nothing to delever!");
        uint256 borrowReduction = borrow - newBorrow;
        for (uint256 i = 0; i < maxDeleverageLoopIterations && borrowReduction > minLeverageAmount; i++) {
            borrowReduction -= _leverDownStep(borrowReduction);
        }
    }

    /**
     * @dev Deleverages one step in an attempt to reduce borrow by {_totalBorrowReduction}.
     *      Returns the amount by which borrow was actually reduced.
     */
    function _leverDownStep(uint256 _totalBorrowReduction) internal returns (uint256) {
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        (, , uint256 threshLtv, , , , , , , ) = IAaveProtocolDataProvider(DATA_PROVIDER).getReserveConfigurationData(
            address(want)
        );
        uint256 threshSupply = (borrow * PERCENT_DIVISOR) / threshLtv;

        // don't use 100% of excess supply, leave a smidge
        uint256 allowance = ((supply - threshSupply) * DELEVER_SAFETY_ZONE) / PERCENT_DIVISOR;
        allowance = MathUpgradeable.min(allowance, borrow);
        allowance = MathUpgradeable.min(allowance, _totalBorrowReduction);
        allowance -= 10; // safety reduction to compensate for rounding errors

        ILendingPool pool = LENDING_POOL();
        pool.withdraw(address(want), allowance, address(this));
        address lendingPoolAddress = ADDRESSES_PROVIDER().getLendingPool();
        IERC20Upgradeable(want).safeIncreaseAllowance(lendingPoolAddress, allowance);
        pool.repay(address(want), allowance, INTEREST_RATE_MODE_VARIABLE, address(this));

        return allowance;
    }

    /**
     * @dev Attempts to reach max leverage as per {targetLtv} using a flash loan.
     */
    function _leverUpMax() internal {
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        uint256 realSupply = supply - borrow;
        uint256 desiredBorrow = (realSupply * targetLtv) / (PERCENT_DIVISOR - targetLtv);

        if (desiredBorrow > borrow + minLeverageAmount) {
            _initFlashLoan(desiredBorrow - borrow, INTEREST_RATE_MODE_VARIABLE, DEPOSIT_FL_IN_PROGRESS);
        }
    }

    /**
     * @dev Attempts to Withdraw {_withdrawAmount} from pool. Withdraws max amount that can be
     *      safely withdrawn if {_withdrawAmount} is too high.
     */
    function _withdrawUnderlying(uint256 _withdrawAmount) internal {
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        uint256 necessarySupply = maxLtv != 0 ? borrow.mulDivUp(PERCENT_DIVISOR, maxLtv) : 0; // use maxLtv instead of targetLtv here
        require(supply > necessarySupply, "can't withdraw anything!");

        uint256 withdrawable = supply - necessarySupply;
        _withdrawAmount = MathUpgradeable.min(_withdrawAmount, withdrawable);
        LENDING_POOL().withdraw(address(want), _withdrawAmount, address(this));
    }

    /**
     * @dev Core harvest function.
     * Swaps amount using path
     */
    function _swap(uint256 amount, address[] storage path) internal {
        if (amount != 0) {
            IERC20Upgradeable(path[0]).safeIncreaseAllowance(UNI_ROUTER, amount);
            IUniswapV2Router02(UNI_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amount,
                0,
                path,
                address(this),
                block.timestamp + 600
            );
        }
    }

    /**
     * @dev Claim rewards for supply and borrow
     */
    function _claimRewards() internal {
        IRewardsController(REWARDER).claimAllRewardsToSelf(rewardTokens);
    }

    function _swapRewards() internal returns (uint256) {
        uint256 usdcBalanceBefore = IERC20Upgradeable(USDC).balanceOf(address(this));
        if (isOathRewardActive) {
            uint256 oathBalance = IERC20Upgradeable(OATH).balanceOf(address(this));
            uint256 wftmBalanceBefore = IERC20Upgradeable(WFTM).balanceOf(address(this));
            _swap(oathBalance, oathToWftmPath);
            uint256 wftmBalanceAfter = IERC20Upgradeable(WFTM).balanceOf(address(this));
            uint256 wftmFee = (wftmBalanceAfter - wftmBalanceBefore) * totalFee / PERCENT_DIVISOR;
            _swap(wftmFee, wftmToUsdcPath);
        }
        if (isStaderRewardActive) {
            uint256 sdBalance = IERC20Upgradeable(STADER).balanceOf(address(this));
            uint256 usdcBalanceBefore = IERC20Upgradeable(USDC).balanceOf(address(this));
            _swap(sdBalance, staderToUsdcPath);
            uint256 usdcBalanceAfter = IERC20Upgradeable(USDC).balanceOf(address(this));
            uint256 usdcToSwap = (usdcBalanceAfter - usdcBalanceBefore) * (PERCENT_DIVISOR - totalFee) / PERCENT_DIVISOR; // Leave totalFee remaining for fees
            _swap(usdcToSwap, usdcToWftmPath);
        }
        if (isGrainRewardActive) {
            uint256 grainBalance = IERC20Upgradeable(GRAIN).balanceOf(address(this));
            uint256 usdcBalanceBefore = IERC20Upgradeable(USDC).balanceOf(address(this));
            _swap(grainBalance, grainToUsdcPath);
            uint256 usdcBalanceAfter = IERC20Upgradeable(USDC).balanceOf(address(this));
            uint256 usdcToSwap = (usdcBalanceAfter - usdcBalanceBefore) * (PERCENT_DIVISOR - totalFee) / PERCENT_DIVISOR; // Leave totalFee remaining for fees
            _swap(usdcToSwap, usdcToWftmPath);
        }
        uint256 usdcBalanceAfter = IERC20Upgradeable(USDC).balanceOf(address(this));
        return usdcBalanceAfter - usdcBalanceBefore;
    }

    /**
     * @dev Core harvest function.
     * Charges fees based on the amount of WFTM gained from reward
     */
    function _chargeFees(uint256 usdcFee) internal returns (uint256 callerFee) {
        if (usdcFee != 0) {
            callerFee = (usdcFee * callFee) / PERCENT_DIVISOR;
            uint256 treasuryFeeToVault = (usdcFee * treasuryFee) / PERCENT_DIVISOR;
            uint256 feeToStrategist = (treasuryFeeToVault * strategistFee) / PERCENT_DIVISOR;
            treasuryFeeToVault -= feeToStrategist;

            IERC20Upgradeable usdc = IERC20Upgradeable(USDC);

            usdc.safeTransfer(msg.sender, callerFee);
            usdc.safeTransfer(treasury, treasuryFeeToVault);
            usdc.safeTransfer(strategistRemitter, feeToStrategist);
        }
    }

    /**
     * @dev Converts all of this contract's {WFTM} balance into {want}.
     *      Typically called during harvesting to transform assets back into
     *      {want} for re-depositing.
     */
    function _convertWftmToWant() internal {
        uint256 wftmBal = IERC20Upgradeable(WFTM).balanceOf(address(this));
        if (wftmBal != 0 && wftmToWantPath.length > 1) {
            _swap(wftmBal, wftmToWantPath);
        }
    }

    /**
     * @dev Helper function to initiate a flash loan from the lending pool for:
     *      - a given {_amount} of {want}
     *      - {_rateMode}: variable (won't pay back in same tx); no rate (will pay back in same tx)
     *      - {_newLoanStatus}: mutex to set for this particular flash loan, read in executeOperation()
     */
    function _initFlashLoan(
        uint256 _amount,
        uint256 _rateMode,
        uint256 _newLoanStatus
    ) internal {
        require(_amount != 0, "FL: invalid amount!");

        // asset to be flashed
        address[] memory assets = new address[](1);
        assets[0] = address(want);

        // amount to be flashed
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _amount;

        // 0 = no debt, 1 = stable, 2 = variable
        uint256[] memory modes = new uint256[](1);
        modes[0] = _rateMode;

        flashLoanStatus = _newLoanStatus;
        LENDING_POOL().flashLoan(address(this), assets, amounts, modes, address(this), "", LENDER_REFERRAL_CODE_NONE);
    }

    /**
     * Returns the current supply and borrow balance for this strategy.
     * Supply is the amount we have deposited in the lending pool as collateral.
     * Borrow is the amount we have taken out on loan against our collateral.
     */
    function getSupplyAndBorrow() public view returns (uint256 supply, uint256 borrow) {
        (supply, , borrow, , , , , , ) = IAaveProtocolDataProvider(DATA_PROVIDER).getUserReserveData(
            address(want),
            address(this)
        );
        return (supply, borrow);
    }

    /**
     * @dev Frees up {_amount} of want by manipulating supply/borrow.
     */
    function authorizedDelever(uint256 _amount) external {
        _atLeastRole(STRATEGIST);
        _delever(_amount);
    }

    /**
     * @dev Attempts to safely withdraw {_amount} from the pool and optionally sends it
     *      to the vault.
     */
    function authorizedWithdrawUnderlying(uint256 _amount) external {
        _atLeastRole(STRATEGIST);
        _withdrawUnderlying(_amount);
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     * It takes into account both the funds in hand, plus the funds in the lendingPool.
     */
    function balanceOf() public view override returns (uint256) {
        return balanceOfPool() + balanceOfWant();
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20Upgradeable(want).balanceOf(address(this));
    }

    function balanceOfPool() public view returns (uint256) {
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        uint256 realSupply = supply - borrow;
        return realSupply;
    }

    /**
     * @dev Updates target LTV (safely), maximum iterations for the
     *      deleveraging loop, can only be called by strategist or owner.
     */
    function setLeverageParams(
        uint256 _newTargetLtv,
        uint256 _newMaxLtv,
        uint256 _newMaxDeleverageLoopIterations,
        uint256 _newMinLeverageAmount
    ) external {
        _atLeastRole(STRATEGIST);
        _safeUpdateTargetLtv(_newTargetLtv, _newMaxLtv);
        maxDeleverageLoopIterations = _newMaxDeleverageLoopIterations;
        minLeverageAmount = _newMinLeverageAmount;
    }

    /**
     * @dev Updates {targetLtv} and {maxLtv} safely, ensuring
     *      - maxLtv is less than or equal to maximum allowed LTV for asset
     *      - targetLtv is less than or equal to maxLtv
     */
    function _safeUpdateTargetLtv(uint256 _newTargetLtv, uint256 _newMaxLtv) internal {
        (, uint256 ltv, , , , , , , , ) = IAaveProtocolDataProvider(DATA_PROVIDER).getReserveConfigurationData(
            address(want)
        );
        require(_newMaxLtv <= (ltv * LTV_SAFETY_ZONE) / PERCENT_DIVISOR, "maxLtv not safe");
        require(_newTargetLtv <= _newMaxLtv, "targetLtv must <= maxLtv");
        maxLtv = _newMaxLtv;
        targetLtv = _newTargetLtv;
    }

    function toggleIsOathRewardActive() external {
        _atLeastRole(STRATEGIST);
        isOathRewardActive = !isOathRewardActive;
    }

    function toggleIsStaderRewardActive() external {
        _atLeastRole(STRATEGIST);
        isStaderRewardActive = !isStaderRewardActive;
    }

    function toggleIsGrainRewardActive() external {
        _atLeastRole(STRATEGIST);
        isGrainRewardActive = !isGrainRewardActive;
    }

    function setGrainToken(address _grainAddress) external {
        _atLeastRole(STRATEGIST);
        require(GRAIN == address(0), "GRAIN can only be set once");
        GRAIN = _grainAddress;
    }

    function setGrainToUsdcPath(address[] calldata _path) external {
        _atLeastRole(STRATEGIST);
        require(_path[0] == GRAIN, "Must start with GRAIN");
        require(_path.length > 1, "Must contain a path");
        grainToUsdcPath = _path;
    }
}
