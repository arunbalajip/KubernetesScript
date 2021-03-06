param(
  [string]
  [Parameter(Mandatory = $true)]
  $aksresourceGroupName,
  [string]
  [Parameter(Mandatory = $true)]
  $identityName,
  [string]
  [Parameter(Mandatory = $true)]
  $identitySelector,
  [string]
  [Parameter(Mandatory = $true)]
  $aksName,
  [string]
  [Parameter(Mandatory = $true)]
  $keyVaultResourceGroupName,
  [string]
  [Parameter(Mandatory = $true)]
  $keyVaultName 
)

# Get the current subscription
$subscriptionId = (az account show | ConvertFrom-Json).id

# Get aks so we can extract it's Service Princpal later
$aks = az aks show `
  -g $aksresourceGroupName `
  -n $aksName | ConvertFrom-Json

# Create Managed Identity
$identity = az identity create `
  -g $aksresourceGroupName `
  -n $identityName `
  -o json | ConvertFrom-Json

# Assign the Reader role to the Managed Identity
az role assignment create `
  --role "Reader" `
  --assignee $identity.principalId `
  --scope /subscriptions/$subscriptionId/resourcegroups/$keyVaultResourceGroupName

# Assign the Managed Identity Operator role to the AKS Service Principal
az role assignment create `
  --role "Managed Identity Operator" `
  --assignee $aks.servicePrincipalProfile.clientId `
  --scope $identity.id

# Add policy to the Key Vault so the Managed Identity can read secrets
az keyvault set-policy `
  --name $keyVaultName `
  --spn $identity.clientId `
  --secret-permissions get list

# Enable AAD Pod Identity on AKS
kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment-rbac.yaml

# Create the Azure Identity and AzureIdentityBinding yaml on the fly
$k8sAzureIdentityandBinding = @"
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentity
metadata:
  name: $($identityName)
  annotations:
    aadpodidentity.k8s.io/Behavior: namespaced
spec:
  type: 0
  ResourceID: $($identity.id)
  ClientID: $($identity.clientId)
---
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentityBinding
metadata:
  name: $($identityName)-identity-binding
  annotations:
    aadpodidentity.k8s.io/Behavior: namespaced
spec:
  AzureIdentity: $($identityName)
  Selector: $($identitySelector)
"@

# Deploy the yamls 
$k8sAzureIdentityandBinding | kubectl apply -n=development -f -
