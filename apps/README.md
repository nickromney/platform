# Apps

This directory contains the source applications that feed the local platform demos.

## Layout

- [`subnet-calculator/`](subnet-calculator/) contains the subnet calculator app and its local compose-based workflows.
- [`sentiment-llm/`](sentiment-llm/) contains the sentiment demo and its local compose-based workflows.

## Relationship To The Kubernetes Demos

The kind stack uses Kubernetes manifests under [`terraform/kubernetes/apps/`](../terraform/kubernetes/apps/), but those manifests are there to deploy the demos into the cluster.

This repo-root `apps/` directory is the better place to start if you want to understand the application source trees themselves.

For the higher-level Kubernetes-side walkthrough, including Mermaid diagrams of the sample app flows, see [sample-apps.md](../kubernetes/kind/docs/sample-apps.md).
