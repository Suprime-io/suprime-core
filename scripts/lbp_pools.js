const hre = require("hardhat");
const { SABLER, TREASURY_FEE_RECIPIENT } = require('./addresses_lookup')

async function main() {

  const deployerAddr = (await hre.ethers.getSigners())[0];

  const pool = await hre.ethers.deployContract("LiquidityBootstrapPool", [SABLER[hre.network.name]]);
  await pool.waitForDeployment();
  console.log(
    `LiquidityBootstrapPool with SABLER address  ${SABLER[hre.network.name]} deployed to ${pool.target}`
  );

  //verify
  if (hre.network.name !== 'localhost') {
    await hre.run("verify:verify", {
      address: pool.target,
      constructorArguments: [
        SABLER[hre.network.name]
      ],
    });
  }

  const treasury = await hre.ethers.deployContract("Treasury", [TREASURY_FEE_RECIPIENT[hre.network.name]]);
  await treasury.waitForDeployment();
  console.log(
    `Treasury deployed to ${treasury.target}`
  );

  //verify
  if (hre.network.name !== 'localhost') {
    await hre.run("verify:verify", {
      address: treasury.target,
      constructorArguments: [
        TREASURY_FEE_RECIPIENT[hre.network.name]
      ],
    });
  }

  const factoryArgs = [
    pool.target,
    deployerAddr.address,
    treasury.target,
    '400',            //4%, _platformFee
    '0',              //0%, _referrerFee
    '300'             //3%, _swapFee
  ];
  const factory = await hre.ethers.deployContract("LiquidityBootstrapPoolFactory", factoryArgs);
  await factory.waitForDeployment();
  console.log(
    `Factory deployed to ${factory.target}`
  );

  //verify
  if (hre.network.name !== 'localhost') {
    await hre.run("verify:verify", {
      address: factory.target,
      constructorArguments: factoryArgs,
    });
  }

  //TODO TransferOwnership: LiquidityBootstrapPoolFactory
  //TODO Update recipients: Treasury
  //TODO TransferOwnership: Treasury
  //TODO TransferOwnership: ProxyAdmin

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
