[working-directory: 'ansible']
deploy HOST="starforge":
    ansible-playbook deploy.yml --limit {{ HOST }}
    
build-custom-images:
    @docker buildx build --push --platform linux/amd64 \
        -f zitadel-roles/Dockerfile \
        -t ghcr.io/starforgefoundry/zitadel-roles:latest \
        -t ghcr.io/starforgefoundry/zitadel-roles:`git rev-parse --short HEAD` zitadel-roles/

collection:
  ansible-galaxy collection install -r ansible/requirements.yml