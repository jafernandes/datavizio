#!/bin/bash

# Função para abortar em caso de falha
abort_on_failure() {
  echo "Erro ao criar $1. Abortando operação e desfazendo todos os recursos."
  clean_up
  exit 1
}

# Função para limpar todos os recursos criados em caso de falha
clean_up() {
  echo "Limpando todos os recursos criados..."
  az group delete --name $resourceGroupName --yes --no-wait
  echo "Recursos limpos."
}

# Definir um trap para limpar recursos em caso de qualquer erro
trap 'abort_on_failure "alguma operação"' ERR

# Solicitar informações ao usuário
echo "Bem-vindo ao processo de configuração interativo do Azure!"
read -p "Digite o nome do cliente: " clientName
read -p "Digite o local (ex: eastus): " location
read -p "Quantos Key Vaults deseja criar? " kvCount

# Nomear os recursos de acordo com as convenções
resourceGroupName="rg-${clientName}"
storageAccountName="st${clientName}$(date +%s)"
dataFactoryName="adf-${clientName}"
synapseWorkspaceName="synapse-${clientName}"
keyVaultNames=()
sqlAdminLogin="sqladmin-${clientName}"
read -s -p "Digite a senha do administrador SQL: " sqlAdminPassword
echo

# Solicitar informações para os Key Vaults
for (( i=1; i<=$kvCount; i++ ))
do
  read -p "Digite o nome do Key Vault #$i: " kvName
  keyVaultNames+=($kvName)
  declare "keyVaultSecrets_$kvName=()"
  read -p "Quantos segredos deseja adicionar no Key Vault $kvName? " secretCount
  for (( j=1; j<=$secretCount; j++ ))
  do
    read -p "Digite o nome do segredo #$j para $kvName: " secretName
    read -s -p "Digite o valor do segredo $secretName: " secretValue
    echo
    declare "keyVaultSecrets_$kvName+=([$secretName]=$secretValue)"
  done
done

# Solicitar informações para configurações de log e orçamento
echo "Configuração de monitoramento de custos e logs"
read -p "Digite o e-mail para notificações: " notificationEmail
read -p "Digite o orçamento máximo mensal (em USD): " monthlyBudget
read -p "Digite o orçamento máximo diário (em USD): " dailyBudget

# Mostrar ao usuário como os recursos serão nomeados
echo "Os recursos serão nomeados da seguinte forma:"
echo "Grupo de Recursos: $resourceGroupName"
echo "Conta de Armazenamento: $storageAccountName"
echo "Data Factory: $dataFactoryName"
echo "Synapse Workspace: $synapseWorkspaceName"
echo "Key Vaults: ${keyVaultNames[@]}"
echo "Usuário SQL: $sqlAdminLogin"

# Confirmar com o usuário
read -p "Deseja continuar com esses nomes? (s/n): " confirm
if [[ $confirm != "s" ]]; then
  echo "Processo cancelado."
  exit 1
fi

# Criar Grupo de Recursos
echo "Criando o grupo de recursos..."
az group create --name $resourceGroupName --location $location || abort_on_failure "grupo de recursos"

# Criar Conta de Armazenamento com configuração interativa
echo "Criando a conta de armazenamento..."
read -p "Deseja configurar opções específicas para a conta de armazenamento? (s/n): " storageConfig
if [[ $storageConfig == "s" ]]; then
  echo "Escolha a SKU de armazenamento:"
  echo "1) Standard_LRS"
  echo "2) Standard_GRS"
  echo "3) Standard_ZRS"
  read -p "Selecione a opção (1/2/3): " storageSkuChoice
  case $storageSkuChoice in
    1) storageSku="Standard_LRS";;
    2) storageSku="Standard_GRS";;
    3) storageSku="Standard_ZRS";;
    *) echo "Opção inválida, usando Standard_LRS."; storageSku="Standard_LRS";;
  esac
else
  storageSku="Standard_LRS"
fi
az storage account create --name $storageAccountName --resource-group $resourceGroupName --location $location --sku $storageSku || abort_on_failure "conta de armazenamento"

# Criar Containers na Conta de Armazenamento
echo "Criando containers na conta de armazenamento..."
az storage container create --name bronze --account-name $storageAccountName || abort_on_failure "container bronze"
az storage container create --name silver --account-name $storageAccountName || abort_on_failure "container silver"
az storage container create --name gold --account-name $storageAccountName || abort_on_failure "container gold"

# Criar Azure Data Factory com configuração interativa
echo "Criando o Azure Data Factory..."
az datafactory create --resource-group $resourceGroupName --name $dataFactoryName --location $location || abort_on_failure "Azure Data Factory"

# Criar Synapse Workspace com configuração interativa
echo "Criando o Synapse Workspace..."
read -p "Deseja configurar opções específicas para o Synapse Workspace? (s/n): " synapseConfig
if [[ $synapseConfig == "s" ]]; then
  echo "Escolha a SKU do Synapse Workspace:"
  echo "1) DW100c (mais barato)"
  echo "2) DW200c"
  echo "3) DW300c"
  read -p "Selecione a opção (1/2/3): " synapseSkuChoice
  case $synapseSkuChoice in
    1) synapseSku="DW100c";;
    2) synapseSku="DW200c";;
    3) synapseSku="DW300c";;
    *) echo "Opção inválida, usando DW100c."; synapseSku="DW100c";;
  esac
else
  synapseSku="DW100c"
fi
az synapse workspace create --name $synapseWorkspaceName --resource-group $resourceGroupName --location $location --storage-account $storageAccountName --file-system default --sql-admin-login-user $sqlAdminLogin --sql-admin-login-password $sqlAdminPassword --sku-name $synapseSku || abort_on_failure "Synapse Workspace"

# Criar e configurar Key Vaults
for kvName in "${keyVaultNames[@]}"
do
  echo "Criando o Azure Key Vault $kvName..."
  az keyvault create --name $kvName --resource-group $resourceGroupName --location $location || abort_on_failure "Key Vault $kvName"
  echo "Configurando Key Vault $kvName..."
  secrets="keyVaultSecrets_$kvName[@]"
  for secretName in "${!secrets}"
  do
    secretValue=${secrets[$secretName]}
    az keyvault secret set --vault-name $kvName --name $secretName --value $secretValue || abort_on_failure "segredo $secretName no Key Vault $kvName"
  done
done

# Configurar permissões entre os recursos
echo "Configurando permissões entre os recursos..."
dataFactoryId=$(az datafactory show --resource-group $resourceGroupName --name $dataFactoryName --query "id" --output tsv) || abort_on_failure "ID do Azure Data Factory"
synapseWorkspaceId=$(az synapse workspace show --name $synapseWorkspaceName --resource-group $resourceGroupName --query "id" --output tsv) || abort_on_failure "ID do Synapse Workspace"

az role assignment create --assignee $dataFactoryId --role "Contributor" --scope $synapseWorkspaceId || abort_on_failure "atribuição de função para o Data Factory"
az role assignment create --assignee $synapseWorkspaceId --role "Storage Blob Data Contributor" --scope $(az storage account show --name $storageAccountName --resource-group $resourceGroupName --query "id" --output tsv) || abort_on_failure "atribuição de função para o Synapse Workspace"

# Criar grupo de usuários no tenant
echo "Criando grupo de usuários no tenant..."
az ad group create --display-name "$clientName-group" --mail-nickname "$clientName-group" || abort_on_failure "grupo de usuários no tenant"

# Configurar monitoramento de custos e logs
echo "Configurando monitoramento de custos e logs..."
az monitor log-analytics workspace create --resource-group $resourceGroupName --workspace-name "${clientName}-log" --location $location || abort_on_failure "Log Analytics Workspace"
logAnalyticsWorkspaceId=$(az monitor log-analytics workspace show --resource-group $resourceGroupName --workspace-name "${clientName}-log" --query "customerId" --output tsv) || abort_on_failure "ID do Log Analytics Workspace"

# Vincular o Log Analytics Workspace ao Synapse Workspace
az synapse workspace data-connection create --workspace-name $synapseWorkspaceName --name "${clientName}-log-connection" --type AzureDataExplorer --workspace-id $logAnalyticsWorkspaceId --resource-group $resourceGroupName || abort_on_failure "vinculação do Log Analytics Workspace ao Synapse Workspace"

# Configurar alertas de custo
echo "Configurando alertas de custo..."
az monitor budget create --resource-group $resourceGroupName --name "${clientName}-monthly-budget" --category cost --amount $monthlyBudget --time-grain monthly --start-date $(date +%Y-%m-01) --end-date $(date -d "$(date +%Y-%m-01) + 1 year" +%Y-%m-%d) --notifications '[{"enabled":true,"operator":"GreaterThan","threshold":90,"contactEmails":["'$notificationEmail'"]}]' || abort_on_failure "orçamento mensal"
az monitor budget create --resource-group $resourceGroupName --name "${clientName}-daily-budget" --category cost --amount $dailyBudget --time-grain daily --start-date $(date +%Y-%m-01) --end-date $(date -d "$(date +%Y-%m-01) + 1 year" +%Y-%m-%d) --notifications '[{"enabled":true,"operator":"GreaterThan","threshold":90,"contactEmails":["'$notificationEmail'"]}]' || abort_on_failure "orçamento diário"

# Configurar logs e alertas de uso
echo "Configurando logs e alertas de uso..."
az monitor diagnostic-settings create --name "${clientName}-diagnostic-settings" --resource-group $resourceGroupName --resource $(az synapse workspace show --name $synapseWorkspaceName --resource-group $resourceGroupName --query "id" --output tsv) --workspace $logAnalyticsWorkspaceId --logs '[{"category": "SynapseWorkspaceAuditLogs", "enabled": true}]' --metrics '[{"category": "AllMetrics", "enabled": true}]' || abort_on_failure "configuração de logs e alertas"

# Configurar alertas de uso
echo "Configurando alertas de uso..."
az monitor metrics alert create --name "${clientName}-usage-alert" --resource-group $resourceGroupName --scopes $(az synapse workspace show --name $synapseWorkspaceName --resource-group $resourceGroupName --query "id" --output tsv) --condition "avg percentage CPU > 80" --description "Alerta de alta utilização de CPU no Synapse Workspace" --action email $notificationEmail || abort_on_failure "alerta de uso"

# Agendar resumos de utilização
echo "Agendando resumos de utilização..."
az logic workflow create --resource-group $resourceGroupName --name "${clientName}-usage-summary" --location $location --definition '{
  "definition": {
    "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
    "actions": {
      "Send_an_email_(V2)": {
        "inputs": {
          "body": "Resumo de utilização de recursos: ...",
          "subject": "Resumo de Utilização",
          "to": "'$notificationEmail'"
        },
        "runAfter": {},
        "type": "ApiConnection"
      }
    },
    "triggers": {
      "Recurrence": {
        "recurrence": {
          "interval": 12,
          "frequency": "Hour"
        },
        "type": "Recurrence"
      }
    }
  },
  "location": "'$location'"
}' || abort_on_failure "agendamento de resumos de utilização"

echo "Configuração concluída com sucesso!"
