default:
    @just --list --unsorted

build:
    nix build .

image:
    nix build path:.#image

push-image:
    nix build path:.#pushImage && ./result/bin/push-image

multiarch-push:
    nix build .#combineImages && ./result/bin/combine-images

list-images:
    nix develop --command skopeo list-tags docker://ghcr.io/kasuboski/feedreader

cache-nix:
    nix build --json \
    | jq -r '.[].outputs | to_entries[].value' \
    | cachix push kasuboski-feedreader

    nix develop --profile dev-profile --command 'true' # to preload or something :shrug:
    cachix push kasuboski-feedreader dev-profile

local-workflow:
    act -s GITHUB_TOKEN="{{ env_var('GITHUB_TOKEN') }}"
