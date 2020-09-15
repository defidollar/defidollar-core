pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {ICurveDeposit} from "../../interfaces/ICurve.sol";
import {YVaultPeak} from "./YVaultPeak.sol";

contract YVaultZap {
    using SafeERC20 for IERC20;

    uint constant N_COINS = 4;
    string constant ERR_SLIPPAGE = "ERR_SLIPPAGE";

    uint[N_COINS] ZEROES = [uint(0),uint(0),uint(0),uint(0)];
    address[N_COINS] underlyingCoins = [
        0x6B175474E89094C44Da98b954EedeAC495271d0F, // dai
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // usdc
        0xdAC17F958D2ee523a2206206994597C13D831ec7, // usdt
        0x0000000000085d4780B73119b644AE5ecd22b376 // tusd
    ];

    ICurveDeposit yDeposit = ICurveDeposit(0xbBC81d23Ea2c3ec7e56D39296F0cbB648873a5d3);
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
        address[N_COINS] memory coins = underlyingCoins;
        for (uint i = 0; i < N_COINS; i++) {
            if (inAmounts[i] > 0) {
                IERC20(coins[i]).safeTransferFrom(msg.sender, address(this), inAmounts[i]);
                IERC20(coins[i]).safeApprove(address(yDeposit), inAmounts[i]);
            }
        }
        yDeposit.add_liquidity(inAmounts, 0);
        uint inAmount = yCrv.balanceOf(address(this));
        yCrv.safeApprove(address(yVaultPeak), inAmount);
        dusdAmount = yVaultPeak.mintWithYcrv(inAmount);
        require(dusdAmount >= minDusdAmount, ERR_SLIPPAGE);
        dusd.safeTransfer(msg.sender, dusdAmount);
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
        dusd.safeTransferFrom(msg.sender, address(this), dusdAmount);
        uint r = yVaultPeak.redeemInYcrv(dusdAmount, 0);
        yCrv.safeApprove(address(yDeposit), r);
        yDeposit.remove_liquidity_one_coin(r, int128(i), minOut); // checks for slippage
        IERC20 coin = IERC20(underlyingCoins[i]);
        uint toTransfer = coin.balanceOf(address(this));
        coin.safeTransfer(msg.sender, toTransfer);
    }
}
