const assert = require('assert')
const utils = require('../utils.js')
const { DefiDollarClient } = require('@defidollar/core-client-lib')

const config = require('../../deployments/development.json')
const toWei = web3.utils.toWei
const fromWei = web3.utils.fromWei
const toBN = web3.utils.toBN
const n_coins = 4

contract('core-client-lib: YVaultPeak', async (accounts) => {
    let alice = accounts[0]

    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)
        this.client = new DefiDollarClient(web3, config)

        this.amounts = [200, 200, 200, 200]
        this.reserves = this.reserves.slice(0, 3).concat([this.reserves[4]])
        const tasks = []
        for (let i = 0; i < n_coins; i++) {
            this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
            tasks.push(this.reserves[i].mint(alice, this.amounts[i]))
        }
        await Promise.all(tasks)
    })

    it('yVaultZap.mint', async () => {
        this.amounts = [100, 100, 100, 100]
        const tasks = []
        for (let i = 0; i < n_coins; i++) {
            this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
            tasks.push(this.reserves[i].approve(this.yVaultZap.address, this.amounts[i]))
        }
        await Promise.all(tasks)
        const tokens = { DAI: 100, USDC: 100, USDT: 100, TUSD: 100 }
        await this.client.mint(tokens, '401', '1', { from: alice })
        assert.equal(fromWei(await this.dusd.balanceOf(alice)), '400')
        assert.equal(fromWei(await this.yCrv.balanceOf(this.yVaultPeak.address)), '20')
        assert.equal(fromWei(await this.yCrv.balanceOf(this.yVault.address)), '380')
        assert.equal(fromWei(await this.yVault.balanceOf(this.controller.address)), '380')

        // calling ySwap.calc_token_amount without any liquidity in curve reverts,
        // so calling this here to verify this call does works
        const { expectedAmount } = await this.client.calcExpectedMintAmount(tokens)
        assert.equal(fromWei(expectedAmount), '400')
    })

    it('redeemInYusd', async () => {
        const dusd = toWei('40')
        const { expectedAmount } = await this.client.calcExpectedRedeemAmount('40', 'yUSD')
        assert.equal(fromWei(expectedAmount), '40')

        await this.yVaultPeak.redeemInYusd(dusd, 0)
        assert.equal(fromWei(await this.dusd.balanceOf(alice)), '360')
        assert.equal(parseInt(fromWei(await this.yVault.balanceOf(alice))), '40')
        assert.equal(fromWei(await this.yVault.balanceOf(this.controller.address)), '340')

        // yCrv balance is unchanged
        assert.equal(fromWei(await this.yCrv.balanceOf(this.yVaultPeak.address)), '20')
        assert.equal(fromWei(await this.yCrv.balanceOf(this.yVault.address)), '380')
    })

    it('mintWithYusd', async () => {
        const yusd = toWei('20')
        await this.yVault.approve(this.yVaultPeak.address, yusd)
        await this.client.mint({ yUSD: '20' }, '22', '10', { from: alice })
        assert.equal(fromWei(await this.dusd.balanceOf(alice)), '380')
        assert.equal(fromWei(await this.yVault.balanceOf(alice)), '20')
        assert.equal(fromWei(await this.yVault.balanceOf(this.controller.address)), '360')

        // yCrv balance is unchanged
        assert.equal(fromWei(await this.yCrv.balanceOf(this.yVaultPeak.address)), '20')
        assert.equal(fromWei(await this.yCrv.balanceOf(this.yVault.address)), '380')
    })

    it('yVaultZap.redeem', async () => {
        // for (let i = 0; i < n_coins; i++) {
        //     console.log((await this.reserves[i].balanceOf(alice)).toString())
        // }
        const dusd = toWei('200')
        const { expectedAmount } = await this.client.calcExpectedRedeemAmount('200')
        await this.dusd.approve(this.yVaultZap.address, dusd)
        const tokens = { DAI: 0, USDC: 0, USDT: 0, TUSD: 0 }
        await this.client.redeem('200', tokens, '0', { from: alice })
        for (let i = 0; i < n_coins; i++) {
            assert.equal(toBN(expectedAmount[i]).div(this.scaleFactor[i]).toString(), '50')
            assert.equal(
                // scaleFactor[3] corresponds to sUSD, but that's fine
                toBN(await this.reserves[i].balanceOf(alice)).div(this.scaleFactor[i]).toString(),
                '150'
            )
        }
        assert.equal(fromWei(await this.dusd.balanceOf(alice)), '180') // 380 - 200
        assert.equal(fromWei(await this.yCrv.balanceOf(this.yVaultPeak.address)), '0') // 20 were redeemed
        assert.equal(fromWei(await this.yVault.balanceOf(this.controller.address)), '180') // 180 were redeemed
        assert.equal(fromWei(await this.yCrv.balanceOf(this.yVault.address)), '200') // 180 were redeemed
    })

    it('yVaultZap.redeemInSingleCoin', async () => {
        const dusd = toWei('20')
        await this.dusd.approve(this.yVaultZap.address, dusd)
        const { expectedAmount } = await this.client.calcExpectedRedeemAmount('20', 'DAI')
        assert.equal(parseInt(fromWei(expectedAmount)), 19)
        await this.client.redeem('20', { DAI: '19' }, '0', { from: alice })
        assert.equal(
            parseInt(fromWei(await this.reserves[0].balanceOf(alice))),
            169
        )
        assert.equal(fromWei(await this.dusd.balanceOf(alice)), '160') // 180 - 20
        assert.equal(fromWei(await this.yCrv.balanceOf(this.yVaultPeak.address)), '0')
        assert.equal(fromWei(await this.yVault.balanceOf(this.controller.address)), '160') // 180 - 20
        assert.equal(fromWei(await this.yCrv.balanceOf(this.yVault.address)), '180') // 20 were redeemed
    })
})
