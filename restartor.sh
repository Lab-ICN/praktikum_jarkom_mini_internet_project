#!/bin/bash

USER=ubuntu

WORKDIR=/home/${USER}/mini_internet_project/platform/
students_as=(3 4 13 14)
routers=("ZURI" "BASE" "GENE" "LUGA" "MUNI" "LYON" "VIEN" "MILA")

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
  for as in ${students_as[@]}; do
    cd $WORKDIR../students_config/

    echo "Restoring config on AS: ${as}"
    docker cp ./configs-as-${as}.tar.gz ${as}_ssh:/root/configs-as-${as}.tar.gz

    # How to use heredoc works here?
    docker exec -iw /root ${as}_ssh bash -c "./restore_configs.sh configs-as-${as}.tar.gz all" << EOF
Y
EOF

    # Extract the config file
    cd $WORKDIR../students_config/; rm -rf configs_*; tar -xf configs-as-${as}.tar.gz
    # Get configs folder name
    configs_folder_name=$(ls -d */ | grep configs)

    # Restore router files
    for rc in ${routers[@]}; do
      cd $WORKDIR../students_config/

      container_name=${as}_${rc}router

      # Overwrite backuped router config file to the /etc/frr/frr.conf
      echo "Restoring $container_name configuration..."
      docker cp ${configs_folder_name}${rc}/router.conf ${container_name}:/root/frr.conf
      docker exec -itw /root ${container_name} bash -c 'cat /root/frr.conf > /etc/frr/frr.conf'
      echo "Verifying $container_name configuration... and sleeping for 4 seconds for you to check..."
      docker exec -itw /root ${container_name} bash -c 'cat /etc/frr/frr.conf'
      sleep 4
      docker exec -itw /root ${container_name} bash -c 'rm /root/frr.conf'

      # Now restart the container to take effect
      docker restart $container_name;
      cd $WORKDIR && sudo ./groups/restart_container.sh $container_name
    done
    
    
    # Restore switch files into switch
    for sw in $(seq 1 4); do
      cd $WORKDIR../students_config/

      # Init switch loc
      switch_name=S${sw}
      data_center_loc='DCN'
      if [[ $switch_name == 'S4' ]]; then
        data_center_loc='DCS'
      fi

      container_name=${as}_L2_${data_center_loc}_${switch_name}


      # Get configs folder name
      configs_folder_name=$(ls -d */ | grep configs)

      # Overwrite backuped switch file to the /etc/openvswitch/conf.db
      echo "Restoring $container_name configuration..."
      docker cp ${configs_folder_name}${switch_name}/switch.db ${container_name}:/etc/openvswitch/conf.db

      # Now restart the container to take effect
      docker restart $container_name;
      cd $WORKDIR && sudo ./groups/restart_container.sh $container_name
    done
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