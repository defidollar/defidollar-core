pragma solidity 0.5.17;

contract MockAggregator {
	int256 _latestAnswer;

	function latestAnswer() external view returns (int256) {
		return _latestAnswer;
	}

	function setLatestAnswer(int256 la) public {
		_latestAnswer = la;
	}
}
