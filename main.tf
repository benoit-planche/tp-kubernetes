terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

provider "kubectl" {
  config_path = "~/.kube/config"
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

# Créer le cluster k3d
resource "null_resource" "create_cluster" {
  provisioner "local-exec" {
    command = <<-EOT
      k3d cluster create mycluster \
        --servers 1 \
        --agents ${var.worker_count} \
        --port 80:80@loadbalancer \
        --port 443:443@loadbalancer \
        --k3s-arg '--disable=traefik@server:0' \
        --k3s-arg '--disable=servicelb@server:0'
    EOT
  }
  depends_on = [null_resource.install_k3d]
}

# Configurer kubectl
resource "null_resource" "configure_kubectl" {
  provisioner "local-exec" {
    command = "k3d kubeconfig get mycluster > ~/.kube/config"
  }
  depends_on = [null_resource.create_cluster]
}

# Installer la Gateway API
resource "null_resource" "install_gateway_api" {
  provisioner "local-exec" {
    command = "kubectl --kubeconfig ~/.kube/config apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v0.6.1/standard-install.yaml"
  }
  depends_on = [null_resource.configure_kubectl]
}

# Installer Istio
resource "null_resource" "install_istio" {
  provisioner "local-exec" {
    command = <<-EOT
      curl -L https://istio.io/downloadIstio | sh -
      cd istio-*
      export PATH=$PWD/bin:$PATH
      istioctl install --set profile=demo -y
    EOT
  }
  depends_on = [null_resource.install_gateway_api]
}

# Installer les composants d'observabilité
resource "null_resource" "install_observability" {
  provisioner "local-exec" {
    command = <<-EOT
      cd istio-*
      export PATH=$PWD/bin:$PATH
      kubectl apply -f samples/addons/prometheus.yaml --kubeconfig ~/.kube/config
      kubectl apply -f samples/addons/grafana.yaml --kubeconfig ~/.kube/config
      kubectl apply -f samples/addons/kiali.yaml --kubeconfig ~/.kube/config
      kubectl apply -f samples/addons/jaeger.yaml --kubeconfig ~/.kube/config
    EOT
  }
  depends_on = [null_resource.install_istio]
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
    command = "kubectl label namespace default istio-injection=enabled --kubeconfig ~/.kube/config"
  }
  depends_on = [null_resource.install_istio]
}

# Deployer virtualService et destinationRule
resource "kubectl_manifest" "virtual_service" {
  yaml_body  = <<YAML
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: my-app
spec:
  hosts:
  - "*"
  gateways:
  - my-gateway
  http:
  - match:
    - uri:
        prefix: "/v1"
    route:
    - destination:
        host: my-service
        subset: v1
  - match:
    - uri:
        prefix: "/v2"
    route:
    - destination:
        host: my-service
        subset: v2
YAML
  depends_on = [null_resource.enable_istio_injection]
}

resource "kubectl_manifest" "destination_rule" {
  yaml_body  = <<YAML
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: my-service-dr
spec:
  host: my-service
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
    outlierDetection:
      consecutiveErrors: 5
      interval: 10s
      baseEjectionTime: 30s
YAML
  depends_on = [null_resource.enable_istio_injection]
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

# --- Build de l'image Docker ---
resource "null_resource" "build_docker_image" {
  provisioner "local-exec" {
    command = "docker build --no-cache -t flask-app:latest ."
  }
  depends_on = [null_resource.verify_installation_cluster]
}

# --- Import de l'image Docker dans le cluster k3d ---
resource "null_resource" "import_docker_image" {
  provisioner "local-exec" {
    command = "k3d image import flask-app:latest -c mycluster"
  }
  depends_on = [null_resource.build_docker_image]
}

# --- Déploiement PostgreSQL et Application Flask via kubectl_manifest ---
resource "kubectl_manifest" "postgres_configmap" {
  yaml_body  = file("${path.module}/manifests/postgres-configmap.yaml")
  depends_on = [null_resource.verify_installation_cluster]
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

resource "kubectl_manifest" "app_deployment" {
  yaml_body  = file("${path.module}/manifests/app-deployment.yaml")
  depends_on = [null_resource.import_docker_image, kubectl_manifest.postgres_service]
}

resource "kubectl_manifest" "app_service" {
  yaml_body  = file("${path.module}/manifests/app-service.yaml")
  depends_on = [kubectl_manifest.app_deployment]
}

# --- Configuration Istio pour l'application Flask ---
resource "kubectl_manifest" "app_gateway" {
  yaml_body  = <<YAML
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: flask-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
YAML
  depends_on = [kubectl_manifest.app_service]
}

resource "kubectl_manifest" "app_virtualservice" {
  yaml_body  = <<YAML
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: flask-vs
spec:
  hosts:
  - "*"
  gateways:
  - flask-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: flask-app
        port:
          number: 80
YAML
  depends_on = [kubectl_manifest.app_gateway]
}

# --- Ancien déploiement à commenter ---
# resource "null_resource" "deploy_app" {
#   provisioner "local-exec" {
#     command = "kubectl apply -f ./app/deploiement.yaml --kubeconfig ~/.kube/config"
#   }
#   depends_on = [null_resource.verify_installation_cluster]
# }

# Deployer observabilité
resource "null_resource" "deploy_observability" {
  provisioner "local-exec" {
    command = "kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.26/samples/addons/grafana.yaml --kubeconfig ~/.kube/config"
  }
  depends_on = [null_resource.verify_installation_cluster]
}
