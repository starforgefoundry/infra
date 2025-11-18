[private]
_resolve_secrets:
    @op inject -i "secrets.yml" -o "secrets.resolved.yml" -f

[private]
_cleanup_secrets:
    @rm -f secrets.resolved.yml

[working-directory: 'ansible']
deploy HOST="starforge":
    @just _resolve_secrets

    ansible-playbook deploy.yml --limit {{ HOST }}
    
    @just _cleanup_secrets

build-custom-images:
    @docker buildx build --push --platform linux/amd64 \
        -f zitadel-roles/Dockerfile \
        -t ghcr.io/starforgefoundry/zitadel-roles:latest \
        -t ghcr.io/starforgefoundry/zitadel-roles:`git rev-parse --short HEAD` zitadel-roles/

collection:
  ansible-galaxy collection install -r ansible/requirements.yml