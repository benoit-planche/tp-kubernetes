# Cluster Kubernetes Local avec k3d

Ce projet déploie un cluster Kubernetes local en utilisant k3d, un outil qui permet de créer des clusters K3s dans des conteneurs Docker.

## Prérequis

- Terraform >= 1.0.0
- Docker installé et en cours d'exécution
- Au moins 4GB de RAM disponible
- Au moins 20GB d'espace disque libre

## Installation

1. Initialisez Terraform :

   ```bash
   terraform init
   ```

2. Appliquez la configuration :

   ```bash
   terraform apply
   ```

## Architecture

Le déploiement inclut :

- Un cluster k3d avec :
  - 1 nœud master (server)
  - 3 nœuds workers (agents, configurable via `worker_count`)
- Configuration automatique de kubectl
- Ports 80 et 443 exposés via le loadbalancer
- Traefik et ServiceLB désactivés pour plus de flexibilité

## Fonctionnalités

- Installation automatique de k3d
- Création d'un cluster multi-nœuds
- Configuration automatique de kubectl
- Vérification de l'installation

## Commandes utiles

```bash
# Lister les clusters
k3d cluster list

# Accéder au cluster
kubectl get nodes

# Supprimer le cluster
k3d cluster delete mycluster
```

## Nettoyage

Pour supprimer le cluster :

```bash
k3d cluster delete mycluster
```

## Vérification

Pour vérifier que le cluster fonctionne correctement :

```bash
kubectl get nodes
kubectl get pods -n kube-system
```
