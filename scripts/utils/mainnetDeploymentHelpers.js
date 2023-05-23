const hre = require('hardhat');

async function verifyContract(address, constructorArguments=[]) {
  try {
    await hre.run("verify:verify", {
      address: address,
      constructorArguments,
    })
  } catch (error) {
    if (error.name != 'NomicLabsHardhatPluginError') {
      console.error(`Error verifying: ${error.name}`)
      console.error(error)
      return
    }
  }
}

module.exports = {
    verifyContract
}
