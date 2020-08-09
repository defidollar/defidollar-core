const assert = require('assert')
const utils = require('../utils.js')

const toWei = web3.utils.toWei
const fromWei = web3.utils.fromWei
const toBN = web3.utils.toBN
const n_coins = 4
let _artifacts

contract('StakeLPToken', async (accounts) => {
	const alice = accounts[0]
	const bob = accounts[1]

	before(async () => {
		_artifacts = await utils.getArtifacts()
        Object.assign(this, _artifacts)
		this.amounts = [1, 2, 3, 4].map((n, i) => {
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
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

		const dusdBalance = await this.dusd.balanceOf(alice)
		assert.equal(dusdBalance.toString(), toWei('10'))
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

		this.dusdBalance = await this.dusd.balanceOf(bob)
		assert.equal(this.dusdBalance.toString(), toWei('10'))
		assert.equal((await this.curveToken.balanceOf(this.curveSusdPeak.address)).toString(), toWei('20'))
		await this.assertions({ dusdTotalSupply: toWei('20') })
	})

	it('alice stakes=4', async () => {
		await this.assertions({
			dusdTotalSupply: toWei('20'),
			dusdStaked: '0',
			stakeLPTokenSupply: '0',
			rewardPerTokenStored: '0'
		})

		const stakeAmount = toWei('4')

		await this.dusd.approve(this.stakeLPToken.address, stakeAmount)
		await this.stakeLPToken.stake(stakeAmount)

		const dusdBal = await this.dusd.balanceOf(alice)
		assert.equal(dusdBal.toString(), toWei('6')) // 10 - 4

		const bal = await this.stakeLPToken.balanceOf(alice)
		assert.equal(bal.toString(), stakeAmount)

		const earned = await this.stakeLPToken.earned(alice)
		assert.equal(earned.toString(), '0')

		await this.assertions({
			dusdTotalSupply: toWei('20'),
			dusdStaked: stakeAmount,
			stakeLPTokenSupply: stakeAmount,
			rewardPerTokenStored: '0'
		})
	})

	it('CurveSusdPeak accrues income=4', async () => {
		this.protocolIncome = utils.scale(4, 18)
		const income = [1, 1, 1, 1].map((n, i) => {
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
		const tasks = []
		for (let i = 0; i < n_coins; i++) {
			tasks.push(this.reserves[i].mint(this.curveSusd.address, income[i]))
		}
		await Promise.all(tasks)
		await this.assertions({ totalSystemAssets: toWei('24') })
	})

	// claimed reward should not get considered twice
	it('alice gets reward', async () => {
		const earned = await this.stakeLPToken.earned(alice)
		assert.equal(earned.toString(), toWei('4')) // entire income

		await this.stakeLPToken.getReward()
		// reward was minted as dusd
		const dusdBal = await this.dusd.balanceOf(alice)
		assert.equal(dusdBal.toString(), toWei('10')) // 6 + 4 (entire reward goes to alice)
		await this.assertions({ dusdTotalSupply: toWei('24') })
	})

	it('CurveSusdPeak accrues income=2', async () => {
		const income = [0, 1, 1, 0].map((n, i) => {
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
		const tasks = []
		for (let i = 0; i < n_coins; i++) {
			tasks.push(this.reserves[i].mint(this.curveSusd.address, income[i]))
		}
		await Promise.all(tasks)
		await this.assertions({ totalSystemAssets: toWei('26') })

		const lastPeriodIncome = await this.core.lastPeriodIncome()
		assert.equal(lastPeriodIncome.toString(), toWei('2'))

		const earned = await this.stakeLPToken.earned(alice)
		assert.equal(earned.toString(), toWei('2')) // entire income shuold go to alice, but not claiming
	})

	it('bob redeems=5', async () => {
		await this.curveSusdPeak.redeem([0, 0, utils.scale(5, 6), 0], toWei('5'), { from: bob })
	})

	it('should not affect lastPeriodIncome', async () => {
		const lastPeriodIncome = await this.core.lastPeriodIncome()
		assert.equal(lastPeriodIncome.toString(), toWei('2'))

		const earned = await this.stakeLPToken.earned(alice)
		assert.equal(earned.toString(), toWei('2')) // entire income shuold go to alice, but not claiming
	})

	it('bob stakes=2', async () => {
		const stakeAmount = toWei('2')
		const from = bob

		await this.dusd.approve(this.stakeLPToken.address, stakeAmount, { from })
		await this.stakeLPToken.stake(stakeAmount, { from })

		const dusdBal = await this.dusd.balanceOf(bob)
		assert.equal(dusdBal.toString(), toWei('3')) // 5 - 2

		const bal = await this.stakeLPToken.balanceOf(bob)
		assert.equal(bal.toString(), stakeAmount)
	})

	it('CurveSusdPeak accrues income=6', async () => {
		const income = [2, 1, 1, 2].map((n, i) => {
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
		const tasks = []
		for (let i = 0; i < n_coins; i++) {
			tasks.push(this.reserves[i].mint(this.curveSusd.address, income[i]))
		}
		await Promise.all(tasks)
		await this.assertions({ totalSystemAssets: toWei('27') })
	})

	it('bob exits', async () => {
		// 6 * 2/6 = 2
		let earned = await this.stakeLPToken.earned(bob)
		assert.equal(earned.toString(), toWei('2')) // entire income should go to alice, but not claiming

		await this.stakeLPToken.exit({ from: bob })
		const dusdBal = await this.dusd.balanceOf(bob)
		assert.equal(dusdBal.toString(), toWei('7')) // 5 + 2

		earned = await this.stakeLPToken.earned(bob)
		assert.equal(earned.toString(), '0')
	})

	it('CurveSusdPeak accrues income=3', async () => {
		const income = [1, 0, 2, 0].map((n, i) => {
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
		const tasks = []
		for (let i = 0; i < n_coins; i++) {
			tasks.push(this.reserves[i].mint(this.curveSusd.address, income[i]))
		}
		await Promise.all(tasks)
	})

	it('alice withdraws stake', async () => {
		await this.stakeLPToken.withdraw(toWei('4')) // staked=4
		const dusdBal = await this.dusd.balanceOf(alice)
		assert.equal(dusdBal.toString(), toWei('14')) // (original) 10 + 4 (reward)
	})

	it('alice exits', async () => {
		// 2 + 6 * 4/6 + 3 = 9
		let earned = await this.stakeLPToken.earned(alice)
		assert.equal(earned.toString(), toWei('9')) // entire income should go to alice, but not claiming

		await this.stakeLPToken.exit()
		const dusdBal = await this.dusd.balanceOf(alice)
		assert.equal(dusdBal.toString(), toWei('23')) // 14 + 9

		earned = await this.stakeLPToken.earned(alice)
		assert.equal(earned.toString(), '0')
	})

	this.assertions = (vals) => {
		return utils.assertions(vals, _artifacts)
	}
})
