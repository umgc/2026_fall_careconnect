# CareConnect Deployment and Operations Guide

## Current Infrastructure Status

The current infrastructure-as-code implementation is the CloudFormation stack
set in [`cloudformation-fargate/`](../../cloudformation-fargate/README.md).
It defines the network, database, platform, and service layers for the Spring
Boot backend running on Amazon ECS Fargate behind API Gateway.

## Operator References

- [CloudFormation Fargate README](../../cloudformation-fargate/README.md): stack
  order, parameter files, deployment, validation, and teardown.
- [`cloudformation-fargate/templates/`](../../cloudformation-fargate/templates/):
  infrastructure templates.
- [`cloudformation-fargate/parameters/`](../../cloudformation-fargate/parameters/):
  environment parameter examples.
- [`backend/core/pg_docker/`](../../backend/core/pg_docker/): local PostgreSQL
  startup for development.

## Current Constraints

- The CloudFormation stack set has been validated for a temporary development
  environment; it is not a production approval or a HIPAA compliance claim.
- AWS secrets must be provided through the documented parameter/secret process;
  do not commit credentials.
- Temporary application environments must be torn down when not in use.

The Fall 2026 controlled Deployment and Operations Guide will expand this
transition document as the project documentation is completed and approved.
