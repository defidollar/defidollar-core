pragma solidity 0.5.17;

interface IPeak {
    function updateFeed(uint[] calldata feed) external returns(uint portfolio);
    function portfolioValueWithFeed(uint[] calldata feed) external view returns(uint);
    function portfolioValue() external view returns(uint);
}
