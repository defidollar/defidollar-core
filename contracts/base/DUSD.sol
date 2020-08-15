pragma solidity 0.5.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Detailed} from "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";

contract DUSD is ERC20, ERC20Detailed {
    address public core;

    constructor(address _core, string memory _name, string memory _symbol, uint8 _decimals)
        public
        ERC20Detailed(_name, _symbol, _decimals)
    {
        core = _core;
    }

    modifier onlyCore() {
        require(msg.sender == core, "Not authorized");
        _;
    }

    function mint(address account, uint amount) public onlyCore {
        _mint(account, amount);
    }

    function burn(address account, uint amount) public onlyCore {
        _burn(account, amount);
    }

    function burnForSelf(uint amount) external {
        _burn(msg.sender, amount);
    }
}
