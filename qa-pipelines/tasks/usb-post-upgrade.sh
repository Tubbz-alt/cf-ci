#!/bin/bash
set -o errexit -o nounset

# Set kube config from pool
mkdir -p /root/.kube/
cp  pool.kube-hosts/metadata /root/.kube/config

DOMAIN=$(kubectl get pods -o json --namespace scf api-0 | jq -r '.spec.containers[0].env[] | select(.name == "DOMAIN").value')
cf api --skip-ssl-validation "https://api.${DOMAIN}"
cf login -u admin -p changeme -o system

# Temporary workaround for usb breakage after secret rotation
echo "Update broker password after rotation:"
CF_NAMESPACE=scf
SECRET=$(kubectl get --namespace $CF_NAMESPACE statefulset,deploy -o json | jq -r '[.items[].spec.template.spec.containers[].env[] | select(.name == "INTERNAL_CA_CERT").valueFrom.secretKeyRef.name] | unique[]')
USB_PASSWORD=$(kubectl get -n scf secret $SECRET -o jsonpath='{@.data.cf-usb-password}' | base64 -d)
USB_ENDPOINT=$(cf curl /v2/service_brokers | jq -r '.resources[] | select(.entity.name=="usb").entity.broker_url')
cf update-service-broker usb broker-admin "$USB_PASSWORD" "$USB_ENDPOINT"

echo "Verify that app bound to postgres service instance is reachable:"
curl -Ikf https://scf-rails-example-postgres.$DOMAIN
echo "Verify that data created before upgrade can be retrieved:"
curl -kf https://scf-rails-example-postgres.$DOMAIN/todos/1 | jq .

echo "Verify that app bound to mysql service instance is reachable:"
curl -Ikf https://scf-rails-example-mysql.$DOMAIN
echo "Verify that data created before upgrade can be retrieved:"
curl -kf https://scf-rails-example-mysql.$DOMAIN/todos/1 | jq .

cd rails-example
cf target -o usb-test-org -s usb-test-space
cf stop scf-rails-example-postgres
cf stop scf-rails-example-mysql
sleep 15
cf delete -f scf-rails-example-postgres
cf delete -f scf-rails-example-mysql
cf delete-service -f testpostgres
cf delete-service -f testmysql
cf delete-org -f usb-test-org

cf unbind-staging-security-group sidecar-net-workaround
cf unbind-running-security-group sidecar-net-workaround
cf delete-security-group -f sidecar-net-workaround

cf install-plugin -f "https://github.com/SUSE/cf-usb-plugin/releases/download/1.0.0/cf-usb-plugin-1.0.0.0.g47b49cd-linux-amd64"
yes | cf usb-delete-driver-endpoint postgres
yes | cf usb-delete-driver-endpoint mysql

for namespace in mysql-sidecar pg-sidecar postgres mysql; do
    while [[ $(kubectl get statefulsets --output json --namespace "${namespace}" | jq '.items | length == 0') != "true" ]]; do
      kubectl delete statefulsets --all --namespace "${namespace}" ||:
    done
    while [[ $(kubectl get deploy --output json --namespace "${namespace}" | jq '.items | length == 0') != "true" ]]; do
      kubectl delete deploy --all --namespace "${namespace}" ||:
    done
    while kubectl get namespace "${namespace}" 2>/dev/null; do
      kubectl delete namespace "${namespace}" ||:
      sleep 30
    done
    while [[ -n $(helm list --short --all ${namespace}) ]]; do
        helm delete --purge ${namespace} ||:
        sleep 10
    done
done