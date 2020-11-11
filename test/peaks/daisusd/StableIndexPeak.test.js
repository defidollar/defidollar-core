const assert = require('assert')
const _deploy_stable_index_peak = require('../../../migrations/4_deploy_stable_index_peak.js')
const utils = require('../../utils.js')

const toWei = web3.utils.toWei
const fromWei = web3.utils.fromWei
const toBN = web3.utils.toBN

const reserveAssets = 2

contract('StableIndexZap', async (accounts) => {
    let alice = accounts[0]

    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)

        this.amounts = [200, 200] // aDAI, aSUSD
        const tasks = []
        for (let i = 0; i < reserveAssets; i++) {
            this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
            tasks.push(this.reserves[i].mint(alice, this.amounts[i]))
        }
        await Promise.all(tasks)

        // Mint aDAI and aSUSD

    })

    it('StableIndexPeak', async () => {
       this.amounts = [100, 100]
       const tasks = []
       for (let i = 0; i  < reserveAssets; i++) {
           this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
           tasks.push(thus.reserves[i].approve(this.stableIndexZap.address, this.amounts[i]))
       }
       await Promise.all(tasks)
       await this.stableIndexPeak.mint(this.amounts)
       assert.equal(fromWei(await this.aDAI.balanceOf(this.bPool.address)), '100');
       assert.equal(fromWei(await this.aSUSD.balanceOf(this.bPool.address)), '100');
       assert.equal(fromWei(await this.crp.balanceOf()))
    })

})
