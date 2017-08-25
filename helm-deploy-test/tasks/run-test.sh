#!/bin/bash
set -o errexit -o nounset

# Set kube config from pool
cp pool.kube-hosts/metadata /root/.kube/config

set -o allexport
CF_NAMESPACE=scf
set +o allexport

unzip s3.scf-config/scf-linux-*.zip -d s3.scf-config/

kube_overrides() {
    ruby <<EOF
        require 'yaml'
        require 'json'
        obj = YAML.load_file('$1')
        obj['spec']['containers'].each do |container|
            container['env'].each do |env|
                env['value'] = '$DOMAIN' if env['name'] == 'DOMAIN'
            end
        end
        puts obj.to_json
EOF
}

image=$(awk '$1 == "image:" { print $2 }' "s3.scf-config/kube/cf/bosh-task/${TEST_NAME}.yaml")
kubectl run \
    --namespace="${CF_NAMESPACE}" \
    --attach \
    --restart=Never \
    --image="${image}" \
    --overrides="$(kube_overrides "s3.scf-config/kube/cf/bosh-task/${TEST_NAME}.yaml")" \
    "${TEST_NAME}"
