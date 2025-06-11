# Déploiement d'une Application Flask avec PostgreSQL sur Kubernetes

Ce projet démontre le déploiement d'une application Flask avec une base de données PostgreSQL sur un cluster Kubernetes local utilisant k3d, avec l'intégration d'Istio pour la gestion du trafic.

## Architecture

Le projet comprend les composants suivants :

- **Application Flask** : Une application web simple qui se connecte à PostgreSQL
- **PostgreSQL** : Base de données pour stocker les données de l'application
- **Kubernetes** : Orchestration des conteneurs via k3d
- **Istio** : Service mesh pour la gestion du trafic et l'observabilité

## Prérequis

- Docker
- k3d
- Terraform
- kubectl
- curl

## Installation

1. Clonez le repository :

   ```bash
   git clone <repository-url>
   cd tp-kubernetes
   ```

2. Initialisez Terraform :

   ```bash
   terraform init
   ```

3. Appliquez la configuration :

   ```bash
   terraform apply
   ```

Cette commande va :

- Créer un cluster k3d
- Installer Istio
- Déployer l'application Flask et PostgreSQL
- Configurer les ressources Istio

## Accès à l'Application

L'application est accessible de deux manières :

1. Via le service NodePort :

   ```bash
   curl http://172.22.0.5:30762
   ```

2. Via l'Ingress Gateway d'Istio :

   ```bash
   curl http://172.22.0.5:32103
   ```

## Structure du Projet

```
.
├── Dockerfile              # Configuration de l'image Docker pour l'application Flask
│   └── requirements.txt   # Dépendances Python
├── manifests/
│   ├── app-deployment.yaml    # Déploiement de l'application Flask
│   ├── app-service.yaml       # Service pour l'application Flask
│   ├── postgres-configmap.yaml # Configuration PostgreSQL
│   ├── postgres-deployment.yaml # Déploiement PostgreSQL
│   ├── postgres-pvc.yaml      # Volume persistant pour PostgreSQL
│   └── postgres-service.yaml  # Service PostgreSQL
├── main.tf               # Configuration Terraform principale
├── variables.tf          # Variables Terraform
└── README.md            # Ce fichier
```

## Fonctionnalités

- **Haute Disponibilité** : L'application Flask est déployée avec plusieurs réplicas
- **Persistance des Données** : PostgreSQL utilise un volume persistant
- **Gestion du Trafic** : Istio gère le routage du trafic
- **Observabilité** : Grafana est déployé pour la surveillance

## Maintenance

### Vérification du Statut

```bash
# Vérifier les pods
kubectl get pods

# Vérifier les services
kubectl get services

# Vérifier les ressources Istio
kubectl get gateway,virtualservice
```

### Logs

```bash
# Logs de l'application Flask
kubectl logs -l app=flask-app

# Logs de PostgreSQL
kubectl logs -l app=postgres
```

## Nettoyage

Pour supprimer toutes les ressources :

```bash
terraform destroy
```

## Dépannage

1. **L'application n'est pas accessible**
   - Vérifiez que les pods sont en état "Running"
   - Vérifiez les logs des pods
   - Vérifiez la configuration du service et de l'Ingress Gateway

2. **Problèmes de connexion à la base de données**
   - Vérifiez que PostgreSQL est en cours d'exécution
   - Vérifiez les logs de PostgreSQL
   - Vérifiez la configuration de la connexion dans l'application

## Contribution

Les contributions sont les bienvenues ! N'hésitez pas à ouvrir une issue ou une pull request.

## Licence

Ce projet est sous licence MIT.
