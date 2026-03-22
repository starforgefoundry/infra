[working-directory: 'ansible']
deploy HOST="starforge":
    ansible-playbook deploy.yml --limit {{ HOST }}
    
build-custom-images:
    @docker buildx build --push --platform linux/amd64 \
        -f apps/frigate-oauth/Dockerfile \
        -t ghcr.io/starforgefoundry/frigate-oauth:latest \
        -t ghcr.io/starforgefoundry/frigate-oauth:`git rev-parse --short HEAD` apps/frigate-oauth/

collection:
  ansible-galaxy collection install -r ansible/requirements.yml

[working-directory: 'nixos']
switch HOST USER="starforge":
  nixos-rebuild switch \
    --flake .#"{{HOST}}" \
    --target-host "{{USER}}@{{HOST}}" \
    --build-host "{{USER}}@{{HOST}}" \
    --sudo \
    --no-reexec

[working-directory: 'nixos']
anywhere HOST IP USER="root":
  nix run github:nix-community/nixos-anywhere -- --flake .#"{{HOST}}" "{{USER}}@{{IP}}"
