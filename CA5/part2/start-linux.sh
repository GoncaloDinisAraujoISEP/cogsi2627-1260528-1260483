#!/usr/bin/env bash
set -e

echo "1. A iniciar Jenkins e VM de produção..."
docker start jenkins-ca5 2>/dev/null || true
vagrant up

echo "Ambiente pronto! Jenkins em http://localhost:8080 | App em http://192.168.56.30:8080/books"
