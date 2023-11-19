#!/bin/bash

if [ $# -lt 1 ]; then
    echo Invalid argument:
    echo "./connect_as.sh AS_NUMBER [ixp | ROUTER [h]]"
    exit 1
fi

if [ $# -eq 1 ]; then
    docker exec -itw /root/ ${1}_ssh bash
elif [ $2 == "ixp" ]; then
    docker exec -it ${1}_IXP vtysh
else
    if [ $# -eq 2 ] || [ $3 == "router" ] || [ $3 == "r" ]; then
        docker exec -itw /root/ ${1}_ssh bash -c "./goto.sh ${3} router"
    elif [ $3 == "host" ] || [ $3 == "h" ]; then
        docker exec -itw /root/ ${1}_ssh bash -c "./goto.sh ${3} host"
    elif [ $3 == "container" ] || [ $3 == "c" ]; then
        docker exec -itw /root/ ${1}_ssh bash -c "./goto.sh ${3} container"
    fi
fi