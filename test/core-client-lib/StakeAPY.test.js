const assert = require('assert')
const DefiDollarClient = require('@defidollar/core-client-lib')

const utils = require('../utils.js')
const config = require('../../deployments/development.json')

const toWei = web3.utils.toWei
const fromWei = web3.utils.fromWei
const toBN = web3.utils.toBN
const n_coins = 4
let _artifacts

contract('core-client-lib: StakeLPToken', async (accounts) => {
	const alice = accounts[0]
	const bob = accounts[1]

	before(async () => {
		_artifacts = await utils.getArtifacts()
        Object.assign(this, _artifacts)
		this.client = new DefiDollarClient(web3, config)
		this.amounts = [250000, 250000, 250000, 250000].map((n, i) => {
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
	})

	it('alice mints 1M (CurveSusdPeak)', async () => {
		const tasks = []
		for (let i = 0; i < n_coins; i++) {
			tasks.push(this.reserves[i].mint(alice, this.amounts[i]))
			tasks.push(this.reserves[i].approve(this.curveSusdPeak.address, this.amounts[i]))
		}
		await Promise.all(tasks)
		await this.client.mint({ DAI: 250000, USDC: 250000, USDT: 250000, sUSD: 250000 }, '100', '0', { from: alice })
	})

	it('alice stakes=500k', async () => {
        const stakeAmount = '500000'
        await this.client.approve('DUSD', this.stakeLPToken.address, stakeAmount, 18, { from: alice })
		await this.client.stake(stakeAmount, { from: alice })
	})

	it('CurveSusdPeak accrues income=4', async () => {
		const income = [1, 1, 1, 1].map((n, i) => {
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
		await this.curveSusd.mock_add_to_balance(income)
		await this.assertions({ totalSystemAssets: toWei('1000004') })
	})

	it('apy', async () => {
		await new Promise(r => setTimeout(r, 2000));
		console.log(await this.client.getAPY(1))
	})

	this.assertions = (vals) => {
		return utils.assertions(vals, _artifacts)
	}
})
