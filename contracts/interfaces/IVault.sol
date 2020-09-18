pragma solidity 0.5.17;

interface IVault {
    function deposit(uint) external;
    function withdraw(uint _shares) external;
    function getPricePerFullShare() external view returns (uint);
    function totalSupply() external view returns (uint);
    function balanceOf(address account) external view returns (uint);
}
