# webhook-inject
This is a proof-of-concept using [DynamicAdmissionControl](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/), specifically MutatingWebHooks to inject authentication secrets into pods.

## MutatingWebhook explained
A MutatingWebhook is a kubernetes construct consisting of
- mutatingwebhookconfiguration
- deployment (webservice)
- service
- certificates

The idea of MutatingWebHooks is to listen to events (such as create, update) that kubernetes apiserver performs on objects (such as pods, configmaps) and perform an action before the object is persisted in the kuberentes object store (etcd). To this end, the deployment/service specified by a mutatingwebhookconfiguration runs a webserver that receives a http/post with the object in question and performs intended changes. 

For security purposes, a MutatingWebHook must provide a certificate that is signed by the cluster's certificate authority. This is necessary, because modifying resources can be dangerous - especially when those resources don't belong to the person modifying them. By requiring a signature created with the cluster ca's private key which is usually owned by the cluster admin, abuse risks of DynamicAdmissionControl are mitigated. 

In order to obtain your cluster ca certificate and private key, ask your friendly cluster admin or provider (such as plusserver).

## Particular construction in this repository explained
The idea is to create a `Secret` (i.e. manifests/webhook.yml|aws-secrets) that contains an env file per each namespace where pods start that should have specific environment variables (such as AWS_ACCESS_KEY_ID).
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: aws-secrets
  namespace: <WEBHOOK_NAMESPACE>
data:
  custom: QVdTX0FDQ0VTU19LRVlfSUQ9ImZvbyIKQVdTX1NFQ1JFVF9BQ0NFU1NfS0VZPSJiYXIiCg==
  mynamespace: QVdTX0FDQ0VTU19LRVlfSUQ9ImZvbyIKQVdTX1NFQ1JFVF9BQ0NFU1NfS0VZPSJiYXIiCg==
```

Each data field of `aws-secrets` is a base64-encoded env file:
```bash
echo QVdTX0FDQ0VTU19LRVlfSUQ9ImZvbyIKQVdTX1NFQ1JFVF9BQ0NFU1NfS0VZPSJiYXIiCg | base64 -d
AWS_ACCESS_KEY_ID="foo"
AWS_SECRET_ACCESS_KEY="bar"
```

The webserver injecting env vars into pods is called as specified in mutatingwebhookconfiguration:
```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: webhook-inject
webhooks:
  - name: webhook-inject.kube-system.svc.cluster.local
    admissionReviewVersions: ["v1"]
    sideEffects: None
    clientConfig:
      service:
        name: webhook-inject
        namespace: <WEBHOOK_NAMESPACE>
        path: "/pod/inject"
      caBundle: <CA_BUNDLE>
    rules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        resources: ["pods"]
        operations: ["CREATE", "UPDATE"]
        scope: "Namespaced"
    namespaceSelector:
      matchLabels:
        netfira.com/namespace.type: "customer"
```
The specific idea is to call the webserver for create and update operations on pods in namespaces which are labelled `netfira.com/namespace.type: "customer"`.

Webserver logic is implemented in `webhook.py` and is roughly:
- `on pod create/update -> get env for namespace -> inject vars into pod`


## Usage
- place `ca.crt` and `ca.key` in `cert` directory
- `make cert`
- set `REGISTRY` in `Makefile` to a docker registry you have access to
- `make build`
- `make push`
- `make apply`
- `make test`


## Further Discussion
Using authentication details injected via the construction in this repository, pods running in customer namespaces, i.e. namespaces labelled `netfira.com/namespace.type: "customer"` can use tools like [aws cli](https://docs.aws.amazon.com/cli/v1/userguide/cli-configure-envvars.html) or [boto3](https://boto3.amazonaws.com/v1/documentation/api/latest/guide/quickstart.html#configuration) in order to access services on external accounts such as AWS.

If pods don't strictly need access to an external service or should not receive authentication details such as `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` the example given in this repository could also be modified such that the webservice that injects environment variables into pods uses boto3 along with authentication details from the mounted secret in order to perform operations on an external account.

For example, the webservice could retrieve a set of parameters from [AWS Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html) and instead of `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` inject the retrieved parameters. In this setup, the same set of credentials could be used for all namespaces and a namespace's name where pods run could decide which parameters are retrieved and injected into pods.
