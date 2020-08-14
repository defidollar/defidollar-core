pragma solidity 0.5.17;

interface IOracle {
    function getPriceFeed() external view returns(uint[] memory);
}
