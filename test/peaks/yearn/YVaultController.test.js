const assert = require('assert')
const utils = require('../../utils.js')

const toWei = web3.utils.toWei
const fromWei = web3.utils.fromWei
const toBN = web3.utils.toBN
const MAX = web3.utils.toTwosComplement(-1);
const n_coins = 4


contract('YVaultController', async (accounts) => {

    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)
        this.owner = accounts[0]

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
            let reverted = false
            try {
                await this.controller.addPeak(this.yVaultPeak.address, {from: this.owner})
            }
            catch (e) {
                reverted = true
                assert.equal(e.reason, 'ERR_PEAK')
            }
            assert.equal(reverted, false, "Error: Owner could not add peak")
        })
 
        it('Owner can add vault', async () => {
            let reverted = false
            try {
                const yCRV = await this.yVaultPeak.vars()
                await this.controller.addVault(yCRV[2], this.yVault.address, {from: this.owner})
            }
            catch (e) {
                reverted = true
                assert.equal(e.reason, 'ERR_VAULT')
            }
            assert.equal(reverted, false, "Error: Owner could not add vault")
        })
    })

    // Controller token transfer to yVault test
    it('Earn', async () => {
       /*
       ROUTE

       yVaultZap.mint()

       - msg.sender [dai, usdc, usdt, tusd] => yVaultZap.address
       - yVaultZap [dai, usdc, usdt, tusd] => yDeposit => yVaultZap.address yCRV
       - yVaultPeak.mintWithyCRV() => yVaultPeak.address (yCRV transfer)
       - yVaultPeak yCRV => controller.address
       - controller.earn() => yCRV vault deposit
       */
       let reverted = false
       this.amounts = [100, 100, 100, 100]
       const tasks = []
       for (let i = 0; i < n_coins; i++) {
           this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
           tasks.push(this.reserves[i].approve(this.yVaultZap.address, this.amounts[i]))
       }
       await Promise.all(tasks)
       try {
           await this.yVaultZap.mint(this.amounts, '0')
       }
       catch (e) {
           reverted = true
           assert.equal(e.reason, 'ERR_EARN')
       }
       // Assert statements controller yCRV => yVault
       // All controller yCRV will be deposited into vault
       assert.equal(fromWei(await this.yCrv.balanceOf(this.controller.address)), '0')
       assert.equal(fromWei(await this.yVault.balanceOf(this.controller.address)), '380')
       assert.equal(reverted, false, "Error: earn() reverted")
    })


    // Peak tests
    describe('Only Peak', async () => {

        it('Peak Vault Withdraw', async () => {
            /*
            ROUTE

            yVaultZap.redeemInYCRV()

            - Calc yCRV based on DUSD input
            - If balance Peak > redeem safeTransfer
            - Else controller.vaultWithdraw()
            - vaultWithdraw() calls withdraw()
            */
            let reverted = false
            const dusd = toWei('100')
            try {
                await this.dusd.approve(this.yVaultZap.address, dusd)
                await this.yVaultZap.redeem(dusd, [0,0,0,0])
            }
            catch (e) {
                reverted = true
                assert.equal(e.reason, 'ERR_WITHDRAW')
            }
            // User dusd balance - dusd amount
            // Peak amount redeemed
            // Controller amount redeemed (calc)
            // vault amount redeemed (calc)
            assert.equal(fromWei(await this.yCRV.balanceOf(this.yVaultPeak.address)), '0') // 0 as yCRV is withdrawn from vault
            assert.equal(fromWei(await this.yCRV.balanceOf(this.controller.address)), '')
            assert.equal(fromWei(await this.yVault.balanceOf(this.controller.address)), '')
        })
    })
})
