#!/bin/bash 

up=$PWD
export NETWORK_NAME=nimiq.local
export DOCKER_BUILDKIT=1

case $(uname -s) in
Darwin)
	NOCOLOR='\033[0m'    # Color off
	RED='\033[0;31m' # Red
	GREEN='\033[0;32m' # Green
	BLUE='\033[0;34m' # Blue
	;;

*)
	NOCOLOR='\e[0m'    # Color off
	RED='\e[1;31m' # Red
	GREEN='\e[1;32m' # Green
	BLUE='\e[1;36m' # Blue
	;;
esac

function list_repos() {
cat << EOF
albatross git@github.com:nimiq/core-rs-albatross.git albatross
EOF
}

function sync_repo() {
    DIR=$1
    REPO=$2
    BRANCH=$3

    echo -e "\n${BLUE}Syncing ${REPO}${NOCOLOR}"

    if [ -d $up/$DIR ]; then 
        cd $up/$DIR 
        git fetch origin
        if [ "$(git status --porcelain)" == "" ] && [ "$(git branch --show-current)" == "$BRANCH" ]; then
            git merge origin/$BRANCH 
        else 
            echo -e "${RED}Repo has untracked changes or is not on $BRANCH branch: merge manually${NOCOLOR}"
        fi
        cd $up
    else 
        git clone $REPO -b $BRANCH $DIR 
    fi 
    echo -e "${GREEN}Done${NOCOLOR}"
}

function build_albatross() {
    cp -f build_ubuntu.Dockerfile albatross/build_ubuntu.Dockerfile
    cp -f build_ubuntu.Dockerfile.dockerignore albatross/build_ubuntu.Dockerfile.dockerignore
    cp -f docker_run.sh albatross/scripts/docker_run.sh
    cp -f docker_config.sh albatross/scripts/docker_config.sh

    chmod 777 albatross/scripts/docker_run.sh
    chmod 777 albatross/scripts/docker_config.sh

    docker compose -f ./docker-compose.yaml build 
}

function up_albatross() {
    docker volume ls | grep -v "VOLUME" | awk '{print $2}' | while read volume; do docker volume rm $volume; done
    docker compose -f ./docker-compose.yaml up -d 
}

function log_albatross() {
    docker compose -f ./docker-compose.yaml logs -f
}

function down_albatross() {
    docker compose -f ./docker-compose.yaml down
}

function show_help() {
cat << EOF
Nimiq devlab: for editing and running pool for development purposes.

usage:
    run.sh <command>

supported commands:
    sync                Sync all necessary repositories
    build-albatross     Build albatross container
    up-albatross        Bring up albatross test-lab with docker-compose 
    down-albatross      Bring down albatross test-lab with docker-compose 
    log-albatross       Attach logger to running albatross nodes
EOF
}

if [ $# -gt 0 ]; then
    case $1 in 
        sync) 
            list_repos | while read info; do sync_repo $info; done;;
        
        build-albatross)
            build_albatross;;
        
        up-albatross)
            up_albatross;;
        
        down-albatross)
            down_albatross;;

        log-albatross)
             log_albatross;;
        
        *) 
            show_help;;
    esac
else 
    show_help
fi
