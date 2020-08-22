const fs = require('fs')

function execute() {
    const data = JSON.parse(
        fs.readFileSync(`${process.cwd()}/scripts/simulations/archive-data-aug.json`).toString()
    )
    const blocks = Object.keys(data)
    console.log(blocks)
    const minified = [blocks[0]]
    for (let i = 1; i < blocks.length; i++) {
        const blockNum = blocks[i]
        for (let j = 0; j < data[blocks[i]].length; j++) {
            if (data[blockNum][j] != data[minified[minified.length-1]][j]) {
                minified.push(blockNum)
                break
            }
        }
    }

    const obj = {}
    console.log(minified)
    for (let i = 0; i < minified.length; i++) {
        obj[minified[i]] = data[minified[i]]
    }
    fs.writeFileSync(
        `${process.cwd()}/scripts/simulations/archive-data-aug-min.json`,
        JSON.stringify(obj, null, 2) // Indent 2 spaces
    )
}

execute()
