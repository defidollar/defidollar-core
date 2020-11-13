pragma solidity 0.5.17;

import { LendingPool, aToken } from "../../../interfaces/IAave.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockAToken } from "../../../common/mocks/MockAToken.sol";
import { SafeERC20, SafeMath } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract MockLendingPool is LendingPool {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    mapping(address => address) public lendingPools;

    // Deposit reserve => aToken
    function deposit(address _reserve, uint256 _amount, uint16 /*_refferalCode*/) public {
        // Transfer reserve
        IERC20(_reserve).safeTransferFrom(msg.sender, address(this), _amount);
        // Mint aToken
        // MockAToken().mint(msg.sender, _amount);
    }

}
