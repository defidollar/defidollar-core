pragma solidity 0.5.17;

interface IConfigurableRightsPool {
    function joinPool(uint poolAmountout, uint[] calldata maxAmountsIn) external;
    function exitPool(uint poolAmountIn, uint[] calldata minAmountsOut) external;
    function getDenormalizedWeight(address token) external view returns (uint);
    function getNormalizedWeight(address token) external view returns (uint);
}

interface IBPool {
    function isBound(address token) external view returns(bool);
    function getBalance(address token) external view returns (uint);
    function rebind(address token, uint balance, uint denorm) external;
    function setSwapFee(uint swapFee) external;
    function bind(address token, uint balance, uint denorm) external;
    function getDenormalizedWeight(address token) external view returns (uint);
    function getNormalizedWeight(address token) external view returns (uint);
    function getTotalDenormalizedWeight() external view returns (uint);
    function setPublicSwap(bool public_) external;
    function getCurrentTokens() external view returns (address[] memory tokens);
    function calcPoolOutGivenSingleIn(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint poolSupply,
        uint totalWeight,
        uint tokenAmountIn,
        uint swapFee
    )
        external pure
        returns (uint poolAmountOut);

    function calcSingleInGivenPoolOut(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint poolSupply,
        uint totalWeight,
        uint poolAmountOut,
        uint swapFee
    )
        external pure
        returns (uint tokenAmountIn);

    function calcSingleOutGivenPoolIn(
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint poolSupply,
        uint totalWeight,
        uint poolAmountIn,
        uint swapFee
    )
        external pure
        returns (uint tokenAmountOut);

    function calcPoolInGivenSingleOut(
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint poolSupply,
        uint totalWeight,
        uint tokenAmountOut,
        uint swapFee
    )
        external pure
        returns (uint poolAmountIn);

    function swapExactAmountOut(
        address tokenIn,
        uint maxAmountIn,
        address tokenOut,
        uint tokenAmountOut,
        uint maxPrice
    )
        external
        returns (uint tokenAmountIn, uint spotPriceAfter);

    function swapExactAmountIn(
        address tokenIn,
        uint tokenAmountIn,
        address tokenOut,
        uint minAmountOut,
        uint maxPrice
    )
        external
        returns (uint tokenAmountOut, uint spotPriceAfter);
}
