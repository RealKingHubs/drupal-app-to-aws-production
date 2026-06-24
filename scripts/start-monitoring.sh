#!/bin/bash
# ============================================================
# Start Monitoring Access
# Opens SSM tunnels for Prometheus, Grafana, and Logstash
# Run this before accessing monitoring tools
# ============================================================
set -euo pipefail

INSTANCE_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=drupal-aws-production-app" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text | awk '{print $1}')

echo "Using instance: $INSTANCE_ID"
echo ""
echo "Starting SSM tunnels..."
echo "Press Ctrl+C to stop all tunnels"
echo ""
echo "Once tunnels are open, access:"
echo "  Grafana:    http://localhost:3000  (admin/admin)"
echo "  Prometheus: http://localhost:9090"
echo "  Kibana:     http://localhost:5601"
echo ""

# Start all three tunnels in background
aws ssm start-session \
  --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}' &
GRAFANA_PID=$!

aws ssm start-session \
  --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["9090"],"localPortNumber":["9090"]}' &
PROMETHEUS_PID=$!

echo "Tunnels started. PIDs: Grafana=$GRAFANA_PID Prometheus=$PROMETHEUS_PID"
echo "Waiting... (Ctrl+C to stop)"

# Clean up on exit
trap "kill $GRAFANA_PID $PROMETHEUS_PID 2>/dev/null; echo 'Tunnels closed'" EXIT
wait
