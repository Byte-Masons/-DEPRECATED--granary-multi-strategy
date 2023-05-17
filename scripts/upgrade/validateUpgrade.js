const { ethers, upgrades } = require("hardhat");

async function validateUpgrade(proxyAddress) {
  const StrategyV2 = await ethers.getContractFactory("ReaperStrategyGranaryV2");
  await upgrades.validateUpgrade(proxyAddress, StrategyV2, { kind: "uups" });
}

async function main() {
  await validateUpgrade("0xeaC9d3DFD1AEa8C27FbA6B1A630d28Ad2a904E6e"); // WFTM
  await validateUpgrade("0x55931Fcc38AD5Ef95AB9f478B201Df24299E0f19"); // USDC
  await validateUpgrade("0x0Ae44f2838a706A283664e9ddF8c9b3E26a29c98"); // DAI
  await validateUpgrade("0xac975240B1388E3B61574b595694004E5a6c5244"); // WBTC
  await validateUpgrade("0x2fDf1594e3b0354DE47415Fd16f7C31374e7c7fC"); // WETH
  await validateUpgrade("0xc27c182f1945c4D23A657C9e9d607E46379EEff8"); // fUSDT
  console.log("upgrades validated");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });