pragma solidity 0.5.17;

interface ICore {
    function mint(uint dusdAmount, address account) external returns(uint usd);
    function redeem(uint dusdAmount, address account) external returns(uint usd);
    // function rewardDistributionCheckpoint(bool shouldDistribute) external returns(uint periodIncome);

    // function lastPeriodIncome() external view returns(uint _totalAssets, uint _periodIncome, uint _adminFee);
    // function currentSystemState() external view returns (uint _totalAssets, uint _deficit, uint _deficitPercent);
    function dusdToUsd(uint _dusd, bool fee) external view returns(uint usd);
}
