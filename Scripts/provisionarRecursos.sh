#!/bin/bash

# Função para verificar se um recurso já existe
resource_exists() {
  local resourceType=$1
  local resourceName=$2
  az $resourceType show --name $resourceName --resource-group $resourceGroupName &>/dev/null
}

# Função para verificar se uma storage account existe (ignorando sufixo)
storage_account_exists() {
  local storageAccountPrefix=$1
  az storage account list --resource-group $resourceGroupName --query "[?starts_with(name, '$storageAccountPrefix')].name" --output tsv | grep -q "$storageAccountPrefix"
}

# Função para verificar se um Databricks Workspace existe
databricks_workspace_exists() {
  local workspaceName=$1
  az databricks workspace list --resource-group $resourceGroupName --query "[?name=='$workspaceName']" --output tsv | grep -q "$workspaceName"
}

# Função para verificar se um container existe na storage account
container_exists() {
  local containerName=$1
  local storageAccountName=$2
  az storage container show --name $containerName --account-name $storageAccountName --auth-mode login &>/dev/null
}

# Função para abortar em caso de falha e limpar recursos
abort_on_failure() {
  echo "Erro ao criar $1."
  read -p "Deseja limpar todos os recursos criados? (s/n): " confirm
  if [[ $confirm == "s" ]]; then
    clean_up_resources
  else
    echo "Recursos mantidos."
  fi
  exit 1
}

# Função para limpar recursos
clean_up_resources() {
  echo "Limpando recursos criados..."
  az group delete --name $resourceGroupName --yes --verbose
  echo "Recursos removidos. Saindo..."
}

# Definir a assinatura e a localização padrão
subscriptionId="0448ce1f-bab4-4d30-bed8-ce1615fd1b5e"
location="eastus"
az account set --subscription $subscriptionId

# Solicitar informações ao usuário
echo "Bem-vindo ao processo de configuração interativo do Azure!"
read -p "Digite o nome do cliente: " clientName

# Nomear os recursos de acordo com as convenções
resourceGroupName="rg-${clientName}"
storageAccountPrefix="st${clientName}"
dataFactoryName="adf-${clientName}"
synapseWorkspaceName="synapse-${clientName}"
sqlAdminLogin="sqladmin-${clientName}"
read -s -p "Digite a senha do administrador SQL: " sqlAdminPassword
echo

# Mostrar ao usuário como os recursos serão nomeados
echo "Os recursos serão nomeados da seguinte forma:"
echo "Grupo de Recursos: $resourceGroupName"
echo "Conta de Armazenamento (prefixo): $storageAccountPrefix"
echo "Data Factory: $dataFactoryName"
echo "Synapse Workspace: $synapseWorkspaceName"
echo "Usuário SQL: $sqlAdminLogin"

# Confirmar com o usuário
read -p "Deseja continuar com esses nomes? (s/n): " confirm
if [[ $confirm != "s" ]]; then
  echo "Processo cancelado."
  exit 1
fi

# Verificar e criar Grupo de Recursos
echo "Verificando grupo de recursos..."
if resource_exists "group" $resourceGroupName; then
  echo "Grupo de recursos já existe."
else
  echo "Criando o grupo de recursos..."
  az group create --name $resourceGroupName --location $location || abort_on_failure "grupo de recursos"
fi

# Verificar e criar Conta de Armazenamento com Azure Data Lake Storage Gen 2
echo "Verificando conta de armazenamento..."
if storage_account_exists $storageAccountPrefix; then
  echo "Conta de armazenamento já existe."
  storageAccountName=$(az storage account list --resource-group $resourceGroupName --query "[?starts_with(name, '$storageAccountPrefix')].name" --output tsv)
else
  echo "Criando a conta de armazenamento..."
  az storage account create --name $storageAccountPrefix --resource-group $resourceGroupName --location $location --sku Standard_LRS --kind StorageV2 --hns true || abort_on_failure "conta de armazenamento"
  storageAccountName=$storageAccountPrefix
fi

# Verificar e criar Containers na Conta de Armazenamento com autenticação Microsoft Entra
create_container_if_not_exists() {
  local containerName=$1
  echo "Verificando container $containerName..."
  if container_exists $containerName $storageAccountName; then
    echo "Container $containerName já existe."
  else
    echo "Criando container $containerName..."
    az storage container create --name $containerName --account-name $storageAccountName --auth-mode login || abort_on_failure "container $containerName"
  fi
}

create_container_if_not_exists "bronze"
create_container_if_not_exists "silver"
create_container_if_not_exists "gold"
create_container_if_not_exists "scripts"

# Verificar e criar Azure Data Factory
echo "Verificando Azure Data Factory..."
if resource_exists "datafactory" $dataFactoryName; then
  echo "Azure Data Factory já existe."
else
  echo "Criando o Azure Data Factory..."
  az datafactory create --resource-group $resourceGroupName --name $dataFactoryName --location $location || abort_on_failure "Azure Data Factory"
fi

# Verificar e criar Synapse Workspace com pool SQL built-in
echo "Verificando Synapse Workspace..."
if resource_exists "synapse workspace" $synapseWorkspaceName; then
  echo "Synapse Workspace já existe."
else
  echo "Criando o Synapse Workspace..."
  az synapse workspace create --name $synapseWorkspaceName --resource-group $resourceGroupName --location $location --storage-account $storageAccountName --file-system default --sql-admin-login-user $sqlAdminLogin --sql-admin-login-password $sqlAdminPassword || abort_on_failure "Synapse Workspace"
fi

# Função para adicionar tags aos recursos
add_tags_if_not_exists() {
  local resourceId=$1
  local existingTags=$(az resource show --ids $resourceId --query "tags" -o tsv)
  
  if [[ -z "$existingTags" || $existingTags != *"Client"* ]]; then
    echo "Adicionando tag ao recurso $resourceId..."
    az resource tag --tags Client=$clientName --ids $resourceId || abort_on_failure "tag no recurso $resourceId"
  else
    echo "Tag já existe para o recurso $resourceId."
  fi
}

# Adicionar tags aos recursos
echo "Adicionando tags aos recursos..."
resources=$(az resource list --resource-group $resourceGroupName --query "[].id" --output tsv)
for resource in $resources; do
  add_tags_if_not_exists $resource
done

echo "Criação de recursos concluída."
