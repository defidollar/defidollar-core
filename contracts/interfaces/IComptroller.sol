pragma solidity 0.5.17;

interface IComptroller {
    function harvest() external;
    function earned() external view returns(uint);
}
