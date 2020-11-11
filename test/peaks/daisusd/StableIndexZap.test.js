const assert = require('assert')
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
    })

    it('StableIndexZap.mint()', async () => {
       this.amounts = [100, 100]
       const tasks = []
       for (let i = 0; i  < reserveAssets; i++) {
           this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
           tasks.push(thus.reserves[i].approve(this.stableIndexZap.address, this.amounts[i]))
       }
       await Promise.all(tasks)
       await this.StableIndexZap.mint(this.amounts, '0');
       assert.equal(fromWei(await this.dusd.balanceOf(alice), '400')) // dusd amount
       assert.equal(fromWei(await this.aDAI.balanceOf(this.bPool.address)), '100') // bPool aDAI
       assert.equal(fromWei(await this.aSUSD.balanceOf(this.bPool.address)), '100')// bPool aDAI & aSUSD
       const BPT = await this.crp.balanceOf(this.stableIndexPeak.address)
       assert.equal(fromWei(BPT), '') // CRP balancer pool tokens
    })

    it('Peak: swap DAI to DAI/sUSD', async () => {
        /**
         * TEST CASE:
         * 
         * 1 - swap 100 dai to correct ratio of DAI/susd using curve susd pool
         */
    })

    it('Zap.mintWithSingleCoin()', async () => {
        /** 
         * TEST CASE:
         * 
         * 1 - 100 DAI => 67 aDAI/33 sUSD
         * 2 - Mint corresponding amount of DUSD
         * 3 - Ensure liquidity is migrated to CRP
         * 
        */
    })
})
