const assert = require('assert')
const utils = require('../../utils.js')

const toWei = web3.utils.toWei
const fromWei = web3.utils.fromWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);
const n_coins = 4

contract('CurveSusdPeak', async (accounts) => {
    let alice = accounts[0]

    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)
        alice = accounts[0]

        this.amounts = [200, 200, 200, 200]
        const tasks = []
        for (let i = 0; i < n_coins; i++) {
            this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
            tasks.push(this.reserves[i].mint(alice, this.amounts[i]))
        }
        await Promise.all(tasks)
    })

    afterEach(async () => {
        // invariant
        assert.ok(
            parseFloat(fromWei(await this.dusd.totalSupply())) <= parseFloat(fromWei(await this.core.totalSystemAssets()))
        )
        if (process.env.DEBUG == 'true') {
            await this.printStats()
        }
    })

    it('curveSusd.add_liquidity', async () => {
        this.amounts = [100, 100, 100, 100]
        const tasks = []
        for (let i = 0; i < n_coins; i++) {
            this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
            tasks.push(this.reserves[i].approve(this.curveSusd.address, this.amounts[i]))
        }
        await Promise.all(tasks)
        await this.curveSusd.add_liquidity(this.amounts, '0')
        assert.equal(fromWei(await this.curveToken.balanceOf(alice)), '400')
    })

    it('peak.mintWithScrv', async () => {
        const inAmount = toBN(await this.curveToken.balanceOf(alice)).div(toBN(2)).toString()
        await this.curveToken.approve(this.curveSusdPeak.address, inAmount)
        await this.curveSusdPeak.mintWithScrv(inAmount, '0')
        assert.equal(fromWei(await this.curveToken.balanceOf(this.curveSusdPeak.address)), '200')
        assert.equal(fromWei(await this.curveToken.balanceOf(alice)), '200')
        assert.equal(fromWei(await this.dusd.balanceOf(alice)), '200')
    })

    it('curveSusdPeak.mint', async () => {
        this.amounts = [10, 0, 8, 0]
        const tasks = []
        for (let i = 0; i < n_coins; i++) {
            this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
            tasks.push(this.reserves[i].approve(this.curveSusdPeak.address, this.amounts[i]))
        }
        await Promise.all(tasks)
        await this.curveSusdPeak.mint(this.amounts, '0')
        assert.equal(parseInt(fromWei(await this.dusd.balanceOf(alice))), 217) // 200 + ~(10 + 8)
        assert.equal(parseInt(fromWei(await this.curveToken.balanceOf(this.curveSusdPeak.address))), 217)
    })

    it('peak.redeem: Alice redeems 1/2 her dusd', async () => {
        const dusdAmount = toBN(await this.dusd.balanceOf(alice)).div(toBN(2))
        await this.curveSusdPeak.redeem(dusdAmount, [0,0,0,0])
    })

    it('peak.redeemInOneCoin(3): Alice redeems 1/2 her leftover dusd', async () => {
        const dusdAmount = toBN(await this.dusd.balanceOf(alice)).div(toBN(2))
        await this.curveSusdPeak.redeemInOneCoin(dusdAmount, 3, 0)
    })

    it('peak.redeemInScrv', async () => {
        await this.curveSusdPeak.redeemInScrv(await this.dusd.balanceOf(alice), 0)
        assert.equal((await this.dusd.balanceOf(alice)).toString(), '0')
        assert.ok(toBN((await this.curveToken.balanceOf(alice))).gt(toBN(utils.scale(200, 18))), 'Didnt get Scrv')
    })

    it('curveSusd.remove_liquidity', async () => {
        const inAmount = await this.curveToken.balanceOf(alice)
        await this.curveSusd.remove_liquidity(inAmount, [0,0,0,0])
        assert.equal((await this.curveToken.balanceOf(alice)).toString(), '0')
    })

    this.printStats = async () => {
        const res = {
            alice: {
                sCrv: fromWei(await this.curveToken.balanceOf(alice)),
                dusd: fromWei(await this.dusd.balanceOf(alice)),
                balances: []
            },
            sCrv: {
                totalSupply: fromWei(await this.curveToken.totalSupply()),
                balances: []
            },
            dusd: {
                sCrv: fromWei(await this.curveToken.balanceOf(this.curveSusdPeak.address)),
                totalSupply: fromWei(await this.dusd.totalSupply()),
                totalAssets: fromWei(await this.core.totalSystemAssets()),
            }
        }
        for (let i = 0; i < n_coins; i++) {
            const divisor = toBN(10 ** this.decimals[i])
            res.sCrv.balances.push(
                (await this.curveSusd.balances(i)).div(divisor).toString()
            )
            res.alice.balances.push(
                (await this.reserves[i].balanceOf(alice)).div(divisor).toString()
            )
        }
        console.log(res)
    }
})
