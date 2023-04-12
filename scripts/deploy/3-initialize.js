const {ethers} = require('hardhat');

async function initializeVault(vaultAddress, strategyAddress) {
  const Vault = await ethers.getContractFactory('ReaperVaultV2');
  const vault = Vault.attach(vaultAddress);

  await vault.addStrategy(strategyAddress, 1000, 9000); // feeBPS = 1000, allocBPS = 9000
  console.log('Vault initialized');
}

async function main() {
  // WFTM
  await initializeVault(
    '0x963ffcd14D471E279245eE1570ad64ca78d8e67E',
    '0xeaC9d3DFD1AEa8C27FbA6B1A630d28Ad2a904E6e'
  );
  // USDC
  await initializeVault(
    '0xd55C59Da5872DE866e39b1e3Af2065330ea8Acd6',
    '0x55931Fcc38AD5Ef95AB9f478B201Df24299E0f19'
  );
  // DAI
  await initializeVault(
    '0x16E4399FA9ba6e58F12BF2d2bC35f8BdE8a9a4aB',
    '0x0Ae44f2838a706A283664e9ddF8c9b3E26a29c98'
  );
  // WETH
  await initializeVault(
    '0xfA985463B7FA975d06cde703EC72eFCcF293c605',
    '0xac975240B1388E3B61574b595694004E5a6c5244'
  );
  // WBTC
  await initializeVault(
    '0xC052627bc73117d2CB3569f133419550156bdFa1',
    '0x2fDf1594e3b0354DE47415Fd16f7C31374e7c7fC'
  );
  // fUSDT
  await initializeVault(
    '0xAea55C0E84aF6e5eF8C9B7042fB6aB682516214A',
    '0xc27c182f1945c4D23A657C9e9d607E46379EEff8'
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
