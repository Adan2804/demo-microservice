const express = require('express');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;

// Variables de entorno
const APP_VERSION = process.env.APP_VERSION || 'stable';
const EXPERIMENT_ENABLED = process.env.EXPERIMENT_ENABLED === 'true';
const POD_NAME = process.env.HOSTNAME || 'unknown';

app.use(cors());
app.use(express.json());

// Middleware para logging
app.use((req, res, next) => {
    console.log(`${new Date().toISOString()} - ${req.method} ${req.path} - Version: ${APP_VERSION} - Pod: ${POD_NAME}`);
    next();
});

// Health checks
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        version: APP_VERSION,
        pod: POD_NAME,
        timestamp: new Date().toISOString(),
        experimentEnabled: EXPERIMENT_ENABLED
    });
});

app.get('/liveness', (req, res) => {
    res.json({ status: 'alive', version: APP_VERSION });
});

app.get('/readiness', (req, res) => {
    res.json({ status: 'ready', version: APP_VERSION });
});

// Endpoint principal para experimentos
app.get('/api/v1/experiment/version', (req, res) => {
    const experimentHeader = req.headers['aws-cf-cd-super-svp-9f8b7a6d'];
    const isExperimentalTraffic = experimentHeader === '123e4567-e89b-12d3-a456-42661417400';
    
    res.json({
        service: 'demo-microservice',
        version: APP_VERSION,
        pod: POD_NAME,
        timestamp: new Date().toISOString(),
        experimentEnabled: EXPERIMENT_ENABLED,
        experimentHeaderPresent: !!experimentHeader,
        isExperimentalTraffic: isExperimentalTraffic,
        headers: {
            'x-experiment-version': EXPERIMENT_ENABLED ? 'true' : 'false',
            'x-pod-type': EXPERIMENT_ENABLED ? 'experimental' : 'stable'
        }
    });
});

// Endpoint para simular funcionalidad experimental
app.post('/api/v1/experiment/process', (req, res) => {
    const experimentHeader = req.headers['aws-cf-cd-super-svp-9f8b7a6d'];
    const isExperimentalTraffic = experimentHeader === '123e4567-e89b-12d3-a456-42661417400';
    
    // Simular diferentes lógicas según la versión
    if (EXPERIMENT_ENABLED && isExperimentalTraffic) {
        // Lógica experimental
        res.json({
            result: 'processed',
            version: APP_VERSION,
            pod: POD_NAME,
            processingMethod: 'ENHANCED_ALGORITHM',
            features: {
                advancedValidation: true,
                realTimeProcessing: true,
                enhancedSecurity: true
            },
            responseTime: '85ms',
            timestamp: new Date().toISOString()
        });
    } else {
        // Lógica estándar
        res.json({
            result: 'processed',
            version: APP_VERSION,
            pod: POD_NAME,
            processingMethod: 'STANDARD_ALGORITHM',
            features: {
                advancedValidation: false,
                realTimeProcessing: false,
                enhancedSecurity: false
            },
            responseTime: '120ms',
            timestamp: new Date().toISOString()
        });
    }
});

// Endpoint para métricas
app.get('/api/v1/experiment/metrics', (req, res) => {
    const metrics = {
        service: 'demo-microservice',
        version: APP_VERSION,
        pod: POD_NAME,
        timestamp: new Date().toISOString(),
        experimentEnabled: EXPERIMENT_ENABLED,
        metrics: EXPERIMENT_ENABLED ? {
            responseTime: '85ms',
            memoryUsage: '78MB',
            cpuUsage: '12%',
            requestsPerSecond: 145,
            errorRate: '0.2%'
        } : {
            responseTime: '120ms',
            memoryUsage: '65MB',
            cpuUsage: '8%',
            requestsPerSecond: 120,
            errorRate: '0.5%'
        }
    };
    
    res.json(metrics);
});

// Endpoint para generar carga
app.get('/api/v1/load/:duration', (req, res) => {
    const duration = parseInt(req.params.duration) || 1000;
    const start = Date.now();
    
    // Simular trabajo CPU-intensivo
    while (Date.now() - start < duration) {
        Math.random() * Math.random();
    }
    
    res.json({
        message: 'Load test completed',
        duration: `${duration}ms`,
        version: APP_VERSION,
        pod: POD_NAME
    });
});

// Catch all
app.get('*', (req, res) => {
    res.json({
        message: 'Demo Microservice',
        version: APP_VERSION,
        pod: POD_NAME,
        availableEndpoints: [
            'GET /health',
            'GET /api/v1/experiment/version',
            'POST /api/v1/experiment/process',
            'GET /api/v1/experiment/metrics',
            'GET /api/v1/load/:duration'
        ]
    });
});

app.listen(PORT, () => {
    console.log(`Demo microservice running on port ${PORT}`);
    console.log(`Version: ${APP_VERSION}`);
    console.log(`Experiment enabled: ${EXPERIMENT_ENABLED}`);
    console.log(`Pod: ${POD_NAME}`);
});