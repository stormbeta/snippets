# AWS IAM Auth

For clusters setup with aws iam auth, your kubeconfig will typically look something like this:

```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: CERTIFICATE_DATA
    server: https://kuberentes.example
  name: my-cluster
contexts:
- context:
    cluster: my-cluster
    namespace: default
    user: my-k8s-user
  name: my-cluster
current-context: my-cluster
kind: Config
preferences: {}
users:
- name: my-k8s-user
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      args:
      - token
      - -i
      - my-cluster
      command: aws-iam-authenticator
      env: null
```

If your AWS access requires MFA however, you'll get errors from kubectl when the token expires.

Instead of having to manually go refresh the token, you can wrap the aws-iam-authenticator to prompt for refresh automatically by replacing the aws-iam-authenticator call with a wrapper script like this:

```bash
#!/usr/bin/env bash
# Automatically prompt for MFA token if expired
set -eo pipefail
# MINUTES = expiration period in minutes
if [[ -n "$(find "${HOME}/.aws/credentials" -mmin +MINUTES)" ]]; then
  YOUR_MFA_SCRIPT 1>&2
fi && exec aws-iam-authenticator "$@"
```
