#!/bin/bash
# NAME       : install_etcd_cli.sh
# 
# DESCRIPTION: This script will install or upgrade the Kubernetes ETCD CLI
#              to be version matched to the ETCD running on the local host.
#
#           This script requires root permissions to access the ETCD cert-
#           ificates and install the CLI binary file.
#          
# AUTHOR     : Richard J. Durso
# DATE       : 08/30/2022
# VERSION    : 0.21
#############################################################################

if [ $(id -u) -ne 0 ]; then
  echo
  echo "* ERROR: ROOT privilage required to access ETCD certificates and install ETCD CLI."
  echo
  exit 1
fi

ETCD_VER=v$(curl -L --cacert /var/lib/rancher/k3s/server/tls/etcd/server-ca.crt --cert /var/lib/rancher/k3s/server/tls/etcd/server-client.crt --key /var/lib/rancher/k3s/server/tls/etcd/server-client.key -s https://127.0.0.1:2379/version | cut -d \" -f 4)

echo Detected etcd server version: ${ETCD_VER}

GOOGLE_URL=https://storage.googleapis.com/etcd
GITHUB_URL=https://github.com/etcd-io/etcd/releases/download
# Choose either URL
DOWNLOAD_URL=${GOOGLE_URL}

# Determine if X86 or ARM architecture
case "$(uname -m)" in
  aarch64) ETCD_ARCH="arm64" ;;
  x86_64) ETCD_ARCH="amd64" ;;
esac;

ETCD_NAME=etcd-${ETCD_VER}-linux-${ETCD_ARCH}
ETCD_TAR=${ETCD_NAME}.tar.gz

rm -f /tmp/${ETCD_TAR}

curl -L -s ${DOWNLOAD_URL}/${ETCD_VER}/${ETCD_TAR} -o /tmp/${ETCD_TAR}

# If tar fails, probably have an error message within the file, show it.
if tar xzvf /tmp/${ETCD_TAR} -C /usr/local/bin --strip-components=1 ${ETCD_NAME}/etcdctl 2>/dev/null
then
  rm -f /tmp/${ETCD_TAR}
  echo Installed: $(which etcdctl)
  etcdctl version
else
  # Show error
  cat /tmp/${ETCD_TAR}
  echo
  rm -f /tmp/${ETCD_TAR}
fi
