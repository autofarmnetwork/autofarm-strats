Autofarm v3 Strats
==================

## Deployment process

1. Use `node config-builders/{...}.js` to generate vault configs in /vaults-config,

2. Test the strats with `STRAT_CONFIG_FILE={...}.json forge test test/prod/{...}.t.sol`,

3. Run the deployment script (without actually deploying) with `forge script scripts/{...}.sol`,

4. Submit a PR to have the tests run on CI,

5. CI will deploy the vaults under the same address as the simulated deployment in (3)

