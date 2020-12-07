pragma solidity 0.5.17;

interface IComptroller {
    function harvest() external;
    function earned(address) external view returns(uint);
}

interface IDFDComptroller {
    function getReward() external;
    function availableReward() external view returns(uint);
}
