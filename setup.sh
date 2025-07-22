#!/bin/bash

# Script per installazione cluster Kubernetes su Ubuntu 25.04
# Supporta: 1 master + 2 worker nodes con Kubernetes v1.33.2
# Requisiti: IP statici già configurati su tutte le macchine

set -e

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funzione per logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Verifica se lo script è eseguito come root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Questo script deve essere eseguito come root (usa sudo)"
    fi
}

# Verifica sistema operativo
check_os() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        error "Questo script è progettato per Ubuntu"
    fi

    local version=$(lsb_release -rs)
    log "Sistema operativo: Ubuntu $version"
}

# Configurazione iniziale del sistema
system_setup() {
    log "Configurazione iniziale del sistema..."

    # Aggiornamento sistema
    apt update && apt upgrade -y

    # Installazione pacchetti essenziali
    apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release

    # Disabilitazione swap (richiesto da Kubernetes)
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

    # Configurazione moduli kernel
    cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

    modprobe overlay
    modprobe br_netfilter

    # Configurazione parametri sysctl
    cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

    sysctl --system

    log "Configurazione sistema completata"
}

# Installazione Container Runtime (containerd)
install_containerd() {
    log "Installazione containerd..."

    # Aggiunta repository Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

    apt update
    apt install -y containerd.io

    # Configurazione containerd
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml

    # Abilitazione SystemdCgroup
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

    # Restart e abilitazione servizio
    systemctl restart containerd
    systemctl enable containerd

    log "containerd installato e configurato"
}

# Installazione Kubernetes components
install_kubernetes() {
    log "Installazione componenti Kubernetes..."

    # Aggiunta repository Kubernetes (latest stable)
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | gpg --dearmor -o /usr/share/keyrings/kubernetes-apt-keyring.gpg

    echo 'deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' > /etc/apt/sources.list.d/kubernetes.list

    apt update

    # Installazione kubelet, kubeadm, kubectl
    apt install -y kubelet kubeadm kubectl

    # Blocco aggiornamenti automatici
    apt-mark hold kubelet kubeadm kubectl

    # Abilitazione kubelet
    systemctl enable kubelet

    log "Componenti Kubernetes v1.33 installati"
}

# Inizializzazione cluster master
init_master() {
    log "Inizializzazione cluster master..."

    local master_ip
    read -p "Inserisci l'IP del nodo master: " master_ip

    if [[ ! $master_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        error "IP non valido"
    fi

    # Inizializzazione cluster con configurazioni per v1.33
    kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$master_ip --kubernetes-version=v1.33.2

    # Configurazione kubectl per utente root
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config

    # Configurazione per utenti non-root (opzionale)
    if [[ -n "$SUDO_USER" ]]; then
        local user_home=$(eval echo ~$SUDO_USER)
        sudo -u $SUDO_USER mkdir -p $user_home/.kube
        cp /etc/kubernetes/admin.conf $user_home/.kube/config
        chown $SUDO_USER:$SUDO_USER $user_home/.kube/config
    fi

    log "Cluster master inizializzato"

    # Salvataggio comando join
    kubeadm token create --print-join-command > /tmp/join-command.sh
    chmod +x /tmp/join-command.sh

    warn "IMPORTANTE: Salva il seguente comando per unire i worker nodes:"
    echo -e "${BLUE}$(cat /tmp/join-command.sh)${NC}"

    log "Il comando è stato salvato anche in /tmp/join-command.sh"
}

# Installazione network plugin (Flannel)
install_network_plugin() {
    log "Installazione network plugin (Flannel) per Kubernetes v1.33..."

    # Verifica che kubectl funzioni
    if ! kubectl cluster-info &>/dev/null; then
        error "kubectl non configurato correttamente"
    fi

    # Installazione Flannel compatibile con v1.33
    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

    # Patch per compatibilità con versioni più recenti se necessario
    kubectl patch daemonset kube-flannel-ds -n kube-flannel --type='merge' -p='{"spec":{"template":{"spec":{"tolerations":[{"operator":"Exists"}]}}}}'

    log "Network plugin installato per Kubernetes v1.33"

    # Attesa che i pod di sistema siano pronti (timeout aumentato per v1.33)
    log "Attendendo che i pod di sistema siano pronti..."
    kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=600s || warn "Alcuni pod potrebbero ancora essere in avvio"

    log "Cluster pronto per l'aggiunta di worker nodes"
}

# Join worker node
join_worker() {
    log "Configurazione worker node..."

    echo "Inserisci il comando kubeadm join (ottenuto dal master):"
    read -r join_command

    if [[ ! $join_command == *"kubeadm join"* ]]; then
        error "Comando join non valido"
    fi

    # Esecuzione comando join
    eval $join_command

    log "Worker node aggiunto al cluster"
}

# Verifica stato cluster
check_cluster() {
    log "Verifica stato cluster..."

    echo -e "\n${BLUE}=== NODI DEL CLUSTER ===${NC}"
    kubectl get nodes -o wide

    echo -e "\n${BLUE}=== POD DI SISTEMA ===${NC}"
    kubectl get pods -n kube-system

    echo -e "\n${BLUE}=== STATO CLUSTER ===${NC}"
    kubectl cluster-info
}

# Menu principale
show_menu() {
    echo -e "\n${BLUE}=== INSTALLAZIONE CLUSTER KUBERNETES v1.33.2 ===${NC}"
    echo "1. Installazione completa Master Node"
    echo "2. Installazione Worker Node"
    echo "3. Solo preparazione sistema (tutti i nodi)"
    echo "4. Solo installazione Kubernetes components"
    echo "5. Verifica stato cluster"
    echo "6. Esci"
    echo
}

# Installazione completa master
install_master_complete() {
    log "Avvio installazione completa Master Node..."
    system_setup
    install_containerd
    install_kubernetes
    init_master
    install_network_plugin
    check_cluster
    log "Installazione Master Node completata!"
}

# Installazione worker
install_worker_complete() {
    log "Avvio installazione Worker Node..."
    system_setup
    install_containerd
    install_kubernetes
    join_worker
    log "Installazione Worker Node completata!"
}

# Preparazione sistema
prepare_system_only() {
    log "Preparazione sistema..."
    system_setup
    install_containerd
    install_kubernetes
    log "Sistema preparato per Kubernetes"
}

# Main
main() {
    check_root
    check_os

    while true; do
        show_menu
        read -p "Seleziona un'opzione [1-6]: " choice

        case $choice in
            1)
                install_master_complete
                ;;
            2)
                install_worker_complete
                ;;
            3)
                prepare_system_only
                ;;
            4)
                install_kubernetes
                ;;
            5)
                check_cluster
                ;;
            6)
                log "Uscita..."
                exit 0
                ;;
            *)
                warn "Opzione non valida. Riprova."
                ;;
        esac

        echo
        read -p "Premi INVIO per continuare..."
    done
}

# Esecuzione script
main "$@"
