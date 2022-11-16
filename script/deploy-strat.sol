// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {MultiRolesAuthority} from
  "solmate/auth/authorities/MultiRolesAuthority.sol";
import {StratX4Compounding} from "autofarm-v3-core/StratX4Compounding.sol";
import {StratX4MinichefLP1} from "../src/MinichefLP1.sol";
import {StratX4MasterchefLP1} from "../src/MasterchefLP1.sol";

import {
  StratConfigJsonLib,
  EarnConfig
} from "../src/json-parsers/StratConfigJsonLib.sol";

contract DeployStrat is Script, Test {
  using stdJson for string;

  address public stratAddress;
  bytes32 public salt = keccak256("autofarm-strat-v3.0.1");

  function run() public {
    vm.startBroadcast();
    deployStrat();
    vm.stopBroadcast();
  }

  function deployStrat() public {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/", vm.envString("STRAT_CONFIG_FILE"));
    string memory json = vm.readFile(path);
    string memory stratContract = json.readString(".StratContract");

    if (keccak256(bytes(stratContract)) == keccak256("MinichefLP1.sol:StratX4MinichefLP1")) {
      deployMinichefLP1(json);
    }
    else if (keccak256(bytes(stratContract)) == keccak256("MasterchefLP1.sol:StratX4MasterchefLP1")) {
      deployMasterchefLP1(json);
    }
  }

  function deployMinichefLP1(string memory json) internal {
    (
      address asset,
      address farmContractAddress,
      uint256 pid,
      EarnConfig[] memory earnConfigs
    ) = StratConfigJsonLib.parse(vm, json);

    console2.log("asset", asset);
    console2.log("farmContractAddress", farmContractAddress);
    console2.log("pid", pid);

    StratX4Compounding strat = new StratX4MinichefLP1{salt: salt}(
      asset,
      vm.envAddress("FEES_CONTROLLER_ADDRESS"),
      MultiRolesAuthority(vm.envAddress("AUTHORITY_ADDRESS")),
      farmContractAddress,
      pid,
      earnConfigs[0].rewardToken,
      earnConfigs[0].swapRoute,
      earnConfigs[0].zapLiquidityConfig
    );
    stratAddress = address(strat);
    console2.log("Deployed strat", stratAddress);

    for (uint256 i = 1; i < earnConfigs.length; i++) {
      StratX4Compounding(stratAddress).addEarnConfig(
        earnConfigs[i].rewardToken,
        abi.encode(earnConfigs[i].swapRoute, earnConfigs[i].zapLiquidityConfig)
      );
    }
  }

  function deployMasterchefLP1(string memory json) internal {
    (
      address asset,
      address farmContractAddress,
      uint256 pid,
      EarnConfig[] memory earnConfigs
    ) = StratConfigJsonLib.parse(vm, json);

    console2.log("asset", asset);
    console2.log("farmContractAddress", farmContractAddress);
    console2.log("pid", pid);

    StratX4Compounding strat = new StratX4MasterchefLP1{salt: salt}(
      asset,
      vm.envAddress("FEES_CONTROLLER_ADDRESS"),
      MultiRolesAuthority(vm.envAddress("AUTHORITY_ADDRESS")),
      farmContractAddress,
      pid,
      earnConfigs[0].rewardToken,
      earnConfigs[0].swapRoute,
      earnConfigs[0].zapLiquidityConfig
    );
    stratAddress = address(strat);
    console2.log("Deployed strat", stratAddress);

    for (uint256 i = 1; i < earnConfigs.length; i++) {
      StratX4Compounding(stratAddress).addEarnConfig(
        earnConfigs[i].rewardToken,
        abi.encode(earnConfigs[i].swapRoute, earnConfigs[i].zapLiquidityConfig)
      );
    }
  }
}
