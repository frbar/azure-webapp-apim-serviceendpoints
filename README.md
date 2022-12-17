# Purpose

This repository contains a Bicep template to create:
- an APIM Consumption and simple API / API operations, to return caller IP
- 1 VNET, 4 subnets, 1 NAT Gateway with different service endpoint configuration (`Microsoft.Web` or none)
- 4 webapps in 4 app service plans with VNET integration and different "route all" configurations

There is also a simple webapp, where endpoint `/api/ping` will trigger a call to APIM to get webapp outbound IP.

The powershell intructions below will:
- deploy the infrastructure, 
- build and deploy the 4 webapps, 
- call the `ping` endpoint on each one, to compare with NAT Gateway IP.

# Deploy the infrastructure

```powershell
az login

$subscription = "My Subscription"
az account set --subscription $subscription

$rgName = "frbar-apim-natgw-2"
$envName = "fb200"
$location = "West Europe"

az group create --name $rgName --location $location

# Deploy infrastructure
az deployment group create --resource-group $rgName `
                           --template-file infra.bicep `
                           --mode complete `
                           --parameters envName=$envName publisherName=$envName publisherEmail="admin@example.com"

# Build webapp
dotnet publish .\api\ -r linux-x64 --self-contained -o publish
Compress-Archive publish\* publish.zip -Force

# Deploy webapp (4 times)
(0..3) | %{ az webapp deployment source config-zip --src .\publish.zip -n "$($envName)-app-$($_)" -g $rgName }

# Test
function test-ips(){
    $natGwIp = az network public-ip list -g $rgName --query [0].ipAddress -otsv
    echo "NAT Gateway IP = $natGwIp"

    (0..3) | %{ (curl "https://$($envName)-app-$($_).azurewebsites.net/api/ping" -UseBasicParsing).Content }    
}
test-ips

echo "Done!"

```

# Tear down

```powershell
az group delete --name $rgName
```