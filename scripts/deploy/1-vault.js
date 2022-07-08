async function main() {
  const Vault = await ethers.getContractFactory('ReaperVaultV2');

  const wantAddress = '0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83';
  const tokenName = 'WFTM Crypt';
  const tokenSymbol = 'rfWFTM';
  const tvlCap = ethers.utils.parseEther('1000');

  const strategist1 = '0x1E71AEE6081f62053123140aacC7a06021D77348';
  const strategist2 = '0x81876677843D00a7D792E1617459aC2E93202576';
  const strategist3 = '0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4';
  const superAdmin = '0x04C710a1E8a738CDf7cAD3a52Ba77A784C35d8CE';
  const admin = '0x539eF36C804e4D735d8cAb69e8e441c12d4B88E0';
  const guardian = '0xf20E25f2AB644C8ecBFc992a6829478a85A98F2c';
  const strategists = [strategist1, strategist2, strategist3];
  const multisigRoles = [superAdmin, admin, guardian];

  const vault = await Vault.deploy(wantAddress, tokenName, tokenSymbol, tvlCap, strategists, multisigRoles);

  await vault.deployed();
  console.log('Vault deployed to:', vault.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
