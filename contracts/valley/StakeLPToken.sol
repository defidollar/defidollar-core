pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {Core} from "../base/Core.sol";
import {Initializable} from "../common/Initializable.sol";

contract LPTokenWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public stok;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        stok.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public {
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        stok.safeTransfer(msg.sender, amount);
    }
}

contract StakeLPToken is Initializable, LPTokenWrapper {
    Core public core;

    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint public timeWeightRewardPerToken;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    function initialize(Core _core, IERC20 _stok) public notInitialized {
        core = _core;
        stok = _stok;
        lastUpdateTime = block.timestamp;
    }

    modifier updateReward(address account) {
        timeWeightRewardPerToken = rewardPerTokenForCurrentWindow();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function rewardPerTokenForCurrentWindow() public view returns (uint256) {
        if (totalSupply() == 0) {
            return timeWeightRewardPerToken;
        }
        return
            timeWeightRewardPerToken.add(
                block.timestamp
                    .sub(lastUpdateTime)
                    .mul(1e36)
                    .div(totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerTokenStored.sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        if (totalSupply() == 0) {
            lastUpdateTime = block.timestamp;
        }
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function getReward() public updateReward(msg.sender) {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            core.mintReward(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function notifyProtocolIncomeAmount(uint rewardRate) public {
        timeWeightRewardPerToken = rewardPerTokenForCurrentWindow();
        rewardPerTokenStored = rewardPerTokenStored.add(timeWeightRewardPerToken.mul(rewardRate).div(1e18));
        timeWeightRewardPerToken = 0;
        lastUpdateTime = block.timestamp;
    }
}
