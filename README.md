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

