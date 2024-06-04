#!/bin/bash

# Função para abortar em caso de falha
abort_on_failure() {
  echo "Erro ao configurar notificações e budget para $1. Saindo..."
  exit 1
}

# Definir a assinatura e a localização padrão
subscriptionId="0448ce1f-bab4-4d30-bed8-ce1615fd1b5e"
location="eastus"
az account set --subscription $subscriptionId

# Solicitar informações ao usuário
echo "Bem-vindo ao processo de configuração de notificações e budget do Azure!"
read -p "Digite o nome do cliente: " clientName

# Nomear os recursos de acordo com as convenções
resourceGroupName="rg-${clientName}"

# Configurar Budget
echo "Configurando o Budget..."
az consumption budget create --budget-name "monthly-budget" --resource-group $resourceGroupName --amount 20 --time-grain Monthly --start-date $(date +%Y-%m-01) --end-date $(date -d "+1 year" +%Y-%m-01) --notifications '{
  "email": {
    "enabled": true,
    "operator": "GreaterThan",
    "threshold": 90,
    "contactEmails": ["Joel.fernandes@datavizio.com.br"]
  }
}' || abort_on_failure "Budget Mensal"

az consumption budget create --budget-name "daily-budget" --resource-group $resourceGroupName --amount 10 --time-grain Daily --start-date $(date +%Y-%m-01) --end-date $(date -d "+1 year" +%Y-%m-01) --notifications '{
  "email": {
    "enabled": true,
    "operator": "GreaterThan",
    "threshold": 90,
    "contactEmails": ["Joel.fernandes@datavizio.com.br"]
  }
}' || abort_on_failure "Budget Diário"

echo "Configuração de notificações e budget concluída."
