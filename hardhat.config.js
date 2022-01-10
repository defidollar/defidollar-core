require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
const PRIVATE_KEY = `0x${process.env.PRIVATE_KEY || 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'}`

module.exports = {
    solidity: {
        compilers: [
            {
                "version": "0.5.17",
            },
            {
                "version": "0.6.11",
            }
        ]
    },
    networks: {
        local: {
            url: 'http://localhost:8545'
        },
        kovan: {
            url: `https://kovan.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
            chainId: 42,
            gasPrice: 10000000000, // 10 gwei
            accounts: [ PRIVATE_KEY ]
        },
        mainnet: {
            url: `https://mainnet.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
            chainId: 1,
            accounts: [ PRIVATE_KEY ]
        }
    },
    etherscan: {
        apiKey: `${process.env.ETHERSCAN || ''}`
    },
    mocha: {
        timeout: 0
    }
};
