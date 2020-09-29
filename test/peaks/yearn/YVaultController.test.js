const assert = require('assert')
const utils = require('../../utils.js')

const toWei = web3.utils.toWei
const fromWei = web3.utils.fromWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1)
const n_coins = 4


contract('YVaultController', async (accounts) => {

    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)
        this.owner = accounts[0]
        this.user = accounts[1]

        this.amounts = [200, 200, 200, 200] // dai, usdc, usdt, tusd
        this.reserves = this.reserves.slice(0, 3).concat([this.reserves[4]])
        const tasks = []
        for (let i = 0; i < n_coins; i++) {
            this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i])) // convert amounts
            tasks.push(this.reserves[i].mint(this.owner, this.amounts[i])) // mint user
        }
        await Promise.all(tasks)
    })

    // Owner tests
    describe('Only Owner', async () => {

        it('Owner can add Peak', async () => {
            await this.controller.addPeak(this.yVaultPeak.address, {from: this.owner})
            const result = await this.controller.peaks.call(this.yVaultPeak.address)
            assert.equal(result, true, "Error: Owner could not add peak")
        })
        
        it('Owner can add vault', async () => {
            await this.controller.addVault(this.yCrv.address, this.yVault.address, {from: this.owner})
            const result = await this.controller.vaults.call(this.yCrv.address)
            assert.equal(result, this.yVault.address, "Error: Owner could not add vault")
        })

        it('User cannot add Peak', async () => {
            let reverted = false
            try {
                await this.controller.addPeak(this.yVaultPeak.address, {from: this.user})
            }
            catch (e) {
                reverted = true
                assert.equal(e.reason, 'NOT_OWNER')
            }
            assert.equal(reverted, true)
        })

        it('User cannot add Vault', async () => {
            let reverted = false
            try {
                await this.controller.addVault(this.yCrv.address, this.yVault.address, {from: this.user})
            }
            catch (e) {
                reverted = true
                assert.equal(e.reason, 'NOT_OWNER')
            }
            assert.equal(reverted, true)
        })
    })

    it('Earn', async () => {
        this.amounts = [100, 100, 100, 100]
        const tasks = []
        for (let i = 0; i < n_coins; i++) {
            this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
            tasks.push(this.reserves[i].approve(this.yVaultZap.address, this.amounts[i]))
        }
        await Promise.all(tasks)
        await this.yVaultZap.mint(this.amounts, '0')
        assert.equal(fromWei(await this.dusd.balanceOf(this.owner)), '400')
        assert.equal(fromWei(await this.yCrv.balanceOf(this.controller.address)), '0')
        assert.equal(fromWei(await this.yVault.balanceOf(this.controller.address)), '380')
        console.log(fromWei(await this.yVault.balanceOf(this.controller.address)))
    })

    // Peak tests
    describe('Only Peak', async () => {

        it('withdraw(): peak withdraw amount from controller', async () => {
            const dusd = toWei('10') 
            await this.yVaultPeak.redeemInYusd(dusd, '0')
            const dusd_balance = await this.dusd.balanceOf(this.owner)
            const yUSD_balance = await this.yVault.balanceOf(this.owner)
            const controller_balance = await this.yVault.balanceOf(this.controller.address)
            console.log('DUSD: ' + fromWei(dusd_balance))
            console.log('yUSD: ' + fromWei(yUSD_balance))
            console.log('Controller: ' + fromWei(controller_balance))
            assert.equal(fromWei(dusd_balance), '390')
            assert.equal(fromWei(yUSD_balance), '10')
            assert.equal(fromWei(controller_balance), '370')
        })

        it('withdraw(): peak withdraw entire controller balance', async () => {
            const dusd = toWei('390')
            await this.yVaultPeak.redeemInYusd(dusd, '0')
            const dusd_balance = await this.dusd.balanceOf(this.owner)
            const yUSD_balance = await this.yVault.balanceOf(this.owner)
            const controller_balance = await this.yVault.balanceOf(this.controller.address)
            console.log('DUSD: ' + fromWei(dusd_balance))
            console.log('yUSD: ' + fromWei(yUSD_balance))
            console.log('Controller: ' + fromWei(controller_balance))
            assert.equal(fromWei(dusd_balance), '0')
            assert.equal(fromWei(yUSD_balance), '380')
            assert.equal(fromWei(controller_balance), '0')
        }) 
        
        it('vaultWithdraw(): peak withdraws shares', async () => {
            // Restore balances
            this.amounts = [100, 100, 100, 100]
            const tasks = []
            for (let i = 0; i < n_coins; i++) {
                this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
                tasks.push(this.reserves[i].approve(this.yVaultZap.address, this.amounts[i]))
            }
            await Promise.all(tasks)
            await this.yVaultZap.mint(this.amounts, '0')
            // Continue testing
            const dusd = toWei('100')
            await this.yVaultPeak.redeemInYcrv(dusd, '0')
            const yVault_balance = await this.yVault.balanceOf(this.controller.address)
            const yCRV_balance = await this.yCrv.balanceOf(this.owner)
            const peak_balance = await this.yCrv.balanceOf(this.yVaultPeak.address)
            console.log(fromWei(await this.yVault.balanceOf(this.controller.address)))
            console.log('yUSD: ' + fromWei(yVault_balance))
            console.log('yCRV: ' + fromWei(yCRV_balance))
            // Balances check
            assert.equal(fromWei(await this.dusd.balanceOf(this.owner)), '300')
            assert.equal(fromWei(await this.yCrv.balanceOf(this.controller.address)), '0')
            assert.equal(fromWei(await this.yVault.balanceOf(this.controller.address)), '320')
            // Test assertions
            assert.equal(fromWei(yCRV_balance), '100')
            assert.equal(fromWei(yVault_balance), '320')
            assert.equal(fromWei(peak_balance), '0')
        })

        it('vaultWithdraw(): peak withdraws entire vault balance', async () => {
            const dusd = toWei('300') 
            await this.yVaultPeak.redeemInYcrv(dusd, '0')
            const yVault_balance = await this.yVault.balanceOf(this.controller.address)
            const yCRV_balance = await this.yCrv.balanceOf(this.owner)
            const peak_balance = await this.yCrv.balanceOf(this.yVaultPeak.address)
            console.log('yUSD: ' + fromWei(yVault_balance))
            console.log('yCRV: ' + fromWei(yCRV_balance))
            assert.equal(fromWei(yCRV_balance), '400')
            assert.equal(fromWei(yVault_balance), '20')
            assert.equal(fromWei(peak_balance), '0')
        })
    })
})
