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
# NODE_DNS - DNS names of all etcd servers
# ARCH - what arch of cfssl should be downloaded

# Also the following will be respected
# CERT_DIR - where to place the finished certs
# CERT_GROUP - who the group owner of the cert files should be
# TMP_CERT_CONFIG_DIR - tmp config directory (work directory to gen cert)

node_ips="${NODE_IPS:="${1}"}"
node_dns="${NODE_DNS:=""}"
arch="${ARCH:-"linux-amd64"}"

cert_dir="${CERT_DIR:-"/etc/kubernetes/pki"}"
cert_group="${CERT_GROUP:-"root"}"
tmp_cert_config_dir="${TMP_CERT_CONFIG_DIR:-"/etc/tmp_kubelet_certs_config"}"

# The following certificate pairs are created:
#
#  - ca (the cluster's certificate authority - copy from master ca)
#  - kublet

#tmpdir=$(mktemp -d --tmpdir kubelet_cacert.XXXXXX)
#trap 'rm -rf "${tmpdir}"' EXIT
#cd "${tmpdir}"

# before exec this script, we have:
# 1. create cert dir
# 2. create tmp config dir
# 3. copy master ca files to tmp config dir
# 4. copy cfssl and cfssljson to tmp config dir

# create tmp config dir if not exist
mkdir -p "${tmp_cert_config_dir}"

# enter work directory to generate cert (tmp config directory)
cd "${tmp_cert_config_dir}"

# create cert directory if not exist which will store cert for working cluster
mkdir -p "$cert_dir"

declare -a san_array=()

IFS=',' read -ra node_ips <<< "$node_ips"
for ip in "${node_ips[@]}"; do
    san_array+=(${ip})
done
IFS=',' read -ra node_dns <<< "$node_dns"
for dns in "${node_dns[@]}"; do
    san_array+=(${dns})
done

# make dir to store cfssh utility
# mkdir -p bin

# download cfssl, cfssljson utility
#curl -sSL -o ./bin/cfssl "https://pkg.cfssl.org/R1.2/cfssl_$arch"
#curl -sSL -o ./bin/cfssljson "https://pkg.cfssl.org/R1.2/cfssljson_$arch"

# copy cfssl, cfssljson utility from master ca config directory
#cp -p "${master_ca_dir}/cfssl" ./bin/cfssl
#cp -p "${master_ca_dir}/cfssljson" ./bin/cfssljson

#chmod +x ./bin/cfssl{,json}
#export PATH="$PATH:${tmpdir}/bin/"

# change cfssl, cfssljson file executable
chmod +x ./cfssl{,json}

# copy master ca files from tmp master ca config directory
#cp -p "${master_ca_dir}/ca.pem" ./ca.pem
#cp -p "${master_ca_dir}/ca-key.pem" ./ca-key.pem
#cp -p "${master_ca_dir}/ca-config.json" ./ca-config.json
#cp -p "${master_ca_dir}/ca-csr.json" ./ca-csr.json
#cp -p "${master_ca_dir}/ca.csr" ./ca.csr

####    generate certs

cn_name="${san_array[0]}"
san_array=("${san_array[@]}")
set -- ${san_array[*]}
for arg do shift
    set -- "$@" \",\" "$arg"
done; shift
hosts_string="\"$(printf %s "$@")\""

# get hostname of currentnode
hostname_current=$(hostname)

cn_name_current="system:node:${hostname_current}"
o_name_use="system:nodes"


# debug
#ls -al ./* > d.log
#echo $node_ips >> d.log
#echo $node_dns >> d.log
#echo $cn_name >> d.log
#echo $san_array >> d.log
#echo $cn_name_current >> d.log
#echo $o_name_use >> d.log 
#hostname >> d.log


####    generate apiserver json
cat <<EOF > kubelet.json
{
    "CN": "${cn_name_current}",
    "hosts": [
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
            "O": "${o_name_use}",
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


if ! (./cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kube kubelet.json | ./cfssljson -bare kubelet) >/dev/null 2>&1; then
    echo "=== Failed to generate server certificates: Aborting ===" 1>&2
    exit 2
fi

