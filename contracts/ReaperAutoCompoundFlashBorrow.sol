// SPDX-License-Identifier: agpl-3.0

pragma solidity ^0.8.0;

import "./ReaperBaseStrategy.sol";
import "./interfaces/IAToken.sol";
import "./interfaces/IAaveProtocolDataProvider.sol";
import "./interfaces/IChefIncentivesController.sol";
import "./interfaces/IFlashLoanReceiver.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/ILendingPoolAddressesProvider.sol";
import "./interfaces/IMultiFeeDistribution.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

/**
 * @dev Implementation of a strategy to get yields from depositing
 * the specified asset in a lending pool such as Geist.
 *
 * Flash loans are utilized during deposit() to achieve max leverage
 * without any loops.
 */
contract ReaperAutoCompoundFlashBorrow is ReaperBaseStrategy, IFlashLoanReceiver {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 3rd-party contract addresses
    address public constant UNI_ROUTER = address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);
    address public constant GEIST_ADDRESSES_PROVIDER = address(0x6c793c628Fe2b480c5e6FB7957dDa4b9291F9c9b);
    address public constant GEIST_DATA_PROVIDER = address(0xf3B0611e2E4D2cd6aB4bb3e01aDe211c3f42A8C3);
    address public constant GEIST_INCENTIVES_CONTROLLER = address(0x297FddC5c33Ef988dd03bd13e162aE084ea1fE57);
    address public constant GEIST_STAKING = address(0x49c93a95dbcc9A6A4D8f77E59c038ce5020e82f8);

    // this strategy's configurable tokens
    IAToken public gWant;
    IERC20Upgradeable public want;

    uint256 public targetLtv; // in hundredths of percent, 8000 = 80%
    uint256 public maxDeleverageLoopIterations;
    uint256 public withdrawSlippageTolerance; // basis points precision, 50 = 0.5%

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
     * {GEIST} - Reward token for borrowing/lending that is used to rebalance and re-deposit.
     * {rewardClaimingTokens} - Array containing gWant + corresponding variable debt token,
     *                          used for vesting any oustanding unvested Geist tokens.
     */
    address public constant WFTM = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public constant GEIST = address(0xd8321AA83Fb0a4ECd6348D4577431310A6E0814d);
    address[] public rewardClaimingTokens;

    /**
     * @dev Paths used to swap tokens:
     * {wftmToWantPath} - to swap {WFTM} to {want}
     * {geistToWftmPath} - to swap {GEIST} to {WFTM}
     */
    address[] public wftmToWantPath;
    address[] public geistToWftmPath;

    uint256 public maxLtv; // in hundredths of percent, 8000 = 80%
    uint256 public minLeverageAmount;

    /**
     * @dev Initializes the strategy. Sets parameters, saves routes, and gives allowances.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address[] memory _feeRemitters,
        address[] memory _strategists,
        IAToken _gWant,
        uint256 _targetLtv,
        uint256 _maxLtv
    ) public initializer {
        __ReaperBaseStrategy_init(_vault, _feeRemitters, _strategists);
        maxDeleverageLoopIterations = 10;
        withdrawSlippageTolerance = 50;
        minLeverageAmount = 1000;
        geistToWftmPath = [GEIST, WFTM];

        gWant = _gWant;
        want = IERC20Upgradeable(_gWant.UNDERLYING_ASSET_ADDRESS());

        if (address(want) == WFTM) {
            wftmToWantPath = [WFTM];
        } else {
            wftmToWantPath = [WFTM, address(want)];
        }

        (, , address vToken) = IAaveProtocolDataProvider(GEIST_DATA_PROVIDER).getReserveTokensAddresses(address(want));
        rewardClaimingTokens = [address(_gWant), vToken];

        _safeUpdateTargetLtv(_targetLtv, _maxLtv);
        _giveAllowances();
    }

    function ADDRESSES_PROVIDER() public pure override returns (ILendingPoolAddressesProvider) {
        return ILendingPoolAddressesProvider(GEIST_ADDRESSES_PROVIDER);
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
        LENDING_POOL().deposit(address(want), want.balanceOf(address(this)), address(this), LENDER_REFERRAL_CODE_NONE);

        return true;
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     */
    function deposit() public override whenNotPaused {
        uint256 wantBal = want.balanceOf(address(this));
        if (wantBal != 0) {
            LENDING_POOL().deposit(address(want), wantBal, address(this), LENDER_REFERRAL_CODE_NONE);
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
    function withdraw(uint256 _amount, bool) external override {
        require(msg.sender == vault, "!vault");
        require(_amount != 0, "invalid amount");
        require(_amount <= balanceOf(), "invalid amount");

        uint256 withdrawFee = (_amount * securityFee) / PERCENT_DIVISOR;
        _amount -= withdrawFee;

        uint256 wantBal = want.balanceOf(address(this));
        if (_amount <= wantBal) {
            want.safeTransfer(vault, _amount);
            return;
        }

        uint256 remaining = _amount - wantBal;
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        supply -= remaining;
        uint256 postWithdrawLtv = supply != 0 ? (borrow * PERCENT_DIVISOR) / supply : 0;

        if (postWithdrawLtv > maxLtv) {
            _delever(remaining);
            _withdrawAndSendToVault(remaining, _amount);
        } else if (postWithdrawLtv < targetLtv) {
            _withdrawAndSendToVault(remaining, _amount);
            _leverUpMax();
        } else {
            _withdrawAndSendToVault(remaining, _amount);
        }
    }

    /**
     * @dev Returns the approx amount of profit from harvesting.
     *      Profit is denominated in WFTM, and takes fees into account.
     */
    function estimateHarvest() external view override returns (uint256 profit, uint256 callFeeToUser) {
        // Technically profit is made up of:
        // 1. 50% of unvested geist (we claim immediately so 50% penalty applies)
        // 2. Less any rebalancing needed
        //
        // However, the main purpose of this function is estimating callFeeToUser
        // and we will charge fees before rebalancing. So in here we don't
        // factor in the rebalancing.
        uint256[] memory unvestedGeistRewards = IChefIncentivesController(GEIST_INCENTIVES_CONTROLLER).claimableReward(
            address(this),
            rewardClaimingTokens
        );
        uint256 unvestedGeist;

        for (uint256 i; i < unvestedGeistRewards.length; i++) {
            unvestedGeist += unvestedGeistRewards[i];
        }

        unvestedGeist /= 2;

        profit = IUniswapV2Router02(UNI_ROUTER).getAmountsOut(unvestedGeist, geistToWftmPath)[1];

        // take out fees from profit
        uint256 wftmFee = (profit * totalFee) / PERCENT_DIVISOR;
        callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
        profit -= wftmFee;
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
        (, , uint256 threshLtv, , , , , , , ) = IAaveProtocolDataProvider(GEIST_DATA_PROVIDER)
            .getReserveConfigurationData(address(want));
        uint256 threshSupply = (borrow * PERCENT_DIVISOR) / threshLtv;

        // don't use 100% of excess supply, leave a smidge
        uint256 allowance = ((supply - threshSupply) * DELEVER_SAFETY_ZONE) / PERCENT_DIVISOR;
        allowance = MathUpgradeable.min(allowance, borrow);
        allowance = MathUpgradeable.min(allowance, _totalBorrowReduction);
        allowance -= 10; // safety reduction to compensate for rounding errors

        ILendingPool pool = LENDING_POOL();
        pool.withdraw(address(want), allowance, address(this));
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
     * @dev Withdraws {_withdrawAmount} from pool and attempts to send {_vaultExpecting} to vault.
     */
    function _withdrawAndSendToVault(uint256 _withdrawAmount, uint256 _vaultExpecting) internal {
        _withdrawUnderlying(_withdrawAmount);

        uint256 wantBal = want.balanceOf(address(this));
        if (wantBal < _vaultExpecting) {
            require(
                wantBal >= (_vaultExpecting * (PERCENT_DIVISOR - withdrawSlippageTolerance)) / PERCENT_DIVISOR,
                "withdraw: outside slippage tolerance!"
            );
        }

        want.safeTransfer(vault, MathUpgradeable.min(wantBal, _vaultExpecting));
    }

    /**
     * @dev Attempts to Withdraw {_withdrawAmount} from pool. Withdraws max amount that can be
     *      safely withdrawn if {_withdrawAmount} is too high.
     */
    function _withdrawUnderlying(uint256 _withdrawAmount) internal {
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        uint256 necessarySupply = maxLtv != 0 ? (borrow * PERCENT_DIVISOR) / maxLtv : 0; // use maxLtv instead of targetLtv here
        require(supply > necessarySupply, "can't withdraw anything!");

        uint256 withdrawable = supply - necessarySupply;
        _withdrawAmount = MathUpgradeable.min(_withdrawAmount, withdrawable);
        LENDING_POOL().withdraw(address(want), _withdrawAmount, address(this));
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     */
    function _harvestCore() internal override {
        _processGeistVestsAndSwapToFtm();
        _chargePerformanceFees();
        _convertWftmToWant();
        deposit();
    }

    /**
     * @dev Vests {GEIST} tokens, withdraws them immediately (for 50% penalty), swaps them to {WFTM}.
     */
    function _processGeistVestsAndSwapToFtm() internal {
        // vest unvested tokens
        IChefIncentivesController(GEIST_INCENTIVES_CONTROLLER).claim(address(this), rewardClaimingTokens);

        // withdraw immediately
        IMultiFeeDistribution stakingContract = IMultiFeeDistribution(GEIST_STAKING);
        // "amount" and "penaltyAmount" would always be the same since
        // penalty is 50%. However, sometimes the returned value for
        // "amount" might be 1 wei higher than "penalty" due to rounding
        // which causes withdraw(amount) to fail. Hence we take the min.
        (uint256 amount, uint256 penaltyAmount) = stakingContract.withdrawableBalance(address(this));
        stakingContract.withdraw(MathUpgradeable.min(amount, penaltyAmount));

        // swap to ftm
        IUniswapV2Router02(UNI_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            IERC20Upgradeable(GEIST).balanceOf(address(this)),
            0,
            geistToWftmPath,
            address(this),
            block.timestamp + 600
        );
    }

    /**
     * @dev Takes out fees from the rewards.
     * callFeeToUser is set as a percentage of the fee.
     */
    function _chargePerformanceFees() internal {
        uint256 wftmFee = (IERC20Upgradeable(WFTM).balanceOf(address(this)) * totalFee) / PERCENT_DIVISOR;

        if (wftmFee != 0) {
            uint256 callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
            uint256 treasuryFeeToVault = (wftmFee * treasuryFee) / PERCENT_DIVISOR;
            uint256 feeToStrategist = (treasuryFeeToVault * strategistFee) / PERCENT_DIVISOR;
            treasuryFeeToVault -= feeToStrategist;

            IERC20Upgradeable(WFTM).safeTransfer(msg.sender, callFeeToUser);
            IERC20Upgradeable(WFTM).safeTransfer(treasury, treasuryFeeToVault);
            IERC20Upgradeable(WFTM).safeTransfer(strategistRemitter, feeToStrategist);
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
            IUniswapV2Router02(UNI_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                wftmBal,
                0,
                wftmToWantPath,
                address(this),
                block.timestamp + 600
            );
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
        (supply, , borrow, , , , , , ) = IAaveProtocolDataProvider(GEIST_DATA_PROVIDER).getUserReserveData(
            address(want),
            address(this)
        );
        return (supply, borrow);
    }

    /**
     * @dev Frees up {_amount} of want by manipulating supply/borrow.
     */
    function authorizedDelever(uint256 _amount) external {
        _onlyStrategistOrOwner();
        _delever(_amount);
    }

    /**
     * @dev Attempts to safely withdraw {_amount} from the pool and optionally sends it
     *      to the vault.
     */
    function authorizedWithdrawUnderlying(uint256 _amount, bool _sendToVault) external {
        _onlyStrategistOrOwner();
        if (_sendToVault) {
            _withdrawAndSendToVault(_amount, _amount);
        } else {
            _withdrawUnderlying(_amount);
        }
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     * It takes into account both the funds in hand, plus the funds in the lendingPool.
     */
    function balanceOf() public view override returns (uint256) {
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        uint256 realSupply = supply - borrow;
        return realSupply + want.balanceOf(address(this));
    }

    /**
     * @dev Function to retire the strategy. Claims all rewards and withdraws
     *      all principal from external contracts, and sends everything back to
     *      the vault. Can only be called by strategist or owner.
     *
     * Note: this is not an emergency withdraw function. For that, see panic().
     */
    function retireStrat() external override {
        _onlyStrategistOrOwner();
        _processGeistVestsAndSwapToFtm();
        _convertWftmToWant();
        _delever(type(uint256).max);
        _withdrawUnderlying(type(uint256).max);
        want.safeTransfer(vault, want.balanceOf(address(this)));
    }

    /**
     * @dev Pauses deposits. Withdraws all funds leaving rewards behind
     */
    function panic() external override {
        _onlyStrategistOrOwner();
        _delever(type(uint256).max);
        _withdrawUnderlying(type(uint256).max);
        pause();
    }

    /**
     * @dev Pauses the strat.
     */
    function pause() public override {
        _onlyStrategistOrOwner();
        _pause();
        _removeAllowances();
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause() external override {
        _onlyStrategistOrOwner();
        _unpause();
        _giveAllowances();
        deposit();
    }

    /**
     * @dev Updates target LTV (safely), maximum iterations for the
     *      deleveraging loop, slippage tolerance (when withdrawing),
     *      Can only be called by strategist or owner.
     */
    function setLeverageParams(
        uint256 _newTargetLtv,
        uint256 _newMaxLtv,
        uint256 _newMaxDeleverageLoopIterations,
        uint256 _newWithdrawSlippageTolerance,
        uint256 _newMinLeverageAmount
    ) external {
        _onlyStrategistOrOwner();
        _safeUpdateTargetLtv(_newTargetLtv, _newMaxLtv);
        maxDeleverageLoopIterations = _newMaxDeleverageLoopIterations;

        require(_newWithdrawSlippageTolerance <= MAX_WITHDRAW_SLIPPAGE_TOLERANCE, "invalid slippage!");
        withdrawSlippageTolerance = _newWithdrawSlippageTolerance;
        minLeverageAmount = _newMinLeverageAmount;
    }

    /**
     * @dev Updates {targetLtv} and {maxLtv} safely, ensuring
     *      - maxLtv is less than or equal to maximum allowed LTV for asset
     *      - targetLtv is less than or equal to maxLtv
     */
    function _safeUpdateTargetLtv(uint256 _newTargetLtv, uint256 _newMaxLtv) internal {
        (, uint256 ltv, , , , , , , , ) = IAaveProtocolDataProvider(GEIST_DATA_PROVIDER).getReserveConfigurationData(
            address(want)
        );
        require(_newMaxLtv <= ltv, "maxLtv not safe");
        require(_newTargetLtv <= _newMaxLtv, "targetLtv must <= maxLtv");
        maxLtv = _newMaxLtv;
        targetLtv = _newTargetLtv;
    }

    /**
     * @dev Gives all the necessary allowances to:
     *      - deposit {want} into lending pool
     *      - swap {GEIST} rewards to {WFTM}
     *      - swap {WFTM} to {want}
     */
    function _giveAllowances() internal {
        address lendingPoolAddress = ADDRESSES_PROVIDER().getLendingPool();
        IERC20Upgradeable(want).safeApprove(lendingPoolAddress, 0);
        IERC20Upgradeable(want).safeApprove(lendingPoolAddress, type(uint256).max);
        IERC20Upgradeable(GEIST).safeApprove(UNI_ROUTER, 0);
        IERC20Upgradeable(GEIST).safeApprove(UNI_ROUTER, type(uint256).max);
        IERC20Upgradeable(WFTM).safeApprove(UNI_ROUTER, 0);
        IERC20Upgradeable(WFTM).safeApprove(UNI_ROUTER, type(uint256).max);
    }

    /**
     * @dev Removes all the allowances that were given above.
     */
    function _removeAllowances() internal {
        address lendingPoolAddress = ADDRESSES_PROVIDER().getLendingPool();
        IERC20Upgradeable(want).safeApprove(lendingPoolAddress, 0);
        IERC20Upgradeable(GEIST).safeApprove(UNI_ROUTER, 0);
        IERC20Upgradeable(WFTM).safeApprove(UNI_ROUTER, 0);
    }
}
