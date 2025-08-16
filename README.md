# GitHub Actions - ArgoCD Integration

This repository includes GitHub Actions workflows for building, pushing Docker images, and deploying via ArgoCD.

## Workflows

### 1. Combined Build and Deploy (`docker-build-and-push.yml`)
- **Triggers**: 
  - Push to `main` or `develop` branches (when `backend/**` files change)
  - Pull requests to `main` branch
  - Manual workflow dispatch
- **Features**:
  - Builds and pushes Docker image to GitHub Container Registry
  - Runs security scan with Trivy
  - Automatically deploys to ArgoCD on push to `main`
  - Supports manual deployment with custom image tag
  - Automatic rollback on deployment failure

### 2. Standalone ArgoCD Deploy (`deploy-argocd.yml`)
- **Triggers**:
  - Push to `main` branch
  - Manual workflow dispatch
- **Features**:
  - Deploys existing Docker images via ArgoCD API
  - Manual rollback capability
  - Deployment status monitoring

## Required Secrets

Configure these secrets in your GitHub repository settings:

### ArgoCD Configuration
- `ARGOCD_SERVER`: Your ArgoCD server URL (e.g., `https://argocd.example.com`)
- `ARGOCD_TOKEN`: ArgoCD authentication token

### Getting ArgoCD Token

1. **Using ArgoCD CLI:**
```bash
argocd account generate-token --account <username>
```

2. **Using ArgoCD UI:**
   - Login to ArgoCD UI
   - Go to User Info → Generate New Token
   - Copy the generated token

3. **Using API:**
```bash
curl -k -X POST https://your-argocd-server/api/v1/session \
  -d '{"username":"admin","password":"your-password"}' | \
  jq -r '.token'
```

## Workflow Features

### Build and Push Job
- Builds Docker image from `backend/` directory
- Tags with branch name and commit SHA
- Pushes to `ghcr.io/[owner]/[repo]/backend`
- Runs security scanning with Trivy
- Only runs on actual code changes (not on manual dispatch if `skip_build` is true)

### ArgoCD Deployment Job
- Updates ArgoCD application with new image
- Triggers sync operation
- Monitors deployment progress (up to 10 minutes)
- Provides detailed status reporting
- Creates deployment summary in GitHub Actions

### Rollback Job
- Automatically triggers on deployment failure
- Rolls back to previous revision
- Provides rollback status summary

## Manual Deployment Options

### Deploy Existing Image
Use workflow dispatch with:
- `image_tag`: Specify the image tag to deploy
- `skip_build`: Set to `true` to skip building and deploy existing image

### Example Manual Deployment
1. Go to Actions tab in GitHub
2. Select "Build, Push, and Deploy via ArgoCD"
3. Click "Run workflow"
4. Enter image tag (e.g., `main-abc1234`)
5. Check "Skip build" if deploying existing image

## ArgoCD Application Configuration

Your ArgoCD application should be configured to use Kustomize with image replacement:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nodejs-app
spec:
  source:
    repoURL: https://github.com/your-org/your-repo
    path: k8s
    targetRevision: main
    kustomize:
      images:
      - ghcr.io/your-org/your-repo/backend:main-latest
```

## Monitoring and Troubleshooting

### Deployment Status
The workflow provides:
- Real-time sync and health status
- Deployment completion confirmation
- ArgoCD application details
- Direct links to ArgoCD UI

### Common Issues

1. **Invalid ArgoCD credentials**
   - Verify `ARGOCD_SERVER` and `ARGOCD_TOKEN` secrets
   - Ensure token has proper permissions

2. **Application not found**
   - Verify ArgoCD application name is `nodejs-app`
   - Or update workflow to use your application name

3. **Image not found**
   - Ensure Docker image was built and pushed successfully
   - Check GitHub Container Registry for image availability

4. **Deployment timeout**
   - Check ArgoCD application sync status
   - Review Kubernetes pod logs
   - Verify cluster resources

### Logs and Debugging
- Check GitHub Actions logs for detailed error messages
- Monitor ArgoCD UI for sync status
- Review ArgoCD application events

## Security Considerations

- Use GitHub Container Registry with proper authentication
- Store ArgoCD credentials as GitHub secrets
- Enable vulnerability scanning with Trivy
- Use least-privilege access for ArgoCD tokens
- Regular token rotation recommended

## Customization

### Change Application Name
Replace `nodejs-app` with your ArgoCD application name in both workflows.

### Modify Image Registry
Update `REGISTRY` and `IMAGE_NAME` environment variables to use different container registry.

### Adjust Timeout
Modify the polling loop in "Wait for deployment completion" step to change timeout duration.

### Add Notifications
Integrate with Slack, Discord, or other notification services by adding notification steps.
