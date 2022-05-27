// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./interfaces/ITraderSet.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/ISwanSettings.sol";
import "./interfaces/aave/ILendingPool.sol";

contract Lake is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    AggregatorV3Interface internal priceFeed;

    uint256 private constant MAX = ~uint256(0);
    uint256 private constant USDC_DECIMAL = 6;
    uint256 private constant DEFAULT_DECIMAL = 18;

    ISwanSettings public settings;

    address[] public routers;
    mapping(address => bool) public isRouter;

    IERC20 public usdc;
    IERC20 public ampl;
    bool public isEpochActive;
    uint256 public epochNumber;
    uint256 public totalValue; // $ value

    address public investor; // $ investor can deposit/withdraw only

    ILendingPool public aavePool;

    event RouterAdded(address router);
    event RouterRemoved(address router);
    event TradingDone(address indexed trader, address[] path1, address router1, uint256 amountIn);
    event FlashTradingDone(
        address indexed trader,
        address[] path1,
        address router1,
        address[] path2,
        address router2,
        uint256 amountIn,
        uint256 profit
    );
    event Pause();
    event Unpause();
    event EpochStarted(uint256 epochNumber);
    event EpochEnded(uint256 epochNumber);

    event ValueTransferred(address indexed to, uint256 value, uint256 usdcAmount, uint256 amplAmount);
    event Deposit(address indexed invesotor, uint256 value, uint256 usdcAmount, uint256 amplAmount);
    event WithdrawAll();

    function initialize(
        address _usdc,
        address _ampl,
        address ampl_usd_feed
    ) public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();

        usdc = IERC20(_usdc);
        ampl = IERC20(_ampl);

        priceFeed = AggregatorV3Interface(ampl_usd_feed);
    }

    modifier onlyTrader() {
        require(ITraderSet(settings.traderSet()).isTrader(msg.sender), "Not a trader");
        _;
    }

    modifier onlyInvestor() {
        require(msg.sender == investor, "Not investor");
        _;
    }

    modifier epochActive() {
        require(isEpochActive, "Epoch is not active");
        _;
    }

    modifier epochNotActive() {
        require(!isEpochActive, "Epoch is active");
        _;
    }

    function setSettings(ISwanSettings _settings) external onlyOwner {
        require(address(_settings) != address(0), "Invalid");

        settings = _settings;
    }

    function setInvestor(address _investor) external onlyOwner {
        require(address(_investor) != address(0), "Invalid");

        investor = _investor;
    }

    function setAavePool(ILendingPool _aavePool) external onlyOwner {
        require(address(_aavePool) != address(0), "Invalid");

        aavePool = _aavePool;
    }

    function getRouters() external view returns (address[] memory) {
        return routers;
    }

    function getRouterCount() external view returns (uint256) {
        return routers.length;
    }

    function addRouter(address router) external onlyOwner {
        require(!isRouter[router], "Already added");

        isRouter[router] = true;
        routers.push(router);

        emit RouterAdded(router);
    }

    function removeRouter(address router) external onlyOwner {
        require(isRouter[router], "Not added yet");

        isRouter[router] = false;

        uint256 index;
        for (; index < routers.length; index++) {
            if (routers[index] == router) {
                break;
            }
        }

        if (index != routers.length - 1) {
            routers[index] = routers[routers.length - 1];
        }

        routers.pop();

        emit RouterRemoved(router);
    }

    function getCurrentTotalValue() public view returns (uint256) {
        uint256 usdcValue = usdc.balanceOf(address(this)) * 10**(DEFAULT_DECIMAL - USDC_DECIMAL);
        uint256 amplValue = (ampl.balanceOf(address(this)) * uint256(getLatestAMPLPrice())) / (10**DEFAULT_DECIMAL);

        return usdcValue + amplValue;
    }

    function startEpoch() external onlyOwner epochNotActive {
        totalValue = getCurrentTotalValue();
        isEpochActive = true;
        epochNumber += 1;

        emit EpochStarted(epochNumber);
    }

    function processMonthly() external onlyOwner epochActive {
        uint256 curEpochValue = getCurrentTotalValue();

        if (curEpochValue > totalValue) {
            //
            uint256 epochFeeValue = ((curEpochValue - totalValue) * settings.monthlyFee()) / settings.FEE_MULTIPLIER();
            _trasferValue(settings.treasury(), epochFeeValue);
        }
    }

    function endEpoch() external onlyOwner epochActive {
        isEpochActive = false;

        uint256 curEpochValue = getCurrentTotalValue();

        if (curEpochValue > totalValue) {
            //
            uint256 epochFeeValue = ((curEpochValue - totalValue) * settings.epochFee()) / settings.FEE_MULTIPLIER();
            _trasferValue(settings.treasury(), epochFeeValue);
        }

        emit EpochStarted(epochNumber);
    }

    function _trasferValue(address to, uint256 value) private {
        uint256 usdcValue = usdc.balanceOf(address(this)) * 10**(DEFAULT_DECIMAL - USDC_DECIMAL);
        uint256 amplValue = (ampl.balanceOf(address(this)) * uint256(getLatestAMPLPrice())) / (10**DEFAULT_DECIMAL);

        uint256 curEpochValue = usdcValue + amplValue;

        require(value <= curEpochValue, "Invalid value");

        uint256 usdcAmount = (value * usdcValue) / curEpochValue / (10**(DEFAULT_DECIMAL - USDC_DECIMAL));
        uint256 amplAmount = (((value * amplValue) / curEpochValue) * 10**DEFAULT_DECIMAL) /
            uint256(getLatestAMPLPrice());

        usdc.safeTransfer(to, usdcAmount);
        ampl.safeTransfer(to, amplAmount);

        totalValue = getCurrentTotalValue();

        emit ValueTransferred(to, value, usdcAmount, amplAmount);
    }

    function deposit(uint256 usdcAmount, uint256 amplAmount) external onlyInvestor epochNotActive nonReentrant {
        uint256 usdcValue = usdcAmount * 10**(DEFAULT_DECIMAL - USDC_DECIMAL);
        uint256 amplValue = amplAmount * uint256(getLatestAMPLPrice());

        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
        ampl.safeTransferFrom(msg.sender, address(this), amplAmount);

        totalValue = getCurrentTotalValue();

        emit Deposit(msg.sender, usdcValue + amplValue, usdcAmount, amplAmount);
    }

    function withdraw(uint256 value) external onlyInvestor epochNotActive nonReentrant {
        _trasferValue(msg.sender, value);
    }

    function withdrawAll() external onlyInvestor epochNotActive nonReentrant {
        usdc.safeTransfer(msg.sender, usdc.balanceOf(address(this)));
        ampl.safeTransfer(msg.sender, ampl.balanceOf(address(this)));

        emit WithdrawAll();
    }

    /**
     * Returns the latest price
     */
    function getLatestAMPLPrice() public view returns (int256) {
        (
            ,
            /*uint80 roundID*/
            int256 price, /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/
            ,
            ,

        ) = priceFeed.latestRoundData();
        // 18 decimal
        return price;
    }

    function recoverWrongToken(address token) external onlyOwner {
        require(token != address(usdc) && token != address(ampl), "Not wrong token");
        uint256 bal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, bal);
    }

    //////////////////////////////////////////////////////////////////
    // Trading related functions here

    function doTrade(
        address router1,
        address[] calldata path1,
        uint256 amountIn
    ) external onlyTrader nonReentrant whenNotPaused epochActive {
        require(isRouter[router1], "Not valid router");

        if (IERC20(path1[0]).allowance(address(this), router1) < amountIn) {
            IERC20(path1[0]).safeApprove(router1, MAX);
        }

        IUniswapV2Router02(router1).swapExactTokensForTokens(amountIn, 0, path1, address(this), block.timestamp);

        emit TradingDone(msg.sender, path1, router1, amountIn);
    }

    /**
     * @dev Deposits an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
     * - E.g. User deposits 100 USDC and gets in return 100 aUSDC
     * @param asset The address of the underlying asset to deposit
     * @param amount The amount to be deposited
     **/
    function aaveDeposit(address asset, uint256 amount) external onlyTrader nonReentrant whenNotPaused epochActive {
        if (IERC20(asset).allowance(address(aavePool), address(this)) < amount) {
            IERC20(asset).safeApprove(address(aavePool), amount);
        }
        aavePool.deposit(asset, amount, address(this), 0);
    }

    /**
     * @notice Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
     * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
     * @param asset The address of the underlying asset to withdraw
     * @param amount The underlying amount to be withdrawn
     *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
     **/
    function aaveWithdraw(address asset, uint256 amount) external onlyTrader nonReentrant whenNotPaused epochActive {
        aavePool.withdraw(asset, amount, address(this));
    }

    /**
     * @notice Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
     * already supplied enough collateral, or he was given enough allowance by a credit delegator on the
     * corresponding debt token (StableDebtToken or VariableDebtToken)
     * - E.g. User borrows 100 USDC passing as `onBehalfOf` his own address, receiving the 100 USDC in his wallet
     *   and 100 stable/variable debt tokens, depending on the `interestRateMode`
     * @param asset The address of the underlying asset to borrow
     * @param amount The amount to be borrowed
     * @param interestRateMode The interest rate mode at which the user wants to borrow: 1 for Stable, 2 for Variable
     * if he has been given credit delegation allowance
     **/
    function aaveBorrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode
    ) external onlyTrader nonReentrant whenNotPaused epochActive {
        aavePool.borrow(asset, amount, interestRateMode, 0, address(this));
    }

    /**
     * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned
     * - E.g. User repays 100 USDC, burning 100 variable/stable debt tokens of the `onBehalfOf` address
     * @param asset The address of the borrowed underlying asset previously borrowed
     * @param amount The amount to repay
     * - Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`
     * @param interestRateMode The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
     **/
    function aaveRepay(
        address asset,
        uint256 amount,
        uint256 interestRateMode
    ) external onlyTrader nonReentrant whenNotPaused epochActive {
        if (IERC20(asset).allowance(address(aavePool), address(this)) < amount) {
            IERC20(asset).safeApprove(address(aavePool), amount);
        }
        aavePool.repay(asset, amount, interestRateMode, address(this));
    }

    function profitAmount(
        address router1,
        address[] calldata path1,
        uint256 amountIn,
        address router2,
        address[] calldata path2
    ) external view returns (uint256) {
        require(path1[path1.length - 1] == path2[0], "Invalid path");
        require(path1[0] == path2[path2.length - 1], "Invalid path");
        uint256[] memory amount1Outs = IUniswapV2Router02(router1).getAmountsOut(amountIn, path1);
        uint256[] memory amount2Outs = IUniswapV2Router02(router2).getAmountsOut(
            amount1Outs[amount1Outs.length - 1],
            path2
        );

        uint256 amountOut = amount2Outs[amount2Outs.length - 1];

        if (amountOut < amountIn) {
            return 0;
        }
        return amountOut - amountIn;
    }

    /**
     * @notice buy and sell
     */
    function doFlashTrade(
        address router1,
        address[] calldata path1,
        uint256 amountIn,
        address router2,
        address[] calldata path2
    ) external nonReentrant whenNotPaused {
        require(path1[path1.length - 1] == path2[0], "Invalid path");
        require(path1[0] == path2[path2.length - 1], "Invalid path");

        if (IERC20(path1[0]).allowance(address(this), router1) < amountIn) {
            IERC20(path1[0]).safeApprove(router1, MAX);
        }

        uint256[] memory amounts1 = IUniswapV2Router02(router1).swapExactTokensForTokens(
            amountIn,
            0,
            path1,
            address(this),
            block.timestamp
        );

        uint256[] memory amounts2 = IUniswapV2Router02(router2).swapExactTokensForTokens(
            amounts1[0],
            0,
            path2,
            address(this),
            block.timestamp
        );

        uint256 amountOut = amounts2[amounts2.length - 1];

        require(amountOut > amountIn, "Non-profitable");

        uint256 profit = amountOut - amountIn;

        emit FlashTradingDone(msg.sender, path1, router1, path2, router2, amountIn, profit);
    }

    /**
     * @notice Triggers stopped state
     * @dev Only possible when contract not paused.
     */
    function pause() external onlyOwner whenNotPaused {
        _pause();
        emit Pause();
    }

    /**
     * @notice Returns to normal state
     * @dev Only possible when contract is paused.
     */
    function unpause() external onlyOwner whenPaused {
        _unpause();
        emit Unpause();
    }
}
