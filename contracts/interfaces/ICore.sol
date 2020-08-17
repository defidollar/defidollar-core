pragma solidity 0.5.17;

interface ICore {
    function mint(uint dusdAmount, address account) external returns(uint usd);
    function redeem(uint dusdAmount, address account) external returns(uint usd);
    function rewardDistributionCheckpoint(bool shouldDistribute) external returns(uint periodIncome);

    function lastPeriodIncome() external view returns(uint _totalAssets, uint periodIncome);
    function usdToDusd(uint usd) external view returns(uint);
    function dusdToUsd(uint _dusd, bool fee) external view returns(uint usd);
}
