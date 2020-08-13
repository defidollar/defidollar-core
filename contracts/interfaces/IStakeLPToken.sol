pragma solidity 0.5.17;

interface IStakeLPToken {
    function notify(uint _deficit) external;
    function totalSupply() external view returns(uint);
}
