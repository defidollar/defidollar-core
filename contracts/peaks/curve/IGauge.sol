pragma solidity 0.5.17;

interface IGauge {
    function deposit(uint) external;
    function balanceOf(address) external view returns (uint);
    function claimable_tokens(address) external view returns (uint);
    function claimable_reward(address) external view returns (uint);
    function withdraw(uint, bool) external;
    function claim_rewards() external;
}

interface IMintr {
    function mint(address) external;
}
