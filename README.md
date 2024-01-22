This repo contains all the required Infrastructure as IAC in Terraform to host a web application in AWS EKS. It also has the manifests files to deploy the app in to AWS EKS and the complete CICD GitLab piplein to provision the Infra until deploy the app into EKS with app-build and test stages in between. 

The terraform stage is set to run only on the main branch. This ensures that the Terraform infrastructure changes are applied only when merging changes into the main or master branch.

The build and test stages are set to run only on merge requests. This ensures that the build and test stages are executed for pull requests.

The deploy stage is set to run only on the main branch. This ensures that the Kubernetes deployment is applied only after changes are merged into the main or master branch.