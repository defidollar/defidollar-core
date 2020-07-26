const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");
const DUSD = artifacts.require("DUSD");
const Reserve = artifacts.require("Reserve");
const Oracle = artifacts.require("Oracle");
const Aggregator = artifacts.require("MockAggregator");
const StakeLPTokenProxy = artifacts.require("StakeLPTokenProxy");
const StakeLPToken = artifacts.require("StakeLPToken");
const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const MockSusdToken = artifacts.require("MockSusdToken");
const MockCurveSusd = artifacts.require("MockCurveSusd");

const n_coins = 4
const toBN = web3.utils.toBN

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

async function getBlockTime(tx) {
	const block = await web3.eth.getBlock(tx.receipt.blockNumber)
	return block.timestamp.toString()
}

function printDebugReceipt(r) {
	r.receipt.rawLogs.forEach(l => {
		if (l.topics[0] == '0x8a36f5a234186d446e36a7df36ace663a05a580d9bea2dd899c6dd76a075d5fa') {
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
}

module.exports = {
	getArtifacts,
	scale,
	increaseBlockTime,
	mineOneBlock,
	printDebugReceipt,
	getBlockTime,
	assertions
}
