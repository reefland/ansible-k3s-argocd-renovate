#!/bin/bash
# NAME       : etcd-defrag.sh
# 
# DESCRIPTION: This script will run the etcd defragment process.  This is used
#           to resolve AlertManager Warnings about etcd being less than 50%
#           of actual allocated storage.
#
# ASSUMPTION: The etcdctl CLI utility has been installed.
#
#           This script requires root permissions to access the etcd server
#           and client certificates.
#          
# AUTHOR     : Richard J. Durso
# DATE       : 01/26/2025
# VERSION    : 0.02
#############################################################################

if [ "$(id -u)" -ne 0 ]; then
  echo
  echo "* ERROR: ROOT privilege required to access etcd certificates."
  echo
  exit 1
fi

__check_file_exists()
{
  if [ ! -f "$1" ]; then
    echo "ERROR: $1 not found"
    exit 2
  fi
}

# Define variables
ETCDCTL_CMD="etcdctl"
SERVER_TLS_CERT="/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt"     # --cacert
CLIENT_TLS_CERT="/var/lib/rancher/k3s/server/tls/etcd/server-client.crt" # --cert
CLIENT_TLS_KEY="/var/lib/rancher/k3s/server/tls/etcd/server-client.key"  # --key

# Confirm certificates can be located
__check_file_exists "${SERVER_TLS_CERT}"
__check_file_exists "${CLIENT_TLS_CERT}"
__check_file_exists "${CLIENT_TLS_KEY}"

# Confirm etcdctl can be located
if [ -x "$(which ${ETCDCTL_CMD})" ]; then
  "${ETCDCTL_CMD}" --cacert "${SERVER_TLS_CERT}" --cert "${CLIENT_TLS_CERT}" --key "${CLIENT_TLS_KEY}" defrag
else
  echo "${ETCDCTL_CMD} cli utility not found in path. Is it installed?"
fi
