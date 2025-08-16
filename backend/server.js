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
        
        // Debug logging
        console.log('Environment variables:', {
            POD_NAME: process.env.POD_NAME,
            HOSTNAME: process.env.HOSTNAME,
            NAMESPACE: process.env.NAMESPACE,
            podName: podName,
            namespace: namespace
        });
        
        if (!podName) {
            throw new Error('Pod name is undefined - check POD_NAME environment variable');
        }
        
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