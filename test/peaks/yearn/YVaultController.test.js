const assert = require('assert')
const utils = require('../../utils.js')

const toWei = web3.utils.toWei
const fromWei = web3.utils.fromWei
const toBN = web3.utils.BN
const MAX = web3.utils.toTwosComplement(-1);
const n_coins = 4

contract('YVaultController', async (accounts) => {

    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)
        this.owner = accounts[0]
        /*
        Init controller with 20 yCRV
        */
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
                console.log(e)
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
                console.log(e)
            }
            assert.equal(reverted, false, "Error: Owner could not add vault")
        })
    })

    // Controller token transfer to yVault test
    it('Earn', async () => {
        let reverted = false
        try {
            const yCRV = await this.yVaultPeak.vars()
            await this.controller.earn(yCRV[2])
        }
        catch (e) {
            reverted = true
            console.log(e)
        }
        // Check balance of yCRV at controller and vault
        assert.equal(reverted, false, "Error: earn() reverted")
        /*
        Add extra assertions for yCRV balance of controller and yVault
        to ensure all controller balance was transferred to the 
        vault 
        */
    })

    // Peak tests
    describe('Only Peak', async () => {
        it('Peak Vault Withdraw', async () => {
            let reverted = false
            let amount = toWei('0')
            try {
                const yCRV = await this.yVaultPeak.vars()
                await this.controller.vaultWithdraw(yCRV[2], amount, {from: this.yVaultPeak.address})
                /*
                Error: sender account not recognised
                Reason: Ganache does not know private key of peak address
                */
            }
            catch (e) {
                reverted = true
                console.log(e)
            }
            assert.equal(reverted, false, "Error: vaultWithdraw() reverted")
            /*
            Additional assert statements to verify yCRV was withdrawn
            to peak from yVault.
            
            const peak_balance = fromWei(await this.yCRV.balanceOf(this.yVaultPeak.address))
            const vault_balance = fromWei(await this.yCRV.balanceOf(this.yVault.address))

            Cannot access yCRV address directly so go through yVaultPeak.vars()
            */
        })

        it('Peak Withdraw', async () => {
            let reverted = false
            let amount = toWei('0') // Change to actual amount
            try {
                const yCRV = await this.yVaultPeak.vars()
                await this.controller.withdraw(yCRV[2], amount, {from: this.yVaultPeak.address})
                /*
                Error: sender account not recognised
                Reason: Ganache does not know private key of peak address
                */
            }
            catch (e) {
                reverted = true
                console.log(e)
            }
            assert.equal(reverted, false, "Error: withdraw() by Peak reverted")
            /*
            Additional assert statements to verify yCRV was withdraw
            to peak from controller.
            
            const controller_balance = fromWei(await this.yCRV.balanceOf(this.controller.address))
            const vault_balance = fromWei(await this.yCRV.balanceOf(this.yVault.address))

            Cannot access yCRV address directly so go through yVaultPeak.vars()
            */
        })
    })

})
