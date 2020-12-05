# Kluster from scratch

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Lint Code Base](https://github.com/JCMenchi/k8skluster/workflows/Lint%20Code%20Base/badge.svg)

The main purpose of this project is to build a kubernetes cluster from scratch using basic tools.
This is not a production ready cluster, but a test bench to understand how to manage security,
high availability, scalability in a kubernetes cluster.

## Prerequisite

- To be able to deploy a real cluster a minimun number of computer is needed.
The best solution is to use a IaaS solution to provision enough server.
In this project we will use azure, to create compute and network resources.

- Ubuntu server is used as operating system for this cluster

- In order to manage many compute resources, an automation solution is needed.
In this project we will use [ansible](https://docs.ansible.com/).

## Architecture



## Future extension

Use something like [terraform](https://www.terraform.io/) to create computing resources, to be able to use other cloud provider.
