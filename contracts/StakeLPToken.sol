pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {Core} from "./Core.sol";

contract StakeLPToken is ERC20 {
  using SafeERC20 for IERC20;
  using SafeMath for uint;

  uint constant PRECISION = 1e18;

  IERC20 public stok;
  Core public core;

  uint income_last;

  uint public rewardPerTokenStored;
  mapping(address => uint256) public userRewardPerTokenPaid;
  mapping(address => uint256) public rewards;

  event Staked(address indexed user, uint256 amount);
  event Withdrawn(address indexed user, uint256 amount);
  event RewardPaid(address indexed user, uint256 reward);

  constructor(Core _core) public {
    core = _core;
  }

  modifier onlyCore() {
    require(msg.sender == address(core), "Only Core");
    _;
  }

  modifier updateReward(address account) {
    uint income_now = core.getProtocolIncome();
    rewardPerTokenStored = _rewardPerToken(income_now);
    income_last = income_now;
    if (account != address(0)) {
      rewards[account] = _earned(rewardPerTokenStored, account);
      userRewardPerTokenPaid[account] = rewardPerTokenStored;
    }
    _;
  }

  function stake(uint amount) external updateReward(msg.sender) {
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

  function exit() external {
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

  // Helper view functions
  function earned(address account)
    public view returns (uint256)
  {
    return _earned(_rewardPerToken(core.getProtocolIncome()), account);
  }

  // internal
  function _rewardPerToken(uint income_now)
    internal
    view
    returns (uint)
  {
    uint total_supply = totalSupply();
    if (total_supply == 0 || income_now <= income_last) {
      // No rewards accumulated if
      // 1. If no tokens were staked during a period
      // 2. The size of the income_now pool reduced (peg failure) from last time
      return rewardPerTokenStored;
    }
    return rewardPerTokenStored.add(
      income_now
      .sub(income_last)
      .mul(PRECISION)
      .div(total_supply)
    );
  }

  function _earned(uint rewardPerToken, address account)
    internal view returns (uint256)
  {
    return
      balanceOf(account)
        .mul(rewardPerToken.sub(userRewardPerTokenPaid[account]))
        .div(PRECISION)
        .add(rewards[account]);
  }
}
