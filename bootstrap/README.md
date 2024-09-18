# Cluster Bootstrapping

## Prerequisites
### 1Password Connect Setup
Follow the 1Password docs on setting up a [Secrets Automation Workflow](https://developer.1password.com/docs/connect/get-started/#manual-step-2-deploy-1password-connect-server).

You will get a `1password-credentials.json` file required to create a connect server and a connect token, which is used by the 1password operator to connect to the connect server.

Export both in separate env files in `kubernetes/infrastructure/workloads/onepassword`. Check out the example env files there.

## Bootstrap the cluster
Execute to the script `run-all.sh` to execute all cluster bootstrap steps in the correct order.
