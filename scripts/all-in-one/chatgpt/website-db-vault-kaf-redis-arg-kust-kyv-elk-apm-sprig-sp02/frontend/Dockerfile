FROM docker.io/nginxinc/nginx-unprivileged:alpine
# default.conf -> proxy /api (FastAPI) i /kafka-metrics (kafka-exporter)
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/
EXPOSE 8080
CMD ["nginx","-g","daemon off;"]
