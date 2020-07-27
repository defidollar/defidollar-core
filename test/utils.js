const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");
const DUSD = artifacts.require("DUSD");
const Reserve = artifacts.require("Reserve");
const Oracle = artifacts.require("Oracle");
const Aggregator = artifacts.require("MockAggregator");
const StakeLPTokenProxy = artifacts.require("StakeLPTokenProxy");
const StakeLPToken = artifacts.require("StakeLPTokenTest");
const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const MockSusdToken = artifacts.require("MockSusdToken");
const MockCurveSusd = artifacts.require("MockCurveSusd");

const n_coins = 4
const toBN = web3.utils.toBN
const fromWei = web3.utils.fromWei

async function getArtifacts() {
    const coreProxy = await CoreProxy.deployed()
    const core = await Core.at(coreProxy.address)
    const dusd = await DUSD.deployed()
    const oracle = await Oracle.deployed()
    const reserves = []
	const decimals = []
	const aggregators = []
    for (let i = 0; i < n_coins; i++) {
        reserves.push(await Reserve.at((await core.systemCoins(i)).token))
		decimals.push(await reserves[i].decimals())
		aggregators.push(await Aggregator.at(await oracle.refs(i)))
    }
    const stakeLPTokenProxy = await StakeLPTokenProxy.deployed()
    return {
        core,
        dusd,
        reserves,
		decimals,
		aggregators,
        stakeLPToken: await StakeLPToken.at(stakeLPTokenProxy.address),

        curveSusdPeak: await CurveSusdPeak.deployed(),
        curveToken: await MockSusdToken.deployed(),
        mockCurveSusd: await MockCurveSusd.deployed()
    }
}

function scale(num, decimals) {
	return toBN(num).mul(toBN(10).pow(toBN(decimals)))
}

async function increaseBlockTime(seconds) {
	await web3.currentProvider.send(
		{
			jsonrpc: '2.0',
			method: 'evm_increaseTime',
			params: [seconds],
			id: new Date().getTime()
		},
		() => {}
	)
	return mineOneBlock()
}

function mineOneBlock() {
	return web3.currentProvider.send(
		{
			jsonrpc: '2.0',
			method: 'evm_mine',
			id: new Date().getTime()
		},
		() => {}
	)
}

async function getBlockTime(stakeLPToken) {
	return stakeLPToken.time()
	// const block = await web3.eth.getBlock(tx.receipt.blockNumber)
	// return block.timestamp.toString()
}

function printDebugReceipt(r) {
	// console.log(r)
	r.receipt.rawLogs.forEach(l => {
		// keccak256('DebugUint(uint256)')
		if (l.topics[0] == '0xf0ed029e274dabb7636aeed7333cf47bc8c97dd6eb6d8faea6e9bfbd6620bebe') {
			console.log(toBN(l.topics[1].slice(2), 'hex').toString())
		}
	})
}

async function assertions(vals, artifacts) {
	if (vals.totalSystemAssets) {
		const totalSystemAssets = await artifacts.core.totalSystemAssets()
		assert.equal(totalSystemAssets.toString(), vals.totalSystemAssets)
	}
	if (vals.totalAssets) {
		const totalAssets = await artifacts.core.totalAssets()
		assert.equal(totalAssets.toString(), vals.totalAssets)
	}
	if (vals.deficit) {
		const deficit = await artifacts.stakeLPToken.deficit()
		assert.equal(deficit.toString(), vals.deficit)
	}
	if (vals.dusdTotalSupply) {
		assert.equal((await artifacts.dusd.totalSupply()).toString(), vals.dusdTotalSupply)
	}
	if (vals.dusdStaked) {
		assert.equal((await artifacts.dusd.balanceOf(artifacts.stakeLPToken.address)).toString(), vals.dusdStaked)
	}
	if (vals.stakeLPToken_supply) {
		assert.equal((await artifacts.stakeLPToken.totalSupply()).toString(), vals.stakeLPToken_supply)
	}
	if (vals.timeWeightedRewardPerToken) {
		assert.equal((await artifacts.stakeLPToken.timeWeightedRewardPerToken()).toString(), vals.timeWeightedRewardPerToken)
	}
	if (vals.rewardPerTokenStored) {
		assert.equal((await artifacts.stakeLPToken.rewardPerTokenStored()).toString(), vals.rewardPerTokenStored)
	}
	if (vals.lastOverCollateralizationAmount) {
		assert.equal((await artifacts.core.lastOverCollateralizationAmount()).toString(), vals.lastOverCollateralizationAmount)
	}
}

async function print(artifacts, options = {}) {
	const vals = {
		totalSystemAssets: fromWei(await artifacts.core.totalSystemAssets()),
		totalAssets: fromWei(await artifacts.core.totalAssets()),
		dusdSupply: fromWei(await artifacts.dusd.totalSupply()),
		dusdStaked: fromWei(await artifacts.dusd.balanceOf(artifacts.stakeLPToken.address)),
		lastOverCollateralizationAmount: fromWei(await artifacts.core.lastOverCollateralizationAmount()),

		stakeLPTokenSupply: fromWei(await artifacts.stakeLPToken.totalSupply()),
		timeWeightedRewardPerToken: fromWei(await artifacts.stakeLPToken.timeWeightedRewardPerToken()),
		rewardPerTokenStored: fromWei(await artifacts.stakeLPToken.rewardPerTokenStored()),
		lastIncomeUpdate: (await artifacts.stakeLPToken.lastIncomeUpdate()).toString(),
		lastUpdate: (await artifacts.stakeLPToken.lastUpdate()).toString()
	}
	if (options.now) {
		vals.incomeWindow = now - parseInt(vals.lastIncomeUpdate, 10),
		vals.stakeWindow = now - parseInt(vals.lastUpdate, 10)
	}
	console.log(vals)
}

module.exports = {
	getArtifacts,
	scale,
	increaseBlockTime,
	mineOneBlock,
	printDebugReceipt,
	getBlockTime,
	assertions,
	print
}
