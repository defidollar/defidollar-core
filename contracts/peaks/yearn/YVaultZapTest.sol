pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ICurve,ICurveDeposit} from "../../interfaces/ICurve.sol";
import {YVaultZap} from "./YVaultZap.sol";
import {YVaultPeak} from "./YVaultPeak.sol";

contract YVaultZapTest is YVaultZap {
    constructor (YVaultPeak _yVaultPeak) public YVaultZap(_yVaultPeak) {}

    function setDeps(
        ICurveDeposit _yDeposit,
        ICurve _ySwap,
        IERC20 _yCrv,
        IERC20 _dusd,
        address[N_COINS] memory _underlyingCoins,
        address[N_COINS] memory _coins
    ) public {
        yDeposit = _yDeposit;
        ySwap = _ySwap;
        yCrv = _yCrv;
        dusd = _dusd;
        underlyingCoins = _underlyingCoins;
        coins = _coins;
    }
}
