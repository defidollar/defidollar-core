const fs = require('fs');
const assert = require('assert')

const Core = artifacts.require("Core");
const CoreProxy = artifacts.require("CoreProxy");
const DUSD = artifacts.require("DUSD");
const Reserve = artifacts.require("Reserve");
const Oracle = artifacts.require("Oracle");
const Aggregator = artifacts.require("MockAggregator");
const StakeLPTokenProxy = artifacts.require("StakeLPTokenProxy");
const StakeLPToken = artifacts.require("StakeLPToken");
const CurveSusdPeak = artifacts.require("CurveSusdPeak");
const CurveSusdPeakProxy = artifacts.require("CurveSusdPeakProxy");
const MockSusdToken = artifacts.require("MockSusdToken");
const ICurve = artifacts.require("ICurve");
const ICurveDeposit = artifacts.require("ICurveDeposit");

const data = JSON.parse(
    fs.readFileSync(`${process.cwd()}/archive-data-aug-min.json`).toString()
)

const fromWei = web3.utils.fromWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);
const n_coins = 4

async function execute() {
    const [ alice, bob ] = await web3.eth.getAccounts()
    const _artifacts = await getArtifacts()
    Object.assign(this, _artifacts)

    let tasks = []
    let amount = '1000000000' // 1B
    for (let i = 0; i < n_coins; i++) {
        amount = toBN(amount).mul(toBN(10 ** this.decimals[i]))
        tasks = tasks.concat([
            this.reserves[i].mint(alice, amount),
            this.reserves[i].approve(this.curveSusd.address, MAX),
            this.reserves[i].mint(bob, amount),
            this.reserves[i].approve(this.curveSusdPeak.address, MAX, { from: bob })
        ])
    }
    await Promise.all(tasks)

    tasks = []
    let blockNums = Object.keys(data) // .slice(0, 100)
    // const start = blockNums.findIndex(b => b > parseInt('10571000'))
    const start = blockNums.findIndex(b => b > parseInt('10571200')) //10571264
    // blockNums = blockNums.slice(start, start+100)
    let percentAvgDeficit = 0, deficit0 = 0, netIncome = toBN(0), avgApy = toBN(0), percentAvgValueForMoney = 0
    for (let i = 0; i < blockNums.length; i+=30) {
        console.log(`Processing ${blockNums[i]}`)
        const _data = data[blockNums[i]]
        // set oracle price
        tasks.push(
            this.ethAggregator.setLatestAnswer(_data[0])
        )
        for(let j = 1; j <= 4; j++) {
            tasks.push(
                this.aggregators[j-1].setLatestAnswer(_data[j])
            )
        }

        // set curve balance
        tasks.push(this.curveToken.setTotalSupply(_data[5]))

        tasks.push(
            this.curveSusd.mock_set_balance(_data.slice(6))
        )
        await Promise.all(tasks)

        // gather system state
        const { deficit } = await this.core.currentSystemState()
        const { periodIncome } = await this.core.lastPeriodIncome()
        // await this.core.syncSystem()
        await this.stakeLPToken.updateProtocolIncome()

        // mint dusd
        const bal = await this.dusd.balanceOf(bob)
        const feed = await this.curveSusdPeak.oracleFeed()
        const mintAmounts = []
        let dollarValue = toBN(0), amount
        for (let i = 0; i < n_coins; i++) {
            amount = toBN(getRandomInt(25))
            dollarValue = dollarValue.add(amount.mul(toBN(feed[i])))
            mintAmounts.push(amount.mul(this.scaleFactor[i]))
        }
        await this.curveSusdPeak.mint(mintAmounts, '0', { from: bob })

        // aggregate stats
        const dusdMinted = (await this.dusd.balanceOf(bob)).sub(bal)
        const valueForMoney = parseFloat(fromWei(scale(dusdMinted, 20).div(dollarValue)))
        percentAvgValueForMoney += valueForMoney
        const totalAssets = await this.core.totalAssets()
        const dusdSupply = await this.dusd.totalSupply()
        netIncome = netIncome.add(periodIncome)
        let apy
        if (i) {
            apy = periodIncome
                .mul(toBN(10 ** 2))
                .mul(toBN(365*24*60*60))
                .div(dusdSupply)
                .div(
                    toBN((blockNums[i] - blockNums[i-30]) * 15)
                )
            avgApy = avgApy.add(apy)
        }
        // avgApy += parseFloat(fromWei()
        // %age deficit
        percentAvgDeficit += parseFloat(fromWei(deficit.mul(toBN(10 ** 20)).div(await this.dusd.totalSupply())))
        if (deficit.toString() == '0') {
            deficit0++
        }
        console.log({
            oracleFeed: (await this.oracle.getPriceFeed()).map(a => (parseFloat(fromWei(toBN(a).mul(toBN(1000)))/1000))),
            feed: feed.map(a => (parseFloat(fromWei(toBN(a).mul(toBN(1000)))/1000))),
            totalAssets: fromWei(totalAssets),
            dusdSupply: fromWei(dusdSupply),
            dollarValue: fromWei(dollarValue),
            valueForMoney,
            deficit: fromWei(deficit),
            percentDeficit: fromWei(deficit.mul(toBN(10 ** 20)).div(totalAssets)),
            pricePerCoin: fromWei(totalAssets.mul(toBN(10 ** 18)).div(dusdSupply)),
            periodIncome: fromWei(periodIncome),
            apy: apy ? apy.toString() : 0
        })
        if (i && deficit.toString() == '0') {
            assert.ok(periodIncome.gt(toBN(0)), 'Deficit / period income mismatch')
        }
    }
    console.log({
        blocksProcessed: blockNums.length,
        percentAvgValueForMoney: percentAvgValueForMoney / blockNums.length,
        netIncome: fromWei(netIncome),
        avgApy: avgApy.div(toBN(blockNums.length-1)).toString(),
        percentAvgDeficit: percentAvgDeficit / blockNums.length,
        deficit0
    })
}

async function getArtifacts() {
    const coreProxy = await CoreProxy.deployed()
    const core = await Core.at(coreProxy.address)
    const dusd = await DUSD.deployed()
    const oracle = await Oracle.deployed()
    const reserves = []
	const decimals = []
	const scaleFactor = []
	const aggregators = []
    for (let i = 0; i < n_coins; i++) {
        reserves.push(await Reserve.at((await core.systemCoins(i))))
		decimals.push(await reserves[i].decimals())
		scaleFactor.push(toBN(10 ** decimals[i]))
		aggregators.push(await Aggregator.at(await oracle.refs(i)))
    }
	const stakeLPTokenProxy = await StakeLPTokenProxy.deployed()
	const curveSusdPeakProxy = await CurveSusdPeakProxy.deployed()
    const res = {
        core,
        dusd,
        reserves,
		decimals,
		scaleFactor,
		aggregators,
		ethAggregator: await Aggregator.at(await oracle.ethUsdAggregator()),
		oracle,
        stakeLPToken: await StakeLPToken.at(stakeLPTokenProxy.address),

        curveSusdPeak: await CurveSusdPeak.at(curveSusdPeakProxy.address),
        curveToken: await MockSusdToken.deployed(),
	}
	const { _curveDeposit, _curve } = await res.curveSusdPeak.deps()
	res.curveSusd = await ICurve.at(_curve)
	res.curveDeposit = await ICurveDeposit.at(_curveDeposit)
	return res
}

function scale(num, decimals) {
	return toBN(num).mul(toBN(10).pow(toBN(decimals)))
}

function getRandomInt(max) {
    return Math.floor(Math.random() * Math.floor(max));
}

module.exports = async function (callback) {
    try {
        await execute()
    } catch (e) {
        // truffle exec <script> doesn't throw errors, so handling it in a verbose manner here
        console.log(e)
    }
    callback()
}
