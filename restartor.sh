#!/bin/bash

USER=ubuntu

WORKDIR=/home/${USER}/mini_internet_project/platform/
students_as=(3 4 13 14)

# save all configs first
save_configs() {
  cd $WORKDIR../
  if ! [[ -d students_config ]]; then
    mkdir students_config
  fi

  cd students_config/
  rm -rf *

  for as in ${students_as[@]}; do
    echo "Saving config on AS: ${as}"

    docker exec -itw /root ${as}_ssh bash -c 'rm -rfv configs*' > /dev/null
    docker exec -itw /root ${as}_ssh "./save_configs.sh" > /dev/null

    configName=$(docker exec -itw /root ${as}_ssh bash -c 'find . -maxdepth 1 -regex \./.*.tar.gz' | sed -e 's/\r$//')
    docker exec -itw /root ${as}_ssh bash -c "mv $configName configs-as-${as}.tar.gz"

    docker cp ${as}_ssh:/root/configs-as-${as}.tar.gz ./configs-as-${as}.tar.gz
  done
}

reset_with_startup() {
  echo "Resetting mini internet with startup.sh again..."
  
  cd $WORKDIR
  
  # Hard reset
  echo "Executing cleanup.sh & hard_reset.sh ..."
  ./cleanup/cleanup.sh .
  ./cleanup/hard_reset.sh .

  # Then startup
  echo "Executing startup.sh ..."
  ./startup.sh . && ./utils/ssh/portforwarding.sh . && ./utils/iptables/filters.sh .

  echo "Waiting for docker container to ready first, sleeping in 3 seconds..."
  sleep 3
  
  # Start MATRIX container
  docker unpause MATRIX
  ./groups/restart_container.sh MATRIX
}

restore_configs() {
  cd $WORKDIR../students_config/

  for as in ${students_as[@]}; do
    echo "Restoring config on AS: ${as}"
    docker cp ./configs-as-${as}.tar.gz ${as}_ssh:/root/configs-as-${as}.tar.gz

    # How to use heredoc works here?
    docker exec -iw /root ${as}_ssh bash -c "./restore_configs.sh configs-as-${as}.tar.gz all" << EOF
Y
EOF
  done
}

main() {
  if [[ $(id -u) -ne 0 ]]; then
    echo "You must run as root, exiting..."
    exit 1
  fi

  save_configs
  reset_with_startup
  restore_configs
}

main