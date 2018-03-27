#!/bin/bash
set -o errexit -o nounset

# Set kube config from pool
mkdir -p /root/.kube/
cp  pool.kube-hosts/metadata /root/.kube/config

set -o allexport
DOMAIN=$(kubectl get pods -o json --namespace scf api-0 | jq -r '.spec.containers[0].env[] | select(.name == "DOMAIN").value')
CF_NAMESPACE=scf
CAP_DIRECTORY=s3.scf-config
set +o allexport

# For upgrade tests
if [ -n "${CAP_INSTALL_VERSION:-}" ]; then
    curl ${CAP_INSTALL_VERSION} -Lo cap-install-version.zip
    export CAP_DIRECTORY=cap-install-version
    unzip ${CAP_DIRECTORY}.zip -d ${CAP_DIRECTORY}/
else
    unzip ${CAP_DIRECTORY}/scf-*.zip -d ${CAP_DIRECTORY}/
fi

# Replace the generated monit password with the name of the generated secrets secret
generated_secrets_secret="$(kubectl get pod api-0 --namespace "${CF_NAMESPACE}" -o jsonpath='{@.spec.containers[0].env[?(@.name=="MONIT_PASSWORD")].valueFrom.secretKeyRef.name}')"

kube_overrides() {
    ruby <<EOF
        require 'yaml'
        require 'json'
        obj = YAML.load_file('$1')
        obj['spec']['containers'].each do |container|
            container['env'].each do |env|
                env['value'] = '$DOMAIN'     if env['name'] == 'DOMAIN'
                env['value'] = 'tcp.$DOMAIN' if env['name'] == 'TCP_DOMAIN'
                if env['name'] == "MONIT_PASSWORD"
                    env['valueFrom']['secretKeyRef']['name'] = '$generated_secrets_secret' 
                end
            end
        end
        puts obj.to_json
EOF
}

container_status() {
  kubectl get --output=json --namespace=scf pod $1 \
    | jq '.status.containerStatuses[0].state.terminated.exitCode | tonumber' 2>/dev/null
}

image=$(awk '$1 == "image:" { gsub(/"/, "", $2); print $2 }' "${CAP_DIRECTORY}/kube/cf${CAP_CHART}/bosh-task/${TEST_NAME}.yaml")

kubectl run \
    --namespace="${CF_NAMESPACE}" \
    --attach \
    --restart=Never \
    --image="${image}" \
    --overrides="$(kube_overrides "${kube_yaml}")" \
    "${TEST_NAME}" ||:

while [[ -z $(container_status ${TEST_NAME}) ]]; do
  kubectl attach --namespace=scf ${TEST_NAME} ||:
done

exit $(container_status ${TEST_NAME})
