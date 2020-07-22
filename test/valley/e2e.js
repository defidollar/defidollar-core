const assert = require('assert')

const Core = artifacts.require("Core");
const DUSD = artifacts.require("DUSD");
const Reserve = artifacts.require("Reserve");
const StakeLPToken = artifacts.require("StakeLPToken");

const MockCurveSusd = artifacts.require('MockCurveSusd')
const MockSusdToken = artifacts.require("MockSusdToken");
const CurveSusdPeak = artifacts.require('CurveSusdPeak')

const toWei = web3.utils.toWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);


async function getBlockTime(tx) {
	const block = await web3.eth.getBlock(tx.receipt.blockNumber)
	return block.timestamp.toString()
}

contract('e2e flow', async (accounts) => {
	const n_coins = 4
	const alice = accounts[0]
	const bob = accounts[1]
	const SCALE_18 = scale(1, 18)
	const SCALE_36 = scale(1, 36)

	before(async () => {
		this.core = await Core.deployed()
		this.dusd = await DUSD.deployed()
		this.stakeLPToken = await StakeLPToken.deployed()
		this.reserves = []
		this.decimals = []
		for (let i = 0; i < n_coins; i++) {
			this.reserves.push(await Reserve.at((await this.core.system_coins(i)).token))
			this.decimals.push(await this.reserves[i].decimals())
		}
		this.pool = await CurveSusdPeak.deployed()

		this.amounts = [1, 2, 3, 4].map((n, i) => {
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
	})

	beforeEach(async () => {
		await increaseBlockTime(3)
	})

	it('alice mints 10 (CurveSusdPeak)', async () => {
		await this.assertions({ dusd_total_supply: '0' })

		const tasks = []
		for (let i = 0; i < n_coins; i++) {
			tasks.push(this.reserves[i].mint(alice, this.amounts[i]))
			tasks.push(this.reserves[i].approve(this.pool.address, this.amounts[i]))
		}
		await Promise.all(tasks)
		await this.pool.mint(this.amounts, toWei('10'))

		const dusd_balance = await this.dusd.balanceOf(alice)
		assert.equal(dusd_balance.toString(), toWei('10'))
		this.curve_token = await MockSusdToken.deployed()
		assert.equal((await this.curve_token.balanceOf(this.pool.address)).toString(), toWei('10'))
		await this.assertions({ dusd_total_supply: toWei('10') })
	})

	it('bob mints 10 (CurveSusdPeak)', async () => {
		const tasks = []
		const from = bob
		for (let i = 0; i < n_coins; i++) {
			tasks.push(this.reserves[i].mint(from, this.amounts[i]))
			tasks.push(this.reserves[i].approve(this.pool.address, this.amounts[i], { from }))
		}
		await Promise.all(tasks)
		await this.pool.mint(this.amounts, toWei('10'), { from })

		this.dusd_balance = await this.dusd.balanceOf(from)
		assert.equal(this.dusd_balance.toString(), toWei('10'))
		this.curve_token = await MockSusdToken.deployed()
		assert.equal((await this.curve_token.balanceOf(this.pool.address)).toString(), toWei('20'))
		await this.assertions({ dusd_total_supply: toWei('20') })
	})

	it('alice stakes 4', async () => {
		await this.assertions({
			dusd_total_supply: toWei('20'),
			dusd_staked: '0',
			stakeLPToken_supply: '0',
			timeWeightRewardPerToken: '0',
			rewardPerTokenStored: '0'
		})

		const stake_amount = toWei('4')

		await this.dusd.approve(this.stakeLPToken.address, stake_amount)
		const stakeTx = await this.stakeLPToken.stake(stake_amount)

		const dusd_bal = await this.dusd.balanceOf(alice)
		assert.equal(dusd_bal.toString(), toWei('6')) // 10 - 4

		const bal = await this.stakeLPToken.balanceOf(alice)
		assert.equal(bal.toString(), stake_amount)

		const earned = await this.stakeLPToken.earned(alice)
		assert.equal(earned.toString(), '0')

		await this.assertions({
			dusd_total_supply: toWei('20'),
			dusd_staked: stake_amount,
			stakeLPToken_supply: stake_amount,
			timeWeightRewardPerToken: '0',
			rewardPerTokenStored: '0'
		})
		this.lastUpdateTime = await this.stakeLPToken.lastUpdateTime()
		assert.equal(this.lastUpdateTime.toString(), (await getBlockTime(stakeTx)).toString())
	})

	it('CurveSusdPeak accrues income=4', async () => {
		this.mockCurveSusd = await MockCurveSusd.deployed()
		this.protocolIncome = scale(4, 18)
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
		this.lastIncomeUpdate = await this.core.lastIncomeUpdate()

		const s = await this.core.sync_system()
		const now = await getBlockTime(s)

		const incomeWindow = now - parseInt(this.lastIncomeUpdate.toString(), 10)
		const rewardRate = this.protocolIncome.div(toBN(incomeWindow))
		const stakeWindow = now - parseInt(this.lastUpdateTime.toString(), 10)
		this.timeWeightRewardPerToken = scale(stakeWindow, 18).div(toBN(4))
		this.rewardPerTokenStored = this.timeWeightRewardPerToken.mul(rewardRate).div(SCALE_18)
		await this.assertions({
			dusd_total_supply: toWei('20'),
			dusd_staked: toWei('4'),
			stakeLPToken_supply: toWei('4'),
			timeWeightRewardPerToken: '0', // has been reset
			rewardPerTokenStored: this.rewardPerTokenStored.toString(),
		})
		this.lastUpdateTime = await this.stakeLPToken.lastUpdateTime()
		assert.equal(this.lastUpdateTime.toString(), now.toString())
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
		const now = await getBlockTime(s)

		const dusd_bal = await this.dusd.balanceOf(bob)
		assert.equal(dusd_bal.toString(), toWei('4')) // 10 - 6

		const bal = await this.stakeLPToken.balanceOf(bob)
		assert.equal(bal.toString(), stake_amount)

		const window = now - parseInt(this.lastUpdateTime.toString(), 10)
		// just before Bob stakes, supply was 4
		this.timeWeightRewardPerToken = scale(window, 18).div(toBN(4))
		await this.assertions({
			dusd_total_supply: toWei('20'),
			dusd_staked: toWei('10'),
			stakeLPToken_supply: toWei('10'),
			timeWeightRewardPerToken: this.timeWeightRewardPerToken.toString(),
			rewardPerTokenStored: this.rewardPerTokenStored.toString() // didn't change
		})

		let earned = await this.stakeLPToken.earned(bob)
		assert.equal(earned.toString(), '0')

		this.lastUpdateTime = await this.stakeLPToken.lastUpdateTime()
		assert.equal(this.lastUpdateTime.toString(), now.toString())
	})

	it('Alice claims reward', async () => {
		this.aliceRewardPerTokenPaid = await this.stakeLPToken.userRewardPerTokenPaid(alice)
		assert.equal(this.aliceRewardPerTokenPaid.toString(), '0')

		this.aliceRewards = await this.stakeLPToken.rewards(alice)
		assert.equal(this.aliceRewards.toString(), '0')

		const s = await this.stakeLPToken.getReward()

		const now = await getBlockTime(s)
		let dusd_bal = await this.dusd.balanceOf(alice)
		assert.equal(dusd_bal.toString(), scale(6, 18).add(this.aliceReward).toString()) // 6 + 4 reward

		const bal = await this.stakeLPToken.balanceOf(alice)
		assert.equal(bal.toString(), toWei('4')) // original staked amount

		earned = await this.stakeLPToken.earned(alice)
		assert.equal(earned.toString(), '0')

		this.aliceRewardPerTokenPaid = await this.stakeLPToken.userRewardPerTokenPaid(alice)
		assert.equal(this.aliceRewardPerTokenPaid.toString(), this.rewardPerTokenStored)

		this.aliceRewards = await this.stakeLPToken.rewards(alice)
		assert.equal(this.aliceRewards.toString(), '0')

		const window = now - parseInt(this.lastUpdateTime.toString(), 10)
		this.timeWeightRewardPerToken = this.timeWeightRewardPerToken.add(scale(window, 18).div(toBN(10))) // totalSupply=10
		this.dusd_total_supply = scale(20, 18).add(this.aliceReward)
		await this.assertions({
			dusd_total_supply: this.dusd_total_supply.toString(),
			dusd_staked: toWei('10'),
			stakeLPToken_supply: toWei('10'),
			timeWeightRewardPerToken: this.timeWeightRewardPerToken.toString(),
			rewardPerTokenStored: this.rewardPerTokenStored.toString(), // didn't change
		})
		this.lastUpdateTime = await this.stakeLPToken.lastUpdateTime()
		assert.equal(this.lastUpdateTime.toString(), now.toString())
	})

	it('CurveSusdPeak accrues income=6', async () => {
		let inventory = await this.core.get_inventory()
		assert.equal(inventory.toString(), toWei('24'))

		this.mockCurveSusd = await MockCurveSusd.deployed()
		this.reward = toBN(6)
		const income = [2, 1, 1, 2].map((n, i) => { // 5 tokens
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
		const tasks = []
		for (let i = 0; i < n_coins; i++) {
			tasks.push(this.reserves[i].mint(this.mockCurveSusd.address, income[i]))
		}
		await Promise.all(tasks)

		inventory = await this.core.get_inventory()
		assert.equal(inventory.toString(), toWei('30'))

		this.protocolIncome = inventory.sub(this.dusd_total_supply).sub(this.protocolIncome)
	})

	it('update system stats', async () => {
		this.lastIncomeUpdate = await this.core.lastIncomeUpdate()

		const s = await this.core.update_system_stats()

		const now = await getBlockTime(s)
		const incomeWindow = now - parseInt(this.lastIncomeUpdate.toString(), 10)
		const rewardRate = this.protocolIncome.div(toBN(incomeWindow))
		const stakeWindow = now - parseInt(this.lastUpdateTime.toString(), 10)
		const timeWeightRewardPerToken = this.timeWeightRewardPerToken.add(
			scale(stakeWindow, 18).div(toBN(10))) // totalSupply=10
		this.rewardPerTokenStored = this.rewardPerTokenStored.add(
			timeWeightRewardPerToken
			.mul(rewardRate)
			.div(SCALE_18)
		)
		await this.assertions({
			dusd_total_supply: this.dusd_total_supply,
			dusd_staked: toWei('10'),
			stakeLPToken_supply: toWei('10'),
			timeWeightRewardPerToken: '0', // has been reset
			rewardPerTokenStored: this.rewardPerTokenStored.toString(),
			incomeDiff: this.incomeDiff
		})
		this.lastUpdateTime = await this.stakeLPToken.lastUpdateTime()
		assert.equal(this.lastUpdateTime.toString(), now.toString())

		this.lastIncomeUpdate = await this.core.lastIncomeUpdate()
		assert.equal(this.lastIncomeUpdate.toString(), now.toString())
	})

	this.assertions = async (vals) => {
		if (vals.dusd_total_supply) {
			assert.equal((await this.dusd.totalSupply()).toString(), vals.dusd_total_supply)
		}
		if (vals.dusd_staked) {
			assert.equal((await this.dusd.balanceOf(this.stakeLPToken.address)).toString(), vals.dusd_staked)
		}
		if (vals.stakeLPToken_supply) {
			assert.equal((await this.stakeLPToken.totalSupply()).toString(), vals.stakeLPToken_supply)
		}
		if (vals.timeWeightRewardPerToken) {
			assert.equal((await this.stakeLPToken.timeWeightRewardPerToken()).toString(), vals.timeWeightRewardPerToken)
		}
		if (vals.rewardPerTokenStored) {
			assert.equal((await this.stakeLPToken.rewardPerTokenStored()).toString(), vals.rewardPerTokenStored)
		}
		if (vals.incomeDiff) {
			assert.equal((await this.stakeLPToken.income_diff()).toString(), vals.incomeDiff)
		}
	}
})

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

function printReceipt(r) {
	r.receipt.rawLogs.forEach(l => {
		if (l.topics[0] == '0x8a36f5a234186d446e36a7df36ace663a05a580d9bea2dd899c6dd76a075d5fa') {
			console.log(toBN(l.topics[1].slice(2), 'hex').toString())
		}
	})
}
