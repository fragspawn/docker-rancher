# k3s Rancher with Backup/Restore

This workspace provides scripts to deploy Rancher on a k3s cluster, expose the Rancher UI through Traefik on host port 7010 (mapped to port 443 in k3s), export Rancher configuration into a local `backup` folder, and restore from that backup during deployment.

## Files

- `scripts/deploy_rancher.sh`: installs cert-manager and Rancher with Traefik ingress enabled and restores config from `backup/latest` when available.
- `scripts/backup_rancher_config.sh`: exports Rancher-related Kubernetes objects to `backup/export-<timestamp>` and updates `backup/latest` symlink.
- `scripts/restore_rancher_config.sh`: reapplies backup manifests from `backup/latest` (or a specified backup folder).
- `k8s/rancher-values.yaml`: Rancher Helm values (`ingress.enabled=true`, ingress class `traefik`, and `tls=external`).
- `k8s/rancher-ui-lb.yaml`: Legacy direct service exposure manifest (not used by current Traefik ingress flow).

## Prerequisites

- Running k3s cluster
- `kubectl` configured for your k3s cluster
- `helm`
- `jq`

## Usage

### Docker Compose workflow

1. Start k3s and run Rancher deployment:

```bash
export RANCHER_BOOTSTRAP_PASSWORD=adminadmin
export SERVER_URL=https://localhost:7010
docker compose up -d k3s
docker compose run --rm rancher-deploy
```

2. Run a short-lived restore container (optional/manual):

```bash
docker compose --profile ops run --rm rancher-restore
```

3. Run a short-lived backup container:

```bash
docker compose --profile ops run --rm rancher-backup
```

4. Access Rancher UI:

```bash
https://localhost:7010
```

The compose file mounts the local workspace into each job container, so backups are written to `./backup` on your host.

### Script workflow

1. Deploy Rancher and expose UI through Traefik on host port 7010:

```bash
export RANCHER_BOOTSTRAP_PASSWORD=adminadmin
export SERVER_URL=https://localhost:7010
./scripts/deploy_rancher.sh
```

2. Export Rancher configuration to local backup folder:

```bash
./scripts/backup_rancher_config.sh
```

3. Re-deploy with automatic restore from backup:

```bash
./scripts/deploy_rancher.sh
```

The deploy script checks `backup/latest`. If backup files exist, it runs restore automatically.

## Notes

- Rancher UI endpoint with this compose setup: `https://localhost:7010`
- `RANCHER_BOOTSTRAP_PASSWORD` is passed from the deploy container to Helm as Rancher's `bootstrapPassword`.
- `SERVER_URL` is passed from the deploy container to the Rancher `server-url` setting after deployment.
- To skip restore on deploy:

```bash
RESTORE_ON_DEPLOY=false ./scripts/deploy_rancher.sh
```
