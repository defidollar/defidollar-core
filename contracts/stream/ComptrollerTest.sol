pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ICore} from "../interfaces/ICore.sol";
import {Comptroller} from "./Comptroller.sol";

contract ComptrollerTest is Comptroller {
    function setParams(
        IERC20 _dusd,
        ICore _core
    )
        external
    {
        dusd = _dusd;
        core = _core;
    }
}
