const assert = require('assert')
const utils = require('./utils.js');

const toWei = web3.utils.toWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);

contract('Deficit flow', async (accounts) => {
    const n_coins = 4
	const alice = accounts[0]
    const bob = accounts[1]

    before(async () => {
		const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)
	})

    it('bob mints 110 dusd', async () => {
        this.amounts = [30, 30, 30, 20].map((n, i) => {
			return toBN(n).mul(toBN(10 ** this.decimals[i]))
		})
        const tasks = []
		for (let i = 0; i < n_coins; i++) {
			tasks.push(this.reserves[i].mint(bob, this.amounts[i]))
			tasks.push(this.reserves[i].approve(this.curveSusdPeak.address, this.amounts[i], { from: bob }))
		}
		await Promise.all(tasks)
		await this.curveSusdPeak.mint(this.amounts, toWei('110'), { from: bob })
    })

    it('bob transfers 10 to alice', async () => {
        await this.dusd.transfer(alice, toWei('10'), { from: bob })
    })

    it('alice stakes 10', async () => {
        this.stakeAmount = toWei('10')
        await this.dusd.approve(this.stakeLPToken.address, MAX)
        await this.stakeLPToken.stake(this.stakeAmount)
    })

    it('10 are withdrawable for alice', async () => {
        const withdrawAble = await this.stakeLPToken.withdrawAble(alice)
        assert.equal(withdrawAble.toString(), this.stakeAmount)
    })

    it('alice withdraws 2', async () => {
        await this.stakeLPToken.withdraw(toWei('2'))
        const balance = await this.dusd.balanceOf(alice)
        assert.equal(balance.toString(), toWei('2'))
        const withdrawAble = await this.stakeLPToken.withdrawAble(alice)
        assert.equal(withdrawAble.toString(), toWei('8'))
    })

    it('8 are withdrawable for alice', async () => {
        const withdrawAble = await this.stakeLPToken.withdrawAble(alice)
        assert.equal(withdrawAble.toString(), toWei('8'))
    })

    it('drop price to create deficit of 4', async () => {
        let totalSystemAssets = await this.core.totalSystemAssets()
        assert.equal(totalSystemAssets.toString(), toWei('110'))
        let deficit = await this.stakeLPToken.deficit()
        assert.equal(deficit.toString(), '0')

        const ethPrice = toBN(200) // from migrations
        // The latestAnswer value for all USD reference data contracts is multiplied by 100000000 before being written on-chain and
        await this.aggregators[3].setLatestAnswer(utils.scale(8, 17).div(ethPrice)) // 20 * .8 = 16 instead of 20
        await this.core.syncSystem()

        totalSystemAssets = await this.core.totalSystemAssets()
        assert.equal(totalSystemAssets.toString(), toWei('106'))
        deficit = await this.stakeLPToken.deficit()
        assert.equal(deficit.toString(), toWei('4'))
    })

    it('4 are withdrawable for alice', async () => {
        const withdrawAble = await this.stakeLPToken.withdrawAble(alice)
        assert.equal(withdrawAble.toString(), toWei('4'))
    })

    it('reverts if alice withdraws > 4', async () => {
        try {
            await this.stakeLPToken.withdraw(utils.scale(41, 17)) // 4.1
        } catch (e) {
            assert.equal(e.reason, 'Funds are illiquid')
        }
    })

    it('alice withdraws 2', async () => {
        let balance = await this.dusd.balanceOf(alice)

        await this.stakeLPToken.withdraw(toWei('2'))
        assert.equal(
            (await this.dusd.balanceOf(alice)).toString(),
            balance.add(utils.scale(2, 18))
        )

        const withdrawAble = await this.stakeLPToken.withdrawAble(alice)
        assert.equal(withdrawAble.toString(), toWei('2'))
    })
})
