pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import {IPeak} from "../../interfaces/IPeak.sol";
// Aave interface (aTokens)
// Balancer interface (BPool)

import {Initializable} from "../../common/Initializable.sol";
import {OwnableProxy} from "../../common/OwnableProxy.sol";

contract DaisUSDPeak is OwnableProxy, Initializable, IPeak {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using Math for uint;

    /**
    Initialises BPool, Controller and aTokens
    */
    function initialize() public {

    }

    /**
    Migrates aDAI/aSUSD to BPool
    Optional: Transfers BPT to Controller address
    */
    function joinPool() external {

    }

    /**
    Removes aDAI/aSUSD from BPool
    Withdraws BPT from controller + Burns
    */
    function exitPool() external {

    }

}