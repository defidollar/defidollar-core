const assert = require('assert')
const utils = require('../utils.js')

const StakeLPTokenProxy = artifacts.require("StakeLPTokenProxy");
const StakeLPToken = artifacts.require("StakeLPToken");

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
		this.amounts = [10, 10, 10, 10].map((n, i) => {
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
	})

	it('alice mints 40 (CurveSusdPeak)', async () => {
		await utils.assertions({ dusdTotalSupply: '0' }, _artifacts)

		const tasks = []
		for (let i = 0; i < n_coins; i++) {
			tasks.push(this.reserves[i].mint(alice, this.amounts[i]))
			tasks.push(this.reserves[i].approve(this.curveSusdPeak.address, this.amounts[i]))
		}
		await Promise.all(tasks)
		const mint = await this.curveSusdPeak.mint(this.amounts, toWei('40'))
		const dusdBalance = await this.dusd.balanceOf(alice)
		assert.equal(dusdBalance.toString(), toWei('40'))
		assert.equal(await this.curveSusdPeak.sCrvBalance(), toWei('40'))
		await utils.assertions({ dusdTotalSupply: toWei('40') }, _artifacts)
	})

	it('bob mints 20 (CurveSusdPeak)', async () => {
		this.amounts = this.amounts.map(b => b.div(toBN(2))) // 5 of each coin
		const tasks = []
		for (let i = 0; i < n_coins; i++) {
			tasks.push(this.reserves[i].mint(bob, this.amounts[i]))
			tasks.push(this.reserves[i].approve(this.curveSusdPeak.address, this.amounts[i], { from: bob }))
		}
		await Promise.all(tasks)
		await this.curveSusdPeak.mint(this.amounts, toWei('20'), { from: bob })

		this.dusdBalance = await this.dusd.balanceOf(bob)
		assert.equal(this.dusdBalance.toString(), toWei('20'))
		assert.equal(await this.curveSusdPeak.sCrvBalance(), toWei('60'))
		await this.assertions({ dusdTotalSupply: toWei('60') })
	})

	it('test upgradeability', async () => {
		const proxy = await StakeLPTokenProxy.at(this.stakeLPToken.address)
		const stakeLPToken = await StakeLPToken.new()
		await proxy.updateImplementation(stakeLPToken.address)
	})

	it('pause staking contract', async () => {
		await this.stakeLPToken.toggleIsPaused(1)
		try {
			await this.stakeLPToken.exit()
			assert.fail('expected to revert with: Staking is paused')
		} catch(e) {
			assert.equal(e.reason, 'Staking is paused')
		}
	})

	it('unpause staking contract', async () => {
		try {
			await this.stakeLPToken.toggleIsPaused(0, { from: bob })
			assert.fail('expected to revert')
		} catch(e) {
			assert.equal(e.reason, 'NOT_OWNER')
		}
		await this.stakeLPToken.toggleIsPaused(0)
	})

	it('alice stakes=4', async () => {
		await this.assertions({
			dusdTotalSupply: toWei('60'),
			dusdStaked: '0',
			stakeLPTokenSupply: '0',
			rewardPerTokenStored: '0'
		})

		const stakeAmount = toWei('4')

		await this.dusd.approve(this.stakeLPToken.address, stakeAmount)
		await this.stakeLPToken.stake(stakeAmount)

		const dusdBal = await this.dusd.balanceOf(alice)
		assert.equal(dusdBal.toString(), toWei('36')) // 40 - 4

		const bal = await this.stakeLPToken.balanceOf(alice)
		assert.equal(bal.toString(), stakeAmount)

		const earned = await this.stakeLPToken.earned(alice)
		assert.equal(earned.toString(), '0')

		await this.assertions({
			dusdTotalSupply: toWei('60'),
			dusdStaked: stakeAmount,
			totalSystemAssets: toWei('60'),
			stakeLPTokenSupply: stakeAmount,
			rewardPerTokenStored: '0'
		})
	})

	it('CurveSusdPeak accrues income=4', async () => {
		const income = [1, 1, 1, 1].map((n, i) => {
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
		await this.curveSusd.mock_add_to_balance(income)
		await this.assertions({ totalSystemAssets: toWei('64') })
	})

	it('alice gets reward', async () => {
		let earned = await this.stakeLPToken.earned(alice)
		assert.equal(earned.toString(), toWei('4')) // entire income - col buffer

		await this.stakeLPToken.getReward()
		// reward was minted as dusd
		const dusdBal = await this.dusd.balanceOf(alice)
		assert.equal(dusdBal.toString(), toWei('40')) // 36 + 4 (entire reward goes to alice)
		await this.assertions({ dusdTotalSupply: toWei('64') })

		// claimed reward should not get considered twice
		earned = await this.stakeLPToken.earned(alice)
		assert.equal(earned.toString(), '0')
	})

	it('CurveSusdPeak accrues income=8', async () => {
		const income = [2, 2, 2, 2].map((n, i) => {
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
		await this.curveSusd.mock_add_to_balance(income)
		await this.assertions({ totalSystemAssets: toWei('72') })

		const { _periodIncome: periodIncome } = await this.core.lastPeriodIncome()
		assert.equal(periodIncome.toString(), toWei('8'))

		const earned = await this.stakeLPToken.earned(alice)
		assert.equal(earned.toString(), toWei('8')) // entire income shuold go to alice, but not claiming
	})

	it('bob redeems=4', async () => {
		await this.curveSusdPeak.redeem(toWei('4'), [0,0,0,0], { from: bob })
		for (let i = 0; i < n_coins; i++) {
			const bal = parseFloat(fromWei(utils.scale(toBN(await this.reserves[i].balanceOf(bob)), 18)
				.div(this.scaleFactor[i])))
			assert.equal(bal, 0.9999) // due to some rounding foo it returns 0.9999 for each coin
		}
	})

	it('should not affect lastPeriodIncome', async () => {
		const { _periodIncome: periodIncome } = await this.core.lastPeriodIncome()
		assert.equal(parseInt(fromWei(periodIncome)), 8)

		const earned = parseInt(fromWei(await this.stakeLPToken.earned(alice)))
		assert.equal(earned, 8) // entire income shuold go to alice, but not claiming
	})

	it('bob stakes=2', async () => {
		const stakeAmount = toWei('2')

		await this.dusd.approve(this.stakeLPToken.address, stakeAmount, { from: bob })
		await this.stakeLPToken.stake(stakeAmount, { from: bob })

		const dusdBal = await this.dusd.balanceOf(bob)
		assert.equal(dusdBal.toString(), toWei('14')) // 20 - 4 - 2

		const bal = await this.stakeLPToken.balanceOf(bob)
		assert.equal(bal.toString(), stakeAmount)
	})

	it('period income was transferred to stakeLPToken for rewards', async () => {
		const bal = await this.dusd.balanceOf(this.stakeLPToken.address)
		assert.equal(parseInt(fromWei(bal)), 14) // alice' stake + 8 income + bob's stake = 14 (+ dust from bob's redeem)
	})

	it('CurveSusdPeak accrues income=6', async () => {
		const income = [15, 15, 15, 15].map((n, i) => {
			return toBN(n).mul(toBN(10 ** (this.decimals[i]-1))) // 1.5 each
		})
		await this.curveSusd.mock_add_to_balance(income)
		assert.equal(
			parseInt(fromWei(await this.core.totalSystemAssets())),
			74
		)
	})

	it('bob exits', async () => {
		// stakedShare * balance = 2/6 * 6 = 2
		let earned = parseInt(fromWei(await this.stakeLPToken.earned(bob)))
		assert.equal(earned, 2)

		await this.stakeLPToken.exit({ from: bob })
		const dusdBal = parseInt(fromWei(await this.dusd.balanceOf(bob)))
		assert.equal(dusdBal, 18) // 20 - 4 (redemed) + 2 (income)

		earned = await this.stakeLPToken.earned(bob)
		assert.equal(earned.toString(), '0')
	})

	it('CurveSusdPeak accrues income=3', async () => {
		const income = [75, 75, 75, 75].map((n, i) => {
			return toBN(n).mul(toBN(10 ** (this.decimals[i]-2))) // .75 each
		})
		await this.curveSusd.mock_add_to_balance(income)
		assert.equal(
			parseInt(fromWei(await this.core.totalSystemAssets())),
			77
		)
	})

	it('10% col buffer fee was introduced', async () => {
		await this.core.setFee(
			await this.core.redeemFactor(), // unchanged
			1000 // FEE_PRECISION = 10k
		)
	})

	it('alice withdraws stake', async () => {
		await this.stakeLPToken.withdraw(toWei('4')) // staked=4
		const dusdBal = await this.dusd.balanceOf(alice)
		assert.equal(dusdBal.toString(), toWei('44')) // (original) 40 + 4 (previous reward)
	})

	it('alice exits', async () => {
		// 8 + 6 * 4/6 + 3 * .9 (col buffer) = 14.7
		let earned = parseInt(fromWei(await this.stakeLPToken.earned(alice)))
		assert.equal(earned, 14)

		await this.stakeLPToken.exit()
		const dusdBal = parseInt(fromWei(await this.dusd.balanceOf(alice)))
		assert.equal(dusdBal, 58) // 44 + 14

		earned = await this.stakeLPToken.earned(alice)
		assert.equal(earned.toString(), '0')
	})

	this.assertions = (vals) => {
		return utils.assertions(vals, _artifacts)
	}
})
