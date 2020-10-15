pragma soldity 0.5.17;

interface IConfigurableRightsPool {
    function joinPool(uint poolAmountout, uint[] calldata maxAmountsIn) external;
    function exitPool(uint poolAmountIn, uint[] calldata minAmountsOut) external;
}
