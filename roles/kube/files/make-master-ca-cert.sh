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
# NODE_IPS - IPs of all cluster servers
# NODE_DNS - DNS names of all cluster servers
# ARCH - what arch of cfssl should be downloaded

# Also the following will be respected
# CERT_DIR - where to place the finished certs (we create tmp cert config directory user CERT_DIR)
# CERT_GROUP - who the group owner of the cert files should be
# USE_LOCAL_BIN - '1' when using local cfssl, cfssljson binary at config directory

node_ips="${NODE_IPS:="${1}"}"
node_dns="${NODE_DNS:=""}"
arch="${ARCH:-"linux-amd64"}"
cert_dir="${CERT_DIR:-"/srv/kubernetes"}"
cert_group="${CERT_GROUP:="root"}"
use_local="${USE_LOCAL_BIN:="${1}"}"

# The following certificate pairs are created:
#
#  - ca (the cluster's certificate authority)
#  - (not yet use for master ca gen) server (for etcd access)
#  - (not yet use for  master ca gen) client (for kube-apiserver, etcdctl)
#  - (not yes use for master ca gen) peer (for etcd peer to peer communication)

tmpdir=$(mktemp -d --tmpdir master_cacert.XXXXXX)
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

mkdir -p "$cert_dir"

mkdir -p bin

if [${use_local} == '1']; then
   cp -p "${cert_dir}/cfssl" ./
   cp -p "${cert_dir}/cfssljson" ./
else
   curl -sSL -o ./bin/cfssl "https://pkg.cfssl.org/R1.2/cfssl_$arch"
   curl -sSL -o ./bin/cfssljson "https://pkg.cfssl.org/R1.2/cfssljson_$arch"
fi

chmod +x ./bin/cfssl{,json}
export PATH="$PATH:${tmpdir}/bin/"

####    create ca-config.json file for ca gen
cat <<EOF > ca-config.json
{
    "signing": {
        "default": {
            "expiry": "87600h"
        },
        "profiles": {
            "utc": {
                "expiry": "87600h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            },
            "kube": {
                "expiry": "87600h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            },
            "server": {
                "expiry": "87600h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            },
            "client": {
                "expiry": "87600h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            },
            "peer": {
                "expiry": "87600h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            }
        }
    }
}
EOF


####    create ca-csr.json for master ca gen
cat <<EOF > ca-csr.json
{
    "CN": "kubernetes",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Shenzhen",
            "ST": "Shenzhen",
            "OU": "kube cluster",
            "L": "internet",
            "O": "kube"
        }
    ]
}
EOF

# debug
#mkdir -p "${cert_dir}"
#ls -al ./* > "${cert_dir}/files.txt"
#cat ./ca-config.json > "${cert_dir}/ca-config.json"
#cat ./ca-csr.json > "${cert_dir}/ca-csr.json"
#cp ./bin/cf* "${cert_dir}/"
#cfssl gencert -initca ca-csr.json | cfssljson -bare ca > "${cert_dir}/cfssl.log"

# generate the master CA/CERT(ca.pem, ca-key.pem) using ca-config.json, ca-csr.json 
if ! (cfssl gencert -initca ca-csr.json | cfssljson -bare ca -) >/dev/null 2>&1; then
    echo "=== Failed to generate CA certificates: Aborting ===" 1>&2
    exit 2
fi


#####    copy generated files to tmp master ca config directory
# mkdir -p "$cert_dir"

#ls -al ./* > "${cert_dir}/files.tx"

tempdir_cert_backup="${cert_dir}"
mkdir -p "${tempdir_cert_backup}"

ls -al ./* > "${tempdir_cert_backup}/files.txt"

cp -p ./ca-config.json "${tempdir_cert_backup}/ca-config.json"
cp -p ./ca.csr "${tempdir_cert_backup}/ca.csr"
cp -p ./ca-csr.json "${tempdir_cert_backup}/ca-csr.json"
cp -p ./ca-key.pem "${tempdir_cert_backup}/ca-key.pem"
cp -p ./ca.pem "${tempdir_cert_backup}/ca.pem"

cp -p ./bin/cfssl "${tempdir_cert_backup}/cfssl"
cp -p ./bin/cfssljson "${tempdir_cert_backup}/cfssljson"

