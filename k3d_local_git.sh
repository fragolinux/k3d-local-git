#!/usr/bin/env bash

set -m  # enable job control

## run with "-d" command line switch to debug each step, script will wait for keypress to go on
## integrated mods by KingdonB in his fork: https://gist.github.com/kingdonb/dec74f3b74ffbb83b54d53d5c033e508
## added proper coredns patching via "coredns-custom" configmap
## added automatic /etc/hosts file modification if needed, sudo password will be asked in case
## added (commented out) lines to add Flux extra controllers to the setup
## deployed podinfo as in Flux Get Started guide
## added kustomize patch to change color in podinfo deployment
## added ingress on http port 8081
## added automatic local ip retrieval, thanks to Log2: https://gist.github.com/log2/f2fd0fa040509d3b6829ce813e5470dc
## ask for confirmation on project folder deletion, and added a bit of "lipstick on a pig", ehm, color :)
## issue: https://github.com/fluxcd/flux/issues/3594

BLACK="\033[0;30m"
BLUE="\033[0;34m"
GREEN="\033[0;32m"
GREY="\033[0;90m"
YELLOW="\033[0;93m"
CYAN="\033[0;36m"
RED="\033[0;31m"
PURPLE="\033[0;35m"
BROWN="\033[0;33m"
WHITE="\033[1;37m"
COLOR_RESET="\033[0m"

echog(){
  echo;echo;echo -e "### ${GREEN}${1}${COLOR_RESET} ###"
}

readr(){
  echo;echo;echo -en ">>> ${RED}${1}${COLOR_RESET} <<<" && read -p ""
}

CONFIG_HOME=~/testgit
CONFIG_REPO=testrepo
CLONE_PATH=${CONFIG_HOME}/${CONFIG_REPO}
BARE_REPO_PATH=${CONFIG_HOME}/gitsrv/${CONFIG_REPO}.git
CLUSTER_NAME=testclu
PUBLICDNS=e4t.example.com
GITSRV_IMG=jkarlos/git-server-docker

_is_good_local_ip() {
  local ip="$1"
  [ -n "$ip" ] && ping "$ip" -c 1 -W 50 &>/dev/null
}

if ! _is_good_local_ip "$PUBLICIP"; then
  echo "PUBLICIP undefined or not reachable, searching for it among defined interfaces (en0 through en9)"
  PUBLICIP=
  for intf in $(seq 0 9)
  do
    tempIP="$(ipconfig getifaddr en$intf)"
    echo -n "Probing local IP $tempIP from interface en$intf ..."
    if _is_good_local_ip "$tempIP" ; then
      echo " IP is reachable, will use it for the rest of this script"
      PUBLICIP="$tempIP"
      break
    else
      echo " IP is not reachable"
    fi
  done
  [ -z "$PUBLICIP" ] && echo "Can't find local IP, please set it accordingly via PUBLICIP variable before starting this script" && exit 1
fi

echog "creating folder structure and ssh keys"
mkdir -p ${CONFIG_HOME}/{${CONFIG_REPO},sshkeys,gitsrv}
ssh-keygen -b 521 -o -t ecdsa -N "" -f ${CONFIG_HOME}/sshkeys/identity

echog "creating a test repo for the gitsrv"
cd ${CLONE_PATH}
git init --shared=true
echo Nothing > README.md
git add .
git commit -m "1st commit"
git clone --bare ${CLONE_PATH} ${BARE_REPO_PATH}

[ "$1" == "-d" ] && readr "Press [Enter] key to continue and create k3d cluster..."

echog "creating a k3d local test cluster with loadbalancer on port 8081"
k3d cluster create ${CLUSTER_NAME} -p "8081:80@loadbalancer"

echog "Waiting for CoreDNS deploying"
ATTEMPTS=0
ROLLOUT_STATUS_CMD="kubectl rollout status deployment/coredns -n kube-system"
until $ROLLOUT_STATUS_CMD || [ $ATTEMPTS -eq 120 ]; do
  $ROLLOUT_STATUS_CMD
  ATTEMPTS=$((ATTEMPTS + 1))
  sleep 1
done

echog "CoreDNS deployed, waiting for its ConfigMap"
while true ; do
    result=$(kubectl -n kube-system get configmap coredns 2>&1)
    if [[ $result == *NotFound* ]] || [[ $result == *refused* ]]; then
        sleep 1
    else
        break
    fi
done

[ "$1" == "-d" ] && readr "Press [Enter] key to continue and patch coredns..."

echog "checking /etc/hosts line presence, or adding it if missing"
if grep -q "$PUBLICDNS" /etc/hosts ; then
    echo "/etc/hosts file already modded"
else
    echo "127.0.0.1 $PUBLICDNS" | sudo tee -a /etc/hosts > /dev/null
    echo "added missing '127.0.0.1 $PUBLICDNS' line to your /etc/hosts file"
fi

echog "CoreDNS ConfigMap ready, patching it"
    read -rd '' coredns_custom << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  example.server: |
    example.com {
      hosts {
          ${PUBLICIP} ${PUBLICDNS}
          fallthrough
      }
      whoami
    }
EOF

echo "$coredns_custom" > ${CONFIG_HOME}/coredns-custom.yaml
kubectl apply -f ${CONFIG_HOME}/coredns-custom.yaml
kubectl get pods -n kube-system|grep coredns|cut -d\  -f1|xargs kubectl delete pod -n kube-system
# to test new dns record working, use: kubectl apply -f https://k8s.io/examples/admin/dns/dnsutils.yaml

[ "$1" == "-d" ] && readr "Press [Enter] key to continue and create local git server..."

echog "creating the local gitserver pointing to the folders created above"
docker run -d -p 2222:22 \
-v ${CONFIG_HOME}/sshkeys:/git-server/keys \
-v ${CONFIG_HOME}/gitsrv:/git-server/repos \
--name gitsrv $GITSRV_IMG

echog "wait for port 2222 to be opened"
while ! nc -z localhost 2222; do
  sleep 0.1
done

echog "adding ssh key and testing ssh"
ssh-add -D ${CONFIG_HOME}/sshkeys/identity
ssh-add ${CONFIG_HOME}/sshkeys/identity
sleep 1
ssh git@${PUBLICDNS} -p 2222

[ "$1" == "-d" ] && readr "Press [Enter] key to continue and bootstrap Flux on local git server and cluster..."

echog "bootstrapping flux on test cluster, using SAME private key already used for the git server"
flux bootstrap git --branch=develop --path=. \
--url=ssh://git@${PUBLICDNS}:2222/git-server/repos/${CONFIG_REPO}.git \
--private-key-file=../sshkeys/identity --silent

[ "$1" == "-d" ] && readr "Press [Enter] key to continue cloning the git repo and adding coredns ..."

echog "cloning created git repo and adding coredns patch"
cd ${CONFIG_HOME}
rm -rf ${CLONE_PATH}
git clone ssh://git@${PUBLICDNS}:2222/git-server/repos/${CONFIG_REPO}.git -b develop
cd ${CLONE_PATH}
mv ${CONFIG_HOME}/coredns-custom.yaml ${CLONE_PATH}
git add -A && git commit -m "Add coredns patch"
git push

[ "$1" == "-d" ] && readr "Press [Enter] key to continue and add podinfo git repo..."

echog "Add podinfo repository to Flux"
flux create source git podinfo \
  --url=https://github.com/stefanprodan/podinfo \
  --branch=master \
  --interval=30s \
  --export > podinfo-source.yaml
git add -A && git commit -m "Add podinfo GitRepository"
git push

[ "$1" == "-d" ] && readr "Press [Enter] key to continue and add podinfo application..."

echog "Deploy podinfo application"
flux create kustomization podinfo \
  --target-namespace=default \
  --source=podinfo \
  --path="./kustomize" \
  --prune=true \
  --wait=true \
  --interval=5m \
  --export > podinfo-kustomization.yaml
git add -A && git commit -m "Add podinfo Kustomization"
git push

echog "Waiting for PodInfo deploying"
ATTEMPTS=0
ROLLOUT_STATUS_CMD="kubectl rollout status deployment/podinfo -n default"
FLUX_RECONCILE_CMD="flux reconcile kustomization flux-system --with-source"

$FLUX_RECONCILE_CMD &
until $ROLLOUT_STATUS_CMD || [ $ATTEMPTS -eq 120 ]; do
  $ROLLOUT_STATUS_CMD
  ATTEMPTS=$((ATTEMPTS + 1))
  sleep 1
done

if [ "$1" == "-d" ]; then
  echog "opening http://localhost:9898 in your browser (only on Mac - do it manually on other systems)"
  kubectl port-forward deployment/podinfo 9898:9898 &
  PID=$!
  open http://${PUBLICDNS}:9898
fi

[ "$1" == "-d" ] && readr "Press [Enter] key to continue and change podinfo background via kustomize patch..." && kill -9 $PID
echog "adding kustomize patch to alter podinfo background"
cd ${CLONE_PATH}
IFS= read -rd '' podinfopatch << EOF
  patches:
    - patch: |-
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: podinfo
        spec:
          template:
            spec:
              containers:
              - name: podinfod
                env:
                - name: PODINFO_UI_COLOR
                  value: '#ffff00'
        target:
          name: podinfo
          kind: Deployment
EOF
echo -e "$podinfopatch" >> podinfo-kustomization.yaml
git add -A
git commit -m "changed color in podinfo deployment via kustomize patch"
git push

echog "adding ingress for podinfo on http://${PUBLICDNS}:8081"
cd ${CLONE_PATH}
IFS= read -rd '' podinfoingress << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: podinfo
  namespace: default
  annotations:
    ingress.kubernetes.io/ssl-redirect: "false"
spec:
  rules:
  - host: ${PUBLICDNS}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: podinfo
            port:
              number: 9898
EOF
echo -e "$podinfoingress" > podinfo-ingress.yaml
git add -A
git commit -m "adding ingress for podinfo on http port 8081"
git push

$FLUX_RECONCILE_CMD         # flux will wait for the new deploy to become ready, but we cannot create a new
flux reconcile kustomization podinfo --with-source # NEEDED otherwise next port-forward will fail...
$ROLLOUT_STATUS_CMD         # port-forward on the same port before it finished terminating! wait for that,

kubectl port-forward deployment/podinfo 9898:9898 &
PID=$!
[ "$1" == "" ] && open http://${PUBLICDNS}:9898 # browse port-forward, open only if in unattended mode
open http://${PUBLICDNS}:8081 # browse ingress

echo; echo
readr "Press [Enter] key to continue and close portforward, ending script (or ^C to leave it running) "
kill -9 $PID

echo;echo;echo -e ">>> ${GREEN}to remove everything, run the following lines${COLOR_RESET} <<<\n${YELLOW}docker stop gitsrv\ndocker rm gitsrv\nk3d cluster delete ${CLUSTER_NAME}\nrm -rf ${CONFIG_HOME}${COLOR_RESET}"

# to add flux extra controllers, uncomment and run next lines:
# echo "adding image-reflector-controller,image-automation-controller Flux extra controllers"
# cd ${CLONE_PATH}/flux-system
# flux install --components-extra=image-reflector-controller,image-automation-controller --export > gotk-components.yaml
# git add .
# git commit -m "adding Flux image-reflector-controller and image-automation-controller"
# git push
# $FLUX_RECONCILE_CMD &