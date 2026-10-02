terraform {
  cloud {
    organization = "davtro02"
    workspaces { name = "github-actions-terraform" }
  }
  required_providers {
    github = { source = "integrations/github", version = "~> 6.0" }
  }
}

provider "github" {
  token = var.github_token
}

variable "github_token" {
  type      = string
  sensitive = true
}

variable "ghcr_pat" {
  type      = string
  sensitive = true
}

resource "github_repository" "repo" {
  name        = "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01"
  description = "Davtro Apartments - platforma wynajmu krotkoterminowego (K8s/ArgoCD/Kafka/Redis/Vault)"
  visibility  = "private"
}

resource "github_actions_secret" "ghcr_pat" {
  repository      = github_repository.repo.name
  secret_name     = "GHCR_PAT"
  plaintext_value = var.ghcr_pat
}
