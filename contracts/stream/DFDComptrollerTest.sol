pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IComptroller} from "../interfaces/IComptroller.sol";
import {DFDComptroller} from "./DFDComptroller.sol";

contract DFDComptrollerTest is DFDComptroller {
    uint public travelled;

    function increaseBlockTime(uint duration) public {
        travelled = travelled.add(duration);
    }

    function _timestamp() internal view returns (uint) {
        return block.timestamp.add(travelled);
    }

    function timestamp() public view returns (uint) {
        return _timestamp();
    }

    function setParams(
        address _bal,
        IERC20 _dfd,
        IERC20 _dusd,
        IComptroller _comptroller
    )
        external
    {
        bal = _bal;
        dfd = _dfd;
        dusd = _dusd;
        comptroller = _comptroller;
    }
}
