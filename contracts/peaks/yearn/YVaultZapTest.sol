pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ICurveDeposit} from "../../interfaces/ICurve.sol";
import {YVaultZap} from "./YVaultZap.sol";
import {YVaultPeak} from "./YVaultPeak.sol";

contract YVaultZapTest is YVaultZap {
    constructor (YVaultPeak _yVaultPeak) public YVaultZap(_yVaultPeak) {}

    function setDeps(
        ICurveDeposit _yDeposit,
        IERC20 _yCrv,
        IERC20 _dusd,
        address[N_COINS] memory _underlyingCoins
    ) public {
        yDeposit = _yDeposit;
        yCrv = _yCrv;
        dusd = _dusd;
        underlyingCoins = _underlyingCoins;
    }
}