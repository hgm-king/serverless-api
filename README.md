# Serverless API

#### A simple serverless API, running in ECS that is accessed through API Gateway

The API is a simple `hello_world` in nodeJS. API Gateway passes requests through to a Load Balancer. This Load Balancer automatically manages a pool of ECS tasks that service the requests. The dockerized code resides in an ECR repo which the tasks pull from.

## Quickstart
1. Pull down project
1. `cd terraform` and `terraform init`
1. `terraform apply`
1. Find your ECR repo in AWS and follow the instructions for `Push commands for code_repository`
1. Make sure to `cd ..` back into the root before following push commands
1. Find API Gateway and deploy the staged API
1. Use the API URL to curl `/hello` (mine looks like `curl https://igxotx43h1.execute-api.us-east-2.amazonaws.com/v1/api/hello`)

![Arch Diagram](./resources/serverless-api.png)

## Notes
- To redeploy the code, you must push to the ECR repo. Then you must stop the required ECS task in the console. The next task will spin up automatically with the newest version.

- To update API Gateway info, you need to use the API Gateway console to redeploy the staged API config.

- ECS is not necessarily cheap so make sure not to use too many resources!