pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {ICore} from "../interfaces/ICore.sol";
import {IDUSD} from "../interfaces/IDUSD.sol";
import {Initializable} from "../common/Initializable.sol";


contract LPTokenWrapper {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IERC20 public dusd;

    uint public totalSupply;
    mapping(address => uint) private _balances;

    function balanceOf(address account) public view returns (uint) {
        return _balances[account];
    }

    function stake(uint amount) public {
        totalSupply = totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        dusd.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint amount) public {
        totalSupply = totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
    }
}

contract StakeLPToken is Initializable, LPTokenWrapper {
    ICore public core;

    uint public rewardPerTokenStored;
    uint public deficit;

    mapping(address => uint) public userRewardPerTokenPaid;
    mapping(address => uint) public rewards;

    event Staked(address indexed user, uint indexed amount);
    event Withdrawn(address indexed user, uint indexed amount);
    event RewardPaid(address indexed user, uint indexed reward);
    event RewardPerTokenUpdated(uint indexed rewardPerToken, uint indexed when);

    modifier onlyCore() {
        require(
            msg.sender == address(core),
            "Not authorized"
        );
        _;
    }

    function initialize(ICore _core, IERC20 _dusd)
        public
        notInitialized
    {
        core = _core;
        dusd = _dusd;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = updateProtocolIncome();
        emit RewardPerTokenUpdated(rewardPerTokenStored, block.timestamp);
        if (account != address(0)) {
            rewards[account] = _earned(rewardPerTokenStored, account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function updateProtocolIncome() public returns(uint) {
        bool shouldDistribute;
        if (totalSupply > 0) {
            shouldDistribute = true;
        }
        uint income = core.rewardDistributionCheckpoint(true);
        // uint income = core.rewardDistributionCheckpoint(shouldDistribute);
        return _rewardPerToken(income);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint amount) public updateReward(msg.sender) {
        _withdraw(amount);
    }

    function exit() external {
        getReward();
        _withdraw(balanceOf(msg.sender));
    }

    function getReward() public updateReward(msg.sender) {
        uint reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            // this contract had received the reward tokens during the call to core.rewardDistributionCheckpoint()
            dusd.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function notify(uint _deficit) external onlyCore {
        deficit = _deficit;
    }

    // View Functions
    function earned(address account) public view returns (uint) {
        (,uint income,) = core.lastPeriodIncome();
        return _earned(_rewardPerToken(income), account);
    }

    function withdrawAble(address account) public view returns(uint) {
        (,uint _deficit) = core.currentSystemState();
        uint balance = balanceOf(account);
        if (totalSupply == 0 || _deficit == 0) {
            return balance;
        }
        uint deficitShare = balance.mul(_deficit).div(totalSupply);
        if (deficitShare >= balance) {
            return 0;
        }
        return balance.sub(deficitShare);
    }

    // Internal functions
    function _earned(uint _rewardPerTokenStored, address account) internal view returns(uint) {
        return
            balanceOf(account)
                .mul(_rewardPerTokenStored.sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    function _rewardPerToken(uint income) internal view returns(uint) {
        if (totalSupply == 0 || income == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored.add(
            income
            .mul(1e18)
            .div(totalSupply)
        );
    }

    function _withdraw(uint amount) internal {
        if (amount == 0) {
            // there might be case where user has 0 staked funds, but called getReward()
            return;
        }
        uint deficitShare = amount.mul(deficit).div(totalSupply);
        super.withdraw(amount);
        if (deficitShare > 0) {
            if (deficitShare < amount) {
                amount = amount.sub(deficitShare);
            } else {
                deficitShare = amount;
                amount = 0;
            }
            // burning user's deficitShare will reduce the overall deficit in the system,
            // since dusd.totalSupply() decreases
            IDUSD(address(dusd)).burnForSelf(deficitShare);
            deficit = deficit.sub(deficitShare);
        }
        if (amount > 0) {
            dusd.safeTransfer(msg.sender, amount);
        }
    }
}
