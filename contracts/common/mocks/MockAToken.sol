pragma solidity 0.5.17;

import "./Reserve.sol";

contract MockAToken is Reserve {
    constructor (string memory _name, string memory _symbol)
        public
        Reserve(_name, _symbol, 18)
    {
    }

    function redirectInterestStream(address) external {}
}
