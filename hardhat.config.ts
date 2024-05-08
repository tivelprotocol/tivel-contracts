// hardhat.config.ts

import "dotenv/config"
import "@nomiclabs/hardhat-etherscan"
import "@nomiclabs/hardhat-solhint"
import "@nomiclabs/hardhat-ethers"
import "@nomiclabs/hardhat-waffle"
// import "@nomiclabs/hardhat-ganache"
import "@openzeppelin/hardhat-upgrades"
import "@typechain/hardhat"
import "hardhat-abi-exporter"
import "hardhat-deploy"
import "hardhat-deploy-ethers"
import "hardhat-gas-reporter"
import "hardhat-spdx-license-identifier"
import "hardhat-watcher"
import "solidity-coverage"

import { HardhatUserConfig } from "hardhat/types"
import { removeConsoleLog } from "hardhat-preprocessor"

const accounts = {
  mnemonic: process.env.MNEMONIC || "test test test test test test test test test test test junk",
  // accountsBalance: "990000000000000000000",
}

const config: HardhatUserConfig = {
  abiExporter: {
    path: "./abi",
    clear: false,
    flat: true,
    // only: [],
    // except: []
  },
  defaultNetwork: "hardhat",
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  mocha: {
    timeout: 20000,
  },
  networks: {
    localhost: {
      live: false,
      saveDeployments: true,
      tags: ["local"],
    },
    hardhat: {
      allowUnlimitedContractSize: false
    },
    mainnet: {
      url: `https://eth.llamarpc.com`,
      accounts,
      // gasPrice: 120 * 1000000000,
      chainId: 1,
    },
    goerli: {
      url: "https://ethereum-goerli.publicnode.com",
      accounts,
      chainId: 5,
      live: true,
      saveDeployments: true,
    },
    sepolia: {
      url: "https://rpc.sepolia.org",
      accounts,
      chainId: 11155111,
      live: true,
      saveDeployments: true,
    },
    arbitrumtest: {
      url: "https://goerli-rollup.arbitrum.io/rpc",
      accounts,
      chainId: 421613,
      live: true,
      saveDeployments: true,
    },
    arbitrum: {
      // url: "https://arbitrum.llamarpc.com",
      url: `https://arb-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_KEY ?? ''}`,
      accounts,
      chainId: 42161,
      live: true,
      saveDeployments: true,
    },
  },
  paths: {
    artifacts: "artifacts",
    cache: "cache",
    deploy: "deploy",
    deployments: "deployments",
    imports: "imports",
    sources: "contracts",
    tests: "test",
  },
  preprocess: {
    eachLine: removeConsoleLog((bre) => bre.network.name !== "hardhat" && bre.network.name !== "localhost"),
  },
  solidity: {
    compilers: [
      {
        version: "0.8.7",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.7.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.4.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: true,
  },
  watcher: {
    compile: {
      files: ["./contracts"],
      verbose: true,
    },
  },
}

export default config
