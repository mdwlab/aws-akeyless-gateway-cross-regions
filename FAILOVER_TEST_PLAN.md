# Cross-region failover test plan

## Objective

Verify that when one region's Akeyless Gateway becomes unavailable, AWS
Global Accelerator detects it and routes all traffic to the healthy region,
with no manual intervention and no client-visible downtime beyond the
health-check detection window.

## Scope

- ALB target group health correctly reflects gateway health (already
  validated: both regions returned `healthy` after the `/status` fix).
- Global Accelerator's endpoint group health correctly reflects
  ALB/region health.
- GA reroutes new connections away from the unhealthy region within its
  detection window, and back once the region recovers.

Out of scope: DNS propagation (GA's two anycast IPs are static - if you're
testing through the optional Route 53 alias, there's no DNS change during
failover, so no TTL/caching delay to account for), and gateway/Vault data
plane correctness (this is purely a network-routing test).

## A nuance that can invalidate the test if missed

Global Accelerator routes each client to whichever *healthy* endpoint
group is closest to it - it is not necessarily round-robining 50/50
between regions. If you're testing from a location clearly closer to one
region, GA may already be sending 100% of your traffic there under normal
conditions. If you then kill the *other* region (the one you were never
being routed to), you'll see no visible change and could wrongly conclude
failover doesn't work.

**Always establish which region is actually serving your test client
first (Step 0), then induce failure on that region specifically.**

## Prerequisites

- Both regions currently healthy (confirm with the commands in Step 0).
- AWS CLI access to both regions, plus IAM permissions for: `ec2`
  (revoke/authorize security group rules), `elbv2` (describe-target-health),
  `globalaccelerator` (describe-endpoint-group), `ssm` (start-session).
- **Gotcha:** the Global Accelerator API is only served from `us-west-2`,
  regardless of which regions your accelerator/endpoints actually use -
  every `aws globalaccelerator ...` command below needs `--region us-west-2`
  even when you're asking about the east endpoint group.
- SSM Session Manager access to both instances (already set up, no SSH key
  needed - IDs available via `terraform output east_instance_id` /
  `west_instance_id`).
- The test URL: `https://k8sgw.wz-aws.cs.akeyless.fans` (routes through GA),
  and the two regions' direct ALB DNS names (`terraform output
  east_alb_dns_name` / `west_alb_dns_name`) for bypassing GA to compare
  against.

Look up resource IDs you'll need, once, up front (EC2 instance IDs are
outputs; the rest still come from state):

```bash
# EC2 instance IDs
terraform output -raw east_instance_id
terraform output -raw west_instance_id

# Security group IDs (ALB SG and EC2 SG, per region)
terraform state show module.east.aws_security_group.alb | grep -E '^\s+id\s'
terraform state show module.east.aws_security_group.ec2 | grep -E '^\s+id\s'
terraform state show module.west.aws_security_group.alb | grep -E '^\s+id\s'
terraform state show module.west.aws_security_group.ec2 | grep -E '^\s+id\s'

# Global Accelerator endpoint group ARNs
terraform state show module.global_accelerator.aws_globalaccelerator_endpoint_group.east | grep -E '^\s+id\s'
terraform state show module.global_accelerator.aws_globalaccelerator_endpoint_group.west | grep -E '^\s+id\s'
```

## Step 0 - Baseline: which region is serving you right now?

Open two SSM sessions, one per instance:

```bash
aws ssm start-session --target "$(terraform output -raw east_instance_id)" --region us-east-1
aws ssm start-session --target "$(terraform output -raw west_instance_id)" --region us-west-2
```

In each session, tail the ingress controller's access log:

```bash
microk8s kubectl -n ingress logs -f -l name=nginx-ingress-microk8s
```

From a third terminal (your test client), send a burst of fresh requests
through the GA-fronted URL (each `curl` invocation opens a new connection,
which is what you want - GA's routing decision is made per new flow):

```bash
for i in $(seq 1 20); do
  curl -s -o /dev/null -w "%{http_code}\n" https://k8sgw.wz-aws.cs.akeyless.fans/status
  sleep 1
done
```

Watch which instance's log(s) show matching incoming requests. Note the
result - this is the region (or regions, if split) you'll target in Test 1.

Also confirm the starting state is fully healthy:

```bash
aws elbv2 describe-target-health --target-group-arn "$(terraform output -raw east_target_group_arn)" --region us-east-1
aws elbv2 describe-target-health --target-group-arn "$(terraform output -raw west_target_group_arn)" --region us-west-2

aws globalaccelerator describe-endpoint-group --endpoint-group-arn <east-endpoint-group-arn> --region us-west-2
aws globalaccelerator describe-endpoint-group --endpoint-group-arn <west-endpoint-group-arn> --region us-west-2
```
(`EndpointDescriptions[].HealthState` should read `HEALTHY` in both.)

## Test 1 (alternative, lighter-weight) - simulate a regional network failure

Cuts the ALB -> EC2 path in the target region by revoking the security
group rule that allows it, without touching the running instance or
MicroK8s. This keeps SSM access alive throughout, so you can verify
server-side (via logs) as well as client-side. Fully reversible with one
command.

Using whichever region Step 0 identified as active (example: west):

1. **Start a continuous client-side probe** in its own terminal, so you get
   a timestamped pass/fail record of the whole test:
   ```bash
   while true; do
     ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
     code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 https://k8sgw.wz-aws.cs.akeyless.fans/status)
     echo "$ts $code"
     sleep 1
   done | tee failover-test-probe.log
   ```

2. **Induce the failure** - revoke the EC2 SG's ingress rule from the ALB SG:
   ```bash
   aws ec2 revoke-security-group-ingress \
     --group-id <west-ec2-sg-id> \
     --protocol tcp --port 80 \
     --source-group <west-alb-sg-id> \
     --region us-west-2
   ```

3. **Watch the ALB target flip unhealthy** (poll every ~15s):
   ```bash
   watch -n 15 aws elbv2 describe-target-health \
     --target-group-arn "$(terraform output -raw west_target_group_arn)" --region us-west-2
   ```
   Expect `unhealthy` within ~90s (3 failed checks x 30s interval,
   `unhealthy_threshold = 3` in `modules/regional-stack/alb.tf`).

4. **Watch the GA endpoint group flip unhealthy:**
   ```bash
   watch -n 15 aws globalaccelerator describe-endpoint-group \
     --endpoint-group-arn <west-endpoint-group-arn> --region us-west-2
   ```
   Expect `HealthState: UNHEALTHY` shortly after (typically within another
   1-2 minutes - GA's health check cadence isn't user-configurable, so
   treat this as observed-and-documented rather than a guaranteed SLA).

5. **Confirm the surviving region picks up all traffic:** the east SSM
   session's log tail should now show all incoming requests (including
   ones that were previously landing on west, if Step 0 showed a split).
   The probe log from step 1 should show `200` throughout, with at most a
   brief run of failures/timeouts during the detection window in steps 3-4
   - that gap (if any) is your measured failover time.

6. **Restore the region:**
   ```bash
   aws ec2 authorize-security-group-ingress \
     --group-id <west-ec2-sg-id> \
     --protocol tcp --port 80 \
     --source-group <west-alb-sg-id> \
     --region us-west-2
   ```

7. **Confirm recovery** - re-run the same `describe-target-health` and
   `describe-endpoint-group` commands from steps 3-4 until both read
   healthy again (expect faster recovery: `healthy_threshold = 2` on the
   target group, so ~60s there). Stop the probe loop from step 1 once
   confirmed.

## Test 2 (selected) - simulate full compute/AZ failure

Same as Test 1, but stop the instance instead of touching the security
group:

```bash
aws ec2 stop-instances --instance-ids "$(terraform output -raw west_instance_id)" --region us-west-2
# ... observe as in Test 1, steps 3-5 ...
aws ec2 start-instances --instance-ids "$(terraform output -raw west_instance_id)" --region us-west-2
```

Caveat: SSM access to the stopped instance is lost for the duration, so
server-side log verification (Step 0/5's log tail) isn't available for the
downed region during this test - rely on the client-side probe and the AWS
API health states instead. After starting it back up, allow a few minutes
for the instance to boot, MicroK8s to come back up, and the ingress
controller/gateway pods to become ready before expecting the target group
to report healthy again.

### Additional signal: gateway-to-SaaS registration

Each gateway node also maintains its own outbound connection/heartbeat to
the Akeyless SaaS backend (console.akeyless.io) to register itself - this
is independent of the AWS-side health checks in this test (ALB target
health and GA endpoint health only observe the ALB->EC2->nginx->gateway
path; they say nothing about the gateway's own connectivity out to SaaS).
Stopping the instance kills that heartbeat too, so use the SaaS console's
gateway detail page (the same one that had the CORS issue -
`https://console.akeyless.io/gateways/item/85534`) as a second, independent
verification source:

- **During the outage:** the stopped node should show as disconnected/down
  on that page, distinct from (and a useful cross-check against) the AWS
  target-health signal.
- **After restart:** don't treat AWS target health alone as "fully
  recovered" - the instance/target group can report healthy (nginx/ingress
  up) before the gateway process has finished re-establishing its SaaS
  registration. Wait for the SaaS console to also show that node
  reconnected before calling the region fully recovered.

## Test 3 - simulate a gateway/cluster crash (instance stays alive)

A faster, lower-risk complement to Test 2. Instead of stopping the EC2
instance, stop MicroK8s itself - the instance, networking, and SSM access
all stay fully up; only the Kubernetes control plane and everything it
manages (nginx-ingress, the gateway pod) go away. This exercises a
different failure signature than Test 1/2: ALB health checks see the
backend port go from "listening" to "connection refused" rather than a
network-level timeout, but the same ALB/GA health-check-driven failover
logic applies either way.

```bash
aws ssm start-session --target "$(terraform output -raw west_instance_id)" --region us-west-2
sudo microk8s stop
# ... observe as in Test 1, steps 3-5, using the surviving region's log
#     tail and the client-side probe - see caveat below ...
sudo microk8s start
```

Caveats:
- `microk8s stop` also stops the local Kubernetes API server, so
  `microk8s kubectl ...` (including the Step 0/5 log tail) won't work on
  the downed node for the duration - you lose that verification signal on
  the down side specifically, though the surviving region's log tail and
  the client-side probe are unaffected and still tell you what you need.
- This does **not** exercise instance or network-level failure at all (the
  ENI, security groups, and TCP/IP stack stay fully alive throughout) - it
  validates workload/application-level failure detection, not compute/AZ
  loss. Don't treat it as a substitute for Test 2, since a real region
  outage more plausibly looks like Test 1/2's failure mode than this one.
- Recovery is much faster than Test 2: `microk8s start` plus a short wait
  for pods to become ready again, no EC2 boot cycle involved. The gateway
  will also need to re-establish its SaaS registration on the way back up
  - same caveat as Test 2's "additional signal" section applies here too.

## Pass/fail criteria

- [ ] Target group in the failed region transitions to `unhealthy` within
      the expected window and back to `healthy` after restoration.
- [ ] GA endpoint group `HealthState` transitions to `UNHEALTHY` for the
      failed region and back to `HEALTHY` after restoration.
- [ ] The client-side probe log shows continuous `200`s except for a
      bounded gap during the detection window - no sustained outage.
- [ ] Server-side logs (Test 1 only) confirm the surviving region receives
      100% of traffic while the other is down.
- [ ] The SaaS console's gateway detail page shows the affected node go
      disconnected during the outage and reconnected after restart (Test 2)
      - checked independently of, and not assumed from, AWS target health.

## Cleanup

- Confirm both target groups and both GA endpoint groups read healthy
  before considering the test complete (a failed rollback here is a
  production outage, not just a test artifact).
- Delete the local `failover-test-probe.log` if you don't want to keep it.

## Optional follow-up

Steps above still lean on `terraform state show ... | grep id` for the
security group IDs and GA endpoint group ARNs, since those aren't exposed
as outputs yet (`*_instance_id` and `*_target_group_arn` now are). If
you'll run this more than once, it's worth adding root outputs for the two
security group IDs per region and the two GA endpoint group ARNs too - say
the word and I'll wire those up the same way.
