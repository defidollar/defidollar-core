const assert = require('assert')
const utils = require('./utils.js');

const toWei = web3.utils.toWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);
const n_coins = 4
let _artifacts

contract('Deficit flow (staked funds cover deficit)', async (accounts) => {
	const alice = accounts[0]
    const bob = accounts[1]

    before(async () => {
		_artifacts = await utils.getArtifacts()
        Object.assign(this, _artifacts)
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
            assert.equal(e.reason, 'Withdrawing more than staked or illiquid due to system deficit')
        }
    })

    it('alice exits', async () => {
        let balance = await this.dusd.balanceOf(alice)

        await this.stakeLPToken.exit()
        assert.equal(
            (await this.dusd.balanceOf(alice)).toString(),
            balance.add(utils.scale(4, 18)) // no rewards
        )

        const withdrawAble = await this.stakeLPToken.withdrawAble(alice)
        assert.equal(withdrawAble.toString(), '0')
    })
})

contract('Deficit flow (staked funds don\'t cover deficit)', async (accounts) => {
	const alice = accounts[0]
    const bob = accounts[1]

    before(async () => {
		_artifacts = await utils.getArtifacts()
        Object.assign(this, _artifacts)
    })

    it('third party mints dusd', async () => {
        const from = accounts[2]
        this.amounts = [10, 10, 10, 10].map((n, i) => {
            return toBN(n).mul(toBN(10 ** this.decimals[i]))
        })
        const tasks = []
        for (let i = 0; i < n_coins; i++) {
            tasks.push(this.reserves[i].mint(from, this.amounts[i]))
            tasks.push(this.reserves[i].approve(this.curveSusd.address, this.amounts[i], { from }))
        }
        await Promise.all(tasks)
        await this.curveSusd.add_liquidity(this.amounts, '0', { from })
    })

    it('bob mints 120 dusd', async () => {
        this.amounts = [30, 30, 30, 30].map((n, i) => {
            return toBN(n).mul(toBN(10 ** this.decimals[i]))
        })
        const tasks = []
        for (let i = 0; i < n_coins; i++) {
            tasks.push(this.reserves[i].mint(bob, this.amounts[i]))
            tasks.push(this.reserves[i].approve(this.curveSusdPeak.address, this.amounts[i], { from: bob }))
        }
        await Promise.all(tasks)
        await this.curveSusdPeak.mint(this.amounts, toWei('120'), { from: bob })
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

    it('drop coin price to 0', async() => {
        await utils.assertions(
            { totalSystemAssets: toWei('120'), totalAssets: toWei('120'), deficit: '0' },
            _artifacts
        )

        await this.aggregators[3].setLatestAnswer(0)
        await this.core.syncSystem()

        await utils.assertions(
            { totalSystemAssets: toWei('90'), totalAssets: toWei('90'), deficit: toWei('30') },
            _artifacts
        )
    })

    it('0 are withdrawable for alice', async () => {
        const withdrawAble = await this.stakeLPToken.withdrawAble(alice)
        assert.equal(withdrawAble.toString(), '0')
    })

    it('reverts if alice attempts to withdraw 1 wei', async () => {
        try {
            await this.stakeLPToken.withdraw(1) // even 1 wei should fail
        } catch (e) {
            assert.equal(e.reason, 'Withdrawing more than staked or illiquid due to system deficit')
        }
    })

    it('dusd is devalued while redeeming/minting', async () => {
        // [40, 40, 40] * 120 / 160
        let amount = toWei('30')
        const nowBalace = utils.scale(40, 18).mul(toBN(120)).div(toBN(160))
            .add(utils.scale(40, 6).mul(toBN(120)).div(toBN(160)).mul(utils.scale(1, 12)))
            .add(utils.scale(40, 6).mul(toBN(120)).div(toBN(160)).mul(utils.scale(1, 12)))
            // 4th coins has gone to 0
        // [10, 40, 40] * 90 / 130
        const balanceAfterRedeem = utils.scale(10, 18).mul(toBN(90)).div(toBN(130))
            .add(utils.scale(40, 6).mul(toBN(90)).div(toBN(130)).mul(utils.scale(1, 12)))
            .add(utils.scale(40, 6).mul(toBN(90)).div(toBN(130)).mul(utils.scale(1, 12)))
        let usdDelta = nowBalace.sub(balanceAfterRedeem)
        // dusdAmount = usd.mul(perceivedSupply).div(totalAssets); i.e. usdDelta * 110 / 90
        let expectedDusdAmount = usdDelta.mul(toBN(110 /* 120 - 10 */)).div(toBN(90))
        const args = [
            [amount, 0, 0, 0],
            toWei('100'),
            { from: bob }
        ]
        let dusdAmount = await this.curveSusdPeak.redeem.call(...args)
        // assert.equal(dusdAmount.toString(), expectedDusdAmount.toString())

        // insert 1st coin
        amount = utils.scale(30, 6)
        await this.reserves[1].mint(bob, amount)
        // [40, 70, 40] * 150 / 190
        const balanceAfterMint = utils.scale(40, 18).mul(toBN(150)).div(toBN(190))
            .add(utils.scale(70, 6).mul(toBN(150)).div(toBN(190)).mul(utils.scale(1, 12)))
            .add(utils.scale(40, 6).mul(toBN(150)).div(toBN(190)).mul(utils.scale(1, 12)))
        usdDelta = balanceAfterMint.sub(nowBalace)
        console.log({
            usdDelta: usdDelta.toString()
        })
        usdDelta = utils.scale(40, 18).mul(toBN(30)).div(toBN(190))
            .add(utils.scale(70, 6).mul(toBN(30)).div(toBN(190)).mul(utils.scale(1, 12)))
            .add(utils.scale(40, 6).mul(toBN(30)).div(toBN(190)).mul(utils.scale(1, 12)))
        console.log({
            usdDelta: usdDelta.toString()
        })
        // dusdAmount = usd.mul(perceivedSupply).div(totalAssets); i.e. usdDelta * 110 / 90
        expectedDusdAmount = usdDelta.mul(toBN(110 /* 120 - 10 */)).div(toBN(90))
        await this.reserves[1].approve(this.curveSusdPeak.address, amount, { from: bob })
        dusdAmount = await this.curveSusdPeak.mint.call([0, amount, 0, 0], '0', { from: bob })
        assert.equal(dusdAmount.toString(), expectedDusdAmount.toString())
    })
})
