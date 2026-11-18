terraform {
  required_version = ">= 1.5.0"

  required_providers {
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 2.20"
    }
  }
}

provider "mongodbatlas" {
  # Option 1: Service Account (recommended)
  client_id     = var.mongodb_atlas_client_id
  client_secret = var.mongodb_atlas_client_secret

  # Option 2: Programmatic API key
  public_key  = var.mongodb_atlas_public_key
  private_key = var.mongodb_atlas_private_key
}