pragma solidity 0.5.17;

import "./Reserve.sol";

contract MockAToken is Reserve {
    constructor (string memory _name, string memory _symbol)
        public
        Reserve(_name, _symbol, 18)
    {
    }

    function mint(address account, uint256 amount) public returns (bool) {
        _mint(account, amount);
        return true;
    }

    function redirectInterestStream(address) external {}
}
