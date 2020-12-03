pragma solidity 0.5.17;

interface ICore {
    function mint(uint dusdAmount, address account) external returns(uint usd);
    function redeem(uint dusdAmount, address account) external returns(uint usd);
    function harvest() external;

    function earned() external view returns(uint);
    function dusdToUsd(uint _dusd, bool fee) external view returns(uint usd);
    function peaks(address peak) external view returns (uint,uint,uint8);
}
