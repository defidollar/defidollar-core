pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {Core} from "../base/Core.sol";

contract StakeLPToken is ERC20 {
  using SafeERC20 for IERC20;
  using SafeMath for uint;

  uint constant PRECISION = 1e18;

  IERC20 public stok;
  Core public core;

  uint income_diff;

  uint public rewardPerTokenStored;
  uint public unitRewardForCurrentFeeWindow;
  mapping(address => uint256) public userRewardPerTokenPaid;
  mapping(address => uint256) public rewards;

  event Staked(address indexed user, uint256 amount);
  event Withdrawn(address indexed user, uint256 amount);
  event RewardPaid(address indexed user, uint256 reward);

  constructor(Core _core, IERC20 _stok) public {
    core = _core;
    stok = _stok;
  }

  modifier onlyCore() {
    require(msg.sender == address(core), "Only Core");
    _;
  }

  modifier updateReward(address account) {
    if (account != address(0)) {
      rewards[account] = earned(account);
      userRewardPerTokenPaid[account] = rewardPerTokenStored;
    }
    _;
    update_unit_reward_for_current_fee_window(true);
  }

  function stake(uint amount) public updateReward(msg.sender) {
    require(amount > 0, "Cannot stake 0");
    stok.safeTransferFrom(msg.sender, address(this), amount);
    _mint(msg.sender, amount);
    emit Staked(msg.sender, amount);
  }

  function withdraw(uint256 amount) public updateReward(msg.sender) {
    require(amount > 0, "Cannot withdraw 0");
    _burn(msg.sender, amount);
    stok.safeTransfer(msg.sender, amount);
    emit Withdrawn(msg.sender, amount);
  }

  function exit() public {
    withdraw(balanceOf(msg.sender));
    getReward();
  }

  function getReward() public updateReward(msg.sender) {
    uint256 reward = rewards[msg.sender];
    if (reward > 0) {
      rewards[msg.sender] = 0;
      core.mintReward(msg.sender, reward);
      emit RewardPaid(msg.sender, reward);
    }
  }

  /**
  * @dev Difference of protocol income at 2 points
  */
  function update_income_diff(uint protocol_income) public onlyCore {
    if (protocol_income > income_diff) {
      income_diff = protocol_income.sub(income_diff);
      rewardPerTokenStored = rewardPerTokenStored.add(unitRewardForCurrentFeeWindow.mul(income_diff).div(PRECISION));
      update_unit_reward_for_current_fee_window(false);
    } else {
      income_diff = 0;
    }
  }

  function update_unit_reward_for_current_fee_window(bool accumulate) internal {
    uint total_supply = totalSupply();
    if (total_supply > 0) {
      if (!accumulate) {
        unitRewardForCurrentFeeWindow = 0;
      }
      unitRewardForCurrentFeeWindow = unitRewardForCurrentFeeWindow.add(PRECISION.mul(PRECISION).div(total_supply));
    } else {
      unitRewardForCurrentFeeWindow = 0;
    }
  }

  // View functions
  function earned(address account)
    public view returns (uint256)
  {
    return
      balanceOf(account)
        .mul(rewardPerTokenStored.sub(userRewardPerTokenPaid[account]))
        .div(PRECISION)
        .add(rewards[account]);
  }
}
