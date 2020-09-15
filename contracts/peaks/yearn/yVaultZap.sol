pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {ICurveDeposit} from "../../interfaces/ICurve.sol";
import {YVaultPeak} from "./YVaultPeak.sol";

contract yVaultZap {
    using SafeERC20 for IERC20;

    uint constant N_COINS = 4;
    string constant ERR_SLIPPAGE = "They see you slippin";

    uint[N_COINS] ZEROES = [uint(0),uint(0),uint(0),uint(0)];
    address[N_COINS] underlyingCoins;

    ICurveDeposit yDeposit;
    IERC20 yUsd;
    IERC20 dusd;
    YVaultPeak yVaultPeak;

    constructor(
        ICurveDeposit _yDeposit,
        IERC20 _yUsd,
        IERC20 _dusd,
        YVaultPeak _yVaultPeak
    ) public {
        yDeposit = _yDeposit;
        yUsd = _yUsd;
        dusd = _dusd;
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
            }
        }
        yDeposit.add_liquidity(inAmounts, 0);
        uint inAmount = yUsd.balanceOf(address(this));
        yUsd.safeApprove(address(yVaultPeak), 0);
        yUsd.safeApprove(address(yVaultPeak), inAmount);
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
        yDeposit.remove_liquidity_one_coin(r, int128(i), minOut); // checks for slippage
        IERC20 coin = IERC20(underlyingCoins[i]);
        uint toTransfer = coin.balanceOf(address(this));
        coin.safeTransfer(msg.sender, toTransfer);
    }
}