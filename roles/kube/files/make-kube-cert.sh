#!/bin/bash

# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

# Export proxy to ensure commands like curl could work
[[ -n "${HTTP_PROXY:-}" ]]  && export HTTP_PROXY=${HTTP_PROXY}
[[ -n "${HTTPS_PROXY:-}" ]] && export HTTPS_PROXY=${HTTPS_PROXY}

# Caller should set in the ev:
# NODE_IPS - IPs of all etcd servers
# LOAD_BALANCER_IP - IP of load balancer
# APISERVER_SERVICE_CLUSTER_IP - IP of apiserver service clust ip (10.96.0.1 - first address of 10.96.0.0/12 )
# NODE_DNS - DNS names of all etcd servers
# ARCH - what arch of cfssl should be downloaded

# Also the following will be respected
# CERT_DIR - where to place the finished certs
# CERT_GROUP - who the group owner of the cert files should be
# MASTER_CA_DIR - tmp master ca file directory. copy master ca files from this directory
# LOAD_BALANCER_IP - load balancer ip address in front of apiserver
# APISERVER_SERVICE_CLUSTER_IP - ip/network of service cluster for apiserver

node_ips="${NODE_IPS:="${1}"}"
load_balancer_ip="${LOAD_BALANCER_IP:="${1}"}"
apiserver_service_cluster_ip="${APISERVER_SERVICE_CLUSTER_IP:="${1}"}"
cluster_kube_dns_ip="${CLUSTER_DNS_IP:="${1}"}"
node_dns="${NODE_DNS:=""}"
arch="${ARCH:-"linux-amd64"}"
cert_dir="${CERT_DIR:-"/srv/kubernetes"}"
cert_group="${CERT_GROUP:="root"}"
master_ca_dir="${MASTER_CA_DIR:-"/etc/tmp_master_ca_config"}"

# The following certificate pairs are created:
#
#  - ca (the cluster's certificate authority - copy from master ca)
#  - apiserver (for kube apiserver)
#  - admin (for kube administrator)
#  - controller-manager (for kube controller manager service)
#  - scheduler (for kube scheduler service)

tmpdir=$(mktemp -d --tmpdir kube_cacert.XXXXXX)
trap 'rm -rf "${tmpdir}"' EXIT
cd "${tmpdir}"

declare -a san_array=()

IFS=',' read -ra node_ips <<< "$node_ips"
for ip in "${node_ips[@]}"; do
    san_array+=(${ip})
done
IFS=',' read -ra node_dns <<< "$node_dns"
for dns in "${node_dns[@]}"; do
    san_array+=(${dns})
done

mkdir -p bin

mkdir -p "$cert_dir"

# download cfssl, cfssljson utility
#curl -sSL -o ./bin/cfssl "https://pkg.cfssl.org/R1.2/cfssl_$arch"
#curl -sSL -o ./bin/cfssljson "https://pkg.cfssl.org/R1.2/cfssljson_$arch"

# copy cfssl, cfssljson utility from master ca config directory
cp -p "${master_ca_dir}/cfssl" ./bin/cfssl
cp -p "${master_ca_dir}/cfssljson" ./bin/cfssljson

chmod +x ./bin/cfssl{,json}
export PATH="$PATH:${tmpdir}/bin/"

# copy master ca files from tmp master ca config directory
cp -p "${master_ca_dir}/ca.pem" ./ca.pem
cp -p "${master_ca_dir}/ca-key.pem" ./ca-key.pem
cp -p "${master_ca_dir}/ca-config.json" ./ca-config.json
cp -p "${master_ca_dir}/ca-csr.json" ./ca-csr.json
cp -p "${master_ca_dir}/ca.csr" ./ca.csr

####    generate certs

cn_name="${san_array[0]}"
san_array=("${san_array[@]}")
set -- ${san_array[*]}
for arg do shift
    set -- "$@" \",\" "$arg"
done; shift
hosts_string="\"$(printf %s "$@")\""

####    generate apiserver json
cat <<EOF > apiserver.json
{
    "CN": "kubernetes",
    "hosts": [
        "127.0.0.1",
        "::1",
        "::",

        "$load_balancer_ip",

        "$cluster_kube_dns_ip", 

        "$apiserver_service_cluster_ip",
        
        $hosts_string,

        "lb-node",
        "api",

        "kubernetes",
        "kubernetes.local",
        "kubernetes.default",
        "kubernetes.default.svc",
        "kubernetes.default.svc.cluster",
        "kubernetes.default.svc.cluster.local"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Shenzhen",
            "ST": "Shenzhen",
            "O": "kube",
            "OU": "internet"
        }
    ]
}
EOF

# debug use
## mkdir -p "$cert_dir"
#ls -al ./* > "${cert_dir}/files.txt"
#cp -p ./* "${cert_dir}"
#cp -p ./bin/* "${cert_dir}"


if ! (cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kube apiserver.json | cfssljson -bare apiserver) >/dev/null 2>&1; then
    echo "=== Failed to generate server certificates: Aborting ===" 1>&2
    exit 2
fi

####    generate admin json
cat <<EOF > admin.json
{
    "CN": "kubernetes-admin",
    "hosts": [
        $hosts_string
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Shenzhen",
            "ST": "Shenzhen",
            "O": "system:masters",
            "OU": "internet"
        }
    ]
}
EOF

if ! (cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kube admin.json | cfssljson -bare admin) >/dev/null 2>&1; then
    echo "=== Failed to generate server certificates: Aborting ===" 1>&2
    exit 2
fi

####    generate controller manager json
cat <<EOF > controller-manager.json
{
    "CN": "system:kube-controller-manager",
    "hosts": [
        $hosts_string
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Shenzhen",
            "ST": "Shenzhen",
            "O": "system:kube-controller-manager",
            "OU": "internet"
        }
    ]
}
EOF

if ! (cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kube controller-manager.json | cfssljson -bare controller-manager) >/dev/null 2>&1; then
    echo "=== Failed to generate server certificates: Aborting ===" 1>&2
    exit 2
fi

####    generate scheduler json
cat <<EOF > scheduler.json
{
    "CN": "system:kube-scheduler",
    "hosts": [
        $hosts_string
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Shenzhen",
            "ST": "Shenzhen",
            "O": "system:kube-scheduler",
            "OU": "internet"
        }
    ]
}
EOF

if ! (cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kube scheduler.json | cfssljson -bare scheduler) >/dev/null 2>&1; then
    echo "=== Failed to generate server certificates: Aborting ===" 1>&2
    exit 2
fi

mkdir -p "$cert_dir"

tempdir_cert_backup="${cert_dir}"
mkdir -p "$tempdir_cert_backup"

ls -al ./* > "${cert_dir}/files.txt"

cp -p ./ca-config.json "${tempdir_cert_backup}/ca-config.json"
cp -p ./ca-csr.json "${tempdir_cert_backup}/ca-csr.json"
cp -p ./ca.csr "${tempdir_cert_backup}/ca.csr"
cp -p ./ca-key.pem "${tempdir_cert_backup}/ca-key.pem"
cp -p ./ca.pem "${tempdir_cert_backup}/ca.pem"

cp -p ./ca-config.json "${tempdir_cert_backup}/kube-ca-config.json"
cp -p ./ca-csr.json "${tempdir_cert_backup}/kube-ca-csr.json"
cp -p ./ca.csr "${tempdir_cert_backup}/kube-ca.csr"
cp -p ./ca-key.pem "${tempdir_cert_backup}/kube-ca-key.pem"
cp -p ./ca.pem "${tempdir_cert_backup}/kube-ca.pem"

cp -p ./apiserver.csr "${tempdir_cert_backup}/apiserver.csr"
cp -p ./apiserver.json "${tempdir_cert_backup}/apiserver.json"
cp -p ./apiserver-key.pem "${tempdir_cert_backup}/apiserver-key.pem"
cp -p ./apiserver.pem "${tempdir_cert_backup}/apiserver.pem"

cp -p ./admin.csr "${tempdir_cert_backup}/admin.csr"
cp -p ./admin.json "${tempdir_cert_backup}/admin.json"
cp -p ./admin-key.pem "${tempdir_cert_backup}/admin-key.pem"
cp -p ./admin.pem "${tempdir_cert_backup}/admin.pem"

cp -p ./controller-manager.csr "${tempdir_cert_backup}/controller-manager.csr"
cp -p ./controller-manager.json "${tempdir_cert_backup}/controller-manager.json"
cp -p ./controller-manager-key.pem "${tempdir_cert_backup}/controller-manager-key.pem"
cp -p ./controller-manager.pem "${tempdir_cert_backup}/controller-manager.pem"

cp -p ./scheduler.csr "${tempdir_cert_backup}/scheduler.csr"
cp -p ./scheduler.json "${tempdir_cert_backup}/scheduler.json"
cp -p ./scheduler-key.pem "${tempdir_cert_backup}/scheduler-key.pem"
cp -p ./scheduler.pem "${tempdir_cert_backup}/scheduler.pem"

cp -p ./bin/cfssl "${tempdir_cert_backup}/cfssl"
cp -p ./bin/cfssljson "${tempdir_cert_backup}/cfssljson"


#cp -p ca.pem "${cert_dir}/ca.crt"
#cp -p server.pem "${cert_dir}/server.crt"
#cp -p server-key.pem "${cert_dir}/server.key"
#cp -p client.pem "${cert_dir}/client.crt"
#cp -p client-key.pem "${cert_dir}/client.key"
#cp -p peer.pem "${cert_dir}/peer.crt"
#cp -p peer-key.pem "${cert_dir}/peer.key"

#CERTS=("ca.crt" "server.crt" "server.key" "client.crt" "client.key" "peer.crt" "peer.key")
#for cert in "${CERTS[@]}"; do
#  chgrp "${cert_group}" "${cert_dir}/${cert}"
#  chmod 660 "${cert_dir}/${cert}"
#done
