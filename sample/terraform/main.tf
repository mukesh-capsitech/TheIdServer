terraform {
  backend "remote" {
    hostname = "app.terraform.io"
    organization = "aguafrommars"

    workspaces {
      name = "TheIdServer"
    }
  }
}

# k8s connection settings are stored in k8s_config variable in Terraform cloud
provider "kubernetes" {
  host = var.k8s_config.host
  token = var.k8s_config.token
  client_certificate = base64decode(var.k8s_config.client_certificate)
  client_key = base64decode(var.k8s_config.client_key)
  cluster_ca_certificate = var.k8s_config.cluster_ca_certificate != null ? base64decode(var.k8s_config.cluster_ca_certificate) : ""
  insecure = var.k8s_config.insecure
}

# k8s connection settings are stored in k8s_config variable in Terraform cloud
provider "helm" {
  kubernetes {
    host = var.k8s_config.host
    token = var.k8s_config.token
    client_certificate = base64decode(var.k8s_config.client_certificate)
    client_key = base64decode(var.k8s_config.client_key)
    cluster_ca_certificate = var.k8s_config.cluster_ca_certificate != null ? base64decode(var.k8s_config.cluster_ca_certificate) : ""
    insecure = var.k8s_config.insecure
  }
}

locals {
  # set node affinity to userpool nodes
  affinity = {
    nodeAffinity = {
      requiredDuringSchedulingIgnoredDuringExecution = {
        nodeSelectorTerms = [{
          matchExpressions = [{
            key = "agentpool"
            operator = "In"
            values = [
              "agentpool"
            ]
          }]
        }]
      }
    }
  }
  # enable wave on config change
  deploymentAnnotations = {
    "wave.pusher.com/update-on-config-change" = "true"
  }
  host = "theidserver.com"
  tls_issuer_name = "letsencrypt"
  tls_issuer_kind = "ClusterIssuer"
  image = {
    repository = "aguacongas/theidserver.duende"
    pullPolicy = "Always"
    tag = "next"
  }
  # SendGrid settings are store in env_settings var in Terraform cloud
  env_settings = var.env_settings
  override_settings = {
    # set node affinity to userpool nodes
    affinity = local.affinity
    seq = {
      # set node affinity to userpool nodes
      affinity = local.affinity
    }
    mysql = {
      image = {
        debug = true
      }      
      primary = {
        # set node affinity to userpool nodes
        affinity = local.affinity
        # user custom master config (max_connections=512)
        # existingConfigmap = "mysql-master-config"
      }
      secondary = {
        # set node affinity to userpool nodes
        affinity = local.affinity
        # user custom secondary config (max_connections=512)
        # existingConfigmap = "mysql-secondary-config"
      }
    }
    redis = {
      master = {
        # set node affinity to userpool nodes
        affinity = local.affinity
      }
      replica = {
        # set node affinity to userpool nodes
        affinity = local.affinity
      }    
    }
    # enable wave on config change
    deploymentAnnotations = local.deploymentAnnotations

    # ingress annotations
    ingress = {
      annotations = {
        "kubernetes.io/ingress.class" = "azure/application-gateway"
        "cert-manager.io/cluster-issuer" = "letsencrypt"
      }
    }
    appSettings = {
      file = {
        # override certificate authentication options
        CertificateAuthenticationOptions = {
          AllowedCertificateTypes = "All"
          ValidateCertificateUse = false
          ValidateValidityPeriod = false
        }
        # override identity server option
        IdentityServerOptions = {
          MutualTls = {
            Enabled = true
            PEMHeader = "ssl-client-cert"
          }
          EnableServerSideSession = true
          ServerSideSessions = {
            UserDisplayNameClaimType = "name"
            RemoveExpiredSessions = true
            ExpiredSessionsTriggerBackchannelLogout = true
            RemoveExpiredSessionsFrequency = "00:10:00"
            RemoveExpiredSessionsBatchSize = 100
          }
          CustomEntriesOfStringArray = {
            token_endpoint_auth_signing_alg_values_supported = [
              "RS256",
              "ES256",
              "ES384",
              "ES512",
              "PS256",
              "PS384",
              "PS512",
              "RS384",
              "RS512"
            ]
            backchannel_authentication_request_signing_alg_values_supported = [
              "RS256",
              "ES256",
              "ES384",
              "ES512",
              "PS256",
              "PS384",
              "PS512",
              "RS384",
              "RS512"
            ]
            acr_values_supported = [
              "idp:local"
            ]
          }
        }
        # override dynamic client registration options
        DynamicClientRegistrationOptions = {
          Protected = false
        }
        # override serilog settings
        Serilog = {
          MinimumLevel = {
            ControlledBy = "$controlSwitch"
            Override = {
              "Microsoft.EntityFrameworkCore" = "Warning"
              System = "Warning"
            }
          }
        }
        # override key management
        IdentityServer = {
          Key = {
            KeyProtectionOptions = {
              KeyProtectionKind = "X509",
              X509CertificatePath = "/usr/local/share/ca-certificates/sk.pfx"
            },
            StorageKind = "EntityFramework",
            Type = "KeysRotation"
            AdditionalSigningKeyType = {
              RS384 = {
                SigningAlgorithm= "RS384"
              },
              RS512 = {
                SigningAlgorithm = "RS512"
              },
              PS256 = {
                SigningAlgorithm = "PS256"
              },
              PS384 = {
                SigningAlgorithm = "PS384"
              },
              PS512 = {
                SigningAlgorithm = "PS512"
              },
              ES256 = {
                SigningAlgorithm = "ES256"
              },
              ES384 = {
                SigningAlgorithm = "ES384"
              },
              ES512 = {
                SigningAlgorithm = "ES512"
              }
            }
          }
        }
        # enable honeycomb
        OpenTelemetryOptions = {
          Trace = {
            ConsoleEnabled = false
            Honeycomb = var.honeycomb
            Instrumentation = {
              Redis = {
                # enable redis telemetry
                ConnectionString = var.redis_connectionstring
              }
            }
          }
        }
      }
    }
  }

  wait = false
}

# Install AAD Pod Identity
resource "helm_release" "aad_pod_identity" {
  name       = "aad-pod-identity"
  repository = "https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts/"
  chart      = "aad-pod-identity"
  namespace  = "ingress-azure"
  create_namespace = true
}

# Install ingress-nginx
resource "helm_release" "azure_ingress" {
  name       = "ingress-azure"
  repository = "https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/"
  chart      = "ingress-azure"
  namespace  = "ingress-azure"
  create_namespace = true

  set {
    name = "appgw.name"
    value = "applicationgateway5f3a"
  }

  set {
    name = "appgw.resourceGroup"
    value = "K8S"
  }
  
  set {
    name = "appgw.subscriptionId"
    value = "7cd7a404-3a0a-41bd-996b-cc3248e8c292"
  }

  set {
    name = "appgw.share"
    value = false
  }

  set {
    name = "armAuth.type"
    value = "aadPodIdentity"
  }

  set {
    name = "armAuth.identityResourceID"
    value = "/subscriptions/7cd7a404-3a0a-41bd-996b-cc3248e8c292/resourcegroups/MC_K8S_AKS5F3A_WESTEUROPE/providers/Microsoft.ManagedIdentity/userAssignedIdentities/appgwContrIdentity5f3a"
  }

  set {
    name = "armAuth.identityClientID"
    value = "904c1efc-5405-459b-99a3-3eb45635a3b0"
  }

  wait = local.wait
}


# Install cert_manager to manage TLS certificates with letsencrypt
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "1.7.2"
  namespace  = "ingress-nginx"
  create_namespace = true

  # uncomment it on 1st deploy

  # set {
  #  name = "installCRDs"
  #  value = true
  #}
  
  wait = local.wait
}

# creates ClusterIssuer
resource "kubernetes_manifest" "cluster_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind = "ClusterIssuer"
    metadata = {
      name = "letsencrypt"
    }
    spec = {
      acme = {
        email = "aguacongas@gamil.com"
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-secrets"
        }
        solvers = [{
          http01 = {
            ingress = {
              class = "nginx"    
            }    
          }
        }]
      }    
    }
  }  
}

# create ns
resource "kubernetes_namespace" "theidserver_namespace" {
  metadata {
    name = "theidserver"
  }  
}

# store mysql master config (max_connections=512)
resource "kubernetes_config_map" "mysql_master_config" {
  metadata {
    name = "mysql-master-config"
    namespace = "theidserver"
  }

  data = {
    "my.cnf" = file("${path.module}/my-master.cnf")
  }
}

# store mysql secondary config (max_connections=512)
resource "kubernetes_config_map" "mysql_scondary_config" {
  metadata {
    name = "mysql-secondary-config"
    namespace = "theidserver"
  }

  data = {
    "my.cnf" = file("${path.module}/my-secondary.cnf")
  }
}

# install TheIdServer cluster with MySql cluster, Redis cluster and Seq server
module "theidserver" {
  source = "Aguafrommars/theidserver/helm"

  host = local.host
  tls_issuer_name = local.tls_issuer_name
  tls_issuer_kind = local.tls_issuer_kind
  image = local.image
  env_settings = local.env_settings
  override_settings = local.override_settings
  replica_count = 3
  create_namespace = true

  wait = local.wait
}


