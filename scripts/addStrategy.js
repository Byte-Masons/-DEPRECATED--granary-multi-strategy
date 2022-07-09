async function main() {
  const vaultAddress = '0xa9A9dB466685F977F9ECEe347958bcef90498177';
  const Vault = await ethers.getContractFactory('ReaperVaultV2');
  const vault = Vault.attach(vaultAddress);

  const strategyAddress = '0xCF266AF4b6688352fFD08BAeA9b58ff89ff09A3a';
  const strategyAllocation = 9000;
  await vault.addStrategy(strategyAddress, strategyAllocation);
  console.log('Strategy added!');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
