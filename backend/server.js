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
    startLongRunningOperation();
    
    res.json({ status: 'LRO started' });
});

app.post('/end-lro', async (req, res) => {
    // Mark this pod as having active LRO
    await unmarkPodAsLRO();
    
    // Start your long-running operation
    startLongRunningOperation();
    
    res.json({ status: 'LRO started' });
});

async function markPodAsLRO() {
    const k8s = require('@kubernetes/client-node');
    const kc = new k8s.KubeConfig();
    kc.loadFromCluster();
    const k8sApi = kc.makeApiClient(k8s.CoreV1Api);
    
    const podName = process.env.HOSTNAME; // Pod name
    const namespace = process.env.NAMESPACE || 'default';
    
    // Add annotation to prevent eviction
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
        undefined,
        undefined,
        undefined,
        undefined,
        { headers: { 'Content-Type': 'application/merge-patch+json' } }
    );
}

// When LRO completes
async function unmarkPodAsLRO() {
    const k8s = require('@kubernetes/client-node');
    const kc = new k8s.KubeConfig();
    kc.loadFromCluster();
    const k8sApi = kc.makeApiClient(k8s.CoreV1Api);
    
    const podName = process.env.HOSTNAME; // Pod name
    const namespace = process.env.NAMESPACE || 'default';
    
    // Remove the annotation
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
        undefined,
        undefined,
        undefined,
        undefined,
        { headers: { 'Content-Type': 'application/merge-patch+json' } }
    );
}

// Start server
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});