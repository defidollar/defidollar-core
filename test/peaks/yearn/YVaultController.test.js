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
                let yCRV = await this.yVaultPeak.vars()
                await this.controller.addVault(yCRV[2], this.yVault.address, {from: this.owner})
            }
            catch (e) {
                reverted = true
                console.log(e)
            }
            assert.equal(reverted, false, "Error: Owner could not add vault")
        })
    })

    // Peak tests
    describe('Only Peak', async () => {
        it('Peak Vault Withdraw', async () => {

        })

        it('Peak Withdraw', async () => {

        })
    })

    // Controller token transfer to yVault test
    it('Earn', async () => {

    })

})
