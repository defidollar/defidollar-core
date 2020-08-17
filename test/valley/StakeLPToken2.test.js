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
		await this.curveSusdPeak.mint(this.amounts, toWei('40'))

		const dusdBalance = await this.dusd.balanceOf(alice)
		assert.equal(dusdBalance.toString(), toWei('40'))
		assert.equal(await this.curveSusdPeak.sCrvBalance(), toWei('40'))
		await utils.assertions({ dusdTotalSupply: toWei('40') }, _artifacts)
	})

	it('CurveSusdPeak accrues income=4', async () => {
		const income = [1, 1, 1, 1].map((n, i) => {
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
		await this.curveSusd.mock_add_to_balance(income)
		await this.assertions({ totalSystemAssets: toWei('44') })
	})

	it('alice stakes=4', async () => {
		await this.assertions({
			dusdTotalSupply: toWei('40'),
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
			dusdTotalSupply: toWei('40'),
			dusdStaked: stakeAmount,
			totalSystemAssets: toWei('44'),
			stakeLPTokenSupply: stakeAmount,
			rewardPerTokenStored: '0'
		})
	})

	it('updateProtocolIncome was triggered correctly', async () => {
		const unclaimedRewards = await this.core.unclaimedRewards()
		assert.equal(unclaimedRewards.toString(), toWei('4'))
	})

	it('CurveSusdPeak accrues income=8', async () => {
		const income = [2, 2, 2, 2].map((n, i) => {
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
		await this.curveSusd.mock_add_to_balance(income)
		await this.assertions({ totalSystemAssets: toWei('52') })
	})

	it('lastPeriodIncome', async () => {
		const { periodIncome } = await this.core.lastPeriodIncome()
		assert.equal(periodIncome.toString(), toWei('8')) // unclaimed income was accounted for

		const unclaimedRewards = await this.core.unclaimedRewards()
		assert.equal(unclaimedRewards.toString(), toWei('4')) // remains same
	})

	it('drop coin prices to $0.5', async() => {
		const ethPrice = toBN(200) // from migrations
		for (let i = 0; i < n_coins; i++) {
			await this.aggregators[i].setLatestAnswer(utils.scale(5, 17).div(ethPrice)) // $.01
		}
		await this.core.syncSystem()

		assert.equal(parseInt(fromWei(await this.core.totalSystemAssets())), 26)
		assert.equal(parseInt(fromWei(await this.core.totalAssets())), 26)
		assert.equal(parseInt(fromWei(await this.stakeLPToken.deficit())), 14)
	})

	this.assertions = (vals) => {
		return utils.assertions(vals, _artifacts)
	}
})
