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

contract.only('e2e flow', async (accounts) => {
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
		this.lastUpdated = await this.stakeLPToken.lastUpdated()
		this.lastIncomeUpdate = await this.stakeLPToken.lastIncomeUpdate()
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
			unitRewardForCurrentFeeWindow: '0',
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
			unitRewardForCurrentFeeWindow: '0', // updates only when a change happens
			rewardPerTokenStored: '0'
		})
		this.lastUpdated = await this.stakeLPToken.lastUpdated()
		assert.equal(this.lastUpdated.toString(), (await getBlockTime(stakeTx)).toString())
		// lastIncomeUpdate remains unchanged
		assert.equal(
			(await this.stakeLPToken.lastIncomeUpdate()).toString(),
			this.lastIncomeUpdate.toString()
		)
	})

	it('CurveSusdPeak accrues income=4', async () => {
		this.mockCurveSusd = await MockCurveSusd.deployed()
		this.reward = scale(4, 18)
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
		assert.equal((await this.stakeLPToken.income_diff()).toString(), '0')

		const s = await this.core.sync_system()

		const now = await getBlockTime(s)
		const window = now - parseInt(this.lastUpdated.toString(), 10)
		const unitRewardForCurrentFeeWindow = scale(window, 18).div(toBN(4)) // totalSupply=4
		const incomeWindow = now - parseInt(this.lastIncomeUpdate.toString(), 10)
		this.rewardPerTokenStored = unitRewardForCurrentFeeWindow.mul(toBN(4)).div(toBN(incomeWindow))
		this.incomeDiff = this.reward
		await this.assertions({
			dusd_total_supply: toWei('20'),
			dusd_staked: toWei('4'),
			stakeLPToken_supply: toWei('4'),
			unitRewardForCurrentFeeWindow: '0', // has been reset
			rewardPerTokenStored: this.rewardPerTokenStored.toString(),
			incomeDiff: this.incomeDiff
		})
		this.lastUpdated = await this.stakeLPToken.lastUpdated()
		assert.equal(this.lastUpdated.toString(), now.toString())

		this.lastIncomeUpdate = await this.stakeLPToken.lastIncomeUpdate()
		assert.equal(this.lastIncomeUpdate.toString(), now.toString())
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

		const window = now - parseInt(this.lastUpdated.toString(), 10)
		// just before Bob stakes, supply was 4
		this.unitRewardForCurrentFeeWindow = scale(window, 18).div(toBN(4))
		await this.assertions({
			dusd_total_supply: toWei('20'),
			dusd_staked: toWei('10'),
			stakeLPToken_supply: toWei('10'),
			unitRewardForCurrentFeeWindow: this.unitRewardForCurrentFeeWindow.toString(),
			rewardPerTokenStored: this.rewardPerTokenStored.toString() // didn't change
		})

		let earned = await this.stakeLPToken.earned(bob)
		assert.equal(earned.toString(), '0')

		this.lastUpdated = await this.stakeLPToken.lastUpdated()
		assert.equal(this.lastUpdated.toString(), now.toString())
		// lastIncomeUpdate remains unchanged
		assert.equal(
			(await this.stakeLPToken.lastIncomeUpdate()).toString(),
			this.lastIncomeUpdate.toString()
		)
	})

	it('Alice claims reward', async () => {
		this.aliceRewardPerTokenPaid = await this.stakeLPToken.userRewardPerTokenPaid(alice)
		assert.equal(this.aliceRewardPerTokenPaid.toString(), '0')

		this.aliceRewards = await this.stakeLPToken.rewards(alice)
		assert.equal(this.aliceRewards.toString(), '0')

		const s = await this.stakeLPToken.getReward()
		printReceipt(s)
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

		const window = now - parseInt(this.lastUpdated.toString(), 10)
		this.unitRewardForCurrentFeeWindow = this.unitRewardForCurrentFeeWindow.add(scale(window, 18).div(toBN(10))) // totalSupply=10
		this.dusd_total_supply = scale(20, 18).add(this.aliceReward)
		console.log({ dusd_total_supply: this.dusd_total_supply })
		await this.assertions({
			dusd_total_supply: this.dusd_total_supply.toString(),
			dusd_staked: toWei('10'),
			stakeLPToken_supply: toWei('10'),
			unitRewardForCurrentFeeWindow: this.unitRewardForCurrentFeeWindow.toString(),
			rewardPerTokenStored: this.rewardPerTokenStored.toString(), // didn't change
			incomeDiff: this.incomeDiff // unchanged
		})
		this.lastUpdated = await this.stakeLPToken.lastUpdated()
		assert.equal(this.lastUpdated.toString(), now.toString())
		// lastIncomeUpdate remains unchanged
		assert.equal(
			(await this.stakeLPToken.lastIncomeUpdate()).toString(),
			this.lastIncomeUpdate.toString()
		)
	})

	it('bla', async () => {
		await this.stakeLPToken.getReward({ from: bob })
		// await this.stakeLPToken.setWindow()
		console.log({
			windowTotal: (await this.stakeLPToken.windowTotal()).toString(),
			lastWindowSize: (await this.stakeLPToken.lastWindowSize()).toString()
		})
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

		this.protocolIncome = inventory.sub(this.dusd_total_supply)
	})

	it('update system stats', async () => {
		assert.equal((await this.stakeLPToken.rewardPerTokenStored()).toString(), this.rewardPerTokenStored)
		this.incomeDiff = this.protocolIncome.sub(this.incomeDiff)

		console.log({
			windowTotal: (await this.stakeLPToken.windowTotal()).toString(),
			lastWindowSize: (await this.stakeLPToken.lastWindowSize()).toString()
		})

		const s = await this.core.update_system_stats()
		printReceipt(s)
		console.log('here')
		await this.stakeLPToken.setWindow()
		console.log({
			windowTotal: (await this.stakeLPToken.windowTotal()).toString(),
			lastWindowSize: (await this.stakeLPToken.lastWindowSize()).toString()
		})

		const now = await getBlockTime(s)
		const window = now - parseInt(this.lastUpdated.toString(), 10)
		const unitRewardForCurrentFeeWindow = this.unitRewardForCurrentFeeWindow.add(
			scale(window, 18).div(toBN(10))) // totalSupply=10
		console.log({
			unitRewardForCurrentFeeWindow: unitRewardForCurrentFeeWindow.toString(),
			rewardPerTokenStored: this.rewardPerTokenStored.toString()
		})
		const incomeWindow = now - parseInt(this.lastIncomeUpdate.toString(), 10)
		this.rewardPerTokenStored = this.rewardPerTokenStored.add(
			unitRewardForCurrentFeeWindow
			.mul(this.incomeDiff)
			.div(toBN(incomeWindow))
			.div(SCALE_18)
		)
		await this.assertions({
			dusd_total_supply: this.dusd_total_supply,
			dusd_staked: toWei('10'),
			stakeLPToken_supply: toWei('10'),
			unitRewardForCurrentFeeWindow: '0', // has been reset
			rewardPerTokenStored: this.rewardPerTokenStored.toString(),
			incomeDiff: this.incomeDiff
		})
		this.lastUpdated = await this.stakeLPToken.lastUpdated()
		assert.equal(this.lastUpdated.toString(), now.toString())

		this.lastIncomeUpdate = await this.stakeLPToken.lastIncomeUpdate()
		assert.equal(this.lastIncomeUpdate.toString(), now.toString())
	})

	it('Alice exits', async () => {
		let old_bal = await this.dusd.balanceOf(alice)
		console.log({
			rewardPerTokenStored: this.rewardPerTokenStored.toString(),
			aliceRewardPerTokenPaid: this.aliceRewardPerTokenPaid.toString(),
			rewards: (await this.stakeLPToken.rewards(alice)).toString(),
			incomeDiff: this.incomeDiff.toString(),
			old_bal: old_bal.toString(),
			windowTotal: (await this.stakeLPToken.windowTotal()).toString(),
			lastWindowSize: (await this.stakeLPToken.lastWindowSize()).toString(),
			earned: (await this.stakeLPToken.earned(alice)).toString(),
			earned2: (await this.stakeLPToken.earned(bob)).toString(),
			staked: (await this.stakeLPToken.balanceOf(alice)).toString(),
		})

		const s = await this.stakeLPToken.getReward()
		// const s = await this.stakeLPToken.exit()
		// const now = await getBlockTime(s)
		// const window = now - parseInt(this.lastUpdated.toString(), 10)
		const earned = toBN(4).mul(this.incomeDiff).div(toBN(10))

		dusd_bal = await this.dusd.balanceOf(alice)
		assert.equal(dusd_bal.toString(), old_bal.add(earned).toString())
		// assert.equal(dusd_bal.toString(), old_bal.add(earned).add(scale(4, 18)).toString())
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
		if (vals.unitRewardForCurrentFeeWindow) {
			assert.equal((await this.stakeLPToken.unitRewardForCurrentFeeWindow()).toString(), vals.unitRewardForCurrentFeeWindow)
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
