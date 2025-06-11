terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "k3d-mycluster"
}

provider "kubectl" {
  config_path    = "~/.kube/config"
  config_context = "k3d-mycluster"
}

# Vérifier si Docker est installé
resource "null_resource" "check_docker" {
  provisioner "local-exec" {
    command = "which docker > /dev/null || (echo \"Docker n'est pas installé. Veuillez l'installer d'abord.\" && exit 1)"
  }
}

# Vérifier si K3d est installé
resource "null_resource" "check_k3d" {
  provisioner "local-exec" {
    command = "which k3d > /dev/null || (echo \"K3d n'est pas installé. Installation en cours...\" && exit 1)"
  }
}

# Installe K3d si nécessaire
resource "null_resource" "install_k3d" {
  provisioner "local-exec" {
    command = "curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
  }
  depends_on = [null_resource.check_k3d]
}

# --- Création du cluster k3d ---
resource "null_resource" "create_cluster" {
  provisioner "local-exec" {
    command = <<-EOT
      k3d cluster create mycluster \
        --servers 1 \
        --agents 3 \
        --port 80:80@loadbalancer \
        --port 443:443@loadbalancer \
        --k3s-arg '--disable=traefik@server:0' \
        --k3s-arg '--disable=servicelb@server:0' \
        --k3s-arg '--tls-san=0.0.0.0@server:0'
    EOT
  }
}

# --- Configuration kubectl ---
resource "null_resource" "configure_kubectl" {
  provisioner "local-exec" {
    command = <<-EOT
      k3d kubeconfig get mycluster > ~/.kube/config
      echo "Waiting for cluster to be ready..."
      for i in {1..30}; do
        if kubectl get nodes > /dev/null 2>&1; then
          echo "Cluster is ready!"
          exit 0
        fi
        echo "Waiting for cluster to be ready... (attempt $i/30)"
        sleep 5
      done
      echo "Cluster not ready after timeout" && exit 1
    EOT
  }
  depends_on = [null_resource.create_cluster]
}

# --- Installation d'Istio ---
resource "null_resource" "install_istio" {
  provisioner "local-exec" {
    command = <<-EOT
      curl -L https://istio.io/downloadIstio | sh -
      cd istio-*
      export PATH=$PWD/bin:$PATH
      istioctl install --set profile=demo -y
    EOT
  }
  depends_on = [null_resource.configure_kubectl]
}

# --- Vérification de l'installation d'Istio ---
resource "null_resource" "wait_istio_crds" {
  provisioner "local-exec" {
    command = <<EOT
      echo "Waiting for Istio installation to complete..."
      for i in {1..60}; do
        if kubectl get pods -n istio-system --kubeconfig ~/.kube/config | grep -q "Running"; then
          echo "Istio pods are running, waiting for CRDs..."
          for j in {1..30}; do
            if kubectl get crd virtualservices.networking.istio.io --kubeconfig ~/.kube/config >/dev/null 2>&1 && \
               kubectl get crd destinationrules.networking.istio.io --kubeconfig ~/.kube/config >/dev/null 2>&1; then
              echo "Istio CRDs are ready!"
              exit 0
            fi
            echo "Waiting for Istio CRDs... (attempt $j/30)"
            sleep 5
          done
        fi
        echo "Waiting for Istio pods to be ready... (attempt $i/60)"
        sleep 5
      done
      echo "Istio installation or CRDs not ready after timeout" && exit 1
    EOT
  }
  depends_on = [null_resource.install_istio]
}

# --- Installation des composants d'observabilité ---
resource "null_resource" "install_observability" {
  provisioner "local-exec" {
    command = <<-EOT
      cd istio-*
      export PATH=$PWD/bin:$PATH
      kubectl apply -f samples/addons/prometheus.yaml --kubeconfig ~/.kube/config 
      kubectl apply -f samples/addons/grafana.yaml --kubeconfig ~/.kube/config
      kubectl apply -f samples/addons/kiali.yaml --kubeconfig ~/.kube/config
    EOT
  }
  depends_on = [null_resource.wait_istio_crds]
}

# --- Déploiement de PostgreSQL ---
resource "kubectl_manifest" "postgres_configmap" {
  yaml_body  = file("${path.module}/manifests/postgres-configmap.yaml")
  depends_on = [null_resource.wait_istio_crds]
}

resource "kubectl_manifest" "postgres_pvc" {
  yaml_body  = file("${path.module}/manifests/postgres-pvc.yaml")
  depends_on = [kubectl_manifest.postgres_configmap]
}

resource "kubectl_manifest" "postgres_deployment" {
  yaml_body  = file("${path.module}/manifests/postgres-deployment.yaml")
  depends_on = [kubectl_manifest.postgres_pvc]
}

resource "kubectl_manifest" "postgres_service" {
  yaml_body  = file("${path.module}/manifests/postgres-service.yaml")
  depends_on = [kubectl_manifest.postgres_deployment]
}

# --- Build et import de l'image Docker ---
resource "null_resource" "build_docker_image" {
  provisioner "local-exec" {
    command = "docker build -t flask-app:latest ."
  }
  depends_on = [null_resource.wait_istio_crds]
}

resource "null_resource" "import_docker_image" {
  provisioner "local-exec" {
    command = "k3d image import flask-app:latest -c mycluster"
  }
  depends_on = [null_resource.build_docker_image]
}

# --- Déploiement de l'application Flask ---
resource "kubectl_manifest" "app_deployment" {
  yaml_body  = file("${path.module}/manifests/app-deployment.yaml")
  depends_on = [null_resource.import_docker_image, kubectl_manifest.postgres_service]
}

resource "kubectl_manifest" "app_service" {
  yaml_body  = file("${path.module}/manifests/app-service.yaml")
  depends_on = [kubectl_manifest.app_deployment]
}

# --- Configuration Istio pour l'application ---
resource "kubectl_manifest" "app_gateway" {
  yaml_body  = file("${path.module}/manifests/app-gateway.yaml")
  depends_on = [kubectl_manifest.app_service]
}

resource "kubectl_manifest" "app_virtualservice" {
  yaml_body  = file("${path.module}/manifests/app-virtualservice.yaml")
  depends_on = [kubectl_manifest.app_gateway]
}

# Configurer Grafana
resource "kubectl_manifest" "grafana_config" {
  yaml_body  = file("${path.module}/manifests/grafana-datasources.yaml")
  depends_on = [null_resource.install_observability]
}

# Configurer les dashboards Grafana
resource "kubectl_manifest" "grafana_dashboards" {
  yaml_body  = <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: istio-system
data:
  istio-mesh-dashboard.json: |-
    {
      "annotations": {
        "list": [
          {
            "builtIn": 1,
            "datasource": "-- Grafana --",
            "enable": true,
            "hide": true,
            "iconColor": "rgba(0, 211, 255, 1)",
            "name": "Annotations & Alerts",
            "type": "dashboard"
          }
        ]
      },
      "editable": true,
      "gnetId": 7630,
      "graphTooltip": 0,
      "id": 1,
      "links": [],
      "panels": [],
      "schemaVersion": 16,
      "style": "dark",
      "tags": [],
      "templating": {
        "list": []
      },
      "time": {
        "from": "now-6h",
        "to": "now"
      },
      "timepicker": {
        "refresh_intervals": [
          "5s",
          "10s",
          "30s",
          "1m",
          "5m",
          "15m",
          "30m",
          "1h",
          "2h",
          "1d"
        ]
      },
      "timezone": "",
      "title": "Istio Mesh Dashboard",
      "uid": "istio-mesh",
      "version": 1
    }
YAML
  depends_on = [kubectl_manifest.grafana_config]
}

# Configurer le service Grafana pour l'accès externe
resource "kubectl_manifest" "grafana_service" {
  yaml_body  = file("${path.module}/manifests/grafana-service.yaml")
  depends_on = [kubectl_manifest.grafana_config]
}

# Activer Istio
resource "null_resource" "enable_istio_injection" {
  provisioner "local-exec" {
    command = "kubectl label namespace default istio-injection=enabled"
  }
  depends_on = [null_resource.install_istio]
}

# Vérifier l'installation
resource "null_resource" "verify_installation_cluster" {
  provisioner "local-exec" {
    command = <<EOT
echo "=== Vérification du cluster k3d ==="
for i in {1..20}; do
  if kubectl get nodes --kubeconfig ~/.kube/config > /dev/null 2>&1; then
    echo "Cluster prêt."
    break
  else
    echo "En attente que l'API Kubernetes soit disponible..."
    sleep 5
  fi
done
kubectl get nodes --kubeconfig ~/.kube/config
kubectl get pods -n kube-system --kubeconfig ~/.kube/config
EOT
  }
  depends_on = [null_resource.install_istio]
}

resource "kubectl_manifest" "istio_system_ns" {
  yaml_body = <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: istio-system
YAML
}
