const assert = require('assert')
const utils = require('../../utils.js')

const toWei = web3.utils.toWei
const fromWei = web3.utils.fromWei
const toBN = web3.utils.toBN
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
        it('Adding same peak fails', async () => {
            try {
                await this.controller.addPeak(this.yVaultPeak.address, {from: this.owner})
                assert.fail('expected to fail')
            } catch (e) {
                assert.strictEqual(e.reason, 'Peak is already added')
            }
        })

        it('Owner can add Peak', async () => {
            const arbitraryPeakAddress = this.core.address
            await this.controller.addPeak(arbitraryPeakAddress, {from: this.owner})
            const result = await this.controller.peaks.call(arbitraryPeakAddress)
            assert.strictEqual(result, true, "Error: Owner could not add peak")
        })

        it('Adding vault for same token fails', async () => {
            try {
                await this.controller.addVault(this.yCrv.address, this.yVault.address, { from: this.owner })
                assert.fail('expected to fail')
            } catch (e) {
                assert.strictEqual(e.reason, 'vault is already added for token')
            }
        })

        it('Owner can add vault', async () => {
            const arbitraryTokenAddress = this.reserves[0].address
            const arbitraryVaultAddress = this.core.address
            await this.controller.addVault(arbitraryTokenAddress, arbitraryVaultAddress, { from: this.owner })
            const result = await this.controller.vaults.call(arbitraryTokenAddress)
            assert.strictEqual(result, arbitraryVaultAddress, "Error: Owner could not add vault")
        })

        it('User cannot add Peak', async () => {
            try {
                await this.controller.addPeak(this.yVaultPeak.address, {from: this.user})
                assert.fail('expected to fail')
            }
            catch (e) {
                assert.equal(e.reason, 'NOT_OWNER')
            }
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
    })

    // Peak tests
    describe('Only Peak', async () => {

        it('redeem in Yusd', async () => {
            const dusd = toWei('10')
            await this.yVaultPeak.redeemInYusd(dusd, '0')
            const dusd_balance = await this.dusd.balanceOf(this.owner)
            const yUSD_balance = await this.yVault.balanceOf(this.owner)
            const controller_balance = await this.yVault.balanceOf(this.controller.address)
            const peak_balance = await this.yCrv.balanceOf(this.yVaultPeak.address)
            assert.equal(fromWei(dusd_balance), '390')
            assert.equal(fromWei(yUSD_balance), '10')
            assert.equal(fromWei(controller_balance), '370')
            assert.equal(fromWei(peak_balance), '20')
        })

        it('redeem entire balance in Yusd', async () => {
            const dusd = toWei('390')
            await this.yVaultPeak.redeemInYusd(dusd, '0')
            const dusd_balance = await this.dusd.balanceOf(this.owner)
            const yUSD_balance = await this.yVault.balanceOf(this.owner)
            const controller_balance = await this.yVault.balanceOf(this.controller.address)
            const peak_balance = await this.yCrv.balanceOf(this.yVaultPeak.address)
            assert.equal(fromWei(dusd_balance), '0')
            assert.equal(fromWei(yUSD_balance), '400') // Should mint 400 to solve bug
            assert.equal(fromWei(controller_balance), '0')
            assert.equal(fromWei(peak_balance), '0')
        })

        it('redeem in Ycrv', async () => {
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
            const dusd_balance = await this.dusd.balanceOf(this.owner)
            const yVault_balance = await this.yVault.balanceOf(this.controller.address)
            const yCRV_balance = await this.yCrv.balanceOf(this.owner)
            const peak_balance = await this.yCrv.balanceOf(this.yVaultPeak.address)
            assert.equal(fromWei(dusd_balance), '300') // 400 - 100
            assert.equal(fromWei(yCRV_balance), '100')
            assert.equal(fromWei(yVault_balance), '300') // 400 - (100-20)
            assert.equal(fromWei(peak_balance), '0') // yCRV Peak drained
        })

        it('redeem entire balance in Ycrv', async () => {
            const dusd = toWei('300')
            await this.yVaultPeak.redeemInYcrv(dusd, '0')
            const dusd_balance = await this.dusd.balanceOf(this.owner)
            const yVault_balance = await this.yVault.balanceOf(this.controller.address)
            const yCRV_balance = await this.yCrv.balanceOf(this.owner)
            const peak_balance = await this.yCrv.balanceOf(this.yVaultPeak.address)
            assert.equal(fromWei(dusd_balance), '0')
            assert.equal(fromWei(yCRV_balance), '400')
            assert.equal(fromWei(yVault_balance), '0') // Remaining yCRV (20 yCRV from peak used)
            assert.equal(fromWei(peak_balance), '0')
        })
    })
})
