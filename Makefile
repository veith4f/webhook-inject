REGISTRY            ?= node-647ee1368442ecd1a315c673.ps-xaas.io/pluscontainer
VERSION             ?= $(shell cat VERSION)
PLATFORM            := linux/amd64
WEBHOOK_NAMESPACE	?= "kube-system"
IMG					?= "webhook-inject"

.DEFAULT_GOAL       := build

.PHONY: build
build:
	@docker build --platform ${PLATFORM} -t ${REGISTRY}/${IMG}:${VERSION} -t ${REGISTRY}/${IMG}:latest .

.PHONY: push
push:
	@if ! docker images ${REGISTRY}/${IMG} | awk '{ print $$2 }' | grep -q -F ${VERSION}; then echo "$(IMAGE_REPOSITORY) version ${REGISTRY}/${IMG} is not yet built. Please run 'make build'"; false; fi
	@docker push ${REGISTRY}/${IMG}:${VERSION}
	@docker push ${REGISTRY}/${IMG}:latest

.PHONY: cert
cert:    
	@if [ ! -f cert/ca.key ] || [ ! -f cert/ca.crt ]; then echo "Please place ca.key and ca.crt containing your cluster ca in cert directory."; fi
	@if [ ! -f cert/tls.key ]; then openssl genrsa -out cert/tls.key 4096; fi
	@if [ ! -f cert/tls.csr ]; then openssl req -new -key cert/tls.key -out cert/tls.csr -config cert/openssl.conf -extensions v3_req; fi
	@if [ ! -f cert/tls.crt ]; then openssl x509 -req -in cert/tls.csr -CA cert/ca.crt -CAkey cert/ca.key -CAcreateserial -out cert/tls.crt -days 3650 -extensions v3_req -extfile cert/openssl.conf; fi

.PHONY: apply
apply:
	@if [ ! -f cert/ca.crt ] || [ ! -f cert/tls.key ] || [ ! -f cert/tls.crt ]; then echo "Please run 'make cert' first." && exit 1; fi;
	@TLS_CERT=$$(cat cert/tls.crt | base64 -w 0); \
	TLS_KEY=$$(cat cert/tls.key | base64 -w 0); \
	CA_BUNDLE=$$(cat cert/ca.crt | base64 -w 0); \
	for file in ./manifests/*; do \
		cat "$$file" | sed "s|<TLS_CERT>|$${TLS_CERT}|g" | \
		sed "s|<TLS_KEY>|$${TLS_KEY}|g" | sed "s|<CA_BUNDLE>|$${CA_BUNDLE}|g" | \
		sed "s|<WEBHOOK_NAMESPACE>|kube-system|g" | sed "s|<IMAGE>|${REGISTRY}/${IMG}:${VERSION}|g" | \
		kubectl apply -f -; \
	done

.PHONY: unapply
unapply:
	@for file in ./manifests/*; do \
		cat "$$file" | sed "s|<TLS_CERT>|$${TLS_CERT}|g" | \
		sed "s|<TLS_KEY>|$${TLS_KEY}|g" | sed "s|<CA_BUNDLE>|$${CA_BUNDLE}|g" | \
		sed "s|<WEBHOOK_NAMESPACE>|kube-system|g" | sed "s|<IMAGE>|${REGISTRY}/${IMG}:${VERSION}|g" | \
		kubectl delete -f -; \
	done

.PHONY: test
test:
	@kubectl apply -f test/ns.yml
	@kubectl apply -f test/pod.yml
	@sleep 5
	@RESULT=$$(kubectl exec -it sleep -n custom -- /bin/sh -c 'echo $$AWS_ACCESS_KEY_ID' | tr -d '[:space:]'); \
	if [ "$${RESULT}" == "foo" ]; then echo "| ----  test ok ---->>"; \
	else echo "| ----  test not ok ---->> "; fi
	@kubectl delete -f test/pod.yml --force --grace-period=0
	@kubectl delete -f test/ns.yml --force --grace-period=0

.PHONY: clean
clean:
	@rm -f cert/tls.*
