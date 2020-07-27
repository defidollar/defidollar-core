pragma solidity 0.5.17;

import "./StakeLPToken.sol";

contract StakeLPTokenTest is StakeLPToken {
    uint public time;

    function timestamp() internal view returns(uint) {
        return time;
    }

    function setTime(uint add) public {
        time += add;
    }
}
