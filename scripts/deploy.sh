#!/bin/bash

set -ex

/scripts/config_k8s.sh

source /scripts/set_env.sh

HELM_HOME=$(helm home)
mkdir -p $HELM_HOME


HELM_ARGS=()

CIRCLE_BRANCH=$(echo $CIRCLE_BRANCH | sed 's/[^A-Za-z0-9]/-/g' | tr '[:upper:]' '[:lower:]')

if [ -n "$HELM_TLS" ]
then
    if [ ! -f $HELM_HOME/ca.pem ]
    then
        echo "$HELM_CA" | base64 -d --ignore-garbage > $HELM_HOME/ca.pem
    fi
    if [ ! -f $HELM_HOME/cert.pem ]
    then
        echo "$HELM_CERT"| base64 -d --ignore-garbage > $HELM_HOME/cert.pem
    fi
    if [ ! -f $HELM_HOME/key.pem ]
    then
        echo "$HELM_KEY"| base64 -d --ignore-garbage > $HELM_HOME/key.pem
    fi
    HELM_ARGS+=(--tls)
fi


if [ "$CIRCLE_BRANCH" = "master" ] || [ "$CIRCLE_BRANCH" = "" ]
then
    # use defaults for now
    echo "deploying..."
else
    HELM_ARGS+=(
        --namespace $CIRCLE_BRANCH
    )

    if ! kubectl get namespaces | grep -q "$CIRCLE_BRANCH"
    then
        kubectl create namespace $CIRCLE_BRANCH
    fi

    /scripts/apply_registry_secret.sh
fi
TILLER_NAMESPACE=${TILLER_NAMESPACE:-"kube-system"}

HELM_ARGS+=(
    --set ingress.hosts={$HOST}
    --set ingress.tls[0].hosts={$HOST}
    --set ingress.tls[0].secretName=$HELM_NAME-staging-cert
    --set image.tag=${CIRCLE_SHA1}
    --tiller-namespace=$TILLER_NAMESPACE
    --force
    --wait
    --install
)

if [ -n "$HELM_VARS" ]
then
    HELM_ARGS+=($(echo "$HELM_VARS" | envsubst))
fi

helm upgrade $HELM_NAME $CHART_NAME "${HELM_ARGS[@]}"
