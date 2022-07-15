// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IStrategy.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/IVault.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

abstract contract ReaperBaseStrategyv4 is IStrategy, UUPSUpgradeable, AccessControlEnumerableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public constant UNI_ROUTER = 0xF491e7B69E4244ad4002BC14e878a34207E38c29;

    uint256 public constant PERCENT_DIVISOR = 10_000;
    uint256 public constant ONE_YEAR = 365 days;
    uint256 public constant UPGRADE_TIMELOCK = 48 hours; // minimum 48 hours for RF

    // The token the strategy wants to operate
    address public want;

    // TODO tess3rac7
    bool public emergencyExit;
    uint256 public lastHarvestTimestamp;
    uint256 public upgradeProposalTime;

    /**
     * We break down the harvest logic into the following operations:
     * 1. Claiming rewards
     * 2. A series of swaps as required, including charging fees in the desired token
     * 3. Creating more of the strategy's underlying token.
     *
     * #1 and #3 are specific to each protocol.
     * #2 however is mostly the same across all strats. So to make things more generic, we
     * will execute #2 by iterating through a series of pre-defined "steps".
     *
     * Currently, a step can of type "Swap" or "ChargeFees".
     */
    enum HarvestStepType {
        Swap,
        ChargeFees
    }

    enum StepPercentageType {
        Absolute, // use the actual percentage value
        TotalFee // use {totalFee} and ignore the actual percentage value
    }

    struct StepTypeWithData {
        HarvestStepType stepType;
        address[] path; // path[0] is treated as feesToken for ChargeFees step
        StepPercentageType percentageType;
        uint256 percentage; // in basis points precision
    }

    /**
     * This array holds all the swapping and fee-charging operations in sequence.
     * {ADMIN} role or higher will be able to pop and push things to this array when
     * the strategy is paused.
     */
    StepTypeWithData[] public steps;

    /**
     * Reaper Roles in increasing order of privilege.
     * {KEEPER} - Stricly permissioned trustless access for off-chain programs or third party keepers.
     * {STRATEGIST} - Role conferred to authors of the strategy, allows for tweaking non-critical params.
     * {GUARDIAN} - Multisig requiring 2 signatures for emergency measures such as pausing and panicking.
     * {ADMIN}- Multisig requiring 3 signatures for unpausing.
     *
     * The DEFAULT_ADMIN_ROLE (in-built access control role) will be granted to a multisig requiring 4
     * signatures. This role would have upgrading capability, as well as the ability to grant any other
     * roles.
     *
     * Also note that roles are cascading. So any higher privileged role should be able to perform all the functions
     * of any lower privileged role.
     */
    bytes32 public constant KEEPER = keccak256("KEEPER");
    bytes32 public constant STRATEGIST = keccak256("STRATEGIST");
    bytes32 public constant GUARDIAN = keccak256("GUARDIAN");
    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32[] private cascadingAccess;

    /**
     * @dev Reaper contracts:
     * {treasury} - Address of the Reaper treasury
     * {vault} - Address of the vault that controls the strategy's funds.
     * {strategistRemitter} - Address where strategist fee is remitted to.
     */
    address public treasury;
    address public vault;
    address public strategistRemitter;

    /**
     * Fee related constants:
     * {MAX_FEE} - Maximum fee allowed by the strategy. Hard-capped at 10%.
     * {STRATEGIST_MAX_FEE} - Maximum strategist fee allowed by the strategy (as % of treasury fee).
     *                        Hard-capped at 50%
     */
    uint256 public constant MAX_FEE = 1000;
    uint256 public constant STRATEGIST_MAX_FEE = 5000;

    /**
     * @dev Distribution of fees earned, expressed as % of the profit from each harvest.
     * {totalFee} - divided by 10,000 to determine the % fee. Set to 4.5% by default and
     * lowered as necessary to provide users with the most competitive APY.
     *
     * {callFee} - Percent of the totalFee reserved for the harvester (1000 = 10% of total fee: 0.45% by default)
     * {treasuryFee} - Percent of the totalFee taken by maintainers of the software (9000 = 90% of total fee: 4.05% by default)
     * {strategistFee} - Percent of the treasuryFee taken by strategist (2500 = 25% of treasury fee: 1.0125% by default)
     */
    uint256 public totalFee;
    uint256 public callFee;
    uint256 public treasuryFee;
    uint256 public strategistFee;

    /**
     * {TotalFeeUpdated} Event that is fired each time the total fee is updated.
     * {FeesUpdated} Event that is fired each time callFee+treasuryFee+strategistFee are updated.
     * {StratHarvest} Event that is fired each time the strategy gets harvested.
     * {StrategistRemitterUpdated} Event that is fired each time the strategistRemitter address is updated.
     */
    event TotalFeeUpdated(uint256 newFee);
    event FeesUpdated(uint256 newCallFee, uint256 newTreasuryFee, uint256 newStrategistFee);
    event StratHarvest(address indexed harvester);
    event StrategistRemitterUpdated(address newStrategistRemitter);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function __ReaperBaseStrategy_init(
        address _vault,
        address _want,
        address[] memory _feeRemitters,
        address[] memory _strategists,
        address[] memory _multisigRoles
    ) internal onlyInitializing {
        __UUPSUpgradeable_init();
        __AccessControlEnumerable_init();

        totalFee = 450;
        callFee = 0;
        treasuryFee = 10000;
        strategistFee = 2500;

        vault = _vault;
        treasury = _feeRemitters[0];
        strategistRemitter = _feeRemitters[1];

        want = _want;
        IERC20Upgradeable(want).safeApprove(vault, type(uint256).max);

        for (uint256 i = 0; i < _strategists.length; i = _uncheckedInc(i)) {
            _grantRole(STRATEGIST, _strategists[i]);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, _multisigRoles[0]);
        _grantRole(ADMIN, _multisigRoles[1]);
        _grantRole(GUARDIAN, _multisigRoles[2]);

        cascadingAccess = [DEFAULT_ADMIN_ROLE, ADMIN, GUARDIAN, STRATEGIST, KEEPER];
        clearUpgradeCooldown();
    }

    /**
     * @dev Withdraws funds and sends them back to the vault. Can only
     *      be called by the vault. _amount must be valid and security fee
     *      is deducted up-front.
     */
    function withdraw(uint256 _amount) external override returns (uint256 loss) {
        require(msg.sender == vault);
        require(_amount != 0);

        uint256 amountFreed = 0;
        (amountFreed, loss) = _liquidatePosition(_amount);
        IERC20Upgradeable(want).safeTransfer(vault, amountFreed);
    }

    /**
     * @dev harvest() function that takes care of logging. Subcontracts should
     *      override _harvestCore() and implement their specific logic in it.
     */
    function harvest() external override returns (uint256 callerFee) {
        _atLeastRole(KEEPER);
        int256 availableCapital = IVault(vault).availableCapital();
        uint256 debt = 0;
        if (availableCapital < 0) {
            debt = uint256(-availableCapital);
        }

        int256 roi = 0;
        uint256 repayment = 0;
        if (emergencyExit) {
            uint256 amountFreed = _liquidateAllPositions();
            if (amountFreed < debt) {
                roi = -int256(debt - amountFreed);
            } else if (amountFreed > debt) {
                roi = int256(amountFreed - debt);
            }

            repayment = debt;
            if (roi < 0) {
                repayment -= uint256(-roi);
            }
        } else {
            (callerFee, roi, repayment) = _harvestCore(debt);
        }

        debt = IVault(vault).report(roi, repayment);
        _adjustPosition(debt);
        lastHarvestTimestamp = block.timestamp;
        emit StratHarvest(msg.sender);
    }

    /**
     * Perform any Strategy unwinding or other calls necessary to capture the
     * "free return" this Strategy has generated since the last time its core
     * position(s) were adjusted. Examples include unwrapping extra rewards.
     * This call is only used during "normal operation" of a Strategy, and
     * should be optimized to minimize losses as much as possible.
     *
     * This method returns any realized profits and/or realized losses
     * incurred, and should return the total amounts of profits/losses/debt
     * payments (in `want` tokens) for the Vault's accounting.
     *
     * `_debt` will be 0 if the Strategy is not past the configured
     * allocated capital, otherwise its value will be how far past the allocation
     * the Strategy is. The Strategy's allocation is configured in the Vault.
     *
     * NOTE: `repayment` should be less than or equal to `_debt`.
     *       It is okay for it to be less than `_debt`, as that
     *       should only used as a guide for how much is left to pay back.
     *       Payments should be made to minimize loss from slippage, debt,
     *       withdrawal fees, etc.
     * @dev The amount of fee that is remitted to the
     *      caller must be returned.
     */
    function _harvestCore(uint256 _debt)
        internal
        virtual
        returns (
            uint256 callerFee,
            int256 roi,
            uint256 repayment
        )
    {
        _claimRewards();
        uint256 numSteps = steps.length;
        for (uint256 i = 0; i < numSteps; i = _uncheckedInc(i)) {
            StepTypeWithData storage step = steps[i];
            IERC20Upgradeable startToken = IERC20Upgradeable(step.path[0]);
            uint256 percentage = _getStepPercentage(step.percentageType, step.percentage);
            uint256 amount = (startToken.balanceOf(address(this)) * percentage) / PERCENT_DIVISOR;
            if (amount == 0) {
                continue;
            }

            if (step.stepType == HarvestStepType.Swap) {
                _swap(amount, step.path);
            } else if (step.stepType == HarvestStepType.ChargeFees) {
                uint256 callFeeToUser = (amount * callFee) / PERCENT_DIVISOR;
                callerFee += callFeeToUser;
                uint256 treasuryFeeToVault = (amount * treasuryFee) / PERCENT_DIVISOR;
                uint256 feeToStrategist = (treasuryFeeToVault * strategistFee) / PERCENT_DIVISOR;
                treasuryFeeToVault -= feeToStrategist;

                startToken.safeTransfer(msg.sender, callFeeToUser);
                startToken.safeTransfer(treasury, treasuryFeeToVault);
                startToken.safeTransfer(strategistRemitter, feeToStrategist);
            }
        }
        _addLiquidity();

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
     * Helper function that reads the {StepPercentageType} and returns
     * the correct token % to use in the operation. If the percentage type
     * is {TotalFee}, {_rawPercentage} is ignored and {totalFee} is returned.
     * Otherwise, {_rawPercentage} is returned.
     */
    function _getStepPercentage(StepPercentageType _type, uint256 _rawPercentage)
        internal
        view
        returns (uint256 percentage)
    {
        if (_type == StepPercentageType.TotalFee) {
            percentage = totalFee;
        } else {
            percentage = _rawPercentage;
        }
    }

    /**
     * @dev Core harvest function.
     * Swaps amount using path
     */
    function _swap(uint256 amount, address[] storage path) internal {
        if (amount != 0) {
            // TODO tess3rac7 check getAmountsOut returns non-zero
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
     * Only {ADMIN} or higher roles may set the array
     * of steps executed as part of harvest.
     */
    function setHarvestSteps(StepTypeWithData[] calldata _newSteps) external {
        _atLeastRole(ADMIN);
        delete steps;

        uint256 numSteps = _newSteps.length;
        for (uint256 i = 0; i < numSteps; i = _uncheckedInc(i)) {
            StepTypeWithData memory step = _newSteps[i];
            uint256 pathLength = step.path.length;
            if (step.stepType == HarvestStepType.Swap) {
                require(pathLength > 1);
                for (uint256 j = 0; j < pathLength; j = _uncheckedInc(j)) {
                    require(step.path[j] != address(0));
                }
            } else {
                require(pathLength == 1);
                require(step.path[0] != address(0));
            }

            if (step.percentageType == StepPercentageType.Absolute) {
                require(step.percentage != 0);
                require(step.percentage <= PERCENT_DIVISOR);
            }

            steps.push(step);
        }
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     *      It takes into account both the funds in hand, plus the funds in external contracts.
     */
    function balanceOf() public view virtual override returns (uint256);

    /**
     * @notice
     *  Activates emergency exit. Once activated, the Strategy will exit its
     *  position upon the next harvest, depositing all funds into the Vault as
     *  quickly as is reasonable given on-chain conditions.
     *
     *  This may only be called by governance or the strategist.
     * @dev
     *  See `vault.setEmergencyShutdown()` and `harvest()` for further details.
     */
    function setEmergencyExit() external {
        _atLeastRole(GUARDIAN);
        emergencyExit = true;
        IVault(vault).revokeStrategy(address(this));
    }

    /**
     * @dev updates the total fee, capped at 5%; only DEFAULT_ADMIN_ROLE.
     */
    function updateTotalFee(uint256 _totalFee) external {
        _atLeastRole(DEFAULT_ADMIN_ROLE);
        require(_totalFee <= MAX_FEE);
        totalFee = _totalFee;
        emit TotalFeeUpdated(totalFee);
    }

    /**
     * @dev updates the call fee, treasury fee, and strategist fee
     *      call Fee + treasury Fee must add up to PERCENT_DIVISOR
     *
     *      strategist fee is expressed as % of the treasury fee and
     *      must be no more than STRATEGIST_MAX_FEE
     *
     *      only DEFAULT_ADMIN_ROLE.
     */
    function updateFees(
        uint256 _callFee,
        uint256 _treasuryFee,
        uint256 _strategistFee
    ) external returns (bool) {
        _atLeastRole(DEFAULT_ADMIN_ROLE);
        require(_callFee + _treasuryFee == PERCENT_DIVISOR);
        require(_strategistFee <= STRATEGIST_MAX_FEE);

        callFee = _callFee;
        treasuryFee = _treasuryFee;
        strategistFee = _strategistFee;
        emit FeesUpdated(callFee, treasuryFee, strategistFee);
        return true;
    }

    /**
     * @dev only DEFAULT_ADMIN_ROLE can update treasury address.
     */
    function updateTreasury(address newTreasury) external returns (bool) {
        _atLeastRole(DEFAULT_ADMIN_ROLE);
        treasury = newTreasury;
        return true;
    }

    /**
     * @dev Updates the current strategistRemitter. Only DEFAULT_ADMIN_ROLE may do this.
     */
    function updateStrategistRemitter(address _newStrategistRemitter) external {
        _atLeastRole(DEFAULT_ADMIN_ROLE);
        require(_newStrategistRemitter != address(0));
        strategistRemitter = _newStrategistRemitter;
        emit StrategistRemitterUpdated(_newStrategistRemitter);
    }

    /**
     * @dev This function must be called prior to upgrading the implementation.
     *      It's required to wait UPGRADE_TIMELOCK seconds before executing the upgrade.
     *      Strategists and roles with higher privilege can initiate this cooldown.
     */
    function initiateUpgradeCooldown() external {
        _atLeastRole(STRATEGIST);
        upgradeProposalTime = block.timestamp;
    }

    /**
     * @dev This function is called:
     *      - in initialize()
     *      - as part of a successful upgrade
     *      - manually to clear the upgrade cooldown.
     * Guardian and roles with higher privilege can clear this cooldown.
     */
    function clearUpgradeCooldown() public {
        _atLeastRole(GUARDIAN);
        upgradeProposalTime = block.timestamp + (ONE_YEAR * 100);
    }

    /**
     * @dev This function must be overriden simply for access control purposes.
     *      Only DEFAULT_ADMIN_ROLE can upgrade the implementation once the timelock
     *      has passed.
     */
    function _authorizeUpgrade(address) internal override {
        _atLeastRole(DEFAULT_ADMIN_ROLE);
        require(upgradeProposalTime + UPGRADE_TIMELOCK < block.timestamp);
        clearUpgradeCooldown();
    }

    /**
     * @dev Internal function that checks cascading role privileges. Any higher privileged role
     * should be able to perform all the functions of any lower privileged role. This is
     * accomplished using the {cascadingAccess} array that lists all roles from most privileged
     * to least privileged.
     */
    function _atLeastRole(bytes32 role) internal view {
        uint256 numRoles = cascadingAccess.length;
        uint256 specifiedRoleIndex;
        for (uint256 i = 0; i < numRoles; i = _uncheckedInc(i)) {
            if (role == cascadingAccess[i]) {
                specifiedRoleIndex = i;
                break;
            } else if (i == numRoles - 1) {
                revert();
            }
        }

        for (uint256 i = 0; i <= specifiedRoleIndex; i = _uncheckedInc(i)) {
            if (hasRole(cascadingAccess[i], msg.sender)) {
                break;
            } else if (i == specifiedRoleIndex) {
                revert();
            }
        }
    }

    /**
     * Perform any adjustments to the core position(s) of this Strategy given
     * what change the Vault made in the "investable capital" available to the
     * Strategy. Note that all "free capital" in the Strategy after the report
     * was made is available for reinvestment. Also note that this number
     * could be 0, and you should handle that scenario accordingly.
     */
    function _adjustPosition(uint256 _debt) internal virtual;

    /**
     * Liquidate up to `_amountNeeded` of `want` of this strategy's positions,
     * irregardless of slippage. Any excess will be re-invested with `_adjustPosition()`.
     * This function should return the amount of `want` tokens made available by the
     * liquidation. If there is a difference between them, `loss` indicates whether the
     * difference is due to a realized loss, or if there is some other sitution at play
     * (e.g. locked funds) where the amount made available is less than what is needed.
     *
     * NOTE: The invariant `liquidatedAmount + loss <= _amountNeeded` should always be maintained
     */
    function _liquidatePosition(uint256 _amountNeeded)
        internal
        virtual
        returns (uint256 liquidatedAmount, uint256 loss);

    /**
     * Liquidate everything and returns the amount that got freed.
     * This function is used during emergency exit instead of `_harvestCore()` to
     * liquidate all of the Strategy's positions back to the Vault.
     */
    function _liquidateAllPositions() internal virtual returns (uint256 amountFreed);

    /**
     * @dev subclasses should add their custom logic for claiming rewards as part of
     *      harvest within this function.
     */
    function _claimRewards() internal virtual;

    /**
     * @dev subclasses should add their custom logic for creating more of the strategy's
     *      underlying token within this function.
     */
    function _addLiquidity() internal virtual;

    function _uncheckedInc(uint256 i) internal pure returns (uint256) {
        unchecked {
            return i + 1;
        }
    }
}
