const assert = require('assert')

const YVaultPeakTest2 = artifacts.require("YVaultPeakTest2");
const YVaultPeakProxy = artifacts.require("YVaultPeakProxy");
const ibDUSDProxy = artifacts.require("ibDUSDProxy");

const utils = require('../utils.js')
const { SavingsClient } = require('@defidollar/core-client-lib')
const config = require('../../deployments/development.json')

const fromWei = web3.utils.fromWei
const toWei = web3.utils.toWei
const toBN = web3.utils.toBN

contract('ibDUSD', async (accounts) => {
    const [ alice ] = accounts

    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)
        this.reserves = this.reserves.slice(0, 3).concat([this.reserves[4]])
        this.client = new SavingsClient(web3, config)
    })

    it('yVaultZap.mint', async () => {
        this.amounts = [100, 100, 100, 100]
        const tasks = []
        for (let i = 0; i < 4; i++) {
            this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
            tasks.push(this.reserves[i].mint(alice, this.amounts[i]))
            tasks.push(this.reserves[i].approve(this.yVaultZap.address, this.amounts[i]))
        }
        await Promise.all(tasks)
        await this.yVaultZap.mint(this.amounts, '0')
        assert.strictEqual(fromWei(await this.dusd.balanceOf(alice)), '400')
    })

    it('deposit', async () => {
        assert.strictEqual((await this.ibDusd.balanceOf(alice)).toString(), '0')

        const amount = toWei('100')
        await this.client.approve('100', { from: alice })
        assert.strictEqual(await this.client.allowance(alice), amount)
        await this.client.deposit('100', { from: alice })
        assert.strictEqual(await this.client.allowance(alice), '0')

        assert.strictEqual((await this.ibDusd.getPricePerFullShare()).toString(), toWei('1'))
        assert.strictEqual((await this.dusd.balanceOf(this.ibDusd.address)).toString(), toWei('100'))
        const { ibDusd, dusd, withrawable } = await this.client.balanceOf(alice)
        assert.strictEqual(ibDusd, amount)
        assert.strictEqual(dusd, toWei('300'))
        assert.strictEqual(withrawable, toWei('100'))
    })

    it('withdraw', async () => {
        const yVaultPeakTest2 = await YVaultPeakTest2.new()
        this.yVaultPeakProxy = await YVaultPeakProxy.deployed()
        await this.yVaultPeakProxy.updateImplementation(yVaultPeakTest2.address)
        this.yVaultPeak = await YVaultPeakTest2.at(YVaultPeakProxy.address)

        await this.yVaultPeak.dummyIncrementVirtualPrice();
        assert.strictEqual((await this.ibDusd.getPricePerFullShare()).toString(), toWei('1.4')) // 140 / 100

        await this.client.withdraw(null, true /* isMax */, { from: alice })
        // OR
        // await this.client.withdraw('140', false, { from: alice })

        const actual = (await Promise.all([
            this.dusd.balanceOf(this.ibDusd.address),
            this.ibDusd.totalSupply(),
            this.ibDusd.getPricePerFullShare() // back to one post-withdraw
        ])).map(v => v.toString())
        const expected = [ toWei('0.7'), '0', toWei('1') ]

        for (let i = 0; i < expected.length; i++) {
            assert.strictEqual(actual[i], expected[i])
        }

        const { ibDusd, dusd, withrawable } = await this.client.balanceOf(alice)
        assert.strictEqual(ibDusd, '0')
        assert.strictEqual(dusd, toWei('439.3') /* 300 + .995 * 140 */)
        assert.strictEqual(withrawable, '0')
    })

    it('transfer residue to owner', async () => {
        const ibDusdProxy = await ibDUSDProxy.deployed()
        await ibDusdProxy.transferOwnership(accounts[9])
        await this.yVaultPeak.dummyIncrementVirtualPrice();

        const amount = toWei('100')
        await this.dusd.approve(this.ibDusd.address, amount)
        await this.ibDusd.deposit(amount)

        const actual = (await Promise.all([
            this.dusd.balanceOf(alice),
            this.dusd.balanceOf(this.ibDusd.address),
            this.ibDusd.balanceOf(alice),
            this.ibDusd.totalSupply(),
            this.ibDusd.getPricePerFullShare(),
            this.dusd.balanceOf(accounts[9])
        ])).map(v => v.toString())

        // virtual_price = 1.1 ^ 2, totalSystemAssets = 1.21 * 400 = 484
        // (440 - 0.7) was withdrawn, so 44.7 has accrued before someone stakes again
        const expected = [ toWei('339.3'), toWei('100'), toWei('100'), toWei('100'), toWei('1'), toWei('44.7') ]

        for (let i = 0; i < expected.length; i++) {
            assert.strictEqual(actual[i], expected[i])
        }
    })
})
