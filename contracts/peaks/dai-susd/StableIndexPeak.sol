pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import {IPeak} from "../../interfaces/IPeak.sol";
import {Iatoken} from "../../interfaces/IAave.sol";
import {IConfigurableRightsPool} from "../../interfaces/IConfigurableRightsPool.sol";

import {Initializable} from "../../common/Initializable.sol";
import {OwnableProxy} from "../../common/OwnableProxy.sol";

contract StableIndexPeak is OwnableProxy, Initializable, IPeak {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using Math for uint;

    // aTokens
    IaToken aDAI;
    IaToken aSUSD;

    // Configurable Rights Pool
    IConfigurableRightsPool crp;

    function initialize(
        IConfigurableRightsPool _crp
    ) public {
        // aTokens
        aDAI = IaToken(0xfC1E690f61EFd961294b3e1Ce3313fBD8aa4f85d); // mainnet
        aSUSD = IaToken(0x625aE63000f46200499120B906716420bd059240); // mainnet
        // CRP
        crp = _crp;
    }

    function joinBPool() external {
        /** 
        
        */
    }

    function exitBPool() external {

    }

    /** 
    Migrates BPT to controller address
    */
    function migrateBPT() external {

    }

    /** 
    mint dusd with aTokens
    */
    function mintWithaTokens() external returns {
        
    }

}
