// SPDX-License-Identifier: MIT

import "./abstract/ReaperBaseStrategyv4.sol";
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

pragma solidity 0.8.11;

/**
 * @dev This strategy will deposit and leverage a token on Geist to maximize yield
 */
contract ReaperStrategyGeist is ReaperBaseStrategyv4 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 3rd-party contract addresses
    address public constant UNI_ROUTER = address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);
    address public constant GEIST_ADDRESSES_PROVIDER = address(0x6c793c628Fe2b480c5e6FB7957dDa4b9291F9c9b);
    address public constant GEIST_DATA_PROVIDER = address(0xf3B0611e2E4D2cd6aB4bb3e01aDe211c3f42A8C3);
    address public constant GEIST_INCENTIVES_CONTROLLER = address(0x297FddC5c33Ef988dd03bd13e162aE084ea1fE57);
    address public constant GEIST_STAKING = address(0x49c93a95dbcc9A6A4D8f77E59c038ce5020e82f8);

    // this strategy's configurable tokens
    IAToken public gWant;

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
        address[] memory _multisigRoles,
        IAToken _gWant,
        uint256 _targetLtv,
        uint256 _maxLtv
    ) public initializer {
        __ReaperBaseStrategy_init(_vault, want, _feeRemitters, _strategists, _multisigRoles);
        maxDeleverageLoopIterations = 10;
        withdrawSlippageTolerance = 50;
        minLeverageAmount = 1000;
        geistToWftmPath = [GEIST, WFTM];

        gWant = _gWant;
        want = _gWant.UNDERLYING_ASSET_ADDRESS();

        if (address(want) == WFTM) {
            wftmToWantPath = [WFTM];
        } else {
            wftmToWantPath = [WFTM, address(want)];
        }

        (, , address vToken) = IAaveProtocolDataProvider(GEIST_DATA_PROVIDER).getReserveTokensAddresses(address(want));
        rewardClaimingTokens = [address(_gWant), vToken];

        // _safeUpdateTargetLtv(_targetLtv, _maxLtv);
        // _giveAllowances();
    }

    function _adjustPosition(uint256 _debt) internal override {
        // if (emergencyExit) {
        //     return;
        // }

        // uint256 wantBalance = balanceOfWant();
        // if (wantBalance > _debt) {
        //     uint256 toReinvest = wantBalance - _debt;
        //     _deposit(toReinvest);
        // }
    }

    function _liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 liquidatedAmount, uint256 loss)
    {
        // uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        // if (wantBal < _amountNeeded) {
        //     _withdraw(_amountNeeded - wantBal);
        //     liquidatedAmount = IERC20Upgradeable(want).balanceOf(address(this));
        // } else {
        //     liquidatedAmount = _amountNeeded;
        // }
        // loss = _amountNeeded - liquidatedAmount;
    }

    function _liquidateAllPositions() internal override returns (uint256 amountFreed) {
        // _deleverage(type(uint256).max);
        // _withdrawUnderlying(balanceOfPool);
        // return balanceOfWant();
    }

    /**
     * @dev Calculates the total amount of {want} held by the strategy
     * which is the balance of want + the total amount supplied to Scream.
     */
    function balanceOf() public view override returns (uint256) {
        // return balanceOfWant() + balanceOfPool;
    }

    /**
     * @dev Calculates the balance of want held directly by the strategy
     */
    function balanceOfWant() public view returns (uint256) {
        // return IERC20Upgradeable(want).balanceOf(address(this));
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
        // _claimRewards();
        // _swapRewardsToWftm();
        // callerFee = _chargeFees();
        // _swapToWant();
        
        // uint256 allocated = IVault(vault).strategies(address(this)).allocated;
        // updateBalance();
        // uint256 totalAssets = balanceOf();
        // uint256 toFree = _debt;

        // if (totalAssets > allocated) {
        //     uint256 profit = totalAssets - allocated;
        //     toFree += profit;
        //     roi = int256(profit);
        // } else if (totalAssets < allocated) {
        //     roi = -int256(allocated - totalAssets);
        // }

        // (uint256 amountFreed, uint256 loss) = _liquidatePosition(toFree);
        // repayment = MathUpgradeable.min(_debt, amountFreed);
        // roi -= int256(loss);
    }
}