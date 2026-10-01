#!/bin/bash
echo "Port-forwarding uslug DavTro..."
kubectl port-forward svc/fastapi-web-app-svc 8080:80 -n davtro02 &
kubectl port-forward svc/grafana 3000:3000 -n davtro02 &
kubectl port-forward svc/prometheus 9090:9090 -n davtro02 &
kubectl port-forward svc/kafka-ui 8081:80 -n davtro02 &
echo "FastAPI: http://localhost:8080"
echo "Grafana: http://localhost:3000"
echo "Prometheus: http://localhost:9090"
echo "Kafka UI: http://localhost:8081"
