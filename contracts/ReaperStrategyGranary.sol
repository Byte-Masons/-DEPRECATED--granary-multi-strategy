// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import "./abstract/ReaperBaseStrategyv4.sol";
import "./interfaces/IAToken.sol";
import "./interfaces/IAaveProtocolDataProvider.sol";
import "./interfaces/IFlashLoanReceiver.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/ILendingPoolAddressesProvider.sol";
import "./interfaces/ILeverageable.sol";
import "./interfaces/IRewardsController.sol";
import "./libraries/ReaperMathUtils.sol";
import "./mixins/UniMixin.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

/**
 * @dev This strategy will deposit and leverage a token on Granary to maximize yield
 */
contract ReaperStrategyGranary is ReaperBaseStrategyv4, IFlashLoanReceiver, UniMixin, ILeverageable {
    using ReaperMathUtils for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 3rd-party contract addresses
    address public constant UNI_ROUTER = 0xF491e7B69E4244ad4002BC14e878a34207E38c29;
    ILendingPoolAddressesProvider public constant ADDRESS_PROVIDER =
        ILendingPoolAddressesProvider(0x8b9D58E2Dc5e9b5275b62b1F30b3c0AC87138130);
    IAaveProtocolDataProvider public constant DATA_PROVIDER =
        IAaveProtocolDataProvider(0x3132870d08f736505FF13B19199be17629085072);
    IRewardsController public constant REWARDER = IRewardsController(0x7780E1A8321BD58BBc76594Db494c7Bfe8e87040);

    // this strategy's configurable tokens
    IAToken public gWant;

    uint256 public targetLtv; // in hundredths of percent, 8000 = 80%
    uint256 public maxLtv; // in hundredths of percent, 8000 = 80%
    uint256 public minLeverageAmount;
    uint256 public maxDeleverageLoopIterations;
    uint256 public withdrawSlippageTolerance; // basis points precision, 50 = 0.5%
    uint256 public constant LTV_SAFETY_ZONE = 9800;

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
    uint256 private constant LEVER_SAFETY_ZONE = 9250;
    uint256 private constant DELEVER_SAFETY_ZONE = 9990;
    uint256 private constant MAX_WITHDRAW_SLIPPAGE_TOLERANCE = 200;

    /**
     * @dev Tokens Used:
     * {rewardClaimingTokens} - Array containing gWant + corresponding variable debt token,
     *                          used for claiming rewards
     */
    address[] public rewardClaimingTokens;

    /**
     * We break down the harvest logic into the following operations:
     * 1. Claiming rewards
     * 2. A series of swaps as required
     * 3. Creating more of the strategy's underlying token, if necessary.
     *
     * #1 and #3 are specific to each protocol.
     * #2 however is mostly the same across all strats. So to make things more generic, we
     * will execute #2 by iterating through a series of pre-defined "steps".
     * 
     * This array holds all the swapping operations in sequence.
     * {ADMIN} role or higher will be able to set this array.
     */
    address[][] public steps;

    /**
     * @dev Initializes the strategy. Sets parameters, saves routes, and gives allowances.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address[] memory _strategists,
        address[] memory _multisigRoles,
        IAToken _gWant,
        uint256 _targetLtv,
        uint256 _maxLtv
    ) public initializer {
        gWant = _gWant;
        want = _gWant.UNDERLYING_ASSET_ADDRESS();
        __ReaperBaseStrategy_init(_vault, want, _strategists, _multisigRoles);
        maxDeleverageLoopIterations = 10;
        minLeverageAmount = 1000;
        withdrawSlippageTolerance = 50;

        (, , address vToken) = IAaveProtocolDataProvider(DATA_PROVIDER).getReserveTokensAddresses(address(want));
        rewardClaimingTokens = [address(_gWant), vToken];

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
     * @dev Core function of the strat, in charge of collecting and swapping rewards
     *      to produce more want.
     * @notice Assumes the deposit will take care of the TVL rebalancing.
     */
    function _harvestCore(uint256 _debt) internal override returns (int256 roi, uint256 repayment) {
        _claimRewards();
        uint256 numSteps = steps.length;
        for (uint256 i = 0; i < numSteps; i = i.uncheckedInc()) {
            address[] memory step = steps[i];
            IERC20Upgradeable startToken = IERC20Upgradeable(step[0]);
            uint256 amount = startToken.balanceOf(address(this));
            if (amount == 0) {
                continue;
            }
            _swapUni(amount, step, UNI_ROUTER);
        }

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

    /**
     * Only {ADMIN} or higher roles may set the array
     * of steps executed as part of harvest.
     */
    function setHarvestSteps(address[][] calldata _newSteps) external {
        _atLeastRole(ADMIN);
        delete steps;

        uint256 numSteps = _newSteps.length;
        for (uint256 i = 0; i < numSteps; i = i.uncheckedInc()) {
            address[] memory step = _newSteps[i];
            uint256 pathLength = step.length;    
            require(pathLength > 1);
            for (uint256 j = 0; j < pathLength; j = j.uncheckedInc()) {
                require(step[j] != address(0));
            }

            steps.push(step);
        }
    }

    function ADDRESSES_PROVIDER() public pure override returns (ILendingPoolAddressesProvider) {
        return ADDRESS_PROVIDER;
    }

    function LENDING_POOL() public view override returns (ILendingPool) {
        return ILendingPool(ADDRESSES_PROVIDER().getLendingPool());
    }

    function executeOperation(
        address[] calldata,
        uint256[] calldata amounts,
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
        IERC20Upgradeable(want).safeIncreaseAllowance(lendingPoolAddress, amounts[0]);
        LENDING_POOL().deposit(address(want), amounts[0], address(this), LENDER_REFERRAL_CODE_NONE);

        return true;
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     * !audit we increase the allowance in the balance amount but we deposit the amount specified
     */
    function _deposit(uint256 toReinvest) internal {
        if (toReinvest != 0) {
            address lendingPoolAddress = ADDRESSES_PROVIDER().getLendingPool();
            IERC20Upgradeable(want).safeIncreaseAllowance(lendingPoolAddress, toReinvest);
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
            uint256 borrowIncrease = desiredBorrow - borrow;

            // flash loan only if gToken has enough want liquidity
            if (IERC20Upgradeable(want).balanceOf(address(gWant)) >= borrowIncrease) {
                _initFlashLoan(borrowIncrease, INTEREST_RATE_MODE_VARIABLE, DEPOSIT_FL_IN_PROGRESS);
            } else {
                // otherwise, lever up in increments using a loop
                for (uint256 i = 0; i < maxDeleverageLoopIterations && borrowIncrease > minLeverageAmount; i++) {
                    borrowIncrease -= _leverUpStep(borrowIncrease);
                }
            }
        }
    }

    /**
     * @dev Leverages up one step in an attempt to increase borrow by {_totalBorrowIncrease}.
     *      Returns the actual amount by which borrow was increased.
     */
    function _leverUpStep(uint256 _totalBorrowIncrease) internal returns (uint256) {
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        (, uint256 threshLtv, , , , , , , , ) = IAaveProtocolDataProvider(DATA_PROVIDER).getReserveConfigurationData(
            address(want)
        );
        uint256 threshBorrow = (supply * threshLtv) / PERCENT_DIVISOR;

        // don't use 100% of borrow allowance, leave a smidge
        uint256 allowance = ((threshBorrow - borrow) * LEVER_SAFETY_ZONE) / PERCENT_DIVISOR;
        allowance = MathUpgradeable.min(allowance, IERC20Upgradeable(want).balanceOf(address(gWant)));
        allowance = MathUpgradeable.min(allowance, _totalBorrowIncrease);
        allowance -= 10; // safety reduction to compensate for rounding errors

        if (allowance != 0) {
            ILendingPool pool = LENDING_POOL();
            pool.borrow(address(want), allowance, INTEREST_RATE_MODE_VARIABLE, LENDER_REFERRAL_CODE_NONE, address(this));
            address lendingPoolAddress = ADDRESSES_PROVIDER().getLendingPool();
            IERC20Upgradeable(want).safeIncreaseAllowance(lendingPoolAddress, allowance);
            pool.deposit(address(want), allowance, address(this), LENDER_REFERRAL_CODE_NONE);
        }

        return allowance;
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
     * @dev Claim rewards for supply and borrow
     */
    function _claimRewards() internal {
        IRewardsController(REWARDER).claimAllRewardsToSelf(rewardClaimingTokens);
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
    ) external override {
        _atLeastRole(KEEPER);
        _safeUpdateTargetLtv(targetLeverage, maxLeverage);
        if (triggerHarvest) {
            harvest();
        }
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

    function calculateLTV() external view returns (uint256 ltv) {
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        if (supply != 0) {
            ltv = (borrow * PERCENT_DIVISOR) / supply;
        } else {
            ltv = 0;
        }
    }
}
