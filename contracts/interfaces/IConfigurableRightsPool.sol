pragma solidity 0.5.17;

interface IConfigurableRightsPool {
    function joinPool(uint poolAmountout, uint[] calldata maxAmountsIn) external;
    function exitPool(uint poolAmountIn, uint[] calldata minAmountsOut) external;
    function getDenormalizedWeight(address token) external view returns (uint);
    function getNormalizedWeight(address token) external view returns (uint);
}
