# Production environment (Aryan)

Production runs on one AWS EC2 instance in Sydney (`ap-southeast-2`) with Docker Compose:

```
Internet -> :80 nginx -> app (FastAPI :8000) -> db (PostgreSQL, named volume)
               |
               +-> JSON access log -> CloudWatch agent -> CloudWatch Logs -> metric filters
EC2 host -> CloudWatch agent (memory, disk, disk I/O) + built-in EC2 metrics (CPU, network)
                                   -> SWE40006-Production dashboard + alarms -> SNS email

GitHub Actions (after all tests pass) -> OIDC role -> AWS SSM Run Command -> deploy.sh on the server
```

## Files

| File | What it does |
|---|---|
| `ec2-user-data.sh` | Pasted into EC2 "User data" at launch. Installs Docker, the CloudWatch agent, swap, log folders and log rotation |
| `docker-compose.prod.yml` | The production stack: nginx + app + postgres |
| `nginx/nginx.conf` | Reverse proxy and JSON access log (includes `request_time` for latency) |
| `deploy.sh` | Runs on the server. Pulls the latest commit, rebuilds, checks `/health`, and rolls back automatically if the check fails |
| `ssm-deploy.sh` | Runs in GitHub Actions. Tells AWS SSM to run `deploy.sh` on the server, then streams the result back into the pipeline log |
| `github-actions-deploy-job.yml` | The deploy job to add to the main pipeline YAML (reference only) |
| `aws/github-oidc-trust-policy.json` | Lets only this repo's `main` branch assume the deploy role (no AWS keys stored in GitHub) |
| `aws/github-deploy-permissions.json` | The deploy role can only run commands on the production instance, nothing else |
| `cloudwatch/cloudwatch-agent.json` | CloudWatch agent config: metrics plus the log files it ships |
| `cloudwatch/setup-cloudwatch.sh` | Run once in CloudShell. Creates metric filters, alarms, SNS email alerts and the dashboard |
| `load-test.sh` | Generates traffic so the dashboard has real data |

## Server details

- Instance: `swe40006-prod`, Ubuntu 24.04, t3.micro, 20 GiB gp3, Elastic IP
- Security group `swe40006-prod-sg`: only **HTTP 80** inbound. No SSH port is open; admin access is through AWS Systems Manager Session Manager
- IAM role `swe40006-prod-ec2-role`: `CloudWatchAgentServerPolicy` + `AmazonSSMManagedInstanceCore`
- Code lives in `/opt/swe40006/app`, logs in `/var/log/swe40006/`
- The server pulls code from GitHub with a read-only deploy key
- DB password is in `deploy/production/.env` on the server only. It's created by `deploy.sh` and never committed

## Common commands (on the server, as `ubuntu`: `sudo -iu ubuntu`)

```bash
bash /opt/swe40006/app/deploy/production/deploy.sh          # deploy latest main
cd /opt/swe40006/app/deploy/production
docker compose -f docker-compose.prod.yml ps                 # container status
docker compose -f docker-compose.prod.yml logs --tail 50 app # app logs
tail -f /var/log/swe40006/nginx/access.json.log              # live requests
tail -n 30 /var/log/swe40006/deploy.log                      # deploy history
sudo systemctl status amazon-cloudwatch-agent                # monitoring agent
```
