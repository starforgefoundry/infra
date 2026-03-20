[working-directory: 'ansible']
deploy HOST="starforge":
    ansible-playbook deploy.yml --limit {{ HOST }}
    
build-custom-images:
    @docker buildx build --push --platform linux/amd64 \
        -f apps/zitadel-roles/Dockerfile \
        -t ghcr.io/starforgefoundry/zitadel-roles:latest \
        -t ghcr.io/starforgefoundry/zitadel-roles:`git rev-parse --short HEAD` apps/zitadel-roles/
    @docker buildx build --push --platform linux/amd64 \
        -f apps/protect-oauth/Dockerfile \
        -t ghcr.io/starforgefoundry/protect-oauth:latest \
        -t ghcr.io/starforgefoundry/protect-oauth:`git rev-parse --short HEAD` apps/protect-oauth/

collection:
  ansible-galaxy collection install -r ansible/requirements.yml