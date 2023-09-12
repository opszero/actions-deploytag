# actions-deploytag

Deploy Feature Environments to Kubernetes using Github Actions


## Github Actions

For Github Actions we have the following checklist:

 - [ ] OIDC IAM
 - [ ] Build Docker
 - [ ] Push to ECR
 - [ ] Deploy using Helm

### Kubernetes Deployment with Feature Branches

EKS Deployment

```
name: Deploy

on:
  push:
    branches:
      - qa
      - production
      - 'feature_deploy/**'
      - 'bug/**'
      - 'epic/**'

jobs:
  deploy:
    name: Test, Build, Deploy
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write

    services:
      postgres:
        image: postgres:13.3
        env:
          POSTGRES_USER: postgres
          POSTGRES_DB: opszero_test
          POSTGRES_PASSWORD: "postgres"
        ports:
        - 5432:5432
        # Set health checks to wait until postgres has started
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

      redis:
        image: redis:5.0
        ports:
        - 6379:6379
        options: --entrypoint redis-server

    steps:
    - name : "Deploytag"
      uses: opszero/deploytag@v2.2
      id: deploytag
      with:
        github-ref: ${{ github.ref }}

    - name: Checkout
      uses: actions/checkout@v3

    - name: Install Python
      uses: actions/setup-python@v2
      with:
        python-version: '3.9.5'

    - name: Run Tests
      env:
        DATABASE_URL: postgres://postgres:postgres@postgres:5432/opszero_test
        POSTGRES_USER: postgres
        POSTGRES_HOST: postgres
        POSTGRES_DB: opszero_test
        POSTGRES_PASSWORD: "postgres"
      run: |
        python -m pip install --upgrade pip setuptools wheel pipenv
        pipenv install --dev
        cp .env.test .env
        pipenv run pytest

    - name: Archive code coverage results
      uses: actions/upload-artifact@v2
      with:
        name: code-coverage-report
        path: output/test/test_results

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v1
      with:
        role-to-assume: arn:aws:iam::123456123123:role/github-deployer
        aws-region: us-west-2

    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v1
      if: ${{ steps.deploytag.outputs.is-preview == 'true' || github.ref == 'refs/heads/qa' || github.ref == 'refs/heads/production'}}

    - name: Build, tag, and push image to Amazon ECR
      id: build-image
      if: ${{ steps.deploytag.outputs.is-preview == 'true' || github.ref == 'refs/heads/qa' || github.ref == 'refs/heads/production'}}
      env:
        ECR_REGISTRY: 12345678910.dkr.ecr.us-west-2.amazonaws.com
        ECR_REPOSITORY: opszero/opszero
        IMAGE_TAG: ${{ github.sha }}
      run: |
        docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

    - name: Release Feature
      if: ${{ steps.deploytag.outputs.is-preview == 'true' }}
      env:
        ECR_REGISTRY: 12345678910.dkr.ecr.us-west-2.amazonaws.com
        ECR_REPOSITORY: opszero/opszero
        IMAGE_TAG: ${{ github.sha }}
        CLUSTER_NAME: opszero-qa
      run: |
        aws eks update-kubeconfig --name $CLUSTER_NAME
        helm upgrade --install opszero ./charts/opszero  \
        --create-namespace \
        --namespace ${{ steps.deploytag.outputs.preview-env-name }} \
        -f charts/qa.yaml \
        -f charts/feature.yaml \
        --set secrets.DEPLOYTAG_BRANCH="${{ steps.deploytag.outputs.preview-env-name }}" \
        --set image.tag=$IMAGE_TAG \
        --set ingress.host=${{ steps.deploytag.outputs.preview-env-name }}.opszero.com

    - name: Release QA
      if: ${{ github.ref == 'refs/heads/qa' }}
      env:
        ECR_REGISTRY: 12345678910.dkr.ecr.us-west-2.amazonaws.com
        ECR_REPOSITORY: opszero/opszero
        IMAGE_TAG: ${{ github.sha }} #Latest tag is used in the chart
        CLUSTER_NAME: opszero-qa
      run: |
        aws eks update-kubeconfig --name $CLUSTER_NAME
        helm upgrade --install opszero ./charts/opszero  \
        --namespace qa \
        -f charts/qa.yaml \
        --set secrets.DEPLOYTAG_BRANCH=qa \
        --set secrets.SECRET_KEY="${{ secrets.SECRET_KEY }}" \
        --set image.tag=$IMAGE_TAG \
        --set ingress.host=qa.opszero.com

    - name: Release Production
      if: ${{ github.ref == 'refs/heads/production' }}
      env:
        ECR_REGISTRY: 12345678910.dkr.ecr.us-west-2.amazonaws.com
        ECR_REPOSITORY: opszero/opszero
        IMAGE_TAG: ${{ github.sha }} #Latest tag is used in the chart
        CLUSTER_NAME: opszero-prod
      run: |
        aws eks update-kubeconfig --name $CLUSTER_NAME
        helm upgrade --install opszero ./charts/opszero  \
        -f charts/production.yaml \
        --set secrets.DEPLOYTAG_BRANCH=production \
        --set image.tag=$IMAGE_TAG \
        --set ingress.host=www.opszero.com


```
