pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICurve} from "../../interfaces/ICurve.sol";
import {ICore} from "../../interfaces/ICore.sol";
import {YVaultPeak} from "./YVaultPeak.sol";

contract YVaultPeakTest is YVaultPeak {
    function setDeps(ICore _core, ICurve _ySwap, IERC20 _yCrv, IERC20 _yUSD)
        public
    {
        core = _core;
        ySwap = _ySwap;
        yCrv = _yCrv;
        yUSD = _yUSD;
    }
}