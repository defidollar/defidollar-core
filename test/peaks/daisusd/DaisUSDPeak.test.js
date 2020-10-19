const assert = require('assert')
const utils = require('../../utils.js')

const toWei = web3.utils.toWei
const fromWei = web3.utils.fromWei
const toBN = web3.utils.toBN

contract('DaisUSDPeak', async (accounts) => {
    let alice = accounts[0]

    before(async () => {
        const artifacts = await utils.getArtifacts()
        Object.assign(this, artifacts)

        this.amounts = [200, 200]
        const tasks = []
        for (let i = 0; i < 2; i++) {
            this.amounts[i] = toBN(this.amounts[i]).mul(toBN(10 ** this.decimals[i]))
            tasks.push(this.reserves[i].mint(alice, this.amounts[i]))
        }
        await Promise.all(tasks)
    })

    it('Zap.mint()', async () => {
        /** 
         * TEST CASE:
         * 
         * 1 - Mint 100 aDAI and 100 aSUSD
         * 2 - Mint corresponding amount of DUSD
         * 3 - Ensure liquidity is migrated to CRP
         * 
        */
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
