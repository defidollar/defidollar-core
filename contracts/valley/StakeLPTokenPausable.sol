pragma solidity 0.5.17;

import {Ownable} from "../common/Ownable.sol";
import "./StakeLPToken.sol";

contract StakeLPTokenPausable is StakeLPToken, Ownable {
    modifier updateReward(address account) {
        require(isActive(), "Staking is paused");
        rewardPerTokenStored = updateProtocolIncome();
        emit RewardPerTokenUpdated(rewardPerTokenStored, block.timestamp);
        if (account != address(0)) {
            rewards[account] = _earned(rewardPerTokenStored, account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function isActive() public view returns(bool) {
        if (getStore(0) == 0) {
            return true;
        }
        return false;
    }

    function toggleIsActive(uint status) external onlyOwner {
        require(status <= 1, "Invalid value");
        setStore(0, status);
    }
}
