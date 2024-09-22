# Cluster Bootstrapping

## Prerequisites
### 1Password Connect Setup
Follow the 1Password docs on setting up a [Secrets Automation Workflow](https://developer.1password.com/docs/connect/get-started/#manual-step-2-deploy-1password-connect-server).

You will get a `1password-credentials.json` file required to create a connect server and a connect token, which is used by the 1password operator to connect to the connect server.

Both token and credentials must be stored in secrets so that the onepassword components can read them. Store the token
and credentials in the files `token.env` and `1password-credentials.json`, respectively. Of note, the connect credentials
are doubly base64 encoded. This is not a bug on our end but a quirk (or rather bug) of the onepassword helm chart.

## Bootstrap the cluster
Execute to the script `run-all.sh` to execute all cluster bootstrap steps in the correct order.
