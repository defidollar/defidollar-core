pragma solidity 0.5.17;

interface ICore {
    function mint(uint usdDelta, address account) external returns (uint dusdAmount);
    function redeem(uint dusdAmount, address account) external returns(uint usd);
    function usdToDusd(uint usd) external view returns(uint);
    function dusdToUsd(uint _dusd, bool fee) external view returns(uint usd);
    function rewardDistributionCheckpoint() external returns(uint);
    function mintReward(address account, uint usdDelta) external;
    function lastPeriodIncome() external view returns(uint _totalAssets, uint periodIncome);
}
