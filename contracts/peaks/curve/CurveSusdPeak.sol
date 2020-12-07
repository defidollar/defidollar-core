pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import {ICurveDeposit, ICurve, IUtil} from "../../interfaces/ICurve.sol";
import {ICore} from "../../interfaces/ICore.sol";
import {IPeak} from "../../interfaces/IPeak.sol";
import {Uni} from "../../interfaces/Uni.sol";

import {Initializable} from "../../common/Initializable.sol";
import {OwnableProxy} from "../../common/OwnableProxy.sol";
import {IGauge, IMintr} from "./IGauge.sol";

contract CurveSusdPeak is OwnableProxy, Initializable, IPeak {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using Math for uint;

    uint constant MAX = uint(-1);
    uint constant N_COINS = 4;
    string constant ERR_SLIPPAGE = "They see you slippin";

    uint[N_COINS] ZEROES = [uint(0),uint(0),uint(0),uint(0)];
    address[N_COINS] underlyingCoins;
    uint[N_COINS] feed;

    ICurveDeposit curveDeposit; // deposit contract
    ICurve curve; // swap contract
    IERC20 curveToken; // LP token contract
    IUtil util;
    IGauge gauge;
    IMintr mintr;
    ICore core;

    function migrate(address destinationPeak, uint sCrv) public onlyOwner {
        if (sCrv == 0) {
            sCrv = gauge.balanceOf(address(this));
        }
        // withdraw from gauge
        gauge.withdraw(sCrv, false);

        // remove liquidity from sPool
        sCrv = curveToken.balanceOf(address(this));
        curve.remove_liquidity(sCrv, ZEROES);

        // swap sUSD for tether
        uint sUSD = IERC20(underlyingCoins[3]).balanceOf((address(this)));
        IERC20(underlyingCoins[3]).safeApprove(address(curve), 0);
        IERC20(underlyingCoins[3]).safeApprove(address(curve), sUSD);
        curve.exchange(int128(3), int128(2), sUSD, 0);

        // Add liquidity to yPool
        ICurveDeposit y = ICurveDeposit(0xbBC81d23Ea2c3ec7e56D39296F0cbB648873a5d3);
        uint[4] memory amounts;
        for (uint i = 0; i < 3; i++) {
            amounts[i] = IERC20(underlyingCoins[i]).balanceOf((address(this)));
            IERC20(underlyingCoins[i]).safeApprove(address(y), 0);
            IERC20(underlyingCoins[i]).safeApprove(address(y), amounts[i]);
        }
        y.add_liquidity(amounts, 0);
        IERC20 yCrv = IERC20(0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8);
        uint bal = yCrv.balanceOf(address(this));
        (,,uint8 state) = core.peaks(destinationPeak);
        require(state == 1, "Not a valid peak");
        yCrv.safeTransfer(destinationPeak, bal);
    }

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
        address[N_COINS] memory coins = underlyingCoins;
        for (uint i = 0; i < N_COINS; i++) {
            if (inAmounts[i] > 0) {
                IERC20(coins[i]).safeTransferFrom(msg.sender, address(this), inAmounts[i]);
            }
        }
        dusdAmount = _mint(inAmounts, minDusdAmount);
        stake();
    }

    function _mint(uint[N_COINS] memory inAmounts, uint minDusdAmount)
        internal
        returns (uint dusdAmount)
    {
        uint _old = portfolioValue();
        curve.add_liquidity(inAmounts, 0);
        uint _new = portfolioValue();
        dusdAmount = core.mint(_new.sub(_old), msg.sender);
        require(dusdAmount >= minDusdAmount, ERR_SLIPPAGE);
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
        _stake(inAmount);
    }

    /**
    * @dev Redeem DUSD
    * @param dusdAmount Exact dusdAmount to burn
    * @param minAmounts Min expected amounts to cap slippage
    */
    function redeem(uint dusdAmount, uint[N_COINS] calldata minAmounts)
        external
    {
        uint sCrv = _secureFunding(core.redeem(dusdAmount, msg.sender));
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
        uint sCrv = _secureFunding(core.redeem(dusdAmount, msg.sender));
        curveDeposit.remove_liquidity_one_coin(sCrv, int128(i), minOut);
        IERC20 coin = IERC20(underlyingCoins[i]);
        uint toTransfer = coin.balanceOf(address(this));
        require(toTransfer >= minOut, ERR_SLIPPAGE);
        coin.safeTransfer(msg.sender, toTransfer);
    }

    function redeemInScrv(uint dusdAmount, uint minOut)
        external
    {
        uint sCrv = _secureFunding(core.redeem(dusdAmount, msg.sender));
        require(sCrv >= minOut, ERR_SLIPPAGE);
        curveToken.safeTransfer(msg.sender, sCrv);
    }

    /**
    * @notice Stake in sCrv Gauge
    */
    function stake() public {
        _stake(curveToken.balanceOf(address(this)));
    }

    // thank you Andre :)
    function harvest(bool shouldClaim, uint minDusdAmount) external onlyOwner returns(uint) {
        if (shouldClaim) {
            claimRewards();
        }
        address uni = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        address[] memory path = new address[](3);
        path[1] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // weth

        address __crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
        IERC20 crv = IERC20(__crv);
        uint _crv = crv.balanceOf(address(this));
        uint _usdt;
        if (_crv > 0) {
            crv.safeApprove(uni, 0);
            crv.safeApprove(uni, _crv);
            path[0] = __crv;
            address __usdt = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
            path[2] = __usdt;
            Uni(uni).swapExactTokensForTokens(_crv, uint(0), path, address(this), now.add(1800));
            _usdt = IERC20(__usdt).balanceOf(address(this));
        }

        address __snx = address(0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F);
        IERC20 snx = IERC20(__snx);
        uint _snx = snx.balanceOf(address(this));
        uint _usdc;
        if (_snx > 0) {
            snx.safeApprove(uni, 0);
            snx.safeApprove(uni, _snx);
            path[0] = __snx;
            address __usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
            path[2] = __usdc;
            Uni(uni).swapExactTokensForTokens(_snx, uint(0), path, address(this), now.add(1800));
            _usdc = IERC20(__usdc).balanceOf(address(this));
        }
        return _mint([0,_usdc,_usdt,0], minDusdAmount);
    }

    function getRewards(address[] calldata tokens, address destination) external onlyOwner {
        claimRewards();
        for (uint i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            require(
                address(token) != address(curveToken),
                "Admin can't withdraw curve lp tokens"
            );
            token.safeTransfer(destination, token.balanceOf(address(this)));
        }
    }

    function claimRewards() public {
        mintr.mint(address(gauge));
        gauge.claim_rewards();
    }

    function replenishApprovals(uint value) public {
        curveToken.safeIncreaseAllowance(address(curveDeposit), value);
        curveToken.safeIncreaseAllowance(address(gauge), value);
        for (uint i = 0; i < N_COINS; i++) {
            IERC20(underlyingCoins[i]).safeIncreaseAllowance(address(curve), value);
        }
    }

    /* ##### View Functions ##### */

    function calcMint(uint[N_COINS] memory inAmounts)
        public view
        returns (uint dusdAmount)
    {
        return sCrvToUsd(curve.calc_token_amount(inAmounts, true /* deposit */));
    }

    function calcMintWithScrv(uint inAmount)
        public view
        returns (uint dusdAmount)
    {
        return sCrvToUsd(inAmount);
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

    function usdToScrv(uint usd) public view returns(uint sCrv) {
        uint exchangeRate = sCrvToUsd(1e18);
        if (exchangeRate > 0) {
            return usd.mul(1e18).div(exchangeRate);
        }
    }

    function portfolioValue() public view returns(uint) {
        return sCrvToUsd(sCrvBalance());
    }

    function sCrvToUsd(uint sCrvBal) public view returns(uint) {
        return _sCrvToUsd(sCrvBal, feed);
    }

    function sCrvBalance() public view returns(uint) {
        return curveToken.balanceOf(address(this))
            .add(gauge.balanceOf(address(this)));
    }

    function vars() public view returns(
        address _curveDeposit,
        address _curve,
        address _curveToken,
        address _util,
        address _gauge,
        address _mintr,
        address _core,
        address[N_COINS] memory _underlyingCoins,
        uint[N_COINS] memory _feed
    ) {
        return(
            address(curveDeposit),
            address(curve),
            address(curveToken),
            address(util),
            address(gauge),
            address(mintr),
            address(core),
            underlyingCoins,
            feed
        );
    }

    /* ##### Internal Functions ##### */

    function _sCrvToUsd(uint sCrvBal, uint[N_COINS] memory /* _feed */)
        internal view
        returns(uint)
    {
        return sCrvBal.mul(curve.get_virtual_price()).div(1e18);
    }

    function _secureFunding(uint usd) internal returns(uint sCrv) {
        sCrv = usdToScrv(usd).min(sCrvBalance()); // in an extreme scenario there might not be enough sCrv to redeem
        gauge.withdraw(sCrv, false);
    }

    function _stake(uint amount) internal {
        if (amount > 0) {
            gauge.deposit(amount);
        }
    }
}

