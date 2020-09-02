pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IGauge} from "../IGauge.sol";

contract Gauge is IGauge {
    using SafeMath for uint;

    IERC20 scrv;

    constructor(IERC20 _scrv) public {
        scrv = _scrv;
    }

    mapping(address => uint) balances;

    function deposit(uint amount) external {
        scrv.transferFrom(msg.sender, address(this), amount);
        balances[msg.sender] = balances[msg.sender].add(amount);
    }

    function balanceOf(address) external view returns (uint) {
        return balances[msg.sender];
    }

    function withdraw(uint amount, bool) external {
        balances[msg.sender] = balances[msg.sender].sub(amount);
        scrv.transfer(msg.sender, amount);
    }

    function claimable_tokens(address) external view returns (uint) {}
    function claimable_reward(address) external view returns (uint) {}
    function claim_rewards() external {}
}
