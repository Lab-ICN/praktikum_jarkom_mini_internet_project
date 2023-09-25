#!/bin/bash

echo "-- RESTART MINI INTERNET PROJECT --"
echo "Script coded by Lab ICN F9.6 Team"

# Check if the script run as root
if [[ $(id -u) -ne 0 ]]; then
        echo "You must run as root, exiting..."
        exit 1
fi

# Ensure the kernel modules load first
modprobe mpls_router \
         mpls_gso \
         mpls_iptunnel \
         openvswitch

# Set working directory
WORKDIR=/home/ubuntu/mini_internet_project/platform/

# Change working dir
cd $WORKDIR

# Verify working dir
echo "Current workdir: $WORKDIR"

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

containerList=$(docker ps -af "status=exited" --format {{.Names}})
totalContainerCount=$(echo $containerList | wc -w)
currentContainer=1

# Restart back all mini internet project
for x in $containerList; do
        echo "Starting container with Docker (${currentContainer}/${totalContainerCount}): "
        echo -n "Container killed: "
        docker kill $x
        echo -n "Container started: "
        docker start $x

        (( currentContainer++ ))
done


containerList=$(docker ps -a --format {{.Names}})
currentContainer=1

for i in $containerList; do
        # Debug output
        echo "Calling restart_container.sh ${currentContainer} of ${totalContainerCount} : $i";
        # Then call ETHZurich's script
        ${WORKDIR}/groups/restart_container.sh $i;

        (( currentContainer++ ))
done

# Start remaining container (if any)
remainContainer=$(docker ps -af "status=exited" --format {{.Names}})

for r in $remainContainer; do
        echo "Starting remaining container: $r"
        # Kill container first
        echo -n "Container killed: "
        docker kill $r;
        # Then start it
        echo -n "Container started: "
        docker start $r;
        # Then call ETHZurich's script
        ${WORKDIR}/groups/restart_container.sh $r;
done