# Serviços quando o Octelium é uma instância separada e o SegPortal
# permanece no Docker Compose do host. __UPSTREAM_HOST__ é o gateway
# que a VM enxerga (QEMU user-net: 10.0.2.2).
#
# ⚠️ Defina __JUMP_HOST_KEY__ com a chave pública REAL do servidor SSH.
kind: Service
metadata:
  name: segportal
spec:
  mode: HTTP
  isPublic: true
  port: 443
  authorization:
    policies: ["allow-segportal-users"]
  config:
    upstream:
      url: http://__UPSTREAM_HOST__:__GUACAMOLE_PORT__
---
kind: Service
metadata:
  name: portal-auth
spec:
  mode: HTTP
  isPublic: true
  port: 443
  authorization:
    policies: ["allow-segportal-users"]
  config:
    upstream:
      url: http://__UPSTREAM_HOST__:__PORTAL_PORT__
---
kind: Service
metadata:
  name: desktop-financeiro
spec:
  mode: TCP
  port: 3389
  authorization:
    policies: ["allow-segportal-users"]
  config:
    upstream:
      url: tcp://__DESKTOP_FINANCEIRO__:3389
---
kind: Service
metadata:
  name: desktop-admin
spec:
  mode: TCP
  port: 3389
  authorization:
    policies: ["allow-segportal-admins"]
  config:
    upstream:
      url: tcp://__DESKTOP_ADMIN__:3389
---
kind: Service
metadata:
  name: jump-ssh
spec:
  mode: SSH
  port: 22
  authorization:
    policies: ["allow-segportal-admins"]
  config:
    upstream:
      url: ssh://__JUMP_HOST__:22
    ssh:
      user: segportal
      upstreamHostKey:
        # Host key REAL do servidor (obtenha com: ssh-keyscan).
        upstreamHostKeyValue: "__JUMP_HOST_KEY__"
        # insecureIgnoreHostKey: true