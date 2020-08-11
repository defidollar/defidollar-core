const assert = require('assert')
const utils = require('../../utils.js')

const CurveSusdPeakProxy = artifacts.require("CurveSusdPeakProxy");

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
        bob = accounts[1]
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

    it('curveSusd.add_liquidity: bob seeded initial liquidity of 400 in curve', async () => {
        this.amounts = [100, 100, 100, 100]
        const tasks = []
        for (let i = 0; i < n_coins; i++) {
            this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
            tasks.push(this.reserves[i].mint(bob, this.amounts[i]))
            tasks.push(this.reserves[i].approve(this.curveSusd.address, this.amounts[i], { from: bob }))
        }
        await Promise.all(tasks)
        await this.curveSusd.add_liquidity(this.amounts, '0', { from: bob })
        console.log(`bob got ${fromWei(await this.curveToken.balanceOf(bob))} yCRV`)
    })

    it('curveSusdPeak.mintWithScrv: bob minted dusd with 1/10 of their Scrv', async () => {
        const inAmount = toBN(await this.curveToken.balanceOf(bob)).div(toBN(10)).toString()
        await this.curveToken.approve(this.curveSusdPeak.address, inAmount, { from: bob })
        await this.curveSusdPeak.mintWithScrv(inAmount, '0', { from: bob })
        console.log(`bob got ${fromWei(await this.dusd.balanceOf(bob))} DUSD`)
    })

    it('alice took a flash loan for 1000 dai and 600 usdc', async () => {
        this.dai = utils.scale(1000, 18)
        this.usdc = utils.scale(600, 6)
        this.totalDebt = this.dai.add(utils.scale(this.usdc, 12))
        await this.reserves[0].mint(alice, this.dai)
        await this.reserves[1].mint(alice, this.usdc)
    })

    it('curveSusd.add_liquidity: alice dumped 1000 dai in curve', async () => {
        await this.reserves[0].approve(this.curveSusd.address, this.dai)
        await this.curveSusd.add_liquidity([this.dai,0,0,0], 0)
        console.log(`alice got ${fromWei(await this.curveToken.balanceOf(alice))} yCRV`)
    })

    it('curveSusdPeak.mint(600 usdc): alice mints dusd with usdc', async () => {
        await this.reserves[1].approve(this.curveSusdPeak.address, this.usdc)
        await this.curveSusdPeak.mint([0,this.usdc,0,0], 0)
        console.log(`alice got ${fromWei(await this.dusd.balanceOf(alice))} DUSD`)
    })

    it('curveDeposit.remove_liquidity_one_coin(dai): alice', async () => {
        const inAmount = await this.curveToken.balanceOf(alice)
        await this.curveToken.approve(this.curveDeposit.address, inAmount)
        await this.curveDeposit.remove_liquidity_one_coin(inAmount,0,0,false)
        // await this.curveSusd.remove_liquidity_imbalance([this.dai,0,0,0], MAX)
        // await this.curveSusd.remove_liquidity(inAmount, [0,0,0,0])
    })

    it('curveSusdPeak.redeemInOneCoin(usdc): alice', async () => {
        const inAmount = await this.dusd.balanceOf(alice)
        await this.curveSusdPeak.redeemInOneCoin(inAmount, 1, 0)
    })

    it('alice did not make a profit', async () => {
        const net = toBN(await this.reserves[0].balanceOf(alice))
            .add(utils.scale(await this.reserves[1].balanceOf(alice), 12))
        assert.ok(net.lt(this.totalDebt))
    })

    this.printStats = async () => {
        const res = {
            alice: {
                sCrv: fromWei(await this.curveToken.balanceOf(alice)),
                dusd: fromWei(await this.dusd.balanceOf(alice)),
                balances: []
            },
            bob: {
                sCrv: fromWei(await this.curveToken.balanceOf(bob)),
                dusd: fromWei(await this.dusd.balanceOf(bob)),
            },
            sCrv: {
                totalSupply: fromWei(await this.curveToken.totalSupply()),
                balances: []
            },
            dusd: {
                sCrv: fromWei(await this.curveToken.balanceOf(this.dusd.address)),
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
