# Kubernetes Cluster Setup Script for Ubuntu 25.04

Questo script automatizza l'installazione di un cluster Kubernetes (v1.33.2) su Ubuntu 25.04, composto da un nodo master e due nodi worker.

## ✅ Funzionalità principali

- Installazione di `containerd` come container runtime
- Installazione dei componenti `kubelet`, `kubeadm`, `kubectl`
- Disabilitazione di `swap` e configurazione dei moduli kernel richiesti
- Inizializzazione del master con rete Flannel
- Generazione del comando `kubeadm join` per i worker
- Possibilità di verificare lo stato del cluster

## 📌 Requisiti

- Ubuntu 25.04 su tutti i nodi
- IP statico configurato su ogni macchina
- Accesso come root o `sudo`

## 🚀 Utilizzo

Esegui lo script con:

```bash
sudo ./install_k8s_cluster.sh
```

Ti verrà presentato un menu con le seguenti opzioni:

1. **Installazione completa Master Node**: Prepara il sistema, installa i componenti, inizializza il cluster e installa la rete Flannel.
2. **Installazione Worker Node**: Prepara il sistema e unisce il nodo al cluster.
3. **Solo preparazione sistema (tutti i nodi)**: Installa containerd e Kubernetes ma non inizializza il cluster.
4. **Solo installazione Kubernetes components**: Installa solo kubelet, kubeadm e kubectl.
5. **Verifica stato cluster**: Mostra lo stato dei nodi e dei pod.
6. **Esci**

## 🌐 Note

- Il file di configurazione kubeconfig viene copiato anche per l’utente non-root se si usa `sudo`.
- Il comando `kubeadm join` viene salvato anche in `/tmp/join-command.sh`.
- La rete Flannel viene installata automaticamente.

## 📄 Licenza

Questo script è fornito "as is" senza alcuna garanzia. Utilizzalo a tuo rischio.

---
