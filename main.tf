terraform {
  required_version = ">= 1.0.0"
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
  depends_on = [null_resource.configure_kubectl]
}