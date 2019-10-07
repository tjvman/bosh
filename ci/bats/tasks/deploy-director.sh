#!/usr/bin/env bash

source /etc/profile.d/chruby.sh
chruby ruby

set -e

function cp_artifacts {
  rm -rf director-state/.bosh cache-dot-bosh-dir/.bosh
  cp -R $HOME/.bosh director-state/
  cp -R $HOME/.bosh cache-dot-bosh-dir/
  cp director.yml director-creds.yml director-state.json director-state/
}

function restore_state {
  rm -rf $HOME/.bosh
  cp -R director-state/.bosh $HOME
  cp director-state/director-* .
}

trap cp_artifacts EXIT

: ${BAT_INFRASTRUCTURE:?}

mv bosh-cli/alpha-bosh-cli-* /usr/local/bin/bosh-cli
chmod +x /usr/local/bin/bosh-cli

if [[ -e director-state/director-state.json ]]; then
  echo "Using existing director-state for upgrade"
  restore_state
fi

bosh-cli interpolate bosh-deployment/bosh.yml \
  -o bosh-deployment/$BAT_INFRASTRUCTURE/cpi.yml \
  -o bosh-deployment/misc/powerdns.yml \
  -o bosh-deployment/jumpbox-user.yml \
  -o bosh-src/ci/bats/ops/remove-health-monitor.yml \
  -o bosh-deployment/local-bosh-release.yml \
  -o bosh-deployment/experimental/blobstore-https.yml \
  -o bosh-deployment/experimental/bpm.yml \
  -v dns_recursor_ip=8.8.8.8 \
  -v director_name=bats-director \
  -v local_bosh_release=$(realpath bosh-release/*.tgz) \
  --vars-file <( bosh-src/ci/bats/iaas/$BAT_INFRASTRUCTURE/director-vars ) \
  $DEPLOY_ARGS \
  > director.yml

bosh-cli create-env \
  --state director-state.json \
  --vars-store director-creds.yml \
  director.yml

cat bosh-release/version
