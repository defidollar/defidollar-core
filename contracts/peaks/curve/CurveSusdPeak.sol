pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import {ICurveDeposit, ICurve, IUtil} from "./ICurve.sol";
import {ICore} from "../../interfaces/ICore.sol";
import {IPeak} from "../../interfaces/IPeak.sol";

import {Initializable} from "../../common/Initializable.sol";
import {Ownable} from "../../common/Ownable.sol";
import {IGauge, IMintr} from "./IGauge.sol";

contract CurveSusdPeak is Initializable, Ownable, IPeak {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using Math for uint;

    uint constant MAX = uint(-1);
    uint constant N_COINS = 4;
    string constant ERR_SLIPPAGE = "They see you slippin";

    uint[N_COINS] ZEROES = [uint(0),uint(0),uint(0),uint(0)];
    address[N_COINS] public underlyingCoins;
    uint[N_COINS] public oraclePrices;

    ICurveDeposit public curveDeposit; // deposit contract
    ICurve public curve; // swap contract
    IERC20 public curveToken; // LP token contract
    IUtil public util;
    IGauge public gauge;
    IMintr public mintr;

    ICore public core;

    function initialize(
        ICurveDeposit _curveDeposit,
        ICurve _curve,
        IERC20 _curveToken,
        ICore _core,
        IUtil _util,
        IGauge _gauge,
        IMintr _mintr,
        address[N_COINS] memory _underlyingCoins
    )   public
        notInitialized
    {
        curveDeposit = _curveDeposit;
        curve = _curve;
        curveToken = _curveToken;
        core = _core;
        util = _util;
        gauge = _gauge;
        mintr = _mintr;
        underlyingCoins = _underlyingCoins;
        replenishApprovals(MAX);
    }

    /**
    * @dev Mint DUSD
    * @param inAmounts Exact inAmounts in the same order as required by the curve pool
    * @param minDusdAmount Minimum DUSD to mint, used for capping slippage
    */
    function mint(uint[N_COINS] calldata inAmounts, uint minDusdAmount)
        external
        returns (uint dusdAmount)
    {
        uint _old = portfolioValue();
        address[N_COINS] memory coins = underlyingCoins;
        for (uint i = 0; i < N_COINS; i++) {
            if (inAmounts[i] > 0) {
                IERC20(coins[i]).safeTransferFrom(msg.sender, address(this), inAmounts[i]);
            }
        }
        curve.add_liquidity(inAmounts, 0);
        dusdAmount = core.mint(portfolioValue().sub(_old), msg.sender);
        require(dusdAmount >= minDusdAmount, ERR_SLIPPAGE);
        if (dusdAmount >= 1e22) { // whale
            stake();
        }
    }

    /**
    * @notice Mint DUSD with Curve LP tokens
    * @param inAmount Exact amount of Curve LP tokens
    * @param minDusdAmount Minimum DUSD to mint, used for capping slippage
    */
    function mintWithScrv(uint inAmount, uint minDusdAmount)
        external
        returns (uint dusdAmount)
    {
        curveToken.safeTransferFrom(msg.sender, address(this), inAmount);
        dusdAmount = core.mint(sCrvToUsd(inAmount), msg.sender);
        require(dusdAmount >= minDusdAmount, ERR_SLIPPAGE);
        if (dusdAmount >= 1e22) { // whale
            stake();
        }
    }

    /**
    * @dev Redeem DUSD
    * @param dusdAmount Exact dusdAmount to burn
    * @param minAmounts Min expected amounts to cap slippage
    */
    function redeem(uint dusdAmount, uint[N_COINS] calldata minAmounts)
        external
    {
        uint sCrv = usdToScrv(core.redeem(dusdAmount, msg.sender));
        _withdraw(sCrv);
        curve.remove_liquidity(sCrv, ZEROES);
        address[N_COINS] memory coins = underlyingCoins;
        IERC20 coin;
        uint toTransfer;
        for (uint i = 0; i < N_COINS; i++) {
            coin = IERC20(coins[i]);
            toTransfer = coin.balanceOf(address(this));
            require(toTransfer >= minAmounts[i], ERR_SLIPPAGE);
            coin.safeTransfer(msg.sender, toTransfer);
        }
    }

    function redeemInSingleCoin(uint dusdAmount, uint i, uint minOut)
        external
    {
        uint sCrv = usdToScrv(core.redeem(dusdAmount, msg.sender));
        _withdraw(sCrv);
        curveDeposit.remove_liquidity_one_coin(sCrv, int128(i), minOut, false);
        IERC20 coin = IERC20(underlyingCoins[i]);
        uint toTransfer = coin.balanceOf(address(this));
        require(toTransfer >= minOut, ERR_SLIPPAGE);
        coin.safeTransfer(msg.sender, toTransfer);
    }

    function redeemInScrv(uint dusdAmount, uint minOut)
        external
    {
        uint sCrv = usdToScrv(core.redeem(dusdAmount, msg.sender));
        _withdraw(sCrv);
        require(sCrv >= minOut, ERR_SLIPPAGE);
        curveToken.safeTransfer(msg.sender, sCrv);
    }

    /**
    * @notice Stake in sCrv Gauge
    */
    function stake() public {
        gauge.deposit(curveToken.balanceOf(address(this)));
    }

    function updateFeed(uint[] calldata _prices) external {
        require(msg.sender == address(core), "ERR_NOT_AUTH");
        require(_prices.length == N_COINS, "ERR_INVALID_UPDATE");
        for (uint i = 0; i < N_COINS; i++) {
            oraclePrices[i] = _prices[i];
        }
    }

    // This is risky (Bancor Hack Scenario).
    // Think about if we need strict token approvals during the actions at the cost of higher gas.
    function replenishApprovals(uint value) public {
        curveToken.safeIncreaseAllowance(address(curveDeposit), value);
        curveToken.safeIncreaseAllowance(address(gauge), value);
        for (uint i = 0; i < N_COINS; i++) {
            IERC20(underlyingCoins[i]).safeIncreaseAllowance(address(curve), value);
        }
    }

    function getRewards(address[] calldata tokens, address destination) external onlyOwner {
        harvest();
        for (uint i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            require(
                address(token) != address(curveToken),
                "Admin can't withdraw curve lp tokens"
            );
            token.safeTransfer(destination, token.balanceOf(address(this)));
        }
    }

    function harvest() public {
        mintr.mint(address(gauge));
        gauge.claim_rewards();
    }

    /* ##### View Functions ##### */

    function calcMint(uint[N_COINS] memory inAmounts)
        public view
        returns (uint dusdAmount)
    {
        uint sCrvBal = curveToken.balanceOf(address(this));
        uint _old = sCrvToUsd(sCrvBal);
        uint _new = sCrvToUsd(sCrvBal.add(curve.calc_token_amount(inAmounts, true /* deposit */)));
        return core.usdToDusd(_new.sub(_old));
    }

    function calcMintWithScrv(uint inAmount)
        public view
        returns (uint dusdAmount)
    {
        return core.usdToDusd(sCrvToUsd(inAmount));
    }

    function calcRedeem(uint dusdAmount)
        public view
        returns(uint[N_COINS] memory amounts)
    {
        uint usd = core.dusdToUsd(dusdAmount, true);
        uint exchangeRate = sCrvToUsd(1e18);
        uint sCrv = usd.mul(1e18).div(exchangeRate);
        uint totalSupply = curveToken.totalSupply();
        for(uint i = 0; i < N_COINS; i++) {
            amounts[i] = curve.balances(int128(i)).mul(sCrv).div(totalSupply);
        }
    }

    function calcRedeemWithScrv(uint dusdAmount)
        public view
        returns(uint amount)
    {
        uint usd = core.dusdToUsd(dusdAmount, true);
        uint exchangeRate = sCrvToUsd(1e18);
        amount = usd.mul(1e18).div(exchangeRate);
    }

    function calcRedeemInSingleCoin(uint dusdAmount, uint i)
        public view
        returns(uint amount)
    {
        uint sCrv = usdToScrv(core.dusdToUsd(dusdAmount, true));
        amount = curveDeposit.calc_withdraw_one_coin(sCrv, int128(i));
    }

    function portfolioValue() public view returns(uint) {
        return sCrvToUsd(curveToken.balanceOf(address(this)));
    }

    function usdToScrv(uint usd) public view returns(uint sCrv) {
        sCrv = curveToken.balanceOf(address(this))
            .add(gauge.balanceOf(address(this)));
        uint exchangeRate = sCrvToUsd(1e18);
        if (exchangeRate > 0) {
            sCrv = sCrv.min(usd.mul(1e18).div(exchangeRate));
        }
    }

    function sCrvToUsd(uint sCrvBal) public view returns(uint) {
        uint sCrvTotalSupply = curveToken.totalSupply();
        if (sCrvTotalSupply == 0 || sCrvBal == 0) {
            return 0;
        }
        uint[N_COINS] memory balances;
        uint[N_COINS] memory prices = oraclePrices;
        for (uint i = 0; i < N_COINS; i++) {
            balances[i] = curve.balances(int128(i)).mul(prices[i]);
            if (i == 0 || i == 3) {
                balances[i] = balances[i].div(1e18);
            } else {
                balances[i] = balances[i].div(1e6);
            }
        }
        // https://github.com/curvefi/curve-contract/blob/pool_susd_plain/vyper/stableswap.vy#L149
        return util.get_D(balances).mul(sCrvBal).div(sCrvTotalSupply);
    }

    /* ##### Internal Functions ##### */

    function _withdraw(uint sCrv) internal {
        uint bal = curveToken.balanceOf(address(this));
        if (sCrv > bal) {
            gauge.withdraw(sCrv.sub(bal), false);
        }
    }
}
