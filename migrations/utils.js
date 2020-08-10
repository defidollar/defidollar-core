const fs = require('fs')

function getContractAddresses() {
    return JSON.parse(
        fs.readFileSync(`${process.cwd()}/deployments/development.json`).toString()
    )
}

function writeContractAddresses(contractAddresses) {
    fs.writeFileSync(
        `${process.cwd()}/deployments/development.json`,
        JSON.stringify(contractAddresses, null, 2) // Indent 4 spaces
    )
}

module.exports = {
  getContractAddresses,
  writeContractAddresses
}
