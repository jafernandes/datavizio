#!/bin/bash

# Função para abortar em caso de falha
abort_on_failure() {
  echo "Erro ao configurar permissões para $1. Saindo..."
  exit 1
}

# Definir a assinatura e a localização padrão
subscriptionId="0448ce1f-bab4-4d30-bed8-ce1615fd1b5e"
location="eastus"
az account set --subscription $subscriptionId

# Solicitar informações ao usuário
echo "Bem-vindo ao processo de configuração de permissões do Azure!"
read -p "Digite o nome do cliente: " clientName

# Nomear os recursos de acordo com as convenções
resourceGroupName="rg-${clientName}"
dataFactoryName="adf-${clientName}"
synapseWorkspaceName="synapse-${clientName}"

# Obter IDs dos recursos
dataFactoryId=$(az datafactory show --name $dataFactoryName --resource-group $resourceGroupName --query id --output tsv)
synapseWorkspaceId=$(az synapse workspace show --name $synapseWorkspaceName --resource-group $resourceGroupName --query id --output tsv)

# Obter o ID do usuário logado
userId=$(az ad signed-in-user show --query id --output tsv)

# Conceder permissões ao usuário no Data Factory
echo "Concedendo permissões no Data Factory..."
az role assignment create --assignee $userId --role "Contributor" --scope $dataFactoryId || abort_on_failure "Data Factory"

# Conceder permissões ao usuário no Synapse Workspace
echo "Concedendo permissões no Synapse Workspace..."
az role assignment create --assignee $userId --role "Contributor" --scope $synapseWorkspaceId || abort_on_failure "Synapse Workspace"

echo "Configuração de permissões concluída."
