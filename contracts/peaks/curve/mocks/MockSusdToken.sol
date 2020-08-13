pragma solidity 0.5.17;

import {Reserve} from "../../../common/mocks/Reserve.sol";

contract MockSusdToken is Reserve {
    constructor ()
        public
        Reserve("crvPlain3andSUSD", "crvPlain3andSUSD", 18)
    {
    }

    function burnFrom(address account, uint amount) public {
        _burn(account, amount);
    }
}
