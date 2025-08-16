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

/**
 * Marks a Kubernetes pod as Long-Running Operation (LRO) active by updating its annotations.
 *
 * This function retrieves the pod name and namespace from environment variables, then updates the pod's metadata
 * to include annotations indicating that it is an LRO and when it was started. It handles potential errors
 * during the update process and logs appropriate messages to the console.
 */
async function markPodAsLRO() {
    try {
        const k8s = require('@kubernetes/client-node');
        const kc = new k8s.KubeConfig();
        kc.loadFromCluster();
        const k8sApi = kc.makeApiClient(k8s.CoreV1Api);
        
        const podName = process.env.POD_NAME || process.env.HOSTNAME; // Use POD_NAME first
        const namespace = process.env.NAMESPACE || 'default';
        
        console.log(`Marking pod ${podName} as LRO active`);
        
        await k8sApi.patchNamespacedPod(
            podName,
            namespace,
            {
                metadata: {
                    annotations: {
                        'app.company.com/lro-active': 'true',
                        'app.company.com/lro-started': new Date().toISOString()
                    }
                }
            },
            undefined, undefined, undefined, undefined,
            { headers: { 'Content-Type': 'application/merge-patch+json' } }
        );
        
        console.log(`Successfully marked pod ${podName} as LRO active`);
    } catch (error) {
        console.error('Error marking pod as LRO:', error.message);
        throw error;
    }
}

// When LRO completes
/**
 * Unmarks a Kubernetes pod as being actively involved in a Long Running Operation (LRO).
 *
 * This function connects to the Kubernetes cluster, retrieves the pod name and namespace from environment variables,
 * and patches the pod's metadata to remove the 'app.company.com/lro-active' annotation. It logs the operation
 * status to the console and handles any errors that occur during the process.
 */
async function unmarkPodAsLRO() {
    try {
        const k8s = require('@kubernetes/client-node');
        const kc = new k8s.KubeConfig();
        kc.loadFromCluster();
        const k8sApi = kc.makeApiClient(k8s.CoreV1Api);
        
        const podName = process.env.POD_NAME || process.env.HOSTNAME;
        const namespace = process.env.NAMESPACE || 'default';
        
        console.log(`Unmarking pod ${podName} as LRO active`);
        
        await k8sApi.patchNamespacedPod(
            podName,
            namespace,
            {
                metadata: {
                    annotations: {
                        'app.company.com/lro-active': null  // Remove annotation
                    }
                }
            },
            undefined, undefined, undefined, undefined,
            { headers: { 'Content-Type': 'application/merge-patch+json' } }
        );
        
        console.log(`Successfully unmarked pod ${podName} as LRO active`);
    } catch (error) {
        console.error('Error unmarking pod as LRO:', error.message);
        throw error;
    }
}


// Start server
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});