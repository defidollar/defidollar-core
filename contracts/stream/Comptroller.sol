pragma solidity 0.5.17;

import {Ownable} from "@openzeppelin/contracts/ownership/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {ICore} from "../interfaces/ICore.sol";

import {IComptroller} from "../interfaces/IComptroller.sol";

contract Comptroller is Ownable, IComptroller {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    uint constant MAX = 10000;

    address[] public beneficiaries;
    uint[] public allocations;

    IERC20 public dusd;
    ICore public core;

    event Harvested(uint indexed revenue);

    constructor(IERC20 _dusd, ICore _core) public {
        dusd = _dusd;
        core = _core;
    }

    /**
    * @notice Harvests all accrued income from core and transfers it to beneficiaries
    * @dev All beneficiaries should account for that fact that they can have dusd transferred to them at any time
    * @dev Any account call harvest
    */
    function harvest() external {
        // address(this) needs to be the authorizedController() in core
        core.harvest();

        // any extraneous dusd tokens in the contract will also be harvested
        uint revenue = dusd.balanceOf(address(this));
        emit Harvested(revenue);
        if (revenue > 0) {
            for (uint i = 0; i < beneficiaries.length; i++) {
                dusd.safeTransfer(beneficiaries[i], revenue.mul(allocations[i]).div(MAX));
            }
        }
    }

    function earned(address account) external view returns(uint) {
        uint revenue = dusd.balanceOf(address(this)).add(core.earned());
        if (revenue > 0) {
            for (uint i = 0; i < beneficiaries.length; i++) {
                if (beneficiaries[i] == account) {
                    return revenue.mul(allocations[i]).div(MAX);
                }
            }
        }
        return 0;
    }

    /* ##### Admin ##### */

    function addBeneficiary(
        address beneficiary,
        uint[] calldata _allocations
    )
        external
        onlyOwner
    {
        require(beneficiary != address(0x0), "ZERO_ADDRESS");
        beneficiaries.push(beneficiary);
        modifyAllocation(_allocations);
    }

    function modifyAllocation(
        uint[] memory _allocations
    )
        public
        onlyOwner
    {
        require(beneficiaries.length == _allocations.length, "MALFORMED_INPUT");
        uint total = 0;
        for (uint i = 0; i < _allocations.length; i++) {
            total = total.add(_allocations[i]);
        }
        require(total == MAX, "INVALID_ALLOCATIONS");
        allocations = _allocations;
    }
}
