#!/usr/bin/env nix-shell
#!nix-shell -i bash

POSITIONAL_ARGS=()
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --verify-evmos)
      EXTRA_ARGS+=("--verify")
      EXTRA_ARGS+=("--verifier-url")
      EXTRA_ARGS+=("https://evm.evmos.org/api")
      EXTRA_ARGS+=("--verifier")
      EXTRA_ARGS+=("blockscout")
      shift # past argument
      ;;
    -c|--chain)
      export CHAIN="$2"
      shift # past argument
      shift # past value
      ;;
    -*|--*)
      EXTRA_ARGS+=("$1") # save positional arg
      EXTRA_ARGS+=("$2") # save positional arg
      # echo "Unknown option $1"
      ## exit 1
      shift;
      shift;
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

if [ -z ${CHAIN+x} ]; then
  echo "No chain specified"
  exit 1
fi


export STRAT_CONFIG_FILE="/vaults-config/$CHAIN/${POSITIONAL_ARGS[0]}.json"
export RPC_URL_ENV="${CHAIN^^}_RPC_URL"
export RPC_URL=${!RPC_URL_ENV}

forge script script/deploy-strat.sol --fork-url $RPC_URL --private-key $PRIVATE_KEY "${EXTRA_ARGS[@]}"

