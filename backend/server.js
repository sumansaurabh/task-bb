const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.json());

// Routes
app.get('/', (req, res) => {
  res.json({ message: 'Hello World! Suman\'s Minimalist Express Server is running.' });
});

app.get('/api/health', (req, res) => {
  res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

app.get('/api/users', (req, res) => {
  res.json([
    { id: 1, name: 'John Doe' },
    { id: 2, name: 'Jane Smith' }
  ]);
});

// When LRO starts
app.post('/start-lro', async (req, res) => {
    try {
        // Mark this pod as having active LRO
        await markPodAsLRO();
        
        // Start your long-running operation
        // startLongRunningOperation();
        
        res.json({ status: 'LRO started' });
    } catch (error) {
        console.error('Error in /start-lro:', error);
        res.status(500).json({ 
            error: 'Failed to start LRO', 
            details: error.message 
        });
    }
});

app.post('/end-lro', async (req, res) => {
    try {
        // Unmark this pod as having active LRO
        await unmarkPodAsLRO();
        
        res.json({ status: 'LRO ended' });
    } catch (error) {
        console.error('Error in /end-lro:', error);
        res.status(500).json({ 
            error: 'Failed to end LRO', 
            details: error.message 
        });
    }
});

app.get('/lro-status', async (req, res) => {
    try {
        const k8s = require('@kubernetes/client-node');
        const kc = new k8s.KubeConfig();
        kc.loadFromCluster();
        const k8sApi = kc.makeApiClient(k8s.CoreV1Api);
        
        const podName = process.env.POD_NAME || process.env.HOSTNAME;
        const namespace = process.env.NAMESPACE || 'default';
        
        const pod = await k8sApi.readNamespacedPod(podName, namespace);
        const lroActive = pod.body.metadata.annotations?.['app.company.com/lro-active'] === 'true';
        const lroStarted = pod.body.metadata.annotations?.['app.company.com/lro-started'];
        
        res.json({
            pod: podName,
            lroActive,
            lroStarted,
            annotations: pod.body.metadata.annotations
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

async function markPodAsLRO() {
    try {
        const k8s = require('@kubernetes/client-node');
        const kc = new k8s.KubeConfig();
        kc.loadFromCluster();
        const k8sApi = kc.makeApiClient(k8s.CoreV1Api);
        
        const podName = process.env.POD_NAME || process.env.HOSTNAME;
        const namespace = process.env.NAMESPACE || 'default';
        
        console.log(`Marking pod ${podName} as LRO active in namespace ${namespace}`);
        
        // Debug logging
        console.log('Debug - podName:', podName, 'type:', typeof podName);
        console.log('Debug - namespace:', namespace, 'type:', typeof namespace);
        
        if (!podName) {
            throw new Error('Pod name is null or undefined. POD_NAME and HOSTNAME environment variables are both missing.');
        }
        
        if (!namespace) {
            throw new Error('Namespace is null or undefined.');
        }
        
        // Create patch object
        const patch = [
            {
                op: 'add',
                path: '/metadata/annotations/app.company.com~1lro-active',
                value: 'true'
            },
            {
                op: 'add',
                path: '/metadata/annotations/app.company.com~1lro-started',
                value: new Date().toISOString()
            }
        ];
        
        console.log('Debug - patch object:', JSON.stringify(patch, null, 2));
        
        // Use JSON Patch format
        const options = {
            headers: {
                'Content-Type': 'application/json-patch+json'
            }
        };
        
        // Call with correct positional parameters
        const response = await k8sApi.patchNamespacedPod(
            podName,        // name (string)
            namespace,      // namespace (string)
            patch,          // body (patch object)
            undefined,      // pretty
            undefined,      // dryRun
            undefined,      // fieldManager
            undefined,      // fieldValidation
            undefined,      // force
            options         // options with headers
        );
        
        console.log(`Successfully marked pod ${podName} as LRO active`);
        return response;
    } catch (error) {
        console.error('Error marking pod as LRO:', error.message);
        
        // If JSON Patch fails, try strategic merge patch
        if (error.response?.statusCode === 415 || error.message.includes('Unsupported Media Type')) {
            console.log('JSON Patch failed, trying strategic merge patch...');
            return await markPodAsLROWithMergePatch();
        }
        
        throw error;
    }
}

async function markPodAsLROWithMergePatch() {
    try {
        const k8s = require('@kubernetes/client-node');
        const kc = new k8s.KubeConfig();
        kc.loadFromCluster();
        const k8sApi = kc.makeApiClient(k8s.CoreV1Api);
        
        const podName = process.env.POD_NAME || process.env.HOSTNAME;
        const namespace = process.env.NAMESPACE || 'default';
        
        console.log(`Attempting strategic merge patch for pod ${podName}`);
        
        // First, get the current pod to check if annotations exist
        const currentPod = await k8sApi.readNamespacedPod(podName, namespace);
        const hasAnnotations = currentPod.body.metadata.annotations !== undefined;
        
        // Create merge patch object
        const patch = {
            metadata: {
                annotations: {
                    'app.company.com/lro-active': 'true',
                    'app.company.com/lro-started': new Date().toISOString()
                }
            }
        };
        
        // If no annotations exist, we need to ensure they're created
        if (!hasAnnotations) {
            patch.metadata.annotations = {
                ...patch.metadata.annotations
            };
        }
        
        const options = {
            headers: {
                'Content-Type': 'application/strategic-merge-patch+json'
            }
        };
        
        const response = await k8sApi.patchNamespacedPod(
            podName,
            namespace,
            patch,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            options
        );
        
        console.log(`Successfully marked pod ${podName} as LRO active using merge patch`);
        return response;
    } catch (error) {
        console.error('Strategic merge patch also failed:', error.message);
        throw error;
    }
}

async function unmarkPodAsLRO() {
    try {
        const k8s = require('@kubernetes/client-node');
        const kc = new k8s.KubeConfig();
        kc.loadFromCluster();
        const k8sApi = kc.makeApiClient(k8s.CoreV1Api);
        
        const podName = process.env.POD_NAME || process.env.HOSTNAME;
        const namespace = process.env.NAMESPACE || 'default';
        
        console.log(`Unmarking pod ${podName} as LRO active in namespace ${namespace}`);
        
        if (!podName) {
            throw new Error('Pod name is null or undefined. POD_NAME and HOSTNAME environment variables are both missing.');
        }
        
        if (!namespace) {
            throw new Error('Namespace is null or undefined.');
        }
        
        // Use JSON Patch to remove the annotation
        const patch = [
            {
                op: 'remove',
                path: '/metadata/annotations/app.company.com~1lro-active'
            }
        ];
        
        const options = {
            headers: {
                'Content-Type': 'application/json-patch+json'
            }
        };
        
        const response = await k8sApi.patchNamespacedPod(
            podName,
            namespace,
            patch,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            options
        );
        
        console.log(`Successfully unmarked pod ${podName} as LRO active`);
        return response;
    } catch (error) {
        console.error('Error unmarking pod as LRO:', error.message);
        
        // If removal fails (e.g., annotation doesn't exist), try setting to false
        if (error.response?.statusCode === 422) {
            console.log('Annotation might not exist, trying to set to false...');
            return await unmarkPodAsLROWithMergePatch();
        }
        
        throw error;
    }
}

async function unmarkPodAsLROWithMergePatch() {
    try {
        const k8s = require('@kubernetes/client-node');
        const kc = new k8s.KubeConfig();
        kc.loadFromCluster();
        const k8sApi = kc.makeApiClient(k8s.CoreV1Api);
        
        const podName = process.env.POD_NAME || process.env.HOSTNAME;
        const namespace = process.env.NAMESPACE || 'default';
        
        const patch = {
            metadata: {
                annotations: {
                    'app.company.com/lro-active': 'false'
                }
            }
        };
        
        const options = {
            headers: {
                'Content-Type': 'application/strategic-merge-patch+json'
            }
        };
        
        const response = await k8sApi.patchNamespacedPod(
            podName,
            namespace,
            patch,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            options
        );
        
        console.log(`Successfully set pod ${podName} LRO active to false`);
        return response;
    } catch (error) {
        console.error('Strategic merge patch for unmarking also failed:', error.message);
        throw error;
    }
}

// Start server
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
  console.log('Environment variables:', {
    POD_NAME: process.env.POD_NAME,
    HOSTNAME: process.env.HOSTNAME,
    NAMESPACE: process.env.NAMESPACE,
    podName: process.env.POD_NAME || process.env.HOSTNAME,
    namespace: process.env.NAMESPACE || 'default'
  });
});