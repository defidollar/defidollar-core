pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import {ICurveDeposit, ICurve, IUtil} from "./ICurve.sol";
import {Core} from "../../base/Core.sol";
import {IPeak} from "../IPeak.sol";
import {Initializable} from "../../common/Initializable.sol";
import {Initializable} from "../../common/Initializable.sol";

contract CurveSusdPeak is Initializable, IPeak {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using Math for uint;

    uint constant MAX = uint(-1);
    uint constant N_COINS = 4;
    uint[N_COINS] ZEROES = [uint(0),uint(0),uint(0),uint(0)];
    string constant ERR_SLIPPAGE = "They see you slippin";

    address[N_COINS] public underlyingCoins;
    uint[N_COINS] public oraclePrices;

    ICurveDeposit public curveDeposit; // deposit contract
    ICurve public curve; // swap contract
    IERC20 public curveToken; // LP token contract
    Core public core;
    IUtil public util;

    function initialize(
        ICurveDeposit _curveDeposit,
        ICurve _curve,
        IERC20 _curveToken,
        Core _core,
        IUtil _util,
        address[N_COINS] memory _underlyingCoins
    )   public
        notInitialized
    {
        curveDeposit = _curveDeposit;
        curve = _curve;
        curveToken = _curveToken;
        core = _core;
        util = _util;
        underlyingCoins = _underlyingCoins;
        replenishApprovals();
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
    }

    /**
    * @notice Mint DUSD with Curve LP tokens
    * @param inAmount Exact amount of Curve LP tokens
    * @param minDusdAmount Minimum DUSD to mint, used for capping slippage
    */
    function mintWithYcrv(uint inAmount, uint minDusdAmount)
        external
        returns (uint dusdAmount)
    {
        curveToken.safeTransferFrom(msg.sender, address(this), inAmount);
        dusdAmount = core.mint(get_dollar_virtual_price(inAmount), msg.sender);
        require(dusdAmount >= minDusdAmount, ERR_SLIPPAGE);
    }

    /**
    * @dev Redeem DUSD
    * @param dusdAmount Exact dusdAmount to burn
    * @param minAmounts Min expected amounts to cap slippage
    */
    function redeem(uint dusdAmount, uint[N_COINS] calldata minAmounts)
        external
    {
        uint yCrv = usdToYcrv(core.redeem(dusdAmount, msg.sender));
        curve.remove_liquidity(yCrv, ZEROES);
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

    function redeemInOneCoin(uint dusdAmount, uint i, uint minOut)
        external
    {
        uint yCrv = usdToYcrv(core.redeem(dusdAmount, msg.sender));
        curveDeposit.remove_liquidity_one_coin(yCrv, int128(i), minOut, false);
        IERC20 coin = IERC20(underlyingCoins[i]);
        uint toTransfer = coin.balanceOf(address(this));
        require(toTransfer >= minOut, ERR_SLIPPAGE);
        coin.safeTransfer(msg.sender, toTransfer);
    }

    function redeemInYcrv(uint dusdAmount, uint minOut)
        external
    {
        uint yCrv = usdToYcrv(core.redeem(dusdAmount, msg.sender));
        require(yCrv >= minOut, ERR_SLIPPAGE);
        curveToken.safeTransfer(msg.sender, yCrv);
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
    function replenishApprovals() public {
        curveToken.approve(address(curveDeposit), MAX);
        curveToken.approve(address(curve), MAX);
        for (uint i = 0; i < N_COINS; i++) {
            IERC20 coin = IERC20(underlyingCoins[i]);
            if (coin.allowance(address(this), address(curveDeposit)) > 0) {
                coin.approve(address(curveDeposit), 0);
            }
            if (coin.allowance(address(this), address(curve)) > 0) {
                coin.approve(address(curve), 0);
            }
            coin.approve(address(curveDeposit), MAX);
            coin.approve(address(curve), MAX);
        }
    }

    /* ##### View Functions ##### */

    function calcMint(uint[N_COINS] memory inAmounts)
        public view
        returns (uint dusdAmount)
    {
        uint yCrvBal = curveToken.balanceOf(address(this));
        uint _old = get_dollar_virtual_price(yCrvBal);
        uint _new = get_dollar_virtual_price(yCrvBal.add(curve.calc_token_amount(inAmounts, true /* deposit */)));
        return core.usdToDusd(_new.sub(_old));
    }

    function calcMintWithYcrv(uint inAmount)
        public view
        returns (uint dusdAmount)
    {
        return core.usdToDusd(get_dollar_virtual_price(inAmount));
    }

    function calcRedeem(uint dusdAmount)
        public view
        returns(uint[N_COINS] memory amounts)
    {
        uint usd = core.dusdToUsd(dusdAmount, true);
        uint exchangeRate = get_dollar_virtual_price(1e18);
        uint yCrv = usd.mul(1e18).div(exchangeRate);
        uint totalSupply = curveToken.totalSupply();
        for(uint i = 0; i < N_COINS; i++) {
            amounts[i] = curve.balances(int128(i)).mul(yCrv).div(totalSupply);
        }
    }

    function calcRedeemWithYcrv(uint dusdAmount)
        public view
        returns(uint amount)
    {
        uint usd = core.dusdToUsd(dusdAmount, true);
        uint exchangeRate = get_dollar_virtual_price(1e18);
        amount = usd.mul(1e18).div(exchangeRate);
    }

    function portfolioValue() public view returns(uint) {
        return get_dollar_virtual_price(curveToken.balanceOf(address(this)));
    }

    function usdToYcrv(uint usd) public view returns(uint yCrv) {
        yCrv = curveToken.balanceOf(address(this));
        uint exchangeRate = get_dollar_virtual_price(1e18);
        if (exchangeRate > 0) {
            yCrv = yCrv.min(usd.mul(1e18).div(exchangeRate));
        }
    }

    function get_dollar_virtual_price(uint yCrvBal) public view returns(uint) {
        uint yCrvTotalSupply = curveToken.totalSupply();
        if (yCrvTotalSupply == 0 || yCrvBal == 0) {
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
        return util.get_D(balances).mul(yCrvBal).div(yCrvTotalSupply);
    }
}
