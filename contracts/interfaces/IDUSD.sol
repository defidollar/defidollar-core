pragma solidity 0.5.17;

interface IDUSD {
    function mint(address account, uint amount) external;
    function burn(address account, uint amount) external;
    function totalSupply() external view returns(uint);
    function burnForSelf(uint amount) external;
}
