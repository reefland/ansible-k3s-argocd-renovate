#!/bin/bash
# NAME       : cri-purge.sh
# 
# DESCRIPTION: This script will parse the output of "crictl images" to
#           determine older images that can be pruned.  Unlike "--prune"
#           option this will not delete all images that are not in use on
#           this specific node.  It will only attempt to delete old versions
#           of the image
#
# ASSUMPTION: The output of CRICTL will be in symantic version order from
#           oldest to newest (v1.7.1, v1.8.0, v1.8.1, v1.8.2, v1.9.0) with the
#           goal to only retain the newest version.
#
#           This script requires root permissions to access the CRICTL and K3S
#           binary files.
#          
# AUTHOR     : Richard J. Durso
# DATE       : 09/01/2022
# VERSION    : 0.01
#############################################################################

if [ $(id -u) -ne 0 ]; then
  echo
  echo "* ERROR: ROOT privilage required to access CRICTL and K3S binaries."
  echo
  exit 1
fi

# Define variables
CRI_CMD="crictl"
# Location of image store to calculate disk space freed (before / after)
IMAGE_STORE="/var/lib/containerd/"
# Skip images with these tags, let human deal with them
SKIP_THESE_TAGS="<none> latest"

###[ Generate Image List ]###################################################
# load list of images / filter out header line
CRI_IMAGES=$(${CRI_CMD} images | tail -n +2)

# Filter out TAGS to SKIP
for TAG in ${SKIP_THESE_TAGS};
do
  if [ $(echo "${CRI_IMAGES}" | grep -c ${TAG}) -ne 0 ]; then
    echo "NOTE: Skipping Images with Tag: ${TAG}"
    echo "${CRI_IMAGES}" | grep ${TAG}
    CRI_IMAGES=$(echo "${CRI_IMAGES}" | grep -v ${TAG}) 
    echo
  fi
done

TOTAL_CRI_IMAGES=$(echo -n "${CRI_IMAGES}" | grep -c '^')

# Reduce raw image list to unique names (without version)
UNIQUE_CRI_IMAGE_NAMES=$(echo "${CRI_IMAGES}" | awk '{ print $1 }' | sort -u)
TOTAL_UNIQUE_IMAGE_NAMES=$(echo -n "${UNIQUE_CRI_IMAGE_NAMES}" | grep -c '^')

###[ Routines ]##############################################################
__process_images() {
  echo
  echo "Total Images: ${TOTAL_CRI_IMAGES} Unique Image Names: ${TOTAL_UNIQUE_IMAGE_NAMES}"
  echo
  COUNT=0
  for IMAGE_NAME in ${UNIQUE_CRI_IMAGE_NAMES};
  do
    ((COUNT=COUNT+1))
    echo -n "${COUNT} / ${TOTAL_UNIQUE_IMAGE_NAMES} : Name: ${IMAGE_NAME}"

    # Find all versions of this IMAGE_NAME
    IFS=$'\n';IMAGES=( $(echo "${CRI_IMAGES}" | grep ${IMAGE_NAME}) )
    NUM_IMAGES=${#IMAGES[@]}

    # If only 1 version detected, keep it.
    if [[ ${NUM_IMAGES} -eq 1 ]]; then
      echo " - Keep TAG: $(echo ${IMAGES} | awk '{ printf "%s (%s)\n", $2, $4 }')"
      echo
    else
      # print last line of the array, shoudl be one to keep.
      echo " - Keep TAG: $(printf %s\\n "${IMAGES[@]: -1}"| awk '{ printf "%s (%s)\n", $2, $4 }')"

      for (( i=0; i<$(( ${#IMAGES[@]}-1 )); i++ )) 
      do
        echo - Purge TAG: $( echo ${IMAGES[$i]} | awk '{ printf "%s (%s)\n", $2, $4 }')

        # Remove the Specific Image:TAG
        ${CRI_CMD} rmi $(echo ${IMAGES[$i]} |awk '{ printf "%s:%s\n", $1, $2 }') > /dev/null 2>&1
      done
      echo
    fi
  done
}

###[ Main Section ]##########################################################

START_DISK_SPACE=$(du -ab ${IMAGE_STORE} | sort -n -r | head -1 | awk '{ print $1 }')
__process_images
END_DISK_SPACE=$(du -ab ${IMAGE_STORE} | sort -n -r | head -1 | awk '{ print $1 }')

echo Disk Space Change: $(numfmt --to iec --format "%8.4f" $((START_DISK_SPACE-END_DISK_SPACE)) )
