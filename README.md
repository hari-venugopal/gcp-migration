# Amaze GCP Lab

A small hands-on version of the two migrations you'll talk about in the interview:

- **Static assets:** an Angular SPA in Cloud Storage, behind a global load balancer with Cloud CDN and Cloud Armor. Hashed bundles are immutable, and `index.html` is the active pointer, so you can swap and roll back.
- **APIs:** a .NET 8 API on Cloud Run with private Cloud SQL PostgreSQL. The password comes from Secret Manager, and you release with zero-traffic revisions, a canary and rollback.

```
Browser ──HTTP──> Global external ALB  (one IP, Cloud Armor)
                    ├─ /*      → backend bucket (Cloud CDN, edge policy) → GCS bucket
                    └─ /api/*  → serverless NEG → Cloud Run (ingress: LB only)
                                                    └─ Direct VPC egress → Cloud SQL (private IP)
                                                                           Secret Manager → DB password
GitHub Actions ──WIF (no keys)──> Artifact Registry / Cloud Run / GCS / CDN purge
```

## How the lab maps to the real design

| Real design | In this lab | Simplified because |
|---|---|---|
| Akamai in front, Cloud Armor allows only Akamai IPs | Cloud CDN plus a Cloud Armor edge policy | No Akamai account |
| Live bucket private, inside a VPC Service Controls perimeter | Public-read bucket | Perimeters need an organization |
| Staging bucket → deploy function → live bucket, then swap | `releases/<sha>/index.html` copied to `/index.html` | Same idea, one bucket |
| SPA router + Redis serves `index.html` | LB serves `index.html` with `no-cache` | No on-prem router |
| Edge-Cache-Tag purge | `url-maps invalidate-cdn-cache` | Cloud CDN equivalent |
| Two regions, active/hot, Red Button | One region | Cost; see stretch exercise |
| Cloud SQL Enterprise Plus, HA + cross-region replica | Enterprise, `db-f1-micro`, HA optional | Cost |
| Harbor → shared Artifact Registry → per-environment virtual registries | One Artifact Registry repo | One environment |
| Terraform deploys the first revision, the pipeline owns the rest | Same, via `lifecycle.ignore_changes` | — |

## Before you start

You need:
- A GCP project with billing enabled.
- `gcloud`, Terraform 1.6+, Node 20, the .NET 8 SDK, and Docker.
- A GitHub repository for this code.

**Cost:** it's roughly $1–2 a day while it's up, mostly the load balancer forwarding rule and Cloud SQL. Check current GCP pricing, and run `terraform destroy` when you're done.

## Step 1: Run it locally (optional, about 10 minutes)

```bash
docker run -d --name pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=items -p 5432:5432 postgres:16
cd api && dotnet run          # http://localhost:8080/api/health
cd spa && npm install && npx ng serve   # http://localhost:4200, proxies /api to :8080
```

## Step 2: Create the infrastructure

```bash
gcloud auth application-default login
cd infra
cp terraform.tfvars.example terraform.tfvars   # set project_id and github_repo
terraform init
terraform apply                                # about 10–15 min (Cloud SQL is the slow part)
terraform output github_variables
```

Cloud Run starts on Google's `hello` placeholder image. That's on purpose: Terraform owns the infrastructure, and the pipeline owns the image and traffic.

## Step 3: Connect GitHub

1. Push this folder to the repository you named in `github_repo`.
2. In GitHub, go to **Settings › Secrets and variables › Actions › Variables**.
3. Add each key from `github_variables`: GCP_PROJECT, GCP_REGION, WIF_PROVIDER, DEPLOYER_SA, AR_REPO, API_SERVICE, SPA_BUCKET, URL_MAP.

No service account keys are involved. GitHub's OIDC token is exchanged through Workload Identity Federation, and only your repository can do it.

## Step 4: First deploys

1. Run **Actions › SPA deploy**, then open `app_url`. The page shows the SPA release ID.
2. Run **API deploy (canary)** with `canary_percent = 100` for the very first release.
3. Refresh the page. You'll see the API revision, and you can add and delete items, which go to Cloud SQL.

## Exercises (practise these, then talk about them)

1. **Canary.** Change something in `api/Program.cs` (for example, the health status text) and push. The new revision gets 10%. Click **Refresh** several times and watch the revision flip between old and new.
2. **Promote.** Run **API traffic** with `promote`, and everything moves to the new revision.
3. **API rollback.** Run **API traffic** with `rollback` and the previous revision's name (it's listed in the run log). The rollback takes seconds and doesn't rebuild anything.
4. **SPA swap and rollback.**
   - Change the heading in `app.component.ts` and push, so the release ID changes.
   - Run **SPA rollback** with the previous ID. The old page comes back immediately, because its hashed bundles were never deleted.
5. **Cloud Armor.**
   - Run `curl "http://<IP>/api/items?q=1'%20OR%20'1'='1"` and you should get a 403 from the SQL injection rule.
   - Add your IP to `blocked_ip_ranges`, apply, and watch the site return 403.
6. **Pre-scaling.**
   - First, wait about 15 minutes with no traffic and time the first request: `curl -w '%{time_total}\n' -o /dev/null -s http://<IP>/api/health`. That's a cold start.
   - Set `api_min_instances = 1`, apply, wait the same time, and measure again.
7. **Database HA.** Set `db_high_availability = true`, apply, then trigger a failover with `gcloud sql instances failover amaze-lab-pg`. Watch the API recover.
8. **Observability.**
   - In Logs Explorer, filter on `resource.type="cloud_run_revision"` to see the JSON logs.
   - Create a log-based metric for errors and an alert on it.
9. **Stretch: second region.** Add a second Cloud Run service and serverless NEG in `us-east1` behind the same backend service. That's your active/active versus active/hot discussion.

## Interview lines this lab backs up

- "Rollback is a traffic shift, not a redeploy." *(exercises 2–3)*
- "Hashed bundles are immutable, and `index.html` is the pointer, so a swap is instant and a rollback is safe." *(exercise 4)*
- "Cloud Run only accepts traffic from the load balancer, and Cloud Armor sits in front." *(exercise 5)*
- "We pre-scale for known peaks and accept paying for some idle capacity." *(exercise 6)*
- "There are no keys anywhere: Workload Identity Federation for CI, and a service account plus Secret Manager at runtime."

## The same design on AWS (for translation week)

| GCP (this lab) | AWS |
|---|---|
| GCS bucket + backend bucket + Cloud CDN | S3 + CloudFront with Origin Access Control |
| Cloud Armor | AWS WAF (managed rule groups, IP sets) |
| Global external ALB with path routing | CloudFront behaviours (`/api/*` → ALB origin) |
| Cloud Run revisions + traffic split | ECS on Fargate + CodeDeploy blue/green, or App Runner |
| Serverless NEG, ingress restricted to LB | Internal ALB / VPC Lattice; tasks in private subnets |
| Cloud SQL PostgreSQL, private IP, HA | Aurora PostgreSQL (Multi-AZ), or RDS |
| Secret Manager | Secrets Manager |
| Artifact Registry | ECR |
| Workload Identity Federation | GitHub OIDC → IAM role (`AssumeRoleWithWebIdentity`) |
| CDN cache invalidation | CloudFront invalidation |
| Cloud Logging / Monitoring | CloudWatch Logs / Metrics / Alarms |
| Partner Interconnect | Direct Connect |

## Teardown

```bash
cd infra && terraform destroy
```

If the destroy stops on the private service networking connection, run it a second time. The connection is set to be abandoned, so the VPC can still be deleted.
