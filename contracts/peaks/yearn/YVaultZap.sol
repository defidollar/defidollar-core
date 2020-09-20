pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {ICurveDeposit, ICurve} from "../../interfaces/ICurve.sol";
import {YVaultPeak} from "./YVaultPeak.sol";

contract YVaultZap {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    uint constant N_COINS = 4;
    string constant ERR_SLIPPAGE = "ERR_SLIPPAGE";

    uint[N_COINS] ZEROES = [uint(0),uint(0),uint(0),uint(0)];
    address[N_COINS] coins = [
        0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01, // ydai
        0xd6aD7a6750A7593E092a9B218d66C0A814a3436e, // yusdc
        0x83f798e925BcD4017Eb265844FDDAbb448f1707D, // yusdt
        0x73a052500105205d34Daf004eAb301916DA8190f // ytusd
    ];
    address[N_COINS] underlyingCoins = [
        0x6B175474E89094C44Da98b954EedeAC495271d0F, // dai
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // usdc
        0xdAC17F958D2ee523a2206206994597C13D831ec7, // usdt
        0x0000000000085d4780B73119b644AE5ecd22b376 // tusd
    ];

    ICurveDeposit yDeposit = ICurveDeposit(0xbBC81d23Ea2c3ec7e56D39296F0cbB648873a5d3);
    ICurve ySwap = ICurve(0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51);
    IERC20 yCrv = IERC20(0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8);
    IERC20 dusd = IERC20(0x5BC25f649fc4e26069dDF4cF4010F9f706c23831);
    YVaultPeak yVaultPeak;

    constructor (YVaultPeak _yVaultPeak) public {
        yVaultPeak = _yVaultPeak;
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
        address[N_COINS] memory _coins = underlyingCoins;
        for (uint i = 0; i < N_COINS; i++) {
            if (inAmounts[i] > 0) {
                IERC20(_coins[i]).safeTransferFrom(msg.sender, address(this), inAmounts[i]);
                IERC20(_coins[i]).safeApprove(address(yDeposit), inAmounts[i]);
            }
        }
        yDeposit.add_liquidity(inAmounts, 0);
        uint inAmount = yCrv.balanceOf(address(this));
        yCrv.safeApprove(address(yVaultPeak), 0);
        yCrv.safeApprove(address(yVaultPeak), inAmount);
        dusdAmount = yVaultPeak.mintWithYcrv(inAmount);
        require(dusdAmount >= minDusdAmount, ERR_SLIPPAGE);
        dusd.safeTransfer(msg.sender, dusdAmount);
    }

    function calcMint(uint[N_COINS] memory inAmounts)
        public view
        returns (uint dusdAmount)
    {
        for(uint i = 0; i < N_COINS; i++) {
            inAmounts[i] = inAmounts[i].mul(1e18).div(yERC20(coins[i]).getPricePerFullShare());
        }
        uint _yCrv = ySwap.calc_token_amount(inAmounts, true /* deposit */);
        return yVaultPeak.calcMintWithYcrv(_yCrv);
    }

    /**
    * @dev Redeem DUSD
    * @param dusdAmount Exact dusdAmount to burn
    * @param minAmounts Min expected amounts to cap slippage
    */
    function redeem(uint dusdAmount, uint[N_COINS] calldata minAmounts)
        external
    {
        dusd.safeTransferFrom(msg.sender, address(this), dusdAmount);
        uint r = yVaultPeak.redeemInYcrv(dusdAmount, 0);
        yCrv.safeApprove(address(yDeposit), r);
        yDeposit.remove_liquidity(r, ZEROES);
        address[N_COINS] memory _coins = underlyingCoins;
        uint toTransfer;
        for (uint i = 0; i < N_COINS; i++) {
            toTransfer = IERC20(_coins[i]).balanceOf(address(this));
            require(toTransfer >= minAmounts[i], ERR_SLIPPAGE);
            IERC20(_coins[i]).safeTransfer(msg.sender, toTransfer);
        }
    }

    function calcRedeem(uint dusdAmount)
        public view
        returns (uint[N_COINS] memory amounts)
    {
        uint _yCrv = yVaultPeak.calcRedeemInYcrv(dusdAmount);
        uint totalSupply = yCrv.totalSupply();
        for(uint i = 0; i < N_COINS; i++) {
            amounts[i] = ySwap.balances(int128(i))
                .mul(_yCrv)
                .div(totalSupply)
                .mul(yERC20(coins[i]).getPricePerFullShare())
                .div(1e18);
        }
    }

    function redeemInSingleCoin(uint dusdAmount, uint i, uint minOut)
        external
    {
        dusd.safeTransferFrom(msg.sender, address(this), dusdAmount);
        uint r = yVaultPeak.redeemInYcrv(dusdAmount, 0);
        yCrv.safeApprove(address(yDeposit), r);
        yDeposit.remove_liquidity_one_coin(r, int128(i), minOut); // checks for slippage
        IERC20 coin = IERC20(underlyingCoins[i]);
        uint toTransfer = coin.balanceOf(address(this));
        coin.safeTransfer(msg.sender, toTransfer);
    }

    function calcRedeemInSingleCoin(uint dusdAmount, uint i)
        public view
        returns(uint)
    {
        uint _yCrv = yVaultPeak.calcRedeemInYcrv(dusdAmount);
        return yDeposit.calc_withdraw_one_coin(_yCrv, int128(i));
    }
}

interface yERC20 {
    function getPricePerFullShare() external view returns(uint);
}
