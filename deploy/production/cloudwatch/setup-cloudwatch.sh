#!/usr/bin/env bash
# Creates the CloudWatch side of production monitoring. Run once in AWS CloudShell
# (Sydney region), after the CloudWatch agent is running on the server.
#
#   bash setup-cloudwatch.sh <instance-id> <alert-email>
#
# Creates: SNS email topic, metric filters on the nginx access log
# (RequestCount, RequestLatency, Http4xx, Http5xx), 5 alarms and the dashboard.
# Safe to re-run: everything is created-or-updated.
set -euo pipefail

INSTANCE_ID="${1:?usage: bash setup-cloudwatch.sh <instance-id> <alert-email>}"
ALERT_EMAIL="${2:?usage: bash setup-cloudwatch.sh <instance-id> <alert-email>}"
REGION="${AWS_REGION:-ap-southeast-2}"
NS="SWE40006/Production"
LOG_GROUP="/swe40006/production/nginx-access"
PREFIX="swe40006-prod"
DASHBOARD="SWE40006-Production"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_DEFAULT_REGION="$REGION"

echo "== 1/4 SNS topic for alert emails"
TOPIC_ARN=$(aws sns create-topic --name "${PREFIX}-alerts" --query TopicArn --output text)
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email \
  --notification-endpoint "$ALERT_EMAIL" >/dev/null
echo "   $TOPIC_ARN"
echo "   -> open $ALERT_EMAIL and click 'Confirm subscription'"

echo "== 2/4 Metric filters on $LOG_GROUP"
aws logs create-log-group --log-group-name "$LOG_GROUP" 2>/dev/null || true

put_filter() {  # name pattern value unit [default]
  local default_json=""
  [ -n "${5:-}" ] && default_json=",\"defaultValue\":$5"
  aws logs put-metric-filter --log-group-name "$LOG_GROUP" \
    --filter-name "$1" --filter-pattern "$2" \
    --metric-transformations "[{\"metricName\":\"$1\",\"metricNamespace\":\"$NS\",\"metricValue\":\"$3\",\"unit\":\"$4\"$default_json}]"
  echo "   $1"
}
put_filter RequestCount   '{ $.status = * }'                       '1'               Count   0
put_filter RequestLatency '{ $.request_time = * }'                 '$.request_time'  Seconds
put_filter Http4xx        '{ $.status >= 400 && $.status < 500 }'  '1'               Count   0
put_filter Http5xx        '{ $.status >= 500 }'                    '1'               Count   0

echo "== 3/4 Alarms"
alarm() {  # name description namespace metric stat period evals threshold operator dims...
  local name="$PREFIX-$1"; shift
  local desc="$1" ns="$2" metric="$3" stat="$4" period="$5" evals="$6" thr="$7" op="$8"; shift 8
  local dims=()
  [ $# -gt 0 ] && dims=(--dimensions "$@")
  aws cloudwatch put-metric-alarm --alarm-name "$name" --alarm-description "$desc" \
    --namespace "$ns" --metric-name "$metric" $([[ $stat == p* ]] && echo --extended-statistic || echo --statistic) "$stat" \
    --period "$period" --evaluation-periods "$evals" --threshold "$thr" \
    --comparison-operator "$op" --treat-missing-data notBreaching \
    --alarm-actions "$TOPIC_ARN" --ok-actions "$TOPIC_ARN" "${dims[@]}"
  echo "   $name"
  ALARM_ARNS+=("arn:aws:cloudwatch:$REGION:$ACCOUNT_ID:alarm:$name")
}
ALARM_ARNS=()
alarm high-cpu      "CPU above 70% for 5 minutes"            AWS/EC2 CPUUtilization   Average 300 1 70 GreaterThanThreshold          "Name=InstanceId,Value=$INSTANCE_ID"
alarm high-memory   "Memory above 85% for 5 minutes"         "$NS"   mem_used_percent Average 300 1 85 GreaterThanThreshold          "Name=InstanceId,Value=$INSTANCE_ID"
alarm status-check  "EC2 instance or system check failing"   AWS/EC2 StatusCheckFailed Maximum 60 2 1  GreaterThanOrEqualToThreshold "Name=InstanceId,Value=$INSTANCE_ID"
alarm http-5xx      "5 or more server errors in 5 minutes"   "$NS"   Http5xx          Sum     300 1 5  GreaterThanOrEqualToThreshold
alarm high-latency  "p95 request latency above 500 ms"       "$NS"   RequestLatency   p95     300 1 0.5 GreaterThanThreshold

echo "== 4/4 Dashboard $DASHBOARD"
ALARMS_JSON=$(printf '"%s",' "${ALARM_ARNS[@]}"); ALARMS_JSON="[${ALARMS_JSON%,}]"
I="$INSTANCE_ID"
cat > /tmp/swe40006-dashboard.json <<EOF
{
  "widgets": [
    {"type":"text","x":0,"y":0,"width":24,"height":2,"properties":{"markdown":"## SWE40006 Production - $I\nEC2 host metrics (CPU, memory, disk, network) + app traffic from the nginx access log (requests, latency, errors)."}},

    {"type":"metric","x":0,"y":2,"width":8,"height":6,"properties":{"title":"CPU utilisation (%)","region":"$REGION","view":"timeSeries","stat":"Average","period":60,
      "metrics":[["AWS/EC2","CPUUtilization","InstanceId","$I"]],"yAxis":{"left":{"min":0,"max":100}},
      "annotations":{"horizontal":[{"label":"Alarm 70%","value":70}]}}},
    {"type":"metric","x":8,"y":2,"width":8,"height":6,"properties":{"title":"Memory used (%)","region":"$REGION","view":"timeSeries","stat":"Average","period":60,
      "metrics":[["$NS","mem_used_percent","InstanceId","$I"]],"yAxis":{"left":{"min":0,"max":100}},
      "annotations":{"horizontal":[{"label":"Alarm 85%","value":85}]}}},
    {"type":"metric","x":16,"y":2,"width":8,"height":6,"properties":{"title":"Root disk used (%)","region":"$REGION","view":"timeSeries","stat":"Average","period":300,
      "metrics":[["$NS","disk_used_percent","InstanceId","$I"]],"yAxis":{"left":{"min":0,"max":100}}}},

    {"type":"metric","x":0,"y":8,"width":12,"height":6,"properties":{"title":"Network traffic (bytes)","region":"$REGION","view":"timeSeries","stat":"Sum","period":300,
      "metrics":[["AWS/EC2","NetworkIn","InstanceId","$I",{"label":"In"}],["AWS/EC2","NetworkOut","InstanceId","$I",{"label":"Out"}]]}},
    {"type":"metric","x":12,"y":8,"width":12,"height":6,"properties":{"title":"Disk I/O (bytes)","region":"$REGION","view":"timeSeries","stat":"Sum","period":60,
      "metrics":[["$NS","diskio_read_bytes","InstanceId","$I",{"label":"Read"}],["$NS","diskio_write_bytes","InstanceId","$I",{"label":"Write"}]]}},

    {"type":"metric","x":0,"y":14,"width":8,"height":6,"properties":{"title":"HTTP requests / minute","region":"$REGION","view":"timeSeries","stat":"Sum","period":60,
      "metrics":[["$NS","RequestCount",{"label":"Requests"}]]}},
    {"type":"metric","x":8,"y":14,"width":8,"height":6,"properties":{"title":"HTTP request latency (seconds)","region":"$REGION","view":"timeSeries","period":60,
      "metrics":[["$NS","RequestLatency",{"stat":"Average","label":"Average"}],["$NS","RequestLatency",{"stat":"p95","label":"p95"}],["$NS","RequestLatency",{"stat":"Maximum","label":"Max"}]]}},
    {"type":"metric","x":16,"y":14,"width":8,"height":6,"properties":{"title":"HTTP errors / minute","region":"$REGION","view":"timeSeries","stat":"Sum","period":60,
      "metrics":[["$NS","Http4xx",{"label":"4xx"}],["$NS","Http5xx",{"label":"5xx"}]]}},

    {"type":"alarm","x":0,"y":20,"width":24,"height":3,"properties":{"title":"Alarm status","alarms":$ALARMS_JSON}},

    {"type":"log","x":0,"y":23,"width":24,"height":7,"properties":{"title":"Latest requests (nginx access log)","region":"$REGION","view":"table",
      "query":"SOURCE '$LOG_GROUP' | fields time, method, uri, status, request_time | sort @timestamp desc | limit 20"}}
  ]
}
EOF
aws cloudwatch put-dashboard --dashboard-name "$DASHBOARD" --dashboard-body file:///tmp/swe40006-dashboard.json >/dev/null
echo "   https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#dashboards/dashboard/$DASHBOARD"
echo "DONE"
