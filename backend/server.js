const express = require('express');
const https = require('https');
const fs = require('fs');
const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.json());

// Kubernetes API configuration
const K8S_API_SERVER = 'https://kubernetes.default.svc';
const TOKEN_PATH = '/var/run/secrets/kubernetes.io/serviceaccount/token';
const CA_PATH = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt';

// Read service account token
let K8S_TOKEN;
let K8S_CA;

try {
    K8S_TOKEN = fs.readFileSync(TOKEN_PATH, 'utf8');
    K8S_CA = fs.readFileSync(CA_PATH);
    console.log('Successfully loaded Kubernetes service account credentials');
} catch (error) {
    console.error('Warning: Could not load Kubernetes service account credentials:', error.message);
}

// Routes
app.get('/', (req, res) => {
    res.json({ message: 'Hello World! Suman\'s hello world minimalist Express Server is running.' });
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

// Test page for streaming
app.get('/stream-test', (req, res) => {
    res.send(`
        <!DOCTYPE html>
        <html>
        <head>
            <title>LRO Streaming Test</title>
            <style>
                body { font-family: Arial, sans-serif; margin: 20px; }
                #output { border: 1px solid #ccc; padding: 10px; height: 400px; overflow-y: scroll; }
                button { padding: 10px 20px; margin: 10px; }
                .progress { background: #f0f0f0; padding: 5px; margin: 5px 0; }
            </style>
        </head>
        <body>
            <h1>LRO Streaming Test</h1>
            <button onclick="startStream()">Start LRO Stream</button>
            <button onclick="clearOutput()">Clear Output</button>
            <div id="output"></div>

            <script>
                let eventSource;

                function startStream() {
                    if (eventSource) {
                        eventSource.close();
                    }

                    eventSource = new EventSource('/start-lro', {
                        method: 'POST'
                    });

                    eventSource.onmessage = function(event) {
                        const data = JSON.parse(event.data);
                        const output = document.getElementById('output');
                        const div = document.createElement('div');
                        div.className = 'progress';
                        
                        if (data.completed) {
                            div.innerHTML = '<strong>' + data.message + ' - Final count: ' + data.count + '</strong>';
                            eventSource.close();
                        } else if (data.count === 0) {
                            div.innerHTML = '<strong>' + data.message + '</strong>';
                        } else {
                            div.innerHTML = 'Count: ' + data.count + ' | Progress: ' + data.progress + '% | Time: ' + new Date(data.timestamp).toLocaleTimeString();
                        }
                        
                        output.appendChild(div);
                        output.scrollTop = output.scrollHeight;
                    };

                    eventSource.onerror = function(event) {
                        console.error('EventSource failed:', event);
                        const output = document.getElementById('output');
                        const div = document.createElement('div');
                        div.innerHTML = '<span style="color: red;">Connection error or completed</span>';
                        output.appendChild(div);
                    };
                }

                function clearOutput() {
                    document.getElementById('output').innerHTML = '';
                }
            </script>
        </body>
        </html>
    `);
});

// When LRO starts - Streaming version
app.post('/start-lro', async (req, res) => {
    try {
        const podName = process.env.POD_NAME || process.env.HOSTNAME;
        const namespace = process.env.NAMESPACE || 'default';
        await markPodAsLRO();
        
        // Set headers for Server-Sent Events
        res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Cache-Control'
        });

        let counter = 1;
        const maxCount = 200;

        // Send initial message
        res.write(`data: ${JSON.stringify({ message: 'LRO started', count: 0 })}\n\n`);

        // Create interval to send numbers 1 to 200 every second
        const interval = setInterval(async () => {
            if (counter <= maxCount) {
                const data = {
                    count: counter,
                    timestamp: new Date().toISOString(),
                    progress: (counter / maxCount * 100).toFixed(2),
                    podName,
                    namespace

                };
                
                res.write(`data: ${JSON.stringify(data)}\n\n`);
                console.log(`Streaming count: ${counter} on pod ${podName} and namespace ${namespace}`);
                counter++;
            } else {
                // Send completion message
                await unmarkPodAsLRO();

                res.write(`data: ${JSON.stringify({ 
                    message: 'LRO completed pod ' + podName + ' marked as inactive', 
                    count: maxCount, 
                    completed: true 
                })}\n\n`);
                
                clearInterval(interval);
                res.end();
            }
        }, 1000); // Send every second

        // Handle client disconnect
        req.on('close', () => {
            console.log('Client disconnected, stopping stream');
            clearInterval(interval);
        });

        req.on('aborted', () => {
            console.log('Request aborted, stopping stream');
            clearInterval(interval);
        });

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
        const podName = process.env.POD_NAME || process.env.HOSTNAME;
        const namespace = process.env.NAMESPACE || 'default';
        
        const pod = await getPod(podName, namespace);
        const lroActive = pod.metadata.annotations?.['app.company.com/lro-active'] === 'true';
        const lroStarted = pod.metadata.annotations?.['app.company.com/lro-started'];
        
        res.json({
            pod: podName,
            lroActive,
            lroStarted,
            annotations: pod.metadata.annotations
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Graceful shutdown endpoint for preStop hook
app.get('/api/shutdown', async (req, res) => {
    try {
        const podName = process.env.POD_NAME || process.env.HOSTNAME;
        const namespace = process.env.NAMESPACE || 'default';
        
        console.log(`Shutdown request received for pod: ${podName}`);
        
        // Check if LRO is active
        const pod = await getPod(podName, namespace);
        const lroActive = pod.metadata.annotations?.['app.company.com/lro-active'] === 'true';
        
        if (lroActive) {
            console.log(`LRO is active on pod ${podName}, waiting for completion...`);
            
            // Keep checking every 30 seconds until LRO is complete
            let checkCount = 0;
            const maxChecks = 20; // 10 minutes max wait (20 * 30 seconds)
            const checkInterval = 30000; // 30 seconds
            
            while (checkCount < maxChecks) {
                await new Promise(resolve => setTimeout(resolve, checkInterval));
                
                try {
                    const updatedPod = await getPod(podName, namespace);
                    const stillActive = updatedPod.metadata.annotations?.['app.company.com/lro-active'] === 'true';
                    
                    if (!stillActive) {
                        console.log(`✅ LRO completed on pod ${podName}, terminating immediately`);
                        res.status(200).json({ 
                            status: 'shutdown_ready', 
                            pod: podName,
                            lroWasActive: true,
                            lroCompletedAfterChecks: checkCount + 1,
                            message: 'LRO completed, safe to terminate'
                        });
                        return;
                    }
                    
                    checkCount++;
                    console.log(`⏳ LRO still active, check ${checkCount}/${maxChecks} (next check in 30s)`);
                } catch (error) {
                    console.error('Error checking LRO status:', error);
                    break;
                }
            }
            
            if (checkCount >= maxChecks) {
                console.warn(`⚠️  LRO timeout reached for pod ${podName}, proceeding with shutdown`);
            }
        } else {
            console.log(`✅ No active LRO on pod ${podName}, safe to shutdown immediately`);
        }
        
        res.status(200).json({ 
            status: 'shutdown_ready', 
            pod: podName,
            lroWasActive: lroActive,
            message: lroActive ? 'LRO timeout reached' : 'No active LRO'
        });
        
    } catch (error) {
        console.error('Error in shutdown handler:', error);
        // Even if there's an error, allow shutdown to proceed
        res.status(200).json({ 
            status: 'shutdown_ready_with_error', 
            error: error.message 
        });
    }
});

// Helper function to make Kubernetes API requests
function makeK8sRequest(path, method = 'GET', body = null) {
    return new Promise((resolve, reject) => {
        const options = {
            hostname: 'kubernetes.default.svc',
            port: 443,
            path: path,
            method: method,
            headers: {
                'Authorization': `Bearer ${K8S_TOKEN}`,
                'Accept': 'application/json'
            },
            ca: K8S_CA,
            rejectUnauthorized: true
        };

        if (body) {
            const bodyString = JSON.stringify(body);
            options.headers['Content-Type'] = 'application/strategic-merge-patch+json';
            options.headers['Content-Length'] = Buffer.byteLength(bodyString);
        }

        const req = https.request(options, (res) => {
            let data = '';

            res.on('data', (chunk) => {
                data += chunk;
            });

            res.on('end', () => {
                try {
                    const jsonData = JSON.parse(data);
                    if (res.statusCode >= 200 && res.statusCode < 300) {
                        resolve(jsonData);
                    } else {
                        reject(new Error(`Kubernetes API error: ${res.statusCode} - ${jsonData.message || JSON.stringify(jsonData)}`));
                    }
                } catch (e) {
                    if (res.statusCode >= 200 && res.statusCode < 300) {
                        resolve(data);
                    } else {
                        reject(new Error(`Kubernetes API error: ${res.statusCode} - ${data}`));
                    }
                }
            });
        });

        req.on('error', (error) => {
            reject(error);
        });

        if (body) {
            req.write(JSON.stringify(body));
        }

        req.end();
    });
}

// Get pod information
async function getPod(podName, namespace) {
    const path = `/api/v1/namespaces/${namespace}/pods/${podName}`;
    return await makeK8sRequest(path);
}

// Mark pod as having active LRO
async function markPodAsLRO() {
    const podName = process.env.POD_NAME || process.env.HOSTNAME;
    const namespace = process.env.NAMESPACE || 'default';
    
    console.log(`Marking pod ${podName} as LRO active in namespace ${namespace}`);
    
    if (!podName) {
        throw new Error('Pod name is null or undefined. POD_NAME and HOSTNAME environment variables are both missing.');
    }
    
    if (!namespace) {
        throw new Error('Namespace is null or undefined.');
    }

    // First, get the current pod to check if annotations exist
    const currentPod = await getPod(podName, namespace);
    const currentAnnotations = currentPod.metadata.annotations || {};
    
    // Prepare the patch
    const patch = {
        metadata: {
            annotations: {
                ...currentAnnotations,
                'app.company.com/lro-active': 'true',
                'app.company.com/lro-started': new Date().toISOString()
            }
        }
    };
    
    const path = `/api/v1/namespaces/${namespace}/pods/${podName}`;
    const response = await makeK8sRequest(path, 'PATCH', patch);
    
    console.log(`Successfully marked pod ${podName} as LRO active`);
    return response;
}

// Unmark pod as having active LRO
async function unmarkPodAsLRO() {
    const podName = process.env.POD_NAME || process.env.HOSTNAME;
    const namespace = process.env.NAMESPACE || 'default';
    
    console.log(`Unmarking pod ${podName} as LRO active in namespace ${namespace}`);
    
    if (!podName) {
        throw new Error('Pod name is null or undefined. POD_NAME and HOSTNAME environment variables are both missing.');
    }
    
    if (!namespace) {
        throw new Error('Namespace is null or undefined.');
    }

    // Get current annotations
    const currentPod = await getPod(podName, namespace);
    const currentAnnotations = currentPod.metadata.annotations || {};
    
    // Remove the LRO annotations
    delete currentAnnotations['app.company.com/lro-active'];
    delete currentAnnotations['app.company.com/lro-started'];
    
    // Prepare the patch
    const patch = {
        metadata: {
            annotations: currentAnnotations
        }
    };
    
    const path = `/api/v1/namespaces/${namespace}/pods/${podName}`;
    const response = await makeK8sRequest(path, 'PATCH', patch);
    
    console.log(`Successfully unmarked pod ${podName} as LRO active`);
    return response;
}

// Alternative implementation using the @kubernetes/client-node library with a workaround
async function markPodAsLROWithLibrary() {
    try {
        const k8s = require('@kubernetes/client-node');
        const kc = new k8s.KubeConfig();
        kc.loadFromCluster();
        
        const podName = process.env.POD_NAME || process.env.HOSTNAME;
        const namespace = process.env.NAMESPACE || 'default';
        
        console.log(`[Library Method] Marking pod ${podName} as LRO active in namespace ${namespace}`);
        
        // Get the raw request options
        const cluster = kc.getCurrentCluster();
        const user = kc.getCurrentUser();
        
        // Create the patch
        const patch = {
            metadata: {
                annotations: {
                    'app.company.com/lro-active': 'true',
                    'app.company.com/lro-started': new Date().toISOString()
                }
            }
        };
        
        // Make a direct HTTP request using the library's configuration
        const https = require('https');
        const opts = {
            ...kc.applyToHTTPSOptions({}),
            hostname: new URL(cluster.server).hostname,
            port: new URL(cluster.server).port || 443,
            path: `/api/v1/namespaces/${namespace}/pods/${podName}`,
            method: 'PATCH',
            headers: {
                'Authorization': `Bearer ${user.token || kc.getCurrentUser().token}`,
                'Content-Type': 'application/strategic-merge-patch+json',
                'Accept': 'application/json'
            }
        };
        
        return new Promise((resolve, reject) => {
            const req = https.request(opts, (res) => {
                let data = '';
                res.on('data', chunk => data += chunk);
                res.on('end', () => {
                    if (res.statusCode >= 200 && res.statusCode < 300) {
                        console.log(`[Library Method] Successfully marked pod ${podName} as LRO active`);
                        resolve(JSON.parse(data));
                    } else {
                        reject(new Error(`Failed: ${res.statusCode} - ${data}`));
                    }
                });
            });
            
            req.on('error', reject);
            req.write(JSON.stringify(patch));
            req.end();
        });
    } catch (error) {
        console.error('[Library Method] Error:', error);
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
    
    // Test if we can read service account credentials
    if (!K8S_TOKEN) {
        console.warn('WARNING: Kubernetes service account token not found. The pod patching will not work.');
        console.warn('Make sure the pod is running with a service account that has the necessary permissions.');
    }
});