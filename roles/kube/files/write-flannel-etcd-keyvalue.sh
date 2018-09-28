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
#[[ -n "${HTTP_PROXY:-}" ]]  && export HTTP_PROXY=${HTTP_PROXY}
#[[ -n "${HTTPS_PROXY:-}" ]] && export HTTPS_PROXY=${HTTPS_PROXY}

# Caller should set in the env:
# ETCD_CMD - command of to exec. e.g., /usr/local/bin/etcdctl
# ETCD_OPT - options for command
# ETCD_OP  - operation to process source and target
# ETCD_TARGET - targe will take operation
# ETCD_SOURCE - source input for operation

etcd_cmd="${ETCD_CMD:="${1}"}"
etcd_opt="${ETCD_OPT:="${1}"}"
etcd_op="${ETCD_OP:="${1}"}"
etcd_target="${ETCD_TARGET:="${1}"}"
etcd_source="${ETCD_SOURCE:="${1}"}"

$etcd_cmd $etcd_opt $etcd_op $etcd_target < $etcd_source
