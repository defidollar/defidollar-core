const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");
const DUSD = artifacts.require("DUSD");
const Reserve = artifacts.require("Reserve");

// Stream
const Comptroller = artifacts.require("Comptroller");
const ibDUSDProxy = artifacts.require("ibDUSDProxy");
const ibDUSD = artifacts.require("ibDUSD");
const ibDFDProxy = artifacts.require("ibDFDProxy");
const ibDFD = artifacts.require("ibDFD");
const DFDComptroller = artifacts.require("DFDComptrollerTest");

// Peaks
const MockSusdToken = artifacts.require("MockSusdToken");
const YVaultPeak = artifacts.require("YVaultPeak");
const YVaultPeakTest2 = artifacts.require("YVaultPeakTest2");
const YVaultPeakProxy = artifacts.require("YVaultPeakProxy");
const YVaultZap = artifacts.require("YVaultZapTest");
const Controller = artifacts.require("Controller");
const MockYvault = artifacts.require("MockYvault");

const n_coins = 5
const toBN = web3.utils.toBN
const fromWei = web3.utils.fromWei

async function getArtifacts() {
	const [ coreProxy, dusd, ibDusdProxy, ibDfdProxy ] = await Promise.all([
		CoreProxy.deployed(),
		DUSD.deployed(),
		ibDUSDProxy.deployed(),
		ibDFDProxy.deployed()
	])
	const [ core, ibDusd, ibDfd ] = await Promise.all([
		Core.at(coreProxy.address),
		ibDUSD.at(ibDusdProxy.address),
		ibDFD.at(ibDfdProxy.address)
	])
    const reserves = []
	const decimals = []
	const scaleFactor = []
    for (let i = 0; i < n_coins; i++) {
        reserves.push(await Reserve.at((await core.systemCoins(i))))
		decimals.push(await reserves[i].decimals())
		scaleFactor.push(toBN(10 ** decimals[i]))
    }
    const res = {
		core,
		dusd,
		dfd: await Reserve.at(await ibDfd.dfd()),
		ibDusd,
		ibDfd,
		reserves,
		decimals,
		scaleFactor,

		ibDfdComptroller: await DFDComptroller.deployed(),
		comptroller: await Comptroller.deployed(),
		yVaultPeak: await YVaultPeak.at(YVaultPeakProxy.address),
		yVaultZap: await YVaultZap.deployed(),
		yVault: await MockYvault.deployed()
	}

	const { _yCrv, _controller } = await res.yVaultPeak.vars()
	res.yCrv = await MockSusdToken.at(_yCrv)
	res.controller = await Controller.at(_controller)
	return res
}

async function swapToMockYvault() {
	const yVaultPeakProxy = await YVaultPeakProxy.deployed()
	const yVaultPeakTest2 = await YVaultPeakTest2.new()
	await yVaultPeakProxy.updateImplementation(yVaultPeakTest2.address)
	return YVaultPeakTest2.at(YVaultPeakProxy.address)
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
	if (vals.stakeLPTokenSupply) {
		assert.equal((await artifacts.stakeLPToken.totalSupply()).toString(), vals.stakeLPTokenSupply)
	}
	if (vals.rewardPerTokenStored) {
		assert.equal((await artifacts.stakeLPToken.rewardPerTokenStored()).toString(), vals.rewardPerTokenStored)
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
	swapToMockYvault,
	scale,
	increaseBlockTime,
	mineOneBlock,
	printDebugReceipt,
	assertions,
	print,
	ZERO_ADDRESS: '0x0000000000000000000000000000000000000000'
}
