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
    '0xe9dB3EF97f2e18A7D5093eD8a3B961b3aC3C81a8',
    '0x601215a39a5e1886Da8DC99F15ac0D17C03F4a21'
  );
  // USDC
  await initializeVault(
    '0x914AA7Fcfc0EE1277dA731058f4700A25102d128',
    '0xB28c4824c355af8e1aA48670298dBd1d52db6aa7'
  );
  // DAI
  await initializeVault(
    '0x60908475bDa9dB9157CEd49AAD8255C32b0150C8',
    '0xD4d1888AFB6A58237e80353B7407cC71b6148C55'
  );
  // WETH
  await initializeVault(
    '0x574E8861eE04CC2838401c481BB6FeA2B9a40794',
    '0x4b9028F0230Ab3f025E0683f8E515b546e571a04'
  );
  // WBTC
  await initializeVault(
    '0x0F8a93CE3be89a5CbF7153f7f7DcFb405A085e83',
    '0xA4de751dd479c4e1418350E3B54225aa47cDaa3F'
  );
  // fUSDT
  await initializeVault(
    '0x76C28169e370CbC21452caf28Fed2122Cee92F26',
    '0x2b3d9A2A4B3EB0ac0F6c1B18885285657887b357'
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
