const assert = require('assert')
const utils = require('../utils.js')

const toWei = web3.utils.toWei
const fromWei = web3.utils.fromWei
const toBN = web3.utils.toBN
const n_coins = 4
let _artifacts

contract('Rewards flow', async (accounts) => {
	const alice = accounts[0]
	const bob = accounts[1]
	const SCALE_18 = utils.scale(1, 18)

	before(async () => {
		_artifacts = await utils.getArtifacts()
        Object.assign(this, _artifacts)
		this.amounts = [1, 2, 3, 4].map((n, i) => {
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
	})

	beforeEach(async () => {
		await this.stakeLPToken.setTime(3)
		// await utils.print(_artifacts)
	})

	it('alice mints 10 (CurveSusdPeak)', async () => {
		await utils.assertions({ dusdTotalSupply: '0' }, _artifacts)

		const tasks = []
		for (let i = 0; i < n_coins; i++) {
			tasks.push(this.reserves[i].mint(alice, this.amounts[i]))
			tasks.push(this.reserves[i].approve(this.curveSusdPeak.address, this.amounts[i]))
		}
		await Promise.all(tasks)
		await this.curveSusdPeak.mint(this.amounts, toWei('10'))

		const dusd_balance = await this.dusd.balanceOf(alice)
		assert.equal(dusd_balance.toString(), toWei('10'))
		assert.equal((await this.curveToken.balanceOf(this.curveSusdPeak.address)).toString(), toWei('10'))
		await utils.assertions({ dusdTotalSupply: toWei('10') }, _artifacts)
	})

	it('bob mints 10 (CurveSusdPeak)', async () => {
		const tasks = []
		const from = bob
		for (let i = 0; i < n_coins; i++) {
			tasks.push(this.reserves[i].mint(from, this.amounts[i]))
			tasks.push(this.reserves[i].approve(this.curveSusdPeak.address, this.amounts[i], { from }))
		}
		await Promise.all(tasks)
		await this.curveSusdPeak.mint(this.amounts, toWei('10'), { from })

		this.dusd_balance = await this.dusd.balanceOf(from)
		assert.equal(this.dusd_balance.toString(), toWei('10'))
		assert.equal((await this.curveToken.balanceOf(this.curveSusdPeak.address)).toString(), toWei('20'))
		await utils.assertions({ dusdTotalSupply: toWei('20') }, _artifacts)
	})

	it('alice stakes 4', async () => {
		await utils.assertions({
			dusdTotalSupply: toWei('20'),
			dusdStaked: '0',
			stakeLPToken_supply: '0',
			timeWeightedRewardPerToken: '0',
			rewardPerTokenStored: '0'
		}, _artifacts)

		const stake_amount = toWei('4')

		await this.dusd.approve(this.stakeLPToken.address, stake_amount)
		const stakeTx = await this.stakeLPToken.stake(stake_amount)

		const dusd_bal = await this.dusd.balanceOf(alice)
		assert.equal(dusd_bal.toString(), toWei('6')) // 10 - 4

		const bal = await this.stakeLPToken.balanceOf(alice)
		assert.equal(bal.toString(), stake_amount)

		const earned = await this.stakeLPToken.earned(alice)
		assert.equal(earned.toString(), '0')

		await utils.assertions({
			dusdTotalSupply: toWei('20'),
			dusdStaked: stake_amount,
			stakeLPToken_supply: stake_amount,
			timeWeightedRewardPerToken: '0',
			rewardPerTokenStored: '0'
		}, _artifacts)
		this.lastUpdate = await this.stakeLPToken.lastUpdate()
		assert.equal(
			this.lastUpdate.toString(),
			(await utils.getBlockTime(_artifacts.stakeLPToken)).toString()
		)
	})

	it('CurveSusdPeak accrues income=4', async () => {
		this.protocolIncome = utils.scale(4, 18)
		const income = [1, 1, 1, 1].map((n, i) => {
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
		const tasks = []
		for (let i = 0; i < n_coins; i++) {
			tasks.push(this.reserves[i].mint(this.mockCurveSusd.address, income[i]))
		}
		await Promise.all(tasks)
	})

	it('sync system', async () => {
		this.lastIncomeUpdate = await this.stakeLPToken.lastIncomeUpdate()

		const s = await this.core.syncSystem()
		const now = await utils.getBlockTime(_artifacts.stakeLPToken)

		const incomeWindow = now - parseInt(this.lastIncomeUpdate.toString(), 10)
		const rewardRate = this.protocolIncome.div(toBN(incomeWindow))
		const stakeWindow = now - parseInt(this.lastUpdate.toString(), 10)

		console.log({ incomeWindow, stakeWindow })

		this.timeWeightedRewardPerToken = utils.scale(stakeWindow, 36).div(utils.scale(4, 18))
		console.log(this.timeWeightedRewardPerToken.toString())
		this.rewardPerTokenStored = this.timeWeightedRewardPerToken
			.mul(this.protocolIncome)
			.div(toBN(incomeWindow))
			.div(SCALE_18)
		// this.timeWeightedRewardPerToken.mul(rewardRate).div(SCALE_18)
		await utils.assertions({
			dusdTotalSupply: toWei('20'),
			dusdStaked: toWei('4'),
			stakeLPToken_supply: toWei('4'),
			timeWeightedRewardPerToken: '0', // has been reset
			rewardPerTokenStored: this.rewardPerTokenStored.toString(),
		}, _artifacts)
		this.lastUpdate = await this.stakeLPToken.lastUpdate()
		assert.equal(this.lastUpdate.toString(), now.toString())
	})

	it('alice has earned', async () => {
		this.aliceReward = await this.stakeLPToken.earned(alice)
		assert.equal(
			this.aliceReward.toString(),
			toBN(4).mul(this.rewardPerTokenStored).toString() // alice's balance=4
		)
	})

	it('bob stakes=6', async () => {
		const stake_amount = toWei('6')
		const from = bob
		await this.dusd.approve(this.stakeLPToken.address, stake_amount, { from })
		const s = await this.stakeLPToken.stake(stake_amount, { from })
		const now = await utils.getBlockTime(_artifacts.stakeLPToken)

		const dusd_bal = await this.dusd.balanceOf(bob)
		assert.equal(dusd_bal.toString(), toWei('4')) // 10 - 6

		const bal = await this.stakeLPToken.balanceOf(bob)
		assert.equal(bal.toString(), stake_amount)

		const window = now - parseInt(this.lastUpdate.toString(), 10)
		// just before Bob stakes, supply was 4
		this.timeWeightedRewardPerToken = utils.scale(window, 18).div(toBN(4))
		console.log({ window })
		await this.assertions({
			dusdTotalSupply: toWei('20'),
			dusdStaked: toWei('10'),
			stakeLPToken_supply: toWei('10'),
			timeWeightedRewardPerToken: this.timeWeightedRewardPerToken.toString(),
			rewardPerTokenStored: this.rewardPerTokenStored.toString() // didn't change
		})

		let earned = await this.stakeLPToken.earned(bob)
		assert.equal(earned.toString(), '0')

		this.lastUpdate = await this.stakeLPToken.lastUpdate()
		assert.equal(this.lastUpdate.toString(), now.toString())
	})

	it('reward', async () => {
		let a = await this.stakeLPToken.earned(alice)
		let b = await this.stakeLPToken.earned(bob)
		console.log({
			alice: fromWei(a),
			bob: fromWei(b),
			aliceReward: fromWei(this.aliceReward),
		})
	})

	it('Alice claims reward', async () => {
		this.aliceRewardPerTokenPaid = await this.stakeLPToken.userRewardPerTokenPaid(alice)
		assert.equal(this.aliceRewardPerTokenPaid.toString(), '0')

		this.aliceRewards = await this.stakeLPToken.rewards(alice)
		assert.equal(this.aliceRewards.toString(), '0')

		const s = await this.stakeLPToken.getReward()

		console.log({ reward: this.aliceReward.toString() })

		const now = await utils.getBlockTime(_artifacts.stakeLPToken)
		let dusd_bal = await this.dusd.balanceOf(alice)
		assert.equal(dusd_bal.toString(), utils.scale(6, 18).add(this.aliceReward).toString())

		const bal = await this.stakeLPToken.balanceOf(alice)
		assert.equal(bal.toString(), toWei('4')) // original staked amount

		earned = await this.stakeLPToken.earned(alice)
		assert.equal(earned.toString(), '0')

		this.aliceRewardPerTokenPaid = await this.stakeLPToken.userRewardPerTokenPaid(alice)
		assert.equal(this.aliceRewardPerTokenPaid.toString(), this.rewardPerTokenStored)
		console.log({
			aliceRewardPerTokenPaid: fromWei(this.aliceRewardPerTokenPaid),
			bobRewardPerTokenPaid: fromWei(await this.stakeLPToken.userRewardPerTokenPaid(bob)),
		})
		this.aliceRewards = await this.stakeLPToken.rewards(alice)
		assert.equal(this.aliceRewards.toString(), '0')

		const window = now - parseInt(this.lastUpdate.toString(), 10)
		this.timeWeightedRewardPerToken = this.timeWeightedRewardPerToken.add(utils.scale(window, 18).div(toBN(10))) // totalSupply=10
		console.log({
			window,
			time: fromWei(utils.scale(window, 18).div(toBN(10))),
		})
		this.dusdTotalSupply = utils.scale(20, 18).add(this.aliceReward)
		await utils.assertions({
			dusdTotalSupply: this.dusdTotalSupply.toString(),
			dusdStaked: toWei('10'),
			stakeLPToken_supply: toWei('10'),
			timeWeightedRewardPerToken: this.timeWeightedRewardPerToken.toString(),
			rewardPerTokenStored: this.rewardPerTokenStored.toString(), // didn't change
		}, _artifacts)
		this.lastUpdate = await this.stakeLPToken.lastUpdate()
		assert.equal(this.lastUpdate.toString(), now.toString())
	})

	it('CurveSusdPeak accrues income=6', async () => {
		this.assertions({ totalAssets: toWei('24'), totalAssets: toWei('24') })

		this.reward = toBN(6)
		const income = [2, 1, 1, 2].map((n, i) => { // 5 tokens
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
		const tasks = []
		for (let i = 0; i < n_coins; i++) {
			tasks.push(this.reserves[i].mint(this.mockCurveSusd.address, income[i]))
		}
		await Promise.all(tasks)

		this.assertions({
			totalSystemAssets: toWei('30'),
			totalAssets: toWei('24') // only updates on notifyProtocolIncomeAndDeficit
		})
	})

	it('update system stats', async () => {
		this.lastIncomeUpdate = await this.stakeLPToken.lastIncomeUpdate()
		this.lastOverCollateralizationAmount = await this.core.lastOverCollateralizationAmount()
		// this.lastOverCollateralizationAmount = await overCollateralizationAmount(this.core, this.dusd)
		// console.log(this.lastOverCollateralizationAmount.toString())

		const s = await this.core.notifyProtocolIncomeAndDeficit()
		utils.printDebugReceipt(s)

		this.overCollateralizationAmount = await overCollateralizationAmount(this.core, this.dusd)
		// this.incomeDuringPeriod = this.overCollateralizationAmount.sub(this.lastOverCollateralizationAmount)
		this.incomeDuringPeriod = this.overCollateralizationAmount.sub(utils.scale(4, 18))
		console.log({
			lastOverCollateralizationAmount: fromWei(this.lastOverCollateralizationAmount),
			overCollateralizationAmount: fromWei(this.overCollateralizationAmount),
			incomeDuringPeriod: fromWei(this.incomeDuringPeriod)
		})

		const now = await utils.getBlockTime(_artifacts.stakeLPToken)
		const incomeWindow = now - parseInt(this.lastIncomeUpdate.toString(), 10)
		const stakeWindow = now - parseInt(this.lastUpdate.toString(), 10)
		console.log({ incomeWindow, stakeWindow })
		const timeWeightedRewardPerToken = this.timeWeightedRewardPerToken.add(
			utils.scale(stakeWindow, 18).div(toBN(10))) // totalSupply=10
		this.rewardPerTokenStored = this.rewardPerTokenStored.add(
			timeWeightedRewardPerToken
			.mul(this.incomeDuringPeriod)
			.div(toBN(incomeWindow))
			.div(SCALE_18)
		)
		await this.assertions({
			dusdTotalSupply: this.dusdTotalSupply,
			dusdStaked: toWei('10'),
			stakeLPToken_supply: toWei('10'),
			timeWeightedRewardPerToken: '0', // has been reset
			rewardPerTokenStored: this.rewardPerTokenStored.toString(),
			lastOverCollateralizationAmount: this.overCollateralizationAmount.toString(),
			totalSystemAssets: toWei('30'),
			totalAssets: toWei('30')
		})
		this.lastUpdate = await this.stakeLPToken.lastUpdate()
		assert.equal(this.lastUpdate.toString(), now.toString())

		this.lastIncomeUpdate = await this.stakeLPToken.lastIncomeUpdate()
		assert.equal(this.lastIncomeUpdate.toString(), now.toString())
	})

	it('alice exits', async () => {
		const reward = await this.stakeLPToken.rewards(alice)
		const userRewardPerTokenPaid = await this.stakeLPToken.userRewardPerTokenPaid(alice)
		const rewardPerTokenStored = await this.stakeLPToken.rewardPerTokenStored()
		const earned = await this.stakeLPToken.earned(alice)
		console.log({
			reward_alice: fromWei(reward),
			reward_bob: fromWei(await this.stakeLPToken.rewards(bob)),
			userRewardPerTokenPaid_alice: fromWei(userRewardPerTokenPaid),
			rewardPerTokenStored: fromWei(rewardPerTokenStored),
			earned_alice: fromWei(earned),
			earned_bob: fromWei(await this.stakeLPToken.earned(bob)),
			// incomeDuringPeriod_alice: fromWei(this.incomeDuringPeriod.mul(toBN(4)).div(toBN(10))),
		})
		// await this.stakeLPToken.exit()
		// const bal = await this.dusd.balanceOf(alice)
		// 10 + this.aliceReward + this.incomeDuringPeriod*4/10
		// const expectedBalance = utils.scale(10, 18).add(this.aliceReward).add(this.incomeDuringPeriod.div(toBN(4)))
		// console.log(expectedBalance.toString(), bal.toString())
	})

	this.assertions = (vals) => {
		return utils.assertions(vals, _artifacts)
	}
})

async function overCollateralizationAmount(core, dusd) {
	const totalAssets = await core.totalAssets()
	const supply = await dusd.totalSupply()
	return totalAssets.sub(supply)
}
