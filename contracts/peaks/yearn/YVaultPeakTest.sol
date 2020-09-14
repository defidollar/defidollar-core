pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ICurve} from "../../interfaces/ICurve.sol";
import {ICore} from "../../interfaces/ICore.sol";
import {IController} from "../../interfaces/IController.sol";

import {YVaultPeak} from "./YVaultPeak.sol";

contract YVaultPeakTest is YVaultPeak {
    function setDeps(ICore _core, ICurve _yPool, IERC20 _yUsd, IERC20 _yyCrv) public {
        core = _core;
        yPool = _yPool;
        yUsd = _yUsd;
        yyCrv = _yyCrv;
    }
}