# Cluster Bootstrapping

## Prerequisites
### 1Password Connect Setup
Follow the 1Password docs on setting up a [Secrets Automation Workflow](https://developer.1password.com/docs/connect/get-started/#manual-step-2-deploy-1password-connect-server).

You will get a `1password-credentials.json` file required to create a connect server and a connect token, which is used by the 1password operator to connect to the connect server.

Both token and credentials must be put in secrets, you can find example files in `kubernetes/infrastructure/workloads/onepassword`.
Of note, the credentials must be supplied in base64 encoding, e.g. via `cat 1password-credentials.json | base64`.

## Bootstrap the cluster
Execute to the script `run-all.sh` to execute all cluster bootstrap steps in the correct order.
