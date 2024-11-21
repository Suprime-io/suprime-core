const hre = require("hardhat");
const { SABLER, TREASURY_FEE_RECIPIENT, TREASURY } = require('./addresses_lookup')

async function main() {

  const deployerAddr = (await hre.ethers.getSigners())[0];

  const pool = await hre.ethers.deployContract("LiquidityBootstrapPool", [SABLER[hre.network.name]]);
  await pool.waitForDeployment();
  console.log(
    `LiquidityBootstrapPool with SABLER address  ${SABLER[hre.network.name]} deployed to ${pool.target}`
  );

  //verify
  if (hre.network.name !== 'localhost') {
    console.log('Waiting before verification....')
    const delay = ms => new Promise(res => setTimeout(res, ms));
    await delay(15000);
    await hre.run("verify:verify", {
      address: pool.target,
      constructorArguments: [
        SABLER[hre.network.name]
      ],
    });
  }


  const factoryArgs = [
    pool.target,
    deployerAddr.address,
    TREASURY[hre.network.name],
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
  //TODO TransferOwnership: ProxyAdmin

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
