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
    fs.readFileSync(`${process.cwd()}/archive-data-aug.json`).toString()
)

const fromWei = web3.utils.fromWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);
const n_coins = 4
let alice, bob

async function execute() {
    const accounts = await web3.eth.getAccounts()
    alice = accounts[0]
    bob = accounts[1]
    const _artifacts = await getArtifacts()
    Object.assign(this, _artifacts)

    // Initialize coins for alice, bob
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
    tasks.push(this.dusd.approve(this.stakeLPToken.address, MAX, { from: bob }))
    await Promise.all(tasks)

    tasks = []
    let blockNums = Object.keys(data).slice(1)
    let percentAvgDeficit = 0, deficit0 = 0, netIncome = toBN(0), percentAvgValueForMoney = 0
    const increment = 1
    for (let i = 0; i < blockNums.length; i+=increment) {
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

        // set curve balances
        tasks.push(setCurveBalances(_data.slice(6).map(toBN), _artifacts))
        await Promise.all(tasks)

        let res = {}
        if (i) {
            // gather system state, after the price updates
            const dusdSupply = toBN(await this.dusd.totalSupply())
            const { _totalAssets: totalAssets, _deficit: deficit, _deficitPercent } = await this.core.currentSystemState()
            console.log({ totalAssets: totalAssets.toString(), deficit: deficit.toString() })
            const deficitPercent = parseFloat(fromWei(scale(_deficitPercent, 13)))
            percentAvgDeficit += deficitPercent
            if (deficit.toString() == '0') {
                deficit0++
            }

            const { _periodIncome: periodIncome } = await this.core.lastPeriodIncome()
            netIncome = netIncome.add(periodIncome)
            let apy = periodIncome
                .mul(toBN(10 ** 20)) // %
                .mul(toBN(31536000)) // 365*24*60*60 seconds
                .div(dusdSupply) // consider all is staked
                .div(
                    toBN((blockNums[i] - blockNums[i-increment]) * 15) // time since last processed block
                )

            res = {
                dusdSupply: fromWei(dusdSupply),
                totalAssets: fromWei(totalAssets),
                deficit: fromWei(deficit),
                percentDeficit: fromWei(deficit.mul(toBN(10 ** 20)).div(totalAssets)),
                // pricePerCoin: fromWei(totalAssets.mul(toBN(10 ** 18)).div(dusdSupply)),
                periodIncome: fromWei(periodIncome),
                apy: apy ? parseFloat(fromWei(apy)) : 0,
                unclaimedRewards: fromWei(await this.core.unclaimedRewards())
            }
            // if (deficit.toString() == '0') {
            //     assert.ok(periodIncome.gt(toBN(0)), 'if deficit is 0, period income > 0') // well mostly
            // }
        }

        await this.stakeLPToken.updateProtocolIncome() // syncs system as well

        // mint dusd
        const { _feed: feed } = await this.curveSusdPeak.vars()
        const mintAmounts = []
        let dollarValue = toBN(0), amount
        for (let i = 0; i < n_coins; i++) {
            amount = toBN(getRandomInt(2500))
            dollarValue = dollarValue.add(amount.mul(toBN(feed[i])))
            mintAmounts.push(amount.mul(this.scaleFactor[i]))
        }
        await this.curveSusdPeak.mint(mintAmounts, '0', { from: bob })
        const dusdMinted = await this.dusd.balanceOf(bob)
        await this.stakeLPToken.stake(dusdMinted, { from: bob }) // stake all

        // aggregate stats
        const valueForMoney = parseFloat(fromWei(scale(dusdMinted, 20).div(dollarValue)))
        percentAvgValueForMoney += valueForMoney

        Object.assign(res, {
            // oracleFeed: feed.map(a => (parseFloat(fromWei(toBN(a).mul(toBN(1000)))/1000))),
            oracleFeed: (await this.oracle.getPriceFeed()).map(a => (parseFloat(fromWei(toBN(a).mul(toBN(1000)))/1000))),
            feed: feed.map(a => (parseFloat(fromWei(toBN(a).mul(toBN(1000)))/1000))),
            // scrv: fromWei(await this.curveSusdPeak.sCrvBalance()),

            // // user stats
            // dusdMinted: fromWei(dusdMinted),
            // dollarValue: fromWei(dollarValue),
            valueForMoney,
        })

        // agg stats
        let netApy = toBN(0)
        const time = (parseInt(blockNums[i]) - parseInt(blockNums[0])) * 15
        if (time) {
            netApy = (await this.stakeLPToken.rewardPerTokenStored())
                .mul(toBN(10 ** 2)) // %
                .mul(toBN(31536000)) // 365*24*60*60 seconds
                .div(toBN(time))
        }

        const blocksProcessed = (i+1) / increment
        Object.assign(res, {
            blocksProcessed,
            percentAvgValueForMoney: percentAvgValueForMoney / blocksProcessed,
            netIncome: fromWei(netIncome),
            netApy: parseFloat(fromWei(netApy)),
            percentAvgDeficit: percentAvgDeficit / blocksProcessed,
            deficit0
        })
        console.log(res)
    }
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
	const { _curveDeposit, _curve } = await res.curveSusdPeak.vars()
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

async function setCurveBalances(targetBals, _artifacts) {
    // console.log(fromWei(await _artifacts.curveToken.balanceOf(alice)))
    // console.log(fromWei(await _artifacts.curveToken.totalSupply()))
    const add = [0,0,0,0], remove = [0,0,0,0]
    let shouldAdd = false, shouldRemove = false
    for (let i = 0; i < targetBals.length; i++) {
        const bal = toBN(await _artifacts.reserves[i].balanceOf(_artifacts.curveSusd.address))
        if (bal.gt(targetBals[i])) {
            remove[i] = bal.sub(targetBals[i])
            shouldRemove = true
        } else if (bal.lt(targetBals[i])) {
            add[i] = targetBals[i].sub(bal)
            shouldAdd = true
        }
    }
    if (shouldAdd) {
        await _artifacts.curveSusd.add_liquidity(add, '0')
    }
    if (shouldRemove) {
        await _artifacts.curveSusd.remove_liquidity_imbalance(remove, MAX)
    }
    // console.log(fromWei(await _artifacts.curveToken.balanceOf(alice)))
    // console.log(fromWei(await _artifacts.curveToken.totalSupply()))
}

/** Notes
- Income suddenly increases at block 10570300
 *
*/
