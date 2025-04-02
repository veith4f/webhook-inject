from flask import Flask, request, jsonify
from kubernetes import client, config
import json
import base64
import ssl
import logging as log

app = Flask(__name__)


def get_env_vars_for_namespace(ns):
	env_vars = []

	with open(f"/secrets/{ns}", "r") as f:
		for line in f:
			line = line.strip()
			if not line or line.startswith("#"):  # Ignore empty lines and comments
				continue
			key, value = line.split("=", 1)  # Split at first '='
			value = value.strip('"')  # Remove surrounding quotes if present
			env_vars.append({
				"name": key,
				"value": value
			})
	return env_vars

@app.route("/pod/inject", methods=["POST"])
def admission_review_handler():
	req_data = request.get_json()
	if not req_data:
		return jsonify({"error": "Invalid request"}), 400
	
	req = req_data.get("request", {})
	rsp = {
		"uid": req.get("uid"),        
		"allowed": True
	}

	ns = req.get("namespace")
	name = req.get("name")
	pod = req.get('object')

	env_vars = get_env_vars_for_namespace(ns)

	for container in pod['spec']['containers']:
		if 'env' not in container:
			container['env'] = []
		container['env'].extend(env_vars)

	
	# patch with jsonpatch https://datatracker.ietf.org/doc/html/rfc6902
	rsp.update({
		"patchType": "JSONPatch",
		"patch": base64.b64encode(
			json.dumps([ {"op": "replace", "path": "/spec/containers", "value": pod['spec']['containers']} ]).encode()
		).decode()
	})
	
	return jsonify({"response": rsp, "kind": "AdmissionReview", "apiVersion": "admission.k8s.io/v1"})

if __name__ == "__main__":
	context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
	context.load_cert_chain("/tls/tls.crt", "/tls/tls.key")
	
	log.info("Starting Webhook on port 443...")
	app.run(host="0.0.0.0", port=443, ssl_context=context)
