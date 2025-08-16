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
    // Mark this pod as having active LRO
    await markPodAsLRO();
    
    // Start your long-running operation
    // startLongRunningOperation();
    
    res.json({ status: 'LRO started' });
});

app.post('/end-lro', async (req, res) => {
    // Mark this pod as having active LRO
    await unmarkPodAsLRO();
    
    // Start your long-running operation
    // startLongRunningOperation();
    
    res.json({ status: 'LRO started' });
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
        const patch = {
            metadata: {
                annotations: {
                    'app.company.com/lro-active': 'true',
                    'app.company.com/lro-started': new Date().toISOString()
                }
            }
        };
        
        console.log('Debug - patch object:', JSON.stringify(patch, null, 2));
        
        // Use the correct API call - try different approaches based on version
        let response;
        try {
            // Method 1: Object-based parameters (newer versions)
            response = await k8sApi.patchNamespacedPod({
                name: podName,
                namespace: namespace,
                body: patch,
                headers: { 
                    'Content-Type': 'application/merge-patch+json' 
                }
            });
        } catch (firstError) {
            console.log('Object-based call failed, trying positional parameters...');
            // Method 2: Positional parameters (older versions or alternative signature)
            response = await k8sApi.patchNamespacedPod(
                podName,        // name
                namespace,      // namespace
                patch,          // body
                undefined,      // pretty
                undefined,      // dryRun
                undefined,      // fieldManager
                undefined,      // fieldValidation
                undefined,      // force
                {
                    headers: { 
                        'Content-Type': 'application/merge-patch+json' 
                    }
                }
            );
        }
        
        console.log(`Successfully marked pod ${podName} as LRO active`);
        return response;
    } catch (error) {
        console.error('Error marking pod as LRO:', error.message);
        console.error('Full error:', error);
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
        
        // Create patch object to remove annotation
        const patch = {
            metadata: {
                annotations: {
                    'app.company.com/lro-active': null  // Remove annotation
                }
            }
        };
        
        // Use the correct API call - try different approaches based on version
        let response;
        try {
            // Method 1: Object-based parameters (newer versions)
            response = await k8sApi.patchNamespacedPod({
                name: podName,
                namespace: namespace,
                body: patch,
                headers: { 
                    'Content-Type': 'application/merge-patch+json' 
                }
            });
        } catch (firstError) {
            console.log('Object-based call failed, trying positional parameters...');
            // Method 2: Positional parameters (older versions or alternative signature)
            response = await k8sApi.patchNamespacedPod(
                podName,        // name
                namespace,      // namespace
                patch,          // body
                undefined,      // pretty
                undefined,      // dryRun
                undefined,      // fieldManager
                undefined,      // fieldValidation
                undefined,      // force
                {
                    headers: { 
                        'Content-Type': 'application/merge-patch+json' 
                    }
                }
            );
        }
        
        console.log(`Successfully unmarked pod ${podName} as LRO active`);
        return response;
    } catch (error) {
        console.error('Error unmarking pod as LRO:', error.message);
        console.error('Full error:', error);
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