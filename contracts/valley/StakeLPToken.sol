pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {Core} from "../base/Core.sol";
import {Initializable} from "../common/Initializable.sol";

contract LPTokenWrapper {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IERC20 public stok;

    uint public totalSupply;
    mapping(address => uint) private _balances;

    function balanceOf(address account) public view returns (uint) {
        return _balances[account];
    }

    function stake(uint amount) public {
        totalSupply = totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        stok.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint amount) public {
        totalSupply = totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        stok.safeTransfer(msg.sender, amount);
    }
}

contract StakeLPToken is Initializable, LPTokenWrapper {
    Core public core;

    uint public timeWeightedRewardPerToken;
    uint public rewardPerTokenStored;
    uint public lastUpdate;
    uint public lastIncomeUpdate;
    uint public deficit;

    mapping(address => uint) public userRewardPerTokenPaid;
    mapping(address => uint) public rewards;

    event Staked(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount);
    event RewardPaid(address indexed user, uint reward);

    modifier onlyCore() {
        require(
            msg.sender == address(core),
            "Not authorized"
        );
        _;
    }

    function initialize(Core _core, IERC20 _stok) public notInitialized {
        core = _core;
        stok = _stok;
        lastUpdate = timestamp();
    }

    modifier updateReward(address account) {
        updateRewardPerTokenForCurrentWindow();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function updateRewardPerTokenForCurrentWindow() internal {
        timeWeightedRewardPerToken = rewardPerTokenForCurrentWindow();
        lastUpdate = timestamp();
    }

    function rewardPerTokenForCurrentWindow() public view returns (uint) {
        if (totalSupply == 0) {
            return timeWeightedRewardPerToken;
        }
        return
            timeWeightedRewardPerToken.add(
                timestamp()
                    .sub(lastUpdate)
                    .mul(1e36)
                    .div(totalSupply)
            );
    }

    function earned(address account) public view returns (uint) {
        return
            balanceOf(account)
                .mul(rewardPerTokenStored.sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        if (totalSupply == 0) {
            lastUpdate = timestamp();
        }
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        require(amount <= withdrawAble(msg.sender), "Funds are illiquid");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function withdrawAble(address account) public view returns(uint) {
        uint _withdrawAble = balanceOf(account);
        if (totalSupply == 0 || deficit == 0) {
            return _withdrawAble;
        }
        uint deficitShare = _withdrawAble.mul(deficit).div(totalSupply);
        if (deficitShare >= _withdrawAble) {
            return 0;
        }
        return _withdrawAble.sub(deficitShare);
    }

    function exit() external {
        withdraw(withdrawAble(msg.sender));
        getReward();
    }

    function getReward() public updateReward(msg.sender) {
        uint reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            core.mintReward(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    event DebugUint(uint indexed a);
    function notifyProtocolIncome(uint reward) external onlyCore {
        updateRewardPerTokenForCurrentWindow();
        // if timestamp() == lastIncomeUpdate, that means there were multiple updates in a single block
        // and we are ok with letting that revert
        emit DebugUint(timeWeightedRewardPerToken);
        emit DebugUint(rewardPerTokenStored);
        emit DebugUint(timestamp().sub(lastIncomeUpdate));
        rewardPerTokenStored = rewardPerTokenStored.add(
            timeWeightedRewardPerToken
                .mul(reward)
                .div(timestamp().sub(lastIncomeUpdate))
                .div(1e18)
        );
        emit DebugUint(rewardPerTokenStored);
        timeWeightedRewardPerToken = 0;
        lastIncomeUpdate = timestamp();
    }

    function notify(uint _deficit) external onlyCore {
        deficit = _deficit;
    }

    function timestamp() internal view returns(uint) {
        return block.timestamp;
    }
}
