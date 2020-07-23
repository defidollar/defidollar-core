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

    address[N_COINS] public underlying_coins;

    ICurveDeposit curve_deposit; // deposit contract
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
        ICurveDeposit _curve_deposit,
        ICurve _curve,
        IERC20 _curveToken,
        Core _core,
        address[N_COINS] memory _underlying_coins
    )   public
        notInitialized
    {
        curve_deposit = _curve_deposit;
        curve = _curve;
        curveToken = _curveToken;
        core = _core;
        underlying_coins = _underlying_coins;
    }

    /**
    * @dev Mint DUSD
    * @param in_amounts Exact in_amounts in the same order as required by the curve pool
    * @param min_dusd_amount Minimum DUSD to mint, used for capping slippage
    */
    function mint(
        uint[] calldata in_amounts,
        uint min_dusd_amount
    ) external
        returns (uint dusd_amount)
    {
        address[N_COINS] memory coins = underlying_coins;
        uint[N_COINS] memory pool_sizes;

        for (uint i = 0; i < N_COINS; i++) {
            pool_sizes[i] = curve.balances(i);
            if (in_amounts[i] == 0) {
                continue;
            }
            IERC20(coins[i]).safeTransferFrom(msg.sender, address(this), in_amounts[i]);
        }

        LPShareInfo memory info;
        info.old_lp_amount = curveToken.balanceOf(address(this));
        info.old_lp_supply = curveToken.totalSupply();

        curve_deposit.add_liquidity(in_amounts, 0);

        info.new_lp_amount = curveToken.balanceOf(address(this));
        info.new_lp_supply = curveToken.totalSupply();

        uint[] memory delta = new uint[](N_COINS);
        for (uint i = 0; i < N_COINS; i++) {
            delta[i] = _calcDepositDelta(info, pool_sizes[i], in_amounts[i]);
        }
        return core.mint(delta, min_dusd_amount, msg.sender);
    }

    /**
    * @dev Burn DUSD
    * @param out_amounts Exact out_amounts in the same order as required by the curve pool
    * @param max_dusd_amount Max DUSD to burn, used for capping slippage
    */
    function redeem(
        uint[] calldata out_amounts,
        uint max_dusd_amount
    )
        external
        returns(uint dusd_amount)
    {
        uint[N_COINS] memory pool_sizes;
        for (uint i = 0; i < N_COINS; i++) {
            pool_sizes[i] = curve.balances(i);
        }

        LPShareInfo memory info;
        info.old_lp_amount = curveToken.balanceOf(address(this));
        info.old_lp_supply = curveToken.totalSupply();

        curve_deposit.remove_liquidity_imbalance(out_amounts, MAX);

        info.new_lp_amount = curveToken.balanceOf(address(this));
        info.new_lp_supply = curveToken.totalSupply();

        address[N_COINS] memory coins = underlying_coins;
        uint[] memory delta = new uint[](N_COINS);

        for (uint i = 0; i < N_COINS; i++) {
            IERC20(coins[i]).safeTransfer(msg.sender, out_amounts[i]);
            delta[i] = _calcWithdrawDelta(info, pool_sizes[i], out_amounts[i]);
        }
        return core.redeem(delta, max_dusd_amount, msg.sender);
    }

    // This is risky (Bancor Hack scenario). Think about if we need strict token approvals during the actions at the cost of higher gas.
    function replenish_approvals() external {
        curveToken.approve(address(curve_deposit), MAX);
        for (uint i = 0; i < N_COINS; i++) {
            IERC20(underlying_coins[i]).approve(address(curve_deposit), MAX);
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
    ) internal
        pure
        returns (uint /* delta */)
    {
        uint old_balance = old_pool_size.mul(info.old_lp_amount).div(info.old_lp_supply);
        uint new_balance;
        if (info.new_lp_supply > 0) {
            new_balance = old_pool_size.add(amount).mul(info.new_lp_amount).div(info.new_lp_supply);
        }
        return old_balance.sub(new_balance);
    }
}
