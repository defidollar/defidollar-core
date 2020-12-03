pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IController {
    function earn(address _token) external;
    function vaultWithdraw(IERC20 token, uint _shares) external;
    function withdraw(IERC20 token, uint amount) external;
    function getPricePerFullShare(address token) external view returns(uint);
}
