const assert = require('assert')

const utils = require('../utils.js')
const { ibDFDClient } = require('@defidollar/core-client-lib')
const config = require('../../deployments/development.json')

const fromWei = web3.utils.fromWei
const toWei = web3.utils.toWei
const toBN = web3.utils.toBN

contract('ibDFD', async (accounts) => {
    const [ alice, bob, charlie ] = accounts

    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)
        this.reserves = this.reserves.slice(0, 3).concat([this.reserves[4]])
        this.client = new ibDFDClient(web3, config)
        await this.dfd.mint(alice, toWei('400'))
    })

    it('yVaultZap.mint', async () => {
        this.amounts = [100, 100, 100, 100]
        const tasks = []
        for (let i = 0; i < 4; i++) {
            this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
            tasks.push(this.reserves[i].mint(bob, this.amounts[i]))
            tasks.push(this.reserves[i].approve(this.yVaultZap.address, this.amounts[i], { from: bob }))
        }
        await Promise.all(tasks)
        await this.yVaultZap.mint(this.amounts, '0', { from: bob })
        assert.strictEqual(fromWei(await this.dusd.balanceOf(bob)), '400')
    })

    it('deposit', async () => {
        assert.strictEqual((await this.ibDfd.balanceOf(alice)).toString(), '0')

        const amount = toWei('100')
        await this.client.approve('100', { from: alice })
        assert.strictEqual(await this.client.allowance(alice), amount)
        await this.client.deposit('100', { from: alice })
        assert.strictEqual(await this.client.allowance(alice), '0')

        assert.strictEqual((await this.ibDfd.getPricePerFullShare()).toString(), toWei('1'))
        assert.strictEqual((await this.dfd.balanceOf(this.ibDfd.address)).toString(), toWei('100'))
        const { ibDfd, dfd, withrawable } = await this.client.balanceOf(alice)
        assert.strictEqual(ibDfd, amount)
        assert.strictEqual(dfd, toWei('300'))
        assert.strictEqual(withrawable, toWei('100'))
    })

    it('income accrues to ibDfdComptroller', async () => {
        this.yVaultPeak = await utils.swapToMockYvault()
        await this.yVaultPeak.dummyIncrementVirtualPrice()
        await this.comptroller.harvest()
        /*
            dummyIncrementVirtualPrice bumps the virtual price by 10%
            Since there are 400 dfd/yCRV LP tokens, net system revenue = $40
            Revenue sharing of 75:25 b/w ibDfd:ibDFD is hardcoded in migrations, so net revenue is $10 for ibDfd
        */
       assert.strictEqual((await this.dusd.balanceOf(this.ibDfdComptroller.address)).toString(), toWei('10'))
    })

    it('harvest', async () => {
        await this.ibDfdComptroller.harvest()
        assert.strictEqual(fromWei(await this.dusd.balanceOf(this.ibDfdComptroller.address)), '0')
        assert.strictEqual(fromWei(await this.dfd.balanceOf(this.ibDfdComptroller.address)), '0') // transferred to ibdusd

        // mock uniswap implementation, gives 2x of the input token supplied, so 20 DFD are expected
        assert.strictEqual(fromWei(await this.dfd.balanceOf(this.ibDfd.address)), '120') // deposited=100 + harvested=20
        assert.strictEqual(fromWei(await this.ibDfd.getPricePerFullShare()), '1.2') // 120 / 100
    })

    it('notifyRewardAmount', async () => {
        this.rewardAmount = toWei('100')
        await this.dfd.mint(charlie, this.rewardAmount)
        await this.dfd.approve(this.ibDfdComptroller.address, this.rewardAmount, { from: charlie })
        try {
            await this.ibDfdComptroller.notifyRewardAmount(this.rewardAmount, { from: charlie })
            assert.fail('expected to fail')
        } catch (e) {
            assert.equal(e.reason, 'Caller is not reward distribution')
        }

        await this.ibDfdComptroller.setRewardDistribution(charlie)
        await this.ibDfdComptroller.notifyRewardAmount(this.rewardAmount, { from: charlie })
        assert.strictEqual(
            (await this.dfd.balanceOf(this.ibDfdComptroller.address)).toString(),
            this.rewardAmount
        )
    })

    it('rewards are accruing from notifyReward', async () => {
        this.ibDfdComptroller.increaseBlockTime(86400)
        this.availableReward = await this.ibDfdComptroller.availableReward()
        assert.strictEqual(parseInt(fromWei(this.availableReward)), 14) // notifyRewardAmount=100, in a day floor(availableReward)=14
        // pricePerFullShare = 1.2 + (14/100) = 1.34
        assert.strictEqual(fromWei(await this.ibDfd.getPricePerFullShare()).substr(0, 4), '1.34')
    })


    it('withdraw', async () => {
        await this.client.withdraw(null, true /* isMax */, { from: alice })

        assert.strictEqual(fromWei(await this.dfd.balanceOf(this.ibDfd.address)).substr(0, 4), '0.67')
        assert.strictEqual(fromWei(await this.ibDfd.totalSupply()), '0')
        assert.strictEqual(fromWei(await this.ibDfd.getPricePerFullShare()), '1') // back to one post-withdraw

        const { ibDfd, dfd, withrawable } = await this.client.balanceOf(alice)
        assert.strictEqual(ibDfd, '0')
        assert.strictEqual(parseInt(fromWei(dfd)), 433) // previous=300 + withdrawn = (.995 * 134) = 433.33
        assert.strictEqual(withrawable, '0')
    })
})
