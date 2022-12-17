targetScope = 'resourceGroup'

param envName string

// https://learn.microsoft.com/en-us/azure/api-management/quickstart-bicep?tabs=CLI

@description('The email address of the owner of the service')
@minLength(1)
param publisherEmail string

@description('The name of the owner of the service')
@minLength(1)
param publisherName string

@description('Location for all resources.')
param location string = resourceGroup().location

var configuration = [
  {
    name: 'microsoft.web service endpoint and route all'
    routeAll: true
    serviceEndpoint: true
  }
  {
    name: 'microsoft.web service endpoint, no route all'
    routeAll: false
    serviceEndpoint: true
  }
  {
    name: 'no service endpoint, but route all'
    routeAll: true
    serviceEndpoint: false
  }
  {
    name: 'no service endpoint, no route all'
    routeAll: false
    serviceEndpoint: false
  }
]

//
// APIM
//

resource apiManagementService 'Microsoft.ApiManagement/service@2021-08-01' = {
  name: '${envName}-apim'
  location: location
  sku: {
    name: 'Consumption'
    capacity: 0
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

resource topLevelPolicy 'Microsoft.ApiManagement/service/policies@2021-12-01-preview' = {
  name: 'policy'
  parent: apiManagementService
  properties: {
    format: 'rawxml'
    value: loadTextContent('topLevelPolicy.xml')
  }
}

resource api 'Microsoft.ApiManagement/service/apis@2021-12-01-preview' = {
  name: 'myAPI'
  parent: apiManagementService
  properties: {
    description: ''
    displayName: 'My API'
    path: 'my'
    apiRevision: '1'
    serviceUrl: 'https://foo.bar'
    protocols: [ 'https' ]
    subscriptionRequired: false
    type: 'http'
  }

  resource policy 'policies@2021-01-01-preview' = {
    name: 'policy'
    properties: {
      format: 'rawxml'
      value: loadTextContent('apiPolicy.xml')
    }
  }
}

resource operation 'Microsoft.ApiManagement/service/apis/operations@2022-04-01-preview' = {
  name: 'ping'
  parent: api
  properties: {
    displayName: 'Ping'
    method: 'GET'
    urlTemplate: '/ping'
    templateParameters: []
    request: {
      queryParameters: []
      headers: []
      representations: []
    }
    responses: []
  }
}

//
// VNET
//
// https://learn.microsoft.com/en-us/azure/virtual-network/nat-gateway/quickstart-create-nat-gateway-bicep?tabs=CLI
//

resource publicIp 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: '${envName}-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}

resource natGateway 'Microsoft.Network/natGateways@2021-05-01' = {
  name: '${envName}-natGw'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [
      {
        id: publicIp.id
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: '${envName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '192.168.0.0/16'
      ]
    }
    subnets: [for i in range(0, 4): {
        name: 'subnet-${i}'
        properties: {
          addressPrefix: '192.168.${i}.0/24'
          natGateway: {
            id: natGateway.id
          }
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          serviceEndpoints: configuration[i].serviceEndpoint ? [{
              service: 'Microsoft.Web'
            }] : []
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }]
    enableDdosProtection: false
    enableVmProtection: false
  }
}

//
// Web Apps
//

resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = [for i in range(0, 4): {
  name: '${envName}-plan-${i}'
  location: location
  properties: {
    reserved: true
  }
  sku: {
    name: 'B1'   
  }
  kind: 'linux'
}]

resource appService 'Microsoft.Web/sites@2021-01-01' = [for i in range(0, 4): {
  name: '${envName}-app-${i}'
  location: location
  kind: 'app'
  properties: {
    serverFarmId: appServicePlan[i].id
    virtualNetworkSubnetId: vnet.properties.subnets[i].id
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|6.0'
      appSettings: [
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'CONFIGURATION'
          value: configuration[i].name
        }
        {
          name: 'URL_TO_PING'
          value: '${apiManagementService.properties.gatewayUrl}/my/ping'
        }
      ]
      healthCheckPath: '/health'
      vnetRouteAllEnabled: configuration[i].routeAll      
    }
  }
}]
