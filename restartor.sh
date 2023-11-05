#!/bin/bash

USER=ubuntu

WORKDIR=/home/${USER}/mini_internet_project/platform/
students_as=(3 4 13 14)
routers=('ZURI' 'BASE' 'GENE' 'LUGA' 'MUNI' 'LYON' 'VIEN' 'MILA')

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

      # Remove the building configuration and current configuration text
      docker exec -itw /root ${container_name} bash -c 'sed '1,3d' /root/frr.conf > /root/frr-removed-header.conf'

      docker exec -itw /root ${container_name} bash -c '/usr/lib/frr/frr-reload.py --reload /root/frr-removed-header.conf'
      sleep 2
      docker exec -itw /root ${container_name} bash -c 'rm /root/{frr,frr-removed-header}.conf'

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
      docker cp ${configs_folder_name}${switch_name}/switch.db ${container_name}:/root/switch.db
      docker exec -itw /root ${container_name} bash -c 'ovsdb-client restore < /root/switch.db'
      sleep 2
      docker exec -itw /root ${container_name} bash -c 'rm /root/switch.db'
    done
  done
}

show_passwords() {
  cd $WORKDIR
  echo "--- START OF ASes PASSWORDS ---"
  cat groups/passwords.txt
  echo "---  END OF ASes PASSWORDS  ---"

  echo "--- START OF krill_passwords ---"
  cat groups/krill_passwords.txt
  echo "---  END OF krill_passwords  ---"

  echo "--- START OF MEASUREMENT PASSWORDS ---"
  cat groups/ssh_measurement.txt
  echo "---  END OF MEASUREMENT PASSWORDS  ---"
}

main() {
  if [[ $(id -u) -ne 0 ]]; then
    echo "You must run as root, exiting..."
    exit 1
  fi

  save_configs
  reset_with_startup
  restore_configs
  echo "Restart complete, here are all passwords..."
  show_passwords
}

main