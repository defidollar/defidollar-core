pragma solidity 0.5.17;

import {Reserve} from "../../../common/mocks/Reserve.sol";

contract MockSusdToken is Reserve {
    uint private _totalSupply;

    constructor ()
        public
        Reserve("crvPlain3andSUSD", "crvPlain3andSUSD", 18)
    {
    }

    function burnFrom(address account, uint amount) public {
        _burn(account, amount);
    }

    function totalSupply() public view returns(uint) {
        return _totalSupply;
    }

    function setTotalSupply(uint ts) public {
        _totalSupply = ts;
    }
}
