Write-Host "=== 1. A lançar o nó DB ===" -ForegroundColor Cyan
multipass launch 24.04 --name db --cpus 1 --memory 1024M --cloud-init db.yaml

# Obter o IP interno do nó db via comando nativo do Linux
$dbIp = (multipass exec db -- hostname -I).Trim().Split(" ")[0]
Write-Host "Nó DB operacional no IP: $dbIp" -ForegroundColor Green

Write-Host "=== 2. A lançar o nó APP ===" -ForegroundColor Cyan
multipass launch 24.04 --name app --cpus 2 --memory 2048M --cloud-init app.yaml

# Injetar o IP da base de dados no /etc/hosts da app e iniciar o serviço
multipass exec app -- sudo bash -c "echo '$dbIp db' >> /etc/hosts"
multipass exec app -- sudo systemctl daemon-reload
multipass exec app -- sudo systemctl enable --now bookstore.service

$appIp = (multipass exec app -- hostname -I).Trim().Split(" ")[0]
Write-Host "Nó APP operacional no IP: $appIp" -ForegroundColor Green

Write-Host "=== 3. A lançar o nó PROXY ===" -ForegroundColor Cyan
multipass launch 24.04 --name proxy --cpus 1 --memory 512M --cloud-init proxy.yaml

# Injetar o IP da app no /etc/hosts do proxy e reiniciar Nginx
multipass exec proxy -- sudo bash -c "echo '$appIp app' >> /etc/hosts"
multipass exec proxy -- sudo rm -f /etc/nginx/sites-enabled/default
multipass exec proxy -- sudo ln -sf /etc/nginx/sites-available/reverse-proxy /etc/nginx/sites-enabled/
multipass exec proxy -- sudo systemctl restart nginx

$proxyIp = (multipass exec proxy -- hostname -I).Trim().Split(" ")[0]
Write-Host "=== Cluster concluído com sucesso! ===" -ForegroundColor Green
Write-Host "Aceda à API através de: http://$proxyIp/books" -ForegroundColor Yellow