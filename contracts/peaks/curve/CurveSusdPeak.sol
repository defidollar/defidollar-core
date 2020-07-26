pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {ICurveDeposit, ICurve} from "./ICurve.sol";
import {Core} from "../../base/Core.sol";
import {IPeak} from "../IPeak.sol";
import {Initializable} from "../../common/Initializable.sol";
import {Initializable} from "../../common/Initializable.sol";

contract CurveSusdPeak is Initializable, IPeak {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    uint constant MAX = 2**256 - 1;
    uint constant N_COINS = 4;

    address[N_COINS] public underlyingCoins;

    ICurveDeposit curveDeposit; // deposit contract
    ICurve curve; // swap contract
    IERC20 curveToken; // LP token contract
    Core core;

    struct LPShareInfo {
        uint old_lp_amount;
        uint old_lp_supply;
        uint new_lp_amount;
        uint new_lp_supply;
    }

    function initialize(
        ICurveDeposit _curveDeposit,
        ICurve _curve,
        IERC20 _curveToken,
        Core _core,
        address[N_COINS] memory _underlyingCoins
    )   public
        notInitialized
    {
        curveDeposit = _curveDeposit;
        curve = _curve;
        curveToken = _curveToken;
        core = _core;
        underlyingCoins = _underlyingCoins;
    }

    /**
    * @dev Mint DUSD
    * @param inAmounts Exact inAmounts in the same order as required by the curve pool
    * @param minDusdAmount Minimum DUSD to mint, used for capping slippage
    */
    function mint(
        uint[] calldata inAmounts,
        uint minDusdAmount
    ) external
        returns (uint dusdAmount)
    {
        address[N_COINS] memory coins = underlyingCoins;
        uint[N_COINS] memory pool_sizes;

        for (uint i = 0; i < N_COINS; i++) {
            pool_sizes[i] = curve.balances(i);
            if (inAmounts[i] == 0) {
                continue;
            }
            IERC20(coins[i]).safeTransferFrom(msg.sender, address(this), inAmounts[i]);
        }

        LPShareInfo memory info;
        info.old_lp_amount = curveToken.balanceOf(address(this));
        info.old_lp_supply = curveToken.totalSupply();

        curveDeposit.add_liquidity(inAmounts, 0);

        info.new_lp_amount = curveToken.balanceOf(address(this));
        info.new_lp_supply = curveToken.totalSupply();

        uint[] memory delta = new uint[](N_COINS);
        for (uint i = 0; i < N_COINS; i++) {
            delta[i] = _calcDepositDelta(info, pool_sizes[i], inAmounts[i]);
        }
        return core.mint(delta, minDusdAmount, msg.sender);
    }

    /**
    * @dev Burn DUSD
    * @param outAmounts Exact outAmounts in the same order as required by the curve pool
    * @param maxDusdAmount Max DUSD to burn, used for capping slippage
    */
    function redeem(
        uint[] calldata outAmounts,
        uint maxDusdAmount
    )
        external
        returns(uint dusdAmount)
    {
        uint[N_COINS] memory pool_sizes;
        for (uint i = 0; i < N_COINS; i++) {
            pool_sizes[i] = curve.balances(i);
        }

        LPShareInfo memory info;
        info.old_lp_amount = curveToken.balanceOf(address(this));
        info.old_lp_supply = curveToken.totalSupply();

        curveDeposit.remove_liquidity_imbalance(outAmounts, MAX);

        info.new_lp_amount = curveToken.balanceOf(address(this));
        info.new_lp_supply = curveToken.totalSupply();

        address[N_COINS] memory coins = underlyingCoins;
        uint[] memory delta = new uint[](N_COINS);

        for (uint i = 0; i < N_COINS; i++) {
            IERC20(coins[i]).safeTransfer(msg.sender, outAmounts[i]);
            delta[i] = _calcWithdrawDelta(info, pool_sizes[i], outAmounts[i]);
        }
        return core.redeem(delta, maxDusdAmount, msg.sender);
    }

    // This is risky (Bancor Hack scenario).
    // Think about if we need strict token approvals during the actions at the cost of higher gas.
    function replenish_approvals() external {
        curveToken.approve(address(curveDeposit), MAX);
        for (uint i = 0; i < N_COINS; i++) {
            IERC20(underlyingCoins[i]).approve(address(curveDeposit), MAX);
        }
    }

    function portfolio() public view returns(uint[] memory _portfolio) {
        uint lp_amount = curveToken.balanceOf(address(this));
        uint lp_supply = curveToken.totalSupply();
        _portfolio = new uint[](N_COINS);
        if (lp_supply > 0) {
            for (uint i = 0; i < N_COINS; i++) {
                _portfolio[i] = curve.balances(i).mul(lp_amount).div(lp_supply);
            }
        }
    }

    function _calcDepositDelta(
        LPShareInfo memory info,
        uint old_pool_size,
        uint amount
    )
        internal
        pure
        returns (uint /* delta */)
    {
        uint old_balance;
        if (info.old_lp_supply > 0) {
            old_balance = old_pool_size.mul(info.old_lp_amount).div(info.old_lp_supply);
        }
        uint new_balance = old_pool_size.add(amount).mul(info.new_lp_amount).div(info.new_lp_supply);
        return new_balance.sub(old_balance);
    }

    function _calcWithdrawDelta(
        LPShareInfo memory info,
        uint old_pool_size,
        uint amount
    )
        internal
        pure
        returns (uint /* delta */)
    {
        uint old_balance = old_pool_size.mul(info.old_lp_amount).div(info.old_lp_supply);
        uint new_balance;
        if (info.new_lp_supply > 0) {
            new_balance = old_pool_size.sub(amount).mul(info.new_lp_amount).div(info.new_lp_supply);
        }
        return old_balance.sub(new_balance);
    }
}
