#!/bin/bash

# -------------- START OF VARIABLES BLOCK -------------- #
user=ubuntu
# -------------- END OF VARIABLES BLOCK   -------------- #


echo "-- RESTART MINI INTERNET PROJECT --"
echo "Script coded by Lab ICN F9.6 Team"

# Check if the script run as root
if [[ $(id -u) -ne 0 ]]; then
        echo "You must run as root, exiting..."
        exit 1
fi

if [[ $(docker ps -af "status=exited" --format {{.Names}} | wc -l) -eq 0 ]]; then
        echo "Your mini project is fine, exiting..."
        exit 0
fi

# Ensure the kernel modules load first
modprobe mpls_router \
         mpls_gso \
         mpls_iptunnel \
         openvswitch

# Set working directory
WORKDIR=/home/${user}/mini_internet_project/platform/

# Change working dir
cd $WORKDIR

# Verify working dir
echo "Current workdir: $WORKDIR"

# Restart containers
containerList=$(docker ps -a --format {{.Names}})
totalContainerCount=$(echo $containerList | wc -w)

currentContainer=1
for x in $containerList; do
        echo "Starting container with Docker (${currentContainer}/${totalContainerCount}): "
        echo -n "Container killed: "
        docker kill $x
        echo -n "Container started: "
        docker start $x

        (( currentContainer++ ))
done

# Reset IXP Containers
readarray groups < "${WORKDIR}"config/AS_config.txt
groupNums=${#groups[@]}

for ((k=0;k<groupNums;k++)); do
        group_k=(${groups[$k]})
        group_number="${group_k[0]}"
        group_as="${group_k[1]}"
        if [[ $group_as == "IXP" ]]; then
                echo "Resetting ${group_number}_IXP"
                docker rm -f "${group_number}_IXP"
                location="${WORKDIR}"groups/g"${group_number}"
                docker run -itd --net='none' --name="${group_number}""_IXP" \
                        --pids-limit 200 --hostname "${group_number}""_IXP" \
                        -v "${location}"/daemons:/etc/quagga/daemons \
                        --privileged \
                        --sysctl net.ipv4.ip_forward=1 \
                        --sysctl net.ipv4.icmp_ratelimit=0 \
                        --sysctl net.ipv4.fib_multipath_hash_policy=1 \
                        --sysctl net.ipv4.conf.all.rp_filter=0 \
                        --sysctl net.ipv4.conf.default.rp_filter=0 \
                        --sysctl net.ipv4.conf.lo.rp_filter=0 \
                        --sysctl net.ipv4.icmp_echo_ignore_broadcasts=0 \
                        --sysctl net.ipv6.conf.all.disable_ipv6=0 \
                        --sysctl net.ipv6.conf.all.forwarding=1 \
                        --sysctl net.ipv6.icmp.ratelimit=0 \
                        -v /etc/timezone:/etc/timezone:ro \
                        -v /etc/localtime:/etc/localtime:ro \
                        -v "${location}"/looking_glass.txt:/home/looking_glass.txt \
                        --log-opt max-size=1m --log-opt max-file=3 \
                        "miniinterneteth/d_ixp"
        fi
done

for i in $(seq 1 2); do
	echo "ITERATION: ${i} of 2"
	currentContainer=1
	for i in $containerList; do
                # Debug output
                echo "Calling restart_container.sh ${currentContainer} of ${totalContainerCount} : $i";
                # Then call ETHZurich's script
                ${WORKDIR}groups/restart_container.sh $i;

                (( currentContainer++ ))
	done
done

echo "Adding IP route on host at device ssh_to_group for activate SSH"
ip addr add 157.0.0.1/16 dev ssh_to_group
ip link set ssh_to_group up

echo "Running portforwarding.sh"
${WORKDIR}/utils/ssh/portforwarding.sh ${WORKDIR}
