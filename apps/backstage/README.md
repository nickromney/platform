# Portal

Portal is the local platform developer portal. It is built on Backstage, but
the user-facing product name is Portal; Kubernetes resources, images, and
service names intentionally keep the internal `backstage` name.

## Local Development

```sh
yarn install
yarn start
```

The app uses oauth2-proxy sign-in in the cluster and the local platform theme in
`packages/app/src/modules/theme.tsx`.

## Review Environments

Review environments should be orchestrated by Gitea Actions and Kubernetes, not
by the Backstage process itself. Portal owns the catalog, templates, and links;
Gitea owns branch events; the workflow owns short-lived Deployment, Service,
HTTPRoute, ReferenceGrant, and CiliumNetworkPolicy resources.

The scaffolded platform-service template includes a review-environment workflow
for non-main branches. It builds and pushes branch-tagged frontend/backend
images, then deploys them into the pre-provisioned `review` application
namespace. Branch deletion removes the matching Deployment, Service,
CiliumNetworkPolicy, HTTPRoute, and ReferenceGrant resources. Review hostnames
are shaped like:

```text
<service>-<branch>.review.127.0.0.1.sslip.io
```

The generated review workflow targets the in-cluster Gitea runner labels
`self-hosted`, `in-cluster`, and `review-env`; the generated image build
workflow uses `self-hosted` and `in-cluster`. In Kind, use a runner-capable
image distribution mode such as `load` or `baked` when exercising branch preview
creation.

Expect a review environment to appear only after a scaffolded service repository
receives a non-`main` branch push in Gitea, the in-cluster Actions runner is
enabled and registered, the `review` namespace has `gitea-registry-creds`, and
the platform gateway certificate covers `*.review.127.0.0.1.sslip.io`. The
default Kind `registry` mode keeps the runner disabled, so it validates the
substrate but will not create branch preview pods.

This deliberately avoids database provisioning. Services that need state should
use in-memory or seeded fixture data in review environments.
