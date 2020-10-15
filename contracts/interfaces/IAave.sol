pragma solidity 0.5.17;

interface IaToken {
    function redeem(uint256 _amount) external;
    function redirectInterestStream(address _to) external;
    function redirectInterestStreamOf(address _from, address _to) external;
    function allowInterestRedirectionTo(address _to) external;
}

interface ILendingpool {
    function deposit(address _reserve, uint256 _amouny, uint16 _referralCode) external;
    function getReserveData(address _reserve) external;
}

interface ILendingPoolAddressProvider {
    function getLendingPool() external;
    function getLendingPoolCore() external;
}
