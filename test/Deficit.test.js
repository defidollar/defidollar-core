const assert = require('assert')
const utils = require('./utils.js');

const toWei = web3.utils.toWei
const fromWei = web3.utils.fromWei
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

    it('bob mints ~110 dusd', async () => {
        this.amounts = [30, 30, 30, 20].map((n, i) => {
            return toBN(n).mul(toBN(10 ** this.decimals[i]))
        })
        const tasks = []
        for (let i = 0; i < n_coins; i++) {
            tasks.push(this.reserves[i].mint(bob, this.amounts[i]))
            tasks.push(this.reserves[i].approve(this.curveSusdPeak.address, this.amounts[i], { from: bob }))
        }
        await Promise.all(tasks)
        await this.curveSusdPeak.mint(this.amounts, toWei('109'), { from: bob })
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

    it('drop price to create deficit of ~4', async () => {
        let totalSystemAssets = parseInt(fromWei(await this.core.totalSystemAssets()))
        let deficit = await this.stakeLPToken.deficit()
        assert.equal(deficit.toString(), '0')

        const ethPrice = toBN(200) // from migrations
        await this.aggregators[3].setLatestAnswer(utils.scale(8, 17).div(ethPrice)) // 20 * .8 = 16 instead of 20
        await this.core.syncSystem()

        assert.equal(
            totalSystemAssets - parseInt(fromWei(await this.core.totalSystemAssets())),
            4
        )
        deficit = await this.stakeLPToken.deficit()
        assert.equal(parseInt(fromWei(deficit)), 4)
    })

    it('~3 are withdrawable for alice', async () => {
        const withdrawAble = await this.stakeLPToken.withdrawAble(alice)
        assert.equal(parseInt(fromWei(withdrawAble)), 3)
    })

    it('alice withdraws 4 but receives (4 - deficitShare)', async () => {
        const amount = utils.scale(4, 18)
        // deficit=4 on stake=8 means deficitShare=2 on amount=4
        await this.stakeLPToken.withdraw(amount)
        assert.equal(
            parseInt(fromWei(await this.dusd.balanceOf(alice))),
            3, // 2 (balance + < 2 withdrawn)
        )
    })

    it('alice exits', async () => {
        const bal = await this.dusd.balanceOf(alice)
        const aliceWillGet = toBN(await this.stakeLPToken.balanceOf(alice))
            .sub(await this.stakeLPToken.deficit())
        await this.stakeLPToken.exit()
        assert.equal(
            (await this.dusd.balanceOf(alice)).toString(),
            bal.add(aliceWillGet).toString()
        )
        const withdrawAble = await this.stakeLPToken.withdrawAble(alice)
        assert.equal(withdrawAble.toString(), '0')
        const deficit = (await this.stakeLPToken.deficit()).toString()
        assert.equal(deficit.toString(), '0')
    })
})

contract('Deficit flow (staked funds don\'t cover deficit)', async (accounts) => {
    const [ alice, bob, charlie ] = accounts

    before(async () => {
		_artifacts = await utils.getArtifacts()
        Object.assign(this, _artifacts)
    })

    it('charlie mints 40 dusd', async () => {
        this.amounts = [10, 10, 10, 10].map((n, i) => {
            return toBN(n).mul(toBN(10 ** this.decimals[i]))
        })
        const tasks = []
        for (let i = 0; i < n_coins; i++) {
            tasks.push(this.reserves[i].mint(charlie, this.amounts[i]))
            tasks.push(this.reserves[i].approve(this.curveSusd.address, this.amounts[i], { from: charlie }))
        }
        await Promise.all(tasks)
        await this.curveSusd.add_liquidity(this.amounts, toWei('40'), { from: charlie })
        assert.equal(fromWei(await this.curveToken.balanceOf(charlie)), '40')
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
        assert.equal(fromWei(await this.dusd.balanceOf(bob)), '120')
    })

    it('bob transfers 10 each to alice and charlie', async () => {
        await this.dusd.transfer(alice, toWei('10'), { from: bob })
        await this.dusd.transfer(charlie, toWei('10'), { from: bob })
    })

    it('alice stakes 10', async () => {
        this.stakeAmount = toWei('10')
        await this.dusd.approve(this.stakeLPToken.address, this.stakeAmount)
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

        const ethPrice = toBN(200) // from migrations
        await this.aggregators[3].setLatestAnswer(utils.scale(1, 16).div(ethPrice)) // $.01
        await this.core.syncSystem()

        assert.equal(parseInt(fromWei(await this.core.totalSystemAssets())), 85)
        assert.equal(parseInt(fromWei(await this.core.totalAssets())), 85)
        assert.equal(parseInt(fromWei(await this.stakeLPToken.deficit())), 34)
    })

    it('0 are withdrawable for alice', async () => {
        const withdrawAble = await this.stakeLPToken.withdrawAble(alice)
        assert.equal(withdrawAble.toString(), '0')
    })

    it('all of alice\'s coins are used to cover deficit', async () => {
        const bal = await this.dusd.balanceOf(alice)
        await this.stakeLPToken.exit()
        assert.equal(
            (await this.dusd.balanceOf(alice)).toString(),
            bal.toString()
        )
    })

    it('dusd is devalued while redeeming', async () => {
        const dusdVal = toBN(await this.core.dusdToUsd(utils.scale(1, 18), false)) // usd value of 1 dusd
        assert.ok(
            dusdVal.lt(utils.scale(8, 17)) && dusdVal.gt(utils.scale(7, 17)),
            "DUSD is not in range ($0.7, $0.8)"
        )
    })

    it('all dusd can be redeemed (race to exit was avoided)', async () => {
        const balances = { old: { bob: [], charlie: [] }, new: { bob: [], charlie: [] } }
        this.divisors = []
        if (process.env.DEBUG == 'true') {
            for (let i = 0; i < n_coins; i++) {
                this.divisors.push(toBN(10 ** this.decimals[i]))
                balances.old.bob.push((await this.reserves[i].balanceOf(bob)).div(this.divisors[i]).toString())
                balances.old.charlie.push((await this.reserves[i].balanceOf(charlie)).div(this.divisors[i]).toString())
            }
        }

        await this.curveSusdPeak.redeem(await this.dusd.balanceOf(bob), [0,0,0,0], { from: bob })
        await this.curveSusdPeak.redeem(await this.dusd.balanceOf(charlie), [0,0,0,0], { from: charlie })

        if (process.env.DEBUG == 'true') {
            for (let i = 0; i < n_coins; i++) {
                balances.new.bob.push((await this.reserves[i].balanceOf(bob)).div(this.divisors[i]).toString())
                balances.new.charlie.push((await this.reserves[i].balanceOf(charlie)).div(this.divisors[i]).toString())
            }
            console.log(balances)
        }
    })

    it('all except staked dusd was redeemed', async () => {
        assert.equal((await this.curveToken.balanceOf(this.core.address)), '0')
        const deficit = await this.stakeLPToken.deficit()
        assert.equal(deficit.toString(), '0')
        assert.equal((await this.dusd.totalSupply()).toString(),'0')
    })

    it('minting and redeeming devalued dusd is unprofitable', async () => {
        const bals = []
        for (let i = 0; i < n_coins; i++) {
            bals.push((await this.reserves[i].balanceOf(bob)))
            await this.reserves[i].approve(this.curveSusdPeak.address, bals[i], { from: bob })
        }
        await this.curveSusdPeak.mint(bals, 0, { from: bob })
        await this.curveSusdPeak.redeem(await this.dusd.balanceOf(bob), [0,0,0,0], { from: bob })
        for (let i = 0; i < n_coins; i++) {
            assert.ok(
                toBN(await this.reserves[i].balanceOf(bob)).lt(bals[i])
            )
        }
    })
})
