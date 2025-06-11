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

## Accès à l'application avec la politique de rate limiting

La politique de rate limiting (VirtualService Istio) bloque uniquement les requêtes HTTP dont le header `user-agent` est exactement `curl` (par exemple, `curl -A "curl" ...`).

- **Les requêtes classiques** (navigateur, ou `curl http://<IP_LOAD_BALANCER>:<NODE_PORT>`) ne sont pas bloquées et accèdent normalement à l'application.
- **Seules les requêtes avec `-A "curl"`** ou un user-agent exactement égal à `curl` reçoivent une erreur HTTP 429 (Too Many Requests).

**Exemple :**

- Cette commande fonctionne (retourne le JSON attendu) :

  ```bash
  curl http://172.22.0.5:32599/
  ```

- Celle-ci est bloquée (retourne 429) :

  ```bash
  curl -A "curl" http://172.22.0.5:32599/
  ```

Vous pouvez donc toujours accéder à l'application normalement, même avec la politique de rate limiting activée.

## Structure du Projet

```
.
├── app/                    # Code source de l'application Flask
│   ├── app.py             # Application Flask
│   └── requirements.txt   # Dépendances Python
├── manifests/             # Manifests Kubernetes
│   ├── app-deployment.yaml    # Déploiement de l'application Flask
│   ├── app-service.yaml       # Service pour l'application Flask
│   ├── app-gateway.yaml       # Configuration Istio Gateway
│   ├── app-virtualservice.yaml # Configuration Istio VirtualService
│   ├── postgres-configmap.yaml # Configuration PostgreSQL
│   ├── postgres-deployment.yaml # Déploiement PostgreSQL
│   ├── postgres-pvc.yaml      # Volume persistant pour PostgreSQL
│   ├── postgres-service.yaml  # Service PostgreSQL
│   ├── grafana-service.yaml   # Service Grafana
│   └── grafana-datasources.yaml # Configuration des sources de données Grafana
├── Dockerfile            # Configuration de l'image Docker pour l'application Flask
├── main.tf              # Configuration Terraform principale
├── variables.tf         # Variables Terraform
└── README.md           # Ce fichier
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

## Avantages du Service Mesh

L'utilisation d'un service mesh (comme Istio) apporte plusieurs avantages :

- **Observabilité** : Collecte de métriques, logs et traces pour une meilleure visibilité sur le comportement de l'application.
- **Gestion du trafic** : Routage avancé, load balancing, et gestion des erreurs.
- **Sécurité** : Chiffrement du trafic, authentification et autorisation.
- **Resilience** : Gestion des timeouts, retries, et circuit breakers.

## Observation et Debugging

### Accès à Grafana

1. Exposez le service Grafana :

   ```bash
   kubectl port-forward -n istio-system svc/grafana 3000:3000 --kubeconfig ~/.kube/config
   ```

2. Accédez à Grafana à l'adresse `http://localhost:3000` avec les identifiants par défaut (admin/admin).

3. Importez le dashboard Istio Mesh (ID: 7630) pour visualiser les métriques de votre application.

### Utilisation de Prometheus

1. Exposez le service Prometheus :

   ```bash
   kubectl port-forward -n istio-system svc/prometheus 9090:9090 --kubeconfig ~/.kube/config
   ```

2. Accédez à Prometheus à l'adresse `http://localhost:9090` pour interroger les métriques.

### Debugging

- Utilisez les logs des pods pour identifier les problèmes :

  ```bash
  kubectl logs -l app=flask-app
  kubectl logs -l app=postgres
  ```

- Vérifiez les ressources Istio :

  ```bash
  kubectl get gateway,virtualservice
  ```

## Sécurité

### Certificats TLS

Les fichiers suivants sont des certificats TLS sensibles et ne doivent **JAMAIS** être poussés sur un dépôt Git :

- `ca.crt` : Certificat de l'autorité de certification
- `client.crt` : Certificat client
- `client.key` : Clé privée du client

Ces fichiers sont utilisés pour :

- L'authentification mutuelle entre le client et le serveur Kubernetes
- Le chiffrement des communications
- La sécurisation des accès au cluster

**Important** : Ajoutez ces fichiers à votre `.gitignore` :

```gitignore
*.crt
*.key
```
