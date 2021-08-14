async function setupMainnetContracts(blockNumber = 12440145) {
    await network.provider.request({
        method: "hardhat_reset",
        params: [{
            forking: {
                jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY}`,
                blockNumber // having a consistent block number speeds up the tests across runs
            }
        }]
    })

    return ethers.getContractAt('UpgradableProxy', '0xA89BD606d5DadDa60242E8DEDeebC95c41aD8986')
}

async function impersonateAccount(account) {
    await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [account],
    })
}

module.exports = {
    setupMainnetContracts,
    impersonateAccount
}
