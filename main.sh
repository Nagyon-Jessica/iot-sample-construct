#!/bin/bash

BASE=$1

echo "Azure CLI extensionのインストール"
az extension add --name account
az extension add --name azure-iot

echo "サブスクリプションIDの取得"
SUBSCRIPTION_ID=$(az account subscription list --only-show-errors --query '[0].subscriptionId' -o tsv)

echo "リソースグループの作成"
az group create -n $BASE --location japaneast

echo "IoT Hubの作成"
az iot hub create -n "${BASE}IoTHub" -g $BASE --sku B1

echo "IoTデバイス1の作成"
az iot hub device-identity create -d Device1 -n "${BASE}IoTHub"

echo "IoTデバイス2の作成"
az iot hub device-identity create -d Device2 -n "${BASE}IoTHub"

echo "ストレージアカウントの作成"
az storage account create -n "${BASE}sa" -g $BASE --access-tier Cool --sku Standard_LRS --allow-blob-public-access false

echo "ストレージアカウント接続文字列の取得"
CONNECT_STR=$(az storage account show-connection-string -g $BASE -n "${BASE}sa" --query 'connectionString' -o tsv)

echo "Blobコンテナの作成"
az storage container create -n iot -g $BASE --account-name "${BASE}sa" --auth-mode login

echo "IoT Hubカスタムエンドポイントの作成（コールドパス）"
az iot hub routing-endpoint create -n coldpath -r $BASE -s $SUBSCRIPTION_ID -t azurestoragecontainer --hub-name "${BASE}IoTHub" -c $CONNECT_STR --container iot --encoding json

echo "メッセージルートの作成（コールドパス）"
az iot hub route create --en coldpath --hub-name "${BASE}IoTHub" -n coldpath -s devicemessages -c true -e true

echo "メッセージルートのテスト（コールドパス）"
az iot hub route test --hub-name "${BASE}IoTHub" -n coldpath

echo "App Serviceプランの作成"
az appservice plan create -n IoTAppPlan -g $BASE --is-linux --sku F1

echo "Web Appの作成"
az webapp create -n iotsampleapp -p IoTAppPlan -g $BASE -r "PYTHON|3.7" -u "https://github.com/Nagyon-Jessica/iot_sample"

echo "Web Appの環境変数の設定"
az webapp config appsettings set -n iotsampleapp -g $BASE --settings AZURE_STORAGE_CONNECTION_STRING=$CONNECT_STR

echo "Web Appのログ設定"
az webapp log config -n iotsampleapp -g $BASE --application-logging filesystem --level error --failed-request-tracing true

echo "Service Bus名前空間の作成"
az servicebus namespace create -g $BASE -n "${BASE}SBus" --sku Basic

echo "Service Busキューの作成"
az servicebus queue create -g $BASE -n iotqueue --namespace-name "${BASE}SBus"

echo "Service Busキューの承認規則の作成"
az servicebus queue authorization-rule create -g $BASE --namespace-name "${BASE}SBus" --queue-name iotqueue -n iotqueuerule --rights Send

echo "Service Busキューの接続文字列の取得"
QUEUE_CONNECT_STR=$(az servicebus queue authorization-rule keys list -n iotqueuerule -g $BASE --namespace-name "${BASE}SBus" --queue-name iotqueue --query 'primaryConnectionString' -o tsv)

echo "IoT Hubカスタムエンドポイントの作成（ホットパス）"
az iot hub routing-endpoint create -n hotpath -r $BASE -s $SUBSCRIPTION_ID -t servicebusqueue --hub-name "${BASE}IoTHub" -c $QUEUE_CONNECT_STR

echo "メッセージルートの作成（ホットパス）"
az iot hub route create --en hotpath --hub-name "${BASE}IoTHub" -n hotpath -s devicemessages -c "temperatureAlert='true'" -e true

# TODO
# echo "メッセージルートのテスト（ホットパス）"
# az iot hub route test --hub-name "${BASE}IoTHub" -n hotpath

echo "IoTデバイス1の接続文字列の表示"
az iot hub device-identity connection-string show -d Device1 -n "${BASE}IoTHub"

echo "IoTデバイス2の接続文字列の表示"
az iot hub device-identity connection-string show -d Device2 -n "${BASE}IoTHub"
