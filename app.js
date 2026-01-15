/**
 * Data Governance Tool - Main Application
 * Provides APIs for data catalog, lineage tracking, and compliance monitoring
 */

const express = require('express');
const { Pool } = require('pg');
const redis = require('redis');
const morgan = require('morgan');
const helmet = require('helmet');

const app = express();
const PORT = process.env.PORT || 3000;

// Security middleware
app.use(helmet());
app.use(express.json());
app.use(morgan('combined'));

// PostgreSQL Connection Pool
const pgPool = new Pool({
  host: process.env.DB_HOST || 'postgres',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'governance_db',
  user: process.env.DB_USER || 'governance_user',
  password: process.env.DB_PASSWORD || 'secure_password',
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Redis Client Setup
const redisClient = redis.createClient({
  socket: {
    host: process.env.REDIS_HOST || 'redis',
    port: process.env.REDIS_PORT || 6379
  },
  password: process.env.REDIS_PASSWORD || undefined
});

redisClient.on('error', (err) => console.error('Redis Client Error:', err));
redisClient.on('connect', () => console.log('Redis Client Connected'));

// Initialize connections
async function initializeApp() {
  try {
    // Connect to Redis
    await redisClient.connect();
    
    // Test PostgreSQL connection and create tables
    await pgPool.query(`
      CREATE TABLE IF NOT EXISTS data_assets (
        id SERIAL PRIMARY KEY,
        asset_name VARCHAR(255) NOT NULL,
        asset_type VARCHAR(100) NOT NULL,
        owner VARCHAR(100),
        sensitivity_level VARCHAR(50),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    
    console.log('Database tables initialized successfully');
  } catch (err) {
    console.error('Initialization error:', err);
    process.exit(1);
  }
}

// Health check endpoint
app.get('/health', async (req, res) => {
  const health = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    services: {
      database: 'unknown',
      cache: 'unknown'
    }
  };

  try {
    // Check database
    await pgPool.query('SELECT 1');
    health.services.database = 'connected';
  } catch (err) {
    health.services.database = 'disconnected';
    health.status = 'unhealthy';
  }

  try {
    // Check Redis
    await redisClient.ping();
    health.services.cache = 'connected';
  } catch (err) {
    health.services.cache = 'disconnected';
    health.status = 'unhealthy';
  }

  const statusCode = health.status === 'healthy' ? 200 : 503;
  res.status(statusCode).json(health);
});

// Get all data assets with caching
app.get('/api/assets', async (req, res) => {
  try {
    // Check cache first
    const cachedData = await redisClient.get('assets:all');
    
    if (cachedData) {
      console.log('Cache hit for assets');
      return res.json({
        source: 'cache',
        data: JSON.parse(cachedData)
      });
    }

    // Query database
    const result = await pgPool.query(
      'SELECT * FROM data_assets ORDER BY created_at DESC'
    );

    // Cache the result for 5 minutes
    await redisClient.setEx('assets:all', 300, JSON.stringify(result.rows));

    res.json({
      source: 'database',
      data: result.rows
    });
  } catch (err) {
    console.error('Error fetching assets:', err);
    res.status(500).json({ error: 'Failed to fetch assets' });
  }
});

// Create a new data asset
app.post('/api/assets', async (req, res) => {
  const { asset_name, asset_type, owner, sensitivity_level } = req.body;

  // Validation
  if (!asset_name || !asset_type) {
    return res.status(400).json({ 
      error: 'asset_name and asset_type are required' 
    });
  }

  try {
    const result = await pgPool.query(
      `INSERT INTO data_assets (asset_name, asset_type, owner, sensitivity_level)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [asset_name, asset_type, owner, sensitivity_level]
    );

    // Invalidate cache
    await redisClient.del('assets:all');

    res.status(201).json({
      message: 'Asset created successfully',
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error creating asset:', err);
    res.status(500).json({ error: 'Failed to create asset' });
  }
});

// Get asset by ID
app.get('/api/assets/:id', async (req, res) => {
  const { id } = req.params;

  try {
    const cacheKey = `asset:${id}`;
    const cachedData = await redisClient.get(cacheKey);

    if (cachedData) {
      return res.json({
        source: 'cache',
        data: JSON.parse(cachedData)
      });
    }

    const result = await pgPool.query(
      'SELECT * FROM data_assets WHERE id = $1',
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Asset not found' });
    }

    await redisClient.setEx(cacheKey, 300, JSON.stringify(result.rows[0]));

    res.json({
      source: 'database',
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error fetching asset:', err);
    res.status(500).json({ error: 'Failed to fetch asset' });
  }
});

// Compliance metrics endpoint
app.get('/api/metrics', async (req, res) => {
  try {
    const stats = await pgPool.query(`
      SELECT 
        COUNT(*) as total_assets,
        COUNT(DISTINCT asset_type) as asset_types,
        COUNT(CASE WHEN sensitivity_level = 'HIGH' THEN 1 END) as high_sensitivity_assets
      FROM data_assets
    `);

    res.json({
      metrics: stats.rows[0],
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error('Error fetching metrics:', err);
    res.status(500).json({ error: 'Failed to fetch metrics' });
  }
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    service: 'Data Governance Tool',
    version: '1.0.0',
    status: 'running',
    endpoints: {
      health: '/health',
      assets: '/api/assets',
      metrics: '/api/metrics'
    }
  });
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, shutting down gracefully...');
  
  await redisClient.quit();
  await pgPool.end();
  
  process.exit(0);
});

// Start server
initializeApp().then(() => {
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Data Governance Tool running on port ${PORT}`);
  });
});