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

import {
  StratConfigJsonLib,
  EarnConfig
} from "../src/json-parsers/StratConfigJsonLib.sol";

contract DeployStrat is Script, Test {
  using stdJson for string;

  address public strat;

  function run() public {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, vm.envString("STRAT_CONFIG_FILE"));
    string memory json = vm.readFile(path);
    string memory stratContract = json.readString(".StratContract");
    bytes memory creationCode = vm.getCode(stratContract);

    vm.startBroadcast();

    if (keccak256(bytes(stratContract)) == keccak256("MinichefLP1.sol:StratX4MinichefLP1")) {
      deployMinichefLP1(creationCode, json);
    }
    else if (keccak256(bytes(stratContract)) == keccak256("MasterchefLP1.sol:StratX4MasterchefLP1")) {
      deployMasterchefLP1(creationCode, json);
    }

    vm.stopBroadcast();
  }

  function deploy(bytes memory creationCode, bytes memory args) internal returns (address deployed) {
    bytes memory bytecode = abi.encodePacked(creationCode, args);
    assembly {
      deployed := create(0, add(bytecode, 0x20), mload(bytecode))
    }
  }

  function deployMinichefLP1(bytes memory creationCode, string memory json) internal {
    (
      address asset,
      address farmContractAddress,
      uint256 pid,
      EarnConfig[] memory earnConfigs
    ) = StratConfigJsonLib.parse(vm, json);

    console2.log("asset", asset);
    console2.log("farmContractAddress", farmContractAddress);
    console2.log("pid", pid);

    bytes memory args = abi.encode(
      asset,
      vm.envAddress("FEES_CONTROLLER_ADDRESS"),
      MultiRolesAuthority(vm.envAddress("AUTHORITY_ADDRESS")),
      farmContractAddress,
      pid,
      earnConfigs[0].rewardToken,
      earnConfigs[0].swapRoute,
      earnConfigs[0].zapLiquidityConfig
    );
    strat = deploy(creationCode, args);

    for (uint256 i = 1; i < earnConfigs.length; i++) {
      StratX4Compounding(strat).addEarnConfig(
        earnConfigs[i].rewardToken,
        abi.encode(earnConfigs[i].swapRoute, earnConfigs[i].zapLiquidityConfig)
      );
    }
  }

  function deployMasterchefLP1(bytes memory creationCode, string memory json) internal {
    (
      address asset,
      address farmContractAddress,
      uint256 pid,
      EarnConfig[] memory earnConfigs
    ) = StratConfigJsonLib.parse(vm, json);

    console2.log("asset", asset);
    console2.log("farmContractAddress", farmContractAddress);
    console2.log("pid", pid);

    bytes memory args = abi.encode(
      asset,
      vm.envAddress("FEES_CONTROLLER_ADDRESS"),
      MultiRolesAuthority(vm.envAddress("AUTHORITY_ADDRESS")),
      farmContractAddress,
      pid,
      earnConfigs[0].rewardToken,
      earnConfigs[0].swapRoute,
      earnConfigs[0].zapLiquidityConfig
    );
    strat = deploy(creationCode, args);

    for (uint256 i = 1; i < earnConfigs.length; i++) {
      StratX4Compounding(strat).addEarnConfig(
        earnConfigs[i].rewardToken,
        abi.encode(earnConfigs[i].swapRoute, earnConfigs[i].zapLiquidityConfig)
      );
    }
  }
}
