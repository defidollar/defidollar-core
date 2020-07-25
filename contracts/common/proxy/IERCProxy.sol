pragma solidity 0.5.17;

interface IERCProxy {
    function proxyType() external pure returns (uint proxyTypeId);
    function implementation() external view returns (address codeAddr);
}
