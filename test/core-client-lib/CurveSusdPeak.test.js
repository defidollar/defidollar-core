const assert = require('assert')
const DefiDollarClient = require('@defidollar/core-client-lib')

const utils = require('../utils.js')
const config = require('../../deployments/development.json')

const toWei = web3.utils.toWei
const fromWei = web3.utils.fromWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);
const n_coins = 4

contract.skip('core-client-lib: CurveSusdPeak', async (accounts) => {
    let alice = accounts[0]

    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)
        alice = accounts[0]
        this.client = new DefiDollarClient(web3, config)

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
        for (let i = 0; i < n_coins; i++) {
            this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
            await this.client.approve(
                this.reserves[i].address,
                this.curveSusd.address, MAX, null, { from: alice }
            )
        }
        await this.curveSusd.add_liquidity(this.amounts, '0')
        assert.equal(fromWei(await this.curveToken.balanceOf(alice)), '400')
    })

    it('ceiling', async () => {
        const { ceiling, available } = await this.client.ceiling()
        assert.equal(ceiling, toWei('1234567'))
        assert.equal(available, toWei('1234567'))
    })

    it('peak.mintWithScrv', async () => {
        const inAmount = toBN(await this.curveToken.balanceOf(alice)).div(toBN(2)).toString()
        await this.curveToken.approve(this.curveSusdPeak.address, inAmount)
        const tokens = { crvPlain3andSUSD: 200 }
        const { expectedAmount } = await this.client.calcExpectedMintAmount(tokens)
        assert.equal(fromWei(expectedAmount), '200')
        const txHash = await this.client.mint(tokens, '200', '.05', { from: alice, transactionHash: true })
        assert.equal(txHash.slice(0, 2), '0x')
        assert.equal(fromWei(await this.curveToken.balanceOf(alice)), '200')
        assert.equal(fromWei(await this.curveSusdPeak.sCrvBalance()), '200')
        assert.equal(fromWei(await this.dusd.balanceOf(alice)), '200')
        const { ceiling, available } = await this.client.ceiling()
        assert.equal(ceiling, toWei('1234567'))
        assert.equal(available, toWei('1234367'))
    })

    it('curveSusdPeak.mint', async () => {
        this.amounts = [10, 0, 8, 0]
        const tasks = []
        for (let i = 0; i < n_coins; i++) {
            this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
            tasks.push(this.reserves[i].approve(this.curveSusdPeak.address, this.amounts[i]))
        }
        await Promise.all(tasks)
        const tokens = { DAI: 10, USDT: 8 }
        const { expectedAmount } = await this.client.calcExpectedMintAmount(tokens)
        await this.client.mint(tokens, '17', '.01', { from: alice })
        assert.equal(parseInt(fromWei(expectedAmount)), 17)
        assert.equal(parseInt(fromWei(await this.dusd.balanceOf(alice))), 217) // 200 + ~(10 + 8)
        assert.equal(parseInt(fromWei(await this.curveSusdPeak.sCrvBalance())), 217)
    })

    it('peak.redeem: Alice redeems 1/2 her dusd', async () => {
        const dusdAmount = fromWei(toBN(await this.dusd.balanceOf(alice)).div(toBN(2)))
        await this.client.calcExpectedRedeemAmount(dusdAmount)
        await this.client.redeem(dusdAmount, [0,0,0,0], 0, { from: alice })
    })

    it('peak.redeemInSingleCoin(3): Alice redeems 1/2 her leftover dusd', async () => {
        const dusdAmount = fromWei(toBN(await this.dusd.balanceOf(alice)).div(toBN(2)))
        await this.client.calcExpectedRedeemAmount(dusdAmount, 'sUSD')
        await this.client.redeem(dusdAmount, { sUSD: 10 /* minOut */ }, 0, { from: alice })
    })

    it('peak.redeemInScrv', async () => {
        const dusdAmount = fromWei(await this.dusd.balanceOf(alice),)
        await this.client.calcExpectedRedeemAmount(dusdAmount, 'crvPlain3andSUSD')
        await this.client.redeem(
            dusdAmount,
            { crvPlain3andSUSD: 10 /* minOut */ }, 0,
            { from: alice }
        )
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
